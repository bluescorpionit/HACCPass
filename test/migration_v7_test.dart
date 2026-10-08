import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/sync_service.dart';

import 'fakes/fake_cloud.dart';

/// Prompt 12, D.2: migrazione v7 con `sync_queue.attachment_id` e
/// scrittura di `cloud_id`/`synced_at` a ogni caricamento.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('mig_v7_test');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('migrazione v6 -> v7: colonna attachment_id presente, dati conservati',
      () async {
    final path = p.join(
      tempDir.path,
      'v6_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final v6 = await openDatabase(
      path,
      version: 6,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('''
          CREATE TABLE sync_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            local_path TEXT NOT NULL,
            remote_folder TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            created_at TEXT NOT NULL
          )
        ''');
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
        await db.insert('sync_queue', {
          'kind': 'pdf',
          'local_path': '/tmp/report.pdf',
          'remote_folder': 'Report',
          'attempts': 0,
          'created_at': DateTime.now().toIso8601String(),
        });
        await db.insert('attachments', {
          'entity_type': 'receipt',
          'entity_id': 1,
          'kind': 'photo',
          'file_name': 'foto.jpg',
          'local_path': '/tmp/foto.jpg',
          'mime': 'image/jpeg',
          'size': 10,
          'created_at': DateTime.now().toIso8601String(),
        });
      },
    );
    await v6.close();

    final migrated = AppDatabase(path: path);
    await migrated.initialize();
    final db = migrated.db;
    expect(await db.getVersion(), 7);
    addTearDown(migrated.close);

    final columns =
        await db.rawQuery('PRAGMA table_info(sync_queue)');
    expect(columns.map((c) => c['name']), contains('attachment_id'),
        reason: 'la colonna attachment_id deve esistere dopo la migrazione');
    final index = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
      ['idx_sync_queue_attachment'],
    );
    expect(index, isNotEmpty);

    final queue = await db.query('sync_queue');
    expect(queue, hasLength(1));
    expect(queue.first['attachment_id'], isNull,
        reason: 'le vecchie voci PDF restano senza allegato');
    final attachments = await db.query('attachments');
    expect(attachments, hasLength(1));
  });

  test('processQueue scrive cloud_id e synced_at sugli allegati caricati',
      () async {
    final dbPath = p.join(
      tempDir.path,
      'sync_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final appDatabase = AppDatabase(path: dbPath);
    await appDatabase.initialize();
    addTearDown(appDatabase.close);
    final repository = HaccpRepository(appDatabase);

    // Due file: un allegato con record e un PDF (senza attachment_id).
    final dir = await tempDir.createTemp('files');
    final foto = File(p.join(dir.path, 'foto_20260101_abc.jpg'))
      ..writeAsStringSync('contenuto foto');
    final pdf = File(p.join(dir.path, 'report.pdf'))..writeAsStringSync('pdf');

    final attachmentId = await repository.addAttachment(Attachment(
      id: 0,
      entityType: 'receipt',
      entityId: 1,
      kind: 'photo',
      fileName: p.basename(foto.path),
      localPath: foto.path,
      mime: 'image/jpeg',
      size: 15,
      createdAt: DateTime.now(),
    ));
    await repository.enqueueSync(
      kind: 'attachment',
      localPath: foto.path,
      remoteFolder: 'Foto',
      attachmentId: attachmentId,
    );
    await repository.enqueueSync(
      kind: 'pdf',
      localPath: pdf.path,
      remoteFolder: 'Report',
    );

    final cloud = FakeCloudProvider();
    final sync = SyncService(repository: repository)..cloud = cloud;
    final uploaded = await sync.processQueue();

    expect(uploaded, 2);
    final rows = await repository.getAllAttachments();
    final restored = rows.singleWhere((a) => a.id == attachmentId);
    expect(restored.cloudId, isNotNull,
        reason: 'l\'upload registra l\'id del file remoto (fix punto 5)');
    expect(restored.syncedAt, isNotNull);
    expect(cloud.uploads, contains(p.basename(foto.path)));
    expect(cloud.uploads, contains(p.basename(pdf.path)));
    expect(await repository.getSyncQueue(), isEmpty);
  });

  test('upload fallito: cloud_id non scritto, voce in coda con errore',
      () async {
    final dbPath = p.join(
      tempDir.path,
      'syncfail_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final appDatabase = AppDatabase(path: dbPath);
    await appDatabase.initialize();
    addTearDown(appDatabase.close);
    final repository = HaccpRepository(appDatabase);

    final dir = await tempDir.createTemp('files');
    final foto = File(p.join(dir.path, 'foto2.jpg'))..writeAsStringSync('x');
    final attachmentId = await repository.addAttachment(Attachment(
      id: 0,
      entityType: 'receipt',
      entityId: 2,
      kind: 'photo',
      fileName: p.basename(foto.path),
      localPath: foto.path,
      mime: 'image/jpeg',
      size: 1,
      createdAt: DateTime.now(),
    ));
    await repository.enqueueSync(
      kind: 'attachment',
      localPath: foto.path,
      remoteFolder: 'Foto',
      attachmentId: attachmentId,
    );

    final cloud = FakeCloudProvider()..uploadError = StateError('boom');
    final sync = SyncService(repository: repository)..cloud = cloud;
    await sync.processQueue();

    final rows = await repository.getAllAttachments();
    expect(rows.single.cloudId, isNull,
        reason: 'nessun riferimento remoto senza upload riuscito');
    expect(rows.single.syncedAt, isNull);
    expect(await repository.getSyncQueue(), hasLength(1),
        reason: 'la voce resta in coda per il retry');
  });

  test('il manifest del backup riporta la versione REALE dello schema',
      () async {
    final dbPath = p.join(
      tempDir.path,
      'manifest_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    final appDatabase = AppDatabase(path: dbPath);
    await appDatabase.initialize();
    addTearDown(appDatabase.close);
    final repository = HaccpRepository(appDatabase);
    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(tempDir.path, 'attachments'),
    );

    final path = await backup.createBackup();
    final handle = await backup.openBackup(path);
    addTearDown(handle.dispose);
    expect(handle.schemaVersion, appDatabaseVersion,
        reason: 'manifest aggiornato alla versione schema corrente');
    expect(appDatabaseVersion, 7);
  });
}
