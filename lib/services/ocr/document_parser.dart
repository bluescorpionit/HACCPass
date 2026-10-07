/// Parser dei documenti commerciali (DDT/fatture) dal testo OCR.
///
/// SOLO Dart puro: nessuna dipendenza da Flutter o ML Kit, input
/// `OcrResult`, output `ParsedDocument`. Regole per l'italiano (etichette
/// tolleranti a maiuscole/punteggiatura/errori OCR, date nei formati
/// italiani, numeri con virgola, tabelle per allineamento delle colonne).
///
/// Regola d'oro: **mai inventare** — un campo che non si trova resta
/// vuoto; ogni campo porta una confidenza 0–1.
library;

import 'ocr_port.dart';

// -----------------------------------------------------------------------------
// Tipi in output
// -----------------------------------------------------------------------------

enum DocKind { ddt, fattura, sconosciuto }

class ParsedField<T> {
  const ParsedField({
    required this.value,
    required this.confidence,
    required this.rawText,
    this.sourceBox,
  });

  final T value;

  /// 0–1: qualità del match etichetta, validazione del valore (data reale,
  /// numero plausibile), posizione e confidenza OCR.
  final double confidence;
  final String rawText;
  final OcrBox? sourceBox;

  bool get needsReview => confidence < 0.6;
}

class ParsedLine {
  const ParsedLine({
    this.description,
    this.lot,
    this.unit,
    this.quantity,
    this.expiry,
    this.box,
  });

  final ParsedField<String>? description;
  final ParsedField<String>? lot;
  final ParsedField<String>? unit;
  final ParsedField<double>? quantity;
  final ParsedField<DateTime>? expiry;
  final OcrBox? box;

  bool get isEmpty =>
      description == null && lot == null && quantity == null && expiry == null;
}

class ParsedDocument {
  const ParsedDocument({
    required this.kind,
    required this.lines,
    this.supplierName,
    this.supplierVat,
    this.docNumber,
    this.docDate,
    this.warnings = const [],
  });

  final DocKind kind;

  final ParsedField<String>? supplierName;
  final ParsedField<String>? supplierVat;
  final ParsedField<String>? docNumber;
  final ParsedField<DateTime>? docDate;
  final List<ParsedLine> lines;

  /// Avvisi (mai silenziosi): es. scadenza precedente alla data documento.
  final List<String> warnings;
}

// -----------------------------------------------------------------------------
// Parser
// -----------------------------------------------------------------------------

class DocumentParser {
  const DocumentParser();

  /// Soglia sotto la quale la UI mostra "Controlla".
  static const double reviewThreshold = 0.6;

  ParsedDocument parse(OcrResult result) {
    final lines = result.lines;
    if (lines.isEmpty) return const ParsedDocument(kind: DocKind.sconosciuto, lines: []);

    final warnings = <String>[];
    final kind = _detectKind(lines);
    final docNumber = _findDocNumber(lines, kind);
    final docDate = _findDocDate(lines);
    final supplierVat = _findVat(lines);
    final supplierName = _findSupplierName(lines, supplierVat);
    final tableLines = _parseTable(lines);
    final freeLines = _parseFreeLines(
      lines,
      tableLines.foundHeader ? tableLines.header : null,
    );
    final allLines = [...tableLines.lines, ...freeLines];

    // Scadenza precedente alla data documento: segnalata, non nascosta.
    if (docDate != null) {
      for (final line in allLines) {
        final expiry = line.expiry;
        if (expiry != null && expiry.value.isBefore(docDate.value)) {
          warnings.add(
            'Scadenza ${_formatDate(expiry.value)} precedente alla data '
            'documento ${_formatDate(docDate.value)}: controlla.',
          );
        }
      }
    }

    return ParsedDocument(
      kind: kind,
      supplierName: supplierName,
      supplierVat: supplierVat,
      docNumber: docNumber,
      docDate: docDate,
      lines: allLines..sort((a, b) =>
          (a.box?.top ?? 0).compareTo(b.box?.top ?? 0)),
      warnings: warnings,
    );
  }

  // ---------------------------------------------------------------------------
  // Tipologia documento e campi di testata
  // ---------------------------------------------------------------------------

  DocKind _detectKind(List<OcrLine> lines) {
    final text = lines.map((l) => l.text.toLowerCase()).join(' ');
    if (_containsLabel(text, ['documento di trasporto', 'ddt'])) {
      return DocKind.ddt;
    }
    if (_containsLabel(text, ['fattura', 'fattura elettronica'])) {
      return DocKind.fattura;
    }
    return DocKind.sconosciuto;
  }

  ParsedField<String>? _findDocNumber(List<OcrLine> lines, DocKind kind) {
    final patterns = [
      RegExp(r'(?:documento di trasporto|ddt|fattura)\s*(?:n[°.]?|num\.?|numero)?\s*[:.]?\s*([A-Z0-9/\-]{2,})',
          caseSensitive: false),
    ];
    for (final line in lines) {
      for (final pattern in patterns) {
        final match = pattern.firstMatch(line.text);
        if (match != null && match.group(1) != null) {
          final raw = match.group(1)!;
          // Un "numero" di soli punti/trattini non è un numero documento.
          final cleaned = _fixAlphanumeric(raw);
          return ParsedField(
            value: cleaned,
            rawText: line.text,
            confidence: _combine(0.9, line.confidence),
            sourceBox: line.box,
          );
        }
      }
    }
    return null;
  }

  ParsedField<DateTime>? _findDocDate(List<OcrLine> lines) {
    // Cerca prima con etichetta (Data, Data documento, Del), poi la prima
    // data plausibile della parte alta del documento.
    for (final line in lines.take(_headCount(lines))) {
      final labelled = RegExp(
              r'(?:data\s*(?:documento|ddt|fattura)?|del)\s*[:.]?\s*([0-9OolISB][0-9OolISB./\-]{4,10})',
              caseSensitive: false)
          .firstMatch(line.text);
      if (labelled != null) {
        final date = parseItalianDate(labelled.group(1)!);
        if (date != null) {
          return ParsedField(
            value: date,
            rawText: labelled.group(1)!,
            confidence: _combine(0.92, line.confidence),
            sourceBox: line.box,
          );
        }
      }
    }
    for (final line in lines.take(_headCount(lines))) {
      final date = _firstDateIn(line.text);
      if (date != null) {
        return ParsedField(
          value: date.value,
          rawText: date.rawText,
          confidence: _combine(0.65, line.confidence),
          sourceBox: line.box,
        );
      }
    }
    return null;
  }

  int _headCount(List<OcrLine> lines) {
    if (lines.isEmpty) return 0;
    if (lines.length <= 6) return lines.length;
    final proportional = (lines.length * 0.4).ceil();
    return proportional < 6 ? 6 : proportional;
  }

  ParsedField<String>? _findVat(List<OcrLine> lines) {
    for (final line in lines) {
      final match = RegExp(r'(?:p\.?\s*iva|partita\s*iva|vat)\s*[:.]?\s*([0-9OolISB]{11})',
              caseSensitive: false)
          .firstMatch(line.text);
      if (match != null) {
        final digits = _fixDigits(match.group(1)!);
        return ParsedField(
          value: digits,
          rawText: match.group(1)!,
          confidence: _combine(
            isValidItalianVat(digits) ? 0.95 : 0.5,
            line.confidence,
          ),
          sourceBox: line.box,
        );
      }
    }
    // Partita IVA "nuda" di 11 cifre nella testata.
    for (final line in lines.take(6)) {
      final match = RegExp(r'\b([0-9OolISB]{11})\b').firstMatch(line.text);
      if (match != null) {
        final digits = _fixDigits(match.group(1)!);
        if (isValidItalianVat(digits)) {
          return ParsedField(
            value: digits,
            rawText: match.group(1)!,
            confidence: _combine(0.7, line.confidence),
            sourceBox: line.box,
          );
        }
      }
    }
    return null;
  }

  /// Intestazione in alto, più grande/più alta: le prime righe con altezza
  /// del riquadro sopra la mediana, escluse etichette P.IVA/date/numerazione.
  ParsedField<String>? _findSupplierName(
    List<OcrLine> lines,
    ParsedField<String>? vat,
  ) {
    if (lines.isEmpty) return null;
    final heights = lines.map((l) => l.box.height).toList()..sort();
    final median = heights[heights.length ~/ 2];
    final skip = RegExp(
        r'p\.?\s*iva|partita\s*iva|ddt|fattura|documento di trasporto|'
        r'scad|lotto|data|^del\b|tel\.?|e-?mail|www\.|@',
        caseSensitive: false);
    final head = lines.take(_headCount(lines)).toList()
      ..sort((a, b) => b.box.height.compareTo(a.box.height));
    for (final line in head) {
      final text = line.text.trim();
      if (text.length < 3) continue;
      if (skip.hasMatch(text)) continue;
      // Non la riga che contiene la P.IVA trovata.
      if (vat?.sourceBox == line.box) continue;
      final heightBonus =
          line.box.height > median * 1.2 ? 0.15 : (line.box.height > median ? 0.05 : 0.0);
      return ParsedField(
        value: _cleanCompanyName(text),
        rawText: text,
        confidence: _combine((0.55 + heightBonus).clamp(0.0, 0.9),
            line.confidence),
        sourceBox: line.box,
      );
    }
    return null;
  }

  String _cleanCompanyName(String text) {
    final noise = RegExp(
        r'\s*(s\.?r\.?l\.?|s\.?r\.?l\.?s\.?|s\.?p\.?a\.?|s\.?n\.?c\.?|s\.?a\.?s\.?|di\s+\w+\s+\w+)$',
        caseSensitive: false);
    return text.replaceAll(RegExp(r'\s{2,}'), ' ').trim().replaceFirstMapped(noise, (m) => m.group(1) ?? '');
  }

  // ---------------------------------------------------------------------------
  // Tabelle: colonne dalle posizioni delle intestazioni
  // ---------------------------------------------------------------------------

  ({List<ParsedLine> lines, bool foundHeader, OcrLine? header})
      _parseTable(List<OcrLine> lines) {
    OcrLine? header;
    for (final line in lines) {
      final lower = line.text.toLowerCase();
      // Una riga con una data o un valore numerico non è una testata di
      // tabella: sono le etichette di riga (es. "Lotto X Scadenza Y").
      if (_firstDateIn(line.text) != null) continue;
      final hits = [
        _containsLabel(lower, ['descrizione', 'articolo', 'prodotto']),
        _containsLabel(lower, ['lotto', 'lotto n', 'batch']),
        _containsLabel(lower, ['scad', 'scadenza', 'tmc', 'da consumar']),
        _containsLabel(lower, ['q.t', 'qta', 'quantit']),
        _containsLabel(lower, ['um', 'u.m']),
      ].where((hit) => hit).length;
      if (hits >= 2) {
        header = line;
        break;
      }
    }
    if (header == null) {
      return (lines: const [], foundHeader: false, header: null);
    }

    final rows = <ParsedLine>[];

    for (final line in lines) {
      if (identical(line, header)) continue;
      if (line.box.top < header.box.bottom - 2) continue;
      // Solo la pagina della testata: righe oltre ~30 altezze di riga
      // appartengono ad altro blocco (piè di pagina, totali).
      if (line.box.top > header.box.bottom + header.box.height * 30) continue;

      // Estrazione per pattern dalla riga intera: i box ML Kit sono per
      // riga (non per parola), l'assegnazione per posizione esatta non è
      // affidabile; data/lotto/quantità/unità si riconoscono per forma.
      // Ordine: prima la data, poi il lotto (escludendo la data), poi la
      // quantità (escludendo data e lotto, preferendo il numero seguito
      // dall'unità di misura).
      final text = line.text.trim();
      if (text.isEmpty) continue;

      final expiry = _parseDateCell(text, line);
      final lot = _parseLotCell(text, line, exclude: [expiry?.rawText]);

      var qtySource = text;
      for (final consumed in [expiry?.rawText, lot?.rawText]) {
        if (consumed != null && consumed.isNotEmpty) {
          qtySource = qtySource.replaceFirst(RegExp.escape(consumed), ' ');
        }
      }
      final quantity = _parseQtyCell(qtySource, line);
      final unit = _parseUnitCell(text, line);
      final description = _descriptionFrom(text, remove: [
        expiry?.rawText,
        lot?.rawText,
        quantity?.rawText,
        unit?.rawText,
      ]);

      final rowHasData = lot != null || expiry != null || quantity != null;
      final descriptionOnly = description.isNotEmpty && !rowHasData;
      final dataOnly = description.isEmpty && rowHasData;
      final previous = rows.isEmpty ? null : rows.last;
      final previousIsBareDescription = previous != null &&
          previous.lot == null &&
          previous.expiry == null &&
          previous.quantity == null;

      if (descriptionOnly && previous != null && previousIsBareDescription) {
        // Descrizione su più righe: accumula sul prodotto precedente.
        rows[rows.length - 1] = ParsedLine(
          description: ParsedField(
            value: '${previous.description!.value} $description',
            rawText: '${previous.description!.rawText} $description',
            confidence: _combine(previous.description!.confidence * 0.9,
                line.confidence),
            sourceBox: previous.description!.sourceBox ?? line.box,
          ),
          box: previous.box ?? line.box,
        );
        continue;
      }
      if (dataOnly && previous != null && previousIsBareDescription) {
        // Lotto/scadenza/quantità scritti sotto la descrizione: completano
        // il prodotto precedente.
        rows[rows.length - 1] = ParsedLine(
          description: previous.description,
          lot: lot,
          unit: unit,
          quantity: quantity,
          expiry: expiry,
          box: previous.box ?? line.box,
        );
        continue;
      }
      if (description.isEmpty && !rowHasData) continue;

      rows.add(ParsedLine(
        description: description.isEmpty
            ? null
            : ParsedField(
                value: description,
                rawText: description,
                confidence: _combine(0.75, line.confidence),
                sourceBox: line.box,
              ),
        lot: lot,
        unit: unit,
        quantity: quantity,
        expiry: expiry,
        box: line.box,
      ));
    }
    return (
      lines: rows.where((row) => !row.isEmpty).toList(),
      foundHeader: true,
      header: header,
    );
  }

  // ---------------------------------------------------------------------------
  // Righe fuori tabella (lotto/scadenza scritti nel testo)
  // ---------------------------------------------------------------------------

  /// Righe fuori tabella con lotto/scadenza etichettati. Quando c'è una
  /// tabella, considera solo le righe SOPRA la testata (dalla testata in
  /// giù le righe sono già state gestite: niente duplicati).
  List<ParsedLine> _parseFreeLines(List<OcrLine> lines, OcrLine? header) {
    final result = <ParsedLine>[];
    for (final line in lines) {
      if (header != null && line.box.top >= header.box.top) continue;
      final text = line.text;
      final lot = _lotFromText(text);
      final date = _firstDateIn(text);
      final qty = _quantityFromText(text);
      final unitToken = _unitFromText(text);
      final isScad = _containsLabel(
          text.toLowerCase(), ['scad', 'scadenza', 'tmc', 'consumar']);
      final isLotLine = lot != null &&
          _containsLabel(text.toLowerCase(), ['lotto', 'lot', 'batch', 'l.']);
      if (!isLotLine && !isScad) continue;
      result.add(ParsedLine(
        lot: lot == null
            ? null
            : ParsedField(
                value: lot.value,
                rawText: text,
                confidence: _combine(0.7, line.confidence),
                sourceBox: line.box),
        unit: unitToken == null
            ? null
            : ParsedField(
                value: unitToken,
                rawText: unitToken,
                confidence: _combine(0.6, line.confidence),
                sourceBox: line.box),
        expiry: (date == null || !isScad)
            ? null
            : ParsedField(
                value: date.value,
                rawText: date.rawText,
                confidence: _combine(0.75, line.confidence),
                sourceBox: line.box),
        quantity: qty == null
            ? null
            : ParsedField(
                value: qty.value,
                rawText: qty.rawText,
                confidence: _combine(0.5, line.confidence),
                sourceBox: line.box),
        box: line.box,
      ));
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Celle: estrazione per forma (data, lotto, quantità, unità) e descrizione
  // come testo residuo
  // ---------------------------------------------------------------------------

  ParsedField<String>? _parseLotCell(
    String text,
    OcrLine line, {
    List<String?> exclude = const [],
  }) {
    // 1) Lotto con etichetta nella riga.
    final labelled = _lotFromText(text);
    if (labelled != null) {
      return ParsedField(
        value: labelled.value,
        rawText: labelled.token,
        confidence: _combine(0.85, line.confidence),
        sourceBox: line.box,
      );
    }
    // 2) Token di solo codice (tipico lotto in colonna): prefisso letterale
    // breve + almeno 3 cifre, non data e non quantità.
    final excluded = {for (final e in exclude) if (e != null) e};
    for (final token in text.split(RegExp(r'\s+'))) {
      if (token.isEmpty || excluded.contains(token)) continue;
      final clean = _fixAlphanumeric(token);
      if (RegExp(r'^[A-Za-z]{0,3}\d{3,}[A-Za-z0-9]{0,4}$').hasMatch(clean) &&
          !RegExp(r'^\d{2}[/.\-]').hasMatch(clean)) {
        return ParsedField(
          value: clean,
          rawText: clean,
          confidence: _combine(0.6, line.confidence),
          sourceBox: line.box,
        );
      }
    }
    return null;
  }

  ParsedField<DateTime>? _parseDateCell(String cell, OcrLine line) {
    final date = _firstDateIn(cell);
    if (date == null) return null;
    return ParsedField(
      value: date.value,
      rawText: date.rawText,
      confidence: _combine(0.85, line.confidence),
      sourceBox: line.box,
    );
  }

  ParsedField<double>? _parseQtyCell(String cell, OcrLine line) {
    final qty = _quantityFromText(cell);
    if (qty == null) return null;
    return ParsedField(
      value: qty.value,
      rawText: qty.rawText,
      confidence: _combine(0.8, line.confidence),
      sourceBox: line.box,
    );
  }

  ParsedField<String>? _parseUnitCell(String text, OcrLine line) {
    final token = _unitFromText(text);
    if (token == null) return null;
    return ParsedField(
      value: token,
      rawText: token,
      confidence: _combine(0.7, line.confidence),
      sourceBox: line.box,
    );
  }

  /// Descrizione: testo della riga senza i token già assegnati ad altri
  /// campi (data, quantità, lotto, unità) e senza etichette residue.
  String _descriptionFrom(String text, {List<String?> remove = const []}) {
    var result = text;
    for (final token in remove) {
      if (token == null || token.isEmpty) continue;
      result = result.replaceFirst(RegExp.escape(token), ' ');
    }
    result = result
        .replaceAll(
            RegExp(
              r'lotto\s*(n[°.]?)?|(^|\s)l\.|lot\.?|batch|scad\.?|scadenza|'
              r'tmc|da consumar\w* entro|q\.?t[àa]?\.?|quantit[àa]|(^|\s)um(\s|$)',
              caseSensitive: false,
            ),
            ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
    return result;
  }

  // ---------------------------------------------------------------------------
  // Primitive di riconoscimento (pubbliche per i test e il riuso)
  // ---------------------------------------------------------------------------

  /// Lotto da testo con etichetta: il valore catturato deve contenere
  /// almeno una cifra (evita "Lotto Scad." letti come codice).
  static ({String value, String token})? _lotFromText(String text) {
    final labelled = RegExp(
            r'(?:lotto\s*(?:n[°.]?)?|lot\.?|batch(?:\s*n[°.]?)?|l\.)\s*[:.]?\s*([A-Za-z0-9][A-Za-z0-9\-/.]{2,})',
            caseSensitive: false)
        .firstMatch(text);
    if (labelled != null) {
      final captured = labelled.group(1)!;
      if (captured.contains(RegExp(r'\d'))) {
        return (value: _fixAlphanumeric(captured), token: captured);
      }
    }
    return null;
  }

  static ({DateTime value, String rawText})? _firstDateIn(String text) {
    final pattern = RegExp(
        r'\b([0-9OolISB]{1,2}[/.\-][0-9OolISB]{1,2}[/.\-][0-9OolISB]{2,4})\b|'
        r'\b([0-9OolISB]{1,2}[/.\-][0-9OolISB]{2,4})\b');
    for (final match in pattern.allMatches(text)) {
      final raw = (match.group(1) ?? match.group(2))!;
      final date = parseItalianDate(raw);
      if (date != null) return (value: date, rawText: raw);
    }
    return null;
  }

  static ({double value, String rawText})? _quantityFromText(String text) {
    // Le sequenze simili a data NON sono quantità: cercale e toglierle
    // dalla ricerca (restano nel testo per la descrizione).
    final withoutDates = text.replaceAll(
        RegExp(
          r'[0-9OolISB]{1,2}[/.\-][0-9OolISB]{1,2}[/.\-][0-9OolISB]{2,4}'
          r'|[0-9OolISB]{1,2}[/.\-][0-9OolISB]{2,4}',
        ),
        ' ');
    final pattern = RegExp(
        r'(?<![0-9A-Za-z])([0-9OolISB]{1,7}(?:[.,][0-9OolISB]{1,3})?)'
        r'(?![0-9A-Za-z/.\-])');
    final unitAfter = RegExp(
        r'^\s*(kg|p[zZ]|nr|n[°.]|cf|colli|lt|gr|pezzi|buste|casse)\b',
        caseSensitive: false);

    // Preferisci il numero seguito dall'unità di misura (la quantità sta
    // in fondo alla riga), altrimenti il primo plausibile.
    RegExpMatch? fallback;
    for (final match in pattern.allMatches(withoutDates)) {
      final value = parseItalianNumber(match.group(1)!);
      if (value == null || value <= 0 || value > 100000) continue;
      final after = withoutDates.substring(match.end);
      if (unitAfter.hasMatch(after)) {
        return (value: value, rawText: match.group(1)!);
      }
      fallback ??= match;
    }
    if (fallback == null) return null;
    final value = parseItalianNumber(fallback.group(1)!);
    if (value == null || value <= 0 || value > 100000) return null;
    return (value: value, rawText: fallback.group(1)!);
  }

  static String? _unitFromText(String text) {
    final match = RegExp(
            r'\b(kg|p[zZ]|nr|n[°.]|cf|colli|lt|gr|pezzi|buste|casse)\b',
            caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    return match.group(1)!.toUpperCase().replaceAll('°', '').replaceAll('.', '');
  }
}

// -----------------------------------------------------------------------------
// Primitive pubbliche (usate anche dai test e dal flusso di scansione)
// -----------------------------------------------------------------------------

/// Date italiane: `gg/mm/aaaa`, `gg-mm-aa`, `gg.mm.aaaa`, `mm/aaaa`.
/// Scarta date impossibili; corregge le confusioni OCR SOLO nel contesto
/// numerico. `mm/aaaa` (solo mese) → primo giorno del mese.
DateTime? parseItalianDate(String raw) {
  var text = _fixDigits(raw);
  final full = RegExp(r'^(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})$')
      .firstMatch(text);
  if (full != null) {
    var day = int.parse(full.group(1)!);
    var month = int.parse(full.group(2)!);
    var year = int.parse(full.group(3)!);
    if (year < 100) year += 2000;
    if (day >= 1 && day <= 31 && month >= 1 && month <= 12) {
      // gg/mm invertiti con mm/gg: se il giorno non è valido ma il mese sì,
      // prova lo scambio SOLO quando è inequivocabile.
      if (day > 12 && month > 12) return null;
      if (day > 12 && month <= 12) {
        final date = DateTime(year, month, day);
        return _valid(date, year) ? date : null;
      }
      final date = DateTime(year, month, day);
      return _valid(date, year) ? date : null;
    }
    return null;
  }
  final monthYear = RegExp(r'^(\d{1,2})[/.\-](\d{2,4})$').firstMatch(text);
  if (monthYear != null) {
    final month = int.parse(monthYear.group(1)!);
    var year = int.parse(monthYear.group(2)!);
    if (year < 100) year += 2000;
    if (month >= 1 && month <= 12) {
      final date = DateTime(year, month, 1);
      return _valid(date, year) ? date : null;
    }
  }
  return null;
}

bool _valid(DateTime date, int year) =>
    year >= 2000 && year <= 2100 && !date.isBefore(DateTime(2000, 1, 1));

/// Numeri italiani: virgola decimale, punto migliaia.
double? parseItalianNumber(String raw) {
  var text = _fixDigits(raw).trim();
  if (text.contains(',') && text.contains('.')) {
    // Formato 1.234,56: il punto sono migliaia.
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (text.contains(',')) {
    text = text.replaceAll(',', '.');
  } else if (text.contains('.')) {
    // "1.234" o "1.5": migliaia solo con 3 cifre decimali.
    final parts = text.split('.');
    if (parts.length == 2 && parts[1].length == 3) {
      text = text.replaceAll('.', '');
    }
  }
  return double.tryParse(text);
}

/// Correzioni OCR di cifre SOLO in contesto numerico (O↔0, l/I↔1, S↔5,
/// B↔8).
String _fixDigits(String raw) => raw
    .replaceAll('O', '0')
    .replaceAll('o', '0')
    .replaceAll('l', '1')
    .replaceAll('I', '1')
    .replaceAll('S', '5')
    .replaceAll('B', '8');

/// Correzione di caratteri ambigui in codici alfanumerici (lotto, numero
/// documento): qui le lettere restano lettere.
String _fixAlphanumeric(String raw) =>
    raw.trim().replaceAll(RegExp(r'^[°.:;\-]+|[°.:;\-]+$'), '');

/// Controllo formale della partita IVA italiana (11 cifre, checksum
/// Luhn-like).
bool isValidItalianVat(String vat) {
  if (vat.length != 11) return false;
  if (!RegExp(r'^\d{11}$').hasMatch(vat)) return false;
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final digit = vat.codeUnitAt(i) - 0x30;
    if (i.isEven) {
      sum += digit;
    } else {
      final doubled = digit * 2;
      sum += doubled > 9 ? doubled - 9 : doubled;
    }
  }
  final check = (10 - sum % 10) % 10;
  return check == vat.codeUnitAt(10) - 0x30;
}

bool _containsLabel(String text, List<String> labels) {
  final clean = text.toLowerCase().replaceAll(RegExp('[°"\']'), '');
  return labels.any((label) => clean.contains(label));
}

double _combine(double base, double? ocrConfidence) {
  if (ocrConfidence == null) return base.clamp(0.0, 1.0);
  return (base * 0.75 + ocrConfidence * 0.25).clamp(0.0, 1.0);
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

// -----------------------------------------------------------------------------
// GS1 (Prompt 8, A4): etichette con codice GS1-128/DataMatrix
// -----------------------------------------------------------------------------

class Gs1Data {
  const Gs1Data({
    this.gtin,
    this.lot,
    this.expiry,
    this.count,
    this.weightKg,
  });

  /// (01) GTIN-14.
  final String? gtin;

  /// (10) lotto.
  final String? lot;

  /// (17) scadenza AAMMGG (giorno 00 = fine mese).
  final DateTime? expiry;

  /// (37) numero pezzi.
  final int? count;

  /// (310x) peso in kg con x decimali.
  final double? weightKg;

  bool get isEmpty =>
      gtin == null && lot == null && expiry == null && count == null && weightKg == null;
}

/// Estrae gli identificativi applicativi GS1 da un codice GS1-128 o
/// DataMatrix. Un EAN-13 semplice dà solo il prodotto (nessun campo GS1).
Gs1Data? parseGs1(String code) {
  final trimmed = code.trim();
  if (trimmed.isEmpty) return null;

  // EAN-13 nudo: nessun identificatore applicativo.
  if (RegExp(r'^\d{13}$').hasMatch(trimmed)) return null;

  final withParens = trimmed.contains('(01)') ||
      trimmed.contains('(10)') ||
      trimmed.contains('(17)');
  if (!withParens) {
    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^(01|10|17|37|310)').hasMatch(digitsOnly)) return null;
  }

  String? gtin;
  String? lot;
  DateTime? expiry;
  int? count;
  double? weightKg;

  if (withParens) {
    final aiPattern = RegExp(r'\((\d{2,4})\)');
    final matches = aiPattern.allMatches(trimmed).toList();
    for (var i = 0; i < matches.length; i++) {
      final ai = matches[i].group(1)!;
      final valueStart = matches[i].end;
      final valueEnd =
          i + 1 < matches.length ? matches[i + 1].start : trimmed.length;
      final value = trimmed.substring(valueStart, valueEnd).trim();
      switch (ai) {
        case '01':
          gtin = _digits(value, 14);
        case '10':
          lot = value.isEmpty ? null : value;
        case '17':
          expiry = _gs1Date(value);
        case '37':
          count = int.tryParse(value);
      }
      if (ai.startsWith('310') && ai.length == 4) {
        weightKg = _gs1Weight(value, ai[3]);
      }
    }
  } else {
    // Formato FNC1 senza parentesi: AI fissi noti.
    var rest = trimmed;
    while (rest.isNotEmpty) {
      if (rest.startsWith('01') && rest.length >= 16) {
        gtin = rest.substring(2, 16);
        rest = rest.substring(16);
      } else if (rest.startsWith('17') && rest.length >= 8) {
        expiry = _gs1Date(rest.substring(2, 8));
        rest = rest.substring(8);
      } else if (rest.startsWith('10')) {
        final groupSeparator = RegExp(r'[\x1D\u001d]');
        final end = groupSeparator.firstMatch(rest)?.start ?? rest.length;
        lot = rest.substring(2, end);
        rest = rest.substring(end);
        break;
      } else if (rest.startsWith('310') && rest.length >= 10) {
        weightKg = _gs1Weight(rest.substring(4, 10), rest[3]);
        rest = rest.substring(10);
      } else {
        break;
      }
    }
  }

  final data = Gs1Data(
      gtin: gtin, lot: lot, expiry: expiry, count: count, weightKg: weightKg);
  return data.isEmpty ? null : data;
}

DateTime? _gs1Date(String aammgg) {
  final digits = _digits(aammgg, 6);
  if (digits.length != 6) return null;
  final year = 2000 + int.parse(digits.substring(0, 2));
  final month = int.parse(digits.substring(2, 4));
  final dayRaw = digits.substring(4, 6);
  if (month < 1 || month > 12) return null;
  if (dayRaw == '00') {
    // Fine mese.
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, lastDay);
  }
  final day = int.parse(dayRaw);
  if (day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  return date.month == month ? date : null;
}

String _digits(String value, int max) {
  final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
  return digitsOnly.length <= max ? digitsOnly : digitsOnly.substring(0, max);
}

/// (310x) peso in kg: valore a 6 cifre con x decimali.
double? _gs1Weight(String value, String decimalChar) {
  final decimals = int.tryParse(decimalChar) ?? 0;
  final raw = _digits(value, 6);
  final asInt = int.tryParse(raw);
  if (asInt == null) return null;
  var divisor = 1;
  for (var i = 0; i < decimals.clamp(0, 5); i++) {
    divisor *= 10;
  }
  return asInt / divisor;
}
