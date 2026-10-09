import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/printing/escpos_encoder.dart';
import 'package:haccpass/core/printing/label_rasterizer.dart';
import 'package:haccpass/core/printing/tspl_encoder.dart';

/// Prompt 11, §3 bis: byte generati dagli encoder ESC/POS (GS v 0) e
/// TSPL (SIZE/GAP/BITMAP/PRINT): intestazione, larghezza in byte,
/// dimensione carta, numero copie, feed e taglio.
void main() {
  MonoBitmap image({int width = 8, int height = 2, int fill = 0xFF}) =>
      MonoBitmap(
        width: width,
        height: height,
        packed: Uint8List.fromList(
          List.filled((width ~/ 8) * height, fill),
        ),
      );

  group('EscPosEncoder', () {
    const encoder = EscPosEncoder();

    test('init: ESC @', () {
      expect(encoder.init, [0x1B, 0x40]);
    });

    test('taglio: GS V 0', () {
      expect(encoder.cut, [0x1D, 0x56, 0x00]);
    });

    test('raster GS v 0: intestazione e dimensioni', () {
      final bytes = encoder.raster(image(width: 64, height: 3));
      // GS v 0 m=0 poi xL xH (bytes/riga) e yL yH (altezza).
      expect(bytes.sublist(0, 4), [0x1D, 0x76, 0x30, 0x00]);
      expect(bytes[4], 8, reason: '64 px = 8 bytes/riga');
      expect(bytes[5], 0);
      expect(bytes[6], 3, reason: 'altezza 3');
      expect(bytes[7], 0);
      expect(bytes.length, 8 + 8 * 3, reason: 'intestazione + dati');
    });

    test('etichetta: init, una copia per volta, feed finale e taglio',
        () async {
      final bytes = encoder.label(
        image(),
        copies: 2,
        feedLines: 10,
      );
      // ESC @ in testa.
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
      final asString = bytes;
      // Due blocchi raster (due copie).
      var count = 0;
      for (var i = 0; i < asString.length - 3; i++) {
        if (asString[i] == 0x1D &&
            asString[i + 1] == 0x76 &&
            asString[i + 2] == 0x30) {
          count++;
        }
      }
      expect(count, 2, reason: 'una raster per copia');
      // Chiude con feed e taglio.
      expect(
        bytes.sublist(bytes.length - 5),
        [0x1B, 0x64, 10, 0x1D, 0x56, 0x00].sublist(1),
      );
      expect(bytes[bytes.length - 6], 0x1B);
      expect(bytes[bytes.length - 5], 0x64);
      expect(bytes[bytes.length - 4], 10);
    });
  });

  group('TsplEncoder', () {
    test('intestazione: SIZE, GAP, DIRECTION, DENSITY, CLS', () {
      final header = const TsplEncoder().header(
        widthMm: 62,
        heightMm: 40,
        density: 3,
      );
      expect(header, contains('SIZE 62.0mm,40.0mm'));
      expect(header, contains('GAP 2.0mm,0mm'));
      expect(header, contains('DIRECTION 1,0'));
      expect(header, contains('DENSITY 6'), reason: 'densità 1–5 → 2–10');
      expect(header, contains('CLS'));
    });

    test('BITMAP: larghezza in byte e altezza nei parametri', () {
      final bytes = const TsplEncoder().bitmap(image(width: 48, height: 5));
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('BITMAP 0,0,6,5,0,'));
      expect(text, endsWith('\r\n'));
      expect(bytes.length, 'BITMAP 0,0,6,5,0,'.length + 6 * 5 + 2);
    });

    test('label: intestazione + bitmap centrata + PRINT copie', () {
      final bytes = const TsplEncoder().label(
        image(width: 8, height: 2),
        widthMm: 50,
        heightMm: 30,
        copies: 3,
      );
      final text = String.fromCharCodes(bytes);
      expect(text, contains('SIZE 50.0mm,30.0mm'));
      // y = (240 px - 2 px) ~/ 2: immagine centrata verticalmente.
      expect(text, contains('BITMAP 0,${(240 - 2) ~/ 2},1,2,0,'));
      expect(text.trimRight().endsWith('PRINT 3,1'), isTrue);
    });

    test('invert = true: i bit dell\'immagine sono complementati',
        () async {
      final encoder = const TsplEncoder();
      final normal = encoder.label(
        image(fill: 0x0F),
        widthMm: 50,
        heightMm: 30,
      );
      final inverted = encoder.label(
        image(fill: 0x0F),
        widthMm: 50,
        heightMm: 30,
        invert: true,
      );
      // L'intestazione ASCII è identica: differiscono solo i dati.
      // Il primo byte immagine è 0x0F: marca l'inizio dei dati.
      final dataStart = normal.indexOf(0x0F);
      final dataEnd = normal.lastIndexOf(0x0F) + 1;
      final invertedStart = inverted.indexOf(0xF0);
      expect(invertedStart, dataStart,
          reason: 'stessa lunghezza di intestazione');
      final imgNormal = normal.sublist(dataStart, dataEnd);
      final imgInverted =
          inverted.sublist(invertedStart, invertedStart + imgNormal.length);
      expect(imgInverted.length, imgNormal.length);
      for (var i = 0; i < imgNormal.length; i++) {
        expect(imgInverted[i], imgNormal[i] ^ 0xFF);
      }
      expect(imgNormal.first, 0x0F);
      expect(imgInverted.first, 0xF0);
    });

    test('centraggio verticale: y per 62x40, 50x30, 40x30', () {
      // Etichetta 62x40 a 203 dpi = 320 px di altezza.
      expect(
        TsplEncoder.verticalCenterOffset(
          labelHeightMm: 40,
          imageHeight: 200,
        ),
        (320 - 200) ~/ 2,
      );
      // 50x30 → 240 px.
      expect(
        TsplEncoder.verticalCenterOffset(
          labelHeightMm: 30,
          imageHeight: 200,
        ),
        (240 - 200) ~/ 2,
      );
      // Immagine più alta dell'etichetta: y = 0.
      expect(
        TsplEncoder.verticalCenterOffset(
          labelHeightMm: 30,
          imageHeight: 300,
        ),
        0,
      );
    });

    test('label: BITMAP parte con la y di centraggio', () {
      final bytes = const TsplEncoder().label(
        image(width: 8, height: 100),
        widthMm: 62,
        heightMm: 40,
      );
      final text = String.fromCharCodes(bytes);
      final y = (320 - 100) ~/ 2;
      expect(text, contains('BITMAP 0,$y,1,100,0,'));
    });
  });
}
