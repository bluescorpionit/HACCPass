import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../core/printing/escpos_encoder.dart';
import '../../core/printing/label_printer.dart';
import '../../core/printing/label_rasterizer.dart';
import '../../core/printing/tspl_encoder.dart';
import 'bluetooth_permissions.dart';
import 'byte_transport.dart';

/// Linguaggio della stampante generica (Prompt 11, Ã‚Â§3 bis).
enum GenericLanguage { escpos, tspl }

extension GenericLanguageX on GenericLanguage {
  String get settingValue => this == GenericLanguage.escpos ? 'escpos' : 'tspl';

  String get label => this == GenericLanguage.escpos
      ? 'ESC/POS (scontrini e termiche generiche)'
      : 'TSPL (stampanti di etichette con carta a gap)';
}

/// Esito del controllo larghezza etichetta/carta (Prompt 17, Â§3).
class GenericFitCheck {
  const GenericFitCheck({
    required this.fits,
    required this.labelMm,
    required this.printableMm,
    required this.printablePx,
  });

  final bool fits;
  final int labelMm;
  final double printableMm;
  final int printablePx;
}

/// Errore tipizzato della ricerca stampanti (Prompt 11-bis, Ã‚Â§3): mai
/// elenchi vuoti muti, sempre un messaggio in italiano.
class PrinterDiscoveryException implements Exception {
  const PrinterDiscoveryException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Configurazione della stampante generica: tutto DICHIARATO dal
/// cliente, niente indovinato (larghezza carta, linguaggio, dpi, punti
/// stampabili, bande, taglierina).
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
    this.bandRows = 128,
    this.cutter = false,
    this.formFeed = false,
    this.antiAdvance = false,
    this.feedMm = 4,
    this.port = 9100,
    this.speed = 'normal',
    this.fitMode = 'ask',
  });

  /// `wifi` | `ble` | `bluetooth` (SPP, solo Android â€” Prompt 17).
  /// USB non disponibile (vedi docs/stampanti.md).
  final String transport;

  /// Indirizzo IP (wifi), remoteId BLE o MAC Bluetooth (senza "bt:").
  final String address;

  /// Caratteristica BLE esplicita (opzione "Avanzate").
  final String? characteristicId;

  final GenericLanguage language;

  /// 203 o 300.
  final int dpi;

  /// Larghezza carta dichiarata dal cliente per ESC/POS (58 o 80 mm):
  /// mai indovinata, mai implicita.
  final int paperWidthMm;

  /// Punti di testina stampabili in larghezza (Prompt 11-bis, Ã‚Â§1).
  final int? printableWidthDots;

  /// TSPL: complementa i bit dell'immagine (molte TSPL usano 0 = nero).
  final bool invertTspl;

  /// Righe per banda raster ESC/POS (Prompt 16, Ã‚Â§7.3): 128 default,
  /// 24 per modelli molto vecchi.
  final int bandRows;

  /// Taglierina: emette `GS V` a fine lavoro SOLO se dichiarata.
  final bool cutter;

  /// Avanza all'etichetta successiva con `FF`.
  final bool formFeed;

  /// Riduce al minimo l'avanzamento carta: niente FF e feed contenuto.
  final bool antiAdvance;

  /// Millimetri di avanzamento dopo l'immagine (default 4).
  final double feedMm;

  /// Porta TCP (default 9100, modificabile in Avanzate).
  final int port;

  /// VelocitÃ  di invio: `normal` | `slow` | `fast` (Prompt 17, Â§1:
  /// blocchi/pausa/bande â€” le stampanti Bluetooth perdono dati se
  /// l'invio Ã¨ troppo veloce).
  final String speed;

  /// Etichetta piÃ¹ larga della carta: `ask` | `shrink` | `reject`
  /// (Prompt 17, Â§3: mai riduzioni nascoste).
  final String fitMode;

  /// Punti stampabili effettivi alla risoluzione [dpi].
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
    int? bandRows,
    bool? cutter,
    bool? formFeed,
    bool? antiAdvance,
    double? feedMm,
    int? port,
    String? speed,
    String? fitMode,
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
        bandRows: bandRows ?? this.bandRows,
        cutter: cutter ?? this.cutter,
        formFeed: formFeed ?? this.formFeed,
        antiAdvance: antiAdvance ?? this.antiAdvance,
        feedMm: feedMm ?? this.feedMm,
        port: port ?? this.port,
        speed: speed ?? this.speed,
        fitMode: fitMode ?? this.fitMode,
      );

  /// Profilo di velocitÃ  effettivo (blocchi/pausa/bande).
  PrintSpeedProfile get speedProfile => PrintSpeedProfile.byId(speed);

  ByteTransport buildTransport() {
    if (transport == 'bluetooth') {
      return BluetoothSppByteTransport(address, profile: speedProfile);
    }
    if (transport == 'ble') {
      return BleByteTransport(
        deviceId: address,
        characteristicId: characteristicId,
      );
    }
    return TcpByteTransport(address, port: port);
  }
}

/// Ricerca BLE per la stampante generica (Prompt 11-bis, Ã‚Â§3): chiede i
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
  /// raccolta dei risultati per tutta la durata, stopScan sempre in
  /// finally.
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
/// VERIFICATI finchÃƒÂ© non provati su hardware reale.
///
/// Prompt 16, Ã‚Â§7.2: **una sola connessione TCP per lavoro** (molte
/// stampanti ne accettano una sola); il Wi-Fi non apre connessioni di
/// prova in `connect()`. Nessuna capacitÃƒÂ  inventata: lo stato riporta
/// solo "connessa / non raggiungibile".
class GenericLabelPrinter implements LabelPrinter {
  GenericLabelPrinter({
    this.config = const GenericPrinterConfig(),
    this.rasterizer,
    this.transportFactory,
    this.bleScanner,
    this.pairedLister,
  });

  GenericPrinterConfig config;

  /// Rasterizzatore (iniettabile nei test).
  final LabelRasterizer? rasterizer;

  /// Fabbrica dei trasporti (iniettabile nei test).
  final ByteTransport Function(GenericPrinterConfig config)? transportFactory;

  /// Scanner BLE (iniettabile nei test).
  final GenericBleScanner? bleScanner;

  /// Elenco dispositivi associati (hook iniettabile per i test,
  /// Prompt 17, Ã‚Â§2).
  final Future<List<SppPairedDevice>> Function()? pairedLister;

  /// Riepilogo dell'ultimo invio (diagnostica, Prompt 16, Ã‚Â§7.4):
  /// "Inviati N byte a IP:porta in X ms (B bande, Ã¢â‚¬Â¦)".
  String? lastJobSummary;

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
    if (config.transport == 'bluetooth') {
      // Dispositivi GIÃƒâ‚¬ ASSOCIATI (Prompt 17, Ã‚Â§2): le stampanti per
      // prime ma tutti selezionabili; nome vuoto Ã¢â€ â€™ MAC abbreviato.
      final granted = await requestBluetoothForPrinters();
      if (!granted) {
        throw const PrinterDiscoveryException(
          'Permesso Bluetooth negato: abilitalo per HACCPass nelle '
          'impostazioni del telefono e riprova.',
        );
      }
      final lister =
          pairedLister ?? BluetoothSppByteTransport.listPairedRecords;
      final paired = List.of(await lister());
      paired.sort((a, b) {
        final pa = BluetoothSppByteTransport.looksLikePrinter(a.name);
        final pb = BluetoothSppByteTransport.looksLikePrinter(b.name);
        if (pa != pb) return pa ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      final printerLike = [
        for (final device in paired)
          if (BluetoothSppByteTransport.looksLikePrinter(device.name)) device,
      ];
      final visible = printerLike.isNotEmpty ? printerLike : paired;
      return [
        for (final device in visible)
          PrinterDevice(
            name: device.name.isEmpty
                ? 'Dispositivo ${device.address.substring(device.address.length - 5)}'
                : device.name,
            id: 'bt:${device.address}',
            transport: PrintTransport.bluetooth,
            detail:
                '\u2026${device.address.substring(device.address.length - 5)}',
          ),
      ];
    }
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
    // Prompt 17, Ã‚Â§2: NESSUNA connessione di prova per nessun trasporto
    // (Prompt 16, Ã‚Â§7.2 per il Wi-Fi): si memorizzano solo identificativo
    // e trasporto; la verifica ÃƒÂ¨ esplicita ("Verifica connessione").
    config = config.copyWith(
      transport: switch (device.transport) {
        PrintTransport.ble => 'ble',
        PrintTransport.bluetooth => 'bluetooth',
        _ => 'wifi',
      },
      address: device.id.startsWith('bt:') ? device.id.substring(3) : device.id,
    );
  }

  ByteTransport _buildTransport() =>
      transportFactory?.call(config) ?? config.buildTransport();

  @override
  Future<void> disconnect() async {
    config = config.copyWith(address: '');
  }

  @override
  bool get isConnected => config.address.isNotEmpty;

  EscPosOptions _escposOptions({int? bandRows}) => EscPosOptions(
        bandRows: bandRows ?? config.bandRows,
        feedRows: config.antiAdvance
            ? 0
            : EscPosOptions.feedRowsForMm(config.feedMm, config.dpi),
        cut: config.cutter,
        formFeed: config.antiAdvance ? false : config.formFeed,
      );

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

    // ESC/POS: adattamento alla carta (Prompt 17, Ã‚Â§3). L'etichetta piÃƒÂ¹
    // larga dell'area stampabile non viene MAI tagliata in silenzio:
    // con fit=reject/ask Ã¢â€ â€™ errore esplicito (l'utente sceglie dalla
    // UI: ridurre, formato piÃƒÂ¹ piccolo o annullare); con fit=shrink Ã¢â€ â€™
    // rasterizzazione a larghezza = area stampabile (multipla di 8).
    var rasterWidthMm = spec.widthMm.toDouble();
    var shrunk = false;
    if (config.language == GenericLanguage.escpos) {
      final fit = checkFit(spec);
      if (!fit.fits) {
        if (config.fitMode != 'shrink') {
          return PrintResult(
            PrintOutcome.labelSizeNotSupported,
            'L\u2019etichetta \u00E8 larga ${spec.widthMm} mm, la stampante ne '
            'stampa al massimo ${fit.printableMm.toStringAsFixed(0)} mm '
            '(carta da ${config.paperWidthMm} mm). Puoi ridurla per '
            'adattarla alla carta (opzioni di stampa) oppure scegliere il '
            'formato 40\u00D730.',
          );
        }
        rasterWidthMm = fit.printablePx / config.dpi * 25.4;
        shrunk = true;
      }
    }

    final raster = rasterizer ?? LabelRasterizer();
    final escpos = const EscPosEncoder();
    final tspl = const TsplEncoder();
    final effectiveBandRows = config.speedProfile.bandRows;

    // 1. Codifica TUTTO il lavoro PRIMA di aprire la connessione.
    final segments = <List<int>>[];
    var bands = 0;
    for (final page in pdfPages) {
      final mono = await raster.rasterPdfPage(
        page,
        dpi: config.dpi,
        widthMm: rasterWidthMm,
      );
      if (config.language == GenericLanguage.escpos) {
        final jobSegments = escpos.labelSegments(
          mono,
          copies: copies,
          options: _escposOptions(bandRows: effectiveBandRows),
        );
        bands +=
            EscPosEncoder.bandHeights(mono.height, effectiveBandRows).length;
        segments.addAll(jobSegments);
      } else {
        segments.add(tspl.label(
          mono,
          widthMm: spec.widthMm.toDouble(),
          heightMm: spec.heightMm.toDouble(),
          copies: copies,
          density: spec.density,
          dpi: config.dpi,
          invert: config.invertTspl,
        ));
      }
    }
    final totalBytes = segments.fold<int>(0, (sum, s) => sum + s.length);

    // 2. UNA sola connessione per l'intero lavoro (Prompt 16, Ã‚Â§7.2).
    final transport = _buildTransport();
    final sw = Stopwatch()..start();
    try {
      await transport.connect();
    } catch (e) {
      debugPrint('Connessione stampante generica fallita (${e.runtimeType}).');
      return PrintResult(
        PrintOutcome.notConnected,
        'Stampante non raggiungibile: ${e is StateError ? e.message : 'controlla indirizzo, Wi-Fi e che la stampante sia accesa.'}',
      );
    }
    try {
      for (final segment in segments) {
        if (!await sendWithRetry(transport, segment)) {
          return const PrintResult(
            PrintOutcome.failed,
            'Invio alla stampante non riuscito (tentato due volte): '
            'controlla la connessione e riprova.',
          );
        }
      }
    } finally {
      await transport.close();
    }
    sw.stop();

    final target = switch (config.transport) {
      'ble' => 'BLE',
      'bluetooth' =>
        'Bluetooth classico (blocchi da ${config.speedProfile.chunkBytes} B, '
            'velocitÃƒÂ  ${config.speedProfile.label})',
      _ => '${config.address}:${config.port}',
    };
    final langLabel =
        config.language == GenericLanguage.escpos ? 'ESC/POS' : 'TSPL';
    final bandsPart =
        config.language == GenericLanguage.escpos ? '$bands bande, ' : '';
    final shrinkPart = shrunk ? ', RIDOTTA alla carta' : '';
    lastJobSummary = 'Inviati $totalBytes byte a $target '
        'in ${sw.elapsed.inMilliseconds} ms '
        '($bandsPart$langLabel, ${config.dpi} dpi, '
        'carta ${config.paperWidthMm} mm$shrinkPart).';

    return const PrintResult(PrintOutcome.ok);
  }

  /// Esito del controllo di adattamento alla carta (Prompt 17, Ã‚Â§3).
  GenericFitCheck checkFit(LabelSpec spec) {
    final dots = config.effectivePrintableWidthDots(config.dpi);
    final px = rasterWidthForMm(spec.widthMm.toDouble(), config.dpi);
    return GenericFitCheck(
      fits: px <= dots,
      labelMm: spec.widthMm,
      printableMm: config.printableWidthMm(config.dpi),
      printablePx: dots,
    );
  }

  /// Avviso di leggibilitÃƒÂ  dopo la riduzione (Prompt 17, Ã‚Â§3): stimato
  /// sul rapporto di riduzione (QR e testi scalati allo stesso
  /// rapporto); sotto ~0.8 il QR rischia di non essere letto.
  bool readabilityWarningNeeded(LabelSpec spec) {
    final fit = checkFit(spec);
    if (fit.fits || config.fitMode != 'shrink') return false;
    final ratio =
        fit.printablePx / rasterWidthForMm(spec.widthMm.toDouble(), config.dpi);
    return ratio < 0.8;
  }

  /// Diagnostica 1 (Prompt 16, Ã‚Â§7.4): verifica esplicita della
  /// raggiungibilitÃƒÂ  TCP, con indirizzo del telefono per confrontare la
  /// sottorete. Solo Wi-Fi.
  Future<TcpProbeResult> probeConnection() async {
    if (config.transport == 'bluetooth') {
      // SPP: apre e chiude il socket RFCOMM (Prompt 17, Â§4).
      if (config.address.isEmpty) {
        return const TcpProbeResult(
          TcpProbeOutcome.networkUnavailable,
          Duration.zero,
          'Inserisci prima il dispositivo Bluetooth associato.',
        );
      }
      final transport = _buildTransport();
      final sw = Stopwatch()..start();
      try {
        await transport.connect();
        await transport.close();
        sw.stop();
        return TcpProbeResult(
          TcpProbeOutcome.reachable,
          sw.elapsed,
          'Collegamento Bluetooth riuscito in '
          '${sw.elapsed.inMilliseconds} ms: stampante raggiungibile.',
        );
      } on StateError catch (e) {
        sw.stop();
        return TcpProbeResult(
          TcpProbeOutcome.refused,
          sw.elapsed,
          e.message,
        );
      }
    }
    if (config.transport == 'ble' || config.address.isEmpty) {
      return const TcpProbeResult(
        TcpProbeOutcome.networkUnavailable,
        Duration.zero,
        'Verifica disponibile solo per stampanti di rete (Wi-Fi): '
        'inserisci l\'indirizzo IP.',
      );
    }
    final result = await probeTcpPrinter(config.address, config.port);
    final phoneIp = await phoneIpv4();
    if (result.isReachable && phoneIp != null) {
      final phoneSubnet = phoneIp.split('.').take(3).join('.');
      final printerSubnet = config.address.split('.').take(3).join('.');
      if (phoneSubnet != printerSubnet) {
        return TcpProbeResult(
          result.outcome,
          result.elapsed,
          '${result.message} ATTENZIONE: il telefono è $phoneIp, su '
          'una sottorete diversa dalla stampante ($printerSubnet.x): '
          'collegati allo stesso Wi-Fi.',
        );
      }
    }
    return result;
  }

  /// Diagnostica 2 (Prompt 16, Ã‚Â§7.4): "prova solo testo". Se stampa e
  /// l'etichetta no, il problema \u00E8 l'immagine/raster; se nemmeno
  /// questa stampa, \u00E8 rete/porta/linguaggio.
  Future<PrintResult> printPlainTextTest() async {
    if (config.address.isEmpty) {
      return const PrintResult(
        PrintOutcome.notConnected,
        'Inserisci prima l\'indirizzo della stampante.',
      );
    }
    final spec = const LabelSpec(format: '62x40');
    final bytes = config.language == GenericLanguage.tspl
        ? const TsplEncoder().plainTextTest(
            widthMm: spec.widthMm.toDouble(),
            heightMm: spec.heightMm.toDouble(),
            density: 3,
          )
        : const EscPosEncoder().plainTextTest(cut: config.cutter);
    final transport = _buildTransport();
    try {
      await transport.connect();
    } catch (e) {
      return PrintResult(
        PrintOutcome.notConnected,
        e is StateError
            ? e.message
            : 'Stampante non raggiungibile: controlla indirizzo e Wi-Fi.',
      );
    }
    try {
      final sent = await sendWithRetry(transport, bytes);
      if (!sent) {
        return const PrintResult(
          PrintOutcome.failed,
          'Test non inviato: la stampante ha chiuso la connessione.',
        );
      }
    } finally {
      await transport.close();
    }
    lastJobSummary = 'Test testo: ${bytes.length} byte a '
        '${config.transport == 'ble' ? 'BLE' : '${config.address}:${config.port}'} '
        '(nessuna immagine, ${config.language == GenericLanguage.tspl ? 'TSPL' : 'ESC/POS'}).';
    return const PrintResult(
      PrintOutcome.ok,
      'Test inviato. Se NON esce nemmeno questo, il problema è rete, '
      'porta o linguaggio; se esce questo ma non l\'etichetta, il '
      'problema è l\'immagine (prova l\'altro linguaggio o '
      'riduci le bande).',
    );
  }

  @override
  Future<PrinterStatus> status() async {
    // Nessuna capacitÃƒÂ  inventata: solo connessa / non raggiungibile.
    if (config.address.isEmpty) {
      return const PrinterStatus(connected: false, ok: false);
    }
    if (config.transport == 'ble') {
      return PrinterStatus(connected: true, detail: 'BLE');
    }
    final probe = await probeConnection();
    return PrinterStatus(
      connected: probe.isReachable,
      detail: probe.isReachable ? '${config.address}:${config.port}' : null,
    );
  }
}
