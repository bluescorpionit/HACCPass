import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/theme/app_theme.dart';
import 'package:haccpass/screens/goods/document_scan_flow.dart';
import 'package:haccpass/services/ocr/document_parser.dart';
import 'package:haccpass/services/ocr/document_scan_service.dart';
import 'package:haccpass/services/ocr/ocr_port.dart';

/// Widget test (Prompt 8, A5) della schermata "Verifica dati letti" e del
/// servizio di scansione con riconoscitore FINTO (nessun ML Kit).
void main() {
  OcrResult fixture() {
    final map = jsonDecode(
      File('test/fixtures/ocr/ddt_tabella.json').readAsStringSync(),
    ) as Map<String, Object?>;
    return OcrResult(
      lines: [
        for (final raw in (map['lines'] as List<Object?>).cast<Map>())
          OcrLine(
            text: raw['text'] as String,
            box: OcrBox(
              left: 100,
              top: (raw['box'] as List).cast<num>()[1].toDouble(),
              right: 800,
              bottom: (raw['box'] as List).cast<num>()[3].toDouble(),
            ),
            confidence: (raw['confidence'] as num?)?.toDouble(),
          ),
      ],
    );
  }

  testWidgets('righe riconosciute visibili, campo modificabile, conferma '
      'restituisce le righe selezionate', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.15;
    addTearDown(tester.view.reset);
    addTearDown(
        tester.platformDispatcher.clearTextScaleFactorTestValue);

    final outcome = DocumentScanOutcome(
      document: const DocumentParser().parse(fixture()),
      ocrPages: const [],
      originalPaths: const ['fake.jpg'],
    );

    List<ConfirmedScanRow>? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              result = await Navigator.of(context)
                  .push<List<ConfirmedScanRow>>(MaterialPageRoute(
                builder: (_) => DocumentReviewScreen(outcome: outcome),
              ));
            },
            child: const Text('apri'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    // Testata e righe lette dal documento.
    expect(find.text('Verifica dati letti'), findsOneWidget);
    expect(find.textContaining('Prosciutto cotto'), findsWidgets);
    expect(find.textContaining('452/AA'), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'nessun overflow a 360x640 con scala 1.15');

    // Modifica del lotto della prima riga.
    final lotField = find.widgetWithText(TextField, 'LT2215A');
    expect(lotField, findsOneWidget);
    await tester.enterText(lotField, 'LT9999Z');

    // Deseleziona la terza riga: solo le prime due tornano.
    await tester.drag(
      find.byType(Scrollable).first,
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    final thirdCheckbox = find.byType(CheckboxListTile).at(2);
    await tester.ensureVisible(thirdCheckbox);
    await tester.pump();
    await tester.tap(thirdCheckbox);
    await tester.pump();

    // Il pulsante Continua è il FAB: sempre visibile.
    await tester.tap(find.text('Continua'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!, hasLength(2), reason: 'terza riga deselezionata');
    expect(result!.first.lot, 'LT9999Z', reason: 'modifica applicata');
  });

  testWidgets('annullamento: nessuna riga, nessun dato salvato',
      (tester) async {
    final outcome = DocumentScanOutcome(
      document: const DocumentParser().parse(OcrResult.empty()),
      ocrPages: const [],
      originalPaths: const ['fake.jpg'],
    );

    var gotResult = false;
    List<ConfirmedScanRow?>? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              result = await Navigator.of(context)
                  .push<List<ConfirmedScanRow>>(MaterialPageRoute(
                builder: (_) => DocumentReviewScreen(outcome: outcome),
              ));
              gotResult = true;
            },
            child: const Text('apri'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('apri'));
    await tester.pumpAndSettle();

    // Nessuna riga dal documento vuoto: "Continua" disabilitato, nessuna
    // eccezione. Il back chiude senza salvare nulla.
    expect(find.text('Aggiungi riga'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(gotResult, isTrue);
    expect(result, isNull, reason: 'nessun dato fuori dalla conferma');
  });

  test('DocumentScanService con FakeTextRecognizer: righe unite e OCR '
      'chiamato per pagina', () async {
    final fake = FakeTextRecognizer(fixture());
    final service = DocumentScanService(recognizer: fake);
    final dir = await Directory.systemTemp.createTemp('scan_fake');

    // Il file sorgente esiste (il servizio non lo legge: passa il percorso
    // al fake, nessun plugin).
    final source = File('${dir.path}/documento.jpg')
      ..writeAsStringSync('immagine fintissima');

    final outcome = await service.scan(
      sourcePaths: [source.path],
      tempDir: dir,
    );
    expect(fake.recognizeCalls, 1);
    expect(outcome.hasData, isTrue);
    expect(outcome.document.lines, isNotEmpty);
    expect(outcome.originalPaths, [source.path]);

    await service.cleanup(outcome.ocrPages);
    await dir.delete(recursive: true);
  });
}
