import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/common_widgets.dart';

/// Monitoraggio strutture per area (Allegato VII): checklist OK / Anomalia.
class StructuresScreen extends StatelessWidget {
  const StructuresScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<_StructuresData>(
      repository: repository,
      loader: () async => _StructuresData(
        checks: await repository.getStructureChecks(),
        lastCheck: await repository.lastStructureCheck(),
      ),
      builder: (context, data) {
        final overdue = data.lastCheck == null ||
            DateTime.now().difference(data.lastCheck!).inDays >
                structureCheckIntervalDays;

        return FeatureScaffold(
          title: 'Strutture',
          subtitle:
              'Checklist per area (Allegato VII), cadenza consigliata '
              'semestrale. Le anomalie aprono una NC riepilogativa.',
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new_structure',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _newCheck(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Nuovo controllo'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (overdue)
                Card(
                  color: context.haccpColors.warningBg,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_outlined,
                            color: context.haccpColors.warning),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            data.lastCheck == null
                                ? 'Nessun controllo strutture registrato.'
                                : 'Ultimo controllo oltre '
                                    '$structureCheckIntervalDays giorni fa.',
                            style: TextStyle(
                              color: context.haccpColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const SectionTitle('Controlli registrati'),
              if (data.checks.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun controllo strutture registrato.'),
                  ),
                )
              else
                for (final check in data.checks)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        check.hasAnomalies
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: check.hasAnomalies
                            ? context.haccpColors.danger
                            : context.haccpColors.success,
                      ),
                      title: Text(
                        '${check.area} \u2022 ${fmtDate(check.checkedAt)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        check.hasAnomalies
                            ? check.items
                                .where((i) => !i.ok)
                                .map((i) => i.label)
                                .join('; ')
                            : 'Nessuna anomalia rilevata',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      isThreeLine: check.hasAnomalies,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _newCheck(BuildContext context) async {
    var area = structureAreas.first;
    final states = {
      for (final item in structureCheckItems) item: true,
    };
    final notes = <String, TextEditingController>{};

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo controllo strutture',
      saveLabel: 'Salva controllo',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Area',
                  child: ChoiceRow<String>(
                    options: [
                      for (final a in structureAreas) (a, a),
                    ],
                    selected: area,
                    onSelected: (v) => setSheetState(() => area = v),
                  ),
                ),
                Text(
                  'Ogni voce: OK / Anomalia. Le anomalie generano una NC riepilogativa.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                for (final item in structureCheckItems)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        ChoiceChipX(
                          label: 'OK',
                          selected: states[item] == true,
                          onSelected: (_) =>
                              setSheetState(() => states[item] = true),
                          semantic: ChipSemantic.success,
                          leading: const Icon(Icons.check, size: 18),
                        ),
                        const SizedBox(width: 8),
                        ChoiceChipX(
                          label: 'Anomalia',
                          selected: states[item] == false,
                          onSelected: (_) =>
                              setSheetState(() => states[item] = false),
                          semantic: ChipSemantic.danger,
                          leading: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Nota sulle anomalie (facoltativa)',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                for (final item in structureCheckItems)
                  if (states[item] == false)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextField(
                        controller: notes.putIfAbsent(
                          item,
                          () => TextEditingController(),
                        ),
                        decoration: InputDecoration(labelText: item),
                      ),
                    ),
              ],
            );
          },
        );
      },
      onSave: () => true,
    );

    if (saved != true) return;

    final operator = await repository.defaultOperator();
    await repository.saveStructureCheck(
      area: area,
      items: [
        for (final item in structureCheckItems)
          StructureCheckItem(
            label: item,
            ok: states[item] ?? true,
            note: states[item] == false
                ? (notes[item]?.text.trim() ?? '')
                : '',
          ),
      ],
      operatorName: operator,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Controllo strutture registrato.')),
      );
    }
  }
}

class _StructuresData {
  const _StructuresData({required this.checks, this.lastCheck});

  final List<StructureCheck> checks;
  final DateTime? lastCheck;
}
