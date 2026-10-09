/// Encoder ESC/POS raster (Prompt 11, §3 bis).
///
/// `GS v 0` (stampa raster): comune a quasi tutte le stampanti termiche
/// economiche (scontrini ed etichette). L'immagine è monocromatica con
/// righe packate MSB-first, bit 1 = punto stampato (nero).
library;

import 'dart:typed_data';

import 'label_rasterizer.dart';

class EscPosEncoder {
  const EscPosEncoder();

  /// Reset: ESC @.
  Uint8List get init => Uint8List.fromList([0x1B, 0x40]);

  /// Alimenta di [n] righe: ESC d n.
  Uint8List feed(int n) => Uint8List.fromList([0x1B, 0x64, n.clamp(0, 255)]);

  /// Taglio: GS V m=0 (taglio pieno al termine del feed).
  Uint8List get cut => Uint8List.fromList([0x1D, 0x56, 0x00]);

  /// Blocco raster `GS v 0 m` con m=0 (modalità normale).
  Uint8List raster(MonoBitmap image) {
    final bytesPerRow = image.bytesPerRow;
    final header = <int>[
      0x1D, 0x76, 0x30, 0x00,
      bytesPerRow & 0xFF, (bytesPerRow >> 8) & 0xFF,
      image.height & 0xFF, (image.height >> 8) & 0xFF,
    ];
    final out = BytesBuilder();
    out.add(header);
    out.add(image.packed);
    return out.toBytes();
  }

  /// Etichetta completa: init, una copia del raster per ogni copia, feed
  /// e taglio al termine (il feed tiene conto dei taglierini delle
  /// stampanti di etichette: minimo [feedLines]).
  Uint8List label(
    MonoBitmap image, {
    int copies = 1,
    int feedLines = 40,
    bool cut = true,
  }) {
    final out = BytesBuilder();
    out.add(init);
    final rasterBlock = raster(image);
    for (var i = 0; i < copies.clamp(1, 999); i++) {
      out.add(rasterBlock);
      if (i < copies - 1) {
        out.add(feed(feedLines));
      }
    }
    out.add(feed(feedLines));
    if (cut) out.add(this.cut);
    return out.toBytes();
  }
}
