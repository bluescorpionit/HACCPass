import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import '../models/haccp_models.dart';

class LabelData {
  const LabelData({
    required this.companyName,
    required this.lot,
    required this.copies,
  });

  final String companyName;
  final ProductionLot lot;
  final int copies;
}

abstract class PrinterService {
  Future<bool> isAvailable();
  Future<void> printLotLabel(LabelData data);
}

/// Stampa demo: simula la stampa senza hardware.
class DemoPrinterService implements PrinterService {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> printLotLabel(LabelData data) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
  }
}

/// Stampa tramite il sistema: apre il flusso di stampa di Android/iOS/Windows,
/// che include le stampanti Bluetooth e Wi-Fi viste dal sistema.
class PdfPrinterService implements PrinterService {
  PdfPrinterService({required this.buildLabelPdf});

  /// Costruisce i byte PDF dell'etichetta (una pagina per copia).
  final Future<Uint8List> Function(LabelData data) buildLabelPdf;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<void> printLotLabel(LabelData data) async {
    final bytes = await buildLabelPdf(data);
    await Printing.layoutPdf(
      onLayout: (format) async => bytes,
      name: 'Etichetta ${data.lot.code}',
    );
  }
}

@visibleForTesting
Future<int> labelPages(LabelData data) async => data.copies;
