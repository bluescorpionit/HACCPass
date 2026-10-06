import 'package:flutter/material.dart';

import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';

class SuppliersScreen extends StatelessWidget {
  const SuppliersScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fornitori')),
      body: LiveQuery<List<Supplier>>(
        repository: repository,
        loader: repository.getSuppliers,
        builder: (context, suppliers) {
          return ListView(
            padding: screenPadding(context, top: 8, bottom: 96),
            children: [
              if (suppliers.isEmpty)
                EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Nessun fornitore',
                  message:
                      'Registra i fornitori per qualificarli e tracciare le '
                      'consegne (PRP 10).',
                  actionLabel: 'Nuovo fornitore',
                  onAction: () => _edit(context, null),
                )
              else
                for (final supplier in suppliers)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          supplier.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (supplier.vat.isNotEmpty) 'P.IVA ${supplier.vat}',
                            if (supplier.phone.isNotEmpty) supplier.phone,
                            if (supplier.products.isNotEmpty)
                              supplier.products,
                          ].join(' \u2022 '),
                        ),
                        isThreeLine: false,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (supplier.hasRepeatedNc)
                              const StatusPill(
                                text: 'NC ripetute',
                                type: StatusType.danger,
                              )
                            else if (!supplier.qualified)
                              const StatusPill(
                                text: 'Da qualificare',
                                type: StatusType.warning,
                              ),
                            PopupMenuButton<String>(
                              onSelected: (action) async {
                                if (action == 'edit') {
                                  _edit(context, supplier);
                                } else if (action == 'attachments') {
                                  if (!context.mounted) return;
                                  await showAttachmentsSheet(
                                    context,
                                    repository: repository,
                                    entity: AttachmentEntity.supplier,
                                    entityId: supplier.id,
                                    title: supplier.name,
                                  );
                                } else if (action == 'delete') {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      title: const Text('Eliminare il fornitore?'),
                                      content: Text(
                                          '"${supplier.name}" verr\u00E0 rimosso. '
                                          'Le consegne registrate restano nello storico.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext, false),
                                          child: const Text('Annulla'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.pop(dialogContext, true),
                                          child: const Text('Elimina'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await repository
                                        .deleteSupplier(supplier.id);
                                  }
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                    value: 'edit', child: Text('Modifica')),
                                PopupMenuItem(
                                    value: 'attachments',
                                    child: Text('Dichiarazioni e allegati')),
                                PopupMenuItem(
                                    value: 'delete', child: Text('Elimina')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'I fornitori con non conformit\u00E0 ripetute vanno '
                    'valutati per la sostituzione, come previsto dal manuale '
                    'di corretta prassi.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_supplier',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _edit(context, null);
        },
        icon: const Icon(Icons.add),
        label: const Text('Fornitore'),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Supplier? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final vatController = TextEditingController(text: existing?.vat ?? '');
    final addressController =
        TextEditingController(text: existing?.address ?? '');
    final phoneController = TextEditingController(text: existing?.phone ?? '');
    final emailController = TextEditingController(text: existing?.email ?? '');
    final productsController =
        TextEditingController(text: existing?.products ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var qualified = existing?.qualified ?? true;

    final saved = await showFormSheet<bool>(
      context: context,
      title: existing == null ? 'Nuovo fornitore' : 'Modifica fornitore',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Ragione sociale',
                  child: TextField(controller: nameController),
                ),
                LabeledField(
                  label: 'P.IVA',
                  child: TextField(controller: vatController),
                ),
                LabeledField(
                  label: 'Indirizzo',
                  child: TextField(controller: addressController),
                ),
                LabeledField(
                  label: 'Telefono',
                  child: TextField(controller: phoneController),
                ),
                LabeledField(
                  label: 'Email',
                  child: TextField(controller: emailController),
                ),
                LabeledField(
                  label: 'Prodotti forniti',
                  child: TextField(controller: productsController),
                ),
                LabeledField(
                  label: 'Qualificato',
                  child: ChoiceRow<bool>(
                    options: const [(true, 'S\u00EC'), (false, 'No')],
                    selected: qualified,
                    onSelected: (v) => setSheetState(() => qualified = v),
                  ),
                ),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            );
          },
        );
      },
      onSave: () => nameController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    await repository.saveSupplier(
      Supplier(
        id: existing?.id ?? 0,
        name: nameController.text.trim(),
        vat: vatController.text.trim(),
        address: addressController.text.trim(),
        phone: phoneController.text.trim(),
        email: emailController.text.trim(),
        products: productsController.text.trim(),
        qualified: qualified,
        notes: notesController.text.trim(),
      ),
      id: existing?.id,
    );
  }
}
