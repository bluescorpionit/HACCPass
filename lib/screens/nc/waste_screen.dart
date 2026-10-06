import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/common_widgets.dart';

/// Registro eliminazione prodotti alimentari (Allegato II).
class WasteScreen extends StatelessWidget {
  const WasteScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Eliminazione prodotti')),
      body: LiveQuery<List<WasteLog>>(
        repository: repository,
        loader: () async {
          final from = DateTime.now().subtract(const Duration(days: 90));
          return repository.getWasteLogs(from: from);
        },
        builder: (context, logs) {
          return ListView(
            padding: screenPadding(context, top: 8, bottom: 96),
            children: [
              PageHeader(
                title: 'Registro eliminazioni',
                subtitle:
                    'Ogni prodotto eliminato va registrato con il motivo '
                    '(Allegato II): serve in ispezione.',
              ),
              if (logs.isEmpty)
                EmptyState(
                  icon: Icons.delete_outline,
                  title: 'Nessuna eliminazione',
                  message:
                      'Registra qui i prodotti scartati, scaduti o restituiti.',
                  actionLabel: 'Nuova eliminazione',
                  onAction: () {
                    if (!license.ensureLicensed(context)) return;
                    _newWaste(context);
                  },
                )
              else
                for (final log in logs)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(
                        log.product,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${log.reason} \u2022 ${fmtDate(log.disposedAt)}'
                        '${log.quantity != null ? ' \u2022 ${fmtQty(log.quantity, log.unit)}' : ''}'
                        '${log.lotCode?.isNotEmpty == true ? ' \u2022 lotto ${log.lotCode}' : ''}',
                      ),
                      isThreeLine: false,
                      trailing: Text(log.operatorName),
                    ),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_waste',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _newWaste(context);
        },
        icon: const Icon(Icons.add),
        label: const Text('Eliminazione'),
      ),
    );
  }

  Future<void> _newWaste(BuildContext context) async {
    final productController = TextEditingController();
    final qtyController = TextEditingController();
    final lotController = TextEditingController();
    final noteController = TextEditingController();
    var reason = wasteReasons.first;
    var unit = 'kg';

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuova eliminazione',
      saveLabel: 'Registra',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Prodotto',
                  child: TextField(controller: productController),
                ),
                LabeledField(
                  label: 'Motivo',
                  child: ChoiceRow<String>(
                    options: [for (final r in wasteReasons) (r, r)],
                    selected: reason,
                    onSelected: (v) => setSheetState(() => reason = v),
                  ),
                ),
                TextField(
                  controller: qtyController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Quantit\u00E0'),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Unit\u00E0',
                  child: ChoiceRow<String>(
                    options: const [('kg', 'kg'), ('pz', 'pz'), ('lt', 'lt')],
                    selected: unit,
                    onSelected: (v) => setSheetState(() => unit = v),
                  ),
                ),
                LabeledField(
                  label: 'Lotto (se noto)',
                  child: TextField(controller: lotController),
                ),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Nota'),
                ),
              ],
            );
          },
        );
      },
      onSave: () => productController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    final operator = await repository.defaultOperator();
    await repository.saveWasteLog(
      WasteLog(
        id: 0,
        disposedAt: DateTime.now(),
        product: productController.text.trim(),
        reason: reason,
        quantity:
            double.tryParse(qtyController.text.trim().replaceAll(',', '.')),
        unit: unit,
        lotCode: lotController.text.trim(),
        note: noteController.text.trim(),
        operatorName: operator,
      ),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eliminazione registrata.')),
      );
    }
  }
}
