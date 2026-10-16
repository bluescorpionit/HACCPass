import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/license/app_integrity.dart';
import 'package:haccpass/core/license/trial_anchor.dart';

/// Storage in memoria per i test dell'ancora.
class MemoryTrialAnchorStorage implements TrialAnchorStorage {
  String? value;
  int writes = 0;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async {
    value = v;
    writes++;
  }

  @override
  Future<void> clear() async => value = null;
}

void main() {
  const secret = 'test-secret-123';

  group('AppIntegrity.anchorSecret (wiring BH_ANCHOR_SECRET)', () {
    // Attivo solo quando il test gira con i dart-define attesi
    // (verifica del Prompt 13):
    //   flutter test test/trial_anchor_test.dart \
    //     --dart-define=BH_ANCHOR_SECRET=test-anchor \
    //     --dart-define=EXPECTED_ANCHOR=test-anchor
    // e per l'alias storico:
    //   flutter test test/trial_anchor_test.dart \
    //     --dart-define=BH_LICENSE_SECRET=test-legacy \
    //     --dart-define=EXPECTED_ANCHOR=test-legacy
    test('il valore arriva da BH_ANCHOR_SECRET o dall\u2019alias', () {
      const expected = String.fromEnvironment('EXPECTED_ANCHOR');
      if (expected.isEmpty) return; // run normale: nessun wiring da verificare
      expect(AppIntegrity.anchorSecret, expected);
    });
  });

  TrialAnchor anchor(MemoryTrialAnchorStorage storage,
          {DateTime Function()? now}) =>
      TrialAnchor(secret: secret, storage: storage, now: now);

  group('TrialAnchor', () {
    test('prima installazione: la prova inizia adesso', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      final result =
          await anchor(storage, now: () => t0).synchronize();

      expect(result.firstInstall, isTrue);
      expect(result.start, t0);
      expect(result.clockTampered, isFalse);
      expect(result.anchorAltered, isFalse);
      // L'ancora viene scritta subito.
      expect(storage.value, isNotNull);
    });

    test('riapertura: la data di inizio non cambia', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();

      final result = await anchor(storage, now: () => t0.add(const Duration(days: 3)))
          .synchronize(databaseStart: t0);

      expect(result.start, t0);
      expect(result.firstInstall, isFalse);
      expect(result.clockTampered, isFalse);
    });

    test('reinstallazione simulata: database cancellato, ancora presente',
        () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();

      // Il database è vuoto (reinstallazione senza ripristino del db):
      // l'ancora sopravvive e la prova NON riparte da 14 giorni.
      final result = await anchor(storage, now: () => t0.add(const Duration(days: 2)))
          .synchronize(databaseStart: null);

      expect(result.start.isAtSameMomentAs(t0), isTrue);
      expect(result.firstInstall, isFalse);
    });

    test('MAC alterato: trattato come assente e riscritto', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();

      // Manomissione: la data viene spostata avanti senza ricalcolare il
      // MAC (tentativo di rifare la prova).
      final map = jsonDecode(storage.value!) as Map<String, dynamic>;
      map['start'] = DateTime(2026, 10, 20).toUtc().toIso8601String();
      storage.value = jsonEncode(map);

      final result = await anchor(storage, now: () => t0.add(const Duration(days: 1)))
          .synchronize(databaseStart: null);

      expect(result.anchorAltered, isTrue);
      // Assente = la prova riparte... a meno che il database non abbia la
      // data. Qui il database è vuoto: nuova data.
      expect(result.firstInstall, isTrue);
      // L'ancora viene riscritta con contenuto valido.
      final rewritten = await anchor(storage, now: () => t0.add(const Duration(days: 2)))
          .synchronize(databaseStart: result.start);
      expect(rewritten.anchorAltered, isFalse);
      expect(rewritten.start, result.start);
    });

    test('MAC alterato ma database valido: vince il database', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();
      final map = jsonDecode(storage.value!) as Map<String, dynamic>;
      map['start'] = DateTime(2026, 10, 20).toUtc().toIso8601String();
      storage.value = jsonEncode(map);

      final result = await anchor(storage, now: () => t0.add(const Duration(days: 1)))
          .synchronize(databaseStart: t0);

      expect(result.anchorAltered, isTrue);
      expect(result.start, t0);
    });

    test('orologio indietro di 3 giorni: rilevato, lastSeen non ridotto',
        () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 10, 9);
      await anchor(storage, now: () => t0).synchronize();

      final back = t0.subtract(const Duration(days: 3));
      final result = await anchor(storage, now: () => back)
          .synchronize(databaseStart: t0);

      expect(result.clockTampered, isTrue);
      expect(result.start, t0);

      // Tornando avanti, l'ancora è integra e lastSeen non è mai sceso:
      // una nuova sincronizzazione dopo 1 giorno NON è alterata.
      final after = await anchor(storage, now: () => t0.add(const Duration(days: 1)))
          .synchronize(databaseStart: t0);
      expect(after.clockTampered, isFalse);
      expect(after.start, t0);
    });

    test('piccolo ritardo entro 24 h: non è manipolazione', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 10, 9);
      await anchor(storage, now: () => t0).synchronize();

      final result = await anchor(storage, now: () => t0.subtract(const Duration(hours: 3)))
          .synchronize(databaseStart: t0);

      expect(result.clockTampered, isFalse);
    });

    test('vince la data più antica tra ancora e database', () async {
      final storage = MemoryTrialAnchorStorage();
      final anchorDate = DateTime(2026, 10, 1, 9);
      final dbDate = DateTime(2026, 9, 20, 8); // più antica
      await anchor(storage, now: () => anchorDate).synchronize();

      final result = await anchor(storage, now: () => DateTime(2026, 10, 5))
          .synchronize(databaseStart: dbDate);

      expect(result.start, dbDate);
    });

    test('la data non viene mai spostata in avanti', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();

      // Un database "futuro" (data più recente) non anticipa la fine della
      // prova: vince comunque la data più antica.
      final result = await anchor(storage, now: () => DateTime(2026, 10, 2))
          .synchronize(databaseStart: t0.add(const Duration(days: 30)));

      expect(result.start.isAtSameMomentAs(t0), isTrue);
    });

    test('clear cancella il supporto', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      await anchor(storage, now: () => t0).synchronize();
      expect(storage.value, isNotNull);

      await anchor(storage).clear();
      expect(storage.value, isNull);
    });

    test('storage assente: il database resta la fonte unica', () async {
      final t0 = DateTime(2026, 10, 1, 9);
      final result = await TrialAnchor(secret: secret, now: () => t0)
          .synchronize(databaseStart: t0);

      expect(result.start, t0);
      expect(result.firstInstall, isFalse);
      expect(result.lastSeen, isNotNull,
          reason: 'lastSeen serve all\'export per il backup');
    });
  });

  group('TrialAnchor.exportSigned/parseSigned (backup, Prompt 20)', () {
    test('roundtrip: stesso formato e stessa firma del file', () async {
      final storage = MemoryTrialAnchorStorage();
      final t0 = DateTime(2026, 10, 1, 9);
      final anchorInstance = anchor(storage, now: () => t0);
      final result = await anchorInstance.synchronize();

      final exported = anchorInstance.exportSigned(
        result.start,
        result.lastSeen!,
      );
      expect(exported, isNotNull);

      // Stesso contenuto del file di piattaforma: stesse chiavi, stessa
      // firma (nessuna logica duplicata).
      expect(exported, storage.value);

      final parsed = anchor(storage).parseSigned(exported!);
      expect(parsed, isNotNull);
      expect(parsed!.$1.isAtSameMomentAs(result.start), isTrue);
      expect(parsed.$2.isAtSameMomentAs(result.lastSeen!), isTrue);

      // Solo le due date e la firma: nessun altro dato personale.
      final map = jsonDecode(exported) as Map<String, dynamic>;
      expect(map.keys.toSet(), {'v', 'start', 'lastSeen', 'mac'});
    });

    test('firma modificata: parseSigned restituisce null', () {
      final anchorInstance = anchor(MemoryTrialAnchorStorage());
      final exported = anchorInstance.exportSigned(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
      )!;
      final map = jsonDecode(exported) as Map<String, dynamic>;

      // Data spostata avanti senza ricalcolare il MAC.
      map['start'] = DateTime(2026, 10, 20).toUtc().toIso8601String();
      expect(anchor(MemoryTrialAnchorStorage()).parseSigned(jsonEncode(map)),
          isNull);

      // MAC sostituito con uno inventato.
      final map2 = jsonDecode(exported) as Map<String, dynamic>;
      map2['mac'] = base64Encode(List.filled(32, 7));
      expect(anchor(MemoryTrialAnchorStorage()).parseSigned(jsonEncode(map2)),
          isNull);
    });

    test('segreto vuoto (debug): non firma e non verifica', () {
      final anchorInstance =
          TrialAnchor(secret: '', storage: MemoryTrialAnchorStorage());
      expect(
        anchorInstance.exportSigned(DateTime(2026, 10, 1), DateTime(2026, 10, 2)),
        isNull,
      );
      expect(anchorInstance.parseSigned('qualsiasi'), isNull);
    });
  });
}
