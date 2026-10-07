import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

/// Rasterizza le pagine di un PDF per l'OCR (Prompt 8, A1): ~200 dpi,
/// massimo 6 pagine per documento. L'allegato originale resta il PDF
/// intatto: le immagini sono temporanee e cancellate dopo il riconoscimento.
Future<List<File>> rasterizePdfForOcr(
  String pdfPath, {
  required Directory tempDir,
  int maxPages = 6,
  double dpi = 200,
}) async {
  final files = <File>[];
  final doc = Printing.raster(
    await File(pdfPath).readAsBytes(),
    pages: List<int>.generate(maxPages, (i) => i),
    dpi: dpi,
  );
  var pageNumber = 0;
  await for (final page in doc) {
    pageNumber++;
    final bytes = await page.toPng();
    final file = File(p.join(
      tempDir.path,
      'pdfpage_${DateTime.now().microsecondsSinceEpoch}_$pageNumber.png',
    ));
    await file.writeAsBytes(bytes, flush: true);
    files.add(file);
    if (files.length >= maxPages) break;
  }
  return files;
}
