import 'package:flutter/material.dart';

import '../repositories/haccp_repository.dart';
import '../services/backup_service.dart';
import '../services/license_service.dart';
import '../services/printer_service.dart';
import '../services/sync_service.dart';
import '../widgets/common_widgets.dart';
import 'checks_hub_screen.dart';
import 'company_screen.dart';
import 'dashboard_screen.dart';
import 'lots_screen.dart';
import 'more_screen.dart';
import 'nc/pests_screen.dart';
import 'nc/structures_screen.dart';
import 'non_conformities_screen.dart';
import 'modules/modules_screens.dart';
import 'modules/extra_screens.dart';
import 'onboarding/onboarding_screen.dart';
import 'reports_screen.dart';
import 'staff/staff_screen.dart';
import 'temperature/temperature_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.repository,
    required this.printerService,
    required this.license,
    required this.sync,
    required this.backup,
    required this.attachments,
    required this.reminders,
  });

  final HaccpRepository repository;
  final PrinterService printerService;
  final LicenseService license;
  final SyncService sync;
  final BackupService backup;
  final dynamic attachments;
  final dynamic reminders;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int index = 0;

  void _openTarget(String target) {
    final navigator = Navigator.of(context);
    switch (target) {
      case 'temperature':
      case 'thermometer':
        navigator.push(MaterialPageRoute(
          builder: (_) => TemperatureScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'cleaning':
        navigator.push(MaterialPageRoute(
          builder: (_) => ChecksHubScreen(
            repository: widget.repository,
            license: widget.license,
            initialTarget: 'cleaning',
            standalone: true,
          ),
        ));
      case 'nc':
        navigator.push(MaterialPageRoute(
          builder: (_) => NonConformitiesScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'staff':
        navigator.push(MaterialPageRoute(
          builder: (_) => StaffScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'pest':
        navigator.push(MaterialPageRoute(
          builder: (_) => PestsScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'structure':
        navigator.push(MaterialPageRoute(
          builder: (_) => StructuresScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'company':
        navigator.push(MaterialPageRoute(
          builder: (_) => CompanyScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'receipts':
        navigator.push(MaterialPageRoute(
          builder: (_) => ChecksHubScreen(
            repository: widget.repository,
            license: widget.license,
            initialTarget: 'receipts',
            standalone: true,
          ),
        ));
      case 'lots':
        setState(() => index = 2);
      case 'cooking':
        navigator.push(MaterialPageRoute(
          builder: (_) => CookingScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'blast':
        navigator.push(MaterialPageRoute(
          builder: (_) => BlastChillScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'transport':
        navigator.push(MaterialPageRoute(
          builder: (_) => TransportScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'samples':
        navigator.push(MaterialPageRoute(
          builder: (_) => SamplesScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'water':
        navigator.push(MaterialPageRoute(
          builder: (_) => WaterScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'recall':
        navigator.push(MaterialPageRoute(
          builder: (_) => RecallScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'culture':
        navigator.push(MaterialPageRoute(
          builder: (_) => CultureScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'cross':
        navigator.push(MaterialPageRoute(
          builder: (_) => CrossContaminationScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'donations':
        navigator.push(MaterialPageRoute(
          builder: (_) => DonationsScreen(
            repository: widget.repository,
            license: widget.license,
          ),
        ));
      case 'limits':
        navigator.push(MaterialPageRoute(
          builder: (_) => LimitsScreen(repository: widget.repository),
        ));
      case 'wizard':
        navigator.push(MaterialPageRoute(
          builder: (_) => OnboardingScreen(
            repository: widget.repository,
            license: widget.license,
            attachments: widget.attachments,
            reminders: widget.reminders,
            sync: widget.sync,
            onFinished: () {},
          ),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      DashboardScreen(
        repository: widget.repository,
        license: widget.license,
        onOpenTarget: _openTarget,
        onNavigate: (value) => setState(() => index = value),
      ),
      ChecksHubScreen(
        repository: widget.repository,
        license: widget.license,
      ),
      LotsScreen(
        repository: widget.repository,
        license: widget.license,
      ),
      ReportsScreen(repository: widget.repository, license: widget.license),
      MoreScreen(
        repository: widget.repository,
        license: widget.license,
        sync: widget.sync,
        backup: widget.backup,
        attachments: widget.attachments,
        reminders: widget.reminders,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        if (!wide) {
          return Scaffold(
            body: IndexedStack(index: index, children: screens),
            bottomNavigationBar: AppBottomBar(
              items: [
                AppNavItem(
                  label: 'Oggi',
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  badge: 0,
                ),
                AppNavItem(
                  label: 'Controlli',
                  icon: Icons.fact_check_outlined,
                  selectedIcon: Icons.fact_check,
                  badge: 0,
                ),
                AppNavItem(
                  label: 'Lotti',
                  icon: Icons.inventory_2_outlined,
                  selectedIcon: Icons.inventory_2,
                  badge: 0,
                ),
                AppNavItem(
                  label: 'Report',
                  icon: Icons.picture_as_pdf_outlined,
                  selectedIcon: Icons.picture_as_pdf,
                  badge: 0,
                ),
                AppNavItem(
                  label: 'Altro',
                  icon: Icons.menu_outlined,
                  selectedIcon: Icons.menu,
                  badge: 0,
                ),
              ],
              currentIndex: index,
              onSelected: (value) => setState(() => index = value),
            ),
          );
        }

        return Scaffold(
          body: Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (value) =>
                    setState(() => index = value),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.only(top: 16, bottom: 24),
                  child: CircleAvatar(
                    radius: 24,
                    child: Icon(Icons.verified_user_outlined),
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: Text('Oggi'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.fact_check_outlined),
                    selectedIcon: Icon(Icons.fact_check),
                    label: Text('Controlli'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    selectedIcon: Icon(Icons.inventory_2),
                    label: Text('Lotti'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.picture_as_pdf_outlined),
                    selectedIcon: Icon(Icons.picture_as_pdf),
                    label: Text('Report'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.menu_outlined),
                    selectedIcon: Icon(Icons.menu),
                    label: Text('Altro'),
                  ),
                ],
              ),
              VerticalDivider(
                width: 1,
                thickness: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: IndexedStack(index: index, children: screens)),
            ],
          ),
        );
      },
    );
  }
}
