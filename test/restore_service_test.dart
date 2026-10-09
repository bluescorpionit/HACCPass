import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/restore_service.dart';

/// Prompt 12, B/C/D: ripristino robusto (streaming, integrità, backup di
/// sicurezza con rollback), sanificazione impostazioni di licenza e
/// riallineamento percorsi.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('restore_test');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// Crea un "telefono" con il proprio database e la propria cartella
  /// allegati.
  Future<(AppDatabase, HaccpRepository, BackupService, Directory)> phone(
    String name,
  ) async {
    final dir = await tempDir.createTemp(name);
    final db = AppDatabase(path: p.join(dir.path, 'blue_haccp.db'));
    await db.initialize();
    final repository = HaccpRepository(db);
    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(dir.path, 'attachments'),
    );
    return (db, repository, backup, dir);
  }

  test('sanificazione: il ripristino non importa MAI lo stato di licenza',
      () async {
    final (sourceDb, source, sourceBackup, _) = await phone('src');
    final (targetDb, target, targetBackup, _) = await phone('dst');
    addTearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    // Telefono di origine: abbonamento attivo + righe delle vecchie
    // chiavi offline + trial iniziato 10 giorni fa.
    final oldTrial =
        DateTime.now().subtract(const Duration(days: 10)).toIso8601String();
    await source.setSetting('onboarding_done', '1');
    await source.setSetting('company_name', 'Trattoria Drive');
    await source.setSetting('iap_active', '1');
    await source
        .setSetting('iap_verified_at', DateTime.now().toIso8601String());
    await source.setSetting('trial_started_at', oldTrial);
    await source.setSetting('license_kind', 'offline');
    await source.setSetting('license_key', 'BH1-CLIENTE1-20501231-DEADBEEF');
    await source.setSetting('license_expires_at', '2050-01-01T00:00:00.000');
    await source.setSetting('license_customer', 'CLIENTE1');

    // Telefono di destinazione: NESSUNA licenza, prova iniziata ADESSO.
    final localTrial = DateTime.now().toIso8601String();
    await target.setSetting('trial_started_at', localTrial);
    await target.setSetting('license_kind', '');
    await target.setSetting('iap_active', '');

    final backupPath = await sourceBackup.createBackup();
    final restore = RestoreService(repository: target, backup: targetBackup);
    await restore.restoreFromFile(backupPath);

    // Nessuno stato di licenza importato: tutto resta quello del telefono.
    expect(await target.getSetting('iap_active'), '',
        reason: 'mai importare iap_active dal backup');
    expect(await target.getSetting('license_kind'), '',
        reason: 'mai importare license_kind dal backup');
    expect(await target.getSetting('license_key'), '',
        reason: 'mai importare la chiave dal backup');
    // I DATI invece arrivano.
    expect(await target.getSetting('company_name'), 'Trattoria Drive');
    expect(await target.isOnboardingDone(), isTrue);
    // La prova non torna mai indietro: la data effettiva è la più antica
    // tra locale e backup (regola dell'ancora, §C.1).
    final restoredTrial = await target.getSetting('trial_started_at');
    expect(DateTime.parse(restoredTrial).isBefore(DateTime.parse(localTrial)),
        isTrue,
        reason: 'la data della prova del telefono di origine vince');
    expect(restoredTrial, oldTrial);
  });

  test('backup manomesso con licenza a vita: dopo il ripristino nessuno sblocco',
      () async {
    final (sourceDb, source, sourceBackup, _) = await phone('tamper_src');
    final (targetDb, target, targetBackup, _) = await phone('tamper_dst');
    addTearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    await source.setSetting('company_name', 'Attività onesta');
    final backupPath = await sourceBackup.createBackup();

    // Manomissione: righe di licenza modificate DENTRO il file di backup
    // (SQLite non cifrato nello ZIP).
    final tampered = await tamperBackupSettings(
      backupPath,
      {'license_kind': 'offline', 'license_expires_at': '9999-12-31'},
    );

    final restore = RestoreService(repository: target, backup: targetBackup);
    await restore.restoreFromFile(tampered);

    // Il telefono non aveva licenza: il manomettere il backup non sblocca
    // nulla. Le impostazioni locali (vuote) restano.
    expect(await target.getSetting('license_kind'), '');
    expect(await target.getSetting('license_expires_at'), '');
    expect(await target.getSetting('company_name'), 'Attività onesta');
  });

  test(
      'riallineamento percorsi: Android→Android, Android→iOS e percorso senza attachments',
      () async {
    final (sourceDb, source, sourceBackup, sourceDir) =
        await phone('paths_src');
    final (targetDb, target, targetBackup, targetDir) =
        await phone('paths_dst');
    addTearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    final sourceRoot = p.join(sourceDir.path, 'attachments');
    final targetRoot = p.join(targetDir.path, 'attachments');

    // Allegati con percorsi assoluti del telefono di origine, in stile
    // Android e in stile iOS.
    await sourceDb.db.insert('attachments', {
      'entity_type': 'receipt',
      'entity_id': 1,
      'kind': 'photo',
      'file_name': 'a.jpg',
      'local_path':
          '/data/user/0/it.bluescorpion.haccpass/app_flutter/attachments/2026/03/a.jpg',
      'thumb_path':
          '/data/user/0/it.bluescorpion.haccpass/app_flutter/attachments/2026/03/a_thumb.jpg',
      'mime': 'image/jpeg',
      'size': 100,
      'created_at': DateTime.now().toIso8601String(),
    });
    await sourceDb.db.insert('attachments', {
      'entity_type': 'receipt',
      'entity_id': 2,
      'kind': 'photo',
      'file_name': 'b.jpg',
      'local_path':
          '/var/mobile/Containers/Data/Application/UUID/Documents/attachments/2026/03/b.jpg',
      'mime': 'image/jpeg',
      'size': 100,
      'created_at': DateTime.now().toIso8601String(),
    });
    await sourceDb.db.insert('attachments', {
      'entity_type': 'receipt',
      'entity_id': 3,
      'kind': 'document',
      'file_name': 'legacy.pdf',
      'local_path': '/sdcard/Download/legacy.pdf',
      'mime': 'application/pdf',
      'size': 50,
      'created_at': DateTime.now().toIso8601String(),
    });
    await source.enqueueSync(
      kind: 'attachment',
      localPath:
          '/data/user/0/it.bluescorpion.haccpass/app_flutter/attachments/2026/03/a.jpg',
      remoteFolder: 'Foto',
      attachmentId: 1,
    );

    final backupPath = await sourceBackup.createBackup();
    final restore = RestoreService(repository: target, backup: targetBackup);
    final result = await restore.restoreFromFile(backupPath);

    final rows = await targetDb.db.query('attachments');
    final byName = {for (final r in rows) r['file_name'] as String: r};

    // Android -> qualunque telefono: ricostruito sulla radice attuale.
    expect(byName['a.jpg']!['local_path'],
        p.join(targetRoot, '2026', '03', 'a.jpg'));
    expect(byName['a.jpg']!['thumb_path'],
        p.join(targetRoot, '2026', '03', 'a_thumb.jpg'));
    // iOS -> telefono nuovo: idem (separatori e contenitore diversi).
    expect(byName['b.jpg']!['local_path'],
        p.join(targetRoot, '2026', '03', 'b.jpg'));
    // Percorso senza cartella attachments: riga lasciata com'è e
    // segnalata "da recuperare".
    expect(byName['legacy.pdf']!['local_path'], '/sdcard/Download/legacy.pdf');
    expect(result.realignment.unrecoverable, 1,
        reason: 'il percorso senza attachments resta da recuperare');
    expect(result.realignment.realignedAttachments, 2);

    // Anche la coda di sincronizzazione viene riallineata.
    final queue = await target.getSyncQueue();
    expect(queue.single['local_path'],
        p.join(targetRoot, '2026', '03', 'a.jpg'));

    // La radice di ORIGINE non è la stessa della destinazione.
    expect(sourceRoot, isNot(targetRoot));
  });

  test('backup completo: allegati ripristinati dal file, streaming senza picchi',
      () async {
    final (sourceDb, source, sourceBackup, sourceDir) = await phone('full_src');
    final (targetDb, target, targetBackup, _) = await phone('full_dst');
    addTearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    // Un allegato "grande" (finto) + il suo record con percorso assoluto.
    final fotoDir = await Directory(
      p.join(sourceDir.path, 'attachments', '2026', '05'),
    ).create(recursive: true);
    final big = File(p.join(fotoDir.path, 'grande.jpg'));
    await big.writeAsBytes(List.filled(3 * 1024 * 1024, 1), flush: true);
    await sourceDb.db.insert('attachments', {
      'entity_type': 'receipt',
      'entity_id': 1,
      'kind': 'photo',
      'file_name': 'grande.jpg',
      'local_path': big.path,
      'mime': 'image/jpeg',
      'size': await big.length(),
      'created_at': DateTime.now().toIso8601String(),
    });
    await source.setSetting('company_name', 'Con foto');

    final backupPath = await sourceBackup.createFullBackup();
    expect(backupPath, isNotNull);

    final restore = RestoreService(repository: target, backup: targetBackup);
    final result = await restore.restoreFromFile(backupPath!);

    expect(result.attachmentsRestored, 1);
    final targetRoot = await targetBackup.attachmentsRootPath();
    final restored = File(p.join(targetRoot, '2026', '05', 'grande.jpg'));
    expect(await restored.exists(), isTrue);
    expect(await restored.length(), 3 * 1024 * 1024);
    expect(await target.getSetting('company_name'), 'Con foto');
  });

  test('fallimento dopo la sostituzione del DB: rollback col backup di sicurezza',
      () async {
    final (sourceDb, source, sourceBackup, sourceDir) = await phone('rb_src');
    final (targetDb, target, _, targetDir) = await phone('rb_dst');
    addTearDown(() async {
      await sourceDb.close();
      await targetDb.close();
    });

    final fotoDir = await Directory(
      p.join(sourceDir.path, 'attachments', '2026', '05'),
    ).create(recursive: true);
    File(p.join(fotoDir.path, 'una.jpg')).writeAsStringSync('x');
    await source.setSetting('company_name', 'Sorgente con foto');
    final backupPath = await sourceBackup.createFullBackup();

    // Destinazione con dati propri: devono tornare dopo il rollback.
    await target.setSetting('company_name', 'Dati locali importanti');

    // Radice allegati della destinazione resa NON scrivibile: il
    // ripristino degli allegati fallisce DOPO la sostituzione del DB.
    final blocker = File(p.join(targetDir.path, 'attachments'));
    blocker.writeAsStringSync('non una cartella');

    final failingBackup = BackupService(
      repository: target,
      appVersion: 'test',
      attachmentsRootOverride: blocker.path,
    );
    final restore =
        RestoreService(repository: target, backup: failingBackup);

    await expectLater(
      restore.restoreFromFile(backupPath!),
      throwsA(isA<FileSystemException>()
          .having((e) => e.osError?.errorCode ?? 1, 'errorCode', isNotNull)),
    );

    // Rollback automatico: i dati locali sono intatti.
    expect(await target.getSetting('company_name'), 'Dati locali importanti',
        reason: 'il backup di sicurezza ha riportato lo stato precedente');
  });
}

/// Manomette le impostazioni dentro un file di backup: apre lo ZIP,
/// modifica le righe del database e riscrive il file (simula l'attacco
/// "licenza gratis" descritto nel Prompt 12, punto 2).
Future<String> tamperBackupSettings(
  String backupPath,
  Map<String, String> settings,
) async {
  final bytes = await File(backupPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  final dbEntry = archive.find('blue_haccp.db')!;
  final tempDir = await Directory.systemTemp.createTemp('tamper');
  final dbFile = File(p.join(tempDir.path, 'db.sqlite'));
  await dbFile.writeAsBytes(List<int>.from(dbEntry.content as List<int>));

  final db = await openDatabase(dbFile.path);
  for (final entry in settings.entries) {
    await db.insert('settings', {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
  await db.close();

  final newArchive = Archive()
    ..addFile(ArchiveFile(
      'blue_haccp.db',
      await dbFile.length(),
      await dbFile.readAsBytes(),
    ))
    ..addFile(archive.find('manifest.json')!);
  final tampered = p.join(tempDir.path, 'tampered.bhb');
  await File(tampered).writeAsBytes(ZipEncoder().encode(newArchive));
  return tampered;
}
