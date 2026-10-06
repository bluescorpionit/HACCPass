import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/constants/haccp_rules.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../services/attachment_service.dart';
import '../services/pdf_service.dart';
import '../widgets/attachment_section.dart';
import '../widgets/common_widgets.dart';
import 'goods/products_screen.dart';
import 'goods/traceability_screen.dart';

class LotsScreen extends StatelessWidget {
  const LotsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  AttachmentService get attachments =>
      AttachmentService(repository: repository);

  @override
  Widget build(BuildContext context) {
    return LiveQuery<List<ProductionLot>>(
      repository: repository,
      loader: () => repository.getLots(),
      builder: (context, lots) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new_lot',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _newLot(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Nuovo lotto'),
          ),
          body: ListView(
            padding: screenPadding(
              context,
              top: 16,
              bottom: 8,
              hasBottomBar: true,
              hasFab: true,
            ),
            children: [
              PageHeader(
                title: 'Lotti e produzione',
                subtitle:
                    'Codice automatico, scadenza precompilata, ingredienti '
                    'collegati alle consegne e etichetta con QR (Reg. CE '
                    '178/2002).',
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TraceabilityScreen(
                        repository: repository),
                  ),
                ),
                icon: const Icon(Icons.search),
                label: const Text('Cerca rintracciabilit\u00E0'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductsScreen(
                        repository: repository, license: license),
                  ),
                ),
                icon: const Icon(Icons.restaurant_menu_outlined),
                label: const Text('Prodotti e allergeni'),
              ),
              const SizedBox(height: 12),
              if (lots.isEmpty)
                EmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Nessun lotto creato',
                  message:
                      'Crea il lotto, collega gli ingredienti alle consegne '
                      'ricevute e stampa l\u2019etichetta.',
                  actionLabel: 'Nuovo lotto',
                  onAction: () {
                    if (!license.ensureLicensed(context)) return;
                    _newLot(context);
                  },
                )
              else
                for (final lot in lots)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _LotCard(
                      lot: lot,
                      repository: repository,
                      license: license,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _newLot(BuildContext context) async {
    final products = await repository.getProducts();
    final usableReceipts = await repository.getUsableReceipts();
    final operator = await repository.defaultOperator();
    if (!context.mounted) return;

    final codeController = TextEditingController();
    final qtyController = TextEditingController();
    final storageController = TextEditingController(text: 'Conservare a 0/+4 \u00B0C');
    final notesController = TextEditingController();
    final freeIngredientController = TextEditingController();
    final pending = <PendingAttachment>[];

    Product? product = products.isEmpty ? null : products.first;
    var producedAt = DateTime.now();
    DateTime? expiresAt;
    var quantityUnit = 'pz';
    final selectedReceiptIds = <int>{};

    if (product != null) {
      codeController.text = repository.generateLotCode(product.name);
      storageController.text =
          product.storage.isEmpty ? storageController.text : product.storage;
      expiresAt = product.shelfLifeDays == null
          ? DateTime.now().add(const Duration(days: 2))
          : DateTime.now().add(Duration(days: product.shelfLifeDays!));
    } else {
      codeController.text = repository.generateLotCode('LOTTO');
      expiresAt = DateTime.now().add(const Duration(days: 2));
    }

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo lotto di produzione',
      saveLabel: 'Crea lotto',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Prodotto (scheda)',
                  child: products.isEmpty
                      ? const Text(
                          'Nessuna scheda prodotto: il lotto sar\u00E0 libero. '
                          'Crea le schede per durata e allergeni.')
                      : ChoiceRow<Product?>(
                          options: [
                            for (final p in products.take(8)) (p, p.name),
                          ],
                          selected: product,
                          onSelected: (v) => setSheetState(() {
                            product = v;
                            codeController.text =
                                repository.generateLotCode(v!.name);
                            storageController.text = v.storage.isEmpty
                                ? 'Conservare a 0/+4 \u00B0C'
                                : v.storage;
                            expiresAt = v.shelfLifeDays == null
                                ? DateTime.now()
                                    .add(const Duration(days: 2))
                                : DateTime.now()
                                    .add(Duration(days: v.shelfLifeDays!));
                          }),
                        ),
                ),
                LabeledField(
                  label: 'Codice lotto (editabile)',
                  child: TextField(controller: codeController),
                ),
                DateField(
                  label: 'Data di produzione',
                  value: producedAt,
                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                  onChanged: (v) =>
                      setSheetState(() => producedAt = v ?? DateTime.now()),
                ),
                DateField(
                  label: 'Utilizzare entro (precompilata dalla durata)',
                  value: expiresAt,
                  onChanged: (v) => setSheetState(() => expiresAt = v),
                ),
                TextField(
                  controller: qtyController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Quantit\u00E0'),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Unit\u00E0',
                  child: ChoiceRow<String>(
                    options: const [('pz', 'pz'), ('kg', 'kg'), ('porzioni', 'porzioni')],
                    selected: quantityUnit,
                    onSelected: (v) => setSheetState(() => quantityUnit = v),
                  ),
                ),
                TextField(
                  controller: storageController,
                  decoration:
                      const InputDecoration(labelText: 'Conservazione'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Ingredienti: consegne ricevute (ultimi 60 giorni)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (usableReceipts.isEmpty)
                  Text(
                    'Nessuna consegna utilizzabile registrata.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in usableReceipts.take(12))
                        FilterChipX(
                          label:
                              '${r.product}${r.supplierLot?.isNotEmpty == true ? ' (${r.supplierLot})' : ''}',
                          selected: selectedReceiptIds.contains(r.id),
                          onSelected: (value) => setSheetState(() {
                            value
                                ? selectedReceiptIds.add(r.id)
                                : selectedReceiptIds.remove(r.id);
                          }),
                        ),
                    ],
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: freeIngredientController,
                  decoration: const InputDecoration(
                    labelText: 'Ingrediente libero (facoltativo)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
                const SizedBox(height: 12),
                PendingAttachmentsSection(
                  service: attachments,
                  pending: pending,
                  hint: 'Foto dell\u2019etichetta del fornitore, del '
                      'prodotto o scheda tecnica.',
                ),
                if (selectedReceiptIds.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _copyAttachmentsFromReceipts(
                        context,
                        usableReceipts
                            .where((r) => selectedReceiptIds.contains(r.id))
                            .toList(),
                        pending,
                        setSheetState,
                      ),
                      icon: const Icon(Icons.file_copy_outlined, size: 18),
                      label: const Text('Copia gli allegati dal carico'),
                    ),
                  ),
              ],
            );
          },
        );
      },
      onSave: () => codeController.text.trim().isNotEmpty,
    );

    if (saved != true) {
      // Annullato: elimina i file temporanei.
      await attachments.discardPending(pending);
      return;
    }

    final ingredients = <LotIngredient>[
      for (final r in usableReceipts)
        if (selectedReceiptIds.contains(r.id))
          LotIngredient(
            id: 0,
            lotId: 0,
            receiptId: r.id,
            name: r.product,
            supplierName: r.supplierName,
            supplierLot: r.supplierLot ?? '',
          ),
      if (freeIngredientController.text.trim().isNotEmpty)
        LotIngredient(
          id: 0,
          lotId: 0,
          name: freeIngredientController.text.trim(),
        ),
    ];

    final lotId = await repository.createLot(
      ProductionLot(
        id: 0,
        code: codeController.text.trim().toUpperCase(),
        productName: product?.name ?? 'Lotto libero',
        productId: product?.id,
        producedAt: producedAt,
        expiresAt: expiresAt,
        quantity: double.tryParse(
            qtyController.text.trim().replaceAll(',', '.')),
        unit: quantityUnit,
        storageInfo: storageController.text.trim(),
        operatorName: operator,
        notes: notesController.text.trim(),
        allergenCodes: product?.allergenCodes ?? const [],
      ),
      ingredients: ingredients,
    );

    // Salvataggio riuscito: gli allegati pendenti diventano definitivi.
    if (pending.isNotEmpty) {
      await attachments.attachPending(
        AttachmentEntity.lot,
        lotId,
        pending,
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            pending.isEmpty
                ? 'Lotto creato con i suoi ingredienti.'
                : 'Lotto creato con ${pending.length} allegati.',
          ),
        ),
      );
    }
  }

  /// Copia in lista pendente gli allegati delle merci ricevute selezionate
  /// come ingredienti: evita doppi scatti della stessa etichetta.
  Future<void> _copyAttachmentsFromReceipts(
    BuildContext context,
    List<Receipt> receipts,
    List<PendingAttachment> pending,
    void Function(void Function()) setSheetState,
  ) async {
    var copied = 0;
    for (final receipt in receipts) {
      final source = await repository.getAttachments('receipt', receipt.id);
      for (final attachment in source) {
        final clone = await attachments.cloneToTemp(attachment);
        pending.add(clone);
        copied++;
      }
    }
    if (!context.mounted) return;
    setSheetState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: copied == 0
            ? const Text('Le merci selezionate non hanno allegati.')
            : Text('$copied allegati copiati dal carico.'),
      ),
    );
  }
}

class _LotCard extends StatelessWidget {
  const _LotCard({
    required this.lot,
    required this.repository,
    required this.license,
  });

  final ProductionLot lot;
  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;

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
                    lot.productName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  lot.code,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Prodotto: ${fmtDate(lot.producedAt)}'
              '${lot.expiresAt != null ? ' \u2022 Entro: ${fmtDate(lot.expiresAt!)}' : ''}'
              '${lot.quantity != null ? ' \u2022 ${fmtQty(lot.quantity, lot.unit)}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (lot.allergenCodes.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Allergeni: ${lot.allergenCodes.map((c) => allergenByCode(c).label).join(', ')}',
                style: TextStyle(
                  color: colors.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (lot.ingredients.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Ingredienti: ${lot.ingredients.map((i) => i.name + (i.supplierName.isEmpty ? '' : ' (${i.supplierName})')).join('; ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showLabel(context),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Etichetta'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showTraceability(context),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('Rintraccio'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Foto e allegati',
                  onPressed: () => showAttachmentsSheet(
                    context,
                    repository: repository,
                    entity: AttachmentEntity.lot,
                    entityId: lot.id,
                    title: lot.productName,
                  ),
                  icon: const Icon(Icons.attach_file),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLabel(BuildContext context) async {
    if (!license.ensureLicensed(context)) return;

    final pdf = PdfService(repository: repository, license: license);
    final bytes = await pdf.buildLotLabel(lot);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          title: 'Etichetta ${lot.code}',
          bytes: bytes,
          fileName:
              'HACCP_Etichetta_${sanitizeFileName(lot.code)}_${_todayStamp()}.pdf',
        ),
      ),
    );
  }

  Future<void> _showTraceability(BuildContext context) async {
    final pdf = PdfService(repository: repository, license: license);
    final bytes = await pdf.buildTraceabilitySheet(lot);
    if (!context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          title: 'Rintracciabilit\u00E0 ${lot.code}',
          bytes: bytes,
          fileName:
              'HACCP_Rintracciabilita_${sanitizeFileName(lot.code)}_${_todayStamp()}.pdf',
        ),
      ),
    );
  }

  String _todayStamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

/// Anteprima PDF condivisa: pulsanti Condividi, Stampa, Salva.
class PdfPreviewScreen extends StatelessWidget {
  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.bytes,
    required this.fileName,
  });

  final String title;
  final Uint8List bytes;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: PdfPreview(
              build: (format) => bytes,
              useActions: false,
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Printing.sharePdf(bytes: bytes, filename: fileName);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('Condividi'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Printing.layoutPdf(
                          onLayout: (format) async => bytes,
                          name: fileName,
                        );
                      },
                      icon: const Icon(Icons.print),
                      label: const Text('Stampa'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
