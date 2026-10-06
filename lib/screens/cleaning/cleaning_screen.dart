import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/common_widgets.dart';

class CleaningScreen extends StatelessWidget {
  const CleaningScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<_CleaningData>(
      repository: repository,
      loader: () async => _CleaningData(
        tasks: await repository.getCleaningTasks(),
        operatorName: await repository.defaultOperator(),
      ),
      builder: (context, data) {
        // Raggruppa per area.
        final byArea = <String, List<CleaningTask>>{};
        for (final task in data.tasks) {
          byArea.putIfAbsent(task.area, () => []).add(task);
        }

        return FeatureScaffold(
          title: 'Pulizie e sanificazione',
          subtitle:
              'Conferma con un tocco. Se la superficie non \u00E8 idonea '
              'usa "Problema" (PRP 2).',
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'cleaning_edit',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _editTask(context, null);
            },
            icon: const Icon(Icons.add),
            label: const Text('Attivit\u00E0'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final area in byArea.keys) ...[
                SectionTitle(area),
                for (final task in byArea[area]!)
                  _TaskCard(
                    task: task,
                    operatorName: data.operatorName,
                    onDone: () async {
                      if (!license.ensureLicensed(context)) return;
                      await repository.completeCleaningTask(
                        task,
                        operatorName: data.operatorName,
                      );
                    },
                    onProblem: () => _reportProblem(
                      context,
                      task,
                      data.operatorName,
                    ),
                    onEdit: () => _editTask(context, task),
                  ),
              ],
              const SectionTitle('Ultime esecuzioni'),
              _RecentCleaning(repository: repository),
            ],
          ),
        );
      },
    );
  }

  Future<void> _reportProblem(
    BuildContext context,
    CleaningTask task,
    String operatorName,
  ) async {
    if (!license.ensureLicensed(context)) return;
    final noteController = TextEditingController();

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Problema: ${task.title}',
      saveLabel: 'Apri non conformit\u00E0',
      saveIcon: Icons.report_outlined,
      builder: (sheetContext) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Superficie non idonea: sporco visibile, tracce di unto o odori.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Descrivi il problema rilevato',
              ),
            ),
          ],
        );
      },
      onSave: () => true,
    );

    if (saved != true) return;
    await repository.reportCleaningProblem(
      task,
      operatorName: operatorName,
      note: noteController.text.trim(),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Problema registrato e non conformit\u00E0 aperta.'),
        ),
      );
    }
  }

  Future<void> _editTask(BuildContext context, CleaningTask? existing) async {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final areaController = TextEditingController(text: existing?.area ?? 'Cucina');
    final productController =
        TextEditingController(text: existing?.productName ?? '');
    final methodController =
        TextEditingController(text: existing?.method ?? '');
    var freq = existing?.frequencyEnum ?? CleaningFrequency.daily;

    final saved = await showFormSheet<bool>(
      context: context,
      title: existing == null
          ? 'Nuova attivit\u00E0 di pulizia'
          : 'Modifica attivit\u00E0',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Titolo',
                  child: TextField(
                    controller: titleController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                LabeledField(
                  label: 'Area',
                  child: TextField(
                    controller: areaController,
                    textCapitalization: TextCapitalization.words,
                  ),
                ),
                LabeledField(
                  label: 'Frequenza',
                  child: ChoiceRow<CleaningFrequency>(
                    options: [
                      for (final f in CleaningFrequency.values) (f, f.label),
                    ],
                    selected: freq,
                    onSelected: (v) => setSheetState(() => freq = v),
                  ),
                ),
                LabeledField(
                  label: 'Prodotto usato',
                  child: TextField(controller: productController),
                ),
                LabeledField(
                  label: 'Metodo (testo guida)',
                  child: TextField(
                    controller: methodController,
                    maxLines: 2,
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () => titleController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    await repository.saveCleaningTask(
      CleaningTask(
        id: existing?.id ?? 0,
        area: areaController.text.trim().isEmpty
            ? 'Cucina'
            : areaController.text.trim(),
        title: titleController.text.trim(),
        frequency: freq.label,
        freqCode: freq.code,
        productName: productController.text.trim(),
        method: methodController.text.trim(),
        lastCompletedAt: existing?.lastCompletedAt,
      ),
      id: existing?.id,
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.operatorName,
    required this.onDone,
    required this.onProblem,
    required this.onEdit,
  });

  final CleaningTask task;
  final String operatorName;
  final VoidCallback onDone;
  final VoidCallback onProblem;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = task.state;

    final (pillType, pillText) = switch (state) {
      CleaningState.pending ||
      CleaningState.dueToday => (StatusType.warning, 'Da fare oggi'),
      CleaningState.done => (StatusType.success, 'Fatto'),
      CleaningState.overdue => (StatusType.danger, 'Scaduta'),
      CleaningState.upcoming => (StatusType.neutral, _upcomingLabel(task)),
    };

    final subtitle = StringBuffer(task.frequency);
    if (task.productName?.isNotEmpty == true) {
      subtitle.write(' \u2022 ${task.productName}');
    }
    if (task.todayDoneCount > 0 && state != CleaningState.done) {
      subtitle.write(' \u2022 fatte ${task.todayDoneCount} oggi');
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Titolo e badge non si comprimono a vicenda: il badge sta
              // sotto il titolo, che puo' occupare fino a due righe.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        StatusPill(text: pillText, type: pillType),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Modifica',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle.toString(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (task.method?.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  task.method!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // "Fatto" e "Problema": etichette su una riga (scaleDown, mai
              // a capo dentro una parola); sotto 360 dp si impilano.
              LayoutBuilder(
                builder: (context, constraints) {
                  final done = FilledButton.icon(
                    onPressed: state == CleaningState.done ? null : onDone,
                    icon: const Icon(Icons.check),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Fatto', maxLines: 1),
                    ),
                  );
                  final problem = OutlinedButton.icon(
                    onPressed: onProblem,
                    icon: const Icon(Icons.report_outlined),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Problema', maxLines: 1),
                    ),
                  );
                  if (constraints.maxWidth < 360) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        done,
                        const SizedBox(height: 10),
                        problem,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: done),
                      const SizedBox(width: 10),
                      Expanded(child: problem),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _upcomingLabel(CleaningTask task) {
    final days = task.daysUntilDue;
    if (days == null) return 'Al bisogno';
    if (days <= 0) return 'Scaduta';
    return 'Tra $days giorni';
  }
}

class _RecentCleaning extends StatelessWidget {
  const _RecentCleaning({required this.repository});

  final HaccpRepository repository;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<List<CleaningLog>>(
      repository: repository,
      loader: () async {
        final from = DateTime.now().subtract(const Duration(days: 7));
        return repository.getCleaningLogs(from: from);
      },
      builder: (context, logs) {
        final colors = context.haccpColors;
        if (logs.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessuna esecuzione negli ultimi 7 giorni.'),
            ),
          );
        }
        return Card(
          child: Column(
            children: [
              for (final log in logs.take(8))
                ListTile(
                  dense: true,
                  leading: Icon(
                    log.hadProblem
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    color:
                        log.hadProblem ? colors.danger : colors.success,
                  ),
                  title: Text(
                    log.taskTitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text('${fmtDateTime(log.doneAt)} \u2022 ${log.operatorName}'),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _CleaningData {
  const _CleaningData({required this.tasks, required this.operatorName});

  final List<CleaningTask> tasks;
  final String operatorName;
}
