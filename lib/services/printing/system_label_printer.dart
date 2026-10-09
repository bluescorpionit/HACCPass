import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../../core/printing/label_printer.dart';

/// Ripiego "Stampa di sistema (PDF)": usa il flusso di stampa di
/// Android/iOS/desktop (AirPrint, servizio di stampa di sistema), come
/// il vecchio `PdfPrinterService`.
class SystemLabelPrinter implements LabelPrinter {
  static const _device = PrinterDevice(
    name: 'Stampa di sistema (PDF)',
    id: 'system',
    transport: PrintTransport.system,
  );

  @override
  String get id => 'system';

  @override
  String get displayName => 'Stampa di sistema';

  @override
  Future<List<PrinterDevice>> discover() async => [_device];

  @override
  Future<void> connect(PrinterDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => true;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    try {
      // Il flusso di stampa è una finestra di sistema per etichetta: le
      // copie vengono ripetute lì dove il pannello lo consente.
      for (final page in pdfPages) {
        for (var i = 0; i < copies.clamp(1, 999); i++) {
          await Printing.layoutPdf(onLayout: (format) async => page);
        }
      }
      return const PrintResult(PrintOutcome.ok);
    } catch (e) {
      debugPrint('Stampa di sistema annullata o fallita: $e');
      return const PrintResult(PrintOutcome.cancelled);
    }
  }

  @override
  Future<PrinterStatus> status() async =>
      const PrinterStatus(connected: true);
}

/// Motore demo: simula la stampa senza hardware. Disponibile SOLO nelle
/// build di debug (nascosto in release).
class DemoLabelPrinter implements LabelPrinter {
  @override
  String get id => 'demo';

  @override
  String get displayName => 'Demo (solo debug)';

  @override
  Future<List<PrinterDevice>> discover() async => const [
        PrinterDevice(
          name: 'Stampante demo',
          id: 'demo',
          transport: PrintTransport.demo,
        ),
      ];

  @override
  Future<void> connect(PrinterDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => true;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    await Future<void>.delayed(
      const Duration(milliseconds: 650) * pdfPages.length * copies,
    );
    return const PrintResult(PrintOutcome.ok);
  }

  @override
  Future<PrinterStatus> status() async =>
      const PrinterStatus(connected: true);
}
