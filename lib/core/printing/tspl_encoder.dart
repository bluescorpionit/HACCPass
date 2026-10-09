/// Encoder TSPL (Prompt 11, §3 bis; correzioni Prompt 11-bis, §2).
///
/// Linguaggio delle stampanti di etichette con carta a gap/tacca
/// (Zjiang/Xprinter/MUNBYN e simili): `SIZE`/`GAP` dichiarano la
/// dimensione dell'etichetta, `BITMAP x,y` invia l'immagine
/// monocromatica (righe packate MSB-first, bit 1 = nero) centrata
/// verticalmente nell'altezza dell'etichetta, `PRINT n,c` chiude.
///
/// **Polarità**: alcune TSPL interpretano 0 = nero e l'etichetta esce
/// in negativo; non si può sapere senza hardware. L'impostazione
/// `printer_generic_invert` ("Inverti immagine") complementa i byte.
library;

import 'dart:typed_data';

import 'label_rasterizer.dart';

class TsplEncoder {
  const TsplEncoder({this.gapMm = 2});

  /// Gap tra le etichette (carta a gap standard 2 mm; 0 per carta
  /// continua con tacca nera).
  final double gapMm;

  /// Intestazione dimensione carta e direzione.
  ///
  /// `DENSITY 0..15`: la densità dell'app (1–5) viene mappata a 2–10.
  String header({
    required double widthMm,
    required double heightMm,
    int density = 3,
    int speed = 3,
  }) {
    final densityValue = (density.clamp(1, 5) * 2).clamp(0, 15);
    return 'SIZE ${widthMm.toStringAsFixed(1)}mm,${heightMm.toStringAsFixed(1)}mm\r\n'
        'GAP ${gapMm.toStringAsFixed(1)}mm,0mm\r\n'
        'DIRECTION 1,0\r\n'
        'DENSITY $densityValue\r\n'
        'SPEED ${speed.clamp(1, 5)}\r\n'
        'CLS\r\n';
  }

  /// Offset verticale che centra l'immagine nell'altezza dell'etichetta
  /// (il ritaglio `cropWhiteBorder` lascia il contenuto in alto).
  static int verticalCenterOffset({
    required double labelHeightMm,
    required int imageHeight,
    int dpi = 203,
  }) {
    final labelHeightPx = (labelHeightMm / 25.4 * dpi).round();
    if (imageHeight >= labelHeightPx) return 0;
    return (labelHeightPx - imageHeight) ~/ 2;
  }

  /// Comando `BITMAP x,y,width(bytes),height,mode,data`.
  Uint8List bitmap(MonoBitmap image, {int x = 0, int y = 0}) {
    final out = BytesBuilder();
    final headerAscii = 'BITMAP $x,$y,${image.bytesPerRow},'
        '${image.height},0,';
    out.add(headerAscii.codeUnits);
    out.add(image.packed);
    out.add('\r\n'.codeUnits);
    return out.toBytes();
  }

  /// Etichetta completa: intestazione + bitmap centrata verticalmente +
  /// stampa di [copies] copie. Con [invert] i bit dell'immagine vengono
  /// complementati (etichette in negativo su alcune TSPL).
  Uint8List label(
    MonoBitmap image, {
    required double widthMm,
    required double heightMm,
    int copies = 1,
    int density = 3,
    int dpi = 203,
    bool invert = false,
  }) {
    final out = BytesBuilder();
    out.add(header(widthMm: widthMm, heightMm: heightMm, density: density)
        .codeUnits);
    final effective = invert ? image.inverted() : image;
    final y = verticalCenterOffset(
      labelHeightMm: heightMm,
      imageHeight: effective.height,
      dpi: dpi,
    );
    out.add(bitmap(effective, y: y));
    out.add('PRINT ${copies.clamp(1, 999)},1\r\n'.codeUnits);
    return out.toBytes();
  }

  /// "Prova solo testo" per TSPL: aiuta a distinguere il problema di
  /// linguaggio/protocollo da quello di rasterizzazione immagine.
  Uint8List plainTextTest({
    required double widthMm,
    required double heightMm,
    int density = 3,
  }) {
    final out = BytesBuilder();
    out.add(
      header(
        widthMm: widthMm,
        heightMm: heightMm,
        density: density,
      ).codeUnits,
    );
    out.add('TEXT 16,16,"0",0,1,1,"HACCPass TSPL test"\r\n'.codeUnits);
    out.add('PRINT 1,1\r\n'.codeUnits);
    return out.toBytes();
  }
}
