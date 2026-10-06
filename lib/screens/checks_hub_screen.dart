import 'package:flutter/material.dart';

import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../widgets/common_widgets.dart';
import 'cleaning/cleaning_screen.dart';
import 'nc/pests_screen.dart';
import 'nc/structures_screen.dart';
import 'nc/waste_screen.dart';
import 'non_conformities_screen.dart';
import 'temperature/temperature_screen.dart';
import 'goods/receipts_screen.dart';
import 'goods/suppliers_screen.dart';
import 'staff/staff_screen.dart';
import 'modules/modules_screens.dart';
import 'modules/extra_screens.dart';

/// Hub dei controlli: ogni registro con il proprio badge di stato.
///
/// Come tab della shell resta senza AppBar; aperta via `Navigator.push`
/// ([standalone] = true) si avvolge in un [FeatureScaffold]: nessuna
/// schermata pushata puo' restituire contenuti senza Scaffold (sfondo
/// nero, testi illeggibili).
class ChecksHubScreen extends StatefulWidget {
  const ChecksHubScreen({
    super.key,
    required this.repository,
    required this.license,
    this.initialTarget,
    this.standalone = false,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final String? initialTarget;
  final bool standalone;

  @override
  State<ChecksHubScreen> createState() => _ChecksHubScreenState();
}

class _ChecksHubScreenState extends State<ChecksHubScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.initialTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _open(widget.initialTarget!);
      });
    }
  }

  void _open(String target) {
    final nav = Navigator.of(context);
    switch (target) {
      case 'temperature':
      case 'thermometer':
        nav.push(MaterialPageRoute(
            builder: (_) => TemperatureScreen(
                repository: widget.repository, license: widget.license)));
      case 'cleaning':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                CleaningScreen(repository: widget.repository, license: widget.license)));
      case 'receipts':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                ReceiptsScreen(repository: widget.repository, license: widget.license)));
      case 'suppliers':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                SuppliersScreen(repository: widget.repository, license: widget.license)));
      case 'pest':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                PestsScreen(repository: widget.repository, license: widget.license)));
      case 'structure':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                StructuresScreen(repository: widget.repository, license: widget.license)));
      case 'nc':
        nav.push(MaterialPageRoute(
            builder: (_) => NonConformitiesScreen(
                repository: widget.repository, license: widget.license)));
      case 'waste':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                WasteScreen(repository: widget.repository, license: widget.license)));
      case 'cooking':
      case 'blast':
      case 'transport':
      case 'samples':
      case 'water':
      case 'recall':
      case 'cross':
        nav.push(MaterialPageRoute(builder: (_) => _moduleScreen(target)));
      case 'staff':
        nav.push(MaterialPageRoute(
            builder: (_) =>
                StaffScreen(repository: widget.repository, license: widget.license)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = LiveQuery<Map<String, int>>(
      repository: widget.repository,
      loader: _loadBadges,
      builder: (context, badges) {
        return ListView(
          padding: screenPadding(context, hasBottomBar: !widget.standalone),
          children: [
            if (!widget.standalone)
              PageHeader(
                title: 'Controlli',
                subtitle:
                    'Tutti i registri HACCP: tocca una voce per registrare o '
                    'consultare.',
              ),
            ...[
              ('temperature', 'Temperature', Icons.thermostat,
                  'Attrezzature e letture del giorno', 'temperature'),
              ('cleaning', 'Pulizie', Icons.cleaning_services_outlined,
                  'Piano e conferme', 'cleaning'),
              ('receipts', 'Merce in arrivo', Icons.local_shipping_outlined,
                  'Ricevimento e controlli fornitore', 'receipts'),
              ('thermometer', 'Verifica termometri',
                  Icons.device_thermostat_outlined, 'Scostamento e tolleranza', 'thermometer'),
              ('cooking', 'Cottura e rigenerazione',
                  Icons.outdoor_grill_outlined, 'Temperatura al cuore, olio (PR COT)', 'cooking'),
              ('blast', 'Abbattimento', Icons.ac_unit_outlined,
                  'Cicli positivi e negativi (PR ABB)', 'blast'),
              ('transport', 'Mantenimento e trasporto',
                  Icons.local_shipping_outlined, 'Catering e somministrazione (PR TRA/SOM)', 'transport'),
              ('samples', 'Pasto campione', Icons.science_outlined,
                  'Campioni 72 ore (PR CAMP 01)', 'samples'),
              ('water', 'Acqua e ghiaccio', Icons.water_drop_outlined,
                  'Analisi, filtri, ghiaccio (PR APO)', 'water'),
              ('pest', 'Infestanti', Icons.pest_control_outlined,
                  'Monitoraggio postazioni', 'pest'),
              ('structure', 'Strutture', Icons.foundation_outlined,
                  'Checklist semestrale', 'structure'),
              ('nc', 'Non conformit\u00E0', Icons.report_outlined,
                  'Problemi, azioni, chiusura', 'nc'),
              ('waste', 'Eliminazione prodotti', Icons.delete_outline,
                  'Registro smaltimenti', 'waste'),
              ('recall', 'Ritiro e richiamo', Icons.campaign_outlined,
                  'Lotti, destinatari, ASL (PR RIN)', 'recall'),
              ('cross', 'Contaminazione crociata',
                  Icons.cleaning_services_outlined,
                  'Attrezzature condivise (2022/C 355/01)', 'cross'),
            ].map(
              (entry) {
                final (key, title, icon, subtitle, target) = entry;
                final badge = badges[key] ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _open(target),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Icon(icon,
                                size: 28, color: theme.colorScheme.primary),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (badge > 0)
                              StatusPill(
                                text: '$badge',
                                type: key == 'nc'
                                    ? StatusType.danger
                                    : StatusType.warning,
                              ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right,
                                color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SectionTitle('Anagrafiche collegate'),
            _link('Fornitori', 'Registro, qualifica, NC ripetute', 'suppliers'),
            _link('Personale', 'Formazione e attestati alimentarista', 'staff'),
          ],
        );
      },
    );

    if (widget.standalone) {
      return FeatureScaffold(
        title: 'Controlli',
        scrollable: false,
        padding: EdgeInsets.zero,
        body: content,
      );
    }
    return content;
  }

  Widget _link(String title, String subtitle, String target) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: ListTile(
          onTap: () => _open(target),
          leading: Icon(Icons.chevron_right, color: theme.colorScheme.primary),
          title: Text(title,
              style:
                  theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(subtitle),
        ),
      ),
    );
  }

  /// Schermata modulo MGSA per chiave target, con i servizi della hub.
  Widget _moduleScreen(String target) {
    final repository = widget.repository;
    final license = widget.license;
    return switch (target) {
      'cooking' => CookingScreen(repository: repository, license: license),
      'blast' => BlastChillScreen(repository: repository, license: license),
      'transport' => TransportScreen(repository: repository, license: license),
      'samples' => SamplesScreen(repository: repository, license: license),
      'water' => WaterScreen(repository: repository, license: license),
      'recall' => RecallScreen(repository: repository, license: license),
      'cross' =>
        CrossContaminationScreen(repository: repository, license: license),
      _ => CookingScreen(repository: repository, license: license),
    };
  }

  Future<Map<String, int>> _loadBadges() async {
    final repository = widget.repository;
    final noReading = await repository.getEquipmentWithoutReadingToday();
    final tasks = await repository.getCleaningTasks();
    final openNc =
        (await repository.getNonConformities()).where((n) => n.isOpen).length;
    final equipment = await repository.getEquipment();
    final thermoOverdue =
        equipment.where((e) => e.thermoCheckOverdue).length;
    final lastPest = await repository.lastPestMonitoring();
    final pestOverdue = lastPest == null ||
            DateTime.now().difference(lastPest).inDays > 30
        ? 1
        : 0;

    return {
      'temperature': noReading.length,
      'cleaning': tasks
          .where((t) =>
              t.state == CleaningState.dueToday ||
              t.state == CleaningState.overdue)
          .length,
      'receipts': 0,
      'thermometer': thermoOverdue,
      'pest': pestOverdue,
      'structure': 0,
      'nc': openNc,
      'waste': 0,
    };
  }
}
