import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/reminder_service.dart';

/// Prompt 18, §5: test con plugin finto (facade iniettabile).
/// - rescheduleAll non programma se le notifiche sono negate;
/// - modalità esatta solo se consentita, altrimenti ripiego inexact;
/// - verifiche periodiche weekly/monthly (prima mai programmate);
/// - _nextOccurrence: prima/dopo now, mezzanotte, ora legale (Roma).
void main() {
  tz.initializeTimeZones();
  final rome = tz.getLocation('Europe/Rome');
  tz.setLocalLocation(rome);

  late Map<String, String> settings;

  ReminderService buildService(
    _FakeFacade facade,
  ) =>
      ReminderService(
        repository: _SettingsRepository(settings),
        facade: facade,
      );

  setUp(() {
    settings = {
      'reminder_temperature_morning': '08:30',
      'reminder_temperature_afternoon': '17:00',
      'reminder_cleaning': '22:00',
      'reminder_periodic': '',
    };
  });

  group('rescheduleAll', () {
    test('notifiche negate: non programma nulla e lo dice', () async {
      final facade = _FakeFacade(notificationsEnabled: false);
      final result = await buildService(facade).rescheduleAll();

      expect(result.notificationsAllowed, isFalse);
      expect(result.scheduledCount, 0);
      expect(facade.scheduled, isEmpty,
          reason: 'nessuna zonedSchedule con permesso negato');
      expect(facade.cancelled, isNotEmpty,
          reason: 'gli eventuali allarmi precedenti vengono tolti');
      expect(result.message, contains('non consentite'));
    });

    test('programma i promemoria giornalieri con ripetizione oraria', () async {
      final facade = _FakeFacade(canExact: true);
      final result = await buildService(facade).rescheduleAll();

      expect(result.notificationsAllowed, isTrue);
      expect(result.scheduledCount, 3, reason: 'mattina, pomeriggio, pulizie');
      expect(facade.scheduled.length, 3);
      for (final call in facade.scheduled) {
        expect(call.match, DateTimeComponents.time,
            reason: 'ripetizione quotidiana alla stessa ora locale');
        expect(call.mode, AndroidScheduleMode.exactAllowWhileIdle,
            reason: 'esatto quando consentito');
        expect(call.when.isAfter(tz.TZDateTime.now(rome)), isTrue);
      }
      final ids = facade.scheduled.map((c) => c.id).toSet();
      expect(ids, {101, 102, 103});
    });

    test('allarmi esatti negati: ripiego inexact e esito esplicito', () async {
      final facade = _FakeFacade(canExact: false);
      final result = await buildService(facade).rescheduleAll();

      expect(result.exactAlarms, isFalse);
      for (final call in facade.scheduled) {
        expect(call.mode, AndroidScheduleMode.inexactAllowWhileIdle);
      }
      expect(result.message, contains('indicativi'));
    });

    test("verifiche periodiche 'weekly': ora programmate (regressione)",
        () async {
      // PRIMA: il valore 'weekly' era salvato ma _isValidTime falliva →
      // la zonedSchedule non veniva MAI chiamata.
      settings['reminder_periodic'] = 'weekly';
      final facade = _FakeFacade();
      final result = await buildService(facade).rescheduleAll();

      expect(result.scheduledCount, 4);
      final periodic = facade.scheduled.firstWhere((c) => c.id == 104);
      expect(periodic.match, DateTimeComponents.dayOfWeekAndTime);
      expect(periodic.when.weekday, DateTime.monday,
          reason: 'prossimo luned\u00EC');
      expect(periodic.when.hour, 8);
    });

    test("verifiche periodiche 'monthly': giorno 1 del mese successivo",
        () async {
      settings['reminder_periodic'] = 'monthly';
      final facade = _FakeFacade();
      await buildService(facade).rescheduleAll();

      final periodic = facade.scheduled.firstWhere((c) => c.id == 104);
      expect(periodic.match, DateTimeComponents.dayOfMonthAndTime);
      expect(periodic.when.day, 1);
    });

    test('orari vuoti o invalidi: nessuna pianificazione per quelli', () async {
      settings['reminder_temperature_morning'] = '';
      settings['reminder_cleaning'] = 'quando chiudo';
      final facade = _FakeFacade();
      final result = await buildService(facade).rescheduleAll();

      expect(result.scheduledCount, 1, reason: 'solo il pomeriggio valido');
    });

    test('diagnostica: prova tra 1 minuto stessa modalit\u00E0 dei veri',
        () async {
      final facade = _FakeFacade(canExact: false);
      final service = buildService(facade);
      await service.scheduleTestNotification();

      expect(facade.scheduled.length, 1);
      final call = facade.scheduled.single;
      expect(call.id, 198);
      expect(call.mode, AndroidScheduleMode.inexactAllowWhileIdle);
      final delta = call.when.difference(tz.TZDateTime.now(rome));
      expect(delta.inSeconds, greaterThanOrEqualTo(55));
      expect(delta.inSeconds, lessThan(70));
    });
  });

  group('nextOccurrence (Europe/Rome)', () {
    tz.TZDateTime at(String iso) => tz.TZDateTime.parse(rome, iso);

    test('ora futura di oggi', () {
      final now = at('2026-07-10 08:00:00');
      final next = ReminderService.nextOccurrence('08:30', now: now);
      expect(next.year, 2026);
      expect(next.month, 7);
      expect(next.day, 10);
      expect((next.hour, next.minute), (8, 30));
    });

    test('ora passata: domani alla stessa ora locale', () {
      final now = at('2026-07-10 09:00:00');
      final next = ReminderService.nextOccurrence('08:30', now: now);
      expect(next.day, 11);
      expect((next.hour, next.minute), (8, 30));
    });

    test('mezzanotte', () {
      final now = at('2026-07-10 00:05:00');
      final next = ReminderService.nextOccurrence('00:00', now: now);
      expect(next.day, 11, reason: 'mezzanotte appena passata');
      expect((next.hour, next.minute), (0, 0));
    });

    test(
        'ora legale (primavera): 02:30 del 29/03/2026 non esiste, '
        'viene risolta senza crash', () {
      final now = at('2026-03-28 23:30:00');
      final next = ReminderService.nextOccurrence('02:30', now: now);
      expect(next.day, 29);
      // 02:30 non esiste (orologo da 02:00 a 03:00): timezone risolve
      // all'ora valida successiva, stessa data, mai il giorno dopo.
      expect(next.isAfter(now), isTrue);
      expect(next.hour, greaterThanOrEqualTo(2));
      expect(next.month, 3);
    });

    test(
        'ora legale (autunno): dopo il cambio, il giorno dopo mantiene '
        'l\u2019ora locale (non slitta di un\u2019ora)', () {
      // 25/10/2026 alle 04:00 (gi\u00E0 in CET): promemoria 03:00 passato →
      // domani 26/10 alle 03:00 CET. Con il vecchio +24h assoluti
      // sarebbe diventato 02:00.
      final now = at('2026-10-25 04:00:00');
      final next = ReminderService.nextOccurrence('03:00', now: now);
      expect(next.day, 26);
      expect((next.hour, next.minute), (3, 0),
          reason: 'la costruzione per componenti mantiene l\u2019ora locale');
    });

    test('nextWeeklyOccurrence: prossimo luned\u00EC alle 8', () {
      // Domenica 11/10/2026 → luned\u00EC 12/10.
      final now = at('2026-10-11 12:00:00');
      final next = ReminderService.nextWeeklyOccurrence(now, location: rome);
      expect(next.weekday, DateTime.monday);
      expect(next.day, 12);
      expect(next.hour, 8);
    });

    test('nextWeeklyOccurrence: luned\u00EC gi\u00E0 passato → il prossimo',
        () {
      final now = at('2026-10-12 09:00:00'); // luned\u00EC dopo le 8
      final next = ReminderService.nextWeeklyOccurrence(now, location: rome);
      expect(next.day, 19);
    });

    test('nextMonthlyOccurrence: 1\u00B0 del mese successivo', () {
      final now = at('2026-12-15 10:00:00');
      final next = ReminderService.nextMonthlyOccurrence(now, location: rome);
      expect((next.year, next.month, next.day), (2027, 1, 1));
    });
  });

  group('diagnostica', () {
    test('pendingOverview elenca i promemoria in coda', () async {
      final facade = _FakeFacade()
        ..pendingList = const [
          ReminderPending(id: 101, title: 'Controllo temperature'),
        ];
      final service = buildService(facade);
      expect(await service.areEnabled(), isTrue);
      final pending = await service.pendingOverview();
      expect(pending.single.title, 'Controllo temperature');
    });

    test('chooseScheduleMode: esatto solo se consentito', () {
      expect(
        ReminderService.chooseScheduleMode(canExact: true),
        AndroidScheduleMode.exactAllowWhileIdle,
      );
      expect(
        ReminderService.chooseScheduleMode(canExact: false),
        AndroidScheduleMode.inexactAllowWhileIdle,
      );
    });
  });
}

/// Repository finto: solo getSetting/setSetting su mappa.
class _SettingsRepository implements HaccpRepository {
  _SettingsRepository(this.map);

  final Map<String, String> map;

  @override
  Future<String> getSetting(String key, {String fallback = ''}) async =>
      map[key] ?? '';

  @override
  Future<void> setSetting(String key, String value) async => map[key] = value;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('repository finto dei promemoria');
}

/// Facade finto del plugin (Prompt 18, §5).
class _FakeFacade extends NotificationsFacade {
  _FakeFacade({
    this.notificationsEnabled = true,
    this.canExact = true,
  });

  bool notificationsEnabled;
  bool canExact;
  List<ReminderPending> pendingList = const [];

  final scheduled = <({
    int id,
    String title,
    tz.TZDateTime when,
    AndroidScheduleMode mode,
    DateTimeComponents? match
  })>[];
  final cancelled = <int>[];
  final shown = <int>[];
  var exactPermissionRequests = 0;

  @override
  Future<void> initialize(InitializationSettings settings) async {}

  @override
  Future<bool> areNotificationsEnabled() async => notificationsEnabled;

  @override
  Future<bool> canScheduleExactNotifications() async => canExact;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> requestExactAlarmsPermission() async {
    exactPermissionRequests++;
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails details,
    required AndroidScheduleMode mode,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled.add((
      id: id,
      title: title,
      when: scheduledDate,
      mode: mode,
      match: matchDateTimeComponents,
    ));
  }

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required NotificationDetails details,
  }) async =>
      shown.add(id);

  @override
  Future<List<ReminderPending>> pendingOverview() async => pendingList;
}
