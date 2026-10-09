/// Encoder ESC/POS raster (Prompt 11, §3 bis; bande Prompt 16, §7.3).
///
/// `GS v 0` (stampa raster): comune a quasi tutte le stampanti termiche
/// economiche (scontrini ed etichette). L'immagine è monocromatica con
/// righe packate MSB-first, bit 1 = punto stampato (nero).
///
/// **Bande**: molte stampanti economiche ignorano o troncano i blocchi
/// raster alti quanto tutta l'etichetta: l'immagine viene divisa in
/// bande di [EscPosOptions.bandRows] righe (default 128; 24 per modelli
/// molto vecchi), una `GS v 0` per banda, con una breve pausa tra le
/// bande gestita dal chiamante ([labelSegments] restituisce i segmenti).
///
/// **Fine lavoro**: avanzamento configurabile in mm (default 4), NESSUN
/// taglio `GS V` se la stampante non è dichiarata "con taglierina"
/// (può bloccare alcune stampanti di etichette) e form feed `FF`
/// opzionale per passare all'etichetta successiva.
library;

import 'dart:typed_data';

import 'label_rasterizer.dart';

/// Opzioni del lavoro ESC/POS (Prompt 16, §7.3).
class EscPosOptions {
  const EscPosOptions({
    this.bandRows = 128,
    this.feedRows = 32,
    this.cut = false,
    this.formFeed = false,
  });

  /// Righe per banda raster (128 default; 24 per modelli vecchi).
  final int bandRows;

  /// Righe di avanzamento dopo l'immagine (default ~4 mm a 203 dpi).
  final int feedRows;

  /// Taglierina attiva: emette `GS V 0` a fine lavoro.
  final bool cut;

  /// Avanza all'etichetta successiva con `FF` (0x0C).
  final bool formFeed;

  /// Righe di avanzamento per [mm] a [dpi].
  static int feedRowsForMm(double mm, int dpi) =>
      (mm / 25.4 * dpi).round().clamp(0, 255);
}

class EscPosEncoder {
  const EscPosEncoder();

  /// Reset: ESC @ (svuota il buffer e gli stati della stampante).
  Uint8List get init => Uint8List.fromList([0x1B, 0x40]);

  /// Alimenta di [n] righe: ESC d n.
  Uint8List feed(int n) => Uint8List.fromList([0x1B, 0x64, n.clamp(0, 255)]);

  /// Taglio: GS V m=0 (taglio pieno al termine del feed).
  Uint8List get cut => Uint8List.fromList([0x1D, 0x56, 0x00]);

  /// Form feed: passa all'etichetta successiva.
  Uint8List get formFeed => Uint8List.fromList([0x0C]);

  /// Blocco raster `GS v 0 m=0` per una banda di [rows] righe prese
  /// dall'immagine a partire da [startRow].
  Uint8List rasterBand(MonoBitmap image, int startRow, int rows) {
    final bytesPerRow = image.bytesPerRow;
    final header = <int>[
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
      rows & 0xFF, (rows >> 8) & 0xFF,
    ];
    final out = BytesBuilder();
    out.add(header);
    final start = startRow * bytesPerRow;
    final end = (startRow + rows) * bytesPerRow;
    out.add(image.packed.sublist(start, end.clamp(0, image.packed.length)));
    return out.toBytes();
  }

  /// Blocco raster unico dell'intera immagine (compatibilità/test).
  Uint8List raster(MonoBitmap image) => rasterBand(image, 0, image.height);

  /// Numero di bande e loro altezze per [image] con [bandRows].
  static List<int> bandHeights(int imageHeight, int bandRows) {
    final band = bandRows.clamp(1, 255);
    if (imageHeight <= 0) return const [];
    return [
      for (var start = 0; start < imageHeight; start += band)
        (imageHeight - start).clamp(0, band),
    ];
  }

  /// Lavoro completo come SEGMENTI: init, una `GS v 0` per banda per
  /// ogni copia (il chiamante mette una breve pausa tra le bande), poi
  /// avanzamento, form feed e taglio secondo [options].
  List<Uint8List> labelSegments(
    MonoBitmap image, {
    int copies = 1,
    EscPosOptions options = const EscPosOptions(),
  }) {
    final segments = <Uint8List>[init];
    final heights = bandHeights(image.height, options.bandRows);
    var startRow = 0;
    for (final height in heights) {
      segments.add(rasterBand(image, startRow, height));
      startRow += height;
    }
    // Le copie ripetono SOLO le bande (l'init è unico).
    for (var copy = 1; copy < copies.clamp(1, 999); copy++) {
      var copyStart = 0;
      for (final height in heights) {
        segments.add(rasterBand(image, copyStart, height));
        copyStart += height;
      }
    }
    segments.add(feed(options.feedRows));
    if (options.formFeed) segments.add(formFeed);
    if (options.cut) segments.add(cut);
    return segments;
  }

  /// Compatibilità: lavoro completo come byte concatenati.
  Uint8List label(
    MonoBitmap image, {
    int copies = 1,
    int feedLines = 32,
    bool cut = false,
    bool formFeed = false,
    int bandRows = 255,
  }) {
    final out = BytesBuilder();
    for (final segment in labelSegments(
      image,
      copies: copies,
      options: EscPosOptions(
        bandRows: bandRows,
        feedRows: feedLines,
        cut: cut,
        formFeed: formFeed,
      ),
    )) {
      out.add(segment);
    }
    return out.toBytes();
  }

  /// "Prova solo testo" (Prompt 16, §7.4): se questa stampa e
  /// l'etichetta no, il problema è l'immagine; se nemmeno questa
  /// stampa, il problema è rete/porta/linguaggio.
  Uint8List plainTextTest({bool cut = false}) {
    final out = BytesBuilder();
    out.add(init);
    out.add('HACCPass prova 9100\n'.codeUnits);
    out.add(feed(3));
    if (cut) out.add(this.cut);
    return out.toBytes();
  }
}
