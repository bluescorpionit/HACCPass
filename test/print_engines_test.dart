import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/printing/label_printer.dart';
import 'package:haccpass/core/printing/label_rasterizer.dart';
import 'package:haccpass/services/printing/byte_transport.dart';
import 'package:haccpass/services/printing/generic_label_printer.dart';
import 'package:haccpass/services/printing/niimbot_label_printer.dart';
import 'package:haccpass/services/printing/print_coordinator.dart';

/// Prompt 11: selezione del motore dalle impostazioni, mappa formato →
/// carta Brother, controllo larghezza Niimbot (dal dispositivo), risultati
/// di errore in italiano, ripiego, trasporto con perdita e nuovo tentativo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pdfBytes = <Uint8List>[Uint8List.fromList([1, 2, 3])];

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
      expect(fake.printCalls.length, 2, reason: 'si ferma subito dopo l\'annullo');
    });

    test('risultati simulati del motore → messaggi in italiano', () async {
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
    test('etichetta più larga della testina: mai taglio silenzioso',
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

    test('B21 (48 mm): formato 40x30 ammesso, densità clampata', () async {
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
      expect(adapter.printCalls.single.$2, 5, reason: 'densità clampata al max');
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

  group('GenericLabelPrinter: area stampabile (punti, non mm di carta)',
      () {
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

    test('40x30 su carta 58 mm: entra (320 px ≤ 384) e stampa', () async {
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

    test('300 dpi: proporzionale (58 mm → 568 punti), 62x40 rifiutato',
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

    test('punti personalizzati (432): 50x30 @203 entra (400 ≤ 432)',
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

    test('indirizzo mancante: messaggio chiaro, nessuna invocazione',
        () async {
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

  group('GenericBleScanner (Prompt 11-bis, §3)', () {
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

    test('permesso negato: errore tipizzato in italiano', () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => false,
      );
      await expectLater(
        scanner.discover(),
        throwsA(
          isA<PrinterDiscoveryException>().having(
            (e) => e.message,
            'message',
            contains('Permesso Bluetooth negato'),
          ),
        ),
      );
    });

    test('Bluetooth spento: errore esplicito', () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => true,
        adapterIsOn: () async => false,
      );
      await expectLater(
        scanner.discover(),
        throwsA(
          isA<PrinterDiscoveryException>().having(
            (e) => e.message,
            'message',
            contains('Bluetooth spento'),
          ),
        ),
      );
    });

    test('raccolta per tutta la durata: i ritardi contano comunque',
        () async {
      final scanner = GenericBleScanner(
        requestPermissions: () async => true,
        adapterIsOn: () async => true,
        scan: (timeout, onHit) async {
          onHit('AA:1', 'Subito');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          onHit('BB:2', 'Dopo-il-timeout-di-avvio');
        },
      );
      final devices = await scanner.discover(
        timeout: const Duration(milliseconds: 50),
      );
      expect(devices.length, 2,
          reason: 'il risultato posticipato viene raccolto');
    });
  });

  group('blocchi BLE e MTU (Prompt 11-bis, §4)', () {
    for (final (mtu, expectedChunk) in const [
      (23, 20),
      (185, 182),
      (517, 512),
    ]) {
      test('MTU $mtu → blocchi da $expectedChunk byte', () async {
        final transport = FakeByteTransport(mtu: mtu);
        await transport.connect();
        expect(transport.suggestedChunkSize, expectedChunk);
        await transport.write(List<int>.filled(1000, 0x55));
        expect(transport.chunkSizes, isNotEmpty);
        expect(
          transport.chunkSizes.every((size) => size <= expectedChunk),
          isTrue,
          reason: 'nessun blocco oltre il limite MTU',
        );
        expect(transport.written.length, 1000, reason: 'tutti i byte arrivano');
      });
    }

    test('sendWithRetry usa la dimensione consigliata dal trasporto',
        () async {
      final transport = FakeByteTransport(mtu: 23); // blocchi da 20
      await transport.connect();
      final ok = await sendWithRetry(transport, List<int>.filled(100, 1));
      expect(ok, isTrue);
      expect(transport.chunkSizes.every((s) => s <= 20), isTrue);
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

    test('sendWithRetry: due fallimenti → false', () async {
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
    (key) async =>
        settings[key]?.isNotEmpty == true ? settings[key] : null,
    engineFactories: {'fake': () => _FakeLabelPrinter(id: 'fake')},
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

  /// (immagine, densità, copie)
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
