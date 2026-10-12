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

/// Filtro dell'elenco Lotti (Prompt 19, §3).
enum LotViewFilter {
  /// Lotti attivi (predefinito): i scaduti attivi restano in testa.
  active,

  /// Solo attivi con scadenza passata: da ritirare o chiudere.
  expired,

  /// Terminati e ritirati, ordinati per data di chiusura.
  archive,

  /// Tutto, con stati ben distinguibili.
  all;

  String get label => switch (this) {
        active => 'Attivi',
        expired => 'Scaduti',
        archive => 'Archivio',
        all => 'Tutti',
      };
}

/// Sotto-filtro del solo Archivio: Terminati / Ritirati / entrambi.
enum LotArchiveSubFilter { all, finished, withdrawn }

/// Filtro e ordinamento dell'elenco (funzione pura, coperta dai test).
/// - Attivi: i lotti attivi, scaduti in testa (scadenza più vecchia
///   prima), poi il resto per produzione descrescente.
/// - Scaduti: solo attivi scaduti, il più urgente prima.
/// - Archivio: chiusi per data di chiusura descrescente.
/// - Tutti: scaduti attivi in testa, poi tutto per produzione.
/// [query] filtra per codice, prodotto e ingredienti (case-insensitive).
List<ProductionLot> filterLotsForView(
  List<ProductionLot> lots,
  LotViewFilter filter, {
  LotArchiveSubFilter archiveSub = LotArchiveSubFilter.all,
  String query = '',
}) {
  var result = switch (filter) {
    LotViewFilter.active => lots.where((l) => l.isActive).toList(),
    LotViewFilter.expired => lots.where((l) => l.isExpired).toList(),
    LotViewFilter.archive => _archiveLots(lots, archiveSub),
    LotViewFilter.all => lots.toList(),
  };
  final q = query.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = result
        .where((l) =>
            l.code.toLowerCase().contains(q) ||
            l.productName.toLowerCase().contains(q) ||
            l.ingredients.any((i) => i.name.toLowerCase().contains(q)))
        .toList();
  }
  result.sort((a, b) {
    switch (filter) {
      case LotViewFilter.expired:
        return a.expiresAt!.compareTo(b.expiresAt!);
      case LotViewFilter.archive:
        final ac = a.closedAt ?? DateTime(1900);
        final bc = b.closedAt ?? DateTime(1900);
        return bc.compareTo(ac);
      default:
        break;
    }
    // Attivi / Tutti: i scaduti in testa (il più urgente prima), poi
    // produzione più recente prima.
    final aExpired = a.isExpired ? 0 : 1;
    final bExpired = b.isExpired ? 0 : 1;
    if (aExpired != bExpired) return aExpired - bExpired;
    if (aExpired == 0) {
      return a.expiresAt!.compareTo(b.expiresAt!);
    }
    return b.producedAt.compareTo(a.producedAt);
  });
  return result;
}

List<ProductionLot> _archiveLots(
    List<ProductionLot> lots, LotArchiveSubFilter sub) {
  final closed = lots.where((l) => l.isClosed).toList();
  return switch (sub) {
    LotArchiveSubFilter.finished =>
      closed.where((l) => l.isFinished).toList(),
    LotArchiveSubFilter.withdrawn =>
      closed.where((l) => l.isWithdrawn).toList(),
    LotArchiveSubFilter.all => closed,
  };
}

/// true se la merce in arrivo ha la scadenza passata (a fine giornata,
/// stessa regola dei lotti: che scade oggi non è scaduto fino a 23:59).
bool isReceiptExpired(Receipt r) {
  final e = r.expiresAt;
  if (e == null) return false;
  return DateTime(e.year, e.month, e.day, 23, 59, 59, 999)
      .isBefore(DateTime.now());
}

class LotsScreen extends StatefulWidget {
  const LotsScreen({
    super.key,
    required this.repository,
    required this.license,
    this.productEditor,
    this.initialFilter = LotViewFilter.active,
  });

  final HaccpRepository repository;
  final LicenseService license;

  /// Editor prodotto iniettabile per i test (default: l'editor condiviso
  /// della schermata Prodotti, Prompt 16, §8).
  final Future<Product?> Function(
    BuildContext context,
    HaccpRepository repository, {
    Product? existing,
  })? productEditor;

  /// Filtro iniziale: usato dalla navigazione da "Oggi" per aprire
  /// direttamente il filtro "Scaduti".
  final LotViewFilter initialFilter;

  @override
  State<LotsScreen> createState() => _LotsScreenState();
}

class _LotsScreenState extends State<LotsScreen> {
  LotViewFilter _filter = LotViewFilter.active;
  LotArchiveSubFilter _archiveSub = LotArchiveSubFilter.all;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  void didUpdateWidget(LotsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter) {
      setState(() => _filter = widget.initialFilter);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  AttachmentService get attachments =>
      AttachmentService(repository: widget.repository);

  HaccpRepository get repository => widget.repository;
  LicenseService get license => widget.license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<List<ProductionLot>>(
      repository: repository,
      loader: () => repository.getLots(),
      builder: (context, lots) {
        final counts = _FilterCounts.of(lots);
        final visible = filterLotsForView(
          lots,
          _filter,
          archiveSub: _archiveSub,
          query: _query,
        );
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
                    builder: (_) =>
                        TraceabilityScreen(repository: repository),
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
              TextField(
                key: const Key('lot_search_field'),
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: 'Cerca per codice, prodotto o ingrediente',
                  suffixIcon: _query.isEmpty
                      ? const Icon(Icons.search)
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
              const SizedBox(height: 12),
              // Filtro in alto (Prompt 19, §3): Attivi · Scaduti ·
              // Archivio · Tutti, con contatori. FittedBox: mai overflow
              // a 360 dp con testo 1.15.
              SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SegmentedButton<LotViewFilter>(
                    key: const Key('lot_filter_segmented'),
                    showSelectedIcon: false,
                    segments: [
                      for (final f in LotViewFilter.values)
                        ButtonSegment(
                          value: f,
                          label: Text(
                            counts.labelFor(f),
                            key: Key('lot_filter_${f.name}'),
                          ),
                        ),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (selection) =>
                        setState(() => _filter = selection.first),
                  ),
                ),
              ),
              if (_filter == LotViewFilter.archive) ...[
                const SizedBox(height: 8),
                ChoiceRow<LotArchiveSubFilter>(
                  options: const [
                    (LotArchiveSubFilter.all, 'Terminati e ritirati'),
                    (LotArchiveSubFilter.finished, 'Solo terminati'),
                    (LotArchiveSubFilter.withdrawn, 'Solo ritirati'),
                  ],
                  selected: _archiveSub,
                  onSelected: (v) => setState(() => _archiveSub = v),
                ),
              ],
              if (_filter == LotViewFilter.expired &&
                  counts.expiredActive > 0) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('lot_bulk_close_button'),
                  onPressed: () => _bulkCloseExpired(context, lots),
                  icon: const Icon(Icons.done_all),
                  label: const Text('Chiudi in blocco'),
                ),
              ],
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
              else if (visible.isEmpty)
                _EmptyFilterState(filter: _filter)
              else
                for (final lot in visible)
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

  /// "Chiudi in blocco" (Prompt 19, §0, primo avvio dopo l'aggiornamento):
  /// selezione multipla dei lotti scaduti attivi, scelta tra "segna come
  /// terminati" e "ritira come scaduti", SEMPRE con conferma esplicita e
  /// anteprima del numero. Nessuna chiusura automatica.
  Future<void> _bulkCloseExpired(
    BuildContext context,
    List<ProductionLot> lots,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final expired = lots.where((l) => l.isExpired).toList()
      ..sort((a, b) => a.expiresAt!.compareTo(b.expiresAt!));
    if (expired.isEmpty) return;
    final selected = {...expired.map((l) => l.id)};
    var asFinished = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Chiudi in blocco'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Scegli come chiudere i lotti scaduti ancora attivi. '
                  'Le registrazioni restano nel registro.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final lot in expired)
                        CheckboxListTile(
                          value: selected.contains(lot.id),
                          controlAffinity:
                              ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '${lot.productName} (${lot.code})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text('Scaduto il ${fmtDate(lot.expiresAt!)}'),
                          onChanged: (v) => setDialogState(() {
                            v == true
                                ? selected.add(lot.id)
                                : selected.remove(lot.id);
                          }),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                RadioGroup<bool>(
                  groupValue: asFinished,
                  onChanged: (v) =>
                      setDialogState(() => asFinished = v ?? true),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<bool>(
                        value: true,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Segna come terminati'),
                        subtitle:
                            const Text('Consumati prima della scadenza'),
                      ),
                      RadioListTile<bool>(
                        value: false,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Ritira come scaduti'),
                        subtitle: const Text(
                            'Motivo: scaduto, tolte dall\u2019uso'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              key: const Key('lot_bulk_close_confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, true),
              child: Text('Chiudi ${selected.length} '
                  '${selected.length == 1 ? 'lotto' : 'lotti'}'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || selected.isEmpty) return;

    final operator = await repository.defaultOperator();
    for (final lot in expired.where((l) => selected.contains(l.id))) {
      if (asFinished) {
        await repository.finishLot(lot.id, operatorName: operator);
      } else {
        await repository.withdrawLot(
          id: lot.id,
          reason: LotWithdrawalReason.expired,
          operatorName: operator,
        );
      }
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${selected.length} ${selected.length == 1 ? 'lotto chiuso' : 'lotti chiusi'} '
          '${asFinished ? 'come terminato' : 'come ritirato (scaduto)'}.',
        ),
      ),
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

    // Prompt 16, §8: nessuna preselezione silenziosa: si parte vuoti
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
    // cambio prodotto (Prompt 16, §8).
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
                                  await (widget.productEditor ??
                                      showProductEditor)(
                                context,
                                repository,
                              );
                              if (created == null || !context.mounted) return;
                              setSheetState(() {
                                product = created;
                                isFreeLot = false;
                                // Il nuovo prodotto è selezionato e il
                                // lotto si precompila (Prompt 16, §8).
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
                              await (widget.productEditor ??
                                      showProductEditor)(
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
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
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
                                  await (widget.productEditor ??
                                      showProductEditor)(
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
                  firstDate:
                      DateTime.now().subtract(const Duration(days: 30)),
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
                  decoration:
                      const InputDecoration(labelText: 'Quantit\u00E0'),
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
                      // Prompt 19, §5: le consegne scadute restano
                      // selezionabili ma sono ben visibili ("Scaduto il
                      // …") e alla creazione serve "Usa comunque".
                      for (final r in usableReceipts.take(12))
                        FilterChipX(
                          key: Key('lot_ingredient_chip_${r.id}'),
                          label: _receiptChipLabel(r),
                          semantic: isReceiptExpired(r)
                              ? ChipSemantic.danger
                              : ChipSemantic.neutral,
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

    // Prompt 19, §5: merce in ingresso scaduta come ingrediente: si
    // procede solo con conferma esplicita, registrata nella nota.
    final expiredSelected = usableReceipts
        .where((r) => selectedReceiptIds.contains(r.id) && isReceiptExpired(r))
        .toList();
    if (expiredSelected.isNotEmpty) {
      if (!context.mounted) {
        await attachments.discardPending(pending);
        return;
      }
      final useAnyway = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ingredienti con scadenza passata'),
          content: Text(
            '${expiredSelected.length == 1 ? 'Un ingrediente scelto ha' : '${expiredSelected.length} ingredienti scelti hanno'} '
            'la scadenza passata:\n\n'
            '${expiredSelected.map((r) => '\u2022 ${r.product} (scad. ${fmtDate(r.expiresAt!)})').join('\n')}\n\n'
            'Non usarlo: se lo usi comunque la scelta viene registrata '
            'nella nota del lotto.',
          ),
          actions: [
            TextButton(
              key: const Key('lot_expired_ingredient_cancel'),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              key: const Key('lot_expired_ingredient_use_anyway'),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Usa comunque'),
            ),
          ],
        ),
      );
      if (useAnyway != true) {
        await attachments.discardPending(pending);
        return;
      }
      final recorded = 'Uso comunque merce con scadenza passata: '
          '${expiredSelected.map((r) => '${r.product} (scad. ${fmtDate(r.expiresAt!)})').join(', ')}';
      notesController.text = notesController.text.trim().isEmpty
          ? recorded
          : '${notesController.text.trim()} \u2022 $recorded';
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
        // Lotto libero: il nome è obbligatorio (validato in onSave).
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

    // Prompt 16, §8: il prossimo lotto riparte da questo prodotto.
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

  String _receiptChipLabel(Receipt r) {
    final base =
        '${r.product}${r.supplierLot?.isNotEmpty == true ? ' (${r.supplierLot})' : ''}';
    if (!isReceiptExpired(r)) return base;
    return '$base \u26A0 scaduto il ${fmtDate(r.expiresAt!)}';
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

/// Contatori dei filtri (etichette "Attivi (12)").
class _FilterCounts {
  const _FilterCounts({
    required this.active,
    required this.expiredActive,
    required this.closed,
    required this.total,
  });

  final int active;
  final int expiredActive;
  final int closed;
  final int total;

  static _FilterCounts of(List<ProductionLot> lots) => _FilterCounts(
        active: lots.where((l) => l.isActive).length,
        expiredActive: lots.where((l) => l.isExpired).length,
        closed: lots.where((l) => l.isClosed).length,
        total: lots.length,
      );

  String labelFor(LotViewFilter filter) {
    final count = switch (filter) {
      LotViewFilter.active => active,
      LotViewFilter.expired => expiredActive,
      LotViewFilter.archive => closed,
      LotViewFilter.all => total,
    };
    return count == 0 ? filter.label : '${filter.label} ($count)';
  }
}

class _EmptyFilterState extends StatelessWidget {
  const _EmptyFilterState({required this.filter});

  final LotViewFilter filter;

  @override
  Widget build(BuildContext context) {
    final (icon, title, message) = switch (filter) {
      LotViewFilter.expired => (
          Icons.verified_outlined,
          'Nessun lotto scaduto da gestire',
          'I lotti attivi con la scadenza passata compaiono qui finché '
              'non li chiudi.',
        ),
      LotViewFilter.archive => (
          Icons.inventory_2_outlined,
          'Archivio vuoto',
          'I lotti terminati o ritirati restano qui, sempre riattivabili.',
        ),
      _ => (
          Icons.inventory_2_outlined,
          'Nessun lotto in questo filtro',
          'Crea un nuovo lotto con il pulsante in basso.',
        ),
      };
    return EmptyState(
      icon: icon,
      title: title,
      message: message,
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

    // I lotti chiusi sono attenuati ma leggibili (Prompt 19, §3).
    return Opacity(
      opacity: lot.isClosed ? 0.75 : 1,
      child: Card(
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
              if (lot.isClosed) ...[
                const SizedBox(height: 8),
                _ClosedStatusBanner(lot: lot),
                if (lot.closingNote?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Nota: ${lot.closingNote}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
              if (lot.isActive && lot.isExpired) ...[
                const SizedBox(height: 8),
                // Badge rosso: sempre anche testo, mai solo colore.
                Container(
                  key: const Key('lot_badge_expired'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colors.dangerBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error_outline,
                          size: 18, color: colors.danger),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Scaduto il ${fmtDate(lot.expiresAt!)} \u2014 da ritirare',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.danger,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (lot.isActive && lot.isExpiringSoon) ...[
                const SizedBox(height: 8),
                Text(
                  'In scadenza entro il ${fmtDate(lot.expiresAt!)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.warning,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
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
              if (lot.isActive) ...[
                // Prompt 19, §2: due azioni in orizzontale (regola di
                // progetto: massimo 2 in riga). Per i lotti già scaduti
                // "Ritira / smaltisci" è l'azione consigliata.
                Row(
                  children: [
                    Expanded(
                      child: lot.isExpired
                          ? OutlinedButton.icon(
                              key: const Key('lot_finish_button'),
                              onPressed: () => _finish(context),
                              icon: const Icon(Icons.task_alt_outlined),
                              label: const Text('Segna come terminato'),
                            )
                          : FilledButton.icon(
                              key: const Key('lot_finish_button'),
                              onPressed: () => _finish(context),
                              icon: const Icon(Icons.task_alt_outlined),
                              label: const Text('Segna come terminato'),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: lot.isExpired
                          ? FilledButton.icon(
                              key: const Key('lot_withdraw_button'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.danger,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => _withdrawSheet(context),
                              icon: const Icon(Icons.warning_amber_outlined),
                              label: const Text('Ritira / smaltisci'),
                            )
                          : OutlinedButton.icon(
                              key: const Key('lot_withdraw_button'),
                              onPressed: () => _withdrawSheet(context),
                              icon: const Icon(Icons.warning_amber_outlined),
                              label: const Text('Ritira / smaltisci'),
                            ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Prompt 16, §1–§2: quattro azioni UGUALI in orizzontale
                // (icona sopra, testo sotto su una riga, 56 dp).
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
              ] else ...[
                // Lotto chiuso: sola lettura salvo "Riattiva" (con
                // conferma) e "Aggiungi nota".
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        key: const Key('lot_reopen_button'),
                        onPressed: () => _reopen(context),
                        icon: const Icon(Icons.restart_alt_outlined),
                        label: const Text('Riattiva'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextButton.icon(
                        key: const Key('lot_add_note_button'),
                        onPressed: () => _addClosingNote(context),
                        icon: const Icon(Icons.note_add_outlined),
                        label: const Text('Aggiungi nota'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// "Segna come terminato": UN tocco, conferma leggera con Annulla
  /// (Prompt 19, §2). Nessun motivo da compilare. Il messenger si
  /// cerca PRIMA dell'await: chiudendo, il lotto esce dal filtro e la
  /// scheda viene smontata, ma la snackbar deve comparire lo stesso.
  Future<void> _finish(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await repository.finishLot(lot.id);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('Lotto ${lot.code} segnato come terminato.'),
        action: SnackBarAction(
          label: 'Annulla',
          onPressed: () => repository.reopenLot(lot.id, annotate: false),
        ),
      ),
    );
  }

  /// "Ritira / smaltisci": foglio con motivo (preselezionato "scaduto"
  /// se la scadenza è passata), quantità opzionale, nota (obbligatoria
  /// solo per "altro"), data/ora modificabile.
  Future<void> _withdrawSheet(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final operator = await repository.defaultOperator();
    if (!context.mounted) return;
    final qtyController = TextEditingController();
    final noteController = TextEditingController();
    var reason = lot.isExpired
        ? LotWithdrawalReason.expired
        : LotWithdrawalReason.damaged;
    var closedAt = DateTime.now();

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Ritira / smaltisci lotto',
      saveLabel: 'Ritira lotto',
      saveIcon: Icons.warning_amber_outlined,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final noteRequired = reason == LotWithdrawalReason.other;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Il lotto resta nel registro ma non sar\u00E0 pi\u00F9 '
                  'usabile come ingrediente n\u00E9 comparir\u00E0 tra gli '
                  'avvisi.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Motivo del ritiro',
                  child: ChoiceRow<String>(
                    key: const Key('lot_withdraw_reason'),
                    options: [
                      for (final r in LotWithdrawalReason.values)
                        (r, LotWithdrawalReason.label(r)),
                    ],
                    selected: reason,
                    onSelected: (v) => setSheetState(() => reason = v),
                  ),
                ),
                DateField(
                  label: 'Data del ritiro',
                  value: closedAt,
                  onChanged: (v) => setSheetState(
                    () => closedAt = _keepTime(closedAt, v),
                  ),
                ),
                LabeledField(
                  label: 'Ora del ritiro',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay.fromDateTime(closedAt),
                      );
                      if (picked != null) {
                        setSheetState(() => closedAt = _keepTime(
                              closedAt,
                              DateTime(
                                closedAt.year,
                                closedAt.month,
                                closedAt.day,
                                picked.hour,
                                picked.minute,
                              ),
                            ));
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        suffixIcon: Icon(Icons.schedule),
                      ),
                      child: Text(
                        fmtTime(closedAt),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                TextField(
                  key: const Key('lot_withdraw_quantity'),
                  controller: qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Quantit\u00E0 smaltita (facoltativa)',
                    hintText: 'es. 2,5 kg',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('lot_withdraw_note'),
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: noteRequired
                        ? 'Nota (obbligatoria per "Altro")'
                        : 'Nota (facoltativa)',
                  ),
                ),
                if (reason == LotWithdrawalReason.damaged ||
                    reason == LotWithdrawalReason.recall) ...[
                  const SizedBox(height: 8),
                  // Facoltativo (Prompt 19, §2): nessuna NC in automatico.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('lot_withdraw_report_nc'),
                      onPressed: () => _reportNonConformity(
                        sheetContext,
                        reason: reason,
                        operatorName: operator,
                      ),
                      icon: const Icon(Icons.report_outlined, size: 18),
                      label: const Text('Segnala non conformit\u00E0'),
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
      onSave: () {
        if (reason == LotWithdrawalReason.other &&
            noteController.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Con motivo "Altro" serve una nota di chiarimento.'),
            ),
          );
          return false;
        }
        return true;
      },
    );

    if (saved != true) return;
    await repository.withdrawLot(
      id: lot.id,
      reason: reason,
      closedAt: closedAt,
      note: noteController.text,
      quantity: qtyController.text,
      operatorName: operator,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Lotto ${lot.code} ritirato '
          '(${LotWithdrawalReason.label(reason).toLowerCase()}).',
        ),
      ),
    );
  }

  DateTime _keepTime(DateTime base, DateTime? newDate) {
    if (newDate == null) return base;
    return DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      base.hour,
      base.minute,
    );
  }

  /// Modulo NC precompilato con lotto e prodotto (Prompt 19, §2,
  /// facoltativo): riusa `createNonConformity` del repository.
  Future<void> _reportNonConformity(
    BuildContext context, {
    required String reason,
    required String operatorName,
  }) async {
    final titleController = TextEditingController(
      text: reason == LotWithdrawalReason.recall
          ? 'Richiamo lotto: ${lot.productName} (${lot.code})'
          : 'Lotto alterato/danneggiato: ${lot.productName} (${lot.code})',
    );
    final descriptionController = TextEditingController(
      text: 'Lotto ${lot.code} prodotto il ${fmtDate(lot.producedAt)} '
          'ritirato dall\u2019uso (${LotWithdrawalReason.label(reason).toLowerCase()}).',
    );
    final actionController = TextEditingController();
    var category = 'Materia prima';

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuova non conformit\u00E0',
      saveLabel: 'Apri non conformit\u00E0',
      saveIcon: Icons.report_outlined,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Categoria',
                child: ChoiceRow<String>(
                  options: [for (final c in ncCategories) (c, c)],
                  selected: category,
                  onSelected: (v) => setSheetState(() => category = v),
                ),
              ),
              LabeledField(
                label: 'Titolo / problema',
                child: TextField(controller: titleController),
              ),
              LabeledField(
                label: 'Descrizione',
                child: TextField(
                  controller: descriptionController,
                  maxLines: 3,
                ),
              ),
              TextField(
                controller: actionController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Azione immediata (facoltativa)',
                ),
              ),
            ],
          ),
        );
      },
      onSave: () =>
          titleController.text.trim().isNotEmpty &&
          descriptionController.text.trim().isNotEmpty,
    );
    if (saved != true) return;
    await repository.createNonConformity(
      category: category,
      title: titleController.text.trim(),
      description: descriptionController.text.trim(),
      correctiveAction: actionController.text.trim(),
      operatorName: operatorName,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non conformit\u00E0 registrata.')),
      );
    }
  }

  /// Riattivazione con conferma: la data viene annotata nella nota.
  Future<void> _reopen(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Riattivare il lotto?'),
        content: Text(
          'Il lotto ${lot.code} torna attivo per correggere un errore. '
          'La data di riattivazione viene annotata nella nota: lo storico '
          'non si perde.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            key: const Key('lot_reopen_confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Riattiva'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final operator = await repository.defaultOperator();
    await repository.reopenLot(lot.id, operatorName: operator);
    messenger.showSnackBar(
      SnackBar(content: Text('Lotto ${lot.code} di nuovo attivo.')),
    );
  }

  Future<void> _addClosingNote(BuildContext context) async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aggiungi nota'),
        content: TextField(
          key: const Key('lot_closing_note_field'),
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nota da aggiungere alla chiusura',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim().isNotEmpty),
            child: const Text('Salva'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    await repository.appendLotClosingNote(lot.id, controller.text);
  }

  /// Stampa l'etichetta del lotto con la stampante configurata (Prompt
  /// 11, §4): nessuna stampante → si configura o si condivide il PDF.
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

/// "Terminato il gg/mm/aaaa" (icona neutra) o "Ritirato il gg/mm/aaaa
/// (motivo)" (icona di avviso): stato sempre leggibile anche senza
/// colore.
class _ClosedStatusBanner extends StatelessWidget {
  const _ClosedStatusBanner({required this.lot});

  final ProductionLot lot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;
    final closedLabel = lot.closedAt == null
        ? lot.statusLabel
        : '${lot.statusLabel} il ${fmtDate(lot.closedAt!)}';
    final reasonLabel = lot.isWithdrawn && lot.withdrawnReason != null
        ? ' (${LotWithdrawalReason.label(lot.withdrawnReason!)})'
        : '';
    final withdrawnQty = lot.withdrawnQuantity?.isNotEmpty == true
        ? ' \u2022 smaltiti: ${lot.withdrawnQuantity}'
        : '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: lot.isWithdrawn ? colors.dangerBg : colors.successBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            lot.isWithdrawn
                ? Icons.warning_amber_outlined
                : Icons.task_alt_outlined,
            size: 18,
            color: lot.isWithdrawn ? colors.danger : colors.success,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$closedLabel$reasonLabel$withdrawnQty',
              style: theme.textTheme.labelMedium?.copyWith(
                color: lot.isWithdrawn ? colors.danger : colors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
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
