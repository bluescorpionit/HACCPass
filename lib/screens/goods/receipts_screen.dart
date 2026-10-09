import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/attachment_service.dart';
import '../../services/license_service.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';
import 'document_scan_flow.dart';
import 'suppliers_screen.dart';

/// Precompilazione di una riga letto dal documento (Prompt 8, A3).
typedef ReceiptPrefill = ({
  String? supplierName,
  String supplierVat,
  String? product,
  String? lot,
  String? ddt,
  DateTime? expiresAt,
  double? quantity,
  PendingAttachment? attachment,
});

class ReceiptsScreen extends StatelessWidget {
  const ReceiptsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  AttachmentService get _attachments =>
      AttachmentService(repository: repository);

  /// Punto d'ingresso pubblico per la coda "Riga i di n" dal documento.
  Future<void> registerReceipt(
    BuildContext context, {
    ReceiptPrefill? prefill,
    String? queueLabel,
  }) =>
      _newReceipt(context, prefill: prefill, queueLabel: queueLabel);

  @override
  Widget build(BuildContext context) {
    return LiveQuery<(List<Receipt>, Map<int, int>)>(
      repository: repository,
      loader: () async {
        final from = DateTime.now().subtract(const Duration(days: 30));
        final receipts = await repository.getReceipts(from: from);
        final counts = await repository.getAttachmentCounts('receipt');
        return (receipts, counts);
      },
      builder: (context, data) {
        final receipts = data.$1;
        final attachmentCounts = data.$2;
        return FeatureScaffold(
          title: 'Merce in arrivo',
          subtitle: 'Registra i controlli al ricevimento (PRP 10): se un '
              'controllo fallisce l\u2019app propone "Respinta" e apre '
              'la NC fornitore.',
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new_receipt',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _newReceipt(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Merce in arrivo'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SuppliersScreen(
                          repository: repository,
                          license: license,
                        ),
                      )),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('Gestisci fornitori'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Prompt 8, A3: lettura automatica dei campi dal
                  // documento (OCR tutto sul telefono, mai in rete).
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        if (!license.ensureLicensed(context)) return;
                        startDocumentScanFlow(
                          context,
                          repository: repository,
                          attachments: _attachments,
                          license: license,
                          onRowsConfirmed: (rows, attachment, head) async {
                            for (var i = 0; i < rows.length; i++) {
                              if (!context.mounted) break;
                              await registerReceipt(
                                context,
                                queueLabel: 'Riga ${i + 1} di ${rows.length}',
                                prefill: (
                                  supplierName: head.supplierName?.value,
                                  supplierVat: head.supplierVat?.value ?? '',
                                  product: rows[i].product,
                                  lot: rows[i].lot,
                                  ddt: head.docNumber?.value,
                                  expiresAt: rows[i].expiresAt,
                                  quantity: rows[i].quantity,
                                  attachment: i == 0 ? attachment : null,
                                ),
                              );
                            }
                          },
                        );
                      },
                      icon: const Icon(Icons.document_scanner),
                      label: const Text('Scansiona documento'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (receipts.isEmpty)
                EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Nessuna merce registrata',
                  message: 'Registra le consegne per tracciare temperatura e '
                      'controlli del fornitore.',
                  actionLabel: 'Registra consegna',
                  onAction: () => _newReceipt(context),
                )
              else
                for (final r in receipts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _ReceiptCard(
                      receipt: r,
                      repository: repository,
                      attachmentCount: attachmentCounts[r.id] ?? 0,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// Corrispondenza approssimata fornitore (normalizzazione: maiuscole,
  /// punteggiatura, spazi) con confronto per contenuto/prefisso.
  Supplier _matchSupplier(List<Supplier> suppliers, String? scannedName) {
    if (scannedName == null || scannedName.trim().isEmpty) {
      return suppliers.first;
    }
    String normalize(String value) => value
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9 ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final target = normalize(scannedName);
    for (final s in suppliers) {
      final candidate = normalize(s.name);
      if (candidate.contains(target) || target.contains(candidate)) {
        return s;
      }
    }
    // SimilaritÃƒÂ  per token comuni (>60%): gestisce "SocietÃƒÂ  X SRL" vs "X".
    final targetTokens = target.split(' ').toSet();
    for (final s in suppliers) {
      final tokens = normalize(s.name).split(' ').toSet();
      if (targetTokens.isEmpty || tokens.isEmpty) continue;
      final common = targetTokens.intersection(tokens).length;
      if (common / targetTokens.length >= 0.6) return s;
    }
    return suppliers.first;
  }

  Future<void> _newReceipt(
    BuildContext context, {
    ReceiptPrefill? prefill,
    String? queueLabel,
  }) async {
    final suppliers = await repository.getSuppliers();
    final operator = await repository.defaultOperator();
    if (!context.mounted) return;

    if (suppliers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registra prima almeno un fornitore.'),
        ),
      );
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            SuppliersScreen(repository: repository, license: license),
      ));
      return;
    }

    final productController = TextEditingController(
      text: prefill?.product ?? '',
    );
    final tempController = TextEditingController();
    final lotController = TextEditingController(text: prefill?.lot ?? '');
    final ddtController = TextEditingController(text: prefill?.ddt ?? '');
    final qtyPrefill = prefill?.quantity;
    final qtyController = TextEditingController(
      text: qtyPrefill == null
          ? ''
          : qtyPrefill
              .toStringAsFixed(qtyPrefill == qtyPrefill.roundToDouble() ? 0 : 3)
              .replaceAll('.', ','),
    );
    final noteController = TextEditingController();
    final pending = <PendingAttachment>[];
    if (prefill?.attachment != null) {
      pending.add(prefill!.attachment!);
    }
    const pendingAttachmentsHint =
        'Foto di DDT, etichetta o stato della merce al momento del controllo.';

    // Fornitore: corrispondenza approssimata con il nome letto dal
    // documento (normalizzazione + similaritÃƒÂ ); se non c'ÃƒÂ¨, resta il
    // primo e l'operatore sceglie.
    var supplier = _matchSupplier(suppliers, prefill?.supplierName);
    var category = goodsCategories.first;
    DateTime? expiresAt = prefill?.expiresAt;
    var packagingOk = true;
    var labelOk = true;
    var expiryOk = true;
    var vehicleOk = true;
    var proposedRejected = false;

    final saved = await showFormSheet<bool>(
      context: context,
      title: queueLabel ?? 'Nuova merce in arrivo',
      saveLabel: 'Registra',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final temp = double.tryParse(
                tempController.text.trim().replaceAll(',', '.'));
            final cat = category;
            final tempCompliant = temp == null
                ? true
                : (cat.minTemp == null || temp >= cat.minTemp!) &&
                    (cat.maxTemp == null || temp <= cat.maxTemp!);
            final allOk = packagingOk &&
                labelOk &&
                expiryOk &&
                vehicleOk &&
                tempCompliant;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Fornitore',
                  // Prompt 16, Ã‚Â§8: i fornitori crescono nel tempo: menu
                  // ricercabile completo (niente piÃƒÂ¹ take(6)).
                  child: SearchablePickerField<Supplier>(
                    label: 'Seleziona il fornitore',
                    selectedLabel: supplier.name,
                    items: [
                      for (final s in suppliers)
                        PickerItem(value: s, title: s.name),
                    ],
                    onPicked: (v) => setSheetState(() => supplier = v!),
                  ),
                ),
                LabeledField(
                  label: 'Prodotto',
                  child: TextField(
                    controller: productController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                LabeledField(
                  label: 'Categoria (limiti di riferimento)',
                  child: ChoiceRow<GoodsCategory>(
                    options: [
                      for (final c in goodsCategories) (c, c.label),
                    ],
                    selected: category,
                    onSelected: (v) => setSheetState(() => category = v),
                  ),
                ),
                if (category.hasTempRange)
                  Text(
                    'Limite: ${category.rangeLabel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Temperatura all\u2019arrivo (\u00B0C)',
                    suffixText: '\u00B0C',
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                if (temp != null && !tempCompliant) ...[
                  const SizedBox(height: 8),
                  const StatusPill(
                    text: 'Temperatura fuori limite per la categoria',
                    type: StatusType.danger,
                    large: true,
                  ),
                ],
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Lotto del fornitore',
                  child: TextField(controller: lotController),
                ),
                LabeledField(
                  label: 'N. DDT / bolla',
                  child: TextField(controller: ddtController),
                ),
                DateField(
                  label: 'Scadenza',
                  value: expiresAt,
                  onChanged: (v) => setSheetState(() => expiresAt = v),
                  allowClear: true,
                ),
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantit\u00E0'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Controlli (s\u00EC / no)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                _checkTile(
                  context,
                  'Integrit\u00E0 confezioni',
                  packagingOk,
                  (v) => setSheetState(() {
                    packagingOk = v;
                    if (!v) proposedRejected = true;
                  }),
                ),
                _checkTile(
                  context,
                  'Etichetta corretta',
                  labelOk,
                  (v) => setSheetState(() {
                    labelOk = v;
                    if (!v) proposedRejected = true;
                  }),
                ),
                _checkTile(
                  context,
                  'Scadenza valida',
                  expiryOk,
                  (v) => setSheetState(() {
                    expiryOk = v;
                    if (!v) proposedRejected = true;
                  }),
                ),
                _checkTile(
                  context,
                  'Mezzo di trasporto igienico',
                  vehicleOk,
                  (v) => setSheetState(() {
                    vehicleOk = v;
                    if (!v) proposedRejected = true;
                  }),
                ),
                const SizedBox(height: 10),
                if (!allOk || proposedRejected)
                  const StatusPill(
                    text: 'Esito proposto: RESPINTA (verr\u00E0 aperta una NC)',
                    type: StatusType.danger,
                    large: true,
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nota (facoltativa)',
                  ),
                ),
                const SizedBox(height: 12),
                // Allegati durante la registrazione: DDT, etichette, foto.
                PendingAttachmentsSection(
                  service: _attachments,
                  pending: pending,
                  hint: pendingAttachmentsHint,
                ),
              ],
            );
          },
        );
      },
      onSave: () => productController.text.trim().isNotEmpty,
    );

    if (saved != true) {
      // Annullato: elimina i file temporanei, nessun allegato orfano.
      await _attachments.discardPending(pending);
      return;
    }

    final temp =
        double.tryParse(tempController.text.trim().replaceAll(',', '.'));

    final receiptId = await repository.saveReceipt(
      Receipt(
        id: 0,
        receivedAt: DateTime.now(),
        supplierId: supplier.id,
        supplierName: supplier.name,
        product: productController.text.trim(),
        category: category.code,
        temperature: temp,
        supplierLot: lotController.text.trim(),
        ddt: ddtController.text.trim(),
        expiresAt: expiresAt,
        quantity:
            double.tryParse(qtyController.text.trim().replaceAll(',', '.')),
        packagingOk: packagingOk,
        labelOk: labelOk,
        expiryOk: expiryOk,
        vehicleOk: vehicleOk,
        outcome: packagingOk && labelOk && expiryOk && vehicleOk
            ? 'accepted'
            : 'rejected',
        note: noteController.text.trim(),
        operatorName: operator,
      ),
    );

    // Registrazione riuscita: gli allegati pendenti diventano definitivi.
    if (pending.isNotEmpty) {
      await _attachments.attachPending(
        AttachmentEntity.receipt,
        receiptId,
        pending,
      );
    }

    final rejected = !(packagingOk && labelOk && expiryOk && vehicleOk);
    if (context.mounted) {
      final messenger = ScaffoldMessenger.of(context);
      if (rejected && pending.isEmpty) {
        // Merce respinta senza foto: suggerisce di documentare ora.
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Merce respinta: aperta la non conformit\u00E0 fornitore.',
            ),
            action: SnackBarAction(
              label: 'Scatta foto del problema',
              onPressed: () => showAttachmentsSheet(
                context,
                repository: repository,
                entity: AttachmentEntity.receipt,
                entityId: receiptId,
                title: productController.text.trim(),
              ),
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              rejected
                  ? 'Merce respinta: NC aperta con ${pending.length} allegati.'
                  : 'Merce registrata: accettata con ${pending.length} '
                      'allegati.',
            ),
          ),
        );
      }
    }
  }

  Widget _checkTile(
    BuildContext context,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final colors = context.haccpColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 8),
          ChoiceChipX(
            label: 'S\u00EC',
            selected: value,
            onSelected: (_) => onChanged(true),
            semantic: ChipSemantic.success,
            leading: Icon(
              Icons.check,
              size: 18,
              color: colors.success,
            ),
          ),
          const SizedBox(width: 8),
          ChoiceChipX(
            label: 'No',
            selected: !value,
            onSelected: (_) => onChanged(false),
            semantic: ChipSemantic.danger,
            leading: Icon(
              Icons.close,
              size: 18,
              color: colors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.receipt,
    required this.repository,
    this.attachmentCount = 0,
  });

  final Receipt receipt;
  final HaccpRepository repository;
  final int attachmentCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    receipt.product,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(
                  text: receipt.outcomeLabel,
                  type: receipt.isRejected
                      ? StatusType.danger
                      : receipt.outcome == 'accepted_with_reserve'
                          ? StatusType.warning
                          : StatusType.success,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${receipt.supplierName} \u2022 ${fmtDate(receipt.receivedAt)}'
              '${receipt.temperature != null ? ' \u2022 ${fmtTemp(receipt.temperature!)}' : ''}'
              '${receipt.supplierLot?.isNotEmpty == true ? ' \u2022 lotto ${receipt.supplierLot}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (receipt.temperature != null && !receipt.isTempCompliant) ...[
              const SizedBox(height: 6),
              const StatusPill(
                text: 'Temperatura fuori limite per la categoria',
                type: StatusType.danger,
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showAttachmentsSheet(
                  context,
                  repository: repository,
                  entity: AttachmentEntity.receipt,
                  entityId: receipt.id,
                  title: receipt.product,
                ),
                icon: Badge(
                  isLabelVisible: attachmentCount > 0,
                  label: Text('$attachmentCount'),
                  child: const Icon(Icons.attach_file, size: 18),
                ),
                label: Text(
                  attachmentCount > 0
                      ? 'Foto e documenti ($attachmentCount)'
                      : 'Foto e documenti',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
