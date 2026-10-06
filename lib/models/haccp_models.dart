import '../core/constants/haccp_rules.dart';

/// Accesso tipizzato alle righe del database.
extension RowX on Map<String, Object?> {
  String str(String key, [String fallback = '']) =>
      (this[key] as String?) ?? fallback;

  String? strOrNull(String key) {
    final v = this[key] as String?;
    if (v == null || v.trim().isEmpty) return null;
    return v;
  }

  double? dbl(String key) => (this[key] as num?)?.toDouble();

  int integer(String key, [int fallback = 0]) =>
      (this[key] as num?)?.toInt() ?? fallback;

  int? intOrNull(String key) => (this[key] as num?)?.toInt();

  bool flag(String key) => integer(key) == 1;

  DateTime? dt(String key) {
    final v = this[key] as String?;
    if (v == null || v.isEmpty) return null;
    return DateTime.tryParse(v);
  }

  DateTime dtOr(String key, DateTime fallback) => dt(key) ?? fallback;
}

// -----------------------------------------------------------------------------
// Anagrafica azienda
// -----------------------------------------------------------------------------

class CompanyProfile {
  const CompanyProfile({
    this.name = 'La mia attività',
    this.address = '',
    this.city = '',
    this.vat = '',
    this.haccpManager = '',
    this.haccpSubstitute = '',
    this.phone = '',
    this.email = '',
    this.pec = '',
    this.healthNotification = '',
    this.ateco = '',
    this.activity = '',
    this.defaultOperator = 'Operatore',
  });

  final String name;
  final String address;
  final String city;
  final String vat;
  final String haccpManager;
  final String haccpSubstitute;
  final String phone;
  final String email;
  final String pec;
  final String healthNotification;
  final String ateco;
  final String activity;
  final String defaultOperator;

  /// Servono ragione sociale e responsabile HACCP per intestare i PDF.
  bool get isComplete =>
      name.trim().isNotEmpty && haccpManager.trim().isNotEmpty;

  factory CompanyProfile.fromMap(Map<String, Object?> map) => CompanyProfile(
        name: map.str('company_name'),
        address: map.str('company_address'),
        city: map.str('company_city'),
        vat: map.str('company_vat'),
        haccpManager: map.str('company_haccp_manager'),
        haccpSubstitute: map.str('company_haccp_substitute'),
        phone: map.str('company_phone'),
        email: map.str('company_email'),
        pec: map.str('company_pec'),
        healthNotification: map.str('company_health_notification'),
        ateco: map.str('company_ateco'),
        activity: map.str('company_activity'),
        defaultOperator: map.str('default_operator', 'Operatore'),
      );

  Map<String, String> get settingsMap => {
        'company_name': name,
        'company_address': address,
        'company_city': city,
        'company_vat': vat,
        'company_haccp_manager': haccpManager,
        'company_haccp_substitute': haccpSubstitute,
        'company_phone': phone,
        'company_email': email,
        'company_pec': pec,
        'company_health_notification': healthNotification,
        'company_ateco': ateco,
        'company_activity': activity,
        'default_operator': defaultOperator,
      };
}

// -----------------------------------------------------------------------------
// Attrezzature e temperature (PRP 11)
// -----------------------------------------------------------------------------

class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.type,
    required this.minTemp,
    required this.maxTemp,
    this.location = '',
    this.notes = '',
    this.thermoVerifiedAt,
    this.active = true,
    this.tempSource = 'manual',
    this.sensorId,
  });

  final int id;
  final String name;
  final String type;
  final double minTemp;
  final double maxTemp;
  final String location;
  final String notes;
  final DateTime? thermoVerifiedAt;
  final bool active;

  /// Sorgente della temperatura: 'manual' (default, comportamento storico)
  /// oppure 'sensor' (attrezzatura collegata a un sensore).
  final String tempSource;

  /// Sensore collegato (null se manuale): un sensore appartiene a UNA sola
  /// attrezzatura (indice univoco parziale nel DB).
  final int? sensorId;

  bool get usesSensor => tempSource == 'sensor' && sensorId != null;

  bool isCompliant(double t) => t >= minTemp && t <= maxTemp;

  String get rangeLabel =>
      '${minTemp.toStringAsFixed(0)} / ${maxTemp.toStringAsFixed(0)} °C';

  bool get thermoCheckOverdue {
    final v = thermoVerifiedAt;
    if (v == null) return true;
    return DateTime.now().difference(v).inDays > thermometerCheckIntervalDays;
  }

  /// NOTA: temp_source/sensor_id NON sono inclusi volutamente: il salvataggio
  /// dell'anagrafica non deve sovrascrivere il collegamento del sensore
  /// (si gestisce con linkSensor/unlinkSensor).
  Map<String, Object?> toMap() => {
        'name': name,
        'type': type,
        'min_temp': minTemp,
        'max_temp': maxTemp,
        'location': location,
        'notes': notes,
        'thermo_verified_at': thermoVerifiedAt?.toIso8601String(),
      };

  factory Equipment.fromMap(Map<String, Object?> map) => Equipment(
        id: map.integer('id'),
        name: map.str('name'),
        type: map.str('type'),
        minTemp: map.dbl('min_temp') ?? 0,
        maxTemp: map.dbl('max_temp') ?? 4,
        location: map.str('location'),
        notes: map.str('notes'),
        thermoVerifiedAt: map.dt('thermo_verified_at'),
        active: map.flag('active'),
        tempSource: map.str('temp_source', 'manual'),
        sensorId: map.intOrNull('sensor_id'),
      );
}

/// Sensore collegato a un'attrezzatura (oggi Govee H5179; in futuro altri
/// modelli tramite il catalogo in `lib/core/sensors/`).
class Sensor {
  const Sensor({
    required this.id,
    required this.modelId,
    required this.deviceKey,
    required this.createdAt,
    this.systemId,
    this.label,
    this.lastTemp,
    this.lastHumidity,
    this.lastSeen,
    this.battery,
    this.enabled = true,
    this.calibrationOffset = 0,
    this.lastVerifiedAt,
  });

  final int id;

  /// Modello ('govee_h5179'): vede il catalogo `sensorRegistry`.
  final String modelId;

  /// Chiave stabile del sensore: suffisso normalizzato del nome
  /// pubblicizzato (es. `AB12`); su iOS l'ID BLE cambia per telefono.
  final String deviceKey;
  final String? systemId;
  final String? label;
  final double? lastTemp;
  final double? lastHumidity;
  final DateTime? lastSeen;
  final int? battery;
  final bool enabled;

  /// Offset di calibrazione in °C (−3…+3, passo 0,1): SEMPRE visibile e
  /// registrato insieme al dato (sensor_raw + sensor_offset nel log).
  final double calibrationOffset;

  /// Ultima verifica con termometro di riferimento (tolleranza ±1 °C).
  final DateTime? lastVerifiedAt;

  final DateTime createdAt;

  /// Etichetta utente o, in assenza, la chiave del dispositivo.
  String get displayName =>
      (label == null || label!.trim().isEmpty) ? deviceKey : label!.trim();

  /// true se la verifica con termometro è assente o scaduta (stessa cadenza
  /// della verifica termometri).
  bool get verificationOverdue {
    final v = lastVerifiedAt;
    if (v == null) return true;
    return DateTime.now().difference(v).inDays >
        thermometerCheckIntervalDays;
  }

  factory Sensor.fromMap(Map<String, Object?> map) => Sensor(
        id: map.integer('id'),
        modelId: map.str('model_id'),
        deviceKey: map.str('device_key'),
        systemId: map.strOrNull('system_id'),
        label: map.strOrNull('label'),
        lastTemp: map.dbl('last_temp'),
        lastHumidity: map.dbl('last_humidity'),
        lastSeen: map.dt('last_seen'),
        battery: map.intOrNull('battery'),
        enabled: map.flag('enabled'),
        calibrationOffset: map.dbl('calibration_offset') ?? 0,
        createdAt: map.dtOr('created_at', DateTime.now()),
        lastVerifiedAt: map.dt('last_verified_at'),
      );
}

class TemperatureLog {
  const TemperatureLog({
    required this.id,
    required this.equipmentId,
    required this.temperature,
    required this.measuredAt,
    required this.operatorName,
    required this.compliant,
    this.note,
    this.correctiveAction,
    this.equipmentName,
    this.minTemp,
    this.maxTemp,
    this.source = 'manual',
    this.sensorId,
    this.sensorLabel,
    this.sensorOffset,
    this.sensorRaw,
    this.sensorReadingAt,
  });

  final int id;
  final int equipmentId;
  final double temperature;
  final DateTime measuredAt;
  final String operatorName;
  final bool compliant;
  final String? note;
  final String? correctiveAction;
  final String? equipmentName;
  final double? minTemp;
  final double? maxTemp;

  /// 'manual' (operatore) o 'sensor' (acquisita dal sensore e confermata).
  final String source;
  final int? sensorId;

  /// Istantanea del sensore al momento del salvataggio: etichetta e offset
  /// restano nel log anche se il sensore viene eliminato.
  final String? sensorLabel;
  final double? sensorOffset;

  /// Valore grezzo del sensore PRIMA dell'offset di calibrazione.
  final double? sensorRaw;
  final DateTime? sensorReadingAt;

  bool get fromSensor => source == 'sensor';

  /// Etichetta della sorgente per PDF e liste.
  String get sourceLabel =>
      fromSensor ? 'Sensore ${sensorLabel ?? ''}'.trim() : 'Manuale';

  factory TemperatureLog.fromMap(Map<String, Object?> map) => TemperatureLog(
        id: map.integer('id'),
        equipmentId: map.integer('equipment_id'),
        temperature: map.dbl('temperature') ?? 0,
        measuredAt: map.dtOr('measured_at', DateTime.now()),
        operatorName: map.str('operator_name', 'Operatore'),
        compliant: map.flag('compliant'),
        note: map.strOrNull('note'),
        correctiveAction: map.strOrNull('corrective_action'),
        equipmentName: map.strOrNull('equipment_name'),
        minTemp: map.dbl('min_temp'),
        maxTemp: map.dbl('max_temp'),
        source: map.str('source', 'manual'),
        sensorId: map.intOrNull('sensor_id'),
        sensorLabel: map.strOrNull('sensor_label'),
        sensorOffset: map.dbl('sensor_offset'),
        sensorRaw: map.dbl('sensor_raw'),
        sensorReadingAt: map.dt('sensor_reading_at'),
      );
}

class ThermometerCheck {
  const ThermometerCheck({
    required this.id,
    required this.equipmentId,
    required this.referenceTemp,
    required this.instrumentTemp,
    required this.checkedAt,
    required this.operatorName,
    this.equipmentName,
  });

  final int id;
  final int equipmentId;
  final double referenceTemp;
  final double instrumentTemp;
  final DateTime checkedAt;
  final String operatorName;
  final String? equipmentName;

  double get deviation => (instrumentTemp - referenceTemp).abs();

  /// true se lo strumento va riparato o sostituito.
  bool get mustReplace => deviation > thermometerReplaceThreshold;

  factory ThermometerCheck.fromMap(Map<String, Object?> map) =>
      ThermometerCheck(
        id: map.integer('id'),
        equipmentId: map.integer('equipment_id'),
        referenceTemp: map.dbl('reference_temp') ?? 0,
        instrumentTemp: map.dbl('instrument_temp') ?? 0,
        checkedAt: map.dtOr('checked_at', DateTime.now()),
        operatorName: map.str('operator_name', 'Operatore'),
        equipmentName: map.strOrNull('equipment_name'),
      );
}

// -----------------------------------------------------------------------------
// Pulizie (PRP 2)
// -----------------------------------------------------------------------------

/// Stato di un'attività di pulizia.
enum CleaningState { pending, dueToday, done, upcoming, overdue }

class CleaningTask {
  const CleaningTask({
    required this.id,
    required this.area,
    required this.title,
    required this.frequency,
    this.freqCode = 'daily',
    this.productName,
    this.method,
    this.lastCompletedAt,
    this.active = true,
    this.todayDoneCount = 0,
  });

  final int id;
  final String area;
  final String title;
  final String frequency;
  final String freqCode;
  final String? productName;
  final String? method;
  final DateTime? lastCompletedAt;
  final bool active;

  /// Numero di esecuzioni registrate oggi (per "2 volte al giorno").
  final int todayDoneCount;

  CleaningFrequency get frequencyEnum =>
      CleaningFrequency.fromCode(freqCode);

  int get requiredPerDay => switch (frequencyEnum) {
        CleaningFrequency.twiceDaily => 2,
        CleaningFrequency.afterUse => 1,
        CleaningFrequency.daily => 1,
        _ => 0,
      };

  CleaningState get state {
    final freq = frequencyEnum;
    switch (freq) {
      case CleaningFrequency.afterUse:
      case CleaningFrequency.daily:
      case CleaningFrequency.twiceDaily:
        if (todayDoneCount >= requiredPerDay) return CleaningState.done;
        return CleaningState.dueToday;
      case CleaningFrequency.weekly:
      case CleaningFrequency.monthly:
      case CleaningFrequency.semiannual:
      case CleaningFrequency.annual:
        final last = lastCompletedAt;
        final intervalDays = switch (freq) {
          CleaningFrequency.weekly => 7,
          CleaningFrequency.monthly => 30,
          CleaningFrequency.semiannual => 182,
          CleaningFrequency.annual => 365,
          _ => 0,
        };
        if (last == null) return CleaningState.overdue;
        final days = DateTime.now().difference(last).inDays;
        if (days >= intervalDays) return CleaningState.overdue;
        if (days >= intervalDays - 2) return CleaningState.dueToday;
        return CleaningState.upcoming;
      case CleaningFrequency.asNeeded:
        return CleaningState.upcoming;
    }
  }

  /// Giorni mancanti alla scadenza (negativi se scaduta).
  int? get daysUntilDue {
    final freq = frequencyEnum;
    final last = lastCompletedAt;
    final intervalDays = switch (freq) {
      CleaningFrequency.weekly => 7,
      CleaningFrequency.monthly => 30,
      CleaningFrequency.semiannual => 182,
      CleaningFrequency.annual => 365,
      _ => null,
    };
    if (intervalDays == null) return null;
    if (last == null) return -1;
    return intervalDays - DateTime.now().difference(last).inDays;
  }

  factory CleaningTask.fromMap(Map<String, Object?> map) => CleaningTask(
        id: map.integer('id'),
        area: map.str('area'),
        title: map.str('title'),
        frequency: map.str('frequency'),
        freqCode: map.str('freq_code', 'daily'),
        productName: map.strOrNull('product_name'),
        method: map.strOrNull('method'),
        lastCompletedAt: map.dt('last_completed_at'),
        active: map.flag('active'),
        todayDoneCount: map.integer('today_done_count'),
      );

  Map<String, Object?> toMap() => {
        'area': area,
        'title': title,
        'frequency': frequency,
        'freq_code': freqCode,
        'product_name': productName,
        'method': method,
        'last_completed_at': lastCompletedAt?.toIso8601String(),
        'active': active ? 1 : 0,
      };
}

class CleaningLog {
  const CleaningLog({
    required this.id,
    required this.taskId,
    required this.doneAt,
    required this.operatorName,
    required this.hadProblem,
    this.note,
    this.taskTitle,
    this.taskArea,
  });

  final int id;
  final int taskId;
  final DateTime doneAt;
  final String operatorName;
  final bool hadProblem;
  final String? note;
  final String? taskTitle;
  final String? taskArea;

  factory CleaningLog.fromMap(Map<String, Object?> map) => CleaningLog(
        id: map.integer('id'),
        taskId: map.integer('task_id'),
        doneAt: map.dtOr('done_at', DateTime.now()),
        operatorName: map.str('operator_name', 'Operatore'),
        hadProblem: map.flag('had_problem'),
        note: map.strOrNull('note'),
        taskTitle: map.strOrNull('task_title'),
        taskArea: map.strOrNull('task_area'),
      );
}

// -----------------------------------------------------------------------------
// Fornitori e merce in arrivo (PRP 10)
// -----------------------------------------------------------------------------

class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.vat = '',
    this.address = '',
    this.phone = '',
    this.email = '',
    this.products = '',
    this.qualified = true,
    this.notes = '',
    this.ncCount = 0,
  });

  final int id;
  final String name;
  final String vat;
  final String address;
  final String phone;
  final String email;
  final String products;
  final bool qualified;
  final String notes;

  /// NC ripetute verso questo fornitore.
  final int ncCount;

  bool get hasRepeatedNc => ncCount >= 2;

  factory Supplier.fromMap(Map<String, Object?> map) => Supplier(
        id: map.integer('id'),
        name: map.str('name'),
        vat: map.str('vat'),
        address: map.str('address'),
        phone: map.str('phone'),
        email: map.str('email'),
        products: map.str('products'),
        qualified: map.flag('qualified'),
        notes: map.str('notes'),
        ncCount: map.integer('nc_count'),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'vat': vat,
        'address': address,
        'phone': phone,
        'email': email,
        'products': products,
        'qualified': qualified ? 1 : 0,
        'notes': notes,
      };
}

class Receipt {
  const Receipt({
    required this.id,
    required this.receivedAt,
    required this.supplierId,
    required this.product,
    required this.category,
    this.supplierName = '',
    this.temperature,
    this.supplierLot,
    this.ddt,
    this.expiresAt,
    this.quantity,
    this.unit,
    this.packagingOk = true,
    this.labelOk = true,
    this.expiryOk = true,
    this.vehicleOk = true,
    this.outcome = 'accepted',
    this.note,
    this.operatorName = 'Operatore',
  });

  final int id;
  final DateTime receivedAt;
  final int supplierId;
  final String supplierName;
  final String product;
  final String category;
  final double? temperature;
  final String? supplierLot;
  final String? ddt;
  final DateTime? expiresAt;
  final double? quantity;
  final String? unit;
  final bool packagingOk;
  final bool labelOk;
  final bool expiryOk;
  final bool vehicleOk;
  final String outcome; // accepted | accepted_with_reserve | rejected
  final String? note;
  final String operatorName;

  GoodsCategory get categoryEnum => goodsCategoryByCode(category);

  bool get isTempCompliant {
    final cat = categoryEnum;
    final t = temperature;
    if (t == null) return true;
    if (cat.minTemp != null && t < cat.minTemp!) return false;
    if (cat.maxTemp != null && t > cat.maxTemp!) return false;
    return true;
  }

  bool get isRejected => outcome == 'rejected';

  String get outcomeLabel => switch (outcome) {
        'accepted' => 'Accettata',
        'accepted_with_reserve' => 'Accettata con riserva',
        'rejected' => 'Respinta',
        _ => outcome,
      };

  factory Receipt.fromMap(Map<String, Object?> map) => Receipt(
        id: map.integer('id'),
        receivedAt: map.dtOr('received_at', DateTime.now()),
        supplierId: map.integer('supplier_id'),
        supplierName: map.str('supplier_name'),
        product: map.str('product'),
        category: map.str('category'),
        temperature: map.dbl('temperature'),
        supplierLot: map.strOrNull('supplier_lot'),
        ddt: map.strOrNull('ddt'),
        expiresAt: map.dt('expires_at'),
        quantity: map.dbl('quantity'),
        unit: map.strOrNull('unit'),
        packagingOk: map.flag('packaging_ok'),
        labelOk: map.flag('label_ok'),
        expiryOk: map.flag('expiry_ok'),
        vehicleOk: map.flag('vehicle_ok'),
        outcome: map.str('outcome', 'accepted'),
        note: map.strOrNull('note'),
        operatorName: map.str('operator_name', 'Operatore'),
      );

  Map<String, Object?> toMap() => {
        'received_at': receivedAt.toIso8601String(),
        'supplier_id': supplierId,
        'product': product,
        'category': category,
        'temperature': temperature,
        'supplier_lot': supplierLot,
        'ddt': ddt,
        'expires_at': expiresAt?.toIso8601String(),
        'quantity': quantity,
        'unit': unit,
        'packaging_ok': packagingOk ? 1 : 0,
        'label_ok': labelOk ? 1 : 0,
        'expiry_ok': expiryOk ? 1 : 0,
        'vehicle_ok': vehicleOk ? 1 : 0,
        'outcome': outcome,
        'note': note,
        'operator_name': operatorName,
      };
}

// -----------------------------------------------------------------------------
// Prodotti, lotti, rintracciabilità
// -----------------------------------------------------------------------------

class Product {
  const Product({
    required this.id,
    required this.name,
    this.category = '',
    this.ingredients = '',
    this.shelfLifeDays,
    this.storage = '',
    this.allergenCodes = const [],
  });

  final int id;
  final String name;
  final String category;
  final String ingredients;
  final int? shelfLifeDays;
  final String storage;
  final List<String> allergenCodes;

  factory Product.fromMap(Map<String, Object?> map) => Product(
        id: map.integer('id'),
        name: map.str('name'),
        category: map.str('category'),
        ingredients: map.str('ingredients'),
        shelfLifeDays: map.integer('shelf_life_days') == 0
            ? null
            : map.integer('shelf_life_days'),
        storage: map.str('storage'),
        allergenCodes: parseAllergenCodes(map.strOrNull('allergens')),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'category': category,
        'ingredients': ingredients,
        'shelf_life_days': shelfLifeDays ?? 0,
        'storage': storage,
        'allergens': allergenCodesToCsv(allergenCodes),
      };
}

class LotIngredient {
  const LotIngredient({
    required this.id,
    required this.lotId,
    this.receiptId,
    this.name = '',
    this.supplierName = '',
    this.supplierLot = '',
  });

  final int id;
  final int lotId;
  final int? receiptId;
  final String name;
  final String supplierName;
  final String supplierLot;

  factory LotIngredient.fromMap(Map<String, Object?> map) => LotIngredient(
        id: map.integer('id'),
        lotId: map.integer('lot_id'),
        receiptId: map['receipt_id'] as int?,
        name: map.str('name'),
        supplierName: map.str('supplier_name'),
        supplierLot: map.str('supplier_lot'),
      );

  Map<String, Object?> toMap() => {
        'lot_id': lotId,
        'receipt_id': receiptId,
        'name': name,
        'supplier_name': supplierName,
        'supplier_lot': supplierLot,
      };
}

class ProductionLot {
  const ProductionLot({
    required this.id,
    required this.code,
    required this.productName,
    required this.producedAt,
    required this.operatorName,
    this.productId,
    this.expiresAt,
    this.quantity,
    this.unit,
    this.storageInfo,
    this.notes,
    this.allergenCodes = const [],
    this.ingredients = const [],
  });

  final int id;
  final String code;
  final String productName;
  final int? productId;
  final DateTime producedAt;
  final DateTime? expiresAt;
  final double? quantity;
  final String? unit;
  final String? storageInfo;
  final String operatorName;
  final String? notes;
  final List<String> allergenCodes;
  final List<LotIngredient> ingredients;

  factory ProductionLot.fromMap(
    Map<String, Object?> map, [
    List<LotIngredient> ingredients = const [],
  ]) =>
      ProductionLot(
        id: map.integer('id'),
        code: map.str('code'),
        productName: map.str('product_name'),
        productId: map['product_id'] as int?,
        producedAt: map.dtOr('produced_at', DateTime.now()),
        expiresAt: map.dt('expires_at'),
        quantity: map.dbl('quantity'),
        unit: map.strOrNull('unit'),
        storageInfo: map.strOrNull('storage_info'),
        operatorName: map.str('operator_name', 'Operatore'),
        notes: map.strOrNull('notes'),
        allergenCodes: parseAllergenCodes(map.strOrNull('allergens')),
        ingredients: ingredients,
      );

  Map<String, Object?> toMap() => {
        'code': code,
        'product_name': productName,
        'product_id': productId,
        'produced_at': producedAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'quantity': quantity,
        'unit': unit,
        'storage_info': storageInfo,
        'operator_name': operatorName,
        'notes': notes,
        'allergens': allergenCodesToCsv(allergenCodes),
      };
}

// -----------------------------------------------------------------------------
// Non conformità (Allegati I, II, III)
// -----------------------------------------------------------------------------

class NonConformity {
  const NonConformity({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.openedAt,
    required this.status,
    required this.operatorName,
    this.correctiveAction,
    this.closedAt,
    this.disposition = 'none',
    this.sourceType,
    this.sourceId,
  });

  final int id;
  final String category;
  final String title;
  final String description;
  final String? correctiveAction;
  final DateTime openedAt;
  final DateTime? closedAt;
  final String status;
  final String operatorName;
  final String disposition;
  final String? sourceType;
  final int? sourceId;

  bool get isOpen => status == 'Aperta';

  String get dispositionLabel =>
      NcDisposition.fromCode(disposition).label;

  factory NonConformity.fromMap(Map<String, Object?> map) => NonConformity(
        id: map.integer('id'),
        category: map.str('category'),
        title: map.str('title'),
        description: map.str('description'),
        correctiveAction: map.strOrNull('corrective_action'),
        openedAt: map.dtOr('opened_at', DateTime.now()),
        closedAt: map.dt('closed_at'),
        status: map.str('status', 'Aperta'),
        operatorName: map.str('operator_name', 'Operatore'),
        disposition: map.str('disposition', 'none'),
        sourceType: map.strOrNull('source_type'),
        sourceId: map['source_id'] as int?,
      );
}

class WasteLog {
  const WasteLog({
    required this.id,
    required this.disposedAt,
    required this.product,
    required this.reason,
    required this.operatorName,
    this.quantity,
    this.unit,
    this.lotCode,
    this.note,
  });

  final int id;
  final DateTime disposedAt;
  final String product;
  final String reason;
  final double? quantity;
  final String? unit;
  final String? lotCode;
  final String? note;
  final String operatorName;

  factory WasteLog.fromMap(Map<String, Object?> map) => WasteLog(
        id: map.integer('id'),
        disposedAt: map.dtOr('disposed_at', DateTime.now()),
        product: map.str('product'),
        reason: map.str('reason'),
        quantity: map.dbl('quantity'),
        unit: map.strOrNull('unit'),
        lotCode: map.strOrNull('lot_code'),
        note: map.strOrNull('note'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

// -----------------------------------------------------------------------------
// Infestanti (PRP 3)
// -----------------------------------------------------------------------------

class PestStation {
  const PestStation({
    required this.id,
    required this.type,
    required this.location,
    this.active = true,
    this.lastCheckedAt,
  });

  final int id;
  final String type;
  final String location;
  final bool active;
  final DateTime? lastCheckedAt;

  factory PestStation.fromMap(Map<String, Object?> map) => PestStation(
        id: map.integer('id'),
        type: map.str('type'),
        location: map.str('location'),
        active: map.flag('active'),
        lastCheckedAt: map.dt('last_checked_at'),
      );

  Map<String, Object?> toMap() => {
        'type': type,
        'location': location,
        'active': active ? 1 : 0,
      };
}

class PestLog {
  const PestLog({
    required this.id,
    required this.checkedAt,
    required this.stationId,
    required this.count,
    required this.level,
    required this.byCompany,
    required this.operatorName,
    this.stationType,
    this.stationLocation,
    this.note,
  });

  final int id;
  final DateTime checkedAt;
  final int stationId;
  final int count;
  final String level; // acceptable | moderate | severe
  final bool byCompany;
  final String operatorName;
  final String? stationType;
  final String? stationLocation;
  final String? note;

  bool get isSevere => level == 'severe';

  factory PestLog.fromMap(Map<String, Object?> map) => PestLog(
        id: map.integer('id'),
        checkedAt: map.dtOr('checked_at', DateTime.now()),
        stationId: map.integer('station_id'),
        count: map.integer('count'),
        level: map.str('level', 'acceptable'),
        byCompany: map.flag('by_company'),
        operatorName: map.str('operator_name', 'Operatore'),
        stationType: map.strOrNull('station_type'),
        stationLocation: map.strOrNull('station_location'),
        note: map.strOrNull('note'),
      );
}

// -----------------------------------------------------------------------------
// Strutture e personale (Allegati VI, VII)
// -----------------------------------------------------------------------------

class StructureCheckItem {
  const StructureCheckItem({
    required this.label,
    this.ok = true,
    this.note = '',
  });

  final String label;
  final bool ok;
  final String note;
}

class StructureCheck {
  const StructureCheck({
    required this.id,
    required this.area,
    required this.checkedAt,
    required this.operatorName,
    required this.itemsJson,
    this.hasAnomalies = false,
    this.ncId,
  });

  final int id;
  final String area;
  final DateTime checkedAt;
  final String operatorName;
  final String itemsJson;
  final bool hasAnomalies;
  final int? ncId;

  List<StructureCheckItem> get items {
    final parts =
        itemsJson.split('||').where((e) => e.trim().isNotEmpty).toList();
    return parts.map((p) {
      final seg = p.split('|');
      return StructureCheckItem(
        label: seg.first,
        ok: seg.length > 1 ? seg[1] == '1' : true,
        note: seg.length > 2 ? seg[2] : '',
      );
    }).toList();
  }

  static String encodeItems(List<StructureCheckItem> items) => items
      .map((i) => '${i.label}|${i.ok ? 1 : 0}|${i.note}')
      .join('||');

  factory StructureCheck.fromMap(Map<String, Object?> map) => StructureCheck(
        id: map.integer('id'),
        area: map.str('area'),
        checkedAt: map.dtOr('checked_at', DateTime.now()),
        operatorName: map.str('operator_name', 'Operatore'),
        itemsJson: map.str('items_json'),
        hasAnomalies: map.flag('has_anomalies'),
        ncId: map['nc_id'] as int?,
      );
}

// -----------------------------------------------------------------------------
// Allegati (foto e documenti)
// -----------------------------------------------------------------------------

/// Tipi di entità a cui si può allegare un file.
class AttachmentEntity {
  const AttachmentEntity._(this.value, this.label);

  final String value;
  final String label;

  static const receipt = AttachmentEntity._('receipt', 'Ricevimento merci');
  static const nonConformity =
      AttachmentEntity._('nonconformity', 'Non conformit\u00E0');
  static const staff = AttachmentEntity._('staff', 'Personale');
  static const equipment = AttachmentEntity._('equipment', 'Attrezzatura');
  static const supplier = AttachmentEntity._('supplier', 'Fornitore');
  static const lot = AttachmentEntity._('lot', 'Lotto');
  static const company = AttachmentEntity._('company', 'Azienda');

  static const all = <AttachmentEntity>[
    receipt,
    nonConformity,
    staff,
    equipment,
    supplier,
    lot,
    company,
  ];
}

class Attachment {
  const Attachment({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.kind,
    required this.fileName,
    required this.localPath,
    required this.createdAt,
    this.mime = '',
    this.size = 0,
    this.cloudId,
    this.syncedAt,
    this.note,
  });

  final int id;
  final String entityType;
  final int entityId;

  /// `photo` o `document`.
  final String kind;
  final String fileName;
  final String localPath;
  final String mime;
  final int size;
  final DateTime createdAt;
  final String? cloudId;
  final DateTime? syncedAt;
  final String? note;

  bool get isPhoto => kind == 'photo';

  factory Attachment.fromMap(Map<String, Object?> map) => Attachment(
        id: map.integer('id'),
        entityType: map.str('entity_type'),
        entityId: map.integer('entity_id'),
        kind: map.str('kind', 'document'),
        fileName: map.str('file_name'),
        localPath: map.str('local_path'),
        mime: map.str('mime'),
        size: map.integer('size'),
        createdAt: map.dtOr('created_at', DateTime.now()),
        cloudId: map.strOrNull('cloud_id'),
        syncedAt: map.dt('synced_at'),
        note: map.strOrNull('note'),
      );

  Map<String, Object?> toMap() => {
        'entity_type': entityType,
        'entity_id': entityId,
        'kind': kind,
        'file_name': fileName,
        'local_path': localPath,
        'mime': mime,
        'size': size,
        'created_at': createdAt.toIso8601String(),
        'cloud_id': cloudId,
        'synced_at': syncedAt?.toIso8601String(),
        'note': note,
      };
}

// -----------------------------------------------------------------------------
// Moduli MGSA-0415: cottura, abbattimento, trasporto, campioni, acqua,
// ritiri, cultura della sicurezza, contaminazione crociata, donazioni
// -----------------------------------------------------------------------------

class CookingLog {
  const CookingLog({
    required this.id,
    required this.cookedAt,
    required this.kind,
    required this.category,
    required this.coreTemp,
    required this.compliant,
    required this.operatorName,
    this.foodName = '',
    this.correctiveAction,
  });

  final int id;
  final DateTime cookedAt;

  /// cottura | rigenerazione | frittura.
  final String kind;
  final String category;
  final String foodName;
  final double coreTemp;
  final bool compliant;
  final String? correctiveAction;
  final String operatorName;

  String get kindLabel => switch (kind) {
        'rigenerazione' => 'Rigenerazione',
        'frittura' => 'Frittura',
        _ => 'Cottura',
      };

  factory CookingLog.fromMap(Map<String, Object?> map) => CookingLog(
        id: map.integer('id'),
        cookedAt: map.dtOr('cooked_at', DateTime.now()),
        kind: map.str('kind', 'cottura'),
        category: map.str('category'),
        foodName: map.str('food_name'),
        coreTemp: map.dbl('core_temp') ?? 0,
        compliant: map.flag('compliant'),
        correctiveAction: map.strOrNull('corrective_action'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class OilValidation {
  const OilValidation({
    required this.id,
    required this.validatedAt,
    required this.fryer,
    required this.tempC,
    required this.sensoryOk,
    required this.oilChanged,
    required this.operatorName,
    this.note,
  });

  final int id;
  final DateTime validatedAt;
  final String fryer;
  final double tempC;
  final bool sensoryOk;
  final bool oilChanged;
  final String? note;
  final String operatorName;

  factory OilValidation.fromMap(Map<String, Object?> map) => OilValidation(
        id: map.integer('id'),
        validatedAt: map.dtOr('validated_at', DateTime.now()),
        fryer: map.str('fryer'),
        tempC: map.dbl('temp_c') ?? 0,
        sensoryOk: map.flag('sensory_ok'),
        oilChanged: map.flag('oil_changed'),
        note: map.strOrNull('note'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class BlastChillCycle {
  const BlastChillCycle({
    required this.id,
    required this.startedAt,
    required this.product,
    required this.kind,
    required this.compliant,
    required this.operatorName,
    this.endedAt,
    this.tStart,
    this.tEnd,
    this.note,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String product;

  /// positivo | negativo.
  final String kind;
  final double? tStart;
  final double? tEnd;
  final bool compliant;
  final String operatorName;
  final String? note;

  factory BlastChillCycle.fromMap(Map<String, Object?> map) =>
      BlastChillCycle(
        id: map.integer('id'),
        startedAt: map.dtOr('started_at', DateTime.now()),
        endedAt: map.dt('ended_at'),
        product: map.str('product'),
        kind: map.str('kind', 'positivo'),
        tStart: map.dbl('t_start'),
        tEnd: map.dbl('t_end'),
        compliant: map.flag('compliant'),
        operatorName: map.str('operator_name', 'Operatore'),
        note: map.strOrNull('note'),
      );
}

class TransportLog {
  const TransportLog({
    required this.id,
    required this.doneAt,
    required this.vehicleClean,
    required this.containersSanitized,
    required this.compliant,
    required this.operatorName,
    this.destination = '',
    this.tempColdStart,
    this.tempColdArrival,
    this.tempHotStart,
    this.tempHotArrival,
    this.note,
  });

  final int id;
  final DateTime doneAt;
  final String destination;
  final double? tempColdStart;
  final double? tempColdArrival;
  final double? tempHotStart;
  final double? tempHotArrival;
  final bool vehicleClean;
  final bool containersSanitized;
  final bool compliant;
  final String operatorName;
  final String? note;

  factory TransportLog.fromMap(Map<String, Object?> map) => TransportLog(
        id: map.integer('id'),
        doneAt: map.dtOr('done_at', DateTime.now()),
        destination: map.str('destination'),
        tempColdStart: map.dbl('temp_cold_start'),
        tempColdArrival: map.dbl('temp_cold_arrival'),
        tempHotStart: map.dbl('temp_hot_start'),
        tempHotArrival: map.dbl('temp_hot_arrival'),
        vehicleClean: map.flag('vehicle_clean'),
        containersSanitized: map.flag('containers_sanitized'),
        compliant: map.flag('compliant'),
        operatorName: map.str('operator_name', 'Operatore'),
        note: map.strOrNull('note'),
      );
}

class SampleMeal {
  const SampleMeal({
    required this.id,
    required this.takenAt,
    required this.dish,
    required this.grams,
    required this.discardAfter,
    required this.operatorName,
    this.discardedAt,
  });

  final int id;
  final DateTime takenAt;
  final String dish;
  final double grams;
  final DateTime discardAfter;
  final DateTime? discardedAt;
  final String operatorName;

  bool get isPendingDisposal =>
      discardedAt == null && DateTime.now().isAfter(discardAfter);

  factory SampleMeal.fromMap(Map<String, Object?> map) => SampleMeal(
        id: map.integer('id'),
        takenAt: map.dtOr('taken_at', DateTime.now()),
        dish: map.str('dish'),
        grams: map.dbl('grams') ?? 0,
        discardAfter: map.dtOr('discard_after', DateTime.now()),
        discardedAt: map.dt('discarded_at'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class WaterCheck {
  const WaterCheck({
    required this.id,
    required this.checkedAt,
    required this.kind,
    required this.resultOk,
    required this.operatorName,
    this.note,
  });

  final int id;
  final DateTime checkedAt;

  /// analisi | filtri | ghiaccio.
  final String kind;
  final bool resultOk;
  final String? note;
  final String operatorName;

  String get kindLabel => switch (kind) {
        'filtri' => 'Pulizia filtri e rompigetto',
        'ghiaccio' => 'Sanificazione produttore di ghiaccio',
        _ => 'Analisi acqua',
      };

  factory WaterCheck.fromMap(Map<String, Object?> map) => WaterCheck(
        id: map.integer('id'),
        checkedAt: map.dtOr('checked_at', DateTime.now()),
        kind: map.str('kind', 'analisi'),
        resultOk: map.flag('result_ok'),
        note: map.strOrNull('note'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.startedAt,
    required this.lotCode,
    required this.clients,
    required this.actions,
    required this.aslNotified,
    required this.outcome,
    required this.operatorName,
    this.closedAt,
  });

  final int id;
  final DateTime startedAt;
  final String lotCode;
  final String clients;
  final String actions;
  final bool aslNotified;

  /// in_corso | concluso.
  final String outcome;
  final DateTime? closedAt;
  final String operatorName;

  bool get isOpen => outcome == 'in_corso';

  factory Withdrawal.fromMap(Map<String, Object?> map) => Withdrawal(
        id: map.integer('id'),
        startedAt: map.dtOr('started_at', DateTime.now()),
        lotCode: map.str('lot_code'),
        clients: map.str('clients'),
        actions: map.str('actions'),
        aslNotified: map.flag('asl_notified'),
        outcome: map.str('outcome', 'in_corso'),
        closedAt: map.dt('closed_at'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class CultureLogEntry {
  const CultureLogEntry({
    required this.id,
    required this.kind,
    required this.title,
    required this.doneAt,
    required this.operatorName,
    this.notes,
  });

  final int id;

  /// politica | comunicazione | verifica.
  final String kind;
  final String title;
  final String? notes;
  final DateTime doneAt;
  final String operatorName;

  String get kindLabel => switch (kind) {
        'comunicazione' => 'Comunicazione al personale',
        'verifica' => 'Verifica annuale',
        _ => 'Politica firmata',
      };

  factory CultureLogEntry.fromMap(Map<String, Object?> map) =>
      CultureLogEntry(
        id: map.integer('id'),
        kind: map.str('kind', 'politica'),
        title: map.str('title'),
        notes: map.strOrNull('notes'),
        doneAt: map.dtOr('done_at', DateTime.now()),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class CrossContaminationCheck {
  const CrossContaminationCheck({
    required this.id,
    required this.checkedAt,
    required this.equipment,
    required this.residueFound,
    required this.operatorName,
    this.action,
  });

  final int id;
  final DateTime checkedAt;
  final String equipment;
  final bool residueFound;
  final String? action;
  final String operatorName;

  factory CrossContaminationCheck.fromMap(Map<String, Object?> map) =>
      CrossContaminationCheck(
        id: map.integer('id'),
        checkedAt: map.dtOr('checked_at', DateTime.now()),
        equipment: map.str('equipment'),
        residueFound: map.flag('residue_found'),
        action: map.strOrNull('action'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class Donation {
  const Donation({
    required this.id,
    required this.donatedAt,
    required this.product,
    required this.entity,
    required this.operatorName,
    this.quantity,
    this.unit,
    this.stateNote,
  });

  final int id;
  final DateTime donatedAt;
  final String product;
  final double? quantity;
  final String? unit;
  final String entity;
  final String? stateNote;
  final String operatorName;

  factory Donation.fromMap(Map<String, Object?> map) => Donation(
        id: map.integer('id'),
        donatedAt: map.dtOr('donated_at', DateTime.now()),
        product: map.str('product'),
        quantity: map.dbl('quantity'),
        unit: map.strOrNull('unit'),
        entity: map.str('entity'),
        stateNote: map.strOrNull('state_note'),
        operatorName: map.str('operator_name', 'Operatore'),
      );
}

class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    required this.role,
    this.job = '',
    this.certificateAt,
    this.notes = '',
  });

  final int id;
  final String name;
  final String role;
  final String job;
  final DateTime? certificateAt;
  final String notes;

  /// valid | expiring | expired | missing. Il periodo di rinnovo \u00E8
  /// configurabile per regione/attivit\u00E0 (default 36 mesi).
  String certificateStatus({int months = 36}) {
    final c = certificateAt;
    if (c == null) return 'missing';
    final expiry = DateTime(c.year + months ~/ 12, c.month + months % 12, c.day);
    final now = DateTime.now();
    if (now.isAfter(expiry)) return 'expired';
    if (now.isAfter(expiry.subtract(const Duration(days: 30)))) {
      return 'expiring';
    }
    return 'valid';
  }

  factory StaffMember.fromMap(Map<String, Object?> map) => StaffMember(
        id: map.integer('id'),
        name: map.str('name'),
        role: map.str('role', 'Alimentarista'),
        job: map.str('job'),
        certificateAt: map.dt('certificate_at'),
        notes: map.str('notes'),
      );

  Map<String, Object?> toMap() => {
        'name': name,
        'role': role,
        'job': job,
        'certificate_at': certificateAt?.toIso8601String(),
        'notes': notes,
      };
}
