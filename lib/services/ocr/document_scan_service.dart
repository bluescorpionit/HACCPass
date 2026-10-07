import 'dart:io';

import 'document_parser.dart';
import 'ocr_port.dart';
import 'pdf_rasterizer.dart';

/// Esito della scansione di un documento: dati estratti, percorsi delle
/// immagini temporanee usate per l'OCR (da eliminare o conservare come
/// allegato dal chiamante) e stato.
class DocumentScanOutcome {
  const DocumentScanOutcome({
    required this.document,
    required this.ocrPages,
    required this.originalPaths,
  });

  final ParsedDocument document;

  /// Copie ad alta risoluzione usate per il riconoscimento: TEMPORANEE,
  /// vanno eliminate dopo la verifica.
  final List<String> ocrPages;

  /// File originali scelti dall'utente (foto o PDF): sono quelli da
  /// allegare alle merci create.
  final List<String> originalPaths;

  bool get hasData => document.lines.isNotEmpty ||
      document.supplierName != null ||
      document.docNumber != null ||
      document.docDate != null;
}

/// Coordinatore della lettura documenti (Prompt 8, A3): preprocessa le
/// immagini (o rasterizza i PDF), chiama il riconoscitore pagina per
/// pagina e unisce i risultati prima del parsing. Annullabile.
class DocumentScanService {
  DocumentScanService({
    required this.recognizer,
    this.pdfRasterizer = rasterizePdfForOcr,
    this.ocrPreparer,
  });

  final TextRecognizerPort recognizer;

  /// Indirette per i test.
  final Future<List<File>> Function(String pdfPath, {required Directory tempDir})
      pdfRasterizer;
  final Future<File> Function(String sourcePath, {required Directory tempDir})?
      ocrPreparer;

  bool _cancelled = false;

  void cancel() => _cancelled = true;

  /// Riconosce un documento da una o più foto/PDF. [onProgress] riceve
  /// messaggi brevi per l'indicatore ("Leggo il documento…", pagina x/y).
  Future<DocumentScanOutcome> scan({
    required List<String> sourcePaths,
    required Directory tempDir,
    void Function(String message)? onProgress,
  }) async {
    _cancelled = false;
    final ocrFiles = <File>[];
    final allLines = <OcrLine>[];
    var pageOffset = 0.0;

    try {
      for (var i = 0; i < sourcePaths.length; i++) {
        if (_cancelled) break;
        final source = sourcePaths[i];
        final lower = source.toLowerCase();
        final isPdf = lower.endsWith('.pdf');

        onProgress?.call(
          'Leggo il documento\u2026 (pagina ${i + 1} di ${sourcePaths.length})',
        );

        List<File> images;
        if (isPdf) {
          images = await pdfRasterizer(source, tempDir: tempDir);
        } else if (ocrPreparer != null) {
          images = [await ocrPreparer!(source, tempDir: tempDir)];
        } else {
          images = [File(source)];
        }
        ocrFiles.addAll(images);

        for (final image in images) {
          if (_cancelled) break;
          final result = await recognizer.recognize(image.path);
          // Offset verticale per pagina: il parser ordina per posizione e
          // le pagine non si sovrappongono.
          for (final line in result.lines) {
            allLines.add(OcrLine(
              text: line.text,
              confidence: line.confidence,
              box: OcrBox(
                left: line.box.left,
                top: line.box.top + pageOffset,
                right: line.box.right,
                bottom: line.box.bottom + pageOffset,
              ),
            ));
          }
          pageOffset += 20000;
        }
      }

      final document = const DocumentParser().parse(
        OcrResult(lines: allLines),
      );
      return DocumentScanOutcome(
        document: document,
        ocrPages: [for (final file in ocrFiles) file.path],
        originalPaths: sourcePaths,
      );
    } finally {
      recognizer.dispose();
    }
  }

  /// Elimina le copie temporanee dell'OCR (chiamare a fine flusso o
  /// all'annullamento).
  Future<void> cleanup(List<String> paths) async {
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Gi\u00E0 rimosso.
      }
    }
  }
}
