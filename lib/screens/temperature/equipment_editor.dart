import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../widgets/common_widgets.dart';
import '../sensors/link_sensor_sheet.dart';
import 'equipment_history_sheet.dart';

/// CRUD attrezzature con preset di temperatura.
class EquipmentEditor extends StatelessWidget {
  const EquipmentEditor({super.key, required this.repository});

  final HaccpRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Attrezzature')),
      body: LiveQuery<List<Equipment>>(
        repository: repository,
        loader: repository.getAllEquipment,
        builder: (context, items) {
          return ListView(
            padding: screenPadding(context, top: 8),
            children: [
              for (final equipment in items.where((e) => e.active))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: ListTile(
                      title: Text(
                        equipment.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${equipment.type} \u2022 ${equipment.rangeLabel}'
                        '${equipment.location.isEmpty ? '' : '\n${equipment.location}'}'
                        '${equipment.usesSensor ? '\nSorgente: Sensore (${equipment.sensorId != null ? 'ID ${equipment.sensorId}' : 'collega da Temperature'})' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          switch (action) {
                            case 'edit':
                              _edit(context, equipment);
                            case 'history':
                              showEquipmentHistory(
                                  context, repository, equipment);
                            case 'sensor':
                              await showLinkSensorSheet(
                                context,
                                repository: repository,
                                equipment: equipment,
                              );
                            case 'unlink':
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('Scollegare il sensore?'),
                                  content: Text(
                                    '${equipment.name} torna a sorgente '
                                    'Manuale. Le letture passate restano.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(
                                          dialogContext, false),
                                      child: const Text('Annulla'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(
                                          dialogContext, true),
                                      child: const Text('Scollega'),
                                    ),
                                  ],
                                ),
                              );
                              if (confirmed == true) {
                                await repository
                                    .unlinkSensorFromEquipment(equipment.id);
                              }
                            case 'delete':
                              final confirmed = await _confirmDelete(
                                  context, equipment);
                              if (confirmed) {
                                await repository
                                    .deactivateEquipment(equipment.id);
                              }
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text('Modifica'),
                          ),
                          PopupMenuItem(
                            value: 'history',
                            child: Text('Storico e verifica termometro'),
                          ),
                          PopupMenuItem(
                            value: 'sensor',
                            child: Text('Collega / cambia sensore'),
                          ),
                          PopupMenuItem(
                            value: 'unlink',
                            child: Text('Scollega sensore'),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text('Disattiva'),
                          ),
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
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nuova'),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Equipment equipment) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disattivare l\u2019attrezzatura?'),
        content: Text(
          '"${equipment.name}" non apparir\u00E0 pi\u00F9 nei controlli. Le '
          'letture passate restano nello storico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Disattiva'),
          ),
        ],
      ),
    ).then((v) => v ?? false);
  }

  Future<void> _edit(BuildContext context, Equipment? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final locationController =
        TextEditingController(text: existing?.location ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    final minController = TextEditingController(
      text: existing == null ? '' : existing.minTemp.toStringAsFixed(0),
    );
    final maxController = TextEditingController(
      text: existing == null ? '' : existing.maxTemp.toStringAsFixed(0),
    );
    var type = existing?.type ?? equipmentTypes.first;

    final knownPreset = equipmentPresets.where(
      (p) =>
          p.minTemp == existing?.minTemp && p.maxTemp == existing?.maxTemp,
    );
    var preset = knownPreset.isEmpty ? null : knownPreset.first;

    final saved = await showFormSheet<bool>(
      context: context,
      title: existing == null ? 'Nuova attrezzatura' : 'Modifica attrezzatura',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Nome',
                  child: TextField(
                    controller: nameController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                LabeledField(
                  label: 'Tipo',
                  child: ChoiceRow<String>(
                    options: [for (final t in equipmentTypes) (t, t)],
                    selected: type,
                    onSelected: (v) => setSheetState(() => type = v),
                  ),
                ),
                LabeledField(
                  label: 'Preset dei limiti (valori di riferimento)',
                  child: ChoiceRow<EquipmentPreset?>(
                    options: [
                      for (final p in equipmentPresets) (p, p.label),
                      (null, 'Personalizzato'),
                    ],
                    selected: preset,
                    onSelected: (p) => setSheetState(() => preset = p),
                  ),
                ),
                if (preset == null)
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Min \u00B0C',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: maxController,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Max \u00B0C',
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'Posizione',
                  child: TextField(
                    controller: locationController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                LabeledField(
                  label: 'Note',
                  child: TextField(
                    controller: notesController,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(height: 14),
                // Sorgente temperatura (Prompt 7): Manuale è il default.
                // Il collegamento vero del sensore avviene dalla sezione
                // Temperature (foglio "Collega sensore" con scansione).
                LabeledField(
                  label: 'Sorgente temperatura',
                  child: Text(
                    existing == null
                        ? 'Manuale (default). Dopo il salvataggio puoi '
                            'collegare un sensore Govee H5179 dalla sezione '
                            'Temperature.'
                        : existing.usesSensor
                            ? 'Sensore collegato: gestisci (cambia, offset, '
                                'verifica, scollega) dalla sezione '
                                'Temperature o dal menu di questa attrezzatura.'
                            : 'Manuale: l\u2019operatore inserisce il valore. '
                                '"Collega / cambia sensore" nel menu per usare '
                                'un Govee H5179.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () => nameController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    final minTemp = preset?.minTemp ??
        double.tryParse(minController.text.trim().replaceAll(',', '.')) ??
        0;
    final maxTemp = preset?.maxTemp ??
        double.tryParse(maxController.text.trim().replaceAll(',', '.')) ??
        4;

    await repository.saveEquipment(
      Equipment(
        id: existing?.id ?? 0,
        name: nameController.text.trim(),
        type: type,
        minTemp: minTemp,
        maxTemp: maxTemp,
        location: locationController.text.trim(),
        notes: notesController.text.trim(),
        thermoVerifiedAt: existing?.thermoVerifiedAt,
      ),
      id: existing?.id,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attrezzatura salvata.')),
      );
    }
  }
}
