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
import '../services/printing/print_label_flow.dart';
import '../widgets/attachment_section.dart';
import '../widgets/common_widgets.dart';
import 'goods/products_screen.dart';
import 'goods/traceability_screen.dart';

class LotsScreen extends StatelessWidget {
  const LotsScreen({
    super.key,
    required this.repository,
    required this.license,
    this.productEditor,
  });

  final HaccpRepository repository;
  final LicenseService license;

  /// Editor prodotto iniettabile per i test (default: l'editor condiviso
  /// della schermata Prodotti, Prompt 16, Â§8).
  final Future<Product?> Function(
    BuildContext context,
    HaccpRepository repository, {
    Product? existing,
  })? productEditor;

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
                    builder: (_) => TraceabilityScreen(repository: repository),
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
    products
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final usableReceipts = await repository.getUsableReceipts();
    final operator = await repository.defaultOperator();
    if (!context.mounted) return;

    final codeController = TextEditingController();
    final qtyController = TextEditingController();
    final storageController =
        TextEditingController(text: 'Conservare a 0/+4 \u00B0C');
    final notesController = TextEditingController();
    final freeIngredientController = TextEditingController();
    final freeLotNameController = TextEditingController();
    final pending = <PendingAttachment>[];

    // Prompt 16, Ã‚Â§8: nessuna preselezione silenziosa: si parte vuoti
    // oppure dall'ultimo prodotto usato (se esiste ancora).
    final lastUsedId =
        int.tryParse(await repository.getSetting('last_lot_product_id'));
    Product? product;
    for (final p in products) {
      if (p.id == lastUsedId) {
        product = p;
        break;
      }
    }
    var isFreeLot = false;
    var producedAt = DateTime.now();
    DateTime? expiresAt;
    var quantityUnit = 'pz';
    final selectedReceiptIds = <int>{};

    // Flag "dirty": i campi modificati a mano NON vengono toccati dal
    // cambio prodotto (Prompt 16, Ã‚Â§8).
    var codeDirty = false;
    var storageDirty = false;
    var expiryDirty = false;

    const defaultStorage = 'Conservare a 0/+4 \u00B0C';

    void prefillFromProduct(Product p, {bool force = false}) {
      if (!codeDirty || force) {
        codeController.text = repository.generateLotCode(p.name);
      }
      if (!storageDirty || force) {
        storageController.text = p.storage.isEmpty ? defaultStorage : p.storage;
      }
      if (!expiryDirty || force) {
        expiresAt = p.shelfLifeDays == null
            ? DateTime.now().add(const Duration(days: 2))
            : DateTime.now().add(Duration(days: p.shelfLifeDays!));
      }
    }

    void resetToFreeDefaults() {
      if (!codeDirty) codeController.text = repository.generateLotCode('LOTTO');
      if (!storageDirty) storageController.text = defaultStorage;
      if (!expiryDirty) {
        expiresAt = DateTime.now().add(const Duration(days: 2));
      }
    }

    if (product != null) {
      prefillFromProduct(product, force: true);
    } else {
      resetToFreeDefaults();
    }

    bool canCreate() =>
        product != null ||
        (isFreeLot && freeLotNameController.text.trim().isNotEmpty);

    if (!context.mounted) return;
    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo lotto di produzione',
      saveLabel: 'Crea lotto',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedName = product?.name ??
                (isFreeLot
                    ? 'Lotto libero (senza scheda)'
                    : 'Seleziona il prodotto');
            final summary = product == null
                ? null
                : [
                    if (product!.shelfLifeDays != null)
                      'Durata ${product!.shelfLifeDays} giorni',
                    if (product!.allergenCodes.isNotEmpty)
                      'Allergeni: ${product!.allergenCodes.map((c) => allergenByCode(c).label).join(', ')}',
                  ].join(' \u2022 ');

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Prodotto (scheda)',
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 340;
                      final picker = SearchablePickerField<Object>(
                        key: const Key('lot_product_picker'),
                        label: products.isEmpty
                            ? 'Nessuna scheda prodotto'
                            : 'Seleziona il prodotto',
                        enabled: products.isNotEmpty,
                        selectedLabel: selectedName,
                        items: [
                          for (final p in products)
                            PickerItem<Object>(
                              value: p,
                              title: p.name,
                              subtitle: [
                                if (p.shelfLifeDays != null)
                                  'durata ${p.shelfLifeDays} giorni',
                                if (p.allergenCodes.isNotEmpty)
                                  'allergeni: ${p.allergenCodes.map((c) => allergenByCode(c).label).join(', ')}',
                              ].join(' \u2022 '),
                            ),
                          const PickerItem<Object>(
                            value: _freeLotChoice,
                            title: 'Lotto libero (senza scheda)',
                          ),
                        ],
                        onPicked: (picked) => setSheetState(() {
                          if (picked == null) return;
                          if (picked is Product) {
                            product = picked;
                            isFreeLot = false;
                            prefillFromProduct(picked);
                          } else {
                            product = null;
                            isFreeLot = true;
                            resetToFreeDefaults();
                          }
                        }),
                      );
                      final newButton = SizedBox(
                        width: 52,
                        height: 52,
                        child: Tooltip(
                          message: 'Nuovo prodotto',
                          child: FilledButton.tonal(
                            onPressed: () async {
                              final created =
                                  await (productEditor ?? showProductEditor)(
                                context,
                                repository,
                              );
                              if (created == null || !context.mounted) return;
                              setSheetState(() {
                                product = created;
                                isFreeLot = false;
                                // Il nuovo prodotto ÃƒÂ¨ selezionato e il
                                // lotto si precompila (Prompt 16, Ã‚Â§8).
                                prefillFromProduct(created, force: true);
                              });
                            },
                            child: const Icon(Icons.add),
                          ),
                        ),
                      );
                      if (narrow) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            picker,
                            const SizedBox(height: 8),
                            newButton,
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: picker),
                          const SizedBox(width: 8),
                          newButton,
                        ],
                      );
                    },
                  ),
                ),
                if (products.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: SizedBox(
                      height: 52,
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () async {
                          final created =
                              await (productEditor ?? showProductEditor)(
                            context,
                            repository,
                          );
                          if (created == null || !context.mounted) return;
                          setSheetState(() {
                            products.add(created);
                            product = created;
                            prefillFromProduct(created, force: true);
                          });
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Crea il primo prodotto'),
                      ),
                    ),
                  )
                else ...[
                  if (product == null && !isFreeLot)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Scegli un prodotto o crea una nuova scheda.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  if (summary != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              summary == ''
                                  ? 'Nessun allergene indicato'
                                  : summary,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final edited =
                                  await (productEditor ?? showProductEditor)(
                                context,
                                repository,
                                existing: product,
                              );
                              if (edited == null || !context.mounted) return;
                              setSheetState(() => product = edited);
                            },
                            child: const Text('Modifica scheda'),
                          ),
                        ],
                      ),
                    ),
                ],
                if (isFreeLot)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextField(
                      key: const Key('lot_free_name_field'),
                      controller: freeLotNameController,
                      onChanged: (_) => setSheetState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Nome del lotto (obbligatorio)',
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Codice lotto (editabile)',
                  child: TextField(
                    key: const Key('lot_code_field'),
                    controller: codeController,
                    onChanged: (_) => codeDirty = true,
                  ),
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
                  onChanged: (v) {
                    expiryDirty = true;
                    setSheetState(() => expiresAt = v);
                  },
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
                    options: const [
                      ('pz', 'pz'),
                      ('kg', 'kg'),
                      ('porzioni', 'porzioni')
                    ],
                    selected: quantityUnit,
                    onSelected: (v) => setSheetState(() => quantityUnit = v),
                  ),
                ),
                TextField(
                  controller: storageController,
                  onChanged: (_) => storageDirty = true,
                  decoration: const InputDecoration(labelText: 'Conservazione'),
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
      onSave: () {
        if (!canCreate()) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Scegli un prodotto o compila il nome del lotto libero.'),
            ),
          );
          return false;
        }
        return codeController.text.trim().isNotEmpty;
      },
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
        // Lotto libero: il nome Ã¨ obbligatorio (validato in onSave).
        productName: product?.name ?? freeLotNameController.text.trim(),
        productId: product?.id,
        producedAt: producedAt,
        expiresAt: expiresAt,
        quantity:
            double.tryParse(qtyController.text.trim().replaceAll(',', '.')),
        unit: quantityUnit,
        storageInfo: storageController.text.trim(),
        operatorName: operator,
        notes: notesController.text.trim(),
        allergenCodes: product?.allergenCodes ?? const [],
      ),
      ingredients: ingredients,
    );

    // Prompt 16, Â§8: il prossimo lotto riparte da questo prodotto.
    await repository.setSetting(
      'last_lot_product_id',
      product?.id.toString() ?? '',
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  lot.code,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
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
            // Prompt 16, Ã‚Â§1Ã¢â‚¬â€œÃ‚Â§2: quattro azioni UGUALI in orizzontale
            // (icona sopra, testo sotto su una riga, 56 dp): niente piÃƒÂ¹
            // testo verticale a 90 dp per pulsante.
            ActionButtonRow(
              actions: [
                ActionButtonData(
                  icon: Icons.print_outlined,
                  label: 'Stampa',
                  tooltip: 'Stampa l\u2019etichetta del lotto',
                  onPressed: () => _printLabel(context),
                ),
                ActionButtonData(
                  icon: Icons.qr_code_2,
                  label: 'Etichetta',
                  tooltip: 'Anteprima e PDF dell\u2019etichetta',
                  onPressed: () => _showLabel(context),
                ),
                ActionButtonData(
                  icon: Icons.account_tree_outlined,
                  label: 'Rintraccio',
                  tooltip: 'Scheda di rintracciabilit\u00E0 del lotto',
                  onPressed: () => _showTraceability(context),
                ),
                ActionButtonData(
                  icon: Icons.attach_file,
                  label: 'Allegati',
                  tooltip: 'Foto e allegati',
                  onPressed: () => showAttachmentsSheet(
                    context,
                    repository: repository,
                    entity: AttachmentEntity.lot,
                    entityId: lot.id,
                    title: lot.productName,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Stampa l'etichetta del lotto con la stampante configurata (Prompt
  /// 11, Ã‚Â§4): nessuna stampante Ã¢â€ â€™ si configura o si condivide il PDF.
  Future<void> _printLabel(BuildContext context) async {
    if (!license.ensureLicensed(context)) return;

    final pdf = PdfService(repository: repository, license: license);
    final bytes = await pdf.buildLotLabel(lot);
    if (!context.mounted) return;

    await showPrintLabelDialog(
      context,
      repository: repository,
      pdfBytes: bytes,
      title: 'Stampa etichetta ${lot.code}',
      pdfFileName:
          'HACCP_Etichetta_${sanitizeFileName(lot.code)}_${_todayStamp()}.pdf',
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
                        await Printing.sharePdf(
                            bytes: bytes, filename: fileName);
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

/// Sentinella della voce "Lotto libero (senza scheda)" nel selettore.
class _FreeLotChoice {
  const _FreeLotChoice();
}

const _freeLotChoice = _FreeLotChoice();
