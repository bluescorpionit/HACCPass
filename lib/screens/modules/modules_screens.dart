import 'package:flutter/material.dart';

import '../../core/constants/mgsa_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';

// -----------------------------------------------------------------------------
// Cottura e rigenerazione (PR COT) + validazione olio (PR COT 02)
// -----------------------------------------------------------------------------

class CookingScreen extends StatelessWidget {
  const CookingScreen({super.key, required this.repository, required this.license});

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Cottura e rigenerazione',
      subtitle:
          'Registra la temperatura al cuore: esito automatico e NC con azione '
          'correttiva se sotto limite (PR COT 01).',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_cooking',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.outdoor_grill_outlined),
        label: const Text('Registra cottura'),
      ),
      body: LiveQuery<List<CookingLog>>(
        repository: repository,
        loader: () => repository.getCookingLogs(
          from: DateTime.now().subtract(const Duration(days: 30)),
        ),
        builder: (context, logs) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _RulesCard(),
              const SizedBox(height: 8),
              if (logs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna cottura registrata negli ultimi 30 giorni.'),
                  ),
                )
              else
                for (final log in logs)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        log.compliant
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: log.compliant
                            ? context.haccpColors.success
                            : context.haccpColors.danger,
                      ),
                      title: Text(
                        '${log.kindLabel} \u2022 ${log.category}'
                        '${log.foodName.isEmpty ? '' : ' (${log.foodName})'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${fmtTemp(log.coreTemp)} al cuore \u2022 '
                        '${fmtDateTime(log.cookedAt)} \u2022 ${log.operatorName}',
                      ),
                      trailing: StatusPill(
                        text: log.compliant ? 'Conforme' : 'Non conforme',
                        type:
                            log.compliant ? StatusType.success : StatusType.danger,
                      ),
                    ),
                  ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _validateOil(context),
                icon: const Icon(Icons.water_drop_outlined),
                label: const Text('Validazione olio da frittura (PR COT 02)'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context) async {
    final tempController = TextEditingController();
    final foodController = TextEditingController();
    final selectedActions = <String>{};
    var kind = 'cottura';
    var category = cookingRulesPRCOT01.first.category;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Registra cottura',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final parsed = double.tryParse(
                tempController.text.trim().replaceAll(',', '.'));
            final minTemp = kind == 'rigenerazione' ? 65.0 : 75.0;
            final compliant = parsed != null && parsed >= minTemp;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Tipo',
                  child: ChoiceRow<String>(
                    options: const [
                      ('cottura', 'Cottura'),
                      ('rigenerazione', 'Rigenerazione'),
                    ],
                    selected: kind,
                    onSelected: (v) => setSheetState(() => kind = v),
                  ),
                ),
                LabeledField(
                  label: 'Categoria (tabella PR COT 01)',
                  child: ChoiceRow<String>(
                    options: [
                      for (final rule in cookingRulesPRCOT01)
                        (rule.category, rule.category),
                    ],
                    selected: category,
                    onSelected: (v) => setSheetState(() => category = v),
                  ),
                ),
                TextField(
                  controller: foodController,
                  decoration: const InputDecoration(
                    labelText: 'Alimento (facoltativo)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tempController,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Temperatura al cuore (\u00B0C)',
                    suffixText: '\u00B0C',
                  ),
                  onChanged: (_) => setSheetState(() {}),
                ),
                const SizedBox(height: 8),
                if (parsed != null)
                  ComplianceIndicator(
                    compliant: compliant,
                    hasValue: true,
                  ),
                if (parsed != null && !compliant) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Azioni correttive',
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  // Righe checkbox: etichette lunghe integre, tocco >= 48 dp.
                  CorrectiveActionPicker(
                    actions: cookingCorrectiveActions,
                    selected: selectedActions,
                    onToggle: (action) => setSheetState(() {
                      selectedActions.contains(action)
                          ? selectedActions.remove(action)
                          : selectedActions.add(action);
                    }),
                  ),
                ],
              ],
            );
          },
        );
      },
      onSave: () =>
          double.tryParse(tempController.text.replaceAll(',', '.')) != null,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveCookingLog(
      kind: kind,
      category: category,
      foodName: foodController.text.trim(),
      coreTemp:
          double.parse(tempController.text.trim().replaceAll(',', '.')),
      correctiveAction:
          selectedActions.isEmpty ? null : selectedActions.join('; '),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cottura registrata.')),
      );
    }
  }

  Future<void> _validateOil(BuildContext context) async {
    final fryerController = TextEditingController();
    final tempController = TextEditingController();
    final noteController = TextEditingController();
    var sensoryOk = true;
    var oilChanged = false;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Validazione olio da frittura',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Friggitrice',
                child: TextField(controller: fryerController),
              ),
              TextField(
                controller: tempController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Temperatura (\u00B0C, limite 180)',
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Esito organolettico idoneo'),
                value: sensoryOk,
                onChanged: (v) => setSheetState(() => sensoryOk = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Olio cambiato'),
                value: oilChanged,
                onChanged: (v) => setSheetState(() => oilChanged = v),
              ),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Nota'),
              ),
            ],
          ),
        );
      },
      onSave: () => fryerController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveOilValidation(
      fryer: fryerController.text.trim(),
      tempC: double.tryParse(tempController.text.replaceAll(',', '.')) ?? 0,
      sensoryOk: sensoryOk,
      oilChanged: oilChanged,
      note: noteController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Validazione olio registrata.')),
      );
    }
  }
}

class _RulesCard extends StatelessWidget {
  const _RulesCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Linee guida cuore/tempo (PR COT 01)',
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Cottura \u2265 75 \u00B0C \u2022 rigenerazione \u2265 65 \u00B0C \u2022 '
              'frittura max 180 \u00B0C senza rabbocchi \u2022 valori di '
              'riferimento modificabili in "Moduli e limiti".',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Abbattimento (PR ABB)
// -----------------------------------------------------------------------------

class BlastChillScreen extends StatelessWidget {
  const BlastChillScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Abbattimento',
      subtitle:
          'Positivo: +3 \u00B0C entro 2 ore. Negativo: -18 \u00B0C entro 2 ore '
          '(PR ABB, limiti modificabili). Anomalia = ritiro e distruzione.',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_blast',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.ac_unit_outlined),
        label: const Text('Nuovo ciclo'),
      ),
      body: LiveQuery<List<BlastChillCycle>>(
        repository: repository,
        loader: () => repository.getBlastChillCycles(
          from: DateTime.now().subtract(const Duration(days: 60)),
        ),
        builder: (context, cycles) {
          return Column(
            children: [
              if (cycles.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun ciclo registrato negli ultimi 60 giorni.'),
                  ),
                )
              else
                for (final cycle in cycles)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        cycle.compliant
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: cycle.compliant
                            ? context.haccpColors.success
                            : context.haccpColors.danger,
                      ),
                      title: Text(
                        '${cycle.product} \u2022 '
                        '${cycle.kind == 'positivo' ? 'Positivo' : 'Negativo'}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Fine ${cycle.endedAt == null ? '\u2014' : fmtDateTime(cycle.endedAt!)}'
                        '${cycle.tEnd != null ? ' \u2022 ${fmtTemp(cycle.tEnd!)}' : ''}'
                        ' \u2022 ${cycle.operatorName}',
                      ),
                      trailing: StatusPill(
                        text: cycle.compliant ? 'Conforme' : 'Anomalia',
                        type:
                            cycle.compliant ? StatusType.success : StatusType.danger,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context) async {
    final productController = TextEditingController();
    final tStartController = TextEditingController();
    final tEndController = TextEditingController();
    final noteController = TextEditingController();
    var kind = 'positivo';
    var startedAt = DateTime.now().subtract(const Duration(hours: 1));
    var endedAt = DateTime.now();

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo ciclo di abbattimento',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Tipo',
                child: ChoiceRow<String>(
                  options: const [
                    ('positivo', 'Positivo (+3 \u00B0C / 2 h)'),
                    ('negativo', 'Negativo (-18 \u00B0C / 2 h)'),
                  ],
                  selected: kind,
                  onSelected: (v) => setSheetState(() => kind = v),
                ),
              ),
              LabeledField(
                label: 'Prodotto',
                child: TextField(controller: productController),
              ),
              DateField(
                label: 'Ora inizio',
                value: startedAt,
                onChanged: (v) =>
                    setSheetState(() => startedAt = v ?? startedAt),
              ),
              DateField(
                label: 'Ora fine',
                value: endedAt,
                onChanged: (v) => setSheetState(() => endedAt = v ?? endedAt),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: tStartController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'T iniziale'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: tEndController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'T finale (\u00B0C)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Etichetta/scadenza collegata (nota)',
                ),
              ),
            ],
          ),
        );
      },
      onSave: () => productController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveBlastChillCycle(
      product: productController.text.trim(),
      kind: kind,
      startedAt: startedAt,
      endedAt: endedAt,
      tEnd:
          double.tryParse(tEndController.text.replaceAll(',', '.')) ?? 99,
      tStart: double.tryParse(tStartController.text.replaceAll(',', '.')),
      note: noteController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ciclo di abbattimento registrato.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Mantenimento e trasporto (PR TRA / PR SOM)
// -----------------------------------------------------------------------------

class TransportScreen extends StatelessWidget {
  const TransportScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Mantenimento e trasporto',
      subtitle:
          'Caldi > 65 \u00B0C, freddi < 10 \u00B0C, checklist automezzo e '
          'contenitori (PR TRA / PR SOM).',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_transport',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('Nuova registrazione'),
      ),
      body: LiveQuery<List<TransportLog>>(
        repository: repository,
        loader: () => repository.getTransportLogs(
          from: DateTime.now().subtract(const Duration(days: 60)),
        ),
        builder: (context, logs) {
          return Column(
            children: [
              if (logs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna registrazione negli ultimi 60 giorni.'),
                  ),
                )
              else
                for (final log in logs)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        log.compliant
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: log.compliant
                            ? context.haccpColors.success
                            : context.haccpColors.danger,
                      ),
                      title: Text(
                        log.destination.isEmpty
                            ? 'Trasporto'
                            : log.destination,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${fmtDate(log.doneAt)} \u2022 '
                        'freddi ${log.tempColdArrival?.toStringAsFixed(0) ?? '\u2014'}\u00B0C \u2022 '
                        'caldi ${log.tempHotArrival?.toStringAsFixed(0) ?? '\u2014'}\u00B0C',
                      ),
                      trailing: StatusPill(
                        text: log.compliant ? 'Conforme' : 'Non conforme',
                        type:
                            log.compliant ? StatusType.success : StatusType.danger,
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context) async {
    final destinationController = TextEditingController();
    final coldStart = TextEditingController();
    final coldArrival = TextEditingController();
    final hotStart = TextEditingController();
    final hotArrival = TextEditingController();
    final noteController = TextEditingController();
    var vehicleClean = true;
    var containersSanitized = true;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Trasporto catering',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Destinazione',
                child: TextField(controller: destinationController),
              ),
              Text(
                'Temperature (partenza / arrivo)',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: coldStart,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Freddi part. \u00B0C'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: coldArrival,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Freddi arr. \u00B0C'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: hotStart,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Caldi part. \u00B0C'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: hotArrival,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Caldi arr. \u00B0C'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Automezzo pulito'),
                value: vehicleClean,
                onChanged: (v) => setSheetState(() => vehicleClean = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Contenitori sanificati'),
                value: containersSanitized,
                onChanged: (v) =>
                    setSheetState(() => containersSanitized = v),
              ),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Nota'),
              ),
            ],
          ),
        );
      },
      onSave: () => true,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveTransportLog(
      destination: destinationController.text.trim(),
      vehicleClean: vehicleClean,
      containersSanitized: containersSanitized,
      tempColdStart:
          double.tryParse(coldStart.text.replaceAll(',', '.')),
      tempColdArrival:
          double.tryParse(coldArrival.text.replaceAll(',', '.')),
      tempHotStart: double.tryParse(hotStart.text.replaceAll(',', '.')),
      tempHotArrival:
          double.tryParse(hotArrival.text.replaceAll(',', '.')),
      note: noteController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Trasporto registrato.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Pasto campione (PR CAMP 01)
// -----------------------------------------------------------------------------

class SamplesScreen extends StatelessWidget {
  const SamplesScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Pasto campione',
      subtitle:
          'Almeno 100 g, etichetta "campione ad uso interno", 0/+4 \u00B0C per '
          '72 ore (PR CAMP 01). Obbligatorio per catering esterno.',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_sample',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.science_outlined),
        label: const Text('Nuovo campione'),
      ),
      body: LiveQuery<List<SampleMeal>>(
        repository: repository,
        loader: repository.getSampleMeals,
        builder: (context, samples) {
          return Column(
            children: [
              if (samples.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun campione registrato.'),
                  ),
                )
              else
                for (final sample in samples)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        sample.discardedAt != null
                            ? Icons.check_circle_outline
                            : sample.isPendingDisposal
                                ? Icons.warning_amber_outlined
                                : Icons.timelapse,
                        color: sample.discardedAt != null
                            ? context.haccpColors.success
                            : sample.isPendingDisposal
                                ? context.haccpColors.warning
                                : context.haccpColors.info,
                      ),
                      title: Text(
                        '${sample.dish} \u2022 ${sample.grams.toStringAsFixed(0)} g',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        'Prelievo ${fmtDateTime(sample.takenAt)} \u2022 '
                        'smaltire dopo ${fmtDateTime(sample.discardAfter)}',
                      ),
                      trailing: sample.discardedAt == null
                          ? TextButton(
                              onPressed: () async {
                                if (!license.ensureLicensed(context)) return;
                                await repository.discardSample(sample.id);
                              },
                              child: const Text('Smaltito'),
                            )
                          : const StatusPill(
                              text: 'Smaltito', type: StatusType.success),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context) async {
    final dishController = TextEditingController();
    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo pasto campione',
      saveLabel: 'Salva',
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Piatto',
            child: TextField(controller: dishController),
          ),
          const Text(
            'Conservazione 0/+4 \u00B0C per 72 ore: la scadenza di smaltimento '
            'viene calcolata automaticamente.',
          ),
        ],
      ),
      onSave: () => dishController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveSampleMeal(
      dish: dishController.text.trim(),
      grams: 100,
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campione registrato.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Acqua potabile e ghiaccio (PR APO)
// -----------------------------------------------------------------------------

class WaterScreen extends StatelessWidget {
  const WaterScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Acqua e ghiaccio',
      subtitle:
          'Analisi microbiologica annuale (con referto allegabile), pulizia '
          'filtri e sanificazione mensile del produttore di ghiaccio (PR APO).',
      body: LiveQuery<List<WaterCheck>>(
        repository: repository,
        loader: () => repository.getWaterChecks(
          from: DateTime.now().subtract(const Duration(days: 400)),
        ),
        builder: (context, checks) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _register(context, 'analisi'),
                      icon: const Icon(Icons.science_outlined),
                      label: const Text('Analisi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _register(context, 'filtri'),
                      icon: const Icon(Icons.plumbing_outlined),
                      label: const Text('Filtri'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _register(context, 'ghiaccio'),
                      icon: const Icon(Icons.ac_unit_outlined),
                      label: const Text('Ghiaccio'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (checks.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna registrazione.'),
                  ),
                )
              else
                for (final check in checks.take(30))
                  Card(
                    child: ListTile(
                      leading: Icon(
                        check.resultOk
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: check.resultOk
                            ? context.haccpColors.success
                            : context.haccpColors.danger,
                      ),
                      title: Text(check.kindLabel),
                      subtitle: Text(
                        '${fmtDateTime(check.checkedAt)} \u2022 ${check.operatorName}',
                      ),
                      trailing: IconButton(
                        tooltip: 'Allega referto',
                        onPressed: () => showAttachmentsModuleSheet(
                          context,
                          repository: repository,
                          entityType: 'company',
                          entityId: check.id,
                          title: 'Referto ${check.kindLabel}',
                        ),
                        icon: const Icon(Icons.attach_file, size: 20),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _register(BuildContext context, String kind) async {
    final noteController = TextEditingController();
    var resultOk = true;

    final saved = await showFormSheet<bool>(
      context: context,
      title: switch (kind) {
        'filtri' => 'Pulizia filtri e rompigetto',
        'ghiaccio' => 'Sanificazione produttore di ghiaccio',
        _ => 'Analisi microbiologica acqua',
      },
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Esito positivo'),
                value: resultOk,
                onChanged: (v) => setSheetState(() => resultOk = v),
              ),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Nota / esito (obbligatoria se negativo)',
                ),
              ),
            ],
          ),
        );
      },
      onSave: () => resultOk || noteController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveWaterCheck(
      kind: kind,
      resultOk: resultOk,
      note: noteController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrazione salvata.')),
      );
    }
  }
}

/// Helper per allegati nelle schermate moduli.
Future<void> showAttachmentsModuleSheet(
  BuildContext context, {
  required HaccpRepository repository,
  required String entityType,
  required int entityId,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      children: [
        Text(
          title,
          style: Theme.of(sheetContext)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        AttachmentSection(
          repository: repository,
          entity: _entityFor(entityType),
          entityId: entityId,
        ),
      ],
    ),
  );
}

AttachmentEntity _entityFor(String type) => switch (type) {
      'company' => AttachmentEntity.company,
      'equipment' => AttachmentEntity.equipment,
      _ => AttachmentEntity.company,
    };
