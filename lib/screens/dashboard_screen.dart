import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../widgets/common_widgets.dart';
import 'license_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    required this.repository,
    required this.license,
    required this.onOpenTarget,
    required this.onNavigate,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final ValueChanged<String> onOpenTarget;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<DashboardData>(
      repository: repository,
      loader: repository.getDashboard,
      builder: (context, data) {
        final company = data.company;
        final theme = Theme.of(context);
        final percent =
            data.totalCount == 0 ? 100 : (data.doneCount * 100 / data.totalCount).round();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            // Intestazione.
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        company.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        fmtLongDate(DateTime.now()),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => LicenseScreen(license: license),
                    ),
                  ),
                  child: StatusPill(
                    text: license.chipLabel,
                    type: license.canWrite
                        ? (license.trialActive
                            ? StatusType.info
                            : StatusType.success)
                        : StatusType.danger,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Card hero.
            _HeroCard(
              percent: percent,
              doneCount: data.doneCount,
              totalCount: data.totalCount,
              openNc: data.openNc,
            ),
            const SizedBox(height: 20),

            if (!company.isComplete)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _CompanyBanner(onOpenTarget: onOpenTarget),
              ),

            if (data.onboardingProgress < 100)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _SetupCard(
                  progress: data.onboardingProgress,
                  onOpenTarget: onOpenTarget,
                ),
              ),

            // Da fare ora.
            if (data.todos.isNotEmpty) ...[
              SectionTitle(
                'Da fare ora',
                trailing: data.todos.length > 1
                    ? Text(
                        '${data.todos.length} attivit\u00E0',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      )
                    : null,
              ),
              ...data.todos.take(6).map(
                    (todo) => TodoRow(
                      severity: todo.severity,
                      icon: _iconFor(todo.icon),
                      title: todo.title,
                      subtitle: todo.subtitle,
                      onTap: () => onOpenTarget(todo.target),
                    ),
                  ),
              const SizedBox(height: 8),
            ],

            // Azioni rapide.
            const SectionTitle('Azioni rapide'),
            GridView.count(
              crossAxisCount: MediaQuery.sizeOf(context).width >= 700 ? 3 : 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.55,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                QuickActionTile(
                  icon: Icons.thermostat,
                  label: 'Temperatura',
                  onTap: () => onOpenTarget('temperature'),
                ),
                QuickActionTile(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Pulizie',
                  onTap: () => onOpenTarget('cleaning'),
                ),
                QuickActionTile(
                  icon: Icons.local_shipping_outlined,
                  label: 'Merce in arrivo',
                  onTap: () => onOpenTarget('receipts'),
                ),
                QuickActionTile(
                  icon: Icons.add_box_outlined,
                  label: 'Nuovo lotto',
                  onTap: () => onNavigate(2),
                ),
                QuickActionTile(
                  icon: Icons.report_outlined,
                  label: 'Non conformit\u00E0',
                  onTap: () => onOpenTarget('nc'),
                ),
                QuickActionTile(
                  icon: Icons.picture_as_pdf_outlined,
                  label: 'Report PDF',
                  onTap: () => onNavigate(3),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  IconData _iconFor(String name) => switch (name) {
        'thermostat' => Icons.thermostat,
        'cleaning' => Icons.cleaning_services_outlined,
        'nc' => Icons.report_outlined,
        'staff' => Icons.badge_outlined,
        'thermometer_check' => Icons.device_thermostat_outlined,
        'pest' => Icons.pest_control_outlined,
        'structure' => Icons.foundation_outlined,
        'company' => Icons.store_outlined,
        'lot' => Icons.inventory_2_outlined,
        'sample' => Icons.science_outlined,
        'water' => Icons.water_drop_outlined,
        'culture' => Icons.history_edu_outlined,
        _ => Icons.task_alt_outlined,
      };
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.percent,
    required this.doneCount,
    required this.totalCount,
    required this.openNc,
  });

  final int percent;
  final int doneCount;
  final int totalCount;
  final int openNc;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    final theme = Theme.of(context);
    final pending = totalCount - doneCount;
    final message = openNc > 0
        ? '$openNc non conformit\u00E0 ${openNc == 1 ? 'aperta' : 'aperte'} da gestire'
        : pending > 0
            ? '$pending attivit\u00E0 da completare'
            : 'Tutto in regola';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [colors.heroStart, colors.heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          ProgressRing(
            percent: percent,
            child: Text(
              '$percent%',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.onHero,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Controlli di oggi',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onHero.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$doneCount su $totalCount completati',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colors.onHero,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      openNc > 0
                          ? Icons.warning_amber_rounded
                          : pending > 0
                              ? Icons.schedule
                              : Icons.check_circle_outline,
                      color: colors.onHero,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onHero,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.progress, required this.onOpenTarget});

  final int progress;
  final ValueChanged<String> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Completa la configurazione: $progress%',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: () => onOpenTarget('wizard'),
                  child: const Text('Riprendi'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyBanner extends StatelessWidget {
  const _CompanyBanner({required this.onOpenTarget});

  final ValueChanged<String> onOpenTarget;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    return Card(
      color: colors.infoBg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: colors.info),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Completa l\u2019anagrafica azienda: ragione sociale e '
                'responsabile HACCP servono per intestare i PDF.',
                style: TextStyle(
                  color: colors.info,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => onOpenTarget('company'),
              child: const Text('Apri'),
            ),
          ],
        ),
      ),
    );
  }
}
