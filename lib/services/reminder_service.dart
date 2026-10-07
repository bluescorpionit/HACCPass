import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../repositories/haccp_repository.dart';

/// Promemoria locali (nessun server): controllo temperature, chiusura
/// pulizie, verifiche periodiche. Fuso orario del dispositivo
/// (Europe/Rome atteso).
class ReminderService {
  ReminderService({required this.repository});

  final HaccpRepository repository;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static const _temperatureMorningId = 101;
  static const _temperatureAfternoonId = 102;
  static const _cleaningId = 103;
  static const _periodicId = 104;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    }

    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      ),
    );
    _initialized = true;
  }

  /// Chiede il permesso notifiche al momento giusto (wizard, passo 10).
  /// Restituisce true se concesso.
  Future<bool> requestPermission() async {
    await initialize();
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        await ios.requestPermissions(alert: true, badge: true, sound: true);
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        // Android 13+: POST_NOTIFICATIONS. Se negato restituisce false:
        // l'app mostra come riattivarlo senza insistere.
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isValidTime(String value) =>
      RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value);

  tz.TZDateTime _nextOccurrence(String hhmm) {
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          // 'blue_haccp_promemoria': id storico del canale, NON cambiare
          // (cambiarlo creerebbe un secondo canale perdendo le
          // impostazioni di notifica scelte dall'utente).
          'blue_haccp_promemoria',
          'Promemoria HACCP',
          channelDescription:
              'Promemoria locali per controlli e registrazioni',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Riprogramma tutti i promemoria in base ai settings.
  /// Le chiavi `reminder_*` contengono l'orario "HH:mm" ('' = disattivo).
  Future<void> rescheduleAll() async {
    await initialize();
    await _cancelAll();

    final morning =
        await repository.getSetting('reminder_temperature_morning');
    final afternoon =
        await repository.getSetting('reminder_temperature_afternoon');
    final cleaning = await repository.getSetting('reminder_cleaning');
    final periodic = await repository.getSetting('reminder_periodic');

    if (_isValidTime(morning)) {
      await _plugin.zonedSchedule(
        id: _temperatureMorningId,
        title: 'Controllo temperature',
        body: '\u00C8 ora di registrare le temperature delle attrezzature.',
        scheduledDate: _nextOccurrence(morning),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    if (_isValidTime(afternoon)) {
      await _plugin.zonedSchedule(
        id: _temperatureAfternoonId,
        title: 'Controllo temperature',
        body: 'Ultimo giro di letture prima della chiusura.',
        scheduledDate: _nextOccurrence(afternoon),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    if (_isValidTime(cleaning)) {
      await _plugin.zonedSchedule(
        id: _cleaningId,
        title: 'Chiusura pulizie',
        body: 'Conferma le pulizie di oggi prima di chiudere.',
        scheduledDate: _nextOccurrence(cleaning),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
    if (_isValidTime(periodic)) {
      await _plugin.zonedSchedule(
        id: _periodicId,
        title: 'Verifiche periodiche',
        body: 'Controlla formazione, termometri, infestanti e strutture.',
        scheduledDate: _nextOccurrence(periodic),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }

  Future<void> _cancelAll() async {
    await _plugin.cancel(id: _temperatureMorningId);
    await _plugin.cancel(id: _temperatureAfternoonId);
    await _plugin.cancel(id: _cleaningId);
    await _plugin.cancel(id: _periodicId);
  }

  /// Notifica immediata di prova (wizard).
  Future<void> showTestNotification() async {
    await initialize();
    await _plugin.show(
      id: 199,
      title: 'Promemoria di prova',
      body: 'Cos\u00EC compariranno i promemoria di HACCPass.',
      notificationDetails: _details,
    );
  }

  /// True se i promemoria sono attivi su questo dispositivo.
  Future<bool> areEnabled() async {
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('ReminderService.areEnabled: $e');
      }
      return false;
    }
  }
}
