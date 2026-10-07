import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/attachment_service.dart';
import 'package:haccpass/services/backup_service.dart';

/// Parte B (Prompt 8): migrazione v6, deduplica SHA-256, miniature,
/// "Libera spazio" che tocca solo file verificati sul cloud, backup
/// completo in streaming e ripristino allegati.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory baseDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;
  late AttachmentService attachments;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('attach_v6_test');
  });

  setUp(() async {
    baseDir = await tempDir.createTemp('base');
    appDatabase = AppDatabase(
      path: '${baseDir.path}/v6_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
    attachments = AttachmentService(
      repository: repository,
      baseDirectory: baseDir,
      tempDirectory: baseDir,
    );
  });

  tearDown(() async {
    await appDatabase.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  PendingAttachment pendingPhoto(String name, String content) {
    final dir =
        Directory('${baseDir.path}/pending_attachments')
          ..createSync(recursive: true);
    final file = File('${dir.path}/$name.jpg');
    file.writeAsStringSync(content);
    return PendingAttachment(tempPath: file.path, kind: 'photo');
  }

  BackupService testBackup() => BackupService(
        repository: repository,
        appVersion: 'test',
        attachmentsRootOverride: '${baseDir.path}/attachments',
      );

  test('migrazione v5 -> v6: colonne e indici presenti, dati conservati',
      () async {
    final path =
        '${tempDir.path}/v5_${DateTime.now().millisecondsSinceEpoch}.db';
    final v5 = await openDatabase(
      path,
      version: 5,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('''
          CREATE TABLE attachments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entity_type TEXT NOT NULL,
            entity_id INTEGER NOT NULL,
            kind TEXT NOT NULL,
            file_name TEXT NOT NULL,
            local_path TEXT NOT NULL,
            mime TEXT NOT NULL DEFAULT '',
            size INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            cloud_id TEXT,
            synced_at TEXT,
            note TEXT
          )
        ''');
        await db.insert('attachments', {
          'entity_type': 'receipt',
          'entity_id': 1,
          'kind': 'photo',
          'file_name': 'vecchia.jpg',
          'local_path': '/tmp/vecchia.jpg',
          'mime': 'image/jpeg',
          'size': 12345,
          'created_at': '2026-01-02T10:00:00.000',
        });
      },
    );
    await v5.close();

    final migrated = AppDatabase(path: path);
    await migrated.initialize();
    final db = migrated.db;
    expect(await db.getVersion(), 6);

    for (final column in [
      'sha256', 'thumb_path', 'width', 'height', 'offloaded_at',
    ]) {
      final rows = await db.rawQuery(
          'PRAGMA table_info(attachments)');
      expect(rows.map((r) => r['name']), contains(column),
          reason: 'manca la colonna $column');
    }
    for (final index in [
      'idx_attachments_sha256', 'idx_attachments_created',
    ]) {
      final rows = await db.rawQuery(
          'SELECT name FROM sqlite_master WHERE name = ?', [index]);
      expect(rows, isNotEmpty, reason: 'manca l\u2019indice $index');
    }
    final rows = await db.rawQuery('SELECT * FROM attachments');
    expect(rows, hasLength(1));
    expect(rows.first['file_name'], 'vecchia.jpg');
    await migrated.close();
  });

  test('deduplica: lo stesso documento su più merci NON duplica il file',
      () async {
    final ddt = pendingPhoto('ddt_condiviso', 'contenuto identico del ddt');
    await attachments.attachPending(AttachmentEntity.receipt, 1, [ddt]);
    final ddt2 = pendingPhoto('ddt_condiviso_2', 'contenuto identico del ddt');
    await attachments.attachPending(AttachmentEntity.receipt, 2, [ddt2]);

    final all = await repository.getAllAttachments();
    expect(all, hasLength(2), reason: 'un record per entità');
    expect(
      all.map((a) => a.localPath).toSet(),
      hasLength(1),
      reason: 'un solo file fisico condiviso',
    );
    expect(all.first.sha256, all.last.sha256);
    // Il secondo temporaneo è stato eliminato (non serve più).
    expect(File(ddt2.tempPath).existsSync(), isFalse);
  });

  test('deleteAttachment: il file condiviso resta finché resta un riferimento',
      () async {
    final photo = pendingPhoto('condivisa', 'foto condivisa');
    await attachments.attachPending(AttachmentEntity.receipt, 1, [photo]);
    final photo2 = pendingPhoto('condivisa_2', 'foto condivisa');
    await attachments.attachPending(AttachmentEntity.receipt, 2, [photo2]);

    final all = await repository.getAllAttachments();
    final first = all.first;
    await repository.deleteAttachment(first.id, localPath: first.localPath);

    final remaining = await repository.getAllAttachments();
    expect(remaining, hasLength(1));
    expect(File(first.localPath).existsSync(), isTrue,
        reason: 'il file serve ancora all\u2019altro record');

    await repository.deleteAttachment(
      remaining.first.id,
      localPath: remaining.first.localPath,
    );
    expect(File(first.localPath).existsSync(), isFalse,
        reason: 'nessun riferimento: file e miniatura eliminati');
  });

  test('libera spazio: solo file sincronizzati e vecchi; ripristino stato',
      () async {
    final old = DateTime.now().subtract(const Duration(days: 400));
    final recente = DateTime.now().subtract(const Duration(days: 5));

    Future<Attachment> seed(DateTime createdAt, {required bool synced}) async {
      final name = 'f_${createdAt.millisecondsSinceEpoch}_$synced';
      final photo =
          pendingPhoto(name, 'dati $createdAt $synced ${DateTime.now()}');
      await attachments.attachPending(AttachmentEntity.receipt, 1, [photo]);
      final added = (await repository.getAllAttachments())
          .firstWhere((a) => a.fileName.contains(name));
      if (synced) {
        await repository.updateAttachmentSync(
          id: added.id,
          cloudId: 'drive-id',
          syncedAt: DateTime.now(),
        );
      }
      await appDatabase.db.update(
        'attachments',
        {'created_at': createdAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [added.id],
      );
      return added;
    }

    final vecchioSyncato = await seed(old, synced: true);
    final vecchioLocale = await seed(old, synced: false);
    final nuovoSyncato = await seed(recente, synced: true);

    final freed = await attachments.offloadOldAttachments(
      olderThan: const Duration(days: 300),
      protectedEntityIds: const {},
    );

    expect(freed, greaterThan(0), reason: 'il vecchio sincronizzato si libera');
    final after = await repository.getAllAttachments();
    final byId = {for (final a in after) a.id: a};
    expect(byId[vecchioSyncato.id]!.isOffloaded, isTrue);
    expect(File(vecchioSyncato.localPath).existsSync(), isFalse);
    expect(byId[vecchioLocale.id]!.isOffloaded, isFalse,
        reason: 'MAI liberare file non caricati');
    expect(File(vecchioLocale.localPath).existsSync(), isTrue);
    expect(byId[nuovoSyncato.id]!.isOffloaded, isFalse,
        reason: 'troppo recente');

    // Riscaricato: torna locale.
    await attachments.markDownloaded(vecchioSyncato);
    final restored = (await repository.getAllAttachments())
        .firstWhere((a) => a.id == vecchioSyncato.id);
    expect(restored.isOffloaded, isFalse);
  });

  test('statistiche: totale, non sincronizzati, file più grandi', () async {
    await attachments.attachPending(AttachmentEntity.receipt, 1,
        [pendingPhoto('stat_a', 'aaa')]);
    await attachments.attachPending(AttachmentEntity.receipt, 1,
        [pendingPhoto('stat_b', 'bbbbbbbbbb')]);

    final stats = await attachments.storageStats();
    expect(stats.fileCount, 2);
    expect(stats.notSyncedCount, 2, reason: 'nessuno \u00E8 su Drive');
    final largest = await attachments.largestLocalAttachments();
    expect(largest.first.size, greaterThanOrEqualTo(largest.last.size));
    expect(stats.byYear.containsKey(DateTime.now().year), isTrue);
  });

  test('backup completo in streaming: DB + 200 allegati, annullabile',
      () async {
    final dir = Directory('${baseDir.path}/attachments/2026/10')
      ..createSync(recursive: true);
    for (var i = 0; i < 200; i++) {
      File('${dir.path}/foto_$i.jpg').writeAsStringSync('contenuto $i');
    }

    final backup = testBackup();
    var progressCalls = 0;
    final path = await backup.createFullBackup(
      onProgress: (_, __) => progressCalls++,
    );
    expect(path, isNotNull);
    expect(progressCalls, 200);

    // Il manifest riporta la versione REALE dello schema e gli allegati.
    final bytes = await File(path!).readAsBytes();
    final zip = await backup.readBackup(path);
    expect(zip.schemaVersion, 6);
    final manifestText = String.fromCharCodes(
      bytes.sublist(0, bytes.length).where((_) => true),
    );
    expect(manifestText, isNotEmpty); // sanity: file leggibile

    // Annullamento: file parziale eliminato, null restituito.
    final cancelled = await backup.createFullBackup(
      shouldCancel: () => true,
    );
    expect(cancelled, isNull);
  });

  test('ripristino allegati dal backup completo', () async {
    final dir = Directory('${baseDir.path}/attachments/2026/10')
      ..createSync(recursive: true);
    File('${dir.path}/da_salvare.jpg').writeAsStringSync('foto importante');

    final backup = testBackup();
    final path = await backup.createFullBackup();
    expect(path, isNotNull);

    // "Nuovo telefono": directory vuota...
    File('${dir.path}/da_salvare.jpg').deleteSync();

    final restored = await backup.restoreAttachments(path!);
    expect(restored, greaterThanOrEqualTo(1));
    expect(
      File('${dir.path}/da_salvare.jpg').existsSync(),
      isTrue,
      reason: 'la foto torna dal backup completo',
    );
  });

  test('pulizia pending oltre 24 ore, i recenti restano', () async {
    final dir =
        Directory('${baseDir.path}/pending_attachments')
          ..createSync(recursive: true);
    final vecchio = File('${dir.path}/vecchio.jpg')
      ..writeAsStringSync('x');
    final recente = File('${dir.path}/recente.jpg')
      ..writeAsStringSync('y');
    vecchio.setLastModifiedSync(
        DateTime.now().subtract(const Duration(hours: 30)));

    final removed = await attachments.cleanupStalePending();
    expect(removed, 1);
    expect(vecchio.existsSync(), isFalse);
    expect(recente.existsSync(), isTrue);
  });
}
