import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/sensors/ble_sensor_source.dart';
import 'package:haccpass/core/sensors/govee_h5179_model.dart';
import 'package:haccpass/core/sensors/sensor_model.dart';
import 'package:haccpass/core/sensors/sensor_registry.dart';
import 'package:haccpass/core/sensors/sensor_source.dart';

/// Catalogo modelli + servizio condiviso (Prompt 7, Fase 1): matches/
/// stableKey/decode sui pacchetti campione e stati live/stale/offline con
/// orologio finto.
void main() {
  final model = sensorModelById('govee_h5179');

  BleAdvertisement adv({
    String name = 'GVH5179_AB12',
    Map<int, List<int>> manufacturerData = const {},
    int rssi = -55,
  }) =>
      BleAdvertisement(
        name: name,
        systemId: 'AA:BB:CC:DD:EE:FF',
        rssi: rssi,
        manufacturerData: manufacturerData,
        serviceData: const {},
        seenAt: DateTime(2026, 1, 15, 10),
      );

  group('SensorRegistry', () {
    test('contiene il modello Govee H5179, ritrovabile per id', () {
      expect(sensorRegistry, hasLength(1));
      expect(model, isA<GoveeH5179Model>());
      expect(model!.displayName, 'Govee H5179 (Bluetooth)');
      expect(model.transport, SensorSourceKind.ble);
      expect(sensorModelById('inesistente'), isNull);
    });
  });

  group('GoveeH5179Model.matches', () {
    test('riconosce i tre prefissi di nome', () {
      expect(model!.matches(adv(name: 'GVH5179_AB12')), isTrue);
      expect(model.matches(adv(name: 'Govee_H5179_3CD5')), isTrue);
      expect(model.matches(adv(name: 'GV5179_6319')), isTrue);
    });

    test('riconosce il pacchetto 9 byte anche senza nome', () {
      expect(
        model!.matches(adv(
          name: '',
          manufacturerData: const {
            0x8801: [
              0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06, 0x64,
            ],
          },
        )),
        isTrue,
      );
    });

    test('rifiuta dispositivi non Govee', () {
      expect(
        model!.matches(adv(name: 'GVH5075_2762')), isFalse);
      expect(
        model.matches(adv(
          name: 'RZSS',
          manufacturerData: const {0x0409: [0x02, 0x01, 0x06]},
        )),
        isFalse,
      );
    });
  });

  group('GoveeH5179Model.stableKey', () {
    test('suffisso normalizzato del nome pubblicizzato', () {
      expect(model!.stableKey(adv(name: 'GVH5179_AB12')), 'AB12');
      expect(model.stableKey(adv(name: 'Govee_H5179_3CD5')), '3CD5');
      expect(model.stableKey(adv(name: 'GV5179_6319')), '6319');
    });

    test('null per nomi non H5179', () {
      expect(model!.stableKey(adv(name: 'GVH5075_2762')), isNull);
    });

    test('normalizeDeviceKey: maiuscolo, gestisce nomi senza underscore', () {
      expect(normalizeDeviceKey('GVH5179_ab12'), 'AB12');
      expect(normalizeDeviceKey('sensorx'), 'SENSORX');
      expect(normalizeDeviceKey(''), isNull);
      expect(normalizeDeviceKey('GVH5179_'), isNull);
    });
  });

  group('GoveeH5179Model.decode', () {
    test('pacchetto reale 9 byte (fixture govee-ble)', () {
      final sample = model!.decode(adv(
        name: 'Govee_H5179_3CD5',
        manufacturerData: const {
          0x8801: [
            0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06, 0x64,
          ],
        },
      ));
      expect(sample, isNotNull);
      expect(sample!.sensorId, '3CD5');
      expect(sample.tempC, closeTo(25.7, 0.001));
      expect(sample.humidity, closeTo(17.0, 0.001));
      expect(sample.batteryPercent, 100);
      expect(sample.source, SensorSourceKind.ble);
    });

    test('pacchetto reale 6 byte (GV5179)', () {
      final sample = model!.decode(adv(
        name: 'GV5179_6319',
        manufacturerData: const {
          1: [0x01, 0x01, 0x03, 0xb3, 0x14, 0x64],
        },
      ));
      expect(sample, isNotNull);
      expect(sample!.sensorId, '6319');
      expect(sample.tempC, closeTo(24.2, 0.001));
    });

    test('pacchetti malformati: null, nessuna eccezione', () {
      expect(
        model!.decode(adv(
          name: 'GVH5179_AB12',
          manufacturerData: const {0x8801: [0xec]},
        )),
        isNull,
      );
      expect(model.decode(adv(name: 'GVH5179_AB12')), isNull);
    });
  });

  group('GoveeH5179Model.specs', () {
    test('precisione dichiarata, range NON verificato (mai inventato)', () {
      final specs = model!.specs;
      expect(specs.verified, isFalse, reason: 'range operativo da verificare');
      expect(specs.precisionC, 0.3);
      // Non verificato: nessun avviso di incompatibilità inventato.
      expect(specs.coversRange(-30, -18), isTrue);
      expect(model.imageAsset, isNull, reason: 'immagine non fornita');
    });
  });

  group('SensorService: stati con orologio finto', () {
    late FakeScanner scanner;
    late DateTime fakeNow;
    late SensorService service;

    setUp(() {
      scanner = FakeScanner();
      fakeNow = DateTime(2026, 1, 15, 12);
      service = SensorService.forTest(scanner, now: () => fakeNow);
    });

    SensorSample sampleAt(DateTime ts, {String key = 'AB12'}) =>
        SensorSample(
          sensorId: key,
          tempC: 4.2,
          source: SensorSourceKind.ble,
          timestamp: ts,
        );

    test('offline se mai visto in sessione', () {
      expect(service.statusFor('AB12'), SensorStatus.offline);
      expect(service.latestFor('AB12'), isNull);
    });

    test('live sotto la soglia, stale oltre', () {
      service.debugInjectReading(sampleAt(fakeNow.subtract(
          const Duration(minutes: 9))));
      expect(service.statusFor('AB12'), SensorStatus.live);

      fakeNow = fakeNow.add(const Duration(minutes: 2));
      expect(service.statusFor('AB12'), SensorStatus.stale);
    });

    test('soglia configurabile', () {
      service.staleAfter = const Duration(minutes: 1);
      service.debugInjectReading(
          sampleAt(fakeNow.subtract(const Duration(minutes: 90))));
      expect(service.statusFor('AB12'), SensorStatus.stale);
    });

    test('start: ascolta lo scanner e aggiorna le letture', () async {
      await service.start();
      final received = expectLater(
        service.samples,
        emitsThrough(predicate<SensorSample>(
          (s) => s.sensorId == 'AB12' && s.tempC < -18,
        )),
      );
      scanner.emit([
        BleAdvertisement(
          name: 'GVH5179_AB12',
          systemId: 'AA:BB:CC:DD:EE:FF',
          rssi: -55,
          manufacturerData: const {
            0x8801: [
              0xec, 0x00, 0x01, 0x01, 0xc6, 0xf8, 0xea, 0x11, 0x64,
            ],
          },
          serviceData: const {},
          seenAt: fakeNow,
        ),
      ]);
      await received;

      final sample = service.latestFor('AB12');
      expect(sample, isNotNull);
      expect(sample!.tempC, closeTo(-18.5, 0.001));
      expect(service.statusFor('AB12'), SensorStatus.live);
      expect(service.latest.value.containsKey('AB12'), isTrue);
      await service.stop();
      expect(scanner.stopped, isTrue);
    });

    test('permesso negato: errore riproposto, servizio non attivo',
        () async {
      scanner.failOnStart = true;
      await expectLater(service.start(), throwsA(isA<Exception>()));
      expect(service.isRunning, isFalse);
    });
  });
}

/// Scanner finto per i test (nessun Bluetooth reale).
class FakeScanner implements SensorScanner {
  final _controller = StreamController<List<BleAdvertisement>>.broadcast();
  bool failOnStart = false;
  bool stopped = false;

  @override
  Stream<List<BleAdvertisement>> get advertisements => _controller.stream;

  @override
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) async {
    if (failOnStart) throw Exception('permesso Bluetooth negato');
  }

  @override
  Future<void> stop() async => stopped = true;

  void emit(List<BleAdvertisement> advertisements) =>
      _controller.add(advertisements);
}
