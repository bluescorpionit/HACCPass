import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/license/trial_anchor.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_envelope.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/restore_service.dart';

/// Storage in memoria dell'ancora (simula file Android / Keychain iOS).
class MemAnchor implements TrialAnchorStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> clear() async => value = null;
}

/// Sorgente (crea il backup) e destinazione (ripristina) di uno
/// scenario del Prompt 20, con le rispettive ancore in memoria.
class _Prompt20Pair {
  _Prompt20Pair(
    this.backupPath,
    this.source,
    this.target,
    this.targetAnchor,
    this.sourceTrialStart,
    this.localTrialStart,
  );

  final String backupPath;
  final HaccpRepository source;
  final HaccpRepository target;
  final TrialAnchorStorage targetAnchor;

  /// Istante esatto scritto come inizio prova nella sorgente.
  final DateTime sourceTrialStart;

  /// Istante esatto scritto come inizio prova nel telefono locale.
  final DateTime localTrialStart;
}

/// Prompt 12, B/C/D: ripristino robusto (streaming, integrità, backup di
/// sicurezza con rollback), sanificazione impostazioni di licenza e
/// riallineamento percorsi. Prompt 20: ancora firmata nel manifest e
/// involucro cifrato dell'app (HPBK1).
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

  /// Telefono con ancora iniettabile (per firmare/verificare).
  Future<
      (
        AppDatabase,
        HaccpRepository,
        BackupService,
        Directory,
        TrialAnchorStorage
      )> anchorPhone(String name, String secret) async {
    final dir = await tempDir.createTemp(name);
    final db = AppDatabase(path: p.join(dir.path, 'blue_haccp.db'));
    await db.initialize();
    final repository = HaccpRepository(db);
    final storage = MemAnchor();
    final anchor = TrialAnchor(secret: secret, storage: storage);
    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: p.join(dir.path, 'attachments'),
      trialAnchor: anchor,
    );
    return (db, repository, backup, dir, storage);
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

  group('ancora firmata nel backup e involucro HPBK1 (Prompt 20)', () {
    const secret = 'test-secret-123';

    Future<_Prompt20Pair> scenario(
      String name, {
      required Duration sourceTrial,
      required Duration localTrial,
    }) async {
      final (sourceDb, source, sourceBackup, _, _) =
          await anchorPhone('${name}_src', secret);
      final (targetDb, target, targetBackup, _, targetAnchor) =
          await anchorPhone('${name}_dst', secret);
      addTearDown(() async {
        await sourceDb.close();
        await targetDb.close();
      });

      // Istanti catturati UNA volta: i confronti del test usano questi.
      final now = DateTime.now();
      final sourceTrialStart = now.subtract(sourceTrial);
      final localTrialStart = now.subtract(localTrial);

      await source.setSetting(
        'trial_started_at',
        sourceTrialStart.toIso8601String(),
      );
      await source.setSetting('company_name', 'Attivita di prova');
      await source.setSetting('iap_active', '1');

      await target.setSetting(
        'trial_started_at',
        localTrialStart.toIso8601String(),
      );
      await target.setSetting('license_kind', '');
      await target.setSetting('iap_active', '');

      final path = await sourceBackup.createBackup();
      return _Prompt20Pair(
        path,
        source,
        target,
        targetAnchor,
        sourceTrialStart,
        localTrialStart,
      );
    }

    RestoreService restoreFor(_Prompt20Pair pair, {String? secretOverride}) =>
        RestoreService(
          repository: pair.target,
          backup: BackupService(
            repository: pair.target,
            appVersion: 'test',
            attachmentsRootOverride: p.join(
              p.dirname(pair.target.database.path),
              'attachments',
            ),
          ),
          trialAnchor: TrialAnchor(
            secret: secretOverride ?? secret,
            storage: pair.targetAnchor,
          ),
        );

    test('il backup nuovo contiene l\'ancora firmata e la versione 1',
        () async {
      final pair = await scenario(
        'manifest',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(days: 1),
      );
      final sourceTrial = DateTime.parse(
        await pair.source.getSetting('trial_started_at'),
      );

      final handle = await BackupService(
        repository: pair.target,
        appVersion: 'test',
      ).openBackup(pair.backupPath);
      addTearDown(handle.dispose);

      expect(handle.trialAnchorVersion, 1);
      final anchorText = handle.trialAnchor;
      expect(anchorText, isNotNull);
      final parsed = TrialAnchor(secret: secret).parseSigned(anchorText!);
      expect(parsed, isNotNull,
          reason: 'l\'ancora nel manifest e\' firmata e verificabile');
      expect(parsed!.$1.isAtSameMomentAs(sourceTrial), isTrue,
          reason: 'la data firmata e\' quella effettiva della prova');
      // Il campo contiene solo le due date e la firma: niente altro.
      final map = jsonDecode(anchorText) as Map<String, dynamic>;
      expect(map.keys.toSet(), {'v', 'start', 'lastSeen', 'mac'});
    });

    test('reinstallazione: la data ripristinata e\' quella dell\'ancora '
        '(la piu\' antica) e l\'ancora locale viene riallineata', () async {
      final pair = await scenario(
        'older_anchor',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(), // reinstallazione: prova appena nata
      );
      final t0 = pair.sourceTrialStart;

      final result = await restoreFor(pair).restoreFromFile(pair.backupPath);

      expect(result.trialAnchorSuspect, isFalse);
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(t0), isTrue,
          reason: 'la data originale (piu\' antica) vince sulla locale');
      // I dati arrivano e la licenza resta del telefono.
      expect(await pair.target.getSetting('company_name'), 'Attivita di prova');
      expect(await pair.target.getSetting('iap_active'), '',
          reason: 'mai importare lo stato di abbonamento dal backup');
      // L'ancora della piattaforma e\' riallineata alla data effettiva.
      final stored = await pair.targetAnchor.read();
      expect(stored, isNotNull);
      final realigned =
          TrialAnchor(secret: secret).parseSigned(stored!);
      expect(realigned, isNotNull);
      expect(realigned!.$1.isAtSameMomentAs(t0), isTrue);
    });

    test('ancora piu\' recente della locale: resta la locale', () async {
      final pair = await scenario(
        'newer_anchor',
        sourceTrial: const Duration(days: 3),
        localTrial: const Duration(days: 8),
      );
      await restoreFor(pair).restoreFromFile(pair.backupPath);

      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(
        restored.isAtSameMomentAs(pair.localTrialStart),
        isTrue,
        reason: 'la data non viene MAI spostata in avanti: resta la locale '
            '(piu\' antica), nonostante l\'ancora del backup sia piu\' recente',
      );
    });

    test('ancora rimossa dal backup nuovo: alterata, nessun giorno in piu\'',
        () async {
      final pair = await scenario(
        'removed_anchor',
        sourceTrial: const Duration(days: 13),
        localTrial: const Duration(days: 11),
      );
      final tampered = await rewriteManifest(
        pair.backupPath,
        (m) => m..remove('trialAnchor'),
      );

      final result =
          await restoreFor(pair).restoreFromFile(tampered);

      expect(result.trialAnchorSuspect, isTrue);
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(pair.localTrialStart), isTrue,
          reason: 'resta SOLO la data del telefono: nessuna data dal backup, '
              'anche se il suo database aveva una data piu\' antica');
      // I dati si ripristinano comunque.
      expect(await pair.target.getSetting('company_name'), 'Attivita di prova');
      expect(await pair.target.getSetting('iap_active'), '');
    });

    test('firma modificata: come rimossa (alterata)', () async {
      final pair = await scenario(
        'badmac_anchor',
        sourceTrial: const Duration(days: 12),
        localTrial: const Duration(days: 5),
      );
      final tampered = await rewriteManifest(pair.backupPath, (m) {
        final map =
            jsonDecode(m['trialAnchor'] as String) as Map<String, dynamic>;
        map['start'] =
            DateTime.now().add(const Duration(days: 30)).toIso8601String();
        return {...m, 'trialAnchor': jsonEncode(map)};
      });

      final result =
          await restoreFor(pair).restoreFromFile(tampered);

      expect(result.trialAnchorSuspect, isTrue);
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(pair.localTrialStart), isTrue,
          reason: 'la data inventata col MAC rotto non viene creduta');
    });

    test('data del database rimossa ma ancora valida: vince l\'ancora',
        () async {
      final pair = await scenario(
        'removed_db_date',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(days: 2),
      );
      // L'attacco classico: trial_started_at cancellato DENTRO il
      // database del backup, ancora firmata lasciata intatta.
      final tampered =
          await tamperBackupSettings(pair.backupPath, {'trial_started_at': ''});

      final result =
          await restoreFor(pair).restoreFromFile(tampered);

      expect(result.trialAnchorSuspect, isFalse);
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(pair.sourceTrialStart), isTrue,
          reason: 'l\'ancora firmata copre la data cancellata nel database');
    });

    test('backup vecchio (senza campi ancora): comportamento attuale',
        () async {
      final pair = await scenario(
        'old_backup',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(), // reinstallazione: prova appena nata
      );
      // Simula un backup della versione pubblicata: nessun campo ancora.
      final oldStyle = await rewriteManifest(
        pair.backupPath,
        (m) => m
          ..remove('trialAnchor')
          ..remove('trialAnchorVersion'),
      );

      final result = await restoreFor(pair).restoreFromFile(oldStyle);

      expect(result.trialAnchorSuspect, isFalse);
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(pair.sourceTrialStart), isTrue,
          reason: 'regola storica: la piu\' antica tra locale e database '
              'del backup');
    });

    test('segreto vuoto (debug): nessun controllo, comportamento attuale',
        () async {
      final pair = await scenario(
        'empty_secret',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(),
      );
      // Ancora presente ma garbage: col segreto vuoto non si puo\'
      // verificare e il flusso resta quello storico.
      final garbage = await rewriteManifest(
        pair.backupPath,
        (m) => {...m, 'trialAnchor': 'non-json'},
      );

      final result = await restoreFor(
        pair,
        secretOverride: '',
      ).restoreFromFile(garbage);

      expect(result.trialAnchorSuspect, isFalse,
          reason: 'debug: nessuna verifica, nessun sospetto');
      final restored = DateTime.parse(
        await pair.target.getSetting('trial_started_at'),
      );
      expect(restored.isAtSameMomentAs(pair.sourceTrialStart), isTrue,
          reason: 'comportamento attuale: data del database del backup');
    });

    test('parser che ignora i campi nuovi: nessun errore (vecchie app)',
        () async {
      final pair = await scenario(
        'old_parser',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(days: 1),
      );
      final inner = await unwrapBackupZip(pair.backupPath);
      final archive = ZipDecoder().decodeBytes(inner);
      final manifest = BackupService.parseManifest(
        archive.find('manifest.json')!.content as List<int>,
      );
      expect(manifest['trialAnchor'], isNotNull);

      // Il lettore della versione pubblicata legge solo le chiavi note:
      // i campi sconosciuti sono innocui e non fanno fallire nulla.
      final oldParserView = {...manifest}
        ..remove('trialAnchor')
        ..remove('trialAnchorVersion');
      final reparsed = BackupService.parseManifest(
        utf8.encode(jsonEncode(oldParserView)),
      );
      expect(reparsed['schemaVersion'], manifest['schemaVersion']);
    });

    test('involucro: byte alterato -> errore pulito, dati non toccati',
        () async {
      final pair = await scenario(
        'tampered_envelope',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(days: 1),
      );
      await pair.target.setSetting('company_name', 'Dati locali');

      final bytes = await File(pair.backupPath).readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0xFF;
      final tamperedFile = File(
        '${p.dirname(pair.backupPath)}/tampered_envelope.bhb',
      );
      await tamperedFile.writeAsBytes(bytes, flush: true);

      await expectLater(
        restoreFor(pair).restoreFromFile(tamperedFile.path),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('alterato o danneggiato'),
        )),
      );
      expect(await pair.target.getSetting('company_name'), 'Dati locali',
          reason: 'nessun dato modificato da un file manomesso');
    });

    test('involucro: keyId sconosciuto -> invito ad aggiornare l\'app',
        () async {
      final pair = await scenario(
        'future_key',
        sourceTrial: const Duration(days: 10),
        localTrial: const Duration(days: 1),
      );
      final bytes = await File(pair.backupPath).readAsBytes();
      bytes[5] = 99; // keyId del futuro
      final futureFile = File('${p.dirname(pair.backupPath)}/future_key.bhb');
      await futureFile.writeAsBytes(bytes, flush: true);

      await expectLater(
        restoreFor(pair).restoreFromFile(futureFile.path),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          allOf(contains('aggiorna'), contains('versione pi\u00F9 recente')),
        )),
      );
    });

    test('backup con password: doppio strato (password dentro, involucro '
        'fuori)', () async {
      final (sourceDb, source, sourceBackup, _) = await phone('double_src');
      final (targetDb, target, targetBackup, _) = await phone('double_dst');
      addTearDown(() async {
        await sourceDb.close();
        await targetDb.close();
      });
      await source.setSetting(
        'trial_started_at',
        DateTime.now().subtract(const Duration(days: 5)).toIso8601String(),
      );
      await source.setSetting('company_name', 'Con password');
      await target.setSetting('company_name', '');

      final path = await sourceBackup.createBackup(password: 'segretissima');
      expect(
        String.fromCharCodes((await File(path).readAsBytes()).take(5)),
        'HPBK1',
        reason: 'l\'involucro dell\'app e\' SEMPRE il layer piu\' esterno',
      );

      // Senza password: la chiede (lo strato interno e\' intatto).
      await expectLater(
        targetBackup.openBackup(path),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('password'),
        )),
      );

      final handle =
          await targetBackup.openBackup(path, password: 'segretissima');
      addTearDown(handle.dispose);
      expect(handle.manifest['encrypted'], isTrue);

      // Ripristino con password: doppio strato superato.
      final restore = RestoreService(repository: target, backup: targetBackup);
      await restore.restoreFromFile(path, password: 'segretissima');
      expect(await target.getSetting('company_name'), 'Con password');
    });
  });
}

/// Rimuove l'eventuale involucro HPBK1 da un file di backup e
/// restituisce i byte dello ZIP interno (per i test che devono leggere
/// o modificare il contenuto).
Future<Uint8List> unwrapBackupZip(String backupPath) async {
  final raw = await File(backupPath).readAsBytes();
  final magic = String.fromCharCodes(raw.take(5));
  if (BackupEnvelope.isEnvelopeMagic(magic)) {
    return BackupEnvelope().openBytes(Uint8List.fromList(raw));
  }
  return Uint8List.fromList(raw);
}

/// Manomette le impostazioni dentro un file di backup: apre lo ZIP,
/// modifica le righe del database e riscrive il file (simula l'attacco
/// "licenza gratis" descritto nel Prompt 12, punto 2). Gestisce sia i
/// backup VECCHI (ZIP nudo) sia i NUOVI (involucro HPBK1, che viene
/// rimosso e rimesso: chi attacca può sempre richiudere il file).
Future<String> tamperBackupSettings(
  String backupPath,
  Map<String, String> settings,
) async {
  final envelope = BackupEnvelope();
  final inner = await unwrapBackupZip(backupPath);
  final archive = ZipDecoder().decodeBytes(inner);
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
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(newArchive));
  await File(tampered)
      .writeAsBytes(await envelope.sealBytes(zipBytes), flush: true);
  return tampered;
}

/// Riscrive il manifest dentro un file di backup applicando
/// [transform] alla mappa decodificata (per simulare backup vecchi o
/// manomessi nei campi dell'ancora, Prompt 20). L'involucro HPBK1
/// viene rimosso e rimesso se presente.
Future<String> rewriteManifest(
  String backupPath,
  Map<String, Object?> Function(Map<String, Object?> manifest) transform,
) async {
  final envelope = BackupEnvelope();
  final raw = await File(backupPath).readAsBytes();
  final magic = String.fromCharCodes(raw.take(5));
  final inner = BackupEnvelope.isEnvelopeMagic(magic)
      ? await envelope.openBytes(Uint8List.fromList(raw))
      : Uint8List.fromList(raw);
  final archive = ZipDecoder().decodeBytes(inner);
  final manifest =
      jsonDecode(utf8.decode(archive.find('manifest.json')!.content as List<int>))
          as Map<String, Object?>;
  final newManifest = transform({...manifest});
  final newManifestBytes = utf8.encode(jsonEncode(newManifest));

  final newArchive = Archive()
    ..addFile(archive.find('blue_haccp.db')!)
    ..addFile(ArchiveFile(
        'manifest.json', newManifestBytes.length, newManifestBytes));
  final tempDir = await Directory.systemTemp.createTemp('rewrite');
  final out = p.join(tempDir.path, 'rewritten.bhb');
  final zipBytes = Uint8List.fromList(ZipEncoder().encode(newArchive));
  final bytes = magic == BackupEnvelope.magic
      ? await envelope.sealBytes(zipBytes)
      : zipBytes;
  await File(out).writeAsBytes(bytes, flush: true);
  return out;
}
