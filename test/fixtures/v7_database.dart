import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Database SINTETICO con lo schema della versione PUBBLICATA (v7),
/// usato dai test di aggiornamento (Prompt 19, §0). Nessun dato reale
/// di clienti: nomi e codici inventati.
///
/// Contiene:
/// - 3 lotti: attivo, scaduto (scadenza passata), con ingredienti
///   collegati a un ricevimento;
/// - 1 fornitore, 1 ricevimento, 1 prodotto;
/// - la tabella `lots` SENZA le colonne degli stati (come in v7).
Future<String> buildPublishedV7Database(Directory dir) async {
  final path = p.join(dir.path, 'blue_haccp.db');
  final db = await openDatabase(path, version: 7, onCreate: (db, v) async {
    await db.execute(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '',
        ingredients TEXT NOT NULL DEFAULT '',
        shelf_life_days INTEGER NOT NULL DEFAULT 0,
        storage TEXT NOT NULL DEFAULT '',
        allergens TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT 'user',
        template_key TEXT
      )
    ''');
    // Schema `lots` della versione pubblicata (v7): NESSUNA colonna di
    // stato. È la definizione su cui la migrazione v8 deve essere
    // additiva e idempotente.
    await db.execute('''
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
    await db.execute('''
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
    await db.execute('''
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
    // Tabelle dei registri toccate dalla dashboard (vuote: servono perché
    // getDashboard le interroga; una installazione pubblicata le ha).
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
        template_key TEXT,
        temp_source TEXT NOT NULL DEFAULT 'manual',
        sensor_id INTEGER
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
        source TEXT NOT NULL DEFAULT 'manual',
        sensor_id INTEGER,
        sensor_label TEXT,
        sensor_offset REAL,
        sensor_reading_at TEXT,
        sensor_raw REAL,
        FOREIGN KEY(equipment_id) REFERENCES equipment(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE cleaning_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        area TEXT NOT NULL,
        title TEXT NOT NULL,
        frequency TEXT NOT NULL,
        freq_code TEXT NOT NULL DEFAULT 'daily',
        product_name TEXT,
        method TEXT,
        last_completed_at TEXT,
        active INTEGER NOT NULL DEFAULT 1,
        source TEXT NOT NULL DEFAULT 'user',
        template_key TEXT
      )
    ''');
    await db.execute('''
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
    await db.execute('''
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
    await db.execute(
        'CREATE TABLE pest_stations (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'type TEXT NOT NULL, location TEXT NOT NULL, active INTEGER NOT NULL '
        'DEFAULT 1, last_checked_at TEXT, source TEXT NOT NULL DEFAULT '
        "'user', template_key TEXT)");
    await db.execute(
        'CREATE TABLE structure_checks (id INTEGER PRIMARY KEY '
        'AUTOINCREMENT, area TEXT NOT NULL, checked_at TEXT NOT NULL, '
        'items_json TEXT NOT NULL, has_anomalies INTEGER NOT NULL DEFAULT 0, '
        'nc_id INTEGER, operator_name TEXT NOT NULL)');
    await db.execute(
        'CREATE TABLE staff (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT '
        'NOT NULL, role TEXT NOT NULL DEFAULT '
        "'Alimentarista', job TEXT NOT NULL DEFAULT '', certificate_at TEXT, "
        "notes TEXT NOT NULL DEFAULT '')");
    await db.execute('''
      CREATE TABLE sample_meals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        taken_at TEXT NOT NULL,
        dish TEXT NOT NULL,
        grams REAL NOT NULL,
        discard_after TEXT NOT NULL,
        discarded_at TEXT,
        operator_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE water_checks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        checked_at TEXT NOT NULL,
        kind TEXT NOT NULL,
        result_ok INTEGER NOT NULL DEFAULT 1,
        note TEXT,
        operator_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE culture_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        notes TEXT,
        done_at TEXT NOT NULL,
        operator_name TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE sensors (
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
    await db.execute('''
      CREATE TABLE sensor_readings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sensor_id INTEGER NOT NULL,
        ts INTEGER NOT NULL,
        temp REAL NOT NULL,
        humidity REAL,
        rssi INTEGER,
        FOREIGN KEY(sensor_id) REFERENCES sensors(id)
      )
    ''');
    await db.insert('settings',
        {'key': 'default_operator', 'value': 'Rossi'});
    final supplierId = await db.insert('suppliers', {
      'name': 'Fornitore Test',
      'products': 'Passata, mozzarella',
    });
    final receiptId = await db.insert('receipts', {
      'received_at': '2026-09-01T08:30:00.000',
      'supplier_id': supplierId,
      'product': 'Passata di pomodoro',
      'category': 'shelf_stable',
      'supplier_lot': 'FORN-001',
      'quantity': 12,
      'unit': 'kg',
      'operator_name': 'Rossi',
    });
    final productId = await db.insert('products', {
      'name': 'Pizza margherita',
      'category': 'Piatto pronto',
      'shelf_life_days': 3,
    });
    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String();
    final activeLotId = await db.insert('lots', {
      'code': 'L260101-PIZ-1000',
      'product_name': 'Pizza margherita',
      'product_id': productId,
      'produced_at': iso(now.subtract(const Duration(days: 1))),
      'expires_at': iso(now.add(const Duration(days: 2))),
      'quantity': 10,
      'unit': 'pz',
      'operator_name': 'Rossi',
      'notes': 'lotto di prova attivo',
    });
    final expiredLotId = await db.insert('lots', {
      'code': 'L260101-PIZ-0900',
      'product_name': 'Pizza margherita',
      'product_id': productId,
      'produced_at': iso(now.subtract(const Duration(days: 10))),
      'expires_at': iso(now.subtract(const Duration(days: 3))),
      'quantity': 4,
      'unit': 'pz',
      'operator_name': 'Rossi',
      'notes': 'lotto di prova scaduto mai chiuso',
    });
    await db.insert('lots', {
      'code': 'L260101-LIB-0800',
      'product_name': 'Impasto fresco',
      'produced_at': iso(now.subtract(const Duration(days: 20))),
      'expires_at': iso(now.subtract(const Duration(days: 5))),
      'quantity': 2,
      'unit': 'kg',
      'operator_name': 'Rossi',
    });
    await db.insert('lot_ingredients', {
      'lot_id': activeLotId,
      'receipt_id': receiptId,
      'name': 'Passata di pomodoro',
      'supplier_name': 'Fornitore Test',
      'supplier_lot': 'FORN-001',
    });
    await db.insert('lot_ingredients', {
      'lot_id': expiredLotId,
      'receipt_id': receiptId,
      'name': 'Passata di pomodoro',
      'supplier_name': 'Fornitore Test',
      'supplier_lot': 'FORN-001',
    });
  });
  await db.close();
  return path;
}
