import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/sensors/sensor_source.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';

/// Modello dati sensori (Prompt 7, Fase 2): migrazione v4→v5, vincolo
/// univoco sensore↔attrezzatura, sorgente nei log, throttling dello
/// storico e backup.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('sensor_db_test');
  });

  setUp(() async {
    appDatabase = AppDatabase(
      path:
          '${tempDir.path}/sensors_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  Future<int> newEquipment(String name,
      {double min = 0, double max = 4}) async {
    return repository.saveEquipment(
      Equipment(
        id: 0,
        name: name,
        type: 'Frigorifero',
        minTemp: min,
        maxTemp: max,
      ),
    );
  }

  group('migrazione v4 -> v5', () {
    test('nuove tabelle/colonne, default manual, dati conservati', () async {
      final path =
          '${tempDir.path}/v4_${DateTime.now().millisecondsSinceEpoch}.db';

      // Database alla versione 4 (forma minimale con righe reali).
      final v4 = await openDatabase(
        path,
        version: 4,
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
          await db.execute('''
            CREATE TABLE temperature_logs (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              equipment_id INTEGER NOT NULL,
              temperature REAL NOT NULL,
              measured_at TEXT NOT NULL,
              operator_name TEXT NOT NULL,
              compliant INTEGER NOT NULL,
              note TEXT,
              corrective_action TEXT,
              FOREIGN KEY(equipment_id) REFERENCES equipment(id)
            )
          ''');
          await db.insert(
              'settings', {'key': 'onboarding_done', 'value': '1'});
          await db.insert('equipment', {
            'name': 'Frigo v4',
            'type': 'Frigorifero',
            'min_temp': 0.0,
            'max_temp': 4.0,
            'active': 1,
          });
          await db.insert('temperature_logs', {
            'equipment_id': 1,
            'temperature': 3.5,
            'measured_at': '2026-01-15T09:00:00.000',
            'operator_name': 'Test',
            'compliant': 1,
          });
        },
      );
      await v4.close();

      final migrated = AppDatabase(path: path);
      await migrated.initialize();
      final db = migrated.db;

      // Il DB sale all'ultima versione (6 dopo le migrazioni successive).
      expect(await db.getVersion(), 7);

      // Nuove tabelle e indici.
      for (final name in [
        'sensors',
        'sensor_readings',
        'idx_equipment_sensor_unique',
        'idx_sensors_device',
      ]) {
        final rows = await db.rawQuery(
            'SELECT name FROM sqlite_master WHERE name = ?', [name]);
        expect(rows, isNotEmpty, reason: 'manca $name');
      }

      // Default 'manual' sulle righe esistenti, dati conservati.
      final equipment =
          await db.rawQuery('SELECT * FROM equipment WHERE id = 1');
      expect(equipment.first['temp_source'], 'manual');
      expect(equipment.first['name'], 'Frigo v4');
      expect(equipment.first['sensor_id'], isNull);

      final log =
          await db.rawQuery('SELECT * FROM temperature_logs LIMIT 1');
      expect(log.first['source'], 'manual');
      expect(log.first['temperature'], 3.5);

      await migrated.close();
    });
  });

  group('associazione sensore <-> attrezzatura', () {
    test('linkSensor collega e la lista vede la coppia', () async {
      final id = await newEquipment('Frigo carni 1');
      final sensorId = await repository.linkSensor(
        equipmentId: id,
        modelId: 'govee_h5179',
        deviceKey: 'AB12',
        label: 'Sensore frigo carni 1',
      );

      final pairs = await repository.getEquipmentWithSensors();
      final (equipment, sensor) =
          pairs.firstWhere((pair) => pair.$1.name == 'Frigo carni 1');
      expect(equipment.tempSource, 'sensor');
      expect(equipment.sensorId, sensorId);
      expect(sensor, isNotNull);
      expect(sensor!.deviceKey, 'AB12');
      expect(sensor.displayName, 'Sensore frigo carni 1');
    });

    test('indice univoco parziale: un sensore, una sola attrezzatura',
        () async {
      final a = await newEquipment('Frigo A');
      final b = await newEquipment('Frigo B');
      final sensorId = await repository.linkSensor(
        equipmentId: a,
        modelId: 'govee_h5179',
        deviceKey: 'AB12',
      );

      // Assegnazione diretta a una seconda attrezzatura: vietata dal DB.
      expect(
        () => appDatabase.db.update(
          'equipment',
          {'sensor_id': sensorId, 'temp_source': 'sensor'},
          where: 'id = ?',
          whereArgs: [b],
        ),
        throwsA(isA<Exception>()),
        reason: 'indice univoco parziale su sensor_id',
      );
    });

    test('linkSensor SPOSTA il sensore dopo la conferma UI', () async {
      final a = await newEquipment('Frigo A');
      final b = await newEquipment('Frigo B');
      await repository.linkSensor(
          equipmentId: a, modelId: 'govee_h5179', deviceKey: 'AB12');

      await repository.linkSensor(
          equipmentId: b, modelId: 'govee_h5179', deviceKey: 'AB12');

      final pairs = {for (final (e, _) in await repository.getEquipmentWithSensors()) e.name: e};
      expect(pairs['Frigo A']!.tempSource, 'manual');
      expect(pairs['Frigo A']!.sensorId, isNull);
      expect(pairs['Frigo B']!.tempSource, 'sensor');
      expect((await repository.getSensors()).where((s) => s.deviceKey == 'AB12'),
          hasLength(1), reason: 'nessun duplicato');
    });

    test('scollegare NON cancella i log (snapshot sorgente conservato)',
        () async {
      final id = await newEquipment('Frigo A');
      final sensorId = await repository.linkSensor(
          equipmentId: id, modelId: 'govee_h5179', deviceKey: 'AB12', label: 'S1');

      final equipment = (await repository.getEquipment())
          .firstWhere((e) => e.id == id);
      await repository.saveTemperature(
        equipment: equipment,
        temperature: 3.0,
        operatorName: 'Test',
        source: 'sensor',
        sensorId: sensorId,
        sensorLabel: 'S1',
        sensorOffset: -0.5,
        sensorRaw: 3.5,
        sensorReadingAt: DateTime(2026, 1, 15, 8),
      );

      await repository.unlinkSensorFromEquipment(id);

      final after = await repository.getEquipmentWithSensors();
      final (unlinked, _) =
          after.firstWhere((pair) => pair.$1.name == 'Frigo A');
      expect(unlinked.tempSource, 'manual');
      expect(unlinked.sensorId, isNull);
      final logs = await repository.getTemperatureLogs();
      expect(logs, hasLength(1), reason: 'le letture passate restano');
      expect(logs.first.fromSensor, isTrue);
      expect(logs.first.sensorLabel, 'S1');
      expect(logs.first.sensorRaw, 3.5);
      expect(logs.first.sensorOffset, -0.5);
      expect(logs.first.sourceLabel, 'Sensore S1');
    });
  });

  group('handleSensorReading: throttling e stato', () {
    SensorSample at(DateTime ts, double temp) => SensorSample(
          sensorId: 'AB12',
          tempC: temp,
          source: SensorSourceKind.ble,
          timestamp: ts,
          rssi: -60,
        );

    test('max 1 ogni 5 min, oppure delta >= 0.2, comunque ogni 15 min',
        () async {
      final id = await newEquipment('Frigo A');
      await repository.linkSensor(
          equipmentId: id, modelId: 'govee_h5179', deviceKey: 'AB12');

      final t0 = DateTime(2026, 1, 15, 10);
      await repository.handleSensorReading(at(t0, 4.0));
      await repository.handleSensorReading(
          at(t0.add(const Duration(minutes: 2)), 5.0));

      var rows = await appDatabase.db.query('sensor_readings');
      expect(rows, hasLength(1), reason: 'entro 5 min: non persiste');
      expect((rows.first['temp'] as num) == 4.0, isTrue);

      // Delta >= 0.2 dopo 5 min: persiste.
      await repository.handleSensorReading(
          at(t0.add(const Duration(minutes: 6)), 4.5));
      rows = await appDatabase.db.query('sensor_readings');
      expect(rows, hasLength(2));

      // Delta piccolo dopo altri 5 min: non persiste.
      await repository.handleSensorReading(
          at(t0.add(const Duration(minutes: 11)), 4.4));
      rows = await appDatabase.db.query('sensor_readings');
      expect(rows, hasLength(2));

      // Comunque ogni 15 min: persiste anche a delta nullo.
      await repository.handleSensorReading(
          at(t0.add(const Duration(minutes: 21)), 4.4));
      rows = await appDatabase.db.query('sensor_readings');
      expect(rows, hasLength(3));

      // Stato del sensore sempre aggiornato.
      final sensor = (await repository.getSensors()).first;
      expect(sensor.lastTemp, 4.4);
      expect(sensor.lastSeen, t0.add(const Duration(minutes: 21)));
    });
  });

  group('"Da fare ora": sensori non raggiungibili', () {
    test('conta i sensori collegati con ultimo dato vecchio', () async {
      final id = await newEquipment('Frigo A');
      await repository.linkSensor(
          equipmentId: id, modelId: 'govee_h5179', deviceKey: 'AB12');

      expect(await repository.getUnreachableSensorCount(), 1,
          reason: 'mai visto: non raggiungibile');

      await repository.handleSensorReading(SensorSample(
        sensorId: 'AB12',
        tempC: 4.0,
        source: SensorSourceKind.ble,
        timestamp: DateTime.now(),
      ));
      expect(await repository.getUnreachableSensorCount(), 0);

      final dashboard = await repository.getDashboard();
      expect(
        dashboard.todos.where((t) =>
            t.title.toLowerCase().contains('sensore non raggiungibile')),
        isEmpty,
      );
    });
  });

  group('backup/ripristino', () {
    test('il backup include tabelle e righe dei sensori', () async {
      final id = await newEquipment('Frigo A');
      await repository.linkSensor(
        equipmentId: id,
        modelId: 'govee_h5179',
        deviceKey: 'AB12',
        label: 'Sensore frigo A',
      );
      await repository.handleSensorReading(SensorSample(
        sensorId: 'AB12',
        tempC: 4.0,
        source: SensorSourceKind.ble,
        timestamp: DateTime.now(),
      ));

      final backup = BackupService(repository: repository, appVersion: 'test');
      final path = await backup.createBackup();
      final bytes = await File(path).readAsBytes();

      // Il .bhb senza password è uno zip con il DB integro.
      final archive = ZipDecoder().decodeBytes(bytes);
      final entry = archive.files.firstWhere((f) => f.name == 'blue_haccp.db');

      final extracted =
          '${tempDir.path}/restore_${DateTime.now().millisecondsSinceEpoch}.db';
      await File(extracted).writeAsBytes(entry.content as List<int>);

      final restored = await openDatabase(extracted, version: 5);
      final sensors = await restored.query('sensors');
      expect(sensors, hasLength(1));
      expect(sensors.first['device_key'], 'AB12');
      final readings = await restored.query('sensor_readings');
      expect(readings, hasLength(1));
      final equipment =
          await restored.query('equipment', where: 'id = ?', whereArgs: [id]);
      expect(equipment.first['temp_source'], 'sensor');
      await restored.close();
    });
  });
}
