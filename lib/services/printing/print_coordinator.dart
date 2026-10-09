import 'package:flutter/foundation.dart';

import '../../core/printing/label_printer.dart';
import '../../repositories/haccp_repository.dart';
import 'brother_label_printer.dart';
import 'generic_label_printer.dart';
import 'niim_blue_adapter.dart';
import 'niimbot_label_printer.dart';
import 'system_label_printer.dart';

/// Impostazioni stampante (Prompt 11, Â§1/Â§4): il motore salvato viene
/// ricostruito da questi valori; la riconnessione avviene SOLO quando
/// serve (alla prima stampa), mai all'avvio.
class PrintSettings {
  const PrintSettings({
    this.engine = '',
    this.deviceId = '',
    this.deviceName = '',
    this.format = '62x40',
    this.density = 3,
    this.generic = const GenericPrinterConfig(),
  });

  /// '' se nessuna stampante configurata.
  final String engine;
  final String deviceId;
  final String deviceName;
  final String format;
  final int density;
  final GenericPrinterConfig generic;

  bool get isConfigured => engine.isNotEmpty;

  LabelSpec get spec => LabelSpec(format: format, density: density);

  static Future<PrintSettings> load(
    Future<String?> Function(String key) read,
  ) async {
    final cache = <String, String>{};
    Future<String> value(String key, String fallback) async {
      if (cache.containsKey(key)) return cache[key]!;
      final raw = await read(key);
      return cache[key] = raw != null && raw.isNotEmpty ? raw : fallback;
    }

    final engine = await value('printer_engine', '');
    final labelFormat = await value('label_format', '62x40');
    final format = await value('printer_label_format', labelFormat);
    final density = int.tryParse(await value('printer_density', '3')) ?? 3;
    final language = await value('printer_generic_language', 'escpos') == 'tspl'
        ? GenericLanguage.tspl
        : GenericLanguage.escpos;
    final characteristic = await value('printer_generic_characteristic', '');
    final dotsRaw = await value('printer_generic_printable_dots', '');
    return PrintSettings(
      engine: engine,
      deviceId: await value('printer_device_id', ''),
      deviceName: await value('printer_device_name', ''),
      format: format,
      density: density,
      generic: GenericPrinterConfig(
        transport: await value('printer_generic_transport', 'wifi'),
        address: await value('printer_generic_address', ''),
        characteristicId: characteristic.isEmpty ? null : characteristic,
        language: language,
        dpi: int.tryParse(await value('printer_generic_dpi', '203')) ?? 203,
        paperWidthMm:
            int.tryParse(await value('printer_generic_paper_width', '58')) ??
                58,
        printableWidthDots: int.tryParse(dotsRaw),
        invertTspl: await value('printer_generic_invert', '0') == '1',
        bandRows:
            int.tryParse(await value('printer_generic_band_rows', '128')) ??
                128,
        cutter: await value('printer_generic_cutter', '0') == '1',
        formFeed: await value('printer_generic_form_feed', '0') == '1',
        antiAdvance: await value('printer_generic_anti_advance', '0') == '1',
        feedMm:
            double.tryParse(await value('printer_generic_feed_mm', '4')) ?? 4,
        port: int.tryParse(await value('printer_generic_port', '9100')) ?? 9100,
        speed: await value('printer_generic_speed', 'normal'),
        fitMode: await value('printer_generic_fit_mode', 'ask'),
      ),
    );
  }

  Future<void> save(HaccpRepository repository) async {
    Future<void> set(String k, String v) => repository.setSetting(k, v);
    await set('printer_engine', engine);
    await set('printer_device_id', deviceId);
    await set('printer_device_name', deviceName);
    await set('printer_label_format', format);
    await set('label_format', format);
    await set('printer_density', density.toString());
    await set('printer_generic_transport', generic.transport);
    await set('printer_generic_address', generic.address);
    await set(
      'printer_generic_characteristic',
      generic.characteristicId ?? '',
    );
    await set(
      'printer_generic_language',
      generic.language.settingValue,
    );
    await set('printer_generic_dpi', generic.dpi.toString());
    await set('printer_generic_paper_width', generic.paperWidthMm.toString());
    await set('printer_generic_printable_dots',
        generic.printableWidthDots?.toString() ?? '');
    await set('printer_generic_invert', generic.invertTspl ? '1' : '0');
    await set('printer_generic_band_rows', generic.bandRows.toString());
    await set('printer_generic_cutter', generic.cutter ? '1' : '0');
    await set('printer_generic_form_feed', generic.formFeed ? '1' : '0');
    await set(
      'printer_generic_anti_advance',
      generic.antiAdvance ? '1' : '0',
    );
    await set('printer_generic_feed_mm', generic.feedMm.toString());
    await set('printer_generic_port', generic.port.toString());
    await set('printer_generic_speed', generic.speed);
    await set('printer_generic_fit_mode', generic.fitMode);
  }
}

/// Token di annullamento della coda di stampa.
class PrintCancel {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// Costruisce e gestisce il motore salvato nelle impostazioni:
/// - `printPdf` ricollega la stampante salvata SOLO quando serve;
/// - stampa a coda, un'etichetta alla volta, con avanzamento e annulla;
/// - ogni [PrintResult] ha giÃ  il messaggio in italiano.
class PrintCoordinator {
  PrintCoordinator._(this.settings, this.engine);

  /// Costruttore per test (motori finti).
  @visibleForTesting
  PrintCoordinator.forTest(this.settings, this.engine);

  final PrintSettings settings;
  final LabelPrinter? engine;

  /// Costruisce il coordinatore dal motore salvato. Con motore `demo`
  /// nelle build di release torna "non configurato" (il demo esiste
  /// solo in debug).
  static Future<PrintCoordinator> load(
    HaccpRepository repository, {
    Map<String, LabelPrinter Function(PrintSettings settings)>? engineFactories,
  }) =>
      loadFrom(repository.getSetting, engineFactories: engineFactories);

  @visibleForTesting
  static Future<PrintCoordinator> loadFrom(
    Future<String?> Function(String key) read, {
    Map<String, LabelPrinter Function(PrintSettings settings)>? engineFactories,
  }) async {
    final settings = await PrintSettings.load(read);
    if (!settings.isConfigured) {
      return PrintCoordinator._(settings, null);
    }
    final factories = engineFactories ?? defaultEngineFactories;
    final factory = factories[settings.engine];
    if (factory == null || (settings.engine == 'demo' && kReleaseMode)) {
      return PrintCoordinator._(settings, null);
    }
    // Prompt 16, Â§7.1: la factory riceve le impostazioni: il motore
    // generico nasce CON la configurazione salvata (linguaggio, dpi,
    // carta, punti, inversione, bande, taglierinaâ€¦).
    return PrintCoordinator._(settings, factory(settings));
  }

  /// Le factory ricevono le [PrintSettings]: il motore generico usa
  /// `settings.generic` (bug del Prompt 16, Â§7.1: prima nasceva con la
  /// configurazione di default e TSPL/300 dpi/80 mm/BLEâ€¦ erano ignorati).
  static Map<String, LabelPrinter Function(PrintSettings settings)>
      get defaultEngineFactories => {
            'brother': (_) => BrotherLabelPrinter(),
            'niimbot': (_) =>
                NiimbotLabelPrinter(adapter: NiimBlueClientAdapter()),
            'generic': (settings) =>
                GenericLabelPrinter(config: settings.generic),
            'system': (_) => SystemLabelPrinter(),
            if (kDebugMode) 'demo': (_) => DemoLabelPrinter(),
          };

  /// Motori mostrati in Impostazioni â†’ Stampante (il demo solo in debug).
  static List<LabelPrinter> availableEngines() => [
        BrotherLabelPrinter(),
        NiimbotLabelPrinter(adapter: NiimBlueClientAdapter()),
        GenericLabelPrinter(),
        SystemLabelPrinter(),
        if (kDebugMode) DemoLabelPrinter(),
      ];

  bool get isConfigured => engine != null && settings.isConfigured;

  /// Il motore Ã¨ la stampa di sistema (nessun dispositivo da collegare).
  bool get needsDevice =>
      isConfigured &&
      engine!.id != 'system' &&
      engine!.id != 'demo' &&
      settings.deviceId.isEmpty;

  /// Stampa [pdfPages] (byte PDF di PdfService) per [copies] copie,
  /// un'etichetta alla volta.
  Future<PrintResult> printPdf(
    List<Uint8List> pdfPages, {
    int copies = 1,
    void Function(int done, int total)? onProgress,
    PrintCancel? cancel,
  }) async {
    final printer = engine;
    if (printer == null || !settings.isConfigured) {
      return const PrintResult(
        PrintOutcome.notConnected,
        'Nessuna stampante configurata: scegline una in Impostazioni '
        '\u2192 Stampante.',
      );
    }

    // Riconnessione SOLO quando serve, qui alla prima stampa.
    if (!printer.isConnected && settings.deviceId.isNotEmpty) {
      final transport = _transportOf(settings);
      try {
        await printer.connect(
          PrinterDevice(
            name: settings.deviceName,
            id: settings.deviceId,
            transport: transport,
          ),
        );
      } catch (e) {
        debugPrint('Riconnessione stampante fallita: $e');
        return const PrintResult(
          PrintOutcome.notConnected,
          'Stampante non collegata: seleziona di nuovo la stampante '
          '(Impostazioni \u2192 Stampante).',
        );
      }
    } else if (!printer.isConnected && needsDevice) {
      return const PrintResult(
        PrintOutcome.notConnected,
        'Seleziona la stampante in Impostazioni \u2192 Stampante.',
      );
    }

    final total = pdfPages.length * copies;
    var done = 0;
    for (var copy = 0; copy < copies; copy++) {
      for (final page in pdfPages) {
        if (cancel?.cancelled ?? false) {
          return const PrintResult(PrintOutcome.cancelled);
        }
        final result = await printer.printLabels([page], settings.spec);
        if (!result.isOk) return result;
        done++;
        onProgress?.call(done, total);
      }
    }
    return const PrintResult(PrintOutcome.ok);
  }

  PrintTransport _transportOf(PrintSettings settings) {
    final id = settings.deviceId;
    if (id.startsWith('wifi:')) return PrintTransport.wifi;
    if (id.startsWith('bt:')) return PrintTransport.bluetooth;
    if (settings.generic.transport == 'bluetooth') {
      return PrintTransport.bluetooth;
    }
    if (settings.engine == 'niimbot' || settings.generic.transport == 'ble') {
      return PrintTransport.ble;
    }
    return PrintTransport.wifi;
  }
}
