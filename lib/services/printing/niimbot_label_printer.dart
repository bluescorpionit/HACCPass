import 'package:flutter/foundation.dart';

import '../../core/printing/label_printer.dart';
import '../../core/printing/label_rasterizer.dart';
import 'bluetooth_permissions.dart';

/// Contratto sottile verso la libreria Niimbot (Prompt 11, §3): il
/// pacchetto `niim_blue_flutter` è recente e non ufficiale, quindi TUTTO
/// passa da questo adattatore: sostituirlo non tocca il motore.
abstract class NiimbotClientAdapter {
  Future<List<PrinterDevice>> discover();

  /// Collega per [deviceId] (remoteId BLE) e restituisce le capacità
  /// rilevate dal dispositivo: dpi, pixel della testina (larghezza
  /// massima stampabile), densità min/max e nome modello.
  Future<NiimbotCapabilities> connect(String deviceId);

  Future<void> disconnect();

  bool get isConnected;

  /// Stampa l'immagine monocromatica [copies] volte con densità
  /// [density] (già nel range del modello).
  Future<void> printMono(
    MonoBitmap image, {
    required int density,
    int copies = 1,
  });
}

class NiimbotCapabilities {
  const NiimbotCapabilities({
    required this.model,
    required this.dpi,
    required this.printheadPixels,
    required this.densityMin,
    required this.densityMax,
  });

  final String model;
  final int dpi;
  final int printheadPixels;
  final int densityMin;
  final int densityMax;

  /// Larghezza massima stampabile in mm, DERIVATA dal dispositivo.
  int get maxPrintableMm => (printheadPixels / dpi * 25.4).floor();
}

/// Motore Niimbot (B21, B1, D110/D11...) via Bluetooth LE.
///
/// AVVISO permanente (riportato nella schermata di configurazione):
/// stampante consumer con protocollo non ufficiale; un aggiornamento del
/// firmware potrebbe richiedere un aggiornamento dell'app.
class NiimbotLabelPrinter implements LabelPrinter {
  NiimbotLabelPrinter({required this.adapter, this.rasterizer});

  final NiimbotClientAdapter adapter;

  /// Rasterizzatore (iniettabile nei test).
  final LabelRasterizer? rasterizer;

  NiimbotCapabilities? _capabilities;

  @override
  String get id => 'niimbot';

  @override
  String get displayName => 'Niimbot';

  NiimbotCapabilities? get capabilities => _capabilities;

  /// Avviso permanente da mostrare nella schermata di configurazione.
  static const String permanentWarning =
      'Stampante consumer con protocollo non ufficiale: un aggiornamento '
      'del firmware potrebbe richiedere un aggiornamento dell\u2019app. '
      'Etichette termiche: verifica l\u2019adesione su contenitori freddi o '
      'umidi e usa etichette con adesivo removibile.';

  @override
  Future<List<PrinterDevice>> discover() async {
    final granted = await requestBluetoothForPrinters();
    if (!granted) {
      throw StateError(
        'Permessi Bluetooth mancanti: consentili per cercare le stampanti '
        'Niimbot (su Android 11 e precedenti serve anche la posizione).',
      );
    }
    return adapter.discover();
  }

  @override
  Future<void> connect(PrinterDevice device) async {
    _capabilities = await adapter.connect(device.id);
  }

  @override
  Future<void> disconnect() async {
    _capabilities = null;
    await adapter.disconnect();
  }

  @override
  bool get isConnected => adapter.isConnected;

  /// Larghezza massima (mm) secondo il modello collegato: nessuna
  /// larghezza scritta a mano, arriva dal dispositivo/pacchetto.
  int? get maxPrintableMm => _capabilities?.maxPrintableMm;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    final caps = _capabilities;
    if (caps == null || !isConnected) {
      return const PrintResult(PrintOutcome.notConnected);
    }

    // L'etichetta non entra nella testina? Messaggio chiaro, MAI taglio
    // silenzioso (i D11/D110 hanno testine molto strette).
    if (spec.widthMm > caps.maxPrintableMm) {
      return PrintResult(
        PrintOutcome.labelSizeNotSupported,
        'Questa stampante non stampa etichette da ${spec.widthMm} mm: '
        'scegli un formato pi\u00F9 piccolo o un\u2019altra stampante '
        '(larghezza massima ${caps.maxPrintableMm} mm per ${caps.model}).',
      );
    }

    final density = spec.density.clamp(caps.densityMin, caps.densityMax);
    final raster = rasterizer ?? LabelRasterizer();
    for (final page in pdfPages) {
      try {
        // Larghezza effettiva: mai oltre i pixel della testina.
        var image = await raster.rasterPdfPage(
          page,
          dpi: caps.dpi,
          widthMm: spec.widthMm.toDouble(),
        );
        if (image.width > caps.printheadPixels) {
          image = _cropToPrinthead(image, caps.printheadPixels);
        }
        await adapter.printMono(image, density: density, copies: copies);
      } catch (e) {
        debugPrint('Stampa Niimbot fallita: $e');
        return const PrintResult(
          PrintOutcome.failed,
          'Stampa Niimbot non riuscita: controlla che l\u2019etichetta sia '
          'caricata e la batteria carica, poi riprova.',
        );
      }
    }
    return const PrintResult(PrintOutcome.ok);
  }

  /// Ritaglia i pixel oltre la testina mantenendo il multipla di 8.
  MonoBitmap _cropToPrinthead(MonoBitmap image, int printheadPixels) {
    final width = printheadPixels - printheadPixels % 8;
    final bytesPerRow = width ~/ 8;
    final out = Uint8List(bytesPerRow * image.height);
    for (var y = 0; y < image.height; y++) {
      out.setRange(
        y * bytesPerRow,
        (y + 1) * bytesPerRow,
        image.packed,
        y * image.bytesPerRow,
      );
    }
    return MonoBitmap(width: width, height: image.height, packed: out);
  }

  @override
  Future<PrinterStatus> status() async {
    if (!isConnected) {
      return const PrinterStatus(connected: false, ok: false);
    }
    final caps = _capabilities;
    return PrinterStatus(
      connected: true,
      detail: caps == null
          ? null
          : '${caps.model} \u2022 max ${caps.maxPrintableMm} mm',
    );
  }
}
