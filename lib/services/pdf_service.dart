import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageByteFormat, instantiateImageCodec;

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/constants/haccp_rules.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import 'license_service.dart';

/// Generazione dei documenti PDF (dossier, registri, etichette).
///
/// Il font Poppins viene incorporato dal bundle: caratteri accentati,
/// simboli (\u00B0C, \u2013, \u2022) e grassi sono resi correttamente.
class PdfService {
  PdfService({required this.repository, this.license});

  final HaccpRepository repository;

  /// Facoltativo: il gating dell'export avviene nelle schermate.
  final LicenseService? license;

  pw.Font? _regular;
  pw.Font? _bold;

  Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    final regularData = await rootBundle.load('assets/fonts/Poppins-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Poppins-Bold.ttf');
    _regular = pw.Font.ttf(regularData);
    _bold = pw.Font.ttf(boldData);
  }

  pw.ThemeData get _theme => pw.ThemeData.withFont(
        base: _regular!,
        bold: _bold!,
      );

  // ---------------------------------------------------------------------------
  // Struttura comune
  // ---------------------------------------------------------------------------

  static const _ink = PdfColor.fromInt(0xFF10201F);
  static const _muted = PdfColor.fromInt(0xFF3F4D4B);
  static const _brand = PdfColor.fromInt(0xFF0B6B66);
  static const _stripe = PdfColor.fromInt(0xFFF1F5F4);
  static const _border = PdfColor.fromInt(0xFFC3D1CE);

  pw.Widget _header(
    CompanyProfile company,
    String title,
    String period, [
    Uint8List? logoBytes,
  ]) {
    return pw.Container(
      padding: pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _border, width: 1)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (logoBytes != null) ...[
            pw.Image(
              pw.MemoryImage(logoBytes),
              width: 26,
              height: 26,
              fit: pw.BoxFit.contain,
            ),
            pw.SizedBox(width: 8),
          ],
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  company.name,
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
                pw.Text(
                  company.address.isEmpty ? 'HACCPass' : company.address,
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                  color: _brand,
                ),
              ),
              pw.Text(
                period,
                style: pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context context, DateTime generatedAt) {
    return pw.Container(
      padding: pw.EdgeInsets.only(top: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _border, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'Generato il ${_fmt(generatedAt)} \u2022 HACCPass',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.Text(
            'Pagina ${context.pageNumber} di ${context.pagesCount}',
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  static String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  pw.Document _doc({
    required CompanyProfile company,
    required String title,
    required String period,
    required List<pw.Widget> children,
    pw.PageOrientation orientation = pw.PageOrientation.portrait,
    PdfPageFormat format = PdfPageFormat.a4,
    bool withFooter = true,
    Uint8List? logoBytes,
  }) {
    final doc = pw.Document(theme: _theme);
    final generatedAt = DateTime.now();
    doc.addPage(
      pw.MultiPage(
        pageFormat: format,
        orientation: orientation,
        margin: pw.EdgeInsets.fromLTRB(36, 32, 36, 30),
        header: (context) => _header(company, title, period, logoBytes),
        footer: withFooter
            ? (context) => _footer(context, generatedAt)
            : null,
        build: (context) => children,
      ),
    );
    return doc;
  }

  pw.Widget _sectionTitle(String text) => pw.Padding(
        padding: pw.EdgeInsets.only(top: 14, bottom: 6),
        child: pw.Text(
          text.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: _brand,
          ),
        ),
      );

  pw.Widget _emptyNote() => pw.Padding(
        padding: pw.EdgeInsets.symmetric(vertical: 6),
        child: pw.Text(
          'Nessuna registrazione nel periodo.',
          style: pw.TextStyle(fontSize: 9.5, color: _muted),
        ),
      );

  pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required List<double> columnWidths,
    double fontSize = 9,
  }) {
    final widths = <int, pw.TableColumnWidth>{
      for (var i = 0; i < columnWidths.length; i++)
        i: pw.FlexColumnWidth(columnWidths[i]),
    };
    return pw.Table(
      border: pw.TableBorder.all(color: _border, width: 0.6),
      columnWidths: widths,
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: _stripe),
          children: [
            for (final h in headers)
              pw.Padding(
                padding:
                    pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: fontSize,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? const PdfColor.fromInt(0xFFF8FBFA) : null,
            ),
            children: [
              for (final cell in rows[i])
                pw.Padding(
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3.5,
                  ),
                  child: pw.Text(
                    cell,
                    style: pw.TextStyle(fontSize: fontSize, color: _ink),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _kv(String label, String value) => pw.Padding(
        padding: pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 150,
              child: pw.Text(
                '$label:',
                style: pw.TextStyle(color: _muted, fontSize: 9.5),
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                value.isEmpty ? '\u2014' : value,
                style: pw.TextStyle(
                  fontSize: 9.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );

  pw.Widget _signatureBlock(String label) => pw.Padding(
        padding: pw.EdgeInsets.only(top: 28),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    height: 42,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _ink, width: 0.8),
                      ),
                    ),
                  ),
                  pw.Text(
                    label,
                    style: pw.TextStyle(fontSize: 8.5, color: _muted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 24),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    height: 42,
                    decoration: pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(color: _ink, width: 0.8),
                      ),
                    ),
                  ),
                  pw.Text(
                    'Data',
                    style: pw.TextStyle(fontSize: 8.5, color: _muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ---------------------------------------------------------------------------
  // Documenti pubblici
  // ---------------------------------------------------------------------------

  Future<Uint8List> buildDossier(
    DateTime from,
    DateTime to, {
    bool includePhotos = true,
  }) async {
    await _loadFonts();
    final company = await repository.getCompany();
    final period = '${_fmtDate(from)} \u2013 ${_fmtDate(to)}';
    final children = <pw.Widget>[];

    // Copertina.
    children.addAll([
      pw.SizedBox(height: 90),
      pw.Center(
        child: pw.Text(
          'DOSSIER HACCP',
          style: pw.TextStyle(
            fontSize: 30,
            fontWeight: pw.FontWeight.bold,
            color: _brand,
          ),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'Registri di autocontrollo \u2013 Reg. CE 852/2004',
          style: pw.TextStyle(fontSize: 12, color: _muted),
        ),
      ),
      pw.SizedBox(height: 40),
      _kv('Azienda', company.name),
      if (company.address.isNotEmpty)
        _kv('Indirizzo', '${company.address} ${company.city}'),
      if (company.vat.isNotEmpty) _kv('P.IVA', company.vat),
      if (company.healthNotification.isNotEmpty)
        _kv('Notifica sanitaria', company.healthNotification),
      _kv('Responsabile HACCP', company.haccpManager),
      if (company.haccpSubstitute.isNotEmpty)
        _kv('Sostituto responsabile', company.haccpSubstitute),
      _kv('Periodo', period),
      _kv('Generato il', _fmt(DateTime.now())),
      pw.SizedBox(height: 30),
      pw.Text(
        'I valori di temperatura riportati sono valori di riferimento: '
        'l\u2019operatore pu\u00F2 adattarli alla propria attivit\u00E0. La '
        'responsabilit\u00E0 dell\u2019autocontrollo resta dell\u2019operatore.',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
          ]);

    // Riepilogo indicatori.
    final temps = await repository.getTemperatureLogs(from: from, to: to);
    final thermo = await repository.getThermometerChecks(from: from, to: to);
    final cleaningLogs =
        await repository.getCleaningLogs(from: from, to: to);
    final receipts = await repository.getReceipts(from: from, to: to);
    final lots = await repository.getLots(from: from, to: to);
    final ncs = await repository.getNonConformities(from: from, to: to);
    final waste = await repository.getWasteLogs(from: from, to: to);
    final pests = await repository.getPestLogs(from: from, to: to);
    final structures =
        await repository.getStructureChecks(from: from, to: to);

    final compliantTemps = temps.where((t) => t.compliant).length;
    final openNc = ncs.where((n) => n.isOpen).length;

    children.addAll([
      _sectionTitle('Riepilogo del periodo'),
      _kv('Letture temperatura', '${temps.length}'),
      _kv('Letture conformi',
          temps.isEmpty ? '100%' : '${(compliantTemps / temps.length * 100).toStringAsFixed(0)}% ($compliantTemps su ${temps.length})'),
      _kv('Esecuzioni pulizie', '${cleaningLogs.length}'),
      _kv('Merce in arrivo', '${receipts.length}'),
      _kv('Lotti prodotti', '${lots.length}'),
      _kv('Non conformit\u00E0', '${ncs.length} (aperte: $openNc, chiuse: ${ncs.length - openNc})'),
      _kv('Eliminazioni prodotti', '${waste.length}'),
      _kv('Controlli infestanti', '${pests.length}'),
      _kv('Verifiche strutture', '${structures.length}'),
      _kv('Verifiche termometri', '${thermo.length}'),
    ]);
    children.addAll(await _temperatureSection(from, to));
    children.addAll(await _thermometerSection(from, to));
    children.addAll(await _cleaningSection(from, to));
    children.addAll(await _receiptsSection(from, to));
    children.addAll(await _lotsSection(from, to));
    children.addAll(await _ncSection(from, to));
    children.addAll(await _wasteSection(from, to));
    children.addAll(await _pestSection(from, to));
    children.addAll(await _structureSection(from, to));
    children.addAll(await _staffSection());
    children.addAll(await _suppliersSection());

    // Registri dei moduli MGSA-0415.
    children.addAll(await _cookingSection(from, to));
    children.addAll(await _blastChillSection(from, to));
    children.addAll(await _transportSection(from, to));
    children.addAll(await _samplesSection());
    children.addAll(await _waterSection(from, to));
    children.addAll(await _recallSection());
    children.addAll(await _cultureSection(from, to));
    children.addAll(await _crossContaminationSection(from, to));
    children.addAll(await _donationsSection(from, to));

    // Appendice fotografica: foto delle NC e dei ricevimenti respinti.
    if (includePhotos) {
      final photos =
          await repository.getDossierPhotos(receipts: receipts, ncs: ncs);
      if (photos.isNotEmpty) {
        children.add(_sectionTitle('Appendice fotografica'));
        children.add(
          pw.Wrap(
            spacing: 10,
            runSpacing: 12,
            children: [
              for (final (attachment, caption) in photos)
                _photoCard(attachment, caption),
            ],
          ),
        );
      }
    }

    children.addAll([
      _sectionTitle('Dichiarazione'),
      pw.Text(
        'Il sottoscritto responsabile HACCP dichiara che i registri allegati '
        'riflettono le attivit\u00E0 di autocontrollo svolte nel periodo '
        'indicato, ai sensi del Reg. CE 852/2004.',
      ),
      _signatureBlock('Firma del responsabile HACCP (${company.haccpManager})'),
      _disclaimer(),
    ]);

    final logo = await _loadLogo();
    return _doc(
      company: company,
      title: 'Dossier HACCP',
      period: period,
      children: children,
      logoBytes: logo,
    ).save();
  }

  pw.Widget _photoCard(Attachment attachment, String caption) {
    return pw.Container(
      width: 150,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (attachment.isPhoto && attachment.mime.startsWith('image/'))
            pw.ClipRRect(
              horizontalRadius: 6,
              verticalRadius: 6,
              child: pw.Image(
                pw.MemoryImage(File(attachment.localPath).readAsBytesSync()),
                width: 150,
                height: 100,
                fit: pw.BoxFit.cover,
              ),
            )
          else
            pw.Container(
              width: 150,
              height: 100,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _border),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Center(
                child: pw.Text(
                  attachment.fileName,
                  style: pw.TextStyle(fontSize: 8, color: _muted),
                ),
              ),
            ),
          pw.SizedBox(height: 3),
          pw.Text(
            caption,
            style: pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    );
  }

  Uint8List? _cachedDefaultLogo;

  /// Logo per l'intestazione: quello caricato dall'azienda oppure, in
  /// assenza, il logo dell'app (ridimensionato per non appesantire i PDF).
  Future<Uint8List?> _loadLogo() async {
    try {
      final logo = await repository.getCompanyLogo();
      if (logo != null) {
        final bytes = await File(logo.localPath).readAsBytes();
        return bytes.length > 64 ? bytes : null;
      }
    } catch (_) {
      // Nessun logo aziendale: fallback sotto.
    }

    if (_cachedDefaultLogo != null) return _cachedDefaultLogo;
    try {
      final raw = await rootBundle.load('assets/images/logo.png');
      final codec = await instantiateImageCodec(
        raw.buffer.asUint8List(),
        targetWidth: 256,
        targetHeight: 256,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ImageByteFormat.png);
      _cachedDefaultLogo = data?.buffer.asUint8List();
    } catch (_) {
      _cachedDefaultLogo = null;
    }
    return _cachedDefaultLogo;
  }

  // Sezioni ---------------------------------------------------------------

  Future<List<pw.Widget>> _temperatureSection(DateTime from, DateTime to) async {
    final logs = await repository.getTemperatureLogs(from: from, to: to);
    return [
      _sectionTitle('Registro temperature'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data e ora', 'Attrezzatura', 'Temp. \u00B0C', 'Esito',
            'Azioni correttive', 'Operatore',
          ],
          columnWidths: const [3, 3.5, 2, 2, 4.5, 2.5],
          rows: [
            for (final l in logs)
              [
                _fmt(l.measuredAt),
                l.equipmentName ?? '',
                l.temperature.toStringAsFixed(1),
                l.compliant ? 'Conforme' : 'Fuori limite',
                l.correctiveAction ?? l.note ?? '',
                l.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _thermometerSection(DateTime from, DateTime to) async {
    final checks = await repository.getThermometerChecks(from: from, to: to);
    return [
      _sectionTitle('Registro verifica termometri'),
      if (checks.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Attrezzatura', 'Riferimento \u00B0C', 'Strumento \u00B0C',
            'Scost.', 'Esito',
          ],
          columnWidths: const [2.6, 3.5, 2.2, 2.2, 1.8, 3],
          rows: [
            for (final c in checks)
              [
                _fmtDate(c.checkedAt),
                c.equipmentName ?? '',
                c.referenceTemp.toStringAsFixed(1),
                c.instrumentTemp.toStringAsFixed(1),
                c.deviation.toStringAsFixed(1),
                c.deviation > 3
                    ? 'Sostituire/riparare'
                    : c.deviation > 1 ? 'Oltre tolleranza' : 'In tolleranza',
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _cleaningSection(DateTime from, DateTime to) async {
    final logs = await repository.getCleaningLogs(from: from, to: to);
    return [
      _sectionTitle('Registro pulizie e sanificazione'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Data e ora', 'Area', 'Attivit\u00E0', 'Esito', 'Operatore'],
          columnWidths: const [3, 2.8, 4.4, 3, 2.6],
          rows: [
            for (final l in logs)
              [
                _fmt(l.doneAt),
                l.taskArea ?? '',
                l.taskTitle ?? '',
                l.hadProblem ? 'Problema rilevato' : 'Eseguita',
                l.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _receiptsSection(DateTime from, DateTime to) async {
    final receipts = await repository.getReceipts(from: from, to: to);
    return [
      _sectionTitle('Registro merce in arrivo'),
      if (receipts.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Fornitore', 'Prodotto', 'Temp. \u00B0C', 'Esito', 'Operatore',
          ],
          columnWidths: const [2.6, 3.2, 3.6, 2, 3.4, 2.6],
          rows: [
            for (final r in receipts)
              [
                _fmtDate(r.receivedAt),
                r.supplierName,
                r.product,
                r.temperature?.toStringAsFixed(1) ?? '\u2014',
                r.outcomeLabel,
                r.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _lotsSection(DateTime from, DateTime to) async {
    final lots = await repository.getLots(from: from, to: to);
    return [
      _sectionTitle('Registro lotti e rintracciabilit\u00E0'),
      if (lots.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Codice', 'Prodotto', 'Produzione', 'Scadenza',
            'Ingredienti (fornitore / lotto)', 'Operatore',
          ],
          columnWidths: const [2.6, 3, 2.2, 2.2, 5, 2.2],
          rows: [
            for (final l in lots)
              [
                l.code,
                l.productName,
                _fmtDate(l.producedAt),
                l.expiresAt == null ? '' : _fmtDate(l.expiresAt!),
                l.ingredients.isEmpty
                    ? ''
                    : l.ingredients
                        .map((i) =>
                            '${i.name}${i.supplierName.isEmpty ? '' : ' (${i.supplierName}${i.supplierLot.isEmpty ? '' : ' / ${i.supplierLot})'}'}')
                        .join('; '),
                l.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _ncSection(DateTime from, DateTime to) async {
    final ncs = await repository.getNonConformities(from: from, to: to);
    return [
      _sectionTitle('Registro non conformit\u00E0'),
      if (ncs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Apertura', 'Categoria', 'Problema', 'Azione correttiva',
            'Destino prodotto', 'Stato', 'Operatore',
          ],
          columnWidths: const [2.4, 2.4, 4, 4, 2.8, 1.8, 2.2],
          rows: [
            for (final n in ncs)
              [
                _fmt(n.openedAt),
                n.category,
                n.title,
                n.correctiveAction ?? '',
                n.dispositionLabel,
                n.status,
                n.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _wasteSection(DateTime from, DateTime to) async {
    final logs = await repository.getWasteLogs(from: from, to: to);
    return [
      _sectionTitle('Registro eliminazione prodotti'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Prodotto', 'Motivo', 'Quantit\u00E0', 'Lotto', 'Operatore',
          ],
          columnWidths: const [2.6, 3.4, 3, 2, 2.6, 2.6],
          rows: [
            for (final w in logs)
              [
                _fmtDate(w.disposedAt),
                w.product,
                w.reason,
                w.quantity?.toStringAsFixed(1) ?? '',
                w.lotCode ?? '',
                w.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _pestSection(DateTime from, DateTime to) async {
    final logs = await repository.getPestLogs(from: from, to: to);
    return [
      _sectionTitle('Registro monitoraggio infestanti'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Postazione', 'Tipo', 'Conteggio', 'Livello',
            'Ditta esterna', 'Operatore',
          ],
          columnWidths: const [2.4, 3.2, 2.2, 2, 2.4, 2.2, 2.2],
          rows: [
            for (final p in logs)
              [
                _fmtDate(p.checkedAt),
                p.stationLocation ?? '',
                p.stationType ?? '',
                '${p.count}',
                switch (p.level) {
                  'severe' => 'Notevole',
                  'moderate' => 'Modesto',
                  _ => 'Accettabile',
                },
                p.byCompany ? 'S\u00EC' : 'No',
                p.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _structureSection(DateTime from, DateTime to) async {
    final checks = await repository.getStructureChecks(from: from, to: to);
    return [
      _sectionTitle('Registro monitoraggio strutture'),
      if (checks.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Data', 'Area', 'Anomalie rilevate', 'Operatore'],
          columnWidths: const [2.6, 3.2, 6.6, 2.6],
          rows: [
            for (final c in checks)
              [
                _fmtDate(c.checkedAt),
                c.area,
                c.items.where((i) => !i.ok).map((i) => i.label).isEmpty
                    ? 'Nessuna'
                    : c.items
                        .where((i) => !i.ok)
                        .map((i) =>
                            i.label + (i.note.isEmpty ? '' : ' (${i.note})'))
                        .join('; '),
                c.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _staffSection() async {
    final staff = await repository.getStaff();
    return [
      _sectionTitle('Personale e formazione'),
      if (staff.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Nome', 'Mansione', 'Ruolo', 'Attestato', 'Stato'],
          columnWidths: const [3.4, 3, 2.6, 2.6, 3],
          rows: [
            for (final s in staff)
              [
                s.name,
                s.job,
                s.role,
                s.certificateAt == null ? '' : _fmtDate(s.certificateAt!),
                switch (s.certificateStatus(
                    months: await repository.getTrainingRenewalMonths())) {
                  'valid' => 'Valido',
                  'expiring' => 'In scadenza',
                  'expired' => 'Scaduto',
                  _ => 'Mancante',
                },
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _suppliersSection() async {
    final suppliers = await repository.getSuppliers();
    return [
      _sectionTitle('Registro fornitori'),
      if (suppliers.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Fornitore', 'P.IVA', 'Telefono', 'Qualificato', 'NC fornitore',
          ],
          columnWidths: const [4.4, 2.8, 2.6, 2.2, 2.6],
          rows: [
            for (final s in suppliers)
              [
                s.name,
                s.vat,
                s.phone,
                s.qualified ? 'S\u00EC' : 'No',
                '${s.ncCount}',
              ],
          ],
        ),
    ];
  }

  // Sezioni moduli MGSA-0415 -----------------------------------------------

  Future<List<pw.Widget>> _cookingSection(DateTime from, DateTime to) async {
    final logs = await repository.getCookingLogs(from: from, to: to);
    final oils = await repository.getOilValidations(from: from, to: to);
    if (logs.isEmpty && oils.isEmpty) return [_sectionTitle('Cottura e rigenerazione (PR COT)'), _emptyNote()];
    return [
      _sectionTitle('Cottura e rigenerazione (PR COT)'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data e ora', 'Tipo', 'Categoria/alimento', 'Cuore \u00B0C',
            'Esito', 'Operatore',
          ],
          columnWidths: const [2.8, 2.2, 4, 2, 2, 2.4],
          rows: [
            for (final log in logs)
              [
                _fmt(log.cookedAt),
                log.kindLabel,
                log.foodName.isEmpty ? log.category : '${log.category} (${log.foodName})',
                log.coreTemp.toStringAsFixed(1),
                log.compliant ? 'Conforme' : 'Non conforme',
                log.operatorName,
              ],
          ],
        ),
      if (oils.isNotEmpty) ...[
        _sectionTitle('Validazione olio da frittura (PR COT 02)'),
        _table(
          headers: const [
            'Data', 'Friggitrice', 'Temp. \u00B0C', 'Organolettico',
            'Olio cambiato', 'Operatore',
          ],
          columnWidths: const [2.6, 3, 2.2, 2.6, 2.4, 2.4],
          rows: [
            for (final o in oils)
              [
                _fmtDate(o.validatedAt),
                o.fryer,
                o.tempC.toStringAsFixed(0),
                o.sensoryOk ? 'Idoneo' : 'Non idoneo',
                o.oilChanged ? 'S\u00EC' : 'No',
                o.operatorName,
              ],
          ],
        ),
      ],
    ];
  }

  Future<List<pw.Widget>> _blastChillSection(DateTime from, DateTime to) async {
    final cycles =
        await repository.getBlastChillCycles(from: from, to: to);
    return [
      _sectionTitle('Abbattimento (PR ABB)'),
      if (cycles.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Inizio', 'Fine', 'Prodotto', 'Tipo', 'T fine \u00B0C', 'Esito',
          ],
          columnWidths: const [3, 3, 3.4, 2.2, 2.2, 2],
          rows: [
            for (final c in cycles)
              [
                _fmt(c.startedAt),
                c.endedAt == null ? '' : _fmt(c.endedAt!),
                c.product,
                c.kind == 'positivo' ? 'Positivo' : 'Negativo',
                c.tEnd?.toStringAsFixed(1) ?? '\u2014',
                c.compliant ? 'Conforme' : 'Anomalia',
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _transportSection(DateTime from, DateTime to) async {
    final logs = await repository.getTransportLogs(from: from, to: to);
    return [
      _sectionTitle('Mantenimento e trasporto (PR TRA / PR SOM)'),
      if (logs.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Destinazione', 'Freddi arr. \u00B0C', 'Caldi arr. \u00B0C',
            'Checklist', 'Esito',
          ],
          columnWidths: const [2.6, 3.2, 2.4, 2.4, 3.4, 2],
          rows: [
            for (final l in logs)
              [
                _fmtDate(l.doneAt),
                l.destination,
                l.tempColdArrival?.toStringAsFixed(0) ?? '\u2014',
                l.tempHotArrival?.toStringAsFixed(0) ?? '\u2014',
                '${l.vehicleClean ? 'automezzo ok' : 'automezzo NO'} / '
                    '${l.containersSanitized ? 'contenitori ok' : 'contenitori NO'}',
                l.compliant ? 'Conforme' : 'Non conforme',
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _samplesSection() async {
    final samples = await repository.getSampleMeals();
    return [
      _sectionTitle('Pasto campione (PR CAMP 01)'),
      if (samples.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Prelievo', 'Piatto', 'Grammi', 'Smaltire entro', 'Smaltito',
          ],
          columnWidths: const [3, 4, 2, 3, 3],
          rows: [
            for (final s in samples)
              [
                _fmt(s.takenAt),
                s.dish,
                s.grams.toStringAsFixed(0),
                _fmt(s.discardAfter),
                s.discardedAt == null ? '' : _fmt(s.discardedAt!),
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _waterSection(DateTime from, DateTime to) async {
    final checks = await repository.getWaterChecks(from: from, to: to);
    return [
      _sectionTitle('Acqua potabile e ghiaccio (PR APO)'),
      if (checks.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Data', 'Tipo', 'Esito', 'Nota', 'Operatore'],
          columnWidths: const [2.8, 3.6, 2.2, 3.6, 2.4],
          rows: [
            for (final c in checks)
              [
                _fmt(c.checkedAt),
                c.kindLabel,
                c.resultOk ? 'Positivo' : 'Non conforme',
                c.note ?? '',
                c.operatorName,
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _recallSection() async {
    final withdrawals = await repository.getWithdrawals();
    return [
      _sectionTitle('Ritiri e richiami (PR RIN)'),
      if (withdrawals.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Lotto', 'Destinatari', 'Azioni', 'ASL', 'Esito',
          ],
          columnWidths: const [2.6, 2.6, 3.4, 3.6, 1.8, 2],
          rows: [
            for (final w in withdrawals)
              [
                _fmt(w.startedAt),
                w.lotCode,
                w.clients,
                w.actions,
                w.aslNotified ? 'S\u00EC' : 'No',
                w.isOpen ? 'In corso' : 'Concluso',
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _cultureSection(DateTime from, DateTime to) async {
    final entries = await repository.getCultureEntries();
    return [
      _sectionTitle('Cultura della sicurezza alimentare (Reg. UE 2021/382)'),
      if (entries.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Data', 'Tipo', 'Oggetto', 'Operatore'],
          columnWidths: const [2.8, 3.2, 4.4, 2.6],
          rows: [
            for (final e in entries)
              [_fmt(e.doneAt), e.kindLabel, e.title, e.operatorName],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _crossContaminationSection(
    DateTime from,
    DateTime to,
  ) async {
    final checks =
        await repository.getCrossContaminationChecks(from: from, to: to);
    return [
      _sectionTitle('Contaminazione crociata (orientamenti 2022/C 355/01)'),
      if (checks.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Data', 'Attrezzatura', 'Residui', 'Azione'],
          columnWidths: const [2.8, 4, 2.2, 4.4],
          rows: [
            for (final c in checks)
              [
                _fmt(c.checkedAt),
                c.equipment,
                c.residueFound ? 'Trovati' : 'Nessuno',
                c.action ?? '',
              ],
          ],
        ),
    ];
  }

  Future<List<pw.Widget>> _donationsSection(DateTime from, DateTime to) async {
    final donations = await repository.getDonations(from: from, to: to);
    return [
      _sectionTitle('Ridistribuzione alimenti (Reg. UE 2021/382)'),
      if (donations.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const [
            'Data', 'Prodotto', 'Quantit\u00E0', 'Ente', 'Stato',
          ],
          columnWidths: const [2.6, 3.4, 2.2, 3, 3.4],
          rows: [
            for (final d in donations)
              [
                _fmtDate(d.donatedAt),
                d.product,
                d.quantity?.toStringAsFixed(1) ?? '',
                d.entity,
                d.stateNote ?? '',
              ],
          ],
        ),
    ];
  }

  /// Disclaimer normativo da riportare nei documenti.
  pw.Widget _disclaimer() => pw.Padding(
        padding: pw.EdgeInsets.only(top: 14),
        child: pw.Text(
          'Contenuti di supporto all\u2019autocontrollo: i limiti sono valori '
          'di riferimento e non sostituiscono la consulenza di un tecnico '
          'HACCP n\u00E9 le disposizioni della propria ASL/Regione. Ultimo '
          'aggiornamento dei contenuti: ottobre 2026.',
          style: pw.TextStyle(fontSize: 8, color: _muted),
        ),
      );

  // Singoli registri ---------------------------------------------------------

  Future<Uint8List> buildRegister(
    String registerId,
    DateTime from,
    DateTime to,
  ) async {
    await _loadFonts();
    final company = await repository.getCompany();
    final period = '${_fmtDate(from)} \u2013 ${_fmtDate(to)}';
    final sections = <pw.Widget>[];

    switch (registerId) {
      case 'temperature':
        sections.addAll(await _temperatureSection(from, to));
      case 'thermometer':
        sections.addAll(await _thermometerSection(from, to));
      case 'cleaning':
        sections.addAll(await _cleaningSection(from, to));
      case 'receipts':
        sections.addAll(await _receiptsSection(from, to));
      case 'lots':
        sections.addAll(await _lotsSection(from, to));
      case 'nc':
        sections.addAll(await _ncSection(from, to));
      case 'waste':
        sections.addAll(await _wasteSection(from, to));
      case 'pest':
        sections.addAll(await _pestSection(from, to));
      case 'structure':
        sections.addAll(await _structureSection(from, to));
      case 'staff':
        sections.addAll(await _staffSection());
      case 'suppliers':
        sections.addAll(await _suppliersSection());
    }

    final titles = {
      'temperature': 'Registro temperature',
      'thermometer': 'Verifica termometri',
      'cleaning': 'Pulizie e sanificazione',
      'receipts': 'Merce in arrivo',
      'lots': 'Lotti e rintracciabilit\u00E0',
      'nc': 'Non conformit\u00E0',
      'waste': 'Eliminazione prodotti',
      'pest': 'Monitoraggio infestanti',
      'structure': 'Monitoraggio strutture',
      'staff': 'Personale e formazione',
      'suppliers': 'Fornitori',
    };

    return _doc(
      company: company,
      title: titles[registerId] ?? 'Registro',
      period: period,
      children: sections,
    ).save();
  }

  /// Menù allergeni in formato orizzontale.
  Future<Uint8List> buildAllergenMenu() async {
    await _loadFonts();
    final company = await repository.getCompany();
    final products = await repository.getProducts();
    final lots = await repository.getLots();

    final rows = <(String, Set<String>)>[];
    for (final p in products) {
      rows.add((p.name, p.allergenCodes.toSet()));
    }
    for (final l in lots) {
      if (products.any((p) => p.name == l.productName)) continue;
      rows.add((l.productName, l.allergenCodes.toSet()));
    }

    final children = <pw.Widget>[
      _sectionTitle('Men\u00F9 allergeni'),
      pw.RichText(
        text: pw.TextSpan(
          text:
              'Tabella prodotti e allergeni ai sensi del Reg. UE 1169/2011, Allegato II.',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
      ),
      pw.SizedBox(height: 8),
      if (rows.isEmpty)
        _emptyNote()
      else
        _table(
          headers: [
            'Prodotto',
            for (var n = 1; n <= 14; n++) '$n',
          ],
          columnWidths: [6, ...List.filled(14, 0.75)],
          fontSize: 9.5,
          rows: [
            for (final (name, codes) in rows)
              [
                name,
                for (final a in allergenOrder)
                  codes.contains(a) ? '\u25CF' : '',
              ],
          ],
        ),
      pw.SizedBox(height: 10),
      pw.Text(
        'Legenda: 1 Glutine \u2022 2 Crostacei \u2022 3 Uova \u2022 4 Pesce '
        '\u2022 5 Arachidi \u2022 6 Soia \u2022 7 Latte \u2022 8 Frutta a guscio '
        '\u2022 9 Sedano \u2022 10 Senape \u2022 11 Sesamo \u2022 12 Solfiti '
        '\u2022 13 Lupini \u2022 14 Molluschi',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),
    ];

    return _doc(
      company: company,
      title: 'Men\u00F9 allergeni',
      period: 'Reg. UE 1169/2011',
      orientation: pw.PageOrientation.landscape,
      children: children,
    ).save();
  }

  static const List<String> allergenOrder = [
    'gluten', 'crustaceans', 'eggs', 'fish', 'peanuts', 'soy', 'milk', 'nuts',
    'celery', 'mustard', 'sesame', 'sulphites', 'lupins', 'molluscs',
  ];

  /// Cartello "PRODOTTO NON CONFORME" (Allegato III).
  Future<Uint8List> buildNcSign(NonConformity nc) async {
    await _loadFonts();
    final company = await repository.getCompany();

    return _doc(
      company: company,
      title: 'Cartello prodotto non conforme',
      period: 'NC #${nc.id}',
      withFooter: false,
      children: [
        pw.SizedBox(height: 40),
        pw.Center(
          child: pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 10,
            ),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.red, width: 2),
            ),
            child: pw.Text(
              'PRODOTTO NON CONFORME',
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.red,
              ),
            ),
          ),
        ),
        pw.SizedBox(height: 24),
        pw.Center(
          child: pw.Text(
            'non idoneo per essere utilizzato, venduto o somministrato,\n'
            'si conserva in attesa di smaltimento o reso al fornitore',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(fontSize: 13, color: _ink),
          ),
        ),
        pw.SizedBox(height: 30),
        _kv('Prodotto / problema', nc.title),
        _kv('Descrizione', nc.description),
        _kv('Data apertura', _fmt(nc.openedAt)),
        _kv('Categoria', nc.category),
        _kv('Destino del prodotto', nc.dispositionLabel),
        pw.SizedBox(height: 30),
        _signatureBlock('Firma operatore (${nc.operatorName})'),
      ],
    ).save();
  }

  /// Modulo NC singola (Allegato I).
  Future<Uint8List> buildNcForm(NonConformity nc) async {
    await _loadFonts();
    final company = await repository.getCompany();
    return _doc(
      company: company,
      title: 'Modulo non conformit\u00E0',
      period: 'NC #${nc.id}',
      children: [
        _sectionTitle('Non conformit\u00E0 #${nc.id}'),
        _kv('Categoria', nc.category),
        _kv('Titolo', nc.title),
        _kv('Descrizione', nc.description),
        _kv('Data e ora apertura', _fmt(nc.openedAt)),
        _kv('Operatore', nc.operatorName),
        _kv('Azione correttiva', nc.correctiveAction ?? '\u2014'),
        _kv('Destino del prodotto', nc.dispositionLabel),
        _kv('Stato', nc.status),
        if (nc.closedAt != null) _kv('Chiusa il', _fmt(nc.closedAt!)),
        _signatureBlock('Firma del responsabile'),
      ],
    ).save();
  }

  /// Etichetta lotto 62x40 mm con QR.
  Future<Uint8List> buildLotLabel(ProductionLot lot) async {
    await _loadFonts();
    final company = await repository.getCompany();
    final bold = _bold!;

    final labelFormat = PdfPageFormat(62 * PdfPageFormat.mm, 40 * PdfPageFormat.mm,
        marginAll: 2 * PdfPageFormat.mm);

    final doc = pw.Document(theme: _theme);
    doc.addPage(
      pw.Page(
        pageFormat: labelFormat,
        build: (context) {
          return pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      company.name.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                        font: bold,
                        fontSize: 7,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      lot.productName,
                      maxLines: 2,
                      style: pw.TextStyle(font: bold, fontSize: 11),
                    ),
                    pw.SizedBox(height: 1.5),
                    pw.Text(
                      'LOTTO ${lot.code}',
                      style: pw.TextStyle(font: bold, fontSize: 8.5),
                    ),
                    pw.Text(
                      'Prod.: ${_fmtDate(lot.producedAt)}'
                      '${lot.expiresAt != null ? '  Entro: ${_fmtDate(lot.expiresAt!)}' : ''}',
                      style: pw.TextStyle(fontSize: 7),
                    ),
                    if (lot.storageInfo?.isNotEmpty == true)
                      pw.Text(
                        lot.storageInfo!,
                        style: pw.TextStyle(fontSize: 6.5),
                      ),
                    if (lot.allergenCodes.isNotEmpty) ...[
                      pw.SizedBox(height: 1),
                      pw.Text(
                        'Allergeni: ${_allergenNames(lot.allergenCodes)}',
                        style: pw.TextStyle(
                          font: bold,
                          fontSize: 6.5,
                          color: PdfColors.red,
                        ),
                        maxLines: 2,
                      ),
                    ],
                  ],
                ),
              ),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: lot.code,
                width: 52,
                height: 52,
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  String _allergenNames(List<String> codes) => codes
      .map((c) => allergenByCode(c).label)
      .where((n) => n.isNotEmpty)
      .join(', ');

  /// Scheda di rintracciabilità del lotto.
  Future<Uint8List> buildTraceabilitySheet(ProductionLot lot) async {
    await _loadFonts();
    final company = await repository.getCompany();
    return _doc(
      company: company,
      title: 'Scheda rintracciabilit\u00E0',
      period: 'Lotto ${lot.code}',
      children: [
        _sectionTitle('Lotto ${lot.code}'),
        _kv('Prodotto', lot.productName),
        _kv('Produzione', _fmt(lot.producedAt)),
        _kv('Scadenza', lot.expiresAt == null ? '\u2014' : _fmtDate(lot.expiresAt!)),
        _kv('Quantit\u00E0',
            '${lot.quantity?.toStringAsFixed(1) ?? '\u2014'} ${lot.unit ?? ''}'),
        _kv('Operatore', lot.operatorName),
        if (lot.allergenCodes.isNotEmpty)
          _kv('Allergeni', lot.allergenCodes.join(', ')),
        _sectionTitle('Ingredienti (rintracciabilit\u00E0 a monte)'),
        if (lot.ingredients.isEmpty)
          _emptyNote()
        else
          _table(
            headers: const ['Ingrediente', 'Fornitore', 'Lotto fornitore'],
            columnWidths: const [4, 4, 4],
            rows: [
              for (final i in lot.ingredients)
                [i.name, i.supplierName, i.supplierLot],
            ],
          ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Rintracciabilit\u00E0 ai sensi del Reg. CE 178/2002: conservare le '
          'registrazioni per il periodo previsto.',
          style: pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ],
    ).save();
  }

  /// Piano di autocontrollo personalizzato (fine wizard): anagrafica,
  /// locali, attrezzature con limiti, piano pulizie, infestanti, fornitori,
  /// figure responsabili e riferimenti normativi.
  Future<Uint8List> buildSelfControlPlan() async {
    await _loadFonts();
    final company = await repository.getCompany();
    final equipment = await repository.getEquipment();
    final cleaning = await repository.getCleaningTasks();
    final pests = await repository.getPestStations();
    final suppliers = await repository.getSuppliers();
    final staff = await repository.getStaff();
    final products = await repository.getProducts();

    final children = <pw.Widget>[
      pw.SizedBox(height: 60),
      pw.Center(
        child: pw.Text(
          'PIANO DI AUTOCONTROLLO',
          style: pw.TextStyle(
            fontSize: 26,
            fontWeight: pw.FontWeight.bold,
            color: _brand,
          ),
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Center(
        child: pw.Text(
          'basato sui principi HACCP \u2013 Reg. CE 852/2004',
          style: pw.TextStyle(fontSize: 11, color: _muted),
        ),
      ),
      pw.SizedBox(height: 28),
      _sectionTitle('Anagrafica azienda'),
      _kv('Azienda', company.name),
      if (company.address.isNotEmpty)
        _kv('Sede', '${company.address} ${company.city}'),
      if (company.vat.isNotEmpty) _kv('P.IVA', company.vat),
      if (company.ateco.isNotEmpty) _kv('ATECO', company.ateco),
      if (company.healthNotification.isNotEmpty)
        _kv('Notifica sanitaria', company.healthNotification),
      if (company.activity.isNotEmpty) _kv('Attivit\u00E0', company.activity),
      _kv('Responsabile HACCP', company.haccpManager),
      if (company.haccpSubstitute.isNotEmpty)
        _kv('Sostituto', company.haccpSubstitute),

      _sectionTitle('Figure responsabili e personale'),
      if (staff.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Nome', 'Ruolo', 'Mansione', 'Attestato'],
          columnWidths: const [4, 3, 3, 3],
          rows: [
            for (final s in staff)
              [
                s.name,
                s.role,
                s.job,
                s.certificateAt == null
                    ? '\u2014'
                    : _fmtDate(s.certificateAt!),
              ],
          ],
        ),

      _sectionTitle('Locali e attrezzature (limiti di temperatura)'),
      _table(
        headers: const [
          'Attrezzatura', 'Tipo', 'Posizione', 'Limiti \u00B0C',
        ],
        columnWidths: const [4, 3, 3, 3],
        rows: [
          for (final e in equipment)
            [
              e.name,
              e.type,
              e.location.isEmpty ? '\u2014' : e.location,
              e.rangeLabel,
            ],
        ],
      ),
      pw.Text(
        'Limiti di riferimento adattabili alla singola attivit\u00E0: la '
        'responsabilit\u00E0 dell\u2019autocontrollo resta dell\u2019operatore.',
        style: pw.TextStyle(fontSize: 8.5, color: _muted),
      ),

      _sectionTitle('Piano di pulizia e sanificazione'),
      _table(
        headers: const ['Area', 'Attivit\u00E0', 'Frequenza', 'Prodotto'],
        columnWidths: const [3, 4, 3, 4],
        rows: [
          for (final c in cleaning)
            [c.area, c.title, c.frequency, c.productName ?? '\u2014'],
        ],
      ),

      _sectionTitle('Piano di monitoraggio infestanti'),
      _table(
        headers: const ['Postazione', 'Tipo'],
        columnWidths: const [3, 3],
        rows: [
          for (final p in pests) [p.location, p.type],
        ],
      ),

      _sectionTitle('Fornitori qualificati'),
      if (suppliers.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Fornitore', 'Prodotti', 'Qualificato'],
          columnWidths: const [4, 5, 3],
          rows: [
            for (final s in suppliers)
              [s.name, s.products.isEmpty ? '\u2014' : s.products,
               s.qualified ? 'S\u00EC' : 'No'],
          ],
        ),

      _sectionTitle('Prodotti in produzione e allergeni'),
      if (products.isEmpty)
        _emptyNote()
      else
        _table(
          headers: const ['Prodotto', 'Allergeni'],
          columnWidths: const [4, 7],
          rows: [
            for (final p in products)
              [
                p.name,
                p.allergenCodes.isEmpty
                    ? '\u2014'
                    : p.allergenCodes
                        .map((c) => allergenByCode(c).label)
                        .join(', '),
              ],
          ],
        ),

      _sectionTitle('Riferimenti'),
      pw.Text(
        'Reg. CE 852/2004 (igiene e autocontrollo), Reg. CE 178/2002 '
        '(rintracciabilit\u00E0), Reg. UE 1169/2011 (allergeni). Valori di '
        'riferimento desunti dai manuali di corretta prassi operativa: '
        'adattarli alla propria attivit\u00E0 e verificarli con il proprio '
        'consulente.',
        style: pw.TextStyle(fontSize: 9, color: _muted),
      ),
      _signatureBlock('Firma del responsabile HACCP (${company.haccpManager})'),
    ];

    final logo = await _loadLogo();
    return _doc(
      company: company,
      title: 'Piano di autocontrollo',
      period: 'Redatto il ${_fmtDate(DateTime.now())}',
      children: children,
      logoBytes: logo,
    ).save();
  }

  /// Etichetta QR per attrezzatura: scansionandola con l'app si apre la
  /// registrazione della temperatura di quell'attrezzatura.
  Future<Uint8List> buildEquipmentQrLabel(Equipment equipment) async {
    await _loadFonts();
    final company = await repository.getCompany();
    final code = 'bluehaccp://equipment/${equipment.id}';

    final pageFormat = PdfPageFormat(
      62 * PdfPageFormat.mm,
      40 * PdfPageFormat.mm,
      marginAll: 3 * PdfPageFormat.mm,
    );
    final doc = pw.Document(theme: _theme);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      company.name.toUpperCase(),
                      maxLines: 1,
                      style: pw.TextStyle(
                        font: _bold!,
                        fontSize: 7,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      equipment.name,
                      maxLines: 2,
                      style: pw.TextStyle(font: _bold!, fontSize: 10),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Scansiona per registrare la temperatura',
                      style: pw.TextStyle(fontSize: 6.5, color: _muted),
                    ),
                    pw.Text(
                      equipment.rangeLabel,
                      style: pw.TextStyle(fontSize: 7, color: _brand),
                    ),
                  ],
                ),
              ),
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: code,
                width: 58,
                height: 58,
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  /// Modulo singolo di ritiro/richiamo (PR RIN).
  Future<Uint8List> buildWithdrawalForm(Withdrawal withdrawal) async {
    await _loadFonts();
    final company = await repository.getCompany();
    return _doc(
      company: company,
      title: 'Modulo ritiro/richiamo',
      period: 'Lotto ${withdrawal.lotCode}',
      children: [
        _sectionTitle('Ritiro/richiamo lotto ${withdrawal.lotCode}'),
        _kv('Data apertura', _fmt(withdrawal.startedAt)),
        _kv('Clienti/destinatari', withdrawal.clients),
        _kv('Azioni intraprese', withdrawal.actions),
        _kv('Comunicazione ASL', withdrawal.aslNotified ? 'Effettuata' : 'Non effettuata'),
        _kv(
          'Esito',
          withdrawal.isOpen
              ? 'In corso'
              : 'Concluso${withdrawal.closedAt == null ? '' : ' il ${_fmt(withdrawal.closedAt!)}'}',
        ),
        _kv('Operatore', withdrawal.operatorName),
        _disclaimer(),
        _signatureBlock('Firma del responsabile'),
      ],
    ).save();
  }

  /// Registro scritto allergeni (Comunicazione 2022/C 355/01): piatto per
  /// piatto, consultabile al banco e stampabile.
  Future<Uint8List> buildWrittenAllergenRegister() async {
    await _loadFonts();
    final company = await repository.getCompany();
    final products = await repository.getProducts();
    final lots = await repository.getLots();

    final rows = <(String, String, List<String>)>[];
    for (final p in products) {
      rows.add((p.name, p.ingredients, p.allergenCodes));
    }
    for (final l in lots) {
      if (products.any((p) => p.name == l.productName)) continue;
      rows.add((l.productName, '', l.allergenCodes));
    }

    return _doc(
      company: company,
      title: 'Registro scritto allergeni',
      period: 'Reg. UE 1169/2011 \u2022 orientamenti 2022/C 355/01',
      children: [
        _sectionTitle('Registro scritto allergeni per piatto/prodotto'),
        pw.Text(
          'Registro consultabile al banco e stampabile, come previsto dagli '
          'orientamenti della Commissione 2022/C 355/01.',
          style: pw.TextStyle(fontSize: 9, color: _muted),
        ),
        if (rows.isEmpty)
          _emptyNote()
        else
          _table(
            headers: const [
              'Piatto/prodotto', 'Ingredienti', 'Allergeni presenti',
            ],
            columnWidths: const [3.6, 4.4, 4.4],
            rows: [
              for (final (name, ingredients, allergens) in rows)
                [
                  name,
                  ingredients,
                  allergens.isEmpty
                      ? 'Nessuno dichiarato'
                      : allergens.map((a) => allergenByCode(a).label).join(', '),
                ],
            ],
          ),
        _disclaimer(),
        _signatureBlock('Firma del responsabile'),
      ],
    ).save();
  }

  /// Prospetto riassuntivo dei moduli: frequenza e stato di compilazione.
  Future<Uint8List> buildOverviewSheet() async {
    await _loadFonts();
    final company = await repository.getCompany();
    final now = DateTime.now();
    final week = now.subtract(const Duration(days: 7));
    final year = now.subtract(const Duration(days: 365));

    final cookings = await repository.getCookingLogs(from: week);
    final blasts = await repository.getBlastChillCycles(from: week);
    final transports = await repository.getTransportLogs(from: week);
    final samples = await repository.getSampleMeals();
    final waters = await repository.getWaterChecks(from: year);
    final withdrawals = await repository.getWithdrawals();
    final culture = await repository.getCultureEntries();
    final cross = await repository.getCrossContaminationChecks(from: week);
    final temperatures = await repository.getTemperatureLogs(from: week);
    final cleaning = await repository.getCleaningLogs(from: week);

    return _doc(
      company: company,
      title: 'Prospetto riassuntivo moduli',
      period: 'Generato il ${_fmtDate(now)}',
      children: [
        _sectionTitle('Prospetto moduli di autocontrollo'),
        _table(
          headers: const ['Modulo', 'Frequenza', 'Compilazioni'],
          columnWidths: const [5, 4, 4],
          rows: [
            ['Temperature attrezzature', 'Giornaliera', '${temperatures.length} (7 gg)'],
            ['Pulizie e sanificazione', 'Secondo piano', '${cleaning.length} (7 gg)'],
            ['Cottura e rigenerazione', 'A ogni produzione', '${cookings.length} (7 gg)'],
            ['Abbattimento', 'A ogni ciclo', '${blasts.length} (7 gg)'],
            ['Mantenimento e trasporto', 'A ogni servizio', '${transports.length} (7 gg)'],
            ['Pasto campione', 'A ogni servizio (catering)', '${samples.length} totali'],
            ['Acqua e ghiaccio', 'Annuale / mensile', '${waters.length} (12 mesi)'],
            ['Ritiro e richiamo', 'Al bisogno', '${withdrawals.length} totali'],
            ['Cultura della sicurezza', 'Continuativa + verifica annuale', '${culture.length} registrazioni'],
            ['Contaminazione crociata', 'A ogni uso condiviso', '${cross.length} (7 gg)'],
          ],
        ),
        _disclaimer(),
      ],
    ).save();
  }

  /// Etichetta di prova per la verifica della stampante (wizard, passo 11).
  Future<Uint8List> buildTestLabel(String format) async {
    await _loadFonts();
    final company = await repository.getCompany();

    final (w, h) = switch (format) {
      '50x30' => (50.0, 30.0),
      '40x30' => (40.0, 30.0),
      _ => (62.0, 40.0),
    };
    final pageFormat = PdfPageFormat(
      w * PdfPageFormat.mm,
      h * PdfPageFormat.mm,
      marginAll: 2 * PdfPageFormat.mm,
    );

    final doc = pw.Document(theme: _theme);
    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) => pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                company.name.toUpperCase(),
                maxLines: 1,
                style: pw.TextStyle(
                  font: _bold!,
                  fontSize: 7,
                  color: _ink,
                ),
              ),
              pw.Text(
                'ETICHETTA DI PROVA',
                style: pw.TextStyle(font: _bold!, fontSize: 9),
              ),
              pw.Text(
                '${w.toStringAsFixed(0)} \u00D7 ${h.toStringAsFixed(0)} mm',
                style: pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }
}
