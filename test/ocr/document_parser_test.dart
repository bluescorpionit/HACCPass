import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/services/ocr/document_parser.dart';
import 'package:haccpass/services/ocr/ocr_port.dart';

/// Test del parser documenti (Prompt 8, A5) su fixture SINTETICHE e
/// anonimizzate in test/fixtures/ocr/: sei impaginazioni diverse di
/// DDT/fattura. Nessun dato reale.
void main() {
  final parser = const DocumentParser();

  /// Carica una fixture: righe con testo, riquadro [l,t,r,b] e confidenza.
  OcrResult loadFixture(String name) {
    final file = File('test/fixtures/ocr/$name.json');
    final map = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final lines = <OcrLine>[];
    for (final raw in (map['lines'] as List<Object?>).cast<Map>()) {
      final box = (raw['box'] as List).cast<num>();
      lines.add(OcrLine(
        text: raw['text'] as String,
        box: OcrBox(
          left: box[0].toDouble(),
          top: box[1].toDouble(),
          right: box[2].toDouble(),
          bottom: box[3].toDouble(),
        ),
        confidence: (raw['confidence'] as num?)?.toDouble(),
      ));
    }
    return OcrResult(lines: lines);
  }

  group('primitive italiane', () {
    test('date nei formati gg/mm/aaaa, gg-mm-aa, gg.mm.aaaa, mm/aaaa', () {
      expect(parseItalianDate('14/10/2026'), DateTime(2026, 10, 14));
      expect(parseItalianDate('30-09-26'), DateTime(2026, 9, 30));
      expect(parseItalianDate('05.10.2026'), DateTime(2026, 10, 5));
      expect(parseItalianDate('11/2027'), DateTime(2027, 11, 1));
    });

    test('date impossibili scartate', () {
      expect(parseItalianDate('32/13/2026'), isNull);
      expect(parseItalianDate('99/99/9999'), isNull);
      expect(parseItalianDate('05/13/2026'), isNull);
    });

    test('numeri italiani: virgola decimale, punto migliaia', () {
      expect(parseItalianNumber('5,500'), closeTo(5.5, 0.001));
      expect(parseItalianNumber('12'), 12);
      expect(parseItalianNumber('1.250,50'), closeTo(1250.5, 0.001));
      expect(parseItalianNumber('1.234'), 1234);
    });

    test('confusioni OCR corrette SOLO in contesto numerico', () {
      expect(parseItalianDate('O5.1O.2O26'), DateTime(2026, 10, 5));
      expect(parseItalianDate('1S/02/2O27'), DateTime(2027, 2, 15));
      expect(parseItalianNumber('2,5OO'), closeTo(2.5, 0.001));
      expect(parseItalianNumber('S,OOO'), closeTo(5.0, 0.001));
    });

    test('partita IVA: checksum valido e non valido', () {
      expect(isValidItalianVat('02345678904'), isTrue);
      expect(isValidItalianVat('02345678905'), isFalse);
      expect(isValidItalianVat('123456789'), isFalse);
    });
  });

  group('fixture 1: DDT con tabella a colonne', () {
    final doc = parser.parse(
        OcrResult(lines: _linesOf(loadFixture('ddt_tabella'))));

    test('testata: tipo, numero, data, P.IVA, fornitore', () {
      expect(doc.kind, DocKind.ddt);
      expect(doc.docNumber?.value, '452/AA');
      expect(doc.docDate?.value, DateTime(2026, 10, 14));
      expect(doc.supplierVat?.value, '02345678904');
      expect(doc.supplierName?.value, contains('ROSSI'));
    });

    test('tre righe prodotto con lotto, scadenza, quantità e unità', () {
      expect(doc.lines, hasLength(3));
      final first = doc.lines.first;
      expect(first.description?.value, contains('Prosciutto cotto'));
      expect(first.lot?.value, 'LT2215A');
      expect(first.expiry?.value, DateTime(2027, 3, 12));
      expect(first.quantity?.value, closeTo(5.5, 0.001));
      expect(first.unit?.value, 'KG');
      final last = doc.lines.last;
      expect(last.lot?.value, 'L0449');
      expect(last.quantity?.value, 12);
      expect(last.unit?.value, 'PZ');
    });

    test('scadenze successive alla data documento: nessun avviso', () {
      expect(doc.warnings, isEmpty);
    });
  });

  group('fixture 2: lotto e scadenza sotto la descrizione', () {
    final doc = parser.parse(loadFixture('ddt_lotto_sotto'));

    test('i dati sotto la descrizione si uniscono alla riga precedente', () {
      expect(doc.lines, hasLength(2));
      final salame = doc.lines.first;
      expect(salame.description?.value, contains('Salame felino'));
      expect(salame.lot?.value, 'SL8421');
      expect(salame.expiry?.value, DateTime(2027, 4, 2));
      expect(salame.quantity?.value, 8);
      final culatello = doc.lines[1];
      expect(culatello.description?.value, contains('Culatello'));
      expect(culatello.lot?.value, 'CZ1180');
      expect(culatello.quantity?.value, closeTo(4.0, 0.001));
    });
  });

  group('fixture 3: fattura con testata', () {
    final doc = parser.parse(loadFixture('fattura_testata'));

    test('tipo fattura, numero, data gg-mm-aa, P.IVA valida', () {
      expect(doc.kind, DocKind.fattura);
      expect(doc.docNumber?.value, '2026/118');
      expect(doc.docDate?.value, DateTime(2026, 9, 30));
      expect(doc.supplierVat?.value, '02345678904');
      expect(doc.supplierName?.value, contains('ROSSI ALIMENTARI'));
    });

    test('nessuna riga prodotto inventata dagli importi', () {
      expect(doc.lines, isEmpty);
    });
  });

  group('fixture 4: scadenza mese/anno', () {
    final doc = parser.parse(loadFixture('ddt_mese_anno'));

    test('mm/aaaa diventa il primo giorno del mese', () {
      expect(doc.lines, hasLength(2));
      expect(doc.lines.first.expiry?.value, DateTime(2027, 11, 1));
      expect(doc.lines[1].expiry?.value, DateTime(2028, 3, 1));
      expect(doc.lines.first.lot?.value, 'PE2210');
      expect(doc.lines.first.quantity?.value, closeTo(4.5, 0.001));
    });
  });

  group('fixture 5: confusioni OCR', () {
    final doc = parser.parse(loadFixture('ddt_ocr_confusioni'));

    test('date, P.IVA e quantità con caratteri confusi vengono ripristinate',
        () {
      expect(doc.docDate?.value, DateTime(2026, 10, 5));
      expect(doc.supplierVat?.value, '02345678904');
      final first = doc.lines.first;
      expect(first.expiry?.value, DateTime(2027, 2, 15));
      expect(first.quantity?.value, closeTo(2.5, 0.001));
      final second = doc.lines[1];
      expect(second.expiry?.value, DateTime(2026, 10, 20));
      expect(second.quantity?.value, closeTo(5.0, 0.001));
    });

    test('il numero documento alfanumerico non viene "corretto"', () {
      expect(doc.docNumber?.value, '45O2');
    });
  });

  group('fixture 6: righe multiple senza tabella', () {
    final doc = parser.parse(loadFixture('ddt_righe_multiple'));

    test('due righe con etichette lotto/scadenza/quantità', () {
      expect(doc.kind, DocKind.ddt);
      expect(doc.docNumber?.value, '1002');
      expect(doc.lines, hasLength(2));
      expect(doc.lines.first.lot?.value, 'LT2341');
      expect(doc.lines.first.expiry?.value, DateTime(2027, 4, 10));
      expect(doc.lines.first.quantity?.value, closeTo(6.0, 0.001));
      expect(doc.lines.first.unit?.value, 'KG');
      expect(doc.lines[1].lot?.value, 'AB8890');
      expect(doc.lines[1].quantity?.value, 12);
    });
  });

  group('mai inventare', () {
    test('documento vuoto: tutti i campi nulli, nessuna eccezione', () {
      final doc = parser.parse(OcrResult.empty());
      expect(doc.kind, DocKind.sconosciuto);
      expect(doc.supplierName, isNull);
      expect(doc.docNumber, isNull);
      expect(doc.docDate, isNull);
      expect(doc.lines, isEmpty);
      expect(doc.warnings, isEmpty);
    });

    test('testo generico senza etichette: nessun campo estratto', () {
      final doc = parser.parse(const OcrResult(lines: [
        OcrLine(
          text: 'Benvenuti al ristorante da Gigi',
          box: OcrBox(left: 10, top: 10, right: 400, bottom: 30),
          confidence: 0.95,
        ),
      ]));
      expect(doc.lines, isEmpty);
      expect(doc.docNumber, isNull);
    });

    test('scadenza precedente alla data documento: segnalata', () {
      final result = const OcrResult(lines: [
        OcrLine(
            text: 'Data documento 10/10/2026',
            box: OcrBox(left: 0, top: 0, right: 300, bottom: 20)),
        OcrLine(
            text: 'Lotto AB123 Scadenza 01/05/2025 Quantità 4 KG',
            box: OcrBox(left: 0, top: 100, right: 600, bottom: 120)),
      ]);
      final doc = parser.parse(result);
      expect(doc.lines.first.expiry?.value, DateTime(2025, 5, 1));
      expect(doc.warnings, isNotEmpty);
      expect(doc.warnings.first, contains('precedente'));
    });
  });

  group('GS1 (A4)', () {
    test('GS1-128 con parentesi: GTIN, lotto, scadenza, peso', () {
      final data = parseGs1('(01)01234567890128(10)LOTTO123(17)270330(3103)012500');
      expect(data, isNotNull);
      expect(data!.gtin, '01234567890128');
      expect(data.lot, 'LOTTO123');
      expect(data.expiry, DateTime(2027, 3, 30));
      expect(data.weightKg, closeTo(12.5, 0.001));
    });

    test('giorno 00 = fine mese', () {
      final data = parseGs1('(01)01234567890128(17)271100(10)L1');
      expect(data!.expiry, DateTime(2027, 11, 30));
    });

    test('(37) numero pezzi', () {
      final data = parseGs1('(01)01234567890128(37)12(10)BX9');
      expect(data!.count, 12);
    });

    test('EAN-13 semplice: nessun campo GS1', () {
      expect(parseGs1('8012345000123'), isNull);
    });

    test('formato senza parentesi (FNC1)', () {
      final data = parseGs1('01012345678901281727033010LOTTO99');
      expect(data!.gtin, '01234567890128');
      expect(data.expiry, DateTime(2027, 3, 30));
      expect(data.lot, 'LOTTO99');
    });
  });
}

List<OcrLine> _linesOf(OcrResult result) => result.lines;
