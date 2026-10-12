import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';

import 'fixtures/v7_database.dart';

/// Prompt 19, §0: aggiornamento di un'installazione reale dalla
/// versione pubblicata (v7) alla v8 (stati del lotto).
///
/// (a) i dati restano identici, (b) i lotti diventano `active`,
/// (c) tracciabilità e avvisi funzionano, (d) la migrazione è
/// idempotente, (e) copia di sicurezza prima di migrare,
/// (f) ripristino di un backup creato dalla versione pubblicata.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('mig_v8_test');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('v7 -> v8: dati identici, lotti active, copia di sicurezza',
      () async {
    final dir = await tempDir.createTemp('upgrade');
    final path = await buildPublishedV7Database(dir);

    final appDatabase = AppDatabase(path: path);
    await appDatabase.initialize();
    addTearDown(appDatabase.close);
    final db = appDatabase.db;

    // Versione alzata, colonne additive presenti.
    expect(await db.getVersion(), 8);
    final columns = await db.rawQuery('PRAGMA table_info(lots)');
    final names = columns.map((c) => c['name']).toSet();
    expect(names, containsAll([
      'status', 'closed_at', 'withdrawn_reason',
      'closing_note', 'withdrawn_quantity', 'closed_by',
    ]));
    // Le colonne storiche sono intatte (nessun DROP/RENAME).
    expect(names, containsAll([
      'code', 'product_name', 'product_id', 'produced_at', 'expires_at',
      'quantity', 'unit', 'storage_info', 'operator_name', 'notes',
      'allergens',
    ]));

    // (a) Dati identici: stessi lotti, stesse note, stessi ingredienti.
    final lots = await db.query('lots', orderBy: 'id');
    expect(lots, hasLength(3));
    final byCode = {for (final l in lots) l['code'] as String: l};
    expect(byCode['L260101-PIZ-1000']!['notes'], 'lotto di prova attivo');
    expect(byCode['L260101-PIZ-0900']!['notes'],
        'lotto di prova scaduto mai chiuso');
    final ingredients = await db.query('lot_ingredients');
    expect(ingredients, hasLength(2));
    final receipts = await db.query('receipts');
    expect(receipts, hasLength(1));
    expect(receipts.first['supplier_lot'], 'FORN-001');

    // (b) Tutti i lotti esistenti diventano active: nessuno cambia
    // stato da solo, nessuna riga cancellata.
    for (final l in lots) {
      expect(l['status'], 'active',
          reason: 'il lotto ${l['code']} deve restare attivo');
    }

    // (c) Tracciabilità e avvisi funzionano sul database migrato.
    final repository = HaccpRepository(appDatabase);
    final traceability = await repository.searchTraceability('FORN-001');
    expect(traceability.lots, hasLength(2),
        reason: 'i lotti collegati al ricevimento si trovano');
    final dashboard = await repository.getDashboard();
    final lotTodos =
        dashboard.todos.where((t) => t.target.startsWith('lots'));
    expect(lotTodos, isNotEmpty,
        reason: 'il lotto scaduto attivo genera ancora l\u2019avviso');
    final parsed = repository.getLots();
    expect((await parsed).where((l) => l.isExpired), hasLength(2));

    // (e) Copia di sicurezza creata prima di migrare.
    final bak = File('$path.pre_v8.bak');
    expect(await bak.exists(), isTrue,
        reason: 'copiare il DB prima di applicare la migrazione');
  });

  test('migrazione idempotente: riaprire due volte non cambia nulla',
      () async {
    final dir = await tempDir.createTemp('idempotent');
    final path = await buildPublishedV7Database(dir);

    final first = AppDatabase(path: path);
    await first.initialize();
    await first.close();
    final afterFirst = await _snapshot(path);

    final second = AppDatabase(path: path);
    await second.initialize();
    await second.close();
    final afterSecond = await _snapshot(path);

    expect(afterSecond, afterFirst,
        reason: 'la seconda apertura non modifica alcun dato');
    expect(afterSecond['version'], 8);
  });

  test('il ripristino di un backup della versione pubblicata funziona',
      () async {
    // Backup .bhb "della versione pubblicata": database v7 (senza le
    // colonne degli stati) e manifest con schemaVersion 7.
    final sourceDir = await tempDir.createTemp('oldbackup_src');
    final v7Path = await buildPublishedV7Database(sourceDir);
    final backupFile = await _craftBackup(tempDir, v7Path,
        schemaVersion: 7, appVersion: '1.0.1+2');

    // Database corrente (vuoto, v8).
    final target = AppDatabase(
        path: p.join((await tempDir.createTemp('oldbackup_dst')).path,
            'blue_haccp.db'));
    await target.initialize();
    addTearDown(target.close);
    final repository = HaccpRepository(target);
    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(tempDir.path, 'attachments'),
    );

    final result = await backup.openBackup(backupFile.path);
    expect(result.schemaVersion, 7);
    await result.dispose();

    // Ripristino vero e proprio: sostituisce il DB e lo riapre; la
    // migrazione v8 gira alla riapertura.
    final restored = await _restoreDirect(target, backupFile.path);
    expect(restored, isTrue);

    final lots = await repository.getLots();
    expect(lots, hasLength(3));
    for (final lot in lots) {
      expect(lot.isActive, isTrue,
          reason: 'i lotti del backup vecchio risultano active');
      expect(lot.status, LotStatus.active);
    }
    // Nessun errore: colonne assenti nel backup => default 'active'.
    expect(target.migrationFailed, isFalse);
  });

  test('backup con schemaVersion più recente: messaggio chiaro, no crash',
      () async {
    final sourceDir = await tempDir.createTemp('future_src');
    final v7Path = await buildPublishedV7Database(sourceDir);
    final backupFile = await _craftBackup(sourceDir, v7Path,
        schemaVersion: 99, appVersion: '9.9.9');

    final target = AppDatabase(
        path: p.join((await tempDir.createTemp('future_dst')).path,
            'blue_haccp.db'));
    await target.initialize();
    addTearDown(target.close);
    final repository = HaccpRepository(target);
    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(tempDir.path, 'attachments'),
    );

    expect(
      () => backup.openBackup(backupFile.path),
      throwsA(isA<BackupException>().having(
        (e) => e.message,
        'message',
        contains('versione più recente'),
      )),
      reason:
          'mai crash né perdita silenziosa: messaggio chiaro con invito '
          'ad aggiornare l\u2019app',
    );
  });

  test('backup creato dalla versione nuova: ripristino conserva stati',
      () async {
    final dir = await tempDir.createTemp('newbackup');
    final appDatabase = AppDatabase(
        path: p.join(dir.path, 'blue_haccp.db'));
    await appDatabase.initialize();
    addTearDown(appDatabase.close);
    final repository = HaccpRepository(appDatabase);

    final operator = 'Rossi';
    final activeId = await repository.createLot(ProductionLot(
      id: 0,
      code: 'NEW-A1',
      productName: 'Attivo',
      producedAt: DateTime.now(),
      operatorName: operator,
    ));
    final finishedId = await repository.createLot(ProductionLot(
      id: 0,
      code: 'NEW-F1',
      productName: 'Terminato',
      producedAt: DateTime.now(),
      operatorName: operator,
    ));
    await repository.finishLot(finishedId, note: 'venduto tutto',
        operatorName: operator);
    final withdrawnId = await repository.createLot(ProductionLot(
      id: 0,
      code: 'NEW-W1',
      productName: 'Ritirato',
      producedAt: DateTime.now(),
      operatorName: operator,
    ));
    await repository.withdrawLot(
      id: withdrawnId,
      reason: LotWithdrawalReason.recall,
      note: 'richiamo fornitore',
      quantity: '2 kg',
      operatorName: operator,
    );

    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(dir.path, 'attachments'),
    );
    final backupPath = await backup.createBackup();

    // Ripristina su un database nuovo.
    final targetDir = await tempDir.createTemp('newbackup_target');
    final target = AppDatabase(
        path: p.join(targetDir.path, 'blue_haccp.db'));
    await target.initialize();
    addTearDown(target.close);
    final targetRepository = HaccpRepository(target);
    final targetBackup = BackupService(
      repository: targetRepository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(targetDir.path, 'attachments'),
    );

    final handle = await targetBackup.openBackup(backupPath);
    expect(handle.schemaVersion, appDatabaseVersion);
    await handle.dispose();
    final ok = await _restoreDirect(target, backupPath);
    expect(ok, isTrue);

    final lots = await targetRepository.getLots();
    final byCode = {for (final l in lots) l.code: l};
    expect(byCode['NEW-A1']!.isActive, isTrue);
    final finished = byCode['NEW-F1']!;
    expect(finished.isFinished, isTrue);
    expect(finished.closedAt, isNotNull);
    expect(finished.closingNote, 'venduto tutto');
    final withdrawn = byCode['NEW-W1']!;
    expect(withdrawn.isWithdrawn, isTrue);
    expect(withdrawn.withdrawnReason, LotWithdrawalReason.recall);
    expect(withdrawn.withdrawnQuantity, '2 kg');
    expect(withdrawn.closedBy, operator);
    expect(activeId, greaterThan(0));
  });
}

/// Fotografia del database: versione + righe di tutte le tabelle.
Future<Map<String, Object>> _snapshot(String path) async {
  final db = await openDatabase(path, readOnly: true, singleInstance: false);
  try {
    final result = <String, Object>{
      'version': await db.getVersion(),
    };
    for (final table in [
      'suppliers', 'receipts', 'products', 'lots', 'lot_ingredients',
      'non_conformities',
    ]) {
      final rows = await db.query(table, orderBy: 'id');
      result[table] = rows;
    }
    // `settings` non ha la colonna id: ordina per chiave.
    result['settings'] = await db.query('settings', orderBy: 'key');
    return result;
  } finally {
    await db.close();
  }
}

/// Crea un file .bhb (ZIP con blue_haccp.db + manifest.json) come lo
/// creava la versione pubblicata.
Future<File> _craftBackup(
  Directory dir,
  String dbPath, {
  required int schemaVersion,
  required String appVersion,
}) async {
  final archive = Archive()
    ..addFile(ArchiveFile(
      'blue_haccp.db',
      await File(dbPath).length(),
      await File(dbPath).readAsBytes(),
    ));
  final manifest =
      utf8.encode(jsonEncode({
    'format': 'BHB2',
    'schemaVersion': schemaVersion,
    'appVersion': appVersion,
    'createdAt': DateTime.now().toIso8601String(),
    'encrypted': false,
  }));
  archive.addFile(ArchiveFile('manifest.json', manifest.length, manifest));
  final out = File(p.join(dir.path,
      'HACCPass_backup_test_${DateTime.now().millisecondsSinceEpoch}.bhb'));
  final bytes = ZipEncoder().encode(archive);
  await out.writeAsBytes(bytes, flush: true);
  return out;
}

/// Sostituisce il database dell'[appDatabase] con il contenuto del
/// backup (come RestoreService._replaceDatabase) e lo riapre.
Future<bool> _restoreDirect(AppDatabase appDatabase, String backupPath) async {
  final handle = await BackupService(
    repository: HaccpRepository(appDatabase),
    appVersion: 'test',
  ).openBackup(backupPath);
  try {
    await appDatabase.close();
    await File(handle.dbPath).copy(appDatabase.path);
    await appDatabase.initialize();
    return true;
  } finally {
    await handle.dispose();
  }
}
