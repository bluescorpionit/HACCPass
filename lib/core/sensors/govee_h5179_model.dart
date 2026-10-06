import 'govee_h5179_decoder.dart';
import 'sensor_model.dart';
import 'sensor_source.dart';

/// Modello del termo-igrometro Govee H5179 (Bluetooth LE, offline).
///
/// Wrapper sottile attorno al decoder già verificato della Fase 0
/// (`GoveeH5179Decoder`, protocollo da govee-ble): nessuna logica duplicata.
class GoveeH5179Model extends SensorModel {
  const GoveeH5179Model();

  @override
  String get id => 'govee_h5179';

  @override
  String get displayName => 'Govee H5179 (Bluetooth)';

  @override
  SensorSourceKind get transport => SensorSourceKind.ble;

  @override
  bool matches(BleAdvertisement a) =>
      GoveeH5179Decoder.isH5179Name(a.name) || decode(a) != null;

  @override
  String? stableKey(BleAdvertisement a) {
    if (!GoveeH5179Decoder.isH5179Name(a.name)) return null;
    return normalizeDeviceKey(a.name);
  }

  @override
  SensorSample? decode(BleAdvertisement a) {
    final reading = GoveeH5179Decoder.decode(
      localName: a.name,
      manufacturerData: a.manufacturerData,
    );
    if (reading == null) return null;
    return SensorSample(
      sensorId: normalizeDeviceKey(a.name) ?? a.systemId,
      tempC: reading.tempC,
      source: SensorSourceKind.ble,
      timestamp: a.seenAt,
      humidity: reading.humidity,
      batteryPercent: reading.batteryPercent,
      rssi: a.rssi,
    );
  }

  @override
  SensorSpecs get specs => const SensorSpecs(
        // Precisione dichiarata ±0,3 °C e umidità ±3% (scheda prodotto).
        // Range operativo NON verificato: nessun valore inventato.
        precisionC: 0.3,
        humidityAccuracy: 3,
      );

  @override
  String? get imageAsset => null; // da fornire in assets/images/
}

/// Normalizza il nome pubblicizzato alla chiave stabile: il suffisso dopo
/// l'ultimo underscore, maiuscolo (`GVH5179_AB12` → `AB12`,
/// `Govee_H5179_3CD5` → `3CD5`). Su iOS l'ID BLE cambia per telefono: il
/// nome pubblicizzato è la chiave, l'ID di sistema resta secondario.
String? normalizeDeviceKey(String name) {
  final n = name.trim();
  if (n.isEmpty) return null;
  final idx = n.lastIndexOf('_');
  final key = idx >= 0 ? n.substring(idx + 1) : n;
  if (key.isEmpty) return null;
  return key.toUpperCase();
}
