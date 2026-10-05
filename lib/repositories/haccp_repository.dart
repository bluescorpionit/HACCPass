import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../core/constants/haccp_rules.dart';
import '../core/database/app_database.dart';
import '../core/utils/format.dart';
import '../models/haccp_models.dart';

/// Riga del motore "Da fare ora" della dashboard.
class TodoItem {
  const TodoItem({
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.target,
  });

  /// 0 = danger, 1 = warning, 2 = info.
  final int severity;
  final String icon;
  final String title;
  final String subtitle;

  /// Destinazione nell'hub Controlli (indice) o schermata.
  final String target;
}

class DashboardData {
  const DashboardData({
    required this.todos,
    required this.doneCount,
    required this.totalCount,
    required this.company,
    this.openNc = 0,
    this.temperatureCount = 0,
    this.lotsCount = 0,
    this.receiptsCount = 0,
    this.onboardingProgress = 100,
    this.onboardingStep = 0,
  });

  final List<TodoItem> todos;

  /// Controlli giornalieri completati (letture + pulizie giornaliere).
  final int doneCount;
  final int totalCount;
  final CompanyProfile company;
  final int openNc;
  final int temperatureCount;
  final int lotsCount;
  final int receiptsCount;

  /// Percentuale di configurazione completata (0-100) e passo da cui
  /// riprendere il wizard.
  final int onboardingProgress;
  final int onboardingStep;
}

class HaccpRepository {
  HaccpRepository(this.database);

  final AppDatabase database;

  /// Incrementato dopo ogni scrittura: i widget LiveQuery si aggiornano.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  void _bump() => revision.value++;

  Database get _db => database.db;

  Future<T> _write<T>(Future<T> Function() action) async {
    final result = await action();
    _bump();
    return result;
  }

  // ---------------------------------------------------------------------------
  // Impostazioni e anagrafica
  // ---------------------------------------------------------------------------

  Future<String> getSetting(String key, {String fallback = ''}) async {
    final rows = await _db.query('settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return fallback;
    return (rows.first['value'] as String?) ?? fallback;
  }

  Future<void> setSetting(String key, String value) async {
    await _write(() async {
      await _db.insert('settings', {'key': key, 'value': value},
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<CompanyProfile> getCompany() async {
    final keys = const CompanyProfile().settingsMap.keys.toList();
    final values = <String, String>{};
    for (final k in keys) {
      values[k] = await getSetting(k);
    }
    return CompanyProfile.fromMap(values);
  }

  Future<void> saveCompany(CompanyProfile company) async {
    await _write(() async {
      for (final entry in company.settingsMap.entries) {
        await _db.insert('settings', {'key': entry.key, 'value': entry.value},
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<String> defaultOperator() =>
      getSetting('default_operator', fallback: 'Operatore');

  /// Periodo di rinnovo dell'attestato alimentarista: configurabile per
  /// attivit\u00E0/regione (es. L.R. Emilia-Romagna 9/2025, TGR Toscana
  /// 540/2024), default 36 mesi.
  Future<int> getTrainingRenewalMonths() async {
    final raw = await getSetting('training_renewal_months');
    final parsed = int.tryParse(raw);
    return parsed == null || parsed < 6 ? 36 : parsed;
  }

  // ---------------------------------------------------------------------------
  // Attrezzature e temperature
  // ---------------------------------------------------------------------------

  Future<List<Equipment>> getEquipment() async {
    final rows = await _db
        .query('equipment', where: 'active = 1', orderBy: 'name');
    return rows.map(Equipment.fromMap).toList();
  }

  Future<List<Equipment>> getAllEquipment() async {
    final rows = await _db.query('equipment', orderBy: 'name');
    return rows.map(Equipment.fromMap).toList();
  }

  Future<int> saveEquipment(Equipment equipment, {int? id}) async {
    return _write(() async {
      if (id == null) {
        return _db.insert('equipment', {
          ...equipment.toMap(),
          'active': 1,
          'source': 'user',
        });
      }
      await _db.update(
        'equipment',
        {...equipment.toMap(), 'source': 'user'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<void> deactivateEquipment(int id) async {
    await _write(() async {
      await _db.update('equipment', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<Map<String, Object?>> saveTemperature({
    required Equipment equipment,
    required double temperature,
    required String operatorName,
    String? note,
    String? correctiveAction,
  }) async {
    final compliant = equipment.isCompliant(temperature);
    final now = DateTime.now();

    return _write(() async {
      final logId = await _db.insert('temperature_logs', {
        'equipment_id': equipment.id,
        'temperature': temperature,
        'measured_at': now.toIso8601String(),
        'operator_name': operatorName,
        'compliant': compliant ? 1 : 0,
        'note': note,
        'corrective_action': correctiveAction,
      });

      int? ncId;
      if (!compliant) {
        ncId = await _db.insert('non_conformities', {
          'category': 'Temperatura',
          'title': 'Temperatura fuori limite - ${equipment.name}',
          'description':
              'Rilevati ${temperature.toStringAsFixed(1)} \u00B0C. Limiti di '
              'riferimento: ${equipment.minTemp.toStringAsFixed(0)} / '
              '${equipment.maxTemp.toStringAsFixed(0)} \u00B0C.',
          'corrective_action': correctiveAction,
          'opened_at': now.toIso8601String(),
          'closed_at': null,
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'none',
          'source_type': 'temperature_log',
          'source_id': logId,
        });
      }

      return {'compliant': compliant, 'nonConformityId': ncId};
    });
  }

  Future<List<TemperatureLog>> getTemperatureLogs({
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('t.measured_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('t.measured_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.rawQuery(
      '''
      SELECT t.*, e.name AS equipment_name, e.min_temp, e.max_temp
      FROM temperature_logs t
      JOIN equipment e ON e.id = t.equipment_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY t.measured_at DESC
      ''',
      args,
    );
    return rows.map(TemperatureLog.fromMap).toList();
  }

  Future<List<TemperatureLog>> getTodayTemperatureLogs() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return getTemperatureLogs(from: start, to: start.add(const Duration(days: 1)));
  }

  /// Serie per il grafico andamento (ultimi N giorni).
  Future<List<TemperatureLog>> getEquipmentHistory(int equipmentId,
      {int days = 14}) async {
    final start =
        dateOnly(DateTime.now().subtract(Duration(days: days)));
    final rows = await _db.rawQuery(
      '''
      SELECT t.*, e.name AS equipment_name, e.min_temp, e.max_temp
      FROM temperature_logs t
      JOIN equipment e ON e.id = t.equipment_id
      WHERE t.equipment_id = ? AND t.measured_at >= ?
      ORDER BY t.measured_at ASC
      ''',
      [equipmentId, start.toIso8601String()],
    );
    return rows.map(TemperatureLog.fromMap).toList();
  }

  /// Attrezzature senza letture oggi (controllo visivo giornaliero minimo).
  Future<List<Equipment>> getEquipmentWithoutReadingToday() async {
    final withReading = (await getTodayTemperatureLogs())
        .map((l) => l.equipmentId)
        .toSet();
    final all = await getEquipment();
    return all.where((e) => !withReading.contains(e.id)).toList();
  }

  // ---------------------------------------------------------------------------
  // Verifica termometri (PRP 4)
  // ---------------------------------------------------------------------------

  Future<int> saveThermometerCheck({
    required Equipment equipment,
    required double referenceTemp,
    required double instrumentTemp,
    required String operatorName,
  }) async {
    return _write(() async {
      final id = await _db.insert('thermometer_checks', {
        'equipment_id': equipment.id,
        'reference_temp': referenceTemp,
        'instrument_temp': instrumentTemp,
        'checked_at': DateTime.now().toIso8601String(),
        'operator_name': operatorName,
      });
      await _db.update(
        'equipment',
        {'thermo_verified_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [equipment.id],
      );

      final check = ThermometerCheck(
        id: id,
        equipmentId: equipment.id,
        referenceTemp: referenceTemp,
        instrumentTemp: instrumentTemp,
        checkedAt: DateTime.now(),
        operatorName: operatorName,
      );
      if (check.mustReplace) {
        await _db.insert('non_conformities', {
          'category': 'Attrezzatura',
          'title': 'Termometro fuori tolleranza - ${equipment.name}',
          'description':
              'Scostamento di ${check.deviation.toStringAsFixed(1)} \u00B0C tra '
              'riferimento e strumento (tolleranza \u00B11 \u00B0C, sostituzione '
              'oltre \u00B13 \u00B0C).',
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'none',
          'source_type': 'thermometer_check',
          'source_id': id,
        });
      }
      return id;
    });
  }

  Future<List<ThermometerCheck>> getThermometerChecks({
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('t.checked_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('t.checked_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.rawQuery(
      '''
      SELECT t.*, e.name AS equipment_name FROM thermometer_checks t
      JOIN equipment e ON e.id = t.equipment_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY t.checked_at DESC
      ''',
      args,
    );
    return rows.map(ThermometerCheck.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Pulizie (PRP 2)
  // ---------------------------------------------------------------------------

  Future<List<CleaningTask>> getCleaningTasks() async {
    final rows = await _db.rawQuery('''
      SELECT t.*,
        (SELECT COUNT(*) FROM cleaning_logs l
         WHERE l.task_id = t.id
           AND l.done_at >= ? AND l.done_at < ? AND l.had_problem = 0) AS today_done_count
      FROM cleaning_tasks t
      WHERE t.active = 1
      ORDER BY t.area, t.title
    ''', [
      _todayStart().toIso8601String(),
      _todayStart().add(const Duration(days: 1)).toIso8601String(),
    ]);
    return rows.map(CleaningTask.fromMap).toList();
  }

  DateTime _todayStart() => dateOnly(DateTime.now());

  Future<int> saveCleaningTask(CleaningTask task, {int? id}) async {
    return _write(() async {
      if (id == null) {
        return _db.insert('cleaning_tasks', {
          ...task.toMap(),
          'active': 1,
          'source': 'user',
        });
      }
      await _db.update(
        'cleaning_tasks',
        {...task.toMap(), 'source': 'user'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<void> deactivateCleaningTask(int id) async {
    await _write(() async {
      await _db.update('cleaning_tasks', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> completeCleaningTask(CleaningTask task,
      {required String operatorName}) async {
    await _write(() async {
      final now = DateTime.now().toIso8601String();
      await _db.insert('cleaning_logs', {
        'task_id': task.id,
        'done_at': now,
        'operator_name': operatorName,
        'had_problem': 0,
      });
      await _db.update('cleaning_tasks', {'last_completed_at': now},
          where: 'id = ?', whereArgs: [task.id]);
    });
  }

  /// "Problema" su una pulizia: registra il problema e crea la NC.
  Future<int> reportCleaningProblem(CleaningTask task,
      {required String operatorName, String? note}) async {
    return _write(() async {
      await _db.insert('cleaning_logs', {
        'task_id': task.id,
        'done_at': DateTime.now().toIso8601String(),
        'operator_name': operatorName,
        'had_problem': 1,
        'note': note,
      });
      return _db.insert('non_conformities', {
        'category': 'Pulizia',
        'title': 'Superficie non idonea - ${task.title}',
        'description': note?.isNotEmpty == true
            ? note!
            : 'Superficie non idonea (sporco visibile, tracce di unto o '
                'odori) rilevata su "${task.title}" nell\u2019area ${task.area}.',
        'opened_at': DateTime.now().toIso8601String(),
        'status': 'Aperta',
        'operator_name': operatorName,
        'disposition': 'none',
        'source_type': 'cleaning_task',
        'source_id': task.id,
      });
    });
  }

  Future<List<CleaningLog>> getCleaningLogs({
    DateTime? from,
    DateTime? to,
    bool onlyProblems = false,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('l.done_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('l.done_at < ?');
      args.add(to.toIso8601String());
    }
    if (onlyProblems) where.add('l.had_problem = 1');
    final rows = await _db.rawQuery(
      '''
      SELECT l.*, t.title AS task_title, t.area AS task_area
      FROM cleaning_logs l
      JOIN cleaning_tasks t ON t.id = l.task_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY l.done_at DESC
      ''',
      args,
    );
    return rows.map(CleaningLog.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Fornitori e merce in arrivo (PRP 10)
  // ---------------------------------------------------------------------------

  Future<List<Supplier>> getSuppliers() async {
    final rows = await _db.rawQuery('''
      SELECT s.*,
        (SELECT COUNT(*) FROM non_conformities n
          WHERE n.source_type = 'receipt' AND n.source_id IN
            (SELECT r.id FROM receipts r WHERE r.supplier_id = s.id)) AS nc_count
      FROM suppliers s
      ORDER BY s.name
    ''');
    return rows.map(Supplier.fromMap).toList();
  }

  Future<int> saveSupplier(Supplier supplier, {int? id}) async {
    return _write(() async {
      if (id == null) return _db.insert('suppliers', supplier.toMap());
      await _db.update('suppliers', supplier.toMap(),
          where: 'id = ?', whereArgs: [id]);
      return id;
    });
  }

  Future<void> deleteSupplier(int id) async {
    await _write(() async {
      await _db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> saveReceipt(Receipt receipt) async {
    return _write(() async {
      final id = await _db.insert('receipts', receipt.toMap());

      final failedChecks = <String>[
        if (!receipt.packagingOk) 'integrit\u00E0 confezioni',
        if (!receipt.labelOk) 'etichettatura',
        if (!receipt.expiryOk) 'scadenza',
        if (!receipt.vehicleOk) 'igiene del mezzo di trasporto',
        if (!receipt.isTempCompliant) 'temperatura all\u2019arrivo',
      ];

      if (receipt.isRejected || failedChecks.isNotEmpty) {
        final supplier = receipt.supplierName.isEmpty ? 'Fornitore' : receipt.supplierName;
        await _db.insert('non_conformities', {
          'category': 'Ricevimento merci',
          'title': 'Merce non conforme - ${receipt.product}',
          'description':
              'Fornitore: $supplier.\nControlli con esito negativo: '
              '${failedChecks.isEmpty ? 'nessuno (respinta per decisione dell\u2019operatore)' : failedFlagsText(failedChecks)}'
              '${receipt.temperature != null ? '\nTemperatura rilevata: ${receipt.temperature!.toStringAsFixed(1)} \u00B0C (riferimento ${receipt.categoryEnum.rangeLabel}).' : ''}'
              '\nEsito: ${receipt.outcomeLabel}.',
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': receipt.operatorName,
          'disposition': receipt.isRejected ? 'returned' : 'isolated',
          'source_type': 'receipt',
          'source_id': id,
        });
      }
      return id;
    });
  }

  String failedFlagsText(List<String> flags) => flags.join(', ');

  Future<List<Receipt>> getReceipts({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('r.received_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('r.received_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.rawQuery(
      '''
      SELECT r.*, s.name AS supplier_name FROM receipts r
      JOIN suppliers s ON s.id = r.supplier_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY r.received_at DESC
      ''',
      args,
    );
    return rows.map(Receipt.fromMap).toList();
  }

  /// Merci ricevute negli ultimi 60 giorni non respinte (per ingredienti lotto).
  Future<List<Receipt>> getUsableReceipts() async {
    final start =
        dateOnly(DateTime.now().subtract(const Duration(days: 60)));
    return getReceipts(from: start)
        .then((list) => list.where((r) => !r.isRejected).toList());
  }

  // ---------------------------------------------------------------------------
  // Prodotti e lotti
  // ---------------------------------------------------------------------------

  Future<List<Product>> getProducts() async {
    final rows = await _db.query('products', orderBy: 'name');
    return rows.map(Product.fromMap).toList();
  }

  Future<int> saveProduct(Product product, {int? id}) async {
    return _write(() async {
      if (id == null) {
        return _db.insert('products', {...product.toMap(), 'source': 'user'});
      }
      await _db.update(
        'products',
        {...product.toMap(), 'source': 'user'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<void> deleteProduct(int id) async {
    await _write(() async {
      await _db.delete('products', where: 'id = ?', whereArgs: [id]);
    });
  }

  String generateLotCode(String productName) {
    final now = DateTime.now();
    final prefix = productName
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toUpperCase()
        .padRight(3, 'X')
        .substring(0, 3);
    final date = DateFormat('yyMMdd').format(now);
    final time = DateFormat('HHmm').format(now);
    return 'L$date-$prefix-$time';
  }

  Future<int> createLot(ProductionLot lot,
      {List<LotIngredient> ingredients = const []}) async {
    return _write(() async {
      final id = await _db.insert('lots', lot.toMap());
      for (final ing in ingredients) {
        await _db.insert('lot_ingredients', {...ing.toMap(), 'lot_id': id});
      }
      return id;
    });
  }

  Future<List<ProductionLot>> getLots({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('produced_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('produced_at < ?');
      args.add(to.toIso8601String());
    }
    final lots = await _db.query('lots',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'produced_at DESC');
    final result = <ProductionLot>[];
    for (final row in lots) {
      final ingredients = await _db.rawQuery('''
        SELECT li.*, r.supplier_lot AS supplier_lot_ref, s.name AS supplier_ref
        FROM lot_ingredients li
        LEFT JOIN receipts r ON r.id = li.receipt_id
        LEFT JOIN suppliers s ON s.id = r.supplier_id
        WHERE li.lot_id = ?
      ''', [row['id']]);
      result.add(ProductionLot.fromMap(
        row,
        ingredients.map(LotIngredient.fromMap).toList(),
      ));
    }
    return result;
  }

  /// Ricerca rintracciabilità: per codice lotto, prodotto o lotto fornitore.
  Future<TraceabilityResult> searchTraceability(String query) async {
    final q = '%${query.trim()}%';
    final lots = await _db.rawQuery('''
      SELECT DISTINCT l.* FROM lots l
      LEFT JOIN lot_ingredients li ON li.lot_id = l.id
      LEFT JOIN receipts r ON r.id = li.receipt_id
      WHERE l.code LIKE ? OR l.product_name LIKE ?
         OR r.supplier_lot LIKE ? OR li.supplier_lot LIKE ?
      ORDER BY l.produced_at DESC
    ''', [q, q, q, q]);

    final receipts = await _db.rawQuery('''
      SELECT DISTINCT r.*, s.name AS supplier_name FROM receipts r
      JOIN suppliers s ON s.id = r.supplier_id
      WHERE r.supplier_lot LIKE ? OR r.product LIKE ?
      ORDER BY r.received_at DESC
    ''', [q, q]);

    final result = TraceabilityResult(
      lots: await Future.wait(lots.map((row) async {
        final ingredients = await _db.rawQuery(
          'SELECT * FROM lot_ingredients WHERE lot_id = ?',
          [row['id']],
        );
        return ProductionLot.fromMap(
            row, ingredients.map(LotIngredient.fromMap).toList());
      })),
      receipts: receipts.map(Receipt.fromMap).toList(),
    );
    return result;
  }

  /// Lotti prodotti che contengono una data consegna (rintracciabilità a valle).
  Future<List<ProductionLot>> getLotsUsingReceipt(int receiptId) async {
    final rows = await _db.rawQuery('''
      SELECT l.* FROM lots l
      JOIN lot_ingredients li ON li.lot_id = l.id
      WHERE li.receipt_id = ?
      ORDER BY l.produced_at DESC
    ''', [receiptId]);
    final result = <ProductionLot>[];
    for (final row in rows) {
      final ingredients = await _db.rawQuery(
        'SELECT * FROM lot_ingredients WHERE lot_id = ?',
        [row['id']],
      );
      result.add(ProductionLot.fromMap(
          row, ingredients.map(LotIngredient.fromMap).toList()));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Non conformità e smaltimenti
  // ---------------------------------------------------------------------------

  Future<List<NonConformity>> getNonConformities({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('opened_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('opened_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.query('non_conformities',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy:
            "CASE status WHEN 'Aperta' THEN 0 ELSE 1 END, opened_at DESC");
    return rows.map(NonConformity.fromMap).toList();
  }

  Future<int> createNonConformity({
    required String category,
    required String title,
    required String description,
    required String operatorName,
    String? correctiveAction,
    String disposition = 'none',
    String? sourceType,
    int? sourceId,
  }) async {
    return _write(() async {
      return _db.insert('non_conformities', {
        'category': category,
        'title': title,
        'description': description,
        'corrective_action': correctiveAction,
        'opened_at': DateTime.now().toIso8601String(),
        'closed_at': null,
        'status': 'Aperta',
        'operator_name': operatorName,
        'disposition': disposition,
        'source_type': sourceType,
        'source_id': sourceId,
      });
    });
  }

  Future<void> closeNonConformity({
    required int id,
    required String correctiveAction,
    required String disposition,
  }) async {
    await _write(() async {
      await _db.update(
        'non_conformities',
        {
          'status': 'Chiusa',
          'corrective_action': correctiveAction,
          'disposition': disposition,
          'closed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<int> saveWasteLog(WasteLog log) async {
    return _write(() async {
      return _db.insert('waste_logs', {
        'disposed_at': log.disposedAt.toIso8601String(),
        'product': log.product,
        'reason': log.reason,
        'quantity': log.quantity,
        'unit': log.unit,
        'lot_code': log.lotCode,
        'note': log.note,
        'operator_name': log.operatorName,
      });
    });
  }

  Future<List<WasteLog>> getWasteLogs({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('disposed_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('disposed_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.query('waste_logs',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'disposed_at DESC');
    return rows.map(WasteLog.fromMap).toList();
  }

  // ---------------------------------------------------------------------------
  // Infestanti (PRP 3)
  // ---------------------------------------------------------------------------

  Future<List<PestStation>> getPestStations() async {
    final rows = await _db.query('pest_stations',
        where: 'active = 1', orderBy: 'type, location');
    return rows.map(PestStation.fromMap).toList();
  }

  Future<int> savePestStation(PestStation station, {int? id}) async {
    return _write(() async {
      if (id == null) {
        return _db.insert('pest_stations', {
          ...station.toMap(),
          'active': 1,
          'source': 'user',
        });
      }
      await _db.update(
        'pest_stations',
        {...station.toMap(), 'source': 'user'},
        where: 'id = ?',
        whereArgs: [id],
      );
      return id;
    });
  }

  Future<void> deletePestStation(int id) async {
    await _write(() async {
      await _db.update('pest_stations', {'active': 0},
          where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<int> savePestLog({
    required PestStation station,
    required int count,
    required bool byCompany,
    required String operatorName,
    String? note,
  }) async {
    return _write(() async {
      final level = switch (station.type) {
        'Roditori' => pestLevelForRodents(count),
        'Striscianti' => pestLevelForCrawlers(count),
        _ => pestLevelForFlyers(count),
      };
      final now = DateTime.now();
      final id = await _db.insert('pest_logs', {
        'station_id': station.id,
        'checked_at': now.toIso8601String(),
        'count': count,
        'level': level.name,
        'by_company': byCompany ? 1 : 0,
        'note': note,
        'operator_name': operatorName,
      });
      await _db.update('pest_stations', {'last_checked_at': now.toIso8601String()},
          where: 'id = ?', whereArgs: [station.id]);

      if (level == PestLevel.severe) {
        await _db.insert('non_conformities', {
          'category': 'Infestanti',
          'title': 'Infestazione notevole - ${station.type}',
          'description':
              'Rilevati $count esemplari presso "${station.location}". '
              'Livello: notevole. ${pestSevereActions.join(' ')}',
          'opened_at': now.toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'isolated',
          'source_type': 'pest_log',
          'source_id': id,
        });
      }
      return id;
    });
  }

  Future<List<PestLog>> getPestLogs({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('l.checked_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('l.checked_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.rawQuery(
      '''
      SELECT l.*, p.type AS station_type, p.location AS station_location
      FROM pest_logs l
      JOIN pest_stations p ON p.id = l.station_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY l.checked_at DESC
      ''',
      args,
    );
    return rows.map(PestLog.fromMap).toList();
  }

  Future<DateTime?> lastPestMonitoring() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(checked_at) AS last FROM pest_logs',
    );
    final value = rows.firstOrNull?['last'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  // ---------------------------------------------------------------------------
  // Strutture e personale
  // ---------------------------------------------------------------------------

  Future<int> saveStructureCheck({
    required String area,
    required List<StructureCheckItem> items,
    required String operatorName,
  }) async {
    return _write(() async {
      final anomalies = items.where((i) => !i.ok).toList();
      final now = DateTime.now();
      int? ncId;
      if (anomalies.isNotEmpty) {
        ncId = await _db.insert('non_conformities', {
          'category': 'Strutture',
          'title': 'Anomalie strutture - $area',
          'description':
              'Rilevate ${anomalies.length} anomalie: '
              '${anomalies.map((a) => a.label + (a.note.isNotEmpty ? ' (${a.note})' : '')).join('; ')}.',
          'opened_at': now.toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'none',
          'source_type': 'structure_check',
        });
      }
      return _db.insert('structure_checks', {
        'area': area,
        'checked_at': now.toIso8601String(),
        'items_json': StructureCheck.encodeItems(items),
        'has_anomalies': anomalies.isNotEmpty ? 1 : 0,
        'nc_id': ncId,
        'operator_name': operatorName,
      });
    });
  }

  Future<List<StructureCheck>> getStructureChecks({
    DateTime? from,
    DateTime? to,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('checked_at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('checked_at < ?');
      args.add(to.toIso8601String());
    }
    final rows = await _db.query('structure_checks',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args.isEmpty ? null : args,
        orderBy: 'checked_at DESC');
    return rows.map(StructureCheck.fromMap).toList();
  }

  Future<DateTime?> lastStructureCheck() async {
    final rows = await _db.rawQuery(
      'SELECT MAX(checked_at) AS last FROM structure_checks',
    );
    final value = rows.firstOrNull?['last'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  Future<List<StaffMember>> getStaff() async {
    final rows = await _db.query('staff', orderBy: 'name');
    return rows.map(StaffMember.fromMap).toList();
  }

  Future<int> saveStaffMember(StaffMember member, {int? id}) async {
    return _write(() async {
      if (id == null) return _db.insert('staff', member.toMap());
      await _db.update('staff', member.toMap(),
          where: 'id = ?', whereArgs: [id]);
      return id;
    });
  }

  Future<void> deleteStaffMember(int id) async {
    await _write(() async {
      await _db.delete('staff', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Motore "Da fare ora" (dashboard)
  // ---------------------------------------------------------------------------

  Future<DashboardData> getDashboard() async {
    final todos = <TodoItem>[];

    // Attivit\u00E0 giornaliere ordinarie: info (teal), non warning.
    final noReading = await getEquipmentWithoutReadingToday();
    for (final e in noReading) {
      todos.add(TodoItem(
        severity: 2,
        icon: 'thermostat',
        title: 'Registra la temperatura di ${e.name}',
        subtitle: 'Limiti ${e.rangeLabel} \u2022 nessuna lettura oggi',
        target: 'temperature',
      ));
    }

    final tasks = await getCleaningTasks();
    final dueCleanings =
        tasks.where((t) => t.state == CleaningState.dueToday).length;
    final overdueCleanings =
        tasks.where((t) => t.state == CleaningState.overdue).length;
    if (dueCleanings > 0) {
      todos.add(TodoItem(
        severity: 2,
        icon: 'cleaning',
        title: '$dueCleanings attività di pulizia da completare oggi',
        subtitle: 'Conferma con un tocco quando terminate',
        target: 'cleaning',
      ));
    }
    // Pulizie gi\u00E0 in ritardo: warning.
    if (overdueCleanings > 0) {
      todos.add(TodoItem(
        severity: 1,
        icon: 'cleaning',
        title: '$overdueCleanings pulizie periodiche scadute',
        subtitle: 'Pulizie settimanali o mensili oltre la scadenza',
        target: 'cleaning',
      ));
    }

    // Danger: NC aperte.
    final openNc = (await getNonConformities())
        .where((n) => n.isOpen)
        .toList();
    for (final nc in openNc.take(3)) {
      todos.add(TodoItem(
        severity: 0,
        icon: 'nc',
        title: nc.title,
        subtitle: 'Non conformità aperta dal ${fmtDate(nc.openedAt)}',
        target: 'nc',
      ));
    }

    // Danger: formazione scaduta. Warning: in scadenza. Info: mancante.
    final staff = await getStaff();
    final renewalMonths = await getTrainingRenewalMonths();
    for (final s in staff) {
      final status = s.certificateStatus(months: renewalMonths);
      if (status == 'expired') {
        todos.add(TodoItem(
          severity: 0,
          icon: 'staff',
          title: 'Attestato scaduto: ${s.name}',
          subtitle: 'Formazione alimentarista da rifare',
          target: 'staff',
        ));
      } else if (status == 'expiring') {
        todos.add(TodoItem(
          severity: 1,
          icon: 'staff',
          title: 'Attestato in scadenza: ${s.name}',
          subtitle: 'Prenotare l\u2019aggiornamento della formazione',
          target: 'staff',
        ));
      } else if (status == 'missing') {
        todos.add(TodoItem(
          severity: 2,
          icon: 'staff',
          title: 'Attestato mancante: ${s.name}',
          subtitle: 'Registrare la data dell\u2019attestato alimentarista',
          target: 'staff',
        ));
      }
    }

    // Warning: verifiche termometriche gi\u00E0 scadute.
    final equipment = await getEquipment();
    final thermoOverdue = equipment.where((e) => e.thermoCheckOverdue);
    final countThermo = thermoOverdue.length;
    if (countThermo > 0) {
      todos.add(TodoItem(
        severity: 1,
        icon: 'thermometer_check',
        title: 'Verifica termometro da fare',
        subtitle: '$countThermo attrezzature senza verifica negli ultimi '
            '$thermometerCheckIntervalDays giorni (tolleranza \u00B11 \u00B0C)',
        target: 'thermometer',
      ));
    }

    // Danger: lotti gi\u00E0 scaduti. Warning: in scadenza entro 7 giorni.
    final now = DateTime.now();
    final lotsAll = await getLots();
    for (final lot in lotsAll) {
      final expiry = lot.expiresAt;
      if (expiry == null) continue;
      if (expiry.isBefore(now)) {
        todos.add(TodoItem(
          severity: 0,
          icon: 'lot',
          title: 'Lotto scaduto: ${lot.productName} (${lot.code})',
          subtitle: 'Scaduto il ${fmtDate(expiry)}: ritirare ed eliminare',
          target: 'lots',
        ));
      } else if (expiry.isBefore(now.add(const Duration(days: 7)))) {
        todos.add(TodoItem(
          severity: 1,
          icon: 'lot',
          title: 'Lotto in scadenza: ${lot.productName} (${lot.code})',
          subtitle: 'Entro il ${fmtDate(expiry)}',
          target: 'lots',
        ));
      }
    }

    // Warning: monitoraggio infestanti gi\u00E0 oltre i 30 giorni.
    final lastPest = await lastPestMonitoring();
    if (lastPest == null ||
        now.difference(lastPest).inDays > pestCheckIntervalDays) {
      todos.add(TodoItem(
        severity: 1,
        icon: 'pest',
        title: 'Monitoraggio infestanti da eseguire',
        subtitle: lastPest == null
            ? 'Nessun monitoraggio registrato'
            : 'Ultimo controllo oltre $pestCheckIntervalDays giorni fa',
        target: 'pest',
      ));
    }

    final lastStruct = await lastStructureCheck();
    if (lastStruct == null ||
        now.difference(lastStruct).inDays > structureCheckIntervalDays) {
      todos.add(TodoItem(
        severity: 1,
        icon: 'structure',
        title: 'Controllo strutture da eseguire',
        subtitle: 'Cadenza semestrale (Allegato VII): gi\u00E0 oltre termine',
        target: 'structure',
      ));
    }

    // Moduli MGSA: pasto campione da smaltire (warning), acqua (warning se
    // in ritardo), cultura annuale (warning se in ritardo), ghiaccio mensile.
    if (await isModuleEnabled('module_samples')) {
      final samples = await getSampleMeals();
      final pending = samples.where((s) => s.isPendingDisposal).length;
      if (pending > 0) {
        todos.add(TodoItem(
          severity: 1,
          icon: 'sample',
          title: '$pending pasti campione da smaltire',
          subtitle: 'Conservazione 72 ore scaduta (PR CAMP 01)',
          target: 'samples',
        ));
      }
    }

    if (await isModuleEnabled('module_water')) {
      final lastAnalysis = await lastWaterCheckOfKind('analisi');
      if (lastAnalysis == null ||
          now.difference(lastAnalysis).inDays > 365) {
        todos.add(TodoItem(
          severity: lastAnalysis == null ? 2 : 1,
          icon: 'water',
          title: 'Analisi microbiologica dell\u2019acqua',
          subtitle: 'Cadenza annuale (PR APO)',
          target: 'water',
        ));
      }
      final lastIce = await lastWaterCheckOfKind('ghiaccio');
      if (lastIce == null ||
          now.difference(lastIce).inDays > 30) {
        todos.add(TodoItem(
          severity: lastIce == null ? 2 : 1,
          icon: 'water',
          title: 'Sanificazione produttore di ghiaccio',
          subtitle: 'Cadenza mensile (PR APO)',
          target: 'water',
        ));
      }
    }

    if (await isModuleEnabled('module_culture')) {
      final lastVerification = await lastCultureVerification();
      if (lastVerification == null ||
          now.difference(lastVerification).inDays > 365) {
        todos.add(TodoItem(
          severity: lastVerification == null ? 2 : 1,
          icon: 'culture',
          title: 'Verifica annuale della cultura della sicurezza',
          subtitle: 'Reg. UE 2021/382: politica, comunicazioni, verifica',
          target: 'culture',
        ));
      }
    }

    final company = await getCompany();
    if (!company.isComplete) {
      todos.add(TodoItem(
        severity: 2,
        icon: 'company',
        title: 'Completa l\u2019anagrafica azienda',
        subtitle: 'Ragione sociale e responsabile HACCP servono per i PDF',
        target: 'company',
      ));
    }

    todos.sort((a, b) => a.severity.compareTo(b.severity));

    // Progresso giornaliero: letture + pulizie giornaliere.
    final todayLogs = await getTodayTemperatureLogs();
    final equipmentIds = equipment.map((e) => e.id).toSet();
    final readEquipment = todayLogs
        .map((l) => l.equipmentId)
        .where(equipmentIds.contains)
        .toSet();
    final dailyTasks = tasks
        .where((t) => t.requiredPerDay > 0)
        .toList();
    final dailyDone = dailyTasks
        .where((t) => t.state == CleaningState.done)
        .length;

    final doneCount = readEquipment.length + dailyDone;
    final totalCount = equipment.length + dailyTasks.length;

    final lots = await getLots(
        from: DateTime.now().subtract(const Duration(days: 3650)));
    final receipts = await getReceipts(
        from: DateTime.now().subtract(const Duration(days: 3650)));

    return DashboardData(
      todos: todos,
      doneCount: totalCount == 0 ? 1 : doneCount,
      totalCount: totalCount,
      company: company,
      openNc: openNc.length,
      temperatureCount: todayLogs.length,
      lotsCount: lots.length,
      receiptsCount: receipts.length,
      onboardingProgress: await onboardingProgress(),
      onboardingStep: await firstIncompleteOnboardingStep(),
    );
  }

  // ---------------------------------------------------------------------------
  // Backup
  // ---------------------------------------------------------------------------

  Future<void> closeForBackup() => database.close();

  // ---------------------------------------------------------------------------
  // Allegati
  // ---------------------------------------------------------------------------

  Future<int> addAttachment(Attachment attachment) async {
    return _write(() async {
      return _db.insert('attachments', attachment.toMap());
    });
  }

  Future<List<Attachment>> getAttachments(
    String entityType,
    int entityId,
  ) async {
    final rows = await _db.query(
      'attachments',
      where: 'entity_type = ? AND entity_id = ?',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
    );
    return rows.map(Attachment.fromMap).toList();
  }

  /// Numero di allegati per ogni id entit\u00E0 (per i badge sulle card).
  Future<Map<int, int>> getAttachmentCounts(String entityType) async {
    final rows = await _db.rawQuery(
      'SELECT entity_id, COUNT(*) AS n FROM attachments '
      'WHERE entity_type = ? GROUP BY entity_id',
      [entityType],
    );
    return {
      for (final row in rows)
        (row['entity_id'] as num).toInt(): (row['n'] as num).toInt(),
    };
  }

  Future<void> deleteAttachment(int id, {String? localPath}) async {
    await _write(() async {
      await _db.delete('attachments', where: 'id = ?', whereArgs: [id]);
    });
    if (localPath != null) {
      try {
        final file = File(localPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Il file può essere già stato rimosso.
      }
    }
  }

  Future<void> updateAttachmentSync({
    required int id,
    String? cloudId,
    DateTime? syncedAt,
  }) async {
    await _write(() async {
      await _db.update(
        'attachments',
        {
          'cloud_id': cloudId,
          'synced_at': syncedAt?.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Logo azienda: ultimo allegato foto dell'entit\u00E0 company.
  Future<Attachment?> getCompanyLogo() async {
    final rows = await _db.query(
      'attachments',
      where: "entity_type = 'company' AND kind = 'photo'",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Attachment.fromMap(rows.first);
  }

  /// Allegati fotografici dei ricevimenti respinti e delle NC aperte/chiuse
  /// nel periodo (per l'appendice fotografica del dossier).
  Future<List<(Attachment, String)>> getDossierPhotos({
    required List<Receipt> receipts,
    required List<NonConformity> ncs,
  }) async {
    final result = <(Attachment, String)>[];
    final db = _db;
    for (final r in receipts.where((r) => r.isRejected)) {
      final rows = await db.query('attachments',
          where:
              "entity_type = 'receipt' AND entity_id = ? AND kind = 'photo'",
          whereArgs: [r.id]);
      for (final row in rows) {
        result.add((
          Attachment.fromMap(row),
          'Merce respinta: ${r.product} (${r.supplierName})',
        ));
      }
    }
    for (final nc in ncs) {
      final rows = await db.query('attachments',
          where:
              "entity_type = 'nonconformity' AND entity_id = ? AND kind = 'photo'",
          whereArgs: [nc.id]);
      for (final row in rows) {
        result.add((Attachment.fromMap(row), 'NC: ${nc.title}'));
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Coda di sincronizzazione cloud
  // ---------------------------------------------------------------------------

  Future<void> enqueueSync({
    required String kind,
    required String localPath,
    required String remoteFolder,
  }) async {
    await _write(() async {
      await _db.insert('sync_queue', {
        'kind': kind,
        'local_path': localPath,
        'remote_folder': remoteFolder,
        'attempts': 0,
        'last_error': null,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
  }

  Future<List<Map<String, Object?>>> getSyncQueue() {
    return _db.query('sync_queue', orderBy: 'created_at');
  }

  Future<void> updateSyncQueueEntry(int id,
      {int? attempts, String? lastError}) async {
    await _write(() async {
      await _db.update(
        'sync_queue',
        {
          'attempts': attempts,
          'last_error': lastError,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<void> dequeueSync(int id) async {
    await _write(() async {
      await _db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // Wizard: applicazione idempotente
  // ---------------------------------------------------------------------------

  /// Sostituisce le righe create dal wizard per una tabella, senza toccare
  /// quelle create o modificate a mano (`source = 'user'`).
  Future<void> _replaceWizardRows(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    await _write(() async {
      await _db.transaction((txn) async {
        await txn.delete(table, where: "source = 'wizard'");
        for (final row in rows) {
          await txn.insert(table, {...row, 'source': 'wizard'});
        }
      });
    });
  }

  Future<void> applyWizardEquipment(
    List<({
      String key,
      String name,
      String type,
      double minTemp,
      double maxTemp,
      String location
    })> equipmentList,
  ) async {
    await _replaceWizardRows('equipment', [
      for (final e in equipmentList)
        {
          'name': e.name,
          'type': e.type,
          'min_temp': e.minTemp,
          'max_temp': e.maxTemp,
          'location': e.location,
          'notes': '',
          'thermo_verified_at': null,
          'active': 1,
          'template_key': e.key,
        },
    ]);
  }

  Future<void> applyWizardCleaning(
    List<({
      String key,
      String area,
      String title,
      String freqCode,
      String? productName,
      String? method
    })> cleaningList,
  ) async {
    await _replaceWizardRows('cleaning_tasks', [
      for (final c in cleaningList)
        {
          'area': c.area,
          'title': c.title,
          'frequency': CleaningFrequency.fromCode(c.freqCode).label,
          'freq_code': c.freqCode,
          'product_name': c.productName,
          'method': c.method,
          'last_completed_at': null,
          'active': 1,
          'template_key': c.key,
        },
    ]);
  }

  Future<void> applyWizardProducts(
    List<({
      String key,
      String name,
      List<String> allergens,
      String category,
      int shelfLifeDays
    })> productList,
  ) async {
    await _replaceWizardRows('products', [
      for (final p in productList)
        {
          'name': p.name,
          'category': p.category,
          'ingredients': '',
          'shelf_life_days': p.shelfLifeDays,
          'storage': '',
          'allergens': allergenCodesToCsv(p.allergens),
          'template_key': p.key,
        },
    ]);
  }

  Future<void> applyWizardPestStations(
    List<({String key, String type, String location})> pestList,
  ) async {
    await _replaceWizardRows('pest_stations', [
      for (final p in pestList)
        {
          'type': p.type,
          'location': p.location,
          'active': 1,
          'last_checked_at': null,
          'template_key': p.key,
        },
    ]);
  }

  // ---------------------------------------------------------------------------
  // Moduli MGSA-0415
  // ---------------------------------------------------------------------------

  /// Limite configurabile con default (double).
  Future<double> getLimit(String key, double fallback) async {
    final raw = await getSetting(key);
    return double.tryParse(raw.replaceAll(',', '.')) ?? fallback;
  }

  /// Limite configurabile con default (int).
  Future<int> getLimitInt(String key, int fallback) async {
    final raw = await getSetting(key);
    return int.tryParse(raw) ?? fallback;
  }

  Future<bool> isModuleEnabled(String key) async =>
      await getSetting(key, fallback: '0') == '1';

  // Cottura e rigenerazione ------------------------------------------------

  /// Registra una cottura/rigenerazione: se non conforme apre la NC.
  Future<bool> saveCookingLog({
    required String kind,
    required String category,
    required double coreTemp,
    required String operatorName,
    String foodName = '',
    String? correctiveAction,
  }) async {
    final minTemp = kind == 'rigenerazione'
        ? await getLimit('limit_regen_core_min', 65)
        : await getLimit('limit_cooking_core_min', 75);
    final compliant = coreTemp >= minTemp;

    await _write(() async {
      await _db.insert('cooking_logs', {
        'cooked_at': DateTime.now().toIso8601String(),
        'kind': kind,
        'category': category,
        'food_name': foodName,
        'core_temp': coreTemp,
        'compliant': compliant ? 1 : 0,
        'corrective_action': correctiveAction,
        'operator_name': operatorName,
      });

      if (!compliant) {
        await _db.insert('non_conformities', {
          'category': 'Temperatura',
          'title':
              '$category non conforme (${coreTemp.toStringAsFixed(1)} \u00B0C al cuore)',
          'description':
              'Temperatura al cuore sotto il limite di ${minTemp.toStringAsFixed(0)} '
              '\u00B0C (${kind == 'rigenerazione' ? 'rigenerazione' : 'cottura'}).',
          'corrective_action': correctiveAction,
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'cooked',
          'source_type': 'cooking_log',
        });
      }
    });
    return compliant;
  }

  Future<List<CookingLog>> getCookingLogs({DateTime? from, DateTime? to}) async {
    final rows = await _rangeQuery('cooking_logs', 'cooked_at', from, to);
    return rows.map(CookingLog.fromMap).toList();
  }

  Future<int> saveOilValidation({
    required String fryer,
    required double tempC,
    required bool sensoryOk,
    required bool oilChanged,
    required String operatorName,
    String? note,
  }) async {
    final maxTemp = await getLimit('limit_fryer_max', 180);
    return _write(() async {
      return _db.insert('oil_validations', {
        'validated_at': DateTime.now().toIso8601String(),
        'fryer': fryer,
        'temp_c': tempC,
        'sensory_ok': sensoryOk ? 1 : 0,
        'oil_changed': oilChanged ? 1 : 0,
        'note': note,
        'operator_name': operatorName,
        // La temperatura oltre il limite viene segnalata nel registro.
      }).then((id) async {
        if (tempC > maxTemp) {
          await _db.insert('non_conformities', {
            'category': 'Temperatura',
            'title': 'Frittura oltre $maxTemp \u00B0C ($fryer)',
            'description':
                'Temperatura olio ${tempC.toStringAsFixed(0)} \u00B0C: oltre il '
                'limite di ${maxTemp.toStringAsFixed(0)} \u00B0C (PR COT 02).',
            'opened_at': DateTime.now().toIso8601String(),
            'status': 'Aperta',
            'operator_name': operatorName,
            'disposition': 'none',
            'source_type': 'oil_validation',
            'source_id': id,
          });
        }
        return id;
      });
    });
  }

  Future<List<OilValidation>> getOilValidations({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _rangeQuery('oil_validations', 'validated_at', from, to);
    return rows.map(OilValidation.fromMap).toList();
  }

  // Abbattimento -----------------------------------------------------------

  /// Registra un ciclo di abbattimento e valuta la conformit\u00E0.
  Future<bool> saveBlastChillCycle({
    required String product,
    required String kind,
    required DateTime startedAt,
    required DateTime endedAt,
    required double tEnd,
    required String operatorName,
    double? tStart,
    String? note,
  }) async {
    final isPositive = kind == 'positivo';
    final targetTemp = await getLimit(
      isPositive ? 'limit_abb_pos_temp' : 'limit_abb_neg_temp',
      isPositive ? 3.0 : -18.0,
    );
    final maxHours = await getLimitInt(
      isPositive ? 'limit_abb_pos_hours' : 'limit_abb_neg_hours',
      2,
    );
    final hours = endedAt.difference(startedAt).inMinutes / 60.0;
    final tempOk =
        isPositive ? tEnd <= targetTemp : tEnd <= targetTemp;
    final compliant = tempOk && hours <= maxHours;

    await _write(() async {
      await _db.insert('blast_chill_cycles', {
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt.toIso8601String(),
        'product': product,
        'kind': kind,
        't_start': tStart,
        't_end': tEnd,
        'compliant': compliant ? 1 : 0,
        'operator_name': operatorName,
        'note': note,
      });

      if (!compliant) {
        await _db.insert('non_conformities', {
          'category': 'Temperatura',
          'title': 'Abbattimento non conforme: $product',
          'description':
              'Ciclo ${isPositive ? 'positivo' : 'negativo'}: ${tEnd.toStringAsFixed(1)} '
              '\u00B0C in ${hours.toStringAsFixed(1)} h (riferimento '
              '${targetTemp.toStringAsFixed(0)} \u00B0C entro $maxHours h). '
              'Azione: ritiro e distruzione del prodotto (PR ABB).',
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'disposed',
          'source_type': 'blast_chill',
        });
      }
    });
    return compliant;
  }

  Future<List<BlastChillCycle>> getBlastChillCycles({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows =
        await _rangeQuery('blast_chill_cycles', 'started_at', from, to);
    return rows.map(BlastChillCycle.fromMap).toList();
  }

  // Trasporto e mantenimento -----------------------------------------------

  Future<bool> saveTransportLog({
    required String destination,
    required bool vehicleClean,
    required bool containersSanitized,
    required String operatorName,
    double? tempColdStart,
    double? tempColdArrival,
    double? tempHotStart,
    double? tempHotArrival,
    String? note,
  }) async {
    final coldMax = await getLimit('limit_transport_cold_max', 10);
    final hotMin = await getLimit('limit_transport_hot_min', 65);
    final coldOk = tempColdArrival == null || tempColdArrival <= coldMax;
    final hotOk = tempHotArrival == null || tempHotArrival >= hotMin;
    final compliant = vehicleClean && containersSanitized && coldOk && hotOk;

    await _write(() async {
      await _db.insert('transport_logs', {
        'done_at': DateTime.now().toIso8601String(),
        'destination': destination,
        'temp_cold_start': tempColdStart,
        'temp_cold_arrival': tempColdArrival,
        'temp_hot_start': tempHotStart,
        'temp_hot_arrival': tempHotArrival,
        'vehicle_clean': vehicleClean ? 1 : 0,
        'containers_sanitized': containersSanitized ? 1 : 0,
        'compliant': compliant ? 1 : 0,
        'operator_name': operatorName,
        'note': note,
      });

      if (!compliant) {
        await _db.insert('non_conformities', {
          'category': 'Temperatura',
          'title': 'Trasporto/somministrazione non conforme',
          'description':
              'Destinazione: ${destination.isEmpty ? '\u2014' : destination}. '
              '${!vehicleClean ? 'Automezzo non pulito. ' : ''}'
              '${!containersSanitized ? 'Contenitori non sanificati. ' : ''}'
              '${!coldOk ? 'Freddi in arrivo oltre $coldMax \u00B0C. ' : ''}'
              '${!hotOk ? 'Caldi in arrivo sotto $hotMin \u00B0C. ' : ''}'
              '(PR TRA / PR SOM).',
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'isolated',
          'source_type': 'transport_log',
        });
      }
    });
    return compliant;
  }

  Future<List<TransportLog>> getTransportLogs({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows = await _rangeQuery('transport_logs', 'done_at', from, to);
    return rows.map(TransportLog.fromMap).toList();
  }

  // Pasto campione -----------------------------------------------------------

  Future<int> saveSampleMeal({
    required String dish,
    required double grams,
    required String operatorName,
  }) async {
    final hours = await getLimitInt('limit_sample_hours', 72);
    final discardAfter = DateTime.now().add(Duration(hours: hours));
    return _write(() async {
      return _db.insert('sample_meals', {
        'taken_at': DateTime.now().toIso8601String(),
        'dish': dish,
        'grams': grams,
        'discard_after': discardAfter.toIso8601String(),
        'discarded_at': null,
        'operator_name': operatorName,
      });
    });
  }

  Future<List<SampleMeal>> getSampleMeals() async {
    final rows = await _db
        .query('sample_meals', orderBy: 'taken_at DESC', limit: 60);
    return rows.map(SampleMeal.fromMap).toList();
  }

  Future<void> discardSample(int id) async {
    await _write(() async {
      await _db.update(
        'sample_meals',
        {'discarded_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // Acqua e ghiaccio ---------------------------------------------------------

  Future<int> saveWaterCheck({
    required String kind,
    required bool resultOk,
    required String operatorName,
    String? note,
  }) async {
    return _write(() async {
      final id = await _db.insert('water_checks', {
        'checked_at': DateTime.now().toIso8601String(),
        'kind': kind,
        'result_ok': resultOk ? 1 : 0,
        'note': note,
        'operator_name': operatorName,
      });
      if (!resultOk && kind == 'analisi') {
        await _db.insert('non_conformities', {
          'category': 'Altro',
          'title': 'Analisi acqua non conforme (PR APO)',
          'description':
              note?.isNotEmpty == true ? note! : 'Esito analisi non conforme.',
          'opened_at': DateTime.now().toIso8601String(),
          'status': 'Aperta',
          'operator_name': operatorName,
          'disposition': 'none',
          'source_type': 'water_check',
          'source_id': id,
        });
      }
      return id;
    });
  }

  Future<List<WaterCheck>> getWaterChecks({DateTime? from, DateTime? to}) async {
    final rows = await _rangeQuery('water_checks', 'checked_at', from, to);
    return rows.map(WaterCheck.fromMap).toList();
  }

  Future<DateTime?> lastWaterCheckOfKind(String kind) async {
    final rows = await _db.rawQuery(
      'SELECT MAX(checked_at) AS last FROM water_checks WHERE kind = ?',
      [kind],
    );
    final value = rows.firstOrNull?['last'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  // Ritiro/richiamo -----------------------------------------------------------

  Future<int> createWithdrawal({
    required String lotCode,
    required String clients,
    required String actions,
    required bool aslNotified,
    required String operatorName,
  }) async {
    return _write(() async {
      return _db.insert('withdrawals', {
        'started_at': DateTime.now().toIso8601String(),
        'lot_code': lotCode,
        'clients': clients,
        'actions': actions,
        'asl_notified': aslNotified ? 1 : 0,
        'outcome': 'in_corso',
        'operator_name': operatorName,
      });
    });
  }

  Future<void> closeWithdrawal(int id) async {
    await _write(() async {
      await _db.update(
        'withdrawals',
        {
          'outcome': 'concluso',
          'closed_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<Withdrawal>> getWithdrawals() async {
    final rows = await _db.query('withdrawals', orderBy: 'started_at DESC');
    return rows.map(Withdrawal.fromMap).toList();
  }

  // Cultura della sicurezza alimentare ---------------------------------------

  Future<int> saveCultureEntry({
    required String kind,
    required String title,
    required String operatorName,
    String? notes,
  }) async {
    return _write(() async {
      return _db.insert('culture_log', {
        'kind': kind,
        'title': title,
        'notes': notes,
        'done_at': DateTime.now().toIso8601String(),
        'operator_name': operatorName,
      });
    });
  }

  Future<List<CultureLogEntry>> getCultureEntries() async {
    final rows = await _db.query('culture_log', orderBy: 'done_at DESC');
    return rows.map(CultureLogEntry.fromMap).toList();
  }

  Future<DateTime?> lastCultureVerification() async {
    final rows = await _db.rawQuery(
      "SELECT MAX(done_at) AS last FROM culture_log WHERE kind = 'verifica'",
    );
    final value = rows.firstOrNull?['last'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  // Contaminazione crociata ---------------------------------------------------

  Future<int> saveCrossContaminationCheck({
    required String equipment,
    required bool residueFound,
    required String operatorName,
    String? action,
  }) async {
    return _write(() async {
      return _db.insert('cross_contamination_checks', {
        'checked_at': DateTime.now().toIso8601String(),
        'equipment': equipment,
        'residue_found': residueFound ? 1 : 0,
        'action': action,
        'operator_name': operatorName,
      });
    });
  }

  Future<List<CrossContaminationCheck>> getCrossContaminationChecks({
    DateTime? from,
    DateTime? to,
  }) async {
    final rows =
        await _rangeQuery('cross_contamination_checks', 'checked_at', from, to);
    return rows.map(CrossContaminationCheck.fromMap).toList();
  }

  // Donazioni (ridistribuzione) -----------------------------------------------

  Future<int> saveDonation({
    required String product,
    required String entity,
    required String operatorName,
    double? quantity,
    String? unit,
    String? stateNote,
  }) async {
    return _write(() async {
      return _db.insert('donations', {
        'donated_at': DateTime.now().toIso8601String(),
        'product': product,
        'quantity': quantity,
        'unit': unit,
        'entity': entity,
        'state_note': stateNote,
        'operator_name': operatorName,
      });
    });
  }

  Future<List<Donation>> getDonations({DateTime? from, DateTime? to}) async {
    final rows = await _rangeQuery('donations', 'donated_at', from, to);
    return rows.map(Donation.fromMap).toList();
  }

  /// Query per periodo su una tabella con colonna data.
  Future<List<Map<String, Object?>>> _rangeQuery(
    String table,
    String dateColumn,
    DateTime? from,
    DateTime? to,
  ) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('$dateColumn >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('$dateColumn < ?');
      args.add(to.toIso8601String());
    }
    return _db.query(
      table,
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: '$dateColumn DESC',
    );
  }

  // ---------------------------------------------------------------------------
  // Stato onboarding
  // ---------------------------------------------------------------------------

  Future<int> getOnboardingStep() async {
    final value = await getSetting('onboarding_step');
    return int.tryParse(value) ?? 0;
  }

  Future<void> setOnboardingStep(int step) =>
      setSetting('onboarding_step', '$step');

  Future<bool> isOnboardingDone() async =>
      await getSetting('onboarding_done') == '1';

  Future<void> setOnboardingDone() async {
    await setSetting('onboarding_done', '1');
    await setSetting(
      'onboarding_completed_at',
      DateTime.now().toIso8601String(),
    );
  }

  /// Percentuale di configurazione completata, da dati reali.
  Future<int> onboardingProgress() async {
    final checks = <Future<bool>>[
      getSetting('terms_accepted_at').then((v) => v.isNotEmpty),
      getCompany().then((c) => c.name.trim().isNotEmpty && c.vat.isNotEmpty),
      getCompany().then((c) => c.haccpManager.trim().isNotEmpty),
      getEquipment().then((l) => l.isNotEmpty),
      getCleaningTasks().then((l) => l.isNotEmpty),
      getProducts().then((l) => l.isNotEmpty),
      getPestStations().then((l) => l.isNotEmpty),
      getStaff().then((l) => l.isNotEmpty),
      getSetting('cloud_provider').then((v) => v.isNotEmpty),
      getSetting('reminder_temperature_morning').then((v) => v.isNotEmpty),
    ];
    final results = await Future.wait(checks);
    final done = results.where((v) => v).length;
    return (done * 100 / checks.length).round();
  }

  /// Primo passo del wizard ancora da completare (0 se va rifatto).
  Future<int> firstIncompleteOnboardingStep() async {
    if (await getSetting('terms_accepted_at') == '') return 0;
    if (await getSetting('onboarding_business_types') == '') return 1;
    final company = await getCompany();
    if (company.name.trim().isEmpty || company.vat.isEmpty) return 2;
    if (company.haccpManager.trim().isEmpty) return 3;
    if ((await getEquipment()).isEmpty) return 4;
    if ((await getCleaningTasks()).isEmpty) return 5;
    if ((await getPestStations()).isEmpty) return 6;
    if (await getSetting('cloud_provider') == '') return 9;
    if (await getSetting('reminder_temperature_morning') == '') return 10;
    return 12;
  }
}

class TraceabilityResult {
  const TraceabilityResult({required this.lots, required this.receipts});

  final List<ProductionLot> lots;
  final List<Receipt> receipts;

  bool get isEmpty => lots.isEmpty && receipts.isEmpty;
}
