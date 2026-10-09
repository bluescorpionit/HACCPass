import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/printing/label_rasterizer.dart';

/// Prompt 11, §1: rasterizzazione condivisa — dimensioni in pixel per i
/// formati alle risoluzioni dei motori, soglia, larghezza multipla di 8,
/// nessuna pagina vuota.
void main() {
  group('rasterWidthForMm', () {
    test('62 mm a 203 dpi (Niimbot/generica): multiplo di 8', () {
      final w = rasterWidthForMm(62, 203);
      expect(w % 8, 0);
      expect(w, 496); // 62/25.4*203 = 495.6 → 496
    });

    test('50 mm a 203 dpi', () {
      final w = rasterWidthForMm(50, 203);
      expect(w % 8, 0);
      expect(w, 400); // 399.6 → 400
    });

    test('40 mm a 203 dpi', () {
      final w = rasterWidthForMm(40, 203);
      expect(w % 8, 0);
      expect(w, 320);
    });

    test('62 mm a 300 dpi (Brother QL / Niimbot 300)', () {
      final w = rasterWidthForMm(62, 300);
      expect(w % 8, 0);
      expect(w, 736); // 732.3 → 736
    });

    test('50 mm a 300 dpi', () {
      final w = rasterWidthForMm(50, 300);
      expect(w, 592); // 590.5 → 592 (multiplo di 8)
    });
  });

  group('monochromeFromRgba', () {
    test('soglia 128: il nero diventa 1, il bianco 0', () {
      // Immagine 8x2: metà sinistra nera, metà destra bianca.
      final rgba = Uint8List(8 * 2 * 4);
      for (var y = 0; y < 2; y++) {
        for (var x = 0; x < 8; x++) {
          final i = (y * 8 + x) * 4;
          final black = x < 4;
          rgba[i] = black ? 0 : 255;
          rgba[i + 1] = black ? 0 : 255;
          rgba[i + 2] = black ? 0 : 255;
          rgba[i + 3] = 255;
        }
      }
      final mono = monochromeFromRgba(rgba, 8, 2, targetWidth: 8);
      expect(mono.width, 8);
      expect(mono.height, 2);
      expect(mono.packed.length, 2); // 2 righe da 1 byte
      expect(mono.packed[0], 0xF0, reason: '4 pixel neri MSB-first');
      expect(mono.packed[1], 0xF0);
    });

    test('soglia più alta = più scuro (i grigi diventano neri)', () {
      // Grigio 160: con soglia 128 resta bianco, con 200 diventa nero.
      final rgba = Uint8List.fromList(
        List.filled(8 * 4, 0).asMap().entries.map((e) {
          final channel = e.key % 4;
          return channel == 3 ? 255 : 160;
        }).toList(),
      );
      final chiaro = monochromeFromRgba(rgba, 8, 1, targetWidth: 8);
      final scuro = monochromeFromRgba(
        rgba,
        8,
        1,
        targetWidth: 8,
        threshold: 200,
      );
      expect(chiaro.packed[0], 0x00);
      expect(scuro.packed[0], 0xFF);
    });

    test('scala nearest-neighbor alla larghezza target', () {
      // 16x1 bianca con un pixel nero in posizione 8.
      final rgba = Uint8List(16 * 4);
      for (var x = 0; x < 16; x++) {
        final i = x * 4;
        rgba[i] = x == 8 ? 0 : 255;
        rgba[i + 1] = x == 8 ? 0 : 255;
        rgba[i + 2] = x == 8 ? 0 : 255;
        rgba[i + 3] = 255;
      }
      final mono = monochromeFromRgba(rgba, 16, 1, targetWidth: 8);
      expect(mono.width, 8);
      expect(mono.height, 1);
      expect(mono.packed[0] != 0, isTrue, reason: 'il nero è preservato');
    });
  });

  group('cropWhiteBorder', () {
    test('nessuna pagina vuota: margine fisso e contenuto preservato', () {
      // 24x10 tutta bianca: il ritaglio non restituisce mai zero.
      final white = MonoBitmap(
        width: 24,
        height: 10,
        packed: Uint8List(3 * 10),
      );
      final cropped = cropWhiteBorder(white, marginPx: 4);
      expect(cropped.width, 24, reason: 'la larghezza resta invariata');
      expect(cropped.height, greaterThanOrEqualTo(1));
      expect(cropped.packed.isNotEmpty, isTrue);
    });

    test('i bordi bianchi vengono tagliati, il contenuto resta', () {
      // 32x12 con un blocco nero 8x4 al centro.
      final packed = Uint8List(4 * 12);
      for (var y = 4; y < 8; y++) {
        packed[y * 4 + 1] = 0xFF; // seconda colonna-di-byte piena
      }
      final source = MonoBitmap(width: 32, height: 12, packed: packed);
      final cropped = cropWhiteBorder(source, marginPx: 2);
      expect(cropped.height, lessThan(12));
      expect(cropped.isEmpty, isFalse, reason: 'il contenuto resta');
      // Il nero sopravvive al ritaglio.
      expect(cropped.packed.any((b) => b != 0), isTrue);
    });
  });

  group('MonoBitmap.toPixelList', () {
    test('bit MSB-first → lista 0/1', () {
      final mono = MonoBitmap(
        width: 8,
        height: 1,
        packed: Uint8List.fromList([0xB0]), // 1011 0000 MSB-first
      );
      expect(mono.toPixelList(), [1, 0, 1, 1, 0, 0, 0, 0]);
    });
  });
}
