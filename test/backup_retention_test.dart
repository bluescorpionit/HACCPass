import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';

import 'fakes/fake_cloud.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;
  late BackupService backup;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('retention_test');
  });

  setUp(() async {
    final dbPath =
        '${tempDir.path}/db_${DateTime.now().millisecondsSinceEpoch}.db';
    appDatabase = AppDatabase(path: dbPath);
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
    backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: '${tempDir.path}/attachments',
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// Un "file di backup" locale finto: quel che conta è il nome (tipo e
  /// data) e la dimensione coerente per la verifica post-upload.
  Future<String> localBackup(String name, {int size = 4096}) async {
    final dir = await tempDir.createTemp('local');
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(List.filled(size, 7), flush: true);
    return file.path;
  }

  test('conservazione: ultimi 14 PER TIPO, i file estranei mai toccati',
      () async {
    final cloud = FakeCloudProvider();
    // 16 backup di soli dati + 2 completi + 1 file estraneo.
    for (var i = 0; i < 16; i++) {
      final name = dataBackupName(i);
      await cloud.upload(
        path: await localBackup(name),
        remoteName: name,
        folder: 'Backup',
      );
    }
    for (var i = 0; i < 2; i++) {
      final name = fullBackupName(i);
      await cloud.upload(
        path: await localBackup(name),
        remoteName: name,
        folder: 'Backup',
      );
    }
    const foreign = 'registro_esterno_2026.bhb';
    cloud.backupFiles.add(backupFile(foreign));
    expect(cloud.backupFiles.length, 19);

    final namesBefore =
        cloud.backupFiles.map((f) => f.name).toList(growable: false);

    // Nuovo backup di soli dati: 17 per quel tipo -> 3 eliminati (i più
    // vecchi); i 3 completi restano; l'estraneo resta.
    final newest = 'HACCPass_backup_20261231_2359.bhb';
    await backup.uploadBackup(
      cloud,
      await localBackup(newest),
      onProgress: (_) {},
    );

    expect(cloud.deletions.length, 3,
        reason: '17 backup di soli dati: se ne conservano 14');

    // Ogni eliminazione è un backup di SOLI DATI vecchio, mai un
    // completo, mai il nuovo, mai un file estraneo.
    final dataOnlyNames = [for (var i = 0; i < 16; i++) dataBackupName(i)];
    final eliminated = <String>[];
    for (final id in cloud.deletions) {
      final name = namesBefore.firstWhere((n) => id.contains(n),
          orElse: () => '');
      expect(name, isNotEmpty, reason: 'eliminato un file noto: $id');
      expect(isFullBackupName(name), isFalse,
          reason: 'i tipi si conservano separatamente: $name');
      expect(name, isNot(newest));
      expect(name, isNot(foreign));
      eliminated.add(name);
    }
    // I tre eliminati sono i più VECCHI per data nel nome.
    final sortedOldest = [...dataOnlyNames]..sort();
    expect(eliminated.toSet(), sortedOldest.take(3).toSet());

    expect(cloud.backupFiles.any((f) => f.name == newest), isTrue);
    expect(cloud.backupFiles.any((f) => f.name == foreign), isTrue,
        reason: 'mai eliminare file senza prefisso HACCPass_backup_');
    expect(
      cloud.backupFiles.where((f) => isFullBackupName(f.name)).length,
      2,
      reason: 'i backup completi non vengono eliminati',
    );
    expect(
      cloud.backupFiles
          .where((f) =>
              f.name.startsWith(BackupService.backupPrefix) &&
              !isFullBackupName(f.name))
          .length,
      14,
      reason: '14 backup di soli dati conservati',
    );
  });

  test('nessuna eliminazione se l\'upload non è verificato (dimensione diversa)',
      () async {
    final cloud = FakeCloudProvider();
    for (var i = 0; i < 15; i++) {
      final name = dataBackupName(i);
      await cloud.upload(
        path: await localBackup(name),
        remoteName: name,
        folder: 'Backup',
      );
    }

    // Il prossimo upload dichiara una dimensione SBAGLIATA: il file
    // remoto non corrisponde al locale -> conservazione sospesa.
    cloud.sizeForUpload = (_) => 999999;
    final messages = <String>[];
    await backup.uploadBackup(
      cloud,
      await localBackup('HACCPass_backup_20261231_2359.bhb'),
      onProgress: messages.add,
    );

    expect(cloud.deletions, isEmpty,
        reason: 'senza verifica di integrità non si cancella niente');
    expect(
      messages.any((m) => m.contains('conservazione')),
      isTrue,
      reason: 'avviso non bloccante all\'utente',
    );
  });

  test('errore di eliminazione: avviso, mai bloccante', () async {
    final inner = FakeCloudProvider();
    for (var i = 0; i < 15; i++) {
      final name = dataBackupName(i);
      await inner.upload(
        path: await localBackup(name),
        remoteName: name,
        folder: 'Backup',
      );
    }
    final failing = _FailingDeleteCloud(inner);
    final messages = <String>[];
    await backup.uploadBackup(
      failing,
      await localBackup('HACCPass_backup_20261231_2359.bhb'),
      onProgress: messages.add,
    );
    expect(failing.deleteAttempts, 2,
        reason: '16 backup di soli dati -> 2 eliminazioni tentate');
    expect(messages.any((m) => m.contains('rimossi')), isTrue);
  });
}

/// Provider che registra i tentativi di delete e fallisce sempre.
class _FailingDeleteCloud extends FakeCloudProvider {
  _FailingDeleteCloud(FakeCloudProvider inner) {
    backupFiles = inner.backupFiles;
    connected = inner.connected;
    filesById.addAll(inner.filesById);
  }

  int deleteAttempts = 0;

  @override
  Future<void> delete(String id) async {
    deleteAttempts++;
    throw StateError('delete non riuscita');
  }
}
