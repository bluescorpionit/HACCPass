/// Catalogo dei modelli di sensore (Prompt 7, Fase 1).
///
/// Un modello = una classe che implementa [SensorModel] + una riga nel
/// `sensor_registry.dart`: schermate e registro temperature non cambiano
/// quando si aggiunge un modello futuro.
library;

import 'sensor_source.dart';

/// Advertisement BLE indipendente dal plugin (mappato da flutter_blue_plus
/// in `ble_sensor_source.dart`): così modelli e test non dipendono dalla
/// libreria Bluetooth.
class BleAdvertisement {
  const BleAdvertisement({
    required this.name,
    required this.systemId,
    required this.rssi,
    required this.manufacturerData,
    required this.serviceData,
    required this.seenAt,
  });

  /// Nome pubblicizzato (es. `GVH5179_AB12`, `Govee_H5179_3CD5`).
  final String name;

  /// MAC/ID di sistema: su iOS cambia per telefono, mai usarlo come chiave.
  final String systemId;

  final int rssi;

  /// Manufacturer data grezzi (chiave = company id).
  final Map<int, List<int>> manufacturerData;

  /// Service data grezzi (chiave = UUID).
  final Map<String, List<int>> serviceData;

  final DateTime seenAt;
}

/// Specifiche dichiarate dal produttore. Ogni campo null = NON VERIFICATO:
/// mai inventare valori; in UI mostrare "Range operativo da verificare nel
/// manuale del sensore".
class SensorSpecs {
  const SensorSpecs({
    this.minTempC,
    this.maxTempC,
    this.precisionC,
    this.humidityAccuracy,
  });

  final double? minTempC;
  final double? maxTempC;
  final double? precisionC;
  final double? humidityAccuracy;

  /// Range operativo verificato (serve per gli avvisi di incompatibilità).
  bool get verified => minTempC != null && maxTempC != null;

  /// true se NON verificato oppure il range copre i limiti dell'attrezzatura.
  bool coversRange(double minTemp, double maxTemp) =>
      !verified || (minTempC! <= minTemp && maxTempC! >= maxTemp);
}

/// Contratto di un modello di sensore.
abstract class SensorModel {
  const SensorModel();

  /// Id stabile (es. 'govee_h5179').
  String get id;

  /// Nome mostrato all'utente (es. 'Govee H5179 (Bluetooth)').
  String get displayName;

  /// Trasporto: ble | cloud | gateway (da `sensor_source.dart`).
  SensorSourceKind get transport;

  /// Riconosce il modello dall'advertisement (nome e/o pacchetto grezzo).
  bool matches(BleAdvertisement advertisement);

  /// Chiave stabile del sensore: suffisso normalizzato del nome
  /// pubblicizzato (es. `GVH5179_AB12` → `AB12`), indipendente dal
  /// telefono. Null se non riconosciuto.
  String? stableKey(BleAdvertisement advertisement);

  /// Decodifica la lettura riusando il decoder esistente; null se il
  /// pacchetto non è decodificabile: mai dati inventati, mai eccezioni.
  SensorSample? decode(BleAdvertisement advertisement);

  /// Range operativo / precisione (null = da verificare).
  SensorSpecs get specs;

  /// Immagine del dispositivo (fornita dal proprietario dell'app in
  /// `assets/images/`): facoltativa, con ripiego a icona generica.
  String? get imageAsset;
}
