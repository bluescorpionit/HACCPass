import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';

/// Ricerca rintracciabilità a monte e a valle (Reg. CE 178/2002).
class TraceabilityScreen extends StatefulWidget {
  const TraceabilityScreen({super.key, required this.repository});

  final HaccpRepository repository;

  @override
  State<TraceabilityScreen> createState() => _TraceabilityScreenState();
}

class _TraceabilityScreenState extends State<TraceabilityScreen> {
  final controller = TextEditingController();
  Future<TraceabilityResult>? future;

  void _search() {
    final query = controller.text.trim();
    if (query.isEmpty) return;
    setState(() => future = widget.repository.searchTraceability(query));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Rintracciabilit\u00E0')),
      body: ListView(
        padding: screenPadding(context),
        children: [
          TextField(
            controller: controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              labelText: 'Cerca per lotto, prodotto o lotto fornitore',
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: _search,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Serve per ritiro o richiamo: dal lotto del fornitore trovi tutti i '
            'lotti prodotti che lo contengono.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (future != null)
            FutureBuilder<TraceabilityResult>(
              future: future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data;
                if (data == null || data.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(18),
                      child: Text('Nessun risultato per la ricerca.'),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.receipts.isNotEmpty) ...[
                      const SectionTitle('Consegne trovate (a monte)'),
                      for (final r in data.receipts)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.local_shipping_outlined),
                            title: Text(
                              '${r.product} \u2022 ${r.supplierName}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'Ricevuta il ${fmtDate(r.receivedAt)}'
                              '${r.supplierLot?.isNotEmpty == true ? ' \u2022 lotto fornitore ${r.supplierLot}' : ''}',
                            ),
                            onTap: () => _showDownstream(context, r),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (data.lots.isNotEmpty) ...[
                      const SectionTitle('Lotti prodotti trovati (a valle)'),
                      for (final lot in data.lots)
                        Card(
                          child: ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(
                              '${lot.productName} \u2022 ${lot.code}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              'Prodotto il ${fmtDate(lot.producedAt)}'
                              '${lot.expiresAt != null ? ' \u2022 entro ${fmtDate(lot.expiresAt!)}' : ''}',
                            ),
                          ),
                        ),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _showDownstream(BuildContext context, Receipt receipt) async {
    final lots = await widget.repository.getLotsUsingReceipt(receipt.id);
    final lotCounts = await widget.repository.getAttachmentCounts('lot');
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          children: [
            Text(
              'Lotti che contengono "${receipt.product}"',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Rintracciabilit\u00E0 a valle: questi lotti vanno ritirati se la '
              'consegna risulta non conforme.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            // Allegati della consegna collegata.
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showAttachmentsSheet(
                  sheetContext,
                  repository: widget.repository,
                  entity: AttachmentEntity.receipt,
                  entityId: receipt.id,
                  title: receipt.product,
                ),
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Allegati della consegna'),
              ),
            ),
            const SizedBox(height: 8),
            if (lots.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nessun lotto prodotto usa questa consegna.'),
                ),
              )
            else
              for (final lot in lots)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text('${lot.productName} \u2022 ${lot.code}'),
                    subtitle: Text(
                        'Prodotto il ${fmtDate(lot.producedAt)} \u2022 ${lot.operatorName}'),
                    trailing: lotCounts[lot.id] != null
                        ? Badge(
                            label: Text('${lotCounts[lot.id]}'),
                            child: const Icon(Icons.attach_file),
                          )
                        : null,
                    onTap: () => showAttachmentsSheet(
                      sheetContext,
                      repository: widget.repository,
                      entity: AttachmentEntity.lot,
                      entityId: lot.id,
                      title: lot.productName,
                    ),
                  ),
                ),
          ],
        );
      },
    );
  }
}
