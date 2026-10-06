import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bh_migration_test');
  });

  setUp(() async {
    // Database nuovo (onCreate alla v4) per i test di conformit\u00E0.
    final freshPath =
        '${tempDir.path}/fresh_${DateTime.now().millisecondsSinceEpoch}.db';
    appDatabase = AppDatabase(path: freshPath);
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  test('migrazione v3 -> v4: nuove tabelle, default limiti, dati conservati',
      () async {
    final migrationPath =
        '${tempDir.path}/migrazione_${DateTime.now().millisecondsSinceEpoch}.db';

    // Database alla versione 3 (forma minimale: tabelle piene + righe reali).
    final v3 = await openDatabase(
      migrationPath,
      version: 3,
      onCreate: (db, version) async {
        await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
        await db.execute('''
          CREATE TABLE equipment (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            min_temp REAL NOT NULL,
            max_temp REAL NOT NULL,
            location TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            thermo_verified_at TEXT,
            active INTEGER NOT NULL DEFAULT 1,
            source TEXT NOT NULL DEFAULT 'user',
            template_key TEXT
          )
        ''');
        await db.insert('settings',
            {'key': 'onboarding_done', 'value': '1'});
        await db.insert('equipment', {
          'name': 'Frigo testify',
          'type': 'Frigorifero',
          'min_temp': 0.0,
          'max_temp': 4.0,
          'active': 1,
        });
      },
    );
    await v3.close();

    // Apertura con AppDatabase: migrazione a v4.
    final migrationDb = AppDatabase(path: migrationPath);
    await migrationDb.initialize();
    final migrationRepo = HaccpRepository(migrationDb);

    final db = migrationDb.db;
    // Il DB sale all'ultima versione (5 con i sensori: le tabelle v4
    // restano e i dati sono conservati).
    expect(await db.getVersion(), 5);

    // Nuove tabelle della v4 presenti.
    for (final table in [
      'cooking_logs',
      'oil_validations',
      'blast_chill_cycles',
      'transport_logs',
      'sample_meals',
      'water_checks',
      'withdrawals',
      'culture_log',
      'cross_contamination_checks',
      'donations',
    ]) {
      final rows = await db.rawQuery(
          'SELECT name FROM sqlite_master WHERE name = ?', [table]);
      expect(rows, isNotEmpty, reason: 'manca la tabella $table');
    }

    // Default dei limiti inseriti senza sovrascrivere chiavi esistenti.
    expect(await migrationRepo.getLimit('limit_cooking_core_min', 0), 75.0);
    expect(await migrationRepo.getLimit('limit_abb_neg_temp', 0), -18.0);
    expect(await migrationRepo.getTrainingRenewalMonths(), 36);
    expect(await migrationRepo.isModuleEnabled('module_cooking'), isTrue);
    expect(await migrationRepo.isModuleEnabled('module_samples'), isFalse,
        reason: 'pasto campione disattivato di default');

    // Dati v3 conservati.
    final equipment = await migrationRepo.getEquipment();
    expect(equipment, hasLength(1));
    expect(equipment.first.name, 'Frigo testify');
    expect(await migrationRepo.isOnboardingDone(), isTrue);

    await migrationDb.close();
  });

  test('cottura sotto limite: esito non conforme e NC aperta', () async {
    final compliant = await repository.saveCookingLog(
      kind: 'cottura',
      category: 'Pollame, carne, pesce, pasta ripiena',
      foodName: 'Pollo arrosto',
      coreTemp: 62.5,
      correctiveAction: 'Prodotto ricottura fino a temperatura raggiunta',
      operatorName: 'Test',
    );
    expect(compliant, isFalse);

    final logs = await repository.getCookingLogs();
    expect(logs, hasLength(1));
    expect(logs.first.compliant, isFalse);

    final openNc =
        (await repository.getNonConformities()).where((n) => n.isOpen);
    expect(openNc, isNotEmpty);
    expect(openNc.first.category, 'Temperatura');
  });

  test('rigenerazione a 70 \u00B0C conforme (limite 65)', () async {
    final compliant = await repository.saveCookingLog(
      kind: 'rigenerazione',
      category: 'Lasagna',
      coreTemp: 70,
      operatorName: 'Test',
    );
    expect(compliant, isTrue);
  });

  test('abbattimento positivo entro limiti conforme, fuori anomalia',
      () async {
    final ok = await repository.saveBlastChillCycle(
      product: 'Rag\u00F9',
      kind: 'positivo',
      startedAt: DateTime.now().subtract(const Duration(minutes: 90)),
      endedAt: DateTime.now(),
      tEnd: 2.5,
      operatorName: 'Test',
    );
    expect(ok, isTrue);

    final anomaly = await repository.saveBlastChillCycle(
      product: 'Arrosticini',
      kind: 'positivo',
      startedAt: DateTime.now().subtract(const Duration(minutes: 180)),
      endedAt: DateTime.now(),
      tEnd: 8.0,
      operatorName: 'Test',
    );
    expect(anomaly, isFalse);
  });

  test('pasto campione: scadenza di smaltimento calcolata a 72 ore',
      () async {
    await repository.saveSampleMeal(
      dish: 'Pasta al forno',
      grams: 120,
      operatorName: 'Test',
    );
    final samples = await repository.getSampleMeals();
    expect(samples, hasLength(1));
    final difference = samples.first.discardAfter
        .difference(samples.first.takenAt)
        .inHours;
    // 72 ore nominali: il troncamento dei millisecondi può dare 71.
    expect(difference, inInclusiveRange(71, 72));
    expect(samples.first.isPendingDisposal, isFalse);
  });

  tearDown(() async {
    await appDatabase.close();
  });
}
