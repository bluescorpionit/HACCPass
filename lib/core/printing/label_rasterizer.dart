/// Rasterizzazione condivisa dei PDF delle etichette (Prompt 11, §1).
///
/// `PdfService` produce le etichette come PDF: i motori Niimbot e
/// generici (ESC/POS / TSPL) le convertono in immagine monocromatica
/// (bianco/nero puro) con soglia regolabile, larghezza multipla di 8
/// pixel e bordi bianchi ritagliati con margine fisso.
library;

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

/// Immagine monocromatica: righe packate MSB-first, bit 1 = nero.
/// La larghezza è sempre multipla di 8.
class MonoBitmap {
  const MonoBitmap({
    required this.width,
    required this.height,
    required this.packed,
  });

  final int width;
  final int height;

  /// `height * width ~/ 8` byte.
  final Uint8List packed;

  int get bytesPerRow => width ~/ 8;

  bool get isEmpty {
    for (final b in packed) {
      if (b != 0) return false;
    }
    return true;
  }

  /// Pixel come lista 0/1 (usata dal motore Niimbot).
  List<int> toPixelList() {
    final pixels = List<int>.filled(width * height, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final byte = packed[y * bytesPerRow + (x >> 3)];
        if ((byte >> (7 - (x & 7))) & 1 == 1) {
          pixels[y * width + x] = 1;
        }
      }
    }
    return pixels;
  }

  /// Immagine con bit complementati (nero ↔ bianco): usata
  /// dall'encoder TSPL quando la stampante esce in negativo
  /// (Prompt 11-bis, §2).
  MonoBitmap inverted() => MonoBitmap(
        width: width,
        height: height,
        packed: Uint8List.fromList([
          for (final b in packed) b ^ 0xFF,
        ]),
      );
}

/// Larghezza in pixel per [mm] alla risoluzione [dpi], arrotondata a
/// multiplo di 8 (richiesto dai motori a termica).
int rasterWidthForMm(double mm, int dpi) {
  final px = (mm / 25.4 * dpi).round();
  return (px + 7) ~/ 8 * 8;
}

/// Converte pixel RGBA (come `PdfRaster.pixels`) in monocromo, scalando
/// al nearest-neighbor sulla larghezza target. La luminanza sotto la
/// [threshold] (default 128) diventa nero: soglia più alta = stampa più
/// scura.
MonoBitmap monochromeFromRgba(
  Uint8List rgba,
  int srcWidth,
  int srcHeight, {
  required int targetWidth,
  int threshold = 128,
}) {
  final width = targetWidth - targetWidth % 8;
  final scale = srcWidth / width;
  final targetHeight = (srcHeight / scale).round().clamp(1, 100000);
  final bytesPerRow = width ~/ 8;
  final packed = Uint8List(bytesPerRow * targetHeight);

  for (var y = 0; y < targetHeight; y++) {
    final sy = (y * srcHeight / targetHeight).floor().clamp(0, srcHeight - 1);
    for (var x = 0; x < width; x++) {
      final sx = (x * scale).floor().clamp(0, srcWidth - 1);
      final i = (sy * srcWidth + sx) * 4;
      final luma = 0.299 * rgba[i] + 0.587 * rgba[i + 1] + 0.114 * rgba[i + 2];
      if (luma < threshold) {
        packed[y * bytesPerRow + (x >> 3)] |= 1 << (7 - (x & 7));
      }
    }
  }
  return MonoBitmap(width: width, height: targetHeight, packed: packed);
}

/// Ritaglia i bordi bianchi mantenendo un margine fisso di [marginPx]
/// pixel. Non restituisce mai un'immagine vuota: almeno una riga di
/// contenuto (più margine) resta.
MonoBitmap cropWhiteBorder(MonoBitmap source, {int marginPx = 4}) {
  final w = source.width;
  final h = source.height;
  final bytesPerRow = source.bytesPerRow;
  final rows = source.packed;

  bool rowIsWhite(int y) {
    for (var i = y * bytesPerRow; i < (y + 1) * bytesPerRow; i++) {
      if (rows[i] != 0) return false;
    }
    return true;
  }

  bool colIsWhite(int x) {
    final byteIndex = x >> 3;
    final mask = 1 << (7 - (x & 7));
    for (var y = 0; y < h; y++) {
      if (rows[y * bytesPerRow + byteIndex] & mask != 0) return false;
    }
    return true;
  }

  var top = 0;
  while (top < h - 1 && rowIsWhite(top)) {
    top++;
  }
  var bottom = h - 1;
  while (bottom > top && rowIsWhite(bottom)) {
    bottom--;
  }
  var left = 0;
  while (left < w - 1 && colIsWhite(left)) {
    left++;
  }
  var right = w - 1;
  while (right > left && colIsWhite(right)) {
    right--;
  }

  final newHeight = (bottom - top + 1).clamp(1, h) + marginPx * 2;
  final startY = (top - marginPx).clamp(0, h - 1);
  final newWidthBytes = bytesPerRow; // la larghezza resta invariata

  final out = Uint8List(newHeight * newWidthBytes);
  final copyRows = newHeight.clamp(1, h - startY);
  for (var y = 0; y < copyRows; y++) {
    final srcIndex = (startY + y) * bytesPerRow;
    out.setRange(
      y * newWidthBytes,
      (y + 1) * newWidthBytes,
      rows,
      srcIndex,
    );
  }
  return MonoBitmap(width: w, height: newHeight, packed: out);
}

/// Rasterizza la prima pagina di un PDF di etichetta.
class LabelRasterizer {
  LabelRasterizer({this.threshold = 128, this.marginPx = 4});

  /// Soglia bianco/nero (0–255): più alta = stampa più scura.
  final int threshold;

  /// Margine fisso lasciato attorno al contenuto ritagliato.
  final int marginPx;

  /// Rasterizza la prima pagina del PDF a [dpi] con larghezza di
  /// [widthMm] millimetri (multipla di 8 pixel).
  Future<MonoBitmap> rasterPdfPage(
    Uint8List pdf, {
    required int dpi,
    required double widthMm,
  }) async {
    final page = await Printing.raster(
      pdf,
      pages: null,
      dpi: dpi.toDouble(),
    ).first;
    final mono = monochromeFromRgba(
      page.pixels,
      page.width,
      page.height,
      targetWidth: rasterWidthForMm(widthMm, dpi),
      threshold: threshold,
    );
    final cropped = cropWhiteBorder(mono, marginPx: marginPx);
    if (cropped.isEmpty) {
      debugPrint('Etichetta rasterizzata vuota (soglia $threshold troppo '
          'alta per il contenuto?).');
    }
    return cropped;
  }
}
