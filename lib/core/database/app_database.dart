import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

/// Database locale SQLite. Versione 4: moduli cottura, abbattimento,
/// trasporto, pasto campione, acqua/ghiaccio, ritiri, cultura della
/// sicurezza alimentare, contaminazione crociata, donazioni.
///
/// Migrazioni con `onUpgrade`: nessun dato viene cancellato.
/// Versione corrente dello schema del database (riportata nel manifest
/// dei backup).
///
/// V7 (ripristino da cloud): `sync_queue.attachment_id` collega la voce
/// in coda al record `attachments` corrispondente: dopo l'upload
/// `cloud_id`/`synced_at` vengono scritti sull'allegato, così dopo un
/// ripristino si sa quale file remoto riscaricare.
const int appDatabaseVersion = 7;

class AppDatabase {
  /// [path] \u00E8 usato nei test per puntare a un file dedicato.
  AppDatabase({String? path}) : _pathOverride = path;

  final String? _pathOverride;

  Database? _db;

  Database get db {
    final value = _db;
    if (value == null) {
      throw StateError('Database non inizializzato');
    }
    return value;
  }

  String? _path;
  static bool _factoryConfigured = false;

  /// Percorso del file DB (per il backup).
  String get path {
    final value = _path;
    if (value == null) {
      throw StateError('Database non inizializzato');
    }
    return value;
  }

  Future<void> initialize() async {
    _configureDatabaseFactoryIfNeeded();

    // 'blue_haccp.db': nome storico del file database, NON cambiare
    // (compatibilità dati: i dispositivi di prova e i backup esistenti
    // puntano a questo file nella cartella privata dell'app).
    final path = _pathOverride ??
        join(await getDatabasesPath(), 'blue_haccp.db');
    _path = path;

    _db = await openDatabase(
      path,
      version: 7,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onOpen: _onOpen,
    );
  }

  void _configureDatabaseFactoryIfNeeded() {
    if (_factoryConfigured) {
      return;
    }
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    _factoryConfigured = true;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> _onOpen(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
    try {
      // Retention letture sensori: 90 giorni (potatura all'avvio).
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 90))
          .millisecondsSinceEpoch;
      await database.delete(
        'sensor_readings',
        where: 'ts < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {
      // Tabella assente (fixture minimale o migrazione parziale): la
      // potatura riproverà alla prossima apertura.
    }
  }

  Future<void> _onCreate(Database database, int version) async {
    await _createV2Tables(database);
    await _createV3Tables(database);
    await _createV4Tables(database);
    await _createV5Tables(database);
    await _createV6Tables(database);
    await _createV7Tables(database);
    await _seed(database);
    await _insertV4Defaults(database);
  }

  Future<void> _onUpgrade(Database database, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _migrateV1toV2(database);
    }
    if (oldVersion < 3) {
      await _migrateV2toV3(database);
    }
    if (oldVersion < 4) {
      await _migrateV3toV4(database);
    }
    if (oldVersion < 5) {
      await _migrateV4toV5(database);
    }
    if (oldVersion < 6) {
      await _migrateV5toV6(database);
    }
    if (oldVersion < 7) {
      await _migrateV6toV7(database);
    }
  }

  /// V5: sensori di temperatura (Prompt 7). Tabella `sensors`, colonne
  /// `temp_source`/`sensor_id` su equipment (vincolo un sensore ↔ una sola
  /// attrezzatura via indice univoco parziale) e colonne
  /// `source`/`sensor_*` su temperature_logs (istantanee che sopravvivono
  /// all'eliminazione del sensore). Nessun dato esistente viene toccato: i
  /// default sono 'manual'.
  Future<void> _createV5Tables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sensors (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        model_id TEXT NOT NULL,
        device_key TEXT NOT NULL,
        system_id TEXT,
        label TEXT,
        calibration_offset REAL NOT NULL DEFAULT 0,
        last_temp REAL,
        last_humidity REAL,
        last_seen TEXT,
        battery INTEGER,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        last_verified_at TEXT
      )
    ''');

    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_sensors_device '
      'ON sensors(device_key)',
    );

    await _addColumn(
      database,
      'equipment',
      'temp_source',
      "TEXT NOT NULL DEFAULT 'manual'",
    );
    await _addColumn(database, 'equipment', 'sensor_id', 'INTEGER');

    // Un sensore al massimo su UNA attrezzatura: indice univoco parziale
    // (ignora le righe senza sensore).
    await database.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_equipment_sensor_unique '
      'ON equipment(sensor_id) WHERE sensor_id IS NOT NULL',
    );

    if (await _tableExists(database, 'temperature_logs')) {
      await _addColumn(
        database,
        'temperature_logs',
        'source',
        "TEXT NOT NULL DEFAULT 'manual'",
      );
      await _addColumn(
          database, 'temperature_logs', 'sensor_id', 'INTEGER');
      await _addColumn(database, 'temperature_logs', 'sensor_label', 'TEXT');
      await _addColumn(
          database, 'temperature_logs', 'sensor_offset', 'REAL');
      await _addColumn(
        database,
        'temperature_logs',
        'sensor_reading_at',
        'TEXT',
      );
      await _addColumn(database, 'temperature_logs', 'sensor_raw', 'REAL');
    }

    // Storico raw dei sensori (facoltativo, schermata andamento): salvato
    // solo a app aperta, max 1 ogni 5 min o se Δ >= 0,2 °C.
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sensor_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensor_id INTEGER NOT NULL,
        ts INTEGER NOT NULL,
        temp REAL NOT NULL,
        humidity REAL,
        rssi INTEGER,
        FOREIGN KEY(sensor_id) REFERENCES sensors(id)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sensor_readings_sensor_ts '
      'ON sensor_readings(sensor_id, ts)',
    );
  }

  Future<void> _migrateV4toV5(Database database) async {
    await _createV5Tables(database);
  }

  /// V6: spazio e sicurezza degli allegati (Prompt 8, parte B). Colonne su
  /// `attachments` per deduplica (sha256), miniature (thumb_path), misure
  /// (width/height) e file liberato dopo verifica cloud (offloaded_at).
  /// Nessun dato esistente viene toccato.
  Future<void> _createV6Tables(Database database) async {
    if (!await _tableExists(database, 'attachments')) return;
    await _addColumn(database, 'attachments', 'sha256', 'TEXT');
    await _addColumn(database, 'attachments', 'thumb_path', 'TEXT');
    await _addColumn(database, 'attachments', 'width', 'INTEGER');
    await _addColumn(database, 'attachments', 'height', 'INTEGER');
    await _addColumn(database, 'attachments', 'offloaded_at', 'TEXT');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_sha256 '
      'ON attachments(sha256)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_attachments_created '
      'ON attachments(created_at)',
    );
  }

  Future<void> _migrateV5toV6(Database database) async {
    await _createV6Tables(database);
  }

  /// V7: legame coda di caricamento ↔ allegato. La colonna
  /// `sync_queue.attachment_id` (null per i PDF) permette a
  /// `SyncService.processQueue` di scrivere `cloud_id`/`synced_at`
  /// sull'allegato dopo l'upload. Nessun dato esistente viene toccato.
  Future<void> _createV7Tables(Database database) async {
    if (!await _tableExists(database, 'sync_queue')) return;
    await _addColumn(database, 'sync_queue', 'attachment_id', 'INTEGER');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_attachment '
      'ON sync_queue(attachment_id)',
    );
  }

  Future<void> _migrateV6toV7(Database database) async {
    await _createV7Tables(database);
  }

  Future<void> _createV4Tables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS cooking_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cooked_at TEXT NOT NULL,
        kind TEXT NOT NULL,
        category TEXT NOT NULL,
        food_name TEXT NOT NULL DEFAULT '',
        core_temp REAL NOT NULL,
        compliant INTEGER NOT NULL,
        corrective_action TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS oil_validations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        validated_at TEXT NOT NULL,
        fryer TEXT NOT NULL,
        temp_c REAL NOT NULL,
        sensory_ok INTEGER NOT NULL DEFAULT 1,
        oil_changed INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS blast_chill_cycles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        ended_at TEXT,
        product TEXT NOT NULL,
        kind TEXT NOT NULL,
        t_start REAL,
        t_end REAL,
        compliant INTEGER NOT NULL DEFAULT 1,
        operator_name TEXT NOT NULL,
        note TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS transport_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        done_at TEXT NOT NULL,
        destination TEXT NOT NULL DEFAULT '',
        temp_cold_start REAL,
        temp_cold_arrival REAL,
        temp_hot_start REAL,
        temp_hot_arrival REAL,
        vehicle_clean INTEGER NOT NULL DEFAULT 1,
        containers_sanitized INTEGER NOT NULL DEFAULT 1,
        compliant INTEGER NOT NULL DEFAULT 1,
        operator_name TEXT NOT NULL,
        note TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sample_meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taken_at TEXT NOT NULL,
        dish TEXT NOT NULL,
        grams REAL NOT NULL,
        discard_after TEXT NOT NULL,
        discarded_at TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS water_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checked_at TEXT NOT NULL,
        kind TEXT NOT NULL,
        result_ok INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS withdrawals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at TEXT NOT NULL,
        lot_code TEXT NOT NULL,
        clients TEXT NOT NULL DEFAULT '',
        actions TEXT NOT NULL DEFAULT '',
        asl_notified INTEGER NOT NULL DEFAULT 0,
        outcome TEXT NOT NULL DEFAULT 'in_corso',
        closed_at TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS culture_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
        done_at TEXT NOT NULL,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS cross_contamination_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checked_at TEXT NOT NULL,
        equipment TEXT NOT NULL,
        residue_found INTEGER NOT NULL DEFAULT 0,
        action TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE IF NOT EXISTS donations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        donated_at TEXT NOT NULL,
        product TEXT NOT NULL,
        quantity REAL,
        unit TEXT,
        entity TEXT NOT NULL,
        state_note TEXT,
        operator_name TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateV3toV4(Database database) async {
    await _createV4Tables(database);
    await _insertV4Defaults(database);
  }

  /// Valori di default dei limiti configurabili (PR COT/ABB/TRA/CAMP)
  /// e dei moduli attivabili: PR COT/ABB/TRA attivi, campione e donazioni
  /// disattivati (si attivano se serve, es. catering esterno).
  Future<void> _insertV4Defaults(Database database) async {
    final defaults = <String, String>{
      'limit_cooking_core_min': '75',
      'limit_regen_core_min': '65',
      'limit_fryer_max': '180',
      'limit_abb_pos_temp': '3',
      'limit_abb_pos_hours': '2',
      'limit_abb_neg_temp': '-18',
      'limit_abb_neg_hours': '2',
      'limit_hold_cold_max': '10',
      'limit_transport_cold_max': '10',
      'limit_transport_hot_min': '65',
      'limit_sample_grams': '100',
      'limit_sample_hours': '72',
      'training_renewal_months': '36',
      'module_cooking': '1',
      'module_blast_chill': '1',
      'module_transport': '1',
      'module_samples': '0',
      'module_water': '1',
      'module_recall': '1',
      'module_culture': '1',
      'module_donations': '0',
    };
    for (final entry in defaults.entries) {
      await database.insert(
        'settings',
        {'key': entry.key, 'value': entry.value},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _createV3Tables(Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
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

    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        local_path TEXT NOT NULL,
        remote_folder TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await _addColumn(database, 'equipment', 'source', "TEXT NOT NULL DEFAULT 'user'");
    await _addColumn(database, 'equipment', 'template_key', 'TEXT');
    await _addColumn(database, 'cleaning_tasks', 'source', "TEXT NOT NULL DEFAULT 'user'");
    await _addColumn(database, 'cleaning_tasks', 'template_key', 'TEXT');
    await _addColumn(database, 'products', 'source', "TEXT NOT NULL DEFAULT 'user'");
    await _addColumn(database, 'products', 'template_key', 'TEXT');
    await _addColumn(database, 'pest_stations', 'source', "TEXT NOT NULL DEFAULT 'user'");
    await _addColumn(database, 'pest_stations', 'template_key', 'TEXT');
  }

  Future<void> _migrateV2toV3(Database database) async {
    await _createV3Tables(database);
  }

  // ---------------------------------------------------------------------------

  Future<void> _createV2Tables(Database database) async {
    await database.execute('''
      CREATE TABLE equipment (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        min_temp REAL NOT NULL,
        max_temp REAL NOT NULL,
        location TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL DEFAULT '',
        thermo_verified_at TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await database.execute('''
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

    await database.execute(
      'CREATE INDEX idx_temperature_measured ON temperature_logs(measured_at)',
    );

    await database.execute('''
      CREATE TABLE thermometer_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        equipment_id INTEGER NOT NULL,
        reference_temp REAL NOT NULL,
        instrument_temp REAL NOT NULL,
        checked_at TEXT NOT NULL,
        operator_name TEXT NOT NULL,
        FOREIGN KEY(equipment_id) REFERENCES equipment(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE cleaning_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        area TEXT NOT NULL,
        title TEXT NOT NULL,
        frequency TEXT NOT NULL,
        freq_code TEXT NOT NULL DEFAULT 'daily',
        product_name TEXT,
        method TEXT,
        last_completed_at TEXT,
        active INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await database.execute('''
      CREATE TABLE cleaning_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        done_at TEXT NOT NULL,
        operator_name TEXT NOT NULL,
        had_problem INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        FOREIGN KEY(task_id) REFERENCES cleaning_tasks(id)
      )
    ''');

    await database.execute(
      'CREATE INDEX idx_cleaning_done ON cleaning_logs(done_at)',
    );

    await database.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        vat TEXT NOT NULL DEFAULT '',
        address TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        email TEXT NOT NULL DEFAULT '',
        products TEXT NOT NULL DEFAULT '',
        qualified INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE receipts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        received_at TEXT NOT NULL,
        supplier_id INTEGER NOT NULL,
        product TEXT NOT NULL,
        category TEXT NOT NULL,
        temperature REAL,
        supplier_lot TEXT,
        ddt TEXT,
        expires_at TEXT,
        quantity REAL,
        unit TEXT,
        packaging_ok INTEGER NOT NULL DEFAULT 1,
        label_ok INTEGER NOT NULL DEFAULT 1,
        expiry_ok INTEGER NOT NULL DEFAULT 1,
        vehicle_ok INTEGER NOT NULL DEFAULT 1,
        outcome TEXT NOT NULL DEFAULT 'accepted',
        note TEXT,
        operator_name TEXT NOT NULL,
        FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
      )
    ''');

    await database.execute(
      'CREATE INDEX idx_receipts_received ON receipts(received_at)',
    );

    await database.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        ingredients TEXT NOT NULL DEFAULT '',
        shelf_life_days INTEGER NOT NULL DEFAULT 0,
        storage TEXT NOT NULL DEFAULT '',
        allergens TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE lots (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT NOT NULL UNIQUE,
        product_name TEXT NOT NULL,
        product_id INTEGER,
        produced_at TEXT NOT NULL,
        expires_at TEXT,
        quantity REAL,
        unit TEXT,
        storage_info TEXT,
        operator_name TEXT NOT NULL,
        notes TEXT,
        allergens TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(product_id) REFERENCES products(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE lot_ingredients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        lot_id INTEGER NOT NULL,
        receipt_id INTEGER,
        name TEXT NOT NULL DEFAULT '',
        supplier_name TEXT NOT NULL DEFAULT '',
        supplier_lot TEXT NOT NULL DEFAULT '',
        FOREIGN KEY(lot_id) REFERENCES lots(id) ON DELETE CASCADE
      )
    ''');

    await database.execute('''
      CREATE TABLE non_conformities (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        corrective_action TEXT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        status TEXT NOT NULL,
        operator_name TEXT NOT NULL,
        disposition TEXT NOT NULL DEFAULT 'none',
        source_type TEXT,
        source_id INTEGER
      )
    ''');

    await database.execute('''
      CREATE TABLE waste_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        disposed_at TEXT NOT NULL,
        product TEXT NOT NULL,
        reason TEXT NOT NULL,
        quantity REAL,
        unit TEXT,
        lot_code TEXT,
        note TEXT,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE pest_stations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        location TEXT NOT NULL,
        active INTEGER NOT NULL DEFAULT 1,
        last_checked_at TEXT
      )
    ''');

    await database.execute('''
      CREATE TABLE pest_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        station_id INTEGER NOT NULL,
        checked_at TEXT NOT NULL,
        count INTEGER NOT NULL,
        level TEXT NOT NULL,
        by_company INTEGER NOT NULL DEFAULT 0,
        note TEXT,
        operator_name TEXT NOT NULL,
        FOREIGN KEY(station_id) REFERENCES pest_stations(id)
      )
    ''');

    await database.execute('''
      CREATE TABLE structure_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        area TEXT NOT NULL,
        checked_at TEXT NOT NULL,
        items_json TEXT NOT NULL,
        has_anomalies INTEGER NOT NULL DEFAULT 0,
        nc_id INTEGER,
        operator_name TEXT NOT NULL
      )
    ''');

    await database.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        role TEXT NOT NULL DEFAULT 'Alimentarista',
        job TEXT NOT NULL DEFAULT '',
        certificate_at TEXT,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');

    await database.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  // ---------------------------------------------------------------------------
  // Migrazione v1 -> v2
  // ---------------------------------------------------------------------------

  Future<void> _migrateV1toV2(Database database) async {
    // Nuove colonne su tabelle esistenti.
    await _addColumn(database, 'equipment', 'location', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(database, 'equipment', 'notes', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(database, 'equipment', 'thermo_verified_at', 'TEXT');
    await _addColumn(database, 'temperature_logs', 'corrective_action', 'TEXT');
    await _addColumn(database, 'cleaning_tasks', 'freq_code', "TEXT NOT NULL DEFAULT 'daily'");
    await _addColumn(database, 'cleaning_tasks', 'method', 'TEXT');
    await _addColumn(database, 'lots', 'allergens', "TEXT NOT NULL DEFAULT ''");
    await _addColumn(database, 'lots', 'product_id', 'INTEGER');
    await _addColumn(database, 'non_conformities', 'disposition', "TEXT NOT NULL DEFAULT 'none'");

    // Nuove tabelle (senza i seed demo).
    final saved = await database.rawQuery('SELECT name FROM sqlite_master WHERE type = ?', ['table']);
    final names = saved.map((r) => r['name'] as String).toSet();
    if (!names.contains('thermometer_checks')) {
      await database.execute('''
        CREATE TABLE thermometer_checks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          equipment_id INTEGER NOT NULL,
          reference_temp REAL NOT NULL,
          instrument_temp REAL NOT NULL,
          checked_at TEXT NOT NULL,
          operator_name TEXT NOT NULL,
          FOREIGN KEY(equipment_id) REFERENCES equipment(id)
        )
      ''');
    }
    if (!names.contains('cleaning_logs')) {
      await database.execute('''
        CREATE TABLE cleaning_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          task_id INTEGER NOT NULL,
          done_at TEXT NOT NULL,
          operator_name TEXT NOT NULL,
          had_problem INTEGER NOT NULL DEFAULT 0,
          note TEXT,
          FOREIGN KEY(task_id) REFERENCES cleaning_tasks(id)
        )
      ''');
    }
    if (!names.contains('suppliers')) {
      await database.execute('''
        CREATE TABLE suppliers (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          vat TEXT NOT NULL DEFAULT '',
          address TEXT NOT NULL DEFAULT '',
          phone TEXT NOT NULL DEFAULT '',
          email TEXT NOT NULL DEFAULT '',
          products TEXT NOT NULL DEFAULT '',
          qualified INTEGER NOT NULL DEFAULT 1,
          notes TEXT NOT NULL DEFAULT ''
        )
      ''');
    }
    if (!names.contains('receipts')) {
      await database.execute('''
        CREATE TABLE receipts (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          received_at TEXT NOT NULL,
          supplier_id INTEGER NOT NULL,
          product TEXT NOT NULL,
          category TEXT NOT NULL,
          temperature REAL,
          supplier_lot TEXT,
          ddt TEXT,
          expires_at TEXT,
          quantity REAL,
          unit TEXT,
          packaging_ok INTEGER NOT NULL DEFAULT 1,
          label_ok INTEGER NOT NULL DEFAULT 1,
          expiry_ok INTEGER NOT NULL DEFAULT 1,
          vehicle_ok INTEGER NOT NULL DEFAULT 1,
          outcome TEXT NOT NULL DEFAULT 'accepted',
          note TEXT,
          operator_name TEXT NOT NULL,
          FOREIGN KEY(supplier_id) REFERENCES suppliers(id)
        )
      ''');
    }
    if (!names.contains('products')) {
      await database.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          category TEXT NOT NULL DEFAULT '',
          ingredients TEXT NOT NULL DEFAULT '',
          shelf_life_days INTEGER NOT NULL DEFAULT 0,
          storage TEXT NOT NULL DEFAULT '',
          allergens TEXT NOT NULL DEFAULT ''
        )
      ''');
    }
    if (!names.contains('lot_ingredients')) {
      await database.execute('''
        CREATE TABLE lot_ingredients (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          lot_id INTEGER NOT NULL,
          receipt_id INTEGER,
          name TEXT NOT NULL DEFAULT '',
          supplier_name TEXT NOT NULL DEFAULT '',
          supplier_lot TEXT NOT NULL DEFAULT '',
          FOREIGN KEY(lot_id) REFERENCES lots(id) ON DELETE CASCADE
        )
      ''');
    }
    if (!names.contains('waste_logs')) {
      await database.execute('''
        CREATE TABLE waste_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          disposed_at TEXT NOT NULL,
          product TEXT NOT NULL,
          reason TEXT NOT NULL,
          quantity REAL,
          unit TEXT,
          lot_code TEXT,
          note TEXT,
          operator_name TEXT NOT NULL
        )
      ''');
    }
    if (!names.contains('pest_stations')) {
      await database.execute('''
        CREATE TABLE pest_stations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          location TEXT NOT NULL,
          active INTEGER NOT NULL DEFAULT 1,
          last_checked_at TEXT
        )
      ''');
    }
    if (!names.contains('pest_logs')) {
      await database.execute('''
        CREATE TABLE pest_logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          station_id INTEGER NOT NULL,
          checked_at TEXT NOT NULL,
          count INTEGER NOT NULL,
          level TEXT NOT NULL,
          by_company INTEGER NOT NULL DEFAULT 0,
          note TEXT,
          operator_name TEXT NOT NULL,
          FOREIGN KEY(station_id) REFERENCES pest_stations(id)
        )
      ''');
    }
    if (!names.contains('structure_checks')) {
      await database.execute('''
        CREATE TABLE structure_checks (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          area TEXT NOT NULL,
          checked_at TEXT NOT NULL,
          items_json TEXT NOT NULL,
          has_anomalies INTEGER NOT NULL DEFAULT 0,
          nc_id INTEGER,
          operator_name TEXT NOT NULL
        )
      ''');
    }
    if (!names.contains('staff')) {
      await database.execute('''
        CREATE TABLE staff (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'Alimentarista',
          job TEXT NOT NULL DEFAULT '',
          certificate_at TEXT,
          notes TEXT NOT NULL DEFAULT ''
        )
      ''');
    }

    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_temperature_measured ON temperature_logs(measured_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_cleaning_done ON cleaning_logs(done_at)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipts_received ON receipts(received_at)',
    );

    // Mappa le frequenze testuali v1 sui nuovi codici.
    final legacyTasks =
        await database.rawQuery('SELECT id, frequency FROM cleaning_tasks');
    for (final row in legacyTasks) {
      final label = (row['frequency'] as String?) ?? 'Giornaliera';
      final code = _freqCodeFromLegacy(label);
      await database.rawUpdate(
        'UPDATE cleaning_tasks SET freq_code = ? WHERE id = ?',
        [code, row['id']],
      );
    }

    // Porta last_completed_at nello storico cleaning_logs.
    final withHistory = await database.rawQuery(
      'SELECT id, last_completed_at FROM cleaning_tasks '
      'WHERE last_completed_at IS NOT NULL',
    );
    for (final row in withHistory) {
      final doneAt = row['last_completed_at'] as String?;
      if (doneAt == null) continue;
      await database.rawInsert(
        'INSERT INTO cleaning_logs (task_id, done_at, operator_name, had_problem) VALUES (?, ?, ?, 0)',
        [row['id'], doneAt, 'Operatore'],
      );
    }

    // Postazioni infestanti di esempio se assenti.
    final pestCount = Sqflite.firstIntValue(
          await database.rawQuery('SELECT COUNT(*) FROM pest_stations'),
        ) ??
        0;
    if (pestCount == 0) {
      final stations = [
        ['Roditori', 'Esterno - lato cortile'],
        ['Roditori', 'Magazzino - porta carico'],
        ['Striscianti', 'Cucina - sotto lavello'],
        ['Striscianti', 'Dispensa - scaffale basso'],
        ['Volanti', 'Sala - ingresso secondario'],
      ];
      for (final s in stations) {
        await database.insert('pest_stations', {
          'type': s.first,
          'location': s.last,
          'active': 1,
        });
      }
    }

    // Data di inizio prova licenza se manca.
    final trial = Sqflite.firstIntValue(
          await database
              .rawQuery("SELECT COUNT(*) FROM settings WHERE key = 'trial_started_at'"),
        ) ??
        0;
    if (trial == 0) {
      await database.insert(
        'settings',
        {'key': 'trial_started_at', 'value': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  String _freqCodeFromLegacy(String label) {
    final l = label.toLowerCase();
    if (l.contains('dopo ogni')) return 'after_use';
    if (l.contains('2 volte')) return 'twice_daily';
    if (l.contains('giornal')) return 'daily';
    if (l.contains('settiman')) return 'weekly';
    if (l.contains('mensil')) return 'monthly';
    if (l.contains('semestr')) return 'semiannual';
    if (l.contains('annual')) return 'annual';
    return 'as_needed';
  }

  Future<bool> _tableExists(Database database, String table) async {
    final rows = await database.rawQuery(
      'SELECT name FROM sqlite_master WHERE type = ? AND name = ?',
      ['table', table],
    );
    return rows.isNotEmpty;
  }

  Future<void> _addColumn(
    Database database,
    String table,
    String column,
    String definition,
  ) async {
    final columns = await database.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((c) => c['name'] == column);
    if (!exists) {
      await database.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  // ---------------------------------------------------------------------------
  // Seed iniziale (nuove installazioni)
  // ---------------------------------------------------------------------------

  Future<void> _seed(Database database) async {
    await database.insert('equipment', {
      'name': 'Frigo cucina',
      'type': 'Frigorifero',
      'min_temp': 0.0,
      'max_temp': 4.0,
      'location': 'Cucina',
      'active': 1,
    });
    await database.insert('equipment', {
      'name': 'Freezer',
      'type': 'Congelatore',
      'min_temp': -30.0,
      'max_temp': -18.0,
      'location': 'Magazzino',
      'active': 1,
    });
    await database.insert('equipment', {
      'name': 'Frigo bevande',
      'type': 'Frigorifero',
      'min_temp': 0.0,
      'max_temp': 8.0,
      'location': 'Sala',
      'active': 1,
    });

    final tasks = [
      {
        'area': 'Cucina',
        'title': 'Piani di lavoro e utensili',
        'frequency': 'Dopo ogni utilizzo',
        'freq_code': 'after_use',
        'product_name': 'Sanificante superfici',
        'method': 'Rimuovere i residui, detergere, risciacquare, sanificare e lasciare asciugare.',
      },
      {
        'area': 'Sala',
        'title': 'Superfici a contatto col cliente',
        'frequency': 'Giornaliera',
        'freq_code': 'daily',
        'product_name': 'Detergente superfici',
        'method': 'Detergere con panno dedicato e soluzione sanitizzante.',
      },
      {
        'area': 'Cucina',
        'title': 'Attrezzature meccaniche (affettatrice, tritacarne)',
        'frequency': 'Giornaliera',
        'freq_code': 'daily',
        'product_name': 'Detergente + disinfettante',
        'method': 'Smontare le parti rimovibili, lavare, sanificare, risciacquare e asciugare.',
      },
      {
        'area': 'Locale',
        'title': 'Pavimenti',
        'frequency': '2 volte al giorno',
        'freq_code': 'twice_daily',
        'product_name': 'Detergente pavimenti',
        'method': 'Aspirare, detergere con mop dedicato e lasciare asciugare.',
      },
      {
        'area': 'Servizi igienici',
        'title': 'Sanitari e pavimenti',
        'frequency': 'Giornaliera',
        'freq_code': 'daily',
        'product_name': 'Detergente sanitari',
        'method': 'Detergere sanitari, specchi e pavimenti con prodotti dedicati.',
      },
      {
        'area': 'Magazzino',
        'title': 'Scaffalature',
        'frequency': 'Settimanale',
        'freq_code': 'weekly',
        'product_name': 'Detergente superfici',
        'method': 'Svuotare, detergere e sanificare le superfici, asciugare prima di ricaricare.',
      },
      {
        'area': 'Magazzino',
        'title': 'Frigoriferi e congelatori (pulizia completa)',
        'frequency': 'Semestrale',
        'freq_code': 'semiannual',
        'product_name': 'Detergente + disinfettante alimentare',
        'method': 'Scongelare, smontare i ripiani, lavare e sanificare, asciugare prima di riattivare.',
      },
    ];
    for (final task in tasks) {
      await database.insert('cleaning_tasks', task);
    }

    final stations = [
      ['Roditori', 'Esterno - lato cortile'],
      ['Roditori', 'Magazzino - porta carico'],
      ['Striscianti', 'Cucina - sotto lavello'],
      ['Striscianti', 'Dispensa - scaffale basso'],
      ['Volanti', 'Sala - ingresso secondario'],
    ];
    for (final s in stations) {
      await database.insert('pest_stations', {
        'type': s.first,
        'location': s.last,
        'active': 1,
      });
    }

    await database.insert('settings',
        {'key': 'company_name', 'value': 'La mia attività'});
    await database.insert(
        'settings', {'key': 'default_operator', 'value': 'Operatore'});
    await database.insert('settings', {
      'key': 'trial_started_at',
      'value': DateTime.now().toIso8601String(),
    });
  }
}
