import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/sensors/govee_h5179_decoder.dart';

/// Test del decoder H5179: pacchetti reali dai test della libreria di
/// riferimento govee-ble (MIT), più casi sintetici per negativi, batteria,
/// errori e pacchetti malformati. Nessun decoder deve crashare su input
/// arbitrario: al peggio restituisce null.
void main() {
  group('pacchetti reali (fixture govee-ble)', () {
    test('formato 9 byte, manufacturer 0x8801: 25.7 °C / 17.0% / bat 100',
        () {
      final reading = GoveeH5179Decoder.decode(
        localName: 'Govee_H5179_3CD5',
        manufacturerData: const {
          0x8801: [
            0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06, 0x64,
          ],
        },
      );

      expect(reading, isNotNull);
      expect(reading!.tempC, closeTo(25.7, 0.001));
      expect(reading.humidity, closeTo(17.0, 0.001));
      expect(reading.batteryPercent, 100);
      expect(reading.format, GoveePacketFormat.bytes9);
    });

    test('formato 6 byte, nome GV5179: 24.2 °C / 45.2% / bat 100', () {
      final reading = GoveeH5179Decoder.decode(
        localName: 'GV5179_6319',
        manufacturerData: const {
          // Beacon iBeacon "INTELLI_ROCKS" (mfr 76): deve essere ignorato.
          76: [
            0x02, 0x15, 0x49, 0x4e, 0x54, 0x45, 0x4c, 0x4c, 0x49, 0x5f,
            0x52, 0x4f, 0x43, 0x4b, 0x53, 0x5f, 0x48, 0x57, 0x50, 0x75,
            0xf2, 0xff, 0x0c,
          ],
          1: [0x01, 0x01, 0x03, 0xb3, 0x14, 0x64],
        },
      );

      expect(reading, isNotNull);
      expect(reading!.tempC, closeTo(24.2, 0.001));
      expect(reading.humidity, closeTo(45.2, 0.001));
      expect(reading.batteryPercent, 100);
      expect(reading.format, GoveePacketFormat.bytes6);
    });

    test('manufacturer 0x8801 riconosciuto anche senza nome', () {
      final reading = GoveeH5179Decoder.decode(
        localName: '',
        manufacturerData: const {
          0x8801: [
            0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06, 0x64,
          ],
        },
      );

      expect(reading, isNotNull);
      expect(reading!.tempC, closeTo(25.7, 0.001));
    });
  });

  group('temperature negative (congelatori)', () {
    test('formato 9 byte: -18.5 °C (int16 LE in complemento a due)', () {
      // -1850 = 0xF8C6 → LE: c6 f8. Umidità 45.86% = 4586 = 0x11EA.
      final reading = GoveeH5179Decoder.decode(
        localName: 'GVH5179_2EC8',
        manufacturerData: const {
          0x8801: [
            0xec, 0x00, 0x01, 0x01, 0xc6, 0xf8, 0xea, 0x11, 0x64,
          ],
        },
      );

      expect(reading, isNotNull);
      expect(reading!.tempC, closeTo(-18.5, 0.001));
      expect(reading.humidity, closeTo(45.86, 0.001));
      expect(reading.batteryPercent, 100);
    });

    test('formato 6 byte: -2.5 °C con bit di segno 0x800000', () {
      // mag = 25.591: int(25591/1000) = 25 → 2.5 °C; 25591 % 1000 = 591
      // → 59.1 %. Con il bit di segno: base = 0x8063F7.
      final reading = GoveeH5179Decoder.decode(
        localName: 'GV5179_6319',
        manufacturerData: const {
          1: [0x01, 0x01, 0x80, 0x63, 0xf7, 0x64],
        },
      );

      expect(reading, isNotNull);
      expect(reading!.tempC, closeTo(-2.5, 0.001));
      expect(reading.humidity, closeTo(59.1, 0.001));
      expect(reading.batteryPercent, 100);
    });
  });

  group('pacchetti malformati o non validi: mai crash, mai dati inventati',
      () {
    test('manufacturer data vuoto', () {
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GVH5179_2EC8',
          manufacturerData: const {},
        ),
        isNull,
      );
    });

    test('payload 9 byte con lunghezza errata (8 byte)', () {
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GVH5179_2EC8',
          manufacturerData: const {
            0x8801: [0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06],
          },
        ),
        isNull,
      );
    });

    test('payload 6 byte con bit di errore batteria (0x80)', () {
      // Come la fixture H5108 "ERROR": byte batteria 0xe4 → errore.
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GV5179_6319',
          manufacturerData: const {
            1: [0x01, 0x01, 0x03, 0xc7, 0x30, 0xe4],
          },
        ),
        isNull,
      );
    });

    test('payload 6 byte con temperatura fuori range (> 100 °C)', () {
      // mag = 0x0F4712 = 1.001.234 → 1001 → 100.1 °C: fuori range.
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GV5179_6319',
          manufacturerData: const {
            1: [0x01, 0x01, 0x0f, 0x47, 0x12, 0x64],
          },
        ),
        isNull,
      );
    });

    test('nome sconosciuto e manufacturer id non Govee: null', () {
      expect(
        GoveeH5179Decoder.decode(
          localName: 'RZSS',
          manufacturerData: const {
            0x0409: [0x02, 0x01, 0x06, 0x11],
          },
        ),
        isNull,
      );
    });

    test('lista bytes più corta del previsto non lancia eccezioni', () {
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GVH5179_2EC8',
          manufacturerData: const {
            0x8801: [0xec],
          },
        ),
        isNull,
      );
      expect(
        GoveeH5179Decoder.decode(
          localName: 'GV5179_6319',
          manufacturerData: const {
            1: [0x01],
          },
        ),
        isNull,
      );
    });
  });

  group('riconoscimento nome', () {
    test('isH5179Name accetta GVH5179_, Govee_H5179_ e GV5179_', () {
      expect(GoveeH5179Decoder.isH5179Name('GVH5179_1234'), isTrue);
      expect(GoveeH5179Decoder.isH5179Name('Govee_H5179_3CD5'), isTrue);
      expect(GoveeH5179Decoder.isH5179Name('GV5179_6319'), isTrue);
      expect(GoveeH5179Decoder.isH5179Name('GVH5075_2762'), isFalse);
      expect(GoveeH5179Decoder.isH5179Name(null), isFalse);
      expect(GoveeH5179Decoder.isH5179Name(''), isFalse);
    });
  });
}
