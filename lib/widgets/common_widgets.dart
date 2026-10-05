import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../repositories/haccp_repository.dart';

// -----------------------------------------------------------------------------
// Struttura pagina
// -----------------------------------------------------------------------------

/// Scaffold per le schermate aperte via `Navigator.push`: AppBar con titolo,
/// freccia indietro automatica, sfondo opaco dal tema e body in SafeArea.
/// Le tab della shell non lo usano (restano senza AppBar).
class FeatureScaffold extends StatelessWidget {
  const FeatureScaffold({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.floatingActionButton,
    this.actions,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 96),
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? floatingActionButton;
  final List<Widget>? actions;
  final EdgeInsetsGeometry padding;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = scrollable
        ? ListView(
            padding: padding,
            children: [
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              body,
            ],
          )
        : Padding(padding: padding, child: body);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(title),
        actions: actions,
        surfaceTintColor: Colors.transparent,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(child: content),
    );
  }
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Stato: sempre icona + testo
// -----------------------------------------------------------------------------

enum StatusType { success, warning, danger, info, neutral }

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.text,
    required this.type,
    this.icon,
    this.large = false,
  });

  final String text;
  final StatusType type;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    final (fg, bg, defaultIcon) = switch (type) {
      StatusType.success => (
          colors.success,
          colors.successBg,
          Icons.check_circle_outline
        ),
      StatusType.warning => (
          colors.warning,
          colors.warningBg,
          Icons.warning_amber_outlined
        ),
      StatusType.danger => (colors.danger, colors.dangerBg, Icons.error_outline),
      StatusType.info => (colors.info, colors.infoBg, Icons.info_outline),
      StatusType.neutral => (
          Theme.of(context).colorScheme.onSurfaceVariant,
          Theme.of(context).colorScheme.surfaceContainerHighest,
          Icons.circle_outlined
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 12 : 10,
        vertical: large ? 7 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? defaultIcon, size: large ? 20 : 16, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w700,
                fontSize: large ? 14 : 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Tile e bottoni
// -----------------------------------------------------------------------------

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 32, color: accent),
              const Spacer(),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.accentColor,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = accentColor ?? theme.colorScheme.primary;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 32, color: accent),
              const SizedBox(height: 10),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Riga "Da fare ora": striscia colorata, icona, titolo, sottotitolo, "Vai".
class TodoRow extends StatelessWidget {
  const TodoRow({
    super.key,
    required this.severity,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final int severity;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    final theme = Theme.of(context);
    final (stripe, fg) = switch (severity) {
      0 => (colors.danger, colors.danger),
      1 => (colors.warning, colors.warning),
      _ => (colors.info, colors.info),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 5, decoration: BoxDecoration(
                color: stripe,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(20),
                ),
              )),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  child: Row(
                    children: [
                      Icon(icon, color: fg, size: 26),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right,
                          color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Form
// -----------------------------------------------------------------------------

/// Bottom sheet riutilizzabile con titolo, contenuto scorrevole e bottone di
/// salvataggio sempre visibile sopra la tastiera.
Future<T?> showFormSheet<T>({
  required BuildContext context,
  required String title,
  required WidgetBuilder builder,
  required String saveLabel,
  required ValueGetter<bool> onSave,
  IconData saveIcon = Icons.check,
}) {
  final theme = Theme.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  title,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: builder(sheetContext),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                child: FilledButton.icon(
                  onPressed: () {
                    if (onSave()) Navigator.pop(sheetContext, true);
                  },
                  icon: Icon(saveIcon),
                  label: Text(saveLabel),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Riga di chip di scelta (più rapida dei dropdown).
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    super.key,
    required this.options,
    this.selected,
    this.onSelected,
    this.enabled = true,
  });

  final List<(T, String)> options;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChipX(
            label: label,
            selected: selected == value,
            onSelected: enabled
                ? (v) {
                    if (v) onSelected?.call(value);
                  }
                : null,
          ),
      ],
    );
  }
}

/// Variante semantica del chip: colore del selezionato legato all'esito
/// (success/danger) invece che al generico secondaryContainer. Le coppie
/// colore/testo-sfondo rispettano 4.5:1 in entrambi i temi.
enum ChipSemantic { neutral, success, danger }

Widget _semanticChipTheme(
  BuildContext context,
  ChipSemantic semantic, {
  required Widget child,
}) {
  if (semantic == ChipSemantic.neutral) return child;

  final theme = Theme.of(context);
  final colors = context.haccpColors;
  final (selectedBg, selectedFg) = switch (semantic) {
    ChipSemantic.success => (colors.successBg, colors.success),
    ChipSemantic.danger => (colors.dangerBg, colors.danger),
    _ => (
        theme.colorScheme.secondaryContainer,
        theme.colorScheme.onSecondaryContainer
      ),
  };

  final baseLabel = theme.chipTheme.labelStyle ?? const TextStyle();
  final chip = theme.chipTheme.copyWith(
    selectedColor: selectedBg,
    labelStyle: baseLabel.copyWith(
      color: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return theme.colorScheme.onSurface.withValues(alpha: 0.70);
        }
        if (states.contains(WidgetState.selected)) {
          return selectedFg;
        }
        return theme.colorScheme.onSurface;
      }),
    ),
    checkmarkColor: selectedFg,
    side: BorderSide(color: selectedFg, width: 1.2),
  );
  return Theme(data: theme.copyWith(chipTheme: chip), child: child);
}

/// [ChoiceChip] con stile unico dal tema e opzionale semantica.
/// Il colore del testo non viene mai impostato dall'esterno: dipende dallo
/// stato (selezionato o no) e dal tema attivo.
class ChoiceChipX extends StatelessWidget {
  const ChoiceChipX({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.semantic = ChipSemantic.neutral,
    this.leading,
    this.showCheckmark = true,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final ChipSemantic semantic;
  final Widget? leading;
  final bool showCheckmark;

  @override
  Widget build(BuildContext context) {
    return _semanticChipTheme(
      context,
      semantic,
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: showCheckmark,
        avatar: leading,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

/// [FilterChip] con lo stesso stile unico di [ChoiceChipX].
class FilterChipX extends StatelessWidget {
  const FilterChipX({
    super.key,
    required this.label,
    required this.selected,
    this.onSelected,
    this.semantic = ChipSemantic.neutral,
    this.leading,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final ChipSemantic semantic;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return _semanticChipTheme(
      context,
      semantic,
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelected,
        checkmarkColor: Theme.of(context).chipTheme.checkmarkColor,
        avatar: leading,
        materialTapTargetSize: MaterialTapTargetSize.padded,
      ),
    );
  }
}

/// Campo data tocco: apre il date picker.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.allowClear = false,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LabeledField(
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: firstDate ?? DateTime(2000),
            lastDate: lastDate ?? DateTime.now().add(const Duration(days: 3650)),
            locale: const Locale('it', 'IT'),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            suffixIcon: value != null && allowClear
                ? IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => onChanged(null),
                  )
                : const Icon(Icons.calendar_month),
          ),
          child: Text(
            value == null
                ? 'Non impostata'
                : '${value!.day.toString().padLeft(2, '0')}/'
                    '${value!.month.toString().padLeft(2, '0')}/${value!.year}',
            style: TextStyle(
              color: value == null
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// Indicatore di conformità in tempo reale per il campo temperatura.
class ComplianceIndicator extends StatelessWidget {
  const ComplianceIndicator({
    super.key,
    required this.compliant,
    required this.hasValue,
  });

  final bool compliant;
  final bool hasValue;

  @override
  Widget build(BuildContext context) {
    if (!hasValue) return const SizedBox.shrink();
    return StatusPill(
      text: compliant ? 'Conforme' : 'Fuori limite',
      type: compliant ? StatusType.success : StatusType.danger,
      large: true,
    );
  }
}

// -----------------------------------------------------------------------------
// LiveQuery: si aggiorna quando il repository cambia
// -----------------------------------------------------------------------------

/// Carica [loader] e ricarica a ogni revisione del repository.
class LiveQuery<T> extends StatefulWidget {
  const LiveQuery({
    super.key,
    required this.repository,
    required this.loader,
    required this.builder,
  });

  final HaccpRepository repository;
  final Future<T> Function() loader;
  final Widget Function(BuildContext, T) builder;

  @override
  State<LiveQuery<T>> createState() => _LiveQueryState<T>();
}

class _LiveQueryState<T> extends State<LiveQuery<T>> {
  Future<T>? _future;
  var _revision = -1;

  @override
  void initState() {
    super.initState();
    _future = widget.loader();
    _revision = widget.repository.revision.value;
    widget.repository.revision.addListener(_onChange);
  }

  void _onChange() {
    if (!mounted) return;
    if (widget.repository.revision.value == _revision) return;
    _revision = widget.repository.revision.value;
    setState(() => _future = widget.loader());
  }

  @override
  void dispose() {
    widget.repository.revision.removeListener(_onChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Errore: ${snapshot.error}'));
        }
        return widget.builder(context, snapshot.data as T);
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Barra di navigazione inferiore custom
// -----------------------------------------------------------------------------

class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.badge,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final int badge;
}

class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelected,
  });

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(child: _buildItem(context, items[i], i)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, AppNavItem item, int index) {
    final theme = Theme.of(context);
    final selected = index == currentIndex;
    final fg = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: () => onSelected(index),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  selected ? item.selectedIcon : item.icon,
                  size: 26,
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : fg,
                ),
              ),
              if (item.badge > 0)
                Positioned(
                  right: 6,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      item.badge > 9 ? '9+' : '${item.badge}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Grafico a linee con banda dei limiti
// -----------------------------------------------------------------------------

class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.points,
    this.minLimit,
    this.maxLimit,
    this.height = 160,
  });

  final List<(DateTime, double)> points;
  final double? minLimit;
  final double? maxLimit;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          points: points,
          minLimit: minLimit,
          maxLimit: maxLimit,
          lineColor: Theme.of(context).colorScheme.primary,
          limitColor: colors.danger.withValues(alpha: 0.7),
          bandColor: colors.success.withValues(alpha: 0.10),
          labelStyle: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.points,
    required this.minLimit,
    required this.maxLimit,
    required this.lineColor,
    required this.limitColor,
    required this.bandColor,
    required this.labelStyle,
  });

  final List<(DateTime, double)> points;
  final double? minLimit;
  final double? maxLimit;
  final Color lineColor;
  final Color limitColor;
  final Color bandColor;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 34.0;
    final chart = Rect.fromLTWH(leftPad, 6, size.width - leftPad - 6,
        size.height - 18);

    if (points.isEmpty) {
      final tp = TextPainter(
        text: TextSpan(text: 'Nessun dato', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, size.height / 2));
      return;
    }

    final values = points.map((p) => p.$2).toList();
    var lo = points.map((p) => p.$2).reduce((a, b) => a < b ? a : b);
    var hi = values.reduce((a, b) => a > b ? a : b);
    if (minLimit != null) {
      lo = lo < minLimit! ? lo : minLimit!;
      hi = hi > minLimit! ? hi : minLimit!;
    }
    if (maxLimit != null) {
      lo = lo < maxLimit! ? lo : maxLimit!;
      hi = hi > maxLimit! ? hi : maxLimit!;
    }
    final margin = (hi - lo).abs() < 1 ? 2.0 : (hi - lo).abs() * 0.12;
    lo -= margin;
    hi += margin;

    double y(double v) => chart.bottom - (v - lo) / (hi - lo) * chart.height;
    double x(int i) =>
        chart.left + (points.length == 1
            ? chart.width / 2
            : i / (points.length - 1) * chart.width);

    // Banda dei limiti.
    if (minLimit != null && maxLimit != null) {
      final bandRect = Rect.fromLTRB(
        chart.left,
        y(maxLimit!),
        chart.right,
        y(minLimit!),
      );
      canvas.drawRect(bandRect, Paint()..color = bandColor);
      canvas.drawLine(
        Offset(chart.left, y(maxLimit!)),
        Offset(chart.right, y(maxLimit!)),
        Paint()
          ..color = limitColor
          ..strokeWidth = 1,
      );
      canvas.drawLine(
        Offset(chart.left, y(minLimit!)),
        Offset(chart.right, y(minLimit!)),
        Paint()
          ..color = limitColor
          ..strokeWidth = 1,
      );
      _label(canvas, '${maxLimit!.toStringAsFixed(0)}\u00B0',
          Offset(2, y(maxLimit!) - 7));
      _label(canvas, '${minLimit!.toStringAsFixed(0)}\u00B0',
          Offset(2, y(minLimit!) - 7));
    }

    // Linea.
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final offset = Offset(x(i), y(points[i].$2));
      if (i == 0) {
        path.moveTo(offset.dx, offset.dy);
      } else {
        path.lineTo(offset.dx, offset.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke,
    );

    // Punti (fuori limite in rosso).
    for (var i = 0; i < points.length; i++) {
      final v = points[i].$2;
      final out = (minLimit != null && v < minLimit!) ||
          (maxLimit != null && v > maxLimit!);
      canvas.drawCircle(
        Offset(x(i), y(v)),
        3,
        Paint()..color = out ? limitColor : lineColor,
      );
    }

    // Etichetta ultimo valore.
    final last = points.last;
    _label(
      canvas,
      '${last.$2.toStringAsFixed(1)}\u00B0',
      Offset(
        (x(points.length - 1) - 28).clamp(chart.left, size.width - 40),
        y(last.$2) - 16,
      ),
    );
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.minLimit != minLimit ||
      oldDelegate.maxLimit != maxLimit;
}

// -----------------------------------------------------------------------------
// Anello di avanzamento custom
// -----------------------------------------------------------------------------

class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.percent,
    required this.child,
    this.size = 120,
  });

  final int percent;
  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          percent: percent.clamp(0, 100),
          color: Colors.white.withValues(alpha: 0.9),
          trackColor: Colors.white.withValues(alpha: 0.25),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percent,
    required this.color,
    required this.trackColor,
  });

  final int percent;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 8;
    const startAngle = -90.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = trackColor,
    );

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle * 3.14159 / 180,
      percent / 100 * 2 * 3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.percent != percent;
}
