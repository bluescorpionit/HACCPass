import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/haccp_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../models/haccp_models.dart';
import '../../../repositories/haccp_repository.dart';
import '../../../services/license_service.dart';
import '../../../widgets/common_widgets.dart';
import 'equipment_editor.dart';
import 'equipment_history_sheet.dart';

class TemperatureScreen extends StatelessWidget {
  const TemperatureScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<_TemperatureData>(
      repository: repository,
      loader: () async => _TemperatureData(
        equipment: await repository.getEquipment(),
        logs: await repository.getTodayTemperatureLogs(),
        operatorName: await repository.defaultOperator(),
      ),
      builder: (context, data) {
        final theme = Theme.of(context);
        final readToday = data.logs.map((l) => l.equipmentId).toSet();

        return FeatureScaffold(
          title: 'Temperature',
          subtitle:
              'Registra la lettura: se \u00E8 fuori limite l\u2019app '
              'propone le azioni correttive (PRP 11).',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _openEditor(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Attrezzatura'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...data.equipment.map(
                (equipment) {
                  final done = readToday.contains(equipment.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () =>
                            _register(context, equipment, data.operatorName),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Icon(
                                done
                                    ? Icons.check_circle_outline
                                    : Icons.thermostat,
                                size: 30,
                                color: done
                                    ? context.haccpColors.success
                                    : theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      equipment.name,
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${equipment.type} \u2022 ${equipment.rangeLabel}'
                                      '${equipment.location.isEmpty ? '' : ' \u2022 ${equipment.location}'}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              FilledButton(
                                onPressed: () => _register(
                                    context, equipment, data.operatorName),
                                child: const Text('Registra'),
                              ),
                              IconButton(
                                tooltip: 'Storico',
                                onPressed: () => showEquipmentHistory(
                                  context,
                                  repository,
                                  equipment,
                                ),
                                icon: const Icon(Icons.show_chart),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SectionTitle('Letture di oggi'),
              if (data.logs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Nessuna temperatura registrata oggi.'),
                  ),
                )
              else
                ...data.logs.map(
                  (log) {
                    final colors = context.haccpColors;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: Icon(
                            log.compliant
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: log.compliant
                                ? colors.success
                                : colors.danger,
                          ),
                          title: Text(
                            '${log.equipmentName ?? ''} \u2022 '
                            '${fmtTemp(log.temperature)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${fmtTime(log.measuredAt)} \u2022 ${log.operatorName}'
                            '${log.correctiveAction?.isNotEmpty == true ? '\nAzione: ${log.correctiveAction}' : ''}',
                          ),
                          isThreeLine:
                              log.correctiveAction?.isNotEmpty == true,
                          trailing: StatusPill(
                            text: log.compliant
                                ? 'Conforme'
                                : 'Fuori limite',
                            type: log.compliant
                                ? StatusType.success
                                : StatusType.danger,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tips_and_updates_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Zona di rischio: tra +10 e +60 \u00B0C. Oltre 2 '
                              'ore il prodotto va riportato a temperatura o '
                              'valutato (Reg. CE 852/2004).',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EquipmentEditor(repository: repository),
    ));
  }

  Future<void> _register(
    BuildContext context,
    Equipment equipment,
    String operatorName,
  ) async {
    if (!license.ensureLicensed(context)) return;

    final controller = TextEditingController();
    final noteController = TextEditingController();
    final selectedActions = <String>{};

    var saved = false;
    var temperature = 0.0;

    final result = await showFormSheet<bool>(
      context: context,
      title: equipment.name,
      saveLabel: 'Salva controllo',
      saveIcon: Icons.thermostat,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final parsed = double.tryParse(
              controller.text.trim().replaceAll(',', '.'),
            );
            final compliant =
                parsed != null && equipment.isCompliant(parsed);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Limiti di riferimento: ${equipment.rangeLabel}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'^-?[0-9]*[.,]?[0-9]*'),
                    ),
                  ],
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Temperatura rilevata (\u00B0C)',
                    suffixText: '\u00B0C',
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 10),
                if (parsed != null)
                  ComplianceIndicator(
                    compliant: compliant,
                    hasValue: true,
                  ),
                if (parsed != null && !compliant) ...[
                  const SizedBox(height: 14),
                  Text(
                    'Azioni correttive adottate',
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
                      for (final action in temperatureCorrectiveActions)
                        FilterChipX(
                          label: action,
                          selected: selectedActions.contains(action),
                          onSelected: (selected) => setSheetState(() {
                            selected
                                ? selectedActions.add(action)
                                : selectedActions.remove(action);
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Nota (facoltativa)',
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () {
        final parsed =
            double.tryParse(controller.text.trim().replaceAll(',', '.'));
        if (parsed == null) return false;
        temperature = parsed;
        saved = true;
        return true;
      },
    );

    if (result != true || !saved) return;

    final correctiveAction = selectedActions.isEmpty
        ? null
        : selectedActions.join('; ');

    await repository.saveTemperature(
      equipment: equipment,
      temperature: temperature,
      operatorName: operatorName,
      note: noteController.text.trim(),
      correctiveAction: correctiveAction,
    );

    if (!context.mounted) return;
    final colors = context.haccpColors;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          equipment.isCompliant(temperature)
              ? 'Temperatura registrata: conforme.'
              : 'Temperatura fuori limite: aperta una non conformit\u00E0 '
                  'con le azioni correttive.',
        ),
        backgroundColor: equipment.isCompliant(temperature)
            ? colors.success
            : colors.danger,
      ),
    );
  }
}

class _TemperatureData {
  const _TemperatureData({
    required this.equipment,
    required this.logs,
    required this.operatorName,
  });

  final List<Equipment> equipment;
  final List<TemperatureLog> logs;
  final String operatorName;
}
