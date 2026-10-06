import 'package:flutter/material.dart';

import '../../core/constants/mgsa_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../services/pdf_service.dart';
import '../../widgets/common_widgets.dart';
import '../lots_screen.dart' show PdfPreviewScreen;

// -----------------------------------------------------------------------------
// Ritiro / richiamo (PR RIN)
// -----------------------------------------------------------------------------

class RecallScreen extends StatelessWidget {
  const RecallScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Ritiro e richiamo',
      subtitle:
          'Seleziona il lotto, elenca i destinatari, registra le azioni e la '
          'comunicazione all\u2019ASL (PR RIN). Esporta il modulo in PDF.',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_recall',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _create(context);
        },
        icon: const Icon(Icons.campaign_outlined),
        label: const Text('Nuovo ritiro'),
      ),
      body: LiveQuery<List<Withdrawal>>(
        repository: repository,
        loader: repository.getWithdrawals,
        builder: (context, withdrawals) {
          return Column(
            children: [
              if (withdrawals.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessun ritiro registrato.'),
                  ),
                )
              else
                for (final withdrawal in withdrawals)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        withdrawal.isOpen
                            ? Icons.warning_amber_outlined
                            : Icons.check_circle_outline,
                        color: withdrawal.isOpen
                            ? context.haccpColors.danger
                            : context.haccpColors.success,
                      ),
                      title: Text(
                        'Lotto ${withdrawal.lotCode}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${fmtDateTime(withdrawal.startedAt)} \u2022 '
                        '${withdrawal.clients.isEmpty ? 'destinatari non indicati' : withdrawal.clients}'
                        '${withdrawal.aslNotified ? ' \u2022 ASL informata' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: withdrawal.isOpen
                          ? TextButton(
                              onPressed: () =>
                                  repository.closeWithdrawal(withdrawal.id),
                              child: const Text('Chiudi'),
                            )
                          : IconButton(
                              tooltip: 'Modulo PDF',
                              onPressed: () => _exportPdf(context, withdrawal),
                              icon: const Icon(Icons.picture_as_pdf_outlined),
                            ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    final lots = await repository.getLots();
    if (!context.mounted) return;
    final lotController = TextEditingController();
    final clientsController = TextEditingController();
    final actionsController = TextEditingController();
    var aslNotified = false;
    var lotCode = lots.isEmpty ? '' : lots.first.code;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuovo ritiro/richiamo',
      saveLabel: 'Registra',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (lots.isNotEmpty)
                LabeledField(
                  label: 'Lotto in produzione',
                  child: ChoiceRow<String>(
                    options: [
                      for (final lot in lots.take(8)) (lot.code, lot.code),
                    ],
                    selected: lotCode,
                    onSelected: (v) => setSheetState(() => lotCode = v),
                  ),
                ),
              LabeledField(
                label: 'Lotto (editabile)',
                child: TextField(
                  controller: lotController..text = lotController.text.isEmpty ? lotCode : lotController.text,
                  onChanged: (v) => lotCode = v,
                ),
              ),
              LabeledField(
                label: 'Clienti / destinatari',
                child: TextField(
                  controller: clientsController,
                  maxLines: 2,
                ),
              ),
              LabeledField(
                label: 'Azioni intraprese',
                child: TextField(
                  controller: actionsController,
                  maxLines: 2,
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ASL informata'),
                value: aslNotified,
                onChanged: (v) => setSheetState(() => aslNotified = v),
              ),
            ],
          ),
        );
      },
      onSave: () => lotCode.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.createWithdrawal(
      lotCode: lotCode.trim().toUpperCase(),
      clients: clientsController.text.trim(),
      actions: actionsController.text.trim(),
      aslNotified: aslNotified,
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ritiro registrato.')),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context, Withdrawal withdrawal) async {
    if (!license.ensureLicensed(context)) return;
    final pdf = PdfService(repository: repository);
    final bytes = await pdf.buildWithdrawalForm(withdrawal);
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          title: 'Ritiro ${withdrawal.lotCode}',
          bytes: bytes,
          fileName:
              'HACCP_Ritiro_${sanitizeFileName(withdrawal.lotCode)}.pdf',
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Cultura della sicurezza alimentare (Reg. UE 2021/382)
// -----------------------------------------------------------------------------

class CultureScreen extends StatelessWidget {
  const CultureScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Cultura della sicurezza alimentare',
      subtitle:
          'Reg. UE 2021/382: politica firmata dal titolare, comunicazioni al '
          'personale e verifica annuale.',
      body: LiveQuery<List<CultureLogEntry>>(
        repository: repository,
        loader: repository.getCultureEntries,
        builder: (context, entries) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: context.haccpColors.infoBg,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'La cultura della sicurezza alimentare si costruisce con: '
                    'impegno visibile della direzione, formazione e '
                    'comunicazione continua, risorse adeguate, verifica '
                    'periodica e miglioramento.',
                    style: TextStyle(color: context.haccpColors.info),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _add(context, 'politica'),
                    icon: const Icon(Icons.gavel_outlined),
                    label: const Text('Politica firmata'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _add(context, 'comunicazione'),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Comunicazione al personale'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _add(context, 'verifica'),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Verifica annuale'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna registrazione.'),
                  ),
                )
              else
                for (final entry in entries)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.history_edu_outlined),
                      title: Text(
                        '${entry.kindLabel} \u2022 ${entry.title}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${fmtDateTime(entry.doneAt)} \u2022 ${entry.operatorName}',
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _add(BuildContext context, String kind) async {
    if (!license.ensureLicensed(context)) return;
    final titleController = TextEditingController();
    final notesController = TextEditingController();

    final saved = await showFormSheet<bool>(
      context: context,
      title: switch (kind) {
        'comunicazione' => 'Comunicazione al personale',
        'verifica' => 'Verifica annuale',
        _ => 'Politica della sicurezza alimentare',
      },
      saveLabel: 'Salva',
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Oggetto',
            child: TextField(controller: titleController),
          ),
          TextField(
            controller: notesController,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Contenuto / esito della verifica',
            ),
          ),
        ],
      ),
      onSave: () => titleController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveCultureEntry(
      kind: kind,
      title: titleController.text.trim(),
      notes: notesController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registrazione salvata.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Contaminazione crociata (Comunicazione 2022/C 355/01)
// -----------------------------------------------------------------------------

class CrossContaminationScreen extends StatelessWidget {
  const CrossContaminationScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Contaminazione crociata',
      subtitle:
          'Pulizia delle attrezzature condivise e verifica dei residui, '
          'collegata al piano di pulizia (orientamenti 2022/C 355/01).',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_cross',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.cleaning_services_outlined),
        label: const Text('Nuova verifica'),
      ),
      body: LiveQuery<List<CrossContaminationCheck>>(
        repository: repository,
        loader: () => repository.getCrossContaminationChecks(
          from: DateTime.now().subtract(const Duration(days: 60)),
        ),
        builder: (context, checks) {
          return Column(
            children: [
              if (checks.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna verifica registrata.'),
                  ),
                )
              else
                for (final check in checks)
                  Card(
                    child: ListTile(
                      leading: Icon(
                        check.residueFound
                            ? Icons.error_outline
                            : Icons.check_circle_outline,
                        color: check.residueFound
                            ? context.haccpColors.danger
                            : context.haccpColors.success,
                      ),
                      title: Text(check.equipment),
                      subtitle: Text(
                        '${fmtDateTime(check.checkedAt)} \u2022 '
                        '${check.residueFound ? 'residui trovati' : 'nessun residuo'}'
                        '${check.action?.isNotEmpty == true ? ' \u2022 ${check.action}' : ''}',
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
    final equipmentController = TextEditingController();
    final actionController = TextEditingController();
    var residueFound = false;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Verifica attrezzatura condivisa',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LabeledField(
                label: 'Attrezzatura (es. affettatrice, planetaria)',
                child: TextField(controller: equipmentController),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Residui trovati dopo la pulizia'),
                value: residueFound,
                onChanged: (v) => setSheetState(() => residueFound = v),
              ),
              if (residueFound)
                TextField(
                  controller: actionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Azione correttiva',
                  ),
                ),
            ],
          ),
        );
      },
      onSave: () =>
          equipmentController.text.trim().isNotEmpty &&
          (!residueFound || actionController.text.trim().isNotEmpty),
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveCrossContaminationCheck(
      equipment: equipmentController.text.trim(),
      residueFound: residueFound,
      action: actionController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verifica registrata.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Donazioni / ridistribuzione (Reg. UE 2021/382, facoltativo)
// -----------------------------------------------------------------------------

class DonationsScreen extends StatelessWidget {
  const DonationsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return FeatureScaffold(
      title: 'Ridistribuzione alimenti',
      subtitle:
          'Registro delle donazioni: data, prodotto, quantit\u00E0, ente e '
          'stato di conservazione (Reg. UE 2021/382, facoltativo).',
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_donation',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _register(context);
        },
        icon: const Icon(Icons.volunteer_activism_outlined),
        label: const Text('Nuova donazione'),
      ),
      body: LiveQuery<List<Donation>>(
        repository: repository,
        loader: () => repository.getDonations(
          from: DateTime.now().subtract(const Duration(days: 365)),
        ),
        builder: (context, donations) {
          return Column(
            children: [
              if (donations.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Nessuna donazione registrata.'),
                  ),
                )
              else
                for (final donation in donations)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.volunteer_activism_outlined),
                      title: Text(
                        '${donation.product} \u2192 ${donation.entity}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${fmtDate(donation.donatedAt)}'
                        '${donation.quantity != null ? ' \u2022 ${fmtQty(donation.quantity, donation.unit)}' : ''}'
                        '${donation.stateNote?.isNotEmpty == true ? ' \u2022 ${donation.stateNote}' : ''}',
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
    final entityController = TextEditingController();
    final qtyController = TextEditingController();
    final stateController = TextEditingController();

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuova donazione',
      saveLabel: 'Salva',
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LabeledField(
            label: 'Prodotto',
            child: TextField(controller: productController),
          ),
          LabeledField(
            label: 'Ente destinatario',
            child: TextField(controller: entityController),
          ),
          TextField(
            controller: qtyController,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantit\u00E0 (kg/pz)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: stateController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Temperatura / stato di conservazione',
            ),
          ),
        ],
      ),
      onSave: () =>
          productController.text.trim().isNotEmpty &&
          entityController.text.trim().isNotEmpty,
    );

    if (saved != true) return;
    final operator = await repository.defaultOperator();
    await repository.saveDonation(
      product: productController.text.trim(),
      entity: entityController.text.trim(),
      quantity: double.tryParse(qtyController.text.replaceAll(',', '.')),
      unit: (double.tryParse(qtyController.text) ?? 0) >= 20 ? 'kg' : 'pz',
      stateNote: stateController.text.trim(),
      operatorName: operator,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Donazione registrata.')),
      );
    }
  }
}

// -----------------------------------------------------------------------------
// Moduli e limiti configurabili
// -----------------------------------------------------------------------------

class LimitsScreen extends StatefulWidget {
  const LimitsScreen({super.key, required this.repository});

  final HaccpRepository repository;

  @override
  State<LimitsScreen> createState() => _LimitsScreenState();
}

class _LimitsScreenState extends State<LimitsScreen> {
  final _controllers = <String, TextEditingController>{};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<(Map<String, String>, Map<String, bool>)> _load() async {
    final values = <String, String>{};
    final modules = <String, bool>{};

    const numericKeys = [
      MgsaSettings.cookingCoreMin,
      MgsaSettings.regenerationCoreMin,
      MgsaSettings.fryerMaxTemp,
      MgsaSettings.blastChillPosTemp,
      MgsaSettings.blastChillPosHours,
      MgsaSettings.blastChillNegTemp,
      MgsaSettings.blastChillNegHours,
      MgsaSettings.holdColdMax,
      MgsaSettings.transportColdMax,
      MgsaSettings.transportHotMin,
      MgsaSettings.sampleGrams,
      MgsaSettings.sampleRetentionHours,
      MgsaSettings.trainingRenewalMonths,
    ];
    for (final key in numericKeys) {
      final raw = await widget.repository.getSetting(key);
      values[key] = raw;
    }

    const moduleKeys = [
      MgsaSettings.moduleCooking,
      MgsaSettings.moduleBlastChill,
      MgsaSettings.moduleTransport,
      MgsaSettings.moduleSamples,
      MgsaSettings.moduleWater,
      MgsaSettings.moduleRecall,
      MgsaSettings.moduleCulture,
      MgsaSettings.moduleDonations,
    ];
    for (final key in moduleKeys) {
      modules[key] = await widget.repository.isModuleEnabled(key);
    }
    return (values, modules);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Moduli e limiti')),
      body: FutureBuilder<(Map<String, String>, Map<String, bool>)>(
        future: _load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (values, modules) = snapshot.data!;

          const labels = <String, String>{
            MgsaSettings.cookingCoreMin:
                'Cottura: minimo al cuore (\u00B0C, default 75)',
            MgsaSettings.regenerationCoreMin:
                'Rigenerazione: minimo al cuore (\u00B0C, default 65)',
            MgsaSettings.fryerMaxTemp:
                'Frittura: temperatura massima (\u00B0C, default 180)',
            MgsaSettings.blastChillPosTemp:
                'Abbattimento positivo: T obiettivo (\u00B0C, default 3)',
            MgsaSettings.blastChillPosHours:
                'Abbattimento positivo: ore massime (default 2)',
            MgsaSettings.blastChillNegTemp:
                'Abbattimento negativo: T obiettivo (\u00B0C, default -18)',
            MgsaSettings.blastChillNegHours:
                'Abbattimento negativo: ore massime (default 2)',
            MgsaSettings.holdColdMax:
                'Mantenimento a freddo: massimo (\u00B0C, default 10)',
            MgsaSettings.transportColdMax:
                'Trasporto freddi: massimo (\u00B0C, default 10)',
            MgsaSettings.transportHotMin:
                'Trasporto caldi: minimo (\u00B0C, default 65)',
            MgsaSettings.sampleGrams:
                'Pasto campione: grammi minimi (default 100)',
            MgsaSettings.sampleRetentionHours:
                'Pasto campione: ore di conservazione (default 72)',
            MgsaSettings.trainingRenewalMonths:
                'Formazione: mesi di rinnovo attestato (default 36, '
                'verificare la propria regione)',
          };

          const moduleLabels = <String, String>{
            MgsaSettings.moduleCooking: 'Cottura e rigenerazione',
            MgsaSettings.moduleBlastChill: 'Abbattimento',
            MgsaSettings.moduleTransport: 'Mantenimento e trasporto',
            MgsaSettings.moduleSamples: 'Pasto campione',
            MgsaSettings.moduleWater: 'Acqua e ghiaccio',
            MgsaSettings.moduleRecall: 'Ritiro e richiamo',
            MgsaSettings.moduleCulture: 'Cultura della sicurezza alimentare',
            MgsaSettings.moduleDonations: 'Ridistribuzione alimenti',
          };

          return ListView(
            padding: screenPadding(context),
            children: [
              Text(
                'Limiti di riferimento (PR COT/ABB/TRA/CAMP): modificabili e '
                'valori di riferimento, la responsabilit\u00E0 resta '
                'dell\u2019operatore.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final entry in labels.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                    controller: _controllers.putIfAbsent(
                      entry.key,
                      () => TextEditingController(text: values[entry.key]),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: InputDecoration(labelText: entry.value),
                  ),
                ),
              const SectionTitle('Moduli attivi'),
              for (final entry in moduleLabels.entries)
                SwitchListTile(
                  title: Text(entry.value),
                  value: modules[entry.key] ?? false,
                  onChanged: (v) async {
                    await widget.repository
                        .setSetting(entry.key, v ? '1' : '0');
                    setState(() {});
                  },
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () async {
                  for (final entry in _controllers.entries) {
                    await widget.repository
                        .setSetting(entry.key, entry.value.text.trim());
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Limiti salvati.')),
                    );
                  }
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salva limiti'),
              ),
            ],
          );
        },
      ),
    );
  }
}
