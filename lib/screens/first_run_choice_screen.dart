import 'package:flutter/material.dart';

import '../widgets/common_widgets.dart';

/// Scelta al primo avvio (Prompt 12, §A): mostrata SOLO con onboarding
/// non completato, database vuoto e scelta non ancora fatta
/// (`first_run_choice_done`).
///
/// - **Nuova attività** (o il link "Più tardi"): prosegue col wizard.
/// - **Ripristina i miei dati**: apre il wizard di ripristino
///   (Google Drive / file dal telefono).
class FirstRunChoiceScreen extends StatelessWidget {
  const FirstRunChoiceScreen({
    super.key,
    required this.onNewActivity,
    required this.onRestore,
  });

  /// "Nuova attività" o "Più tardi": prosegue con la configurazione.
  final Future<void> Function() onNewActivity;

  /// "Ho già usato HACCPass: ripristina i miei dati".
  final Future<void> Function() onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: screenPadding(context, top: 40),
          children: [
            Icon(
              Icons.restaurant_menu_outlined,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              'Benvenuto in HACCPass',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'È la prima volta su questo telefono?',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _ChoiceCard(
              icon: Icons.add_business_outlined,
              title: 'Nuova attività',
              subtitle:
                  'Parto da zero: configurazione guidata di azienda, '
                  'attrezzature e piano di pulizia.',
              onPressed: onNewActivity,
            ),
            const SizedBox(height: 14),
            _ChoiceCard(
              icon: Icons.cloud_download_outlined,
              title: 'Ho già usato HACCPass',
              subtitle:
                  'Ripristina i miei dati da Google Drive o da un file di '
                  'backup: ritrovo registri e foto anche su un telefono '
                  'nuovo.',
              emphasized: true,
              onPressed: onRestore,
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: onNewActivity,
                child: const Text('Più tardi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: emphasized ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                icon,
                size: 34,
                color: emphasized
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: emphasized
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: emphasized
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.85)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: emphasized
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
