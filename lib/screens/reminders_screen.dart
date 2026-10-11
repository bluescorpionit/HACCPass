import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../repositories/haccp_repository.dart';
import '../services/reminder_service.dart';
import '../widgets/common_widgets.dart' show screenPadding;

/// Impostazioni → Promemoria (Prompt 18, §3): orari, stato onesto e
/// diagnostica (permessi, allarmi precisi, energia, prossimi promemoria
/// e prove immediata/tra 1 minuto).
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    super.key,
    required this.repository,
    required this.reminders,
  });

  final HaccpRepository repository;
  final ReminderService reminders;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool _loading = true;
  String? _note;

  String _morning = '';
  String _afternoon = '';
  String _cleaning = '';
  String _periodic = '';

  bool? _notificationsAllowed;
  bool? _exactAlarms;
  List<ReminderPending> _pending = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final morning =
        await widget.repository.getSetting('reminder_temperature_morning');
    final afternoon =
        await widget.repository.getSetting('reminder_temperature_afternoon');
    final cleaning = await widget.repository.getSetting('reminder_cleaning');
    final periodic = await widget.repository.getSetting('reminder_periodic');
    final allowed = await widget.reminders.notificationsAllowed();
    final exact = await widget.reminders.canScheduleExactNotifications();
    final pending = await widget.reminders.pendingOverview();
    if (!mounted) return;
    setState(() {
      _morning = morning;
      _afternoon = afternoon;
      _cleaning = cleaning;
      _periodic = periodic;
      _notificationsAllowed = allowed;
      _exactAlarms = exact;
      _pending = pending;
      _loading = false;
    });
  }

  Future<void> _saveAndReschedule() async {
    await widget.repository
        .setSetting('reminder_temperature_morning', _morning);
    await widget.repository
        .setSetting('reminder_temperature_afternoon', _afternoon);
    await widget.repository.setSetting('reminder_cleaning', _cleaning);
    await widget.repository.setSetting('reminder_periodic', _periodic);
    final result = await widget.reminders.rescheduleAll();
    if (!mounted) return;
    await _reload();
    if (!mounted) return;
    setState(() => _note = result.message);
  }

  Future<void> _pickTime(String key, String label) async {
    final current = switch (key) {
      'morning' => _morning,
      'afternoon' => _afternoon,
      _ => _cleaning,
    };
    final initial = _parseTime(current.isEmpty ? '09:00' : current);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: label,
    );
    if (picked == null) return;
    final value =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      switch (key) {
        case 'morning':
          _morning = value;
        case 'afternoon':
          _afternoon = value;
        default:
          _cleaning = value;
      }
    });
    await _saveAndReschedule();
  }

  TimeOfDay _parseTime(String value) {
    final parts = value.split(':');
    return TimeOfDay(
      hour: int.tryParse(parts.first) ?? 9,
      minute: parts.length > 1 ? (int.tryParse(parts.last) ?? 0) : 0,
    );
  }

  Future<void> _rescheduleOnly() async {
    final result = await widget.reminders.rescheduleAll();
    await _reload();
    if (!mounted) return;
    setState(() => _note = result.message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Promemoria')),
      body: ListView(
        padding: screenPadding(context, horizontal: 16),
        children: [
          _statusCard(theme),
          const SizedBox(height: 12),
          Text('Orari dei promemoria',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          _timeTile(theme, 'Controllo temperature (mattina)', _morning,
              () => _pickTime('morning', 'Controllo temperature (mattina)')),
          _timeTile(
              theme,
              'Controllo temperature (pomeriggio)',
              _afternoon,
              () =>
                  _pickTime('afternoon', 'Controllo temperature (pomeriggio)')),
          _timeTile(theme, 'Chiusura pulizie', _cleaning,
              () => _pickTime('cleaning', 'Chiusura pulizie')),
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verifiche periodiche (formazione, termometri, '
                    'infestanti, strutture)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final (value, label) in const [
                        ('', 'Disattivato'),
                        ('weekly', 'Settimanale, luned\u00EC 8:00'),
                        ('monthly', 'Mensile, giorno 1'),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: _periodic == value,
                          onSelected: (_) {
                            setState(() => _periodic = value);
                            _saveAndReschedule();
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  await widget.reminders.showTestNotification();
                  if (mounted) {
                    setState(() => _note =
                        'Notifica immediata inviata: se non compare, il '
                            'permesso \u00E8 negato o il canale \u00E8 silenziato.');
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Notifica immediata'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await widget.reminders.scheduleTestNotification();
                  if (mounted) {
                    setState(() => _note =
                        'Tra 1 minuto dovrebbe comparire una notifica. Se '
                            'questa NON arriva ma l\u2019immediata s\u00EC, il '
                            'problema \u00E8 la pianificazione o il risparmio '
                            'energetico, NON il permesso.');
                  }
                },
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Prova tra 1 minuto'),
              ),
            ],
          ),
          if (_note != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_note!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'I promemoria sono locali: nessun server, nessun dato inviato. '
            'Dopo il riavvio del telefono si ricreano da soli.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeTile(
    ThemeData theme,
    String label,
    String value,
    VoidCallback onTap,
  ) =>
      Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          title: Text(label),
          trailing: value.isEmpty
              ? TextButton(
                  onPressed: onTap,
                  child: const Text('Imposta ora'),
                )
              : TextButton(
                  onPressed: onTap,
                  child: Text(
                    value,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
          onTap: onTap,
        ),
      );

  Widget _statusCard(ThemeData theme) {
    if (_loading) {
      return const Card(
          child: Padding(
              padding: EdgeInsets.all(16), child: LinearProgressIndicator()));
    }
    final allowed = _notificationsAllowed ?? true;
    final exact = _exactAlarms ?? true;
    return Card(
      color: allowed ? null : theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stato dei promemoria',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _statusRow(
              theme,
              'Notifiche consentite',
              allowed ? 'S\u00EC' : 'No',
              allowed ? null : 'Apri impostazioni notifiche',
              allowed ? null : () => openAppSettings(),
            ),
            _statusRow(
              theme,
              'Allarmi precisi',
              exact ? 'S\u00EC' : 'No',
              exact
                  ? null
                  : 'Per orari precisi consenti "Sveglie e promemoria"',
              exact
                  ? null
                  : () async {
                      await widget.reminders.requestExactAlarmsPermission();
                      await _rescheduleOnly();
                    },
            ),
            _statusRow(
              theme,
              'Risparmio energetico',
              '',
              'Escludi HACCPass dall\u2019ottimizzazione batteria',
              () async {
                // Richiesta SOLO al tocco (Prompt 18, §3): alcuni
                // telefoni (Samsung, Xiaomi, Huawei, Oppo, OnePlus)
                // bloccano le notifiche in background.
                final status =
                    await Permission.ignoreBatteryOptimizations.status;
                if (status.isGranted) {
                  if (mounted) {
                    setState(() => _note =
                        'HACCPass \u00E8 gi\u00E0 esclusa dall\u2019ottimizzazione '
                            'batteria. Su Samsung/Xiaomi/Huawei/Oppo abilita '
                            'anche l\u2019avvio automatico.');
                  }
                  return;
                }
                await Permission.ignoreBatteryOptimizations.request();
              },
              hint: 'Alcuni telefoni bloccano le notifiche delle app in '
                  'background. Su Samsung, Xiaomi, Huawei, Oppo e OnePlus: '
                  'abilita l\u2019avvio automatico e disattiva il risparmio '
                  'energetico per HACCPass.',
            ),
            const Divider(height: 20),
            Text(
              'Promemoria programmati: ${_pending.length}',
              style: theme.textTheme.titleSmall,
            ),
            if (_pending.isEmpty)
              Text(
                'Nessuno: imposta almeno un orario qui sopra.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final pending in _pending)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined, size: 20),
                  title: Text(pending.title),
                  subtitle: Text('id ${pending.id}'),
                ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(
    ThemeData theme,
    String label,
    String value,
    String? buttonLabel,
    VoidCallback? onButton, {
    String? hint,
  }) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    value.isEmpty ? label : '$label: $value',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                if (buttonLabel != null && onButton != null)
                  TextButton(
                    onPressed: onButton,
                    child: Text(buttonLabel),
                  ),
              ],
            ),
            if (hint != null)
              Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      );
}
