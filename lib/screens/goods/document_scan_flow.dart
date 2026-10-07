import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../repositories/haccp_repository.dart';
import '../../services/attachment_service.dart';
import '../../services/license_service.dart';
import '../../services/ocr/document_parser.dart';
import '../../services/ocr/document_scan_service.dart';
import '../../services/ocr/ocr_port.dart';
import '../../services/ocr/ocr_preprocess.dart';
import '../../widgets/common_widgets.dart';

/// Riga prodotto confermata dall'operatore nella verifica.
class ConfirmedScanRow {
  ConfirmedScanRow({
    this.product,
    this.lot,
    this.expiresAt,
    this.quantity,
  });

  String? product;
  String? lot;
  DateTime? expiresAt;
  double? quantity;
}

/// Prompt 8, A3: flusso "Scansiona documento" in Merce in arrivo.
///
/// 1. scelta sorgente (foto o PDF dal telefono);
/// 2. OCR sul telefono (nessuna rete), annullabile, con copia temporanea
///    ad alta risoluzione (il PDF resta intatto);
/// 3. schermata "Verifica dati letti": campi incerti evidenziati, righe
///    modificabili e selezionabili;
/// 4. [onRowsConfirmed] riceve le righe confermate: l'operatore completa
///    i controlli HACCP nei fogli precompilati. Nulla viene salvato senza
///    conferma esplicita.
///
/// Con OCR fallito o documento illeggibile: messaggio chiaro, ripiego
/// manuale e nessun file residuo.
Future<void> startDocumentScanFlow(
  BuildContext context, {
  required HaccpRepository repository,
  required AttachmentService attachments,
  required LicenseService license,
  required Future<void> Function(
    List<ConfirmedScanRow> rows,
    PendingAttachment documentAttachment,
    ParsedDocument head,
  ) onRowsConfirmed,
}) async {
  // 1. Sorgente.
  final source = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Scansiona documento'),
      content: const Text(
        'Scatta una foto al DDT o alla fattura (luce buona, documento '
        'piatto, tutto nel riquadro) oppure scegli un file dal telefono. '
        'La lettura avviene SOLO sul telefono: nessuna immagine viene '
        'inviata in rete.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, 'camera'),
          child: const Text('Scatta foto'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, 'file'),
          child: const Text('Scegli file/foto'),
        ),
      ],
    ),
  );
  if (source == null || !context.mounted) return;

  PendingAttachment? picked;
  try {
    picked = source == 'camera'
        ? await attachments.capturePhotoTemp()
        : await attachments.pickDocumentTemp();
  } catch (_) {
    picked = null;
  }
  if (picked == null || !context.mounted) return;

  // 2. OCR con indicatore e annullamento.
  final service = DocumentScanService(
    recognizer: MlkitTextRecognizer(),
    ocrPreparer: (sourcePath, {required tempDir}) =>
        prepareForOcr(sourcePath, tempDir: tempDir),
  );
  var cancelled = false;
  DocumentScanOutcome? outcome;

  final progress = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Leggo il documento\u2026'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Riconoscimento sul telefono: alcuni secondi. '
              'Nessun dato lascia il dispositivo.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              service.cancel();
              Navigator.pop(dialogContext);
            },
            child: const Text('Annulla'),
          ),
        ],
      ),
    ),
  );

  try {
    final tempRoot = await getTemporaryDirectory();
    outcome = await service.scan(
      sourcePaths: [picked.tempPath],
      tempDir: tempRoot,
    );
  } catch (_) {
    outcome = null;
  }
  if (context.mounted) {
    Navigator.of(context).pop(); // chiude il progress
  }
  await progress.catchError((_) {});

  if (cancelled || !context.mounted) {
    await service.cleanup(outcome?.ocrPages ?? const []);
    await attachments.discardPending([picked]);
    return;
  }

  final scanOutcome = outcome;
  if (scanOutcome == null || !scanOutcome.hasData) {
    // Ripiego manuale: documento comunque allegabile, nessun dato perso.
    await service.cleanup(outcome?.ocrPages ?? const []);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Non ho letto il documento (foto sfocata o piegata?). '
            'Inserisci i dati a mano: puoi comunque allegare il file.',
          ),
        ),
      );
    }
    await attachments.discardPending([picked]);
    return;
  }

  // 3. Verifica dati letti.
  final confirmed = await Navigator.of(context).push<List<ConfirmedScanRow>>(
    MaterialPageRoute(
      builder: (_) => DocumentReviewScreen(outcome: scanOutcome),
    ),
  );
  await service.cleanup(scanOutcome.ocrPages);

  if (confirmed == null || confirmed.isEmpty || !context.mounted) {
    // Annullato: nessun file residuo.
    await attachments.discardPending([picked]);
    return;
  }

  // 4. Coda di fogli precompilati; il documento si collega a TUTTE le
  // merci create (file unico, più record: deduplica SHA-256).
  await onRowsConfirmed(confirmed, picked, scanOutcome.document);
}

/// Schermata "Verifica dati letti" (Prompt 8, A3): righe riconosciute come
/// schede modificabili, campi a bassa confidenza con avviso "Controlla"
/// (mai solo colore), selezione delle righe da registrare e aggiunta
/// manuale. Anteprima del documento con testo riconosciuto.
class DocumentReviewScreen extends StatefulWidget {
  const DocumentReviewScreen({super.key, required this.outcome});

  final DocumentScanOutcome outcome;

  @override
  State<DocumentReviewScreen> createState() => _DocumentReviewScreenState();
}

class _DocumentReviewScreenState extends State<DocumentReviewScreen> {
  late List<_EditableRow> _rows;

  @override
  void initState() {
    super.initState();
    _rows = [
      for (final line in widget.outcome.document.lines)
        _EditableRow.from(line),
    ];
  }

  void _addRow() {
    setState(() => _rows.add(_EditableRow.empty()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final doc = widget.outcome.document;
    final warnings = doc.warnings;

    return FeatureScaffold(
      title: 'Verifica dati letti',
      subtitle:
          'Controlla e correggi: i campi con "Controlla" sono incerti. '
          'Nulla viene salvato senza la tua conferma.',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'confirm_scan_rows',
        onPressed: _rows.any((r) => r.selected)
            ? () => Navigator.of(context).pop([
                  for (final row in _rows.where((r) => r.selected))
                    ConfirmedScanRow(
                      product: row.product.text.trim(),
                      lot: row.lot.text.trim(),
                      expiresAt: row.expiresAt,
                      quantity: double.tryParse(
                          row.quantity.text.trim().replaceAll(',', '.')),
                    ),
                ])
            : null,
        icon: const Icon(Icons.check),
        label: const Text('Continua'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _HeadField(
                    label: 'Fornitore',
                    value: doc.supplierName?.value,
                    confidence: doc.supplierName?.confidence,
                  ),
                  _HeadField(
                    label: 'P. IVA',
                    value: doc.supplierVat?.value,
                    confidence: doc.supplierVat?.confidence,
                  ),
                  _HeadField(
                    label: 'N. documento',
                    value: doc.docNumber?.value,
                    confidence: doc.docNumber?.confidence,
                  ),
                  _HeadField(
                    label: 'Data documento',
                    value: doc.docDate == null
                        ? null
                        : '${doc.docDate!.value.day.toString().padLeft(2, '0')}/'
                            '${doc.docDate!.value.month.toString().padLeft(2, '0')}/'
                            '${doc.docDate!.value.year}',
                    confidence: doc.docDate?.confidence,
                  ),
                  Text(
                    'Tipo riconosciuto: ${switch (doc.kind) { DocKind.ddt => 'DDT', DocKind.fattura => 'Fattura', _ => 'Non riconosciuto' }}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: StatusPill(
                        text: warning,
                        type: StatusType.warning,
                        large: true,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _rows.length; i++) _rowCard(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('Aggiungi riga'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowCard(int index) {
    final theme = Theme.of(context);
    final row = _rows[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                value: row.selected,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(
                  'Riga ${index + 1}',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                onChanged: (v) => setState(() => row.selected = v ?? false),
              ),
              TextField(
                controller: row.product,
                enabled: row.selected,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Prodotto',
                  errorText: row.productConfident ? null : 'Controlla',
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: row.lot,
                      enabled: row.selected,
                      decoration: InputDecoration(
                        labelText: 'Lotto',
                        errorText: row.lotConfident ? null : 'Controlla',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: row.quantity,
                      enabled: row.selected,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Quantità'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DateField(
                label: 'Scadenza',
                value: row.expiresAt,
                onChanged: (v) => setState(() => row.expiresAt = v),
                allowClear: true,
              ),
              if (!row.expiryConfident && row.expiresAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: StatusPill(
                    text: 'Scadenza letta con incertezza: controlla',
                    type: StatusType.warning,
                    large: true,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableRow {
  _EditableRow.empty()
      : selected = true,
        product = TextEditingController(),
        lot = TextEditingController(),
        quantity = TextEditingController(),
        productConfident = true,
        lotConfident = true,
        expiryConfident = true,
        expiresAt = null;

  factory _EditableRow.from(ParsedLine line) {
    return _EditableRow._(
      product: TextEditingController(text: line.description?.value ?? ''),
      lot: TextEditingController(text: line.lot?.value ?? ''),
      quantity: TextEditingController(
        text: line.quantity == null
            ? ''
            : (line.quantity!.value == line.quantity!.value.roundToDouble()
                ? line.quantity!.value.toStringAsFixed(0)
                : line.quantity!.value.toStringAsFixed(3)),
      ),
      productConfident: line.description == null ||
          !line.description!.needsReview,
      lotConfident: line.lot == null || !line.lot!.needsReview,
      expiryConfident: line.expiry == null || !line.expiry!.needsReview,
      expiresAt: line.expiry?.value,
      selected: true,
    );
  }

  _EditableRow._({
    required this.selected,
    required this.product,
    required this.lot,
    required this.quantity,
    required this.productConfident,
    required this.lotConfident,
    required this.expiryConfident,
    required this.expiresAt,
  });

  bool selected;
  final TextEditingController product;
  final TextEditingController lot;
  final TextEditingController quantity;
  final bool productConfident;
  final bool lotConfident;
  final bool expiryConfident;
  DateTime? expiresAt;
}

class _HeadField extends StatelessWidget {
  const _HeadField({
    required this.label,
    required this.value,
    this.confidence,
  });

  final String label;
  final String? value;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lowConfidence =
        confidence != null && confidence! < DocumentParser.reviewThreshold;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Text(
                value ?? '\u2014',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (value != null && lowConfidence)
          Icon(
            Icons.warning_amber,
            color: theme.colorScheme.error,
            semanticLabel: 'Controlla',
          ),
        if (value == null)
          Icon(
            Icons.help_outline,
            color: theme.colorScheme.onSurfaceVariant,
            semanticLabel: 'Non trovato: compila a mano nel passo successivo',
          ),
      ],
    ),
    );
  }
}
