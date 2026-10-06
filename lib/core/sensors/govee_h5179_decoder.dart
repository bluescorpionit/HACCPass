/// Decodificatore BLE per i termo-igrometri Govee H5179.
///
/// Il protocollo è tratto dalla libreria open source `govee-ble`
/// (Bluetooth-Devices, MIT), file `parser.py`: NESSUN byte o offset è stato
/// inventato. L'H5179 advertise in due formati, entrambi gestiti:
///
/// 1. **Formato 9 byte** — manufacturer id `0x8801` (34817) oppure nome che
///    contiene "H5179" (es. `Govee_H5179_3CD5`):
///    `ec 00 01 01 | TT TT HH HH BB` dove i 5 byte finali sono
///    int16 LE (temp ×100), uint16 LE (umidità ×100), uint8 (batteria %).
///    Pacchetto reale dai test di govee-ble:
///    `ec 00 01 01 0a 0a a4 06 64` → 25.7 °C, 17.0 %, batteria 100 %.
///
/// 2. **Formato 6 byte** — nome `GV5179_*` (famiglia H5108):
///    `01 01 | MMM MMM BB` dove i 3 byte M packano temp+umidità:
///    bit 23 = segno, poi `int(mag / 1000) / 10` = temperatura e
///    `(mag % 1000) / 10` = umidità. Il byte batteria maschera il bit 0x80
///    (errore sensore). Pacchetto reale:
///    `01 01 03 b3 14 64` → 24.2 °C, 45.2 %, batteria 100 %.
///
/// Secondo govee-ble l'H5179 ha `requires_active_scan = true`: il payload
/// sta nella scan response, quindi la scansione deve essere attiva (su
/// Android: `AndroidScanMode.lowLatency`) e abbastanza lunga da catturare
/// un ciclo completo di advertisement.
///
/// NOTA Fase 0: i due formati sono quelli dichiarati dalla libreria di
/// riferimento; la corrispondenza con un sensore reale (±0,3 °C rispetto a
/// display e app Govee Home) va confermata con la schermata "Diagnostica
/// sensori" e registrata in `docs/govee_h5179.md` prima di usare i dati
/// nel registro HACCP.
library;

/// Lettura decodificata da un advertisement H5179.
class GoveeReading {
  const GoveeReading({
    required this.tempC,
    required this.humidity,
    required this.batteryPercent,
    required this.format,
  });

  final double tempC;
  final double humidity;
  final int batteryPercent;

  /// Formato del pacchetto da cui proviene la lettura.
  final GoveePacketFormat format;

  @override
  String toString() =>
      '$tempC\u00B0C • $humidity% • bat $batteryPercent% ($format)';
}

enum GoveePacketFormat {
  /// 9 byte, manufacturer id 0x8801.
  bytes9,

  /// 6 byte, famiglia H5108 (nome GV5179_*).
  bytes6,
}

class GoveeH5179Decoder {
  GoveeH5179Decoder._();

  /// Manufacturer id del formato a 9 byte (34817 decimale).
  static const int manufacturerIdBytes9 = 0x8801;

  /// Manufacturer id del beacon iBeacon "INTELLI_ROCKS" che govee-ble
  /// ignora sempre.
  static const int _intelliRocksId = 76;

  static const int _minTempC = -40;
  static const int _maxTempC = 100;

  /// true se il nome announcement appartiene a un H5179
  /// (`Govee_H5179_xxxx` o `GV5179_xxxx`).
  static bool isH5179Name(String? localName) {
    if (localName == null) return false;
    return localName.contains('H5179') || localName.contains('GV5179');
  }

  /// Decodifica la prima lettura H5179 valida dai manufacturer data di un
  /// advertisement. Restituisce `null` se nessun pacchetto è decodificabile
  /// (lunghezza errata, bit di errore, valori fuori range): mai valori
  /// inventati, mai eccezioni.
  static GoveeReading? decode({
    required Map<int, List<int>> manufacturerData,
    String localName = '',
  }) {
    final entries = manufacturerData.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      if (entry.key == _intelliRocksId) continue;
      final data = entry.value;
      if (data.length == 9 &&
          (localName.contains('H5179') || entry.key == manufacturerIdBytes9)) {
        final reading = _decodeBytes9(data);
        if (reading != null) return reading;
        continue;
      }
      if (data.length == 6 && localName.contains('GV5179')) {
        final reading = _decodeBytes6(data);
        if (reading != null) return reading;
      }
    }
    return null;
  }

  /// `ec 00 01 01 | int16LE(temp×100) | uint16LE(um×100) | batteria`
  static GoveeReading? _decodeBytes9(List<int> data) {
    if (data.length < 9) return null;
    final tempRaw = (data[4] | (data[5] << 8)).toSigned(16);
    final humidityRaw = data[6] | (data[7] << 8);
    return GoveeReading(
      tempC: tempRaw / 100.0,
      humidity: humidityRaw / 100.0,
      batteryPercent: data[8],
      format: GoveePacketFormat.bytes9,
    );
  }

  /// `01 01 | 3 byte temp+umidità (bit 23 segno) | batteria (bit 7 errore)`
  static GoveeReading? _decodeBytes6(List<int> data) {
    if (data.length < 6) return null;
    final base = (data[2] << 16) | (data[3] << 8) | data[4];
    final isNegative = base & 0x800000 != 0;
    final magnitude = base & 0x7FFFFF;
    var temp = (magnitude ~/ 1000) / 10.0;
    if (isNegative) temp = -temp;
    final humidity = (magnitude % 1000) / 10.0;
    final battery = data[5] & 0x7F;
    final error = data[5] & 0x80 != 0;

    // Come govee-ble: scarta letture con errore sensore o fuori range.
    if (error || temp < _minTempC || temp > _maxTempC) return null;
    return GoveeReading(
      tempC: temp,
      humidity: humidity,
      batteryPercent: battery,
      format: GoveePacketFormat.bytes6,
    );
  }
}
