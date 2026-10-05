import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/common_widgets.dart';

/// Monitoraggio infestanti (PRP 3): postazioni, conteggi, livelli automatici.
class PestsScreen extends StatelessWidget {
  const PestsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<_PestData>(
      repository: repository,
      loader: () async => _PestData(
        stations: await repository.getPestStations(),
        logs: await repository.getPestLogs(
          from: DateTime.now().subtract(const Duration(days: 60)),
        ),
        lastCheck: await repository.lastPestMonitoring(),
      ),
      builder: (context, data) {
        final overdue = data.lastCheck == null ||
            DateTime.now().difference(data.lastCheck!).inDays >
                pestCheckIntervalDays;

        return FeatureScaffold(
          title: 'Infestanti',
          subtitle:
              'Registra i conteggi per postazione: il livello \u00E8 '
              'calcolato automaticamente (PRP 3).',
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new_pest',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _newStation(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Postazione'),
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
                                ? 'Nessun monitoraggio registrato: esegui il '
                                    'controllo delle postazioni.'
                                : 'Ultimo monitoraggio oltre $pestCheckIntervalDays '
                                    'giorni fa.',
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
              for (final station in data.stations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                station.type == 'Roditori'
                                    ? Icons.pest_control_rodent_outlined
                                    : Icons.pest_control_outlined,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  station.location,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              Text(
                                station.type,
                                style:
                                    Theme.of(context).textTheme.labelMedium,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _typeHint(station.type),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                          if (station.lastCheckedAt != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Ultimo controllo: ${fmtDate(station.lastCheckedAt!)}',
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    if (!license.ensureLicensed(context)) return;
                                    _registerCheck(context, station);
                                  },
                                  icon: const Icon(Icons.check),
                                  label: const Text('Registra conteggio'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SectionTitle('Storico controlli'),
              if (data.logs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun controllo negli ultimi 60 giorni.'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final log in data.logs.take(12))
                        ListTile(
                          dense: true,
                          leading: Icon(
                            log.isSevere
                                ? Icons.error_outline
                                : log.level == 'moderate'
                                    ? Icons.warning_amber_outlined
                                    : Icons.check_circle_outline,
                            color: log.isSevere
                                ? context.haccpColors.danger
                                : log.level == 'moderate'
                                    ? context.haccpColors.warning
                                    : context.haccpColors.success,
                          ),
                          title: Text(
                            '${log.stationLocation ?? ''} \u2022 ${log.count}',
                          ),
                          subtitle: Text(
                            '${pestLevelLabel(switch (log.level) {
                                  'severe' => PestLevel.severe,
                                  'moderate' => PestLevel.moderate,
                                  _ => PestLevel.acceptable,
                                })} \u2022 ${fmtDate(log.checkedAt)}'
                            '${log.byCompany ? ' \u2022 ditta esterna' : ''}',
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _typeHint(String type) => switch (type) {
        'Roditori' =>
          '0 = accettabile \u2022 1 o pi\u00F9 = notevole (NC automatica)',
        'Striscianti' =>
          'somma 0-3 accettabile \u2022 4-7 modesto \u2022 8+ notevole',
        _ => 'per trappola: fino a 20 accettabile \u2022 21-30 modesto \u2022 31+ notevole',
      };

  Future<void> _newStation(BuildContext context) async {
    final locationController = TextEditingController();
    var type = pestStationTypes.first;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuova postazione',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Tipo',
                  child: ChoiceRow<String>(
                    options: [
                      for (final t in pestStationTypes) (t, t),
                    ],
                    selected: type,
                    onSelected: (v) => setSheetState(() => type = v),
                  ),
                ),
                LabeledField(
                  label: 'Ubicazione',
                  child: TextField(
                    controller: locationController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () => locationController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    await repository.savePestStation(
      PestStation(id: 0, type: type, location: locationController.text.trim()),
    );
  }

  Future<void> _registerCheck(BuildContext context, PestStation station) async {
    var count = 0;
    var byCompany = false;

    final saved = await showFormSheet<bool>(
      context: context,
      title: station.location,
      saveLabel: 'Salva conteggio',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final level = switch (station.type) {
              'Roditori' => pestLevelForRodents(count),
              'Striscianti' => pestLevelForCrawlers(count),
              _ => pestLevelForFlyers(count),
            };

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${station.type} \u2022 ${_typeHint(station.type)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: count > 0
                          ? () => setSheetState(() => count--)
                          : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      child: Text(
                        '$count',
                        style: Theme.of(context)
                            .textTheme
                            .displaySmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => setSheetState(() => count++),
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                StatusPill(
                  text: 'Livello: ${pestLevelLabel(level)}',
                  type: switch (level) {
                    PestLevel.acceptable => StatusType.success,
                    PestLevel.moderate => StatusType.warning,
                    PestLevel.severe => StatusType.danger,
                  },
                  large: true,
                ),
                if (level == PestLevel.severe) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: context.haccpColors.dangerBg,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Azioni immediate',
                            style: TextStyle(
                              color: context.haccpColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          for (final action in pestSevereActions)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '\u2022 $action',
                                style: TextStyle(
                                    color: context.haccpColors.danger),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                      'Controllo eseguito dalla ditta specializzata'),
                  value: byCompany,
                  onChanged: (v) => setSheetState(() => byCompany = v),
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
    await repository.savePestLog(
      station: station,
      count: count,
      byCompany: byCompany,
      operatorName: operator,
    );

    final level = switch (station.type) {
      'Roditori' => pestLevelForRodents(count),
      'Striscianti' => pestLevelForCrawlers(count),
      _ => pestLevelForFlyers(count),
    };
    if (context.mounted && level == PestLevel.severe) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Livello notevole: aperta una non conformit\u00E0 con le azioni da adottare.'),
          backgroundColor: context.haccpColors.danger,
        ),
      );
    }
  }
}

class _PestData {
  const _PestData({
    required this.stations,
    required this.logs,
    this.lastCheck,
  });

  final List<PestStation> stations;
  final List<PestLog> logs;
  final DateTime? lastCheck;
}
