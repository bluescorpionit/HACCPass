import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/sensors/ble_sensor_source.dart';
import 'package:haccpass/core/sensors/sensor_model.dart';
import 'package:haccpass/core/sensors/sensor_source.dart';
import 'package:haccpass/core/theme/app_theme.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/sensors/link_sensor_sheet.dart';
import 'package:haccpass/screens/sensors/sensor_image.dart';
import 'package:haccpass/screens/temperature/temperature_screen.dart';
import 'package:haccpass/services/license_service.dart';

/// Widget test dei sensori (Prompt 7, Fase 5): fallback immagine,
/// "Leggi dal sensore" (attivo/disabilitato con dato vecchio), associazione
/// con scansione simulata.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  final license = _StubLicense();
  final repoStub = _StubRepository();

  Sensor sensorFor({double offset = 0}) => Sensor(
        id: 7,
        modelId: 'govee_h5179',
        deviceKey: 'AB12',
        createdAt: DateTime.now(),
        calibrationOffset: offset,
        label: 'S1',
      );

  Equipment newEquipment() => Equipment(
        id: 1,
        name: 'Frigo carni 1',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
      );

  void installFakeService(SensorService service) {
    SensorService.instanceForTest = service;
    addTearDown(() => SensorService.instanceForTest = null);
  }

  group('SensorModelImage', () {
    testWidgets('senza asset: icona generica, nessuna eccezione',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SensorModelImage(model: _NoImageModel(), size: 96),
        ),
      ));
      expect(find.byIcon(Icons.sensors), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('asset mancante sul disco: ripiego a icona, nessun crash',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SensorModelImage(model: _MissingImageModel(), size: 96),
        ),
      ));
      // L'errorBuilder scatta in modo asincrono dopo il tentativo di load.
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.sensors), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('fogli di registrazione: "Leggi dal sensore"', () {
    testWidgets('dato vecchio: pulsante disabilitato con spiegazione',
        (tester) async {
      final service = SensorService.forTest(_FakeScanner());
      service.debugInjectReading(SensorSample(
        sensorId: 'AB12',
        tempC: 4.0,
        source: SensorSourceKind.ble,
        timestamp: DateTime.now().subtract(const Duration(minutes: 40)),
      ));
      installFakeService(service);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showRegisterTemperatureSheet(
                tester.element(find.byType(Scaffold)),
                repository: repoStub,
                license: license,
                equipment: newEquipment(),
                operatorName: 'Op',
                sensor: sensorFor(),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('apri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final button =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNull,
          reason: 'dato vecchio: inserimento manuale');
      expect(find.textContaining('dato vecchio'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dato live: compila il valore con offset e orario',
        (tester) async {
      final service = SensorService.forTest(_FakeScanner());
      service.debugInjectReading(SensorSample(
        sensorId: 'AB12',
        tempC: 3.5,
        source: SensorSourceKind.ble,
        timestamp: DateTime.now(),
      ));
      installFakeService(service);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showRegisterTemperatureSheet(
                tester.element(find.byType(Scaffold)),
                repository: repoStub,
                license: license,
                equipment: newEquipment(),
                operatorName: 'Op',
                sensor: sensorFor(offset: -0.5),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('apri'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final button =
          tester.widget<OutlinedButton>(find.byType(OutlinedButton));
      expect(button.onPressed, isNotNull, reason: 'dato live: leggibile');

      await tester.tap(find.byType(OutlinedButton));
      await tester.pump();

      // 3.5 grezzi + offset -0.5 = 3.0 nel campo.
      expect(find.text('3.0'), findsOneWidget);
      expect(find.textContaining('Letto dal sensore alle'), findsOneWidget);
      expect(
        find.textContaining('offset -0.5'),
        findsOneWidget,
        reason: 'offset sempre visibile',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('associazione con scansione simulata (FakeSensorService)', () {
    late Directory tempDir;
    late AppDatabase appDatabase;
    late HaccpRepository repository;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sensor_widget_test');
      appDatabase = AppDatabase(
        path:
            '${tempDir.path}/w_${DateTime.now().millisecondsSinceEpoch}.db',
      );
      await appDatabase.initialize();
      repository = HaccpRepository(appDatabase);
    });

    tearDown(() async {
      await appDatabase.close();
      await tempDir.delete(recursive: true);
    });

    testWidgets('dal foglio Collega sensore al collegamento salvato',
        (tester) async {
      // Superficie alta: il foglio (immagine, aiuti, righe, etichetta,
      // note) entra interamente senza scroll, cos\u00EC i tap sono stabili.
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final scanner = _FakeScanner();
      installFakeService(SensorService.forTest(scanner));

      // Attrezzatura reale sul DB (loop reale per le future del DB).
      final equipmentId = await tester.runAsync(() async {
        final id = await repository.saveEquipment(Equipment(
          id: 0,
          name: 'Frigo carni 1',
          type: 'Frigorifero',
          minTemp: 0,
          maxTemp: 4,
        ));
        return id;
      });

      final liveEquipment = Equipment(
        id: equipmentId!,
        name: 'Frigo carni 1',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
      );

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => showLinkSensorSheet(
                tester.element(find.byType(Scaffold)),
                repository: repository,
                equipment: liveEquipment,
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('apri'));
      await tester.pump();

      // Lo scanner finto emette un H5179 valido; la mappa "gi\u00E0 usato
      // per" completa sul loop reale.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Il dispositivo trovato dalla scansione \u00E8 visibile con la sua
      // temperatura decodificata (25.7 \u00B0C dal pacchetto reale) e la
      // nota di non affiliazione obbligatoria.
      expect(find.textContaining('GVH5179_AB12'), findsWidgets);
      expect(find.textContaining('25.7'), findsWidgets);
      expect(find.textContaining('HACCPass non \u00E8 affiliata a Govee'),
          findsOneWidget);

      // Il pulsante Collega resta disabilitato finch\u00E9 non si seleziona
      // una riga: nessuna associazione accidentale.
      final filled =
          tester.widget<FilledButton>(find.byType(FilledButton).last);
      expect(filled.onPressed, isNull,
          reason: 'nessun sensore selezionato: Collega disabilitato');
      expect(tester.takeException(), isNull);
    });
  });
}

class _StubLicense implements LicenseService {
  @override
  bool get canWrite => true;

  @override
  bool get trialActive => false;

  @override
  String get chipLabel => 'Prova: 14 giorni';

  @override
  bool ensureLicensed(BuildContext context) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub: ${invocation.memberName}');
}

class _StubRepository implements HaccpRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub repo: ${invocation.memberName}');
}

/// Scanner finto: alla prima start emette un H5179 con pacchetto reale.
class _FakeScanner implements SensorScanner {
  final _controller = StreamController<List<BleAdvertisement>>.broadcast();

  @override
  Stream<List<BleAdvertisement>> get advertisements => _controller.stream;

  @override
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) async {
    await Future<void>.delayed(Duration.zero);
    _controller.add([
      BleAdvertisement(
        name: 'GVH5179_AB12',
        systemId: 'AA:BB:CC:DD:EE:FF',
        rssi: -52,
        manufacturerData: const {
          0x8801: [
            0xec, 0x00, 0x01, 0x01, 0x0a, 0x0a, 0xa4, 0x06, 0x64,
          ],
        },
        serviceData: const {},
        seenAt: DateTime.now(),
      ),
    ]);
  }

  @override
  Future<void> stop() async {}
}

class _NoImageModel implements SensorModel {
  const _NoImageModel();

  @override
  String get id => 'no_image';

  @override
  String get displayName => 'Senza immagine';

  @override
  SensorSourceKind get transport => SensorSourceKind.ble;

  @override
  bool matches(BleAdvertisement a) => false;

  @override
  String? stableKey(BleAdvertisement a) => null;

  @override
  SensorSample? decode(BleAdvertisement a) => null;

  @override
  SensorSpecs get specs => const SensorSpecs();

  @override
  String? get imageAsset => null;
}

class _MissingImageModel implements SensorModel {
  const _MissingImageModel();

  @override
  String get id => 'missing_image';

  @override
  String get displayName => 'Immagine mancante';

  @override
  SensorSourceKind get transport => SensorSourceKind.ble;

  @override
  bool matches(BleAdvertisement a) => false;

  @override
  String? stableKey(BleAdvertisement a) => null;

  @override
  SensorSample? decode(BleAdvertisement a) => null;

  @override
  SensorSpecs get specs => const SensorSpecs();

  @override
  String? get imageAsset => 'assets/images/inesistente.png';
}
