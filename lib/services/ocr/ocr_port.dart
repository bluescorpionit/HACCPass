import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Riquadro di delimitazione di una riga OCR: solo numeri, nessuna
/// dipendenza del parser da Flutter/ML Kit (resta Dart puro e testabile).
class OcrBox {
  const OcrBox({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  /// Sovrapposizione orizzontale con un altro riquadro (per l'assegnazione
  /// alle colonne delle tabelle).
  bool overlapsHorizontally(OcrBox other, {double tolerance = 0}) =>
      left < other.right + tolerance && other.left < right + tolerance;

  @override
  String toString() => 'OcrBox($left, $top, $right, $bottom)';
}

/// Singola riga riconosciuta: testo, riquadro e (se disponibile)
/// confidenza OCR 0–1.
class OcrLine {
  const OcrLine({
    required this.text,
    required this.box,
    this.confidence,
  });

  final String text;
  final OcrBox box;
  final double? confidence;
}

/// Risultato del riconoscimento: righe ordinate dall'alto al basso.
class OcrResult {
  const OcrResult({required this.lines});

  final List<OcrLine> lines;

  factory OcrResult.empty() => const OcrResult(lines: []);
}

/// Porta del riconoscimento testo (Prompt 8, A1): l'app dipende solo da
/// questa astrazione; ML Kit è un'implementazione, i test usano fake.
abstract interface class TextRecognizerPort {
  /// Riconosce il testo da un'immagine sul telefono: NESSUNA chiamata di
  /// rete, nessun invio a servizi esterni.
  Future<OcrResult> recognize(String imagePath);

  void dispose();
}

/// Implementazione reale con google_mlkit_text_recognition, script Latin
/// (l'italiano è latino: nessuno script aggiuntivo da includere).
class MlkitTextRecognizer implements TextRecognizerPort {
  MlkitTextRecognizer();

  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  @override
  Future<OcrResult> recognize(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final visionText = await _recognizer.processImage(inputImage);
    final lines = <OcrLine>[
      for (final block in visionText.blocks)
        for (final line in block.lines)
          OcrLine(
            text: line.text,
            box: OcrBox(
              left: line.boundingBox.left.toDouble(),
              top: line.boundingBox.top.toDouble(),
              right: line.boundingBox.right.toDouble(),
              bottom: line.boundingBox.bottom.toDouble(),
            ),
            confidence: line.confidence,
          ),
    ]..sort((a, b) => a.box.top.compareTo(b.box.top));
    return OcrResult(lines: lines);
  }

  @override
  void dispose() {
    _recognizer.close();
  }
}

/// Fake per i test: risponde con un risultato preimpostato.
class FakeTextRecognizer implements TextRecognizerPort {
  FakeTextRecognizer([OcrResult? result])
      : _result = result ?? OcrResult.empty();

  OcrResult _result;
  int recognizeCalls = 0;
  List<String> requestedPaths = [];

  set result(OcrResult value) => _result = value;

  @override
  Future<OcrResult> recognize(String imagePath) async {
    recognizeCalls++;
    requestedPaths.add(imagePath);
    return _result;
  }

  @override
  void dispose() {}
}
