import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/printing/label_printer.dart';
import 'package:haccpass/core/printing/label_rasterizer.dart';
import 'package:haccpass/services/printing/byte_transport.dart';
import 'package:haccpass/services/printing/generic_label_printer.dart';
import 'package:haccpass/services/printing/niimbot_label_printer.dart';
import 'package:haccpass/services/printing/print_coordinator.dart';

/// Prompt 11: selezione del motore dalle impostazioni, mappa formato ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢
/// carta Brother, controllo larghezza Niimbot (dal dispositivo), risultati
/// di errore in italiano, ripiego, trasporto con perdita e nuovo tentativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pdfBytes = <Uint8List>[
    Uint8List.fromList([1, 2, 3])
  ];

  group('PrintCoordinator.load: motore dalle impostazioni', () {
    test('motore salvato viene costruito', () async {
      final coordinator = await _loadWith({
        'printer_engine': 'fake',
        'printer_device_id': 'wifi:192.168.1.60|QL-820NWB',
        'printer_device_name': 'QL-820NWB',
        'printer_label_format': '50x30',
        'printer_density': '4',
      });
      expect(coordinator.isConfigured, isTrue);
      expect(coordinator.engine!.id, 'fake',
          reason: 'il motore salvato nelle impostazioni viene costruito');
      expect(coordinator.settings.format, '50x30');
      expect(coordinator.settings.spec.widthMm, 50);
      expect(coordinator.settings.spec.density, 4);
    });

    test('nessun motore: non configurato, l\'app resta usabile', () async {
      final coordinator = await _loadWith(const {});
      expect(coordinator.isConfigured, isFalse);
      final result = await coordinator.printPdf(pdfBytes);
      expect(result.outcome, PrintOutcome.notConnected);
      expect(result.italianMessage, contains('Nessuna stampante configurata'));
    });

    test('formato default da label_format del wizard', () async {
      final coordinator = await _loadWith({
        'printer_engine': 'system',
        'label_format': '40x30',
      });
      expect(coordinator.settings.format, '40x30');
    });

    test('config generica letta dalle impostazioni', () async {
      final coordinator = await _loadWith({
        'printer_engine': 'generic',
        'printer_generic_transport': 'wifi',
        'printer_generic_address': '192.168.1.90',
        'printer_generic_language': 'tspl',
        'printer_generic_dpi': '300',
        'printer_generic_paper_width': '80',
      });
      expect(coordinator.settings.generic.language, GenericLanguage.tspl);
      expect(coordinator.settings.generic.dpi, 300);
      expect(coordinator.settings.generic.paperWidthMm, 80);
      expect(coordinator.settings.generic.address, '192.168.1.90');
    });
  });

  group('PrintCoordinator.printPdf: coda e riconnessione', () {
    test('un\'etichetta alla volta con avanzamento', () async {
      final fake = _FakeLabelPrinter(id: 'fake');
      final coordinator = _coordinatorWith(fake);
      final progress = <int>[];

      final result = await coordinator.printPdf(
        pdfBytes,
        copies: 3,
        onProgress: (done, total) => progress.add(done),
      );

      expect(result.isOk, isTrue);
      expect(fake.printCalls.length, 3, reason: 'una stampa per copia');
      expect(fake.connectCalls, 1, reason: 'ricollegata SOLO quando serve');
      expect(progress, [1, 2, 3]);
    });

    test('riconnessione fallita: messaggio con "Seleziona stampante"',
        () async {
      final fake = _FakeLabelPrinter(id: 'fake', connectFails: true);
      final result = await _coordinatorWith(fake).printPdf(pdfBytes);
      expect(result.outcome, PrintOutcome.notConnected);
      expect(result.italianMessage, contains('seleziona di nuovo'));
    });

    test('annullamento interrompe la coda', () async {
      final fake = _FakeLabelPrinter(id: 'fake');
      final cancel = PrintCancel();
      final coordinator = _coordinatorWith(fake);

      final result = await coordinator.printPdf(
        pdfBytes,
        copies: 5,
        onProgress: (done, total) {
          if (done == 2) cancel.cancel();
        },
        cancel: cancel,
      );

      expect(result.outcome, PrintOutcome.cancelled);
      expect(fake.printCalls.length, 2,
          reason: 'si ferma subito dopo l\'annullo');
    });

    test(
        'risultati simulati del motore ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ messaggi in italiano',
        () async {
      for (final (outcome, expected) in const [
        (PrintOutcome.paperError, 'Carta assente'),
        (PrintOutcome.coverOpen, 'Coperchio aperto'),
        (PrintOutcome.busy, 'Stampante occupata'),
        (PrintOutcome.labelSizeNotSupported, 'non adatto'),
      ]) {
        final fake = _FakeLabelPrinter(id: 'fake')
          ..nextResult = PrintResult(outcome);
        final result = await _coordinatorWith(fake).printPdf(pdfBytes);
        expect(result.outcome, outcome);
        expect(result.italianMessage, contains(expected), reason: '$outcome');
      }
    });
  });

  group('NiimbotLabelPrinter: larghezza dal dispositivo', () {
    test(
        'etichetta piÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¹ larga della testina: mai taglio silenzioso',
        () async {
      final adapter = _FakeNiimAdapter(
        capabilities: const _Caps(
          model: 'D11',
          dpi: 203,
          printheadPixels: 96, // ~12 mm
          densityMin: 1,
          densityMax: 3,
        ),
      );
      final printer = NiimbotLabelPrinter(adapter: adapter);
      await printer.connect(const PrinterDevice(
        name: 'D11',
        id: 'AA:BB',
        transport: PrintTransport.ble,
      ));

      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '62x40'),
      );

      expect(result.outcome, PrintOutcome.labelSizeNotSupported);
      expect(
        result.italianMessage,
        contains('non stampa etichette da 62 mm'),
      );
      expect(adapter.printCalls, isEmpty, reason: 'non invia nulla');
    });

    test(
        'B21 (48 mm): formato 40x30 ammesso, densitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  clampata',
        () async {
      final adapter = _FakeNiimAdapter(
        capabilities: const _Caps(
          model: 'B21',
          dpi: 203,
          printheadPixels: 384,
          densityMin: 1,
          densityMax: 5,
        ),
      );
      final printer = NiimbotLabelPrinter(
        adapter: adapter,
        rasterizer: _StubRasterizer(),
      );
      await printer.connect(const PrinterDevice(
        name: 'B21',
        id: 'AA:CC',
        transport: PrintTransport.ble,
      ));

      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '40x30', density: 9),
        copies: 2,
      );

      expect(result.isOk, isTrue);
      expect(adapter.printCalls.single.$2, 5,
          reason: 'densitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  clampata al max');
      expect(adapter.printCalls.single.$3, 2);
    });

    test('non collegata: notConnected senza crash', () async {
      final printer = NiimbotLabelPrinter(adapter: _FakeNiimAdapter());
      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '62x40'),
      );
      expect(result.outcome, PrintOutcome.notConnected);
    });
  });

  group('GenericLabelPrinter: area stampabile (punti, non mm di carta)', () {
    Future<PrintResult> printWith({
      required String format,
      required GenericPrinterConfig config,
    }) {
      final transport = FakeByteTransport();
      final printer = GenericLabelPrinter(
        config: config,
        rasterizer: _StubRasterizer(),
        transportFactory: (_) => transport,
      );
      return printer.printLabels(pdfBytes, LabelSpec(format: format));
    }

    test('62x40 su carta 58 mm (384 punti @203): rifiutato', () async {
      final result = await printWith(
        format: '62x40',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          paperWidthMm: 58,
        ),
      );
      expect(result.outcome, PrintOutcome.labelSizeNotSupported);
      // 496 px richiesti > 384 stampabili: nessun taglio silenzioso.
      expect(result.italianMessage, contains('massimo 48 mm'));
      expect(result.italianMessage, contains('carta da 58 mm'));
    });

    test('50x30 su carta 58 mm: rifiutato (400 px > 384)', () async {
      final result = await printWith(
        format: '50x30',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          paperWidthMm: 58,
        ),
      );
      expect(result.outcome, PrintOutcome.labelSizeNotSupported);
      expect(result.italianMessage, contains('50 mm'));
    });

    test(
        '40x30 su carta 58 mm: entra (320 px ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°Ãƒâ€šÃ‚Â¤ 384) e stampa',
        () async {
      final result = await printWith(
        format: '40x30',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          paperWidthMm: 58,
        ),
      );
      expect(result.isOk, isTrue);
    });

    test('62x40 su carta 80 mm (576 punti @203): entra e stampa', () async {
      final result = await printWith(
        format: '62x40',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          paperWidthMm: 80,
        ),
      );
      expect(result.isOk, isTrue);
    });

    test(
        '300 dpi: proporzionale (58 mm ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 568 punti), 62x40 rifiutato',
        () async {
      final result = await printWith(
        format: '62x40',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          dpi: 300,
          paperWidthMm: 58,
        ),
      );
      // 62 mm @300 dpi = 736 px > 568.
      expect(result.outcome, PrintOutcome.labelSizeNotSupported);
    });

    test(
        'punti personalizzati (432): 50x30 @203 entra (400 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â°Ãƒâ€šÃ‚Â¤ 432)',
        () async {
      final result = await printWith(
        format: '50x30',
        config: const GenericPrinterConfig(
          transport: 'wifi',
          address: '10.0.0.5',
          paperWidthMm: 58,
          printableWidthDots: 432,
        ),
      );
      expect(result.isOk, isTrue);
    });

    test('indirizzo mancante: messaggio chiaro, nessuna invocazione', () async {
      final printer = GenericLabelPrinter(
        config: const GenericPrinterConfig(transport: 'wifi'),
      );
      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '50x30'),
      );
      expect(result.outcome, PrintOutcome.notConnected);
      expect(result.italianMessage, contains('Inserisci l\u2019indirizzo'));
    });
  });

  group('GenericBleScanner (Prompt 11-bis, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§3)', () {
    test('risultati deduplicati per remoteId, nomi vuoti scartati', () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => true,
        adapterIsOn: () async => true,
        scan: (timeout, onHit) async {
          onHit('AA:1', 'Printer-X');
          onHit('AA:1', 'Printer-X'); // duplicato
          onHit('BB:2', '');
          onHit('CC:3', 'Printer-Y');
        },
      );
      final devices = await scanner.discover(
        timeout: const Duration(milliseconds: 10),
      );
      expect(devices.length, 2);
      expect(devices.map((d) => d.id), containsAll(['AA:1', 'CC:3']));
      expect(devices.every((d) => d.transport == PrintTransport.ble), isTrue);
    });

    test('permesso negato: messaggi distinti in italiano', () {
      // Il permesso su host e' concesso di default: si verifica la mappa
      // dei messaggi del trasporto SPP (Prompt 17, sezione 4).
      expect(
        BluetoothSppByteTransport.messageForCode('permission'),
        contains('Permesso Bluetooth negato'),
      );
      expect(
        BluetoothSppByteTransport.messageForCode('not_bonded'),
        contains('non associata'),
      );
      expect(
        BluetoothSppByteTransport.messageForCode('unreachable'),
        contains('accendi la stampante e avvicinala'),
      );
      expect(
        BluetoothSppByteTransport.messageForCode('busy'),
        contains('scollegala'),
      );
      expect(
        BluetoothSppByteTransport.messageForCode('off'),
        contains('Bluetooth spento'),
      );
    });

    test('ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§2: looksLikePrinter riconosce i nomi tipici', () {
      expect(BluetoothSppByteTransport.looksLikePrinter('MTP-58'), isTrue);
      expect(BluetoothSppByteTransport.looksLikePrinter('XP-5820'), isTrue);
      expect(BluetoothSppByteTransport.looksLikePrinter('Auricolarino auto'),
          isFalse);
    });

    test(
        'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§1: una sola connessione SPP per lavoro con piÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¹ copie',
        () async {
      final transport = FakeByteTransport();
      final printer = GenericLabelPrinter(
        config: const GenericPrinterConfig(
          transport: 'bluetooth',
          address: 'AA:BB:CC:DD:EE:FF',
        ),
        rasterizer: _StubRasterizer(),
        transportFactory: (_) => transport,
      );
      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '40x30'),
        copies: 3,
      );
      expect(result.isOk, isTrue);
      expect(transport.connectCalls, 1);
    });

    test(
        'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§1: profili di velocitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  (blocchi/pausa/bande)',
        () {
      expect(PrintSpeedProfile.normal.chunkBytes, 256);
      expect(PrintSpeedProfile.slow.chunkBytes, 128);
      expect(PrintSpeedProfile.fast.chunkBytes, 512);
      expect(PrintSpeedProfile.normal.bandRows, 64);
      expect(PrintSpeedProfile.slow.bandRows, 24);
      expect(PrintSpeedProfile.fast.bandRows, 128);
      expect(PrintSpeedProfile.byId('slow').pause,
          const Duration(milliseconds: 50));
      expect(PrintSpeedProfile.byId('sconosciuto').id, 'normal');
    });

    test(
        'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§3: 62x40 e 50x30 su 58 mm con fit=reject ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ rifiutati',
        () async {
      for (final format in const ['62x40', '50x30']) {
        final printer = GenericLabelPrinter(
          config: const GenericPrinterConfig(
            address: '10.0.0.5',
            fitMode: 'reject',
          ),
          rasterizer: _StubRasterizer(),
          transportFactory: (_) => FakeByteTransport(),
        );
        final result = await printer.printLabels(
          pdfBytes,
          LabelSpec(format: format),
        );
        expect(result.outcome, PrintOutcome.labelSizeNotSupported,
            reason: format);
        expect(result.italianMessage, contains('ridurla per adattarla'));
      }
    });

    test(
        'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§3: fit=shrink rasterizza alla larghezza stampabile (multipla di 8)',
        () async {
      final rasterizer = _RecordingRasterizer();
      final printer = GenericLabelPrinter(
        config: const GenericPrinterConfig(
          address: '10.0.0.5',
          fitMode: 'shrink',
        ),
        rasterizer: rasterizer,
        transportFactory: (_) => FakeByteTransport(),
      );
      final result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '62x40'),
      );
      expect(result.isOk, isTrue);
      // Larghezza richiesta al rasterizzatore = 384 px a 203 dpi.
      final widthPx = rasterWidthForMm(rasterizer.lastWidthMm!, 203);
      expect(widthPx, 384);
      expect(widthPx % 8, 0);
      expect(printer.lastJobSummary, contains('RIDOTTA alla carta'));
    });

    test('ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§3: 40x30 su 58 mm e 62x40 su 80 mm non riducono',
        () async {
      final rasterizer = _RecordingRasterizer();
      final printer = GenericLabelPrinter(
        config: const GenericPrinterConfig(address: '10.0.0.5'),
        rasterizer: rasterizer,
        transportFactory: (_) => FakeByteTransport(),
      );
      // 40x30 su 58: entra.
      var result = await printer.printLabels(
        pdfBytes,
        const LabelSpec(format: '40x30'),
      );
      expect(result.isOk, isTrue);
      expect(rasterWidthForMm(rasterizer.lastWidthMm!, 203), 320);

      // 62x40 su 80 mm: entra.
      final wide = GenericLabelPrinter(
        config:
            const GenericPrinterConfig(address: '10.0.0.5', paperWidthMm: 80),
        rasterizer: rasterizer,
        transportFactory: (_) => FakeByteTransport(),
      );
      result =
          await wide.printLabels(pdfBytes, const LabelSpec(format: '62x40'));
      expect(result.isOk, isTrue);
      expect(rasterWidthForMm(rasterizer.lastWidthMm!, 203), 496);
      expect(wide.lastJobSummary, isNot(contains('RIDOTTA')));
    });

    test(
        'ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§3: avviso di leggibilitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  quando la riduzione ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¨ forte',
        () async {
      final shrink = GenericLabelPrinter(
        config:
            const GenericPrinterConfig(address: '10.0.0.5', fitMode: 'shrink'),
      );
      // 62 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 48 mm: rapporto ~0,77 < 0,8 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ avviso.
      expect(shrink.readabilityWarningNeeded(const LabelSpec(format: '62x40')),
          isTrue);
      // 50 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ 48 mm: rapporto ~0,96 ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ nessun avviso.
      expect(shrink.readabilityWarningNeeded(const LabelSpec(format: '50x30')),
          isFalse);
      // 40 mm: entra, nessun avviso.
      expect(shrink.readabilityWarningNeeded(const LabelSpec(format: '40x30')),
          isFalse);
    });
  });

  group('Prompt 17: SPP (recupero)', () {
    test('transport bluetooth arriva al motore col profilo slow', () async {
      final settingsMap = const {
        'printer_engine': 'generic',
        'printer_generic_transport': 'bluetooth',
        'printer_generic_address': 'AA:BB:CC:DD:EE:FF',
        'printer_generic_speed': 'slow',
      };
      final coordinator = await PrintCoordinator.loadFrom(
        (key) async => settingsMap[key],
      );
      final engine = coordinator.engine as GenericLabelPrinter;
      expect(engine.config.transport, 'bluetooth');
      expect(engine.config.speedProfile.chunkBytes, 128);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        expect(
            engine.config.buildTransport(), isA<BluetoothSppByteTransport>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('connect() Bluetooth memorizza e non ricade su Wi-Fi', () async {
      var built = 0;
      final printer = GenericLabelPrinter(
        transportFactory: (_) {
          built++;
          return FakeByteTransport();
        },
      );
      await printer.connect(const PrinterDevice(
        name: 'POS-58',
        id: 'bt:AA:BB:CC:DD:EE:FF',
        transport: PrintTransport.bluetooth,
      ));
      expect(built, 0, reason: 'connect() non apre connessioni');
      expect(printer.config.transport, 'bluetooth');
      expect(printer.config.address, 'AA:BB:CC:DD:EE:FF');
    });

    test('elenco associati: stampanti prima, nome vuoto -> MAC', () async {
      final printer = GenericLabelPrinter(
        config: const GenericPrinterConfig(transport: 'bluetooth'),
        pairedLister: () async => const [
          (name: 'Auricolarino', address: 'AA:00:00:00:00:01'),
          (name: '', address: 'BB:00:00:00:00:02'),
          (name: 'MTP-58 Printer', address: 'CC:00:00:00:00:03'),
        ],
      );
      final devices = await printer.discover();
      expect(devices.length, 3);
      expect(devices.first.name, 'MTP-58 Printer');
      expect(devices[1].name, 'Dispositivo 00:02');
      expect(devices[2].name, 'Auricolarino');
      expect(devices[1].id, 'bt:BB:00:00:00:00:02');
      expect(devices.every((d) => d.transport == PrintTransport.bluetooth),
          isTrue);
    });
  });

  group('GenericBleScanner (recupero)', () {
    test('risultati deduplicati per remoteId, nomi vuoti scartati', () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => true,
        adapterIsOn: () async => true,
        scan: (timeout, onHit) async {
          onHit('AA:1', 'Printer-X');
          onHit('AA:1', 'Printer-X');
          onHit('BB:2', '');
          onHit('CC:3', 'Printer-Y');
        },
      );
      final devices =
          await scanner.discover(timeout: const Duration(milliseconds: 10));
      expect(devices.length, 2);
      expect(devices.map((d) => d.id), containsAll(['AA:1', 'CC:3']));
    });

    test('permesso negato: errore tipizzato', () async {
      final scanner = GenericBleScanner(requestPermissions: () async => false);
      await expectLater(
        scanner.discover(),
        throwsA(isA<PrinterDiscoveryException>().having(
          (e) => e.message,
          'message',
          contains('Permesso Bluetooth negato'),
        )),
      );
    });

    test('Bluetooth spento: errore esplicito', () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => true,
        adapterIsOn: () async => false,
      );
      await expectLater(
        scanner.discover(),
        throwsA(isA<PrinterDiscoveryException>().having(
          (e) => e.message,
          'message',
          contains('Bluetooth spento'),
        )),
      );
    });
  });

  group('trasporto con perdita di connessione', () {
    test('sendWithRetry: primo invio fallisce, secondo riesce', () async {
      final transport = FakeByteTransport(failAtBytes: 100);
      await transport.connect();
      final ok = await sendWithRetry(
        transport,
        List<int>.filled(400, 0xAA),
        chunkSize: 128,
      );
      expect(ok, isTrue);
      expect(transport.connectCalls, 2, reason: 'una riconnessione');
      expect(transport.written.length, 400,
          reason: 'il nuovo tentativo rinvia tutto');
    });

    test(
        'sendWithRetry: due fallimenti ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ false',
        () async {
      final transport = _AlwaysFailingTransport();
      final ok = await sendWithRetry(transport, [1, 2, 3]);
      expect(ok, isFalse);
      expect(transport.closeCalls, greaterThanOrEqualTo(2));
    });
  });
}

// ---------------------------------------------------------------------------
// Finti
// ---------------------------------------------------------------------------

Future<PrintCoordinator> _loadWith(Map<String, String> settings) {
  return PrintCoordinator.loadFrom(
    (key) async => settings[key]?.isNotEmpty == true ? settings[key] : null,
    engineFactories: {'fake': (_) => _FakeLabelPrinter(id: 'fake')},
  );
}

PrintCoordinator _coordinatorWith(_FakeLabelPrinter fake) {
  return PrintCoordinator.forTest(
    PrintSettings(
      engine: 'fake',
      deviceId: 'fake-device',
      deviceName: 'Finta',
      format: '62x40',
      density: 3,
    ),
    fake,
  );
}

class _FakeLabelPrinter implements LabelPrinter {
  _FakeLabelPrinter({required this.id, this.connectFails = false});

  @override
  final String id;

  final bool connectFails;

  int connectCalls = 0;
  final List<void> printCalls = [];
  PrintResult? nextResult;
  bool connected = false;

  @override
  String get displayName => 'Finta $id';

  @override
  Future<List<PrinterDevice>> discover() async => const [];

  @override
  Future<void> connect(PrinterDevice device) async {
    connectCalls++;
    if (connectFails) {
      throw StateError('non raggiungibile');
    }
    connected = true;
  }

  @override
  Future<void> disconnect() async => connected = false;

  @override
  bool get isConnected => connected;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    printCalls.add(null);
    return nextResult ?? const PrintResult(PrintOutcome.ok);
  }

  @override
  Future<PrinterStatus> status() async => PrinterStatus(connected: connected);
}

class _Caps implements NiimbotCapabilities {
  const _Caps({
    required this.model,
    required this.dpi,
    required this.printheadPixels,
    required this.densityMin,
    required this.densityMax,
  });

  @override
  final String model;
  @override
  final int dpi;
  @override
  final int printheadPixels;
  @override
  final int densityMin;
  @override
  final int densityMax;

  @override
  int get maxPrintableMm => (printheadPixels / dpi * 25.4).floor();
}

class _FakeNiimAdapter implements NiimbotClientAdapter {
  _FakeNiimAdapter({this.capabilities});

  final NiimbotCapabilities? capabilities;

  /// (immagine, densitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â , copie)
  final List<(MonoBitmap, int, int)> printCalls = [];

  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Future<List<PrinterDevice>> discover() async => const [];

  @override
  Future<NiimbotCapabilities> connect(String deviceId) async {
    if (capabilities == null) {
      throw StateError('nessuna stampante');
    }
    _connected = true;
    return capabilities!;
  }

  @override
  Future<void> disconnect() async => _connected = false;

  @override
  Future<void> printMono(
    MonoBitmap image, {
    required int density,
    int copies = 1,
  }) async {
    printCalls.add((image, density, copies));
  }
}

class _StubRasterizer extends LabelRasterizer {
  @override
  Future<MonoBitmap> rasterPdfPage(
    Uint8List pdf, {
    required int dpi,
    required double widthMm,
  }) async =>
      MonoBitmap(
        width: 64,
        height: 32,
        packed: Uint8List(8 * 32),
      );
}

class _AlwaysFailingTransport extends FakeByteTransport {
  @override
  Future<void> writeChunk(List<int> bytes) async {
    throw const SocketExceptionSimulated();
  }
}

class SocketExceptionSimulated implements Exception {
  const SocketExceptionSimulated();
}

// ===========================================================================
// Prompt 17: Bluetooth classico SPP e adattamento alla carta
// ===========================================================================
void main17() {}

extension Prompt17Tests on Never {
  static void noop() {}
}

/// Rasterizzatore finto che registra l'ultima larghezza richiesta.
class _RecordingRasterizer extends LabelRasterizer {
  double? lastWidthMm;

  @override
  Future<MonoBitmap> rasterPdfPage(
    Uint8List pdf, {
    required int dpi,
    required double widthMm,
  }) async {
    lastWidthMm = widthMm;
    return MonoBitmap(
      width: rasterWidthForMm(widthMm, dpi),
      height: 40,
      packed: Uint8List(rasterWidthForMm(widthMm, dpi) ~/ 8 * 40),
    );
  }
}
