import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../repositories/haccp_repository.dart';

/// Esito della riprogrammazione (Prompt 18, §2): mai fingere che i
/// promemoria siano attivi se non lo sono.
class ReminderScheduleResult {
  const ReminderScheduleResult({
    required this.notificationsAllowed,
    required this.scheduledCount,
    required this.exactAlarms,
  });

  /// false se le notifiche sono negate/canale spento: in quel caso non
  /// si programma nulla.
  final bool notificationsAllowed;

  /// Quanti promemoria sono stati programmati.
  final int scheduledCount;

  /// true se si è potuto usare l'allarme esatto, false se ripiego
  /// inexact (ritardi possibili in Doze/risparmio energetico).
  final bool exactAlarms;

  String get message => !notificationsAllowed
      ? 'Notifiche non consentite: attivale dalle impostazioni per '
          'ricevere i promemoria.'
      : scheduledCount == 0
          ? 'Nessun promemoria attivo: imposta almeno un orario.'
          : '$scheduledCount promemoria programmati'
              '${exactAlarms ? ' (orari precisi)' : ' (orari indicativi: '
                  'consenti "Sveglie e promemoria" per la precisione)'}';
}

/// Prossimo promemoria in coda (diagnostica della schermata).
class ReminderPending {
  const ReminderPending({required this.id, required this.title});

  final int id;
  final String title;
}

/// Facade sottile sul plugin delle notifiche (Prompt 18, §5): TUTTO il
/// plugin passa da qui, così i test iniettano una versione fintа con
/// risposte configurabili e registrazione delle chiamate.
class NotificationsFacade {
  NotificationsFacade({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize(InitializationSettings settings) =>
      _plugin.initialize(settings: settings);

  /// Permesso notifiche concesso? (Android: app + canale attivo;
  /// iOS: checkPermissions; desktop: true).
  Future<bool> areNotificationsEnabled() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        final permissions = await ios.checkPermissions();
        return permissions?.isEnabled ?? true;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  /// Allarmi esatti consentiti (Android 12+)? Su iOS/desktop true.
  Future<bool> canScheduleExactNotifications() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      return await android.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Apre la pagina di sistema "Sveglie e promemoria" (Android 12+):
  /// MAI all'avvio, solo dalla schermata Promemoria.
  Future<void> requestExactAlarmsPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestExactAlarmsPermission();
    } catch (_) {}
  }

  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
    DateTimeComponents? matchDateTimeComponents,
  }) =>
      _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: details,
        androidScheduleMode: mode,
        matchDateTimeComponents: matchDateTimeComponents,
      );

  /// Permesso notifiche (Android 13+ POST_NOTIFICATIONS / iOS): se
  /// negato restituisce false, l'app mostra come riattivarlo.
  Future<bool> requestPermission() async {
    try {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        await ios.requestPermissions(alert: true, badge: true, sound: true);
      }
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        final granted = await android.requestNotificationsPermission();
        return granted ?? false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel(int id) => _plugin.cancel(id: id);

  Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
  }) =>
      _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
      );

  Future<List<ReminderPending>> pendingOverview() async {
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final request in requests)
        ReminderPending(
          id: request.id,
          title: request.title ?? '',
        ),
    ];
  }
}

/// Promemoria locali (nessun server): controllo temperature, chiusura
/// pulizie, verifiche periodiche. Fuso orario del dispositivo
/// (Europe/Rome atteso).
///
/// Prompt 18: allarmi esatti con ripiego quando consentiti,
/// riprogrammazione al resume (fuso/ora legale), verifiche periodiche
/// settimanali/mensili (prima il valore 'weekly'/'monthly' era salvato
/// ma MAI programmato), diagnostica onesta.
class ReminderService {
  ReminderService({required this.repository, NotificationsFacade? facade})
      : _facade = facade ?? NotificationsFacade();

  final HaccpRepository repository;
  final NotificationsFacade _facade;

  bool _initialized = false;

  static const _temperatureMorningId = 101;
  static const _temperatureAfternoonId = 102;
  static const _cleaningId = 103;
  static const _periodicId = 104;
  static const _testScheduledId = 198;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      tz.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _facade.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );
    _initialized = true;
  }

  /// Chiede il permesso notifiche al momento giusto (wizard, passo 10).
  /// Restituisce true se concesso.
  Future<bool> requestPermission() async {
    await initialize();
    return _facade.requestPermission();
  }

  bool _isValidTime(String value) => RegExp(r'^\d{1,2}:\d{2}$').hasMatch(value);

  /// Prossima occorrenza giornaliera di [hhmm] (ora locale), con
  /// costruzione per componenti (DST-safe: il +24h poteva slittare
  /// di un'ora nel giorno del cambio ora).
  @visibleForTesting
  static tz.TZDateTime nextOccurrence(
    String hhmm, {
    required tz.TZDateTime now,
    tz.Location? location,
  }) {
    final loc = location ?? tz.local;
    final parts = hhmm.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    var scheduled = tz.TZDateTime(
      loc,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      // Giorno successivo costruito per componenti: il fuso/ora legale
      // vengono ricalcolati sulla nuova data.
      scheduled = tz.TZDateTime(
        loc,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return scheduled;
  }

  /// Prossimo lunedì alle 08:00 (verifiche periodiche settimanali).
  @visibleForTesting
  static tz.TZDateTime nextWeeklyOccurrence(
    tz.TZDateTime now, {
    tz.Location? location,
  }) {
    final loc = location ?? tz.local;
    var candidate = tz.TZDateTime(
      loc,
      now.year,
      now.month,
      now.day,
      8,
    );
    var daysAhead = (DateTime.monday - candidate.weekday) % 7;
    if (daysAhead == 0 && !candidate.isAfter(now)) {
      daysAhead = 7;
    }
    return tz.TZDateTime(
      loc,
      now.year,
      now.month,
      now.day + daysAhead,
      8,
    );
  }

  /// Primo giorno del mese successivo alle 08:00 (verifiche mensili).
  @visibleForTesting
  static tz.TZDateTime nextMonthlyOccurrence(
    tz.TZDateTime now, {
    tz.Location? location,
  }) {
    final loc = location ?? tz.local;
    final year = now.month == 12 ? now.year + 1 : now.year;
    final month = now.month == 12 ? 1 : now.month + 1;
    return tz.TZDateTime(loc, year, month, 1, 8);
  }

  /// Modalità di pianificazione (Prompt 18, §2): ESATTA solo se
  /// consentita, altrimenti ripiego inexact.
  @visibleForTesting
  static AndroidScheduleMode chooseScheduleMode({required bool canExact}) =>
      canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          // 'blue_haccp_promemoria': id storico del canale, NON cambiare
          // (cambiarlo creerebbe un secondo canale perdendo le
          // impostazioni di notifica scelte dall'utente).
          'blue_haccp_promemoria',
          'Promemoria HACCP',
          channelDescription: 'Promemoria locali per controlli e registrazioni',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  /// Riprogramma tutti i promemoria in base ai settings.
  /// Le chiavi `reminder_*` contengono l'orario "HH:mm" ('' = disattivo)
  /// e `reminder_periodic` vale '' | 'weekly' | 'monthly'.
  ///
  /// Prompt 18, §2: (a) se le notifiche non sono consentite NON
  /// programma nulla e lo dice; (b) restituisce quanti promemoria ha
  /// programmato; (c) usa l'allarme esatto quando consentito.
  Future<ReminderScheduleResult> rescheduleAll() async {
    await initialize();

    final allowed = await notificationsAllowed();
    if (!allowed) {
      await _cancelAll();
      return const ReminderScheduleResult(
        notificationsAllowed: false,
        scheduledCount: 0,
        exactAlarms: false,
      );
    }
    final canExact = await _facade.canScheduleExactNotifications();
    final mode = chooseScheduleMode(canExact: canExact);

    await _cancelAll();
    var scheduled = 0;

    final morning = await repository.getSetting('reminder_temperature_morning');
    final afternoon =
        await repository.getSetting('reminder_temperature_afternoon');
    final cleaning = await repository.getSetting('reminder_cleaning');
    final periodic = await repository.getSetting('reminder_periodic');
    final now = tz.TZDateTime.now(tz.local);

    Future<void> scheduleDaily(int id, String hhmm, String body) async {
      await _facade.zonedSchedule(
        id: id,
        title: 'Controllo temperature',
        body: body,
        scheduledDate: nextOccurrence(hhmm, now: now),
        details: _details,
        mode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      scheduled++;
    }

    if (_isValidTime(morning)) {
      await scheduleDaily(
        _temperatureMorningId,
        morning,
        '\u00C8 ora di registrare le temperature delle attrezzature.',
      );
    }
    if (_isValidTime(afternoon)) {
      await scheduleDaily(
        _temperatureAfternoonId,
        afternoon,
        'Ultimo giro di letture prima della chiusura.',
      );
    }
    if (_isValidTime(cleaning)) {
      await _facade.zonedSchedule(
        id: _cleaningId,
        title: 'Chiusura pulizie',
        body: 'Conferma le pulizie di oggi prima di chiudere.',
        scheduledDate: nextOccurrence(cleaning, now: now),
        details: _details,
        mode: mode,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      scheduled++;
    }

    // Verifiche periodiche: PRIMA il wizard salvava 'weekly'/'monthly'
    // ma il servizio le ignorava (accettava solo "HH:mm"): mai
    // programmate (Prompt 18, diagnosi).
    if (periodic == 'weekly') {
      await _facade.zonedSchedule(
        id: _periodicId,
        title: 'Verifiche periodiche',
        body: 'Controlla formazione, termometri, infestanti e strutture.',
        scheduledDate: nextWeeklyOccurrence(now),
        details: _details,
        mode: mode,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      scheduled++;
    } else if (periodic == 'monthly') {
      await _facade.zonedSchedule(
        id: _periodicId,
        title: 'Verifiche periodiche',
        body: 'Controlla formazione, termometri, infestanti e strutture.',
        scheduledDate: nextMonthlyOccurrence(now),
        details: _details,
        mode: mode,
        matchDateTimeComponents: DateTimeComponents.dayOfMonthAndTime,
      );
      scheduled++;
    }

    return ReminderScheduleResult(
      notificationsAllowed: true,
      scheduledCount: scheduled,
      exactAlarms: canExact,
    );
  }

  /// Notifiche consentite su questo dispositivo (app e, su Android,
  /// permesso di sistema; il plugin non espone lo stato del canale
  /// singolo: se l'utente ha silenziato SOLO il canale il promemoria
  /// non suona ma qui risulta attivo — limitare documentato in
  /// docs/promemoria.md).
  Future<bool> notificationsAllowed() async {
    await initialize();
    return _facade.areNotificationsEnabled();
  }

  /// Allarmi esatti disponibili (Android 12+).
  Future<bool> canScheduleExactNotifications() async {
    await initialize();
    return _facade.canScheduleExactNotifications();
  }

  /// Pulsante "Per orari precisi" della schermata Promemoria.
  Future<void> requestExactAlarmsPermission() async {
    await initialize();
    await _facade.requestExactAlarmsPermission();
  }

  Future<void> _cancelAll() async {
    await _facade.cancel(_temperatureMorningId);
    await _facade.cancel(_temperatureAfternoonId);
    await _facade.cancel(_cleaningId);
    await _facade.cancel(_periodicId);
  }

  /// Notifica immediata di prova (wizard / diagnostica).
  Future<void> showTestNotification() async {
    await initialize();
    await _facade.show(
      id: 199,
      title: 'Promemoria di prova',
      body: 'Cos\u00EC compariranno i promemoria di HACCPass.',
      details: _details,
    );
  }

  /// "Prova una notifica tra 1 minuto" (Prompt 18, §3): stessa canale e
  /// modalità dei promemoria veri. Se questa NON arriva e l'immediata
  /// sì, il problema è la pianificazione/energia e non il permesso.
  Future<void> scheduleTestNotification(
      {Duration delay = const Duration(minutes: 1)}) async {
    await initialize();
    final canExact = await _facade.canScheduleExactNotifications();
    await _facade.zonedSchedule(
      id: _testScheduledId,
      title: 'Promemoria di prova (pianificato)',
      body: 'Se questa arriva dopo ~1 minuto la pianificazione funziona.',
      scheduledDate: tz.TZDateTime.now(tz.local).add(delay),
      details: _details,
      mode: chooseScheduleMode(canExact: canExact),
    );
  }

  /// Elenco dei promemoria in coda (diagnostica).
  Future<List<ReminderPending>> pendingOverview() async {
    await initialize();
    return _facade.pendingOverview();
  }

  /// True se i promemoria sono attivi su questo dispositivo.
  Future<bool> areEnabled() async {
    try {
      final pending = await pendingOverview();
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
