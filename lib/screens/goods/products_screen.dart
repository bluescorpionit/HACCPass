import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/common_widgets.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Prodotti e allergeni')),
      body: LiveQuery<List<Product>>(
        repository: repository,
        loader: repository.getProducts,
        builder: (context, products) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              if (products.isEmpty)
                EmptyState(
                  icon: Icons.restaurant_menu_outlined,
                  title: 'Nessuna scheda prodotto',
                  message:
                      'Crea le schede con ingredienti e allergeni (Reg. UE '
                      '1169/2011): servono per lotti, etichette e men\u00F9.',
                  actionLabel: 'Nuovo prodotto',
                  onAction: () => _edit(context, null),
                )
              else
                for (final product in products)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (product.category.isNotEmpty) product.category,
                            if (product.shelfLifeDays != null)
                              'durata ${product.shelfLifeDays} giorni',
                            if (product.allergenCodes.isNotEmpty)
                              'allergeni: ${_allergenShort(product.allergenCodes)}',
                          ].join(' \u2022 '),
                        ),
                        isThreeLine: product.allergenCodes.length > 2,
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) async {
                            if (action == 'edit') {
                              _edit(context, product);
                            } else {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Eliminare il prodotto?'),
                                  content:
                                      Text('"${product.name}" verr\u00E0 rimosso.'),
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
                                await repository.deleteProduct(product.id);
                              }
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Modifica')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Elimina')),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_product',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _edit(context, null);
        },
        icon: const Icon(Icons.add),
        label: const Text('Prodotto'),
      ),
    );
  }

  String _allergenShort(List<String> codes) {
    final names =
        codes.map((c) => allergenByCode(c).label).take(3).join(', ');
    return codes.length > 3 ? '$names \u2026' : names;
  }

  Future<void> _edit(BuildContext context, Product? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final categoryController =
        TextEditingController(text: existing?.category ?? '');
    final ingredientsController =
        TextEditingController(text: existing?.ingredients ?? '');
    final shelfLifeController = TextEditingController(
      text: existing?.shelfLifeDays?.toString() ?? '',
    );
    final storageController =
        TextEditingController(text: existing?.storage ?? 'Conservare a 0/+4 \u00B0C');
    final selected = {...?existing?.allergenCodes};

    final saved = await showFormSheet<bool>(
      context: context,
      title: existing == null ? 'Nuovo prodotto' : 'Modifica prodotto',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Nome',
                  child: TextField(controller: nameController),
                ),
                LabeledField(
                  label: 'Categoria',
                  child: TextField(controller: categoryController),
                ),
                LabeledField(
                  label: 'Ingredienti',
                  child: TextField(
                    controller: ingredientsController,
                    maxLines: 2,
                  ),
                ),
                TextField(
                  controller: shelfLifeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Durata in giorni (per calcolare la scadenza)',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: storageController,
                  decoration:
                      const InputDecoration(labelText: 'Conservazione'),
                ),
                const SizedBox(height: 14),
                Text(
                  'Allergeni (Reg. UE 1169/2011)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final allergen in allergens)
                      FilterChipX(
                        label: '${allergen.number}. ${allergen.label}',
                        selected: selected.contains(allergen.code),
                        onSelected: (value) => setSheetState(() {
                          value
                              ? selected.add(allergen.code)
                              : selected.remove(allergen.code);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            );
          },
        );
      },
      onSave: () => nameController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    await repository.saveProduct(
      Product(
        id: existing?.id ?? 0,
        name: nameController.text.trim(),
        category: categoryController.text.trim(),
        ingredients: ingredientsController.text.trim(),
        shelfLifeDays: int.tryParse(shelfLifeController.text.trim()),
        storage: storageController.text.trim(),
        allergenCodes: selected.toList(),
      ),
      id: existing?.id,
    );
  }
}
