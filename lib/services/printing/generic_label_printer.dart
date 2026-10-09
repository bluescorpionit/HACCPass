import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/printing/escpos_encoder.dart';
import '../../core/printing/label_printer.dart';
import '../../core/printing/label_rasterizer.dart';
import '../../core/printing/tspl_encoder.dart';
import 'bluetooth_permissions.dart';
import 'byte_transport.dart';

/// Linguaggio della stampante generica (Prompt 11, §3 bis).
enum GenericLanguage { escpos, tspl }

extension GenericLanguageX on GenericLanguage {
  String get settingValue =>
      this == GenericLanguage.escpos ? 'escpos' : 'tspl';

  String get label => this == GenericLanguage.escpos
      ? 'ESC/POS (scontrini e termiche generiche)'
      : 'TSPL (stampanti di etichette con carta a gap)';
}

/// Errore tipizzato della ricerca stampanti (Prompt 11-bis, §3): mai
/// elenchi vuoti muti, sempre un messaggio in italiano.
class PrinterDiscoveryException implements Exception {
  const PrinterDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Configurazione della stampante generica: tutto DICHIARATO dal
/// cliente, niente indovinato (larghezza carta, linguaggio, dpi, punti
/// stampabili).
class GenericPrinterConfig {
  const GenericPrinterConfig({
    this.transport = 'wifi',
    this.address = '',
    this.characteristicId,
    this.language = GenericLanguage.escpos,
    this.dpi = 203,
    this.paperWidthMm = 58,
    this.printableWidthDots,
    this.invertTspl = false,
  });

  /// `wifi` | `ble` (bluetooth classico SPP e USB non disponibili in
  /// questa versione, vedi docs/stampanti.md).
  final String transport;

  /// Indirizzo IP (wifi) o remoteId BLE.
  final String address;

  /// Caratteristica BLE esplicita (opzione "Avanzate").
  final String? characteristicId;

  final GenericLanguage language;

  /// 203 o 300.
  final int dpi;

  /// Larghezza carta dichiarata dal cliente per ESC/POS (58 o 80 mm):
  /// mai indovinata, mai implicita.
  final int paperWidthMm;

  /// Punti di testina stampabili in larghezza (Prompt 11-bis, §1).
  /// Default dalla carta dichiarata: 58 mm → 384 punti, 80 mm → 576 a
  /// 203 dpi (proporzionale a 300 dpi). Modificabile in "Avanzate":
  /// alcuni modelli hanno 432 o 640 punti.
  final int? printableWidthDots;

  /// TSPL: complementa i bit dell'immagine (molte TSPL usano 0 = nero e
  /// senza inversione l'etichetta esce in negativo). Prompt 11-bis, §2.
  final bool invertTspl;

  /// Punti stampabili effettivi alla risoluzione [dpi]: valore
  /// personalizzato o default proporzionale dalla carta.
  int effectivePrintableWidthDots(int dpi) {
    final custom = printableWidthDots;
    if (custom != null && custom > 0) return custom;
    final base = paperWidthMm >= 80 ? 576 : 384;
    final dots = (base * dpi / 203).round();
    return dots - dots % 8;
  }

  /// Larghezza stampabile in mm (per i messaggi all'utente).
  double printableWidthMm(int dpi) =>
      effectivePrintableWidthDots(dpi) / dpi * 25.4;

  GenericPrinterConfig copyWith({
    String? transport,
    String? address,
    String? characteristicId,
    GenericLanguage? language,
    int? dpi,
    int? paperWidthMm,
    int? printableWidthDots,
    bool? invertTspl,
  }) =>
      GenericPrinterConfig(
        transport: transport ?? this.transport,
        address: address ?? this.address,
        characteristicId: characteristicId ?? this.characteristicId,
        language: language ?? this.language,
        dpi: dpi ?? this.dpi,
        paperWidthMm: paperWidthMm ?? this.paperWidthMm,
        printableWidthDots: printableWidthDots ?? this.printableWidthDots,
        invertTspl: invertTspl ?? this.invertTspl,
      );

  ByteTransport buildTransport() {
    if (transport == 'ble') {
      return BleByteTransport(
        deviceId: address,
        characteristicId: characteristicId,
      );
    }
    return TcpByteTransport(address, port: 9100);
  }
}

/// Ricerca BLE per la stampante generica (Prompt 11-bis, §3): chiede i
/// permessi PRIMA, controlla il Bluetooth, avvia la scansione solo su
/// richiesta e raccoglie i risultati per tutta la durata, con
/// deduplicazione per remoteId. I hook sono iniettabili per i test.
class GenericBleScanner {
  GenericBleScanner({
    this.requestPermissions = requestBluetoothForPrinters,
    Future<bool> Function()? adapterIsOn,
    Future<void> Function(
      Duration timeout,
      void Function(String remoteId, String name) onHit,
    )? scan,
  })  : _adapterIsOn = adapterIsOn ?? _defaultAdapterIsOn,
        _scan = scan ?? _defaultScan;

  final Future<bool> Function() requestPermissions;
  final Future<bool> Function() _adapterIsOn;
  final Future<void> Function(
    Duration timeout,
    void Function(String remoteId, String name) onHit,
  ) _scan;

  static Future<bool> _defaultAdapterIsOn() async {
    try {
      return FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;
    } catch (_) {
      return false;
    }
  }

  /// Scansione reale su flutter_blue_plus: startScan con timeout,
  /// raccolta dei risultati per tutta la durata (se startScan ritorna
  /// prima, si attende il tempo mancante), stopScan sempre in finally.
  static Future<void> _defaultScan(
    Duration timeout,
    void Function(String remoteId, String name) onHit,
  ) async {
    final sw = Stopwatch()..start();
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        final advName = result.advertisementData.advName;
        final name = advName.isNotEmpty ? advName : result.device.platformName;
        if (name.isEmpty) continue;
        onHit(result.device.remoteId.str, name);
      }
    });
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      final remaining = timeout - sw.elapsed;
      if (remaining > Duration.zero) {
        await Future<void>.delayed(remaining);
      }
    } finally {
      await sub.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  Future<List<PrinterDevice>> discover({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (!await requestPermissions()) {
      throw const PrinterDiscoveryException(
        'Permesso Bluetooth negato: abilitalo nelle impostazioni del '
        'telefono e riprova.',
      );
    }
    if (!await _adapterIsOn()) {
      throw const PrinterDiscoveryException(
        'Bluetooth spento: attivalo dalle impostazioni del telefono e '
        'riprova.',
      );
    }

    final byId = <String, PrinterDevice>{};
    await _scan(timeout, (remoteId, name) {
      if (name.isEmpty) return;
      byId.putIfAbsent(
        remoteId,
        () => PrinterDevice(
          name: name,
          id: remoteId,
          transport: PrintTransport.ble,
        ),
      );
    });
    return byId.values.toList();
  }
}

/// Motore "Stampante generica": termiche economiche ESC/POS o TSPL via
/// Wi-Fi/LAN (TCP 9100) o Bluetooth LE. TUTTI i modelli sono NON
/// VERIFICATI finché non provati su hardware reale.
///
/// Nessuna capacità inventata: lo stato carta/coperchio generalmente non
/// è leggibile, `status()` riporta solo "connessa / non raggiungibile"
/// e la UI non promette di rilevare la carta.
class GenericLabelPrinter implements LabelPrinter {
  GenericLabelPrinter({
    this.config = const GenericPrinterConfig(),
    this.rasterizer,
    this.transportFactory,
    this.bleScanner,
  });

  GenericPrinterConfig config;

  /// Rasterizzatore (iniettabile nei test).
  final LabelRasterizer? rasterizer;

  /// Fabbrica dei trasporti (iniettabile nei test).
  final ByteTransport Function(GenericPrinterConfig config)? transportFactory;

  /// Scanner BLE (iniettabile nei test).
  final GenericBleScanner? bleScanner;

  ByteTransport? _transport;

  static const String permanentWarning =
      'Stampante generica: compatibilit\u00E0 non garantita per ogni '
      'modello. Se non esce nulla o l\u2019etichetta \u00E8 tagliata, prova '
      'l\u2019altro linguaggio (ESC/POS/TSPL), regola larghezza e densit\u00E0 '
      'e stampa l\u2019etichetta di prova.';

  @override
  String get id => 'generic';

  @override
  String get displayName => 'Stampante generica';

  @override
  Future<List<PrinterDevice>> discover() async {
    // Wi-Fi: l'indirizzo IP si inserisce a mano (niente discovery UDP
    // broadcast, spesso bloccato). BLE: ricerca reale con permessi,
    // stato adattatore e deduplicazione (Prompt 11-bis, §3).
    if (config.transport != 'ble') return const [];
    final scanner = bleScanner ?? GenericBleScanner();
    try {
      return await scanner.discover();
    } on PrinterDiscoveryException {
      rethrow;
    } catch (e) {
      debugPrint('Ricerca BLE generica fallita (${e.runtimeType}).');
      throw const PrinterDiscoveryException(
        'Ricerca Bluetooth non riuscita: riprova tra poco.',
      );
    }
  }

  @override
  Future<void> connect(PrinterDevice device) async {
    config = config.copyWith(
      transport: device.transport == PrintTransport.ble ? 'ble' : 'wifi',
      address: device.id,
    );
    final transport = _buildTransport();
    await transport.connect();
    await transport.close();
    _transport = null;
  }

  ByteTransport _buildTransport() =>
      transportFactory?.call(config) ?? config.buildTransport();

  @override
  Future<void> disconnect() async {
    await _transport?.close();
    _transport = null;
  }

  @override
  bool get isConnected => _transport?.isConnected ?? false;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    if (config.address.isEmpty) {
      return const PrintResult(
        PrintOutcome.notConnected,
        'Inserisci l\u2019indirizzo della stampante (IP per Wi-Fi, '
        'dispositivo per Bluetooth LE).',
      );
    }

    // ESC/POS: l'etichetta rasterizzata deve entrare nell'area
    // stampabile della testina (punti, non mm di carta): mai tagli o
    // scalature in silenzio (Prompt 11-bis, §1).
    if (config.language == GenericLanguage.escpos) {
      final dots = config.effectivePrintableWidthDots(config.dpi);
      final imageWidthPx = rasterWidthForMm(spec.widthMm.toDouble(), config.dpi);
      if (imageWidthPx > dots) {
        return PrintResult(
          PrintOutcome.labelSizeNotSupported,
          'L\u2019etichetta \u00E8 larga ${spec.widthMm} mm, la stampante ne '
          'stampa al massimo ${config.printableWidthMm(config.dpi).toStringAsFixed(0)} mm '
          '(carta da ${config.paperWidthMm} mm): scegli un formato pi\u00F9 '
          'piccolo o carta pi\u00F9 larga.',
        );
      }
    }

    final raster = rasterizer ?? LabelRasterizer();
    final escpos = const EscPosEncoder();
    final tspl = const TsplEncoder();

    for (final page in pdfPages) {
      final mono = await raster.rasterPdfPage(
        page,
        dpi: config.dpi,
        widthMm: spec.widthMm.toDouble(),
      );

      final Uint8List job;
      if (config.language == GenericLanguage.escpos) {
        job = escpos.label(mono, copies: copies);
      } else {
        job = tspl.label(
          mono,
          widthMm: spec.widthMm.toDouble(),
          heightMm: spec.heightMm.toDouble(),
          copies: copies,
          density: spec.density,
          dpi: config.dpi,
          invert: config.invertTspl,
        );
      }

      final transport = _buildTransport();
      try {
        await transport.connect();
      } catch (e) {
        debugPrint('Connessione stampante generica fallita (${e.runtimeType}).');
        return const PrintResult(
          PrintOutcome.notConnected,
          'Stampante non raggiungibile: controlla indirizzo, Wi-Fi e che '
          'la stampante sia accesa.',
        );
      }
      _transport = transport;
      final sent = await sendWithRetry(transport, job);
      await transport.close();
      _transport = null;
      if (!sent) {
        return const PrintResult(
          PrintOutcome.failed,
          'Invio alla stampante non riuscito (tentato due volte): '
          'controlla la connessione e riprova.',
        );
      }
    }
    return const PrintResult(PrintOutcome.ok);
  }

  @override
  Future<PrinterStatus> status() async {
    // Nessuna capacità inventata: solo connessa / non raggiungibile.
    if (config.address.isEmpty) {
      return const PrinterStatus(connected: false, ok: false);
    }
    try {
      final transport = _buildTransport();
      await transport.connect();
      await transport.close();
      return PrinterStatus(
        connected: true,
        detail: config.transport == 'ble' ? 'BLE' : '${config.address}:9100',
      );
    } catch (_) {
      return const PrinterStatus(connected: false, ok: false);
    }
  }
}
