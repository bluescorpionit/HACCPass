import 'dart:io';

import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;

/// Copia temporanea ad alta risoluzione per l'OCR (Prompt 8, A1):
/// lato lungo ~2200 px, qualità alta, orientamento gestito dal plugin.
/// La copia SALVATA come allegato resta quella compressa standard: questa
/// si elimina subito dopo il riconoscimento.
Future<File> prepareForOcr(
  String sourcePath, {
  required Directory tempDir,
  int maxSide = 2200,
}) async {
  final target = p.join(
    tempDir.path,
    'ocr_${DateTime.now().microsecondsSinceEpoch}_'
    '${p.basenameWithoutExtension(sourcePath)}.jpg',
  );
  final compressed = await FlutterImageCompress.compressAndGetFile(
    sourcePath,
    target,
    minWidth: maxSide,
    minHeight: maxSide,
    quality: 92,
    keepExif: true,
  );
  if (compressed != null) return File(compressed.path);
  // Compressione non disponibile (formato insolito): usa una copia integra.
  final copy = File(target);
  await File(sourcePath).copy(copy.path);
  return copy;
}
