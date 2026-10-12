import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/lots_screen.dart';

/// Prompt 19, §1–§5 e §8: stati del lotto, avvisi, filtri,
/// tracciabilità inclusiva dei chiusi.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late HaccpRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lots_status');
  });

  setUp(() async {
    final dir = await tempDir.createTemp('db');
    db = AppDatabase(path: p.join(dir.path, 'blue_haccp.db'));
    await db.initialize();
    repository = HaccpRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  ProductionLot lot({
    required String code,
    DateTime? expiresAt,
    String status = LotStatus.active,
  }) =>
      ProductionLot(
        id: 0,
        code: code,
        productName: 'Prodotto $code',
        producedAt: DateTime.now().subtract(const Duration(days: 5)),
        expiresAt: expiresAt,
        operatorName: 'Rossi',
        status: status,
      );

  group('isExpired / isExpiringSoon (fine giornata, solo attivi)', () {
    test('il giorno stesso della scadenza NON è scaduto', () {
      final now = DateTime.now();
      final l = lot(code: 'OGGI', expiresAt: now);
      expect(l.isExpired, isFalse,
          reason: 'scade oggi: non è scaduto fino alle 23:59');
      expect(l.isExpiringSoon, isTrue);
    });

    test('il giorno dopo la scadenza è scaduto', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(lot(code: 'IERI', expiresAt: yesterday).isExpired, isTrue);
    });

    test('oltre 7 giorni non è "in scadenza"', () {
      final inTenDays = DateTime.now().add(const Duration(days: 10));
      final l = lot(code: 'FUTURO', expiresAt: inTenDays);
      expect(l.isExpired, isFalse);
      expect(l.isExpiringSoon, isFalse);
    });

    test('lotti chiusi: mai scaduti né in scadenza', () {
      final past = DateTime.now().subtract(const Duration(days: 30));
      final finished = lot(
          code: 'F', expiresAt: past, status: LotStatus.finished);
      final withdrawn = lot(
          code: 'W', expiresAt: past, status: LotStatus.withdrawn);
      expect(finished.isExpired, isFalse);
      expect(finished.isExpiringSoon, isFalse);
      expect(withdrawn.isExpired, isFalse);
      expect(withdrawn.isExpiringSoon, isFalse);
      expect(finished.isClosed, isTrue);
      expect(withdrawn.isClosed, isTrue);
    });

    test('senza scadenza non è mai scaduto', () {
      expect(lot(code: 'NOEXP').isExpired, isFalse);
      expect(lot(code: 'NOEXP').isExpiringSoon, isFalse);
    });
  });

  group('azioni sul lotto (repository)', () {
    test('"Terminato": salva finished e closed_at, nessun motivo',
        () async {
      final id = await repository.createLot(
          lot(code: 'T1', expiresAt: DateTime.now().add(const Duration(days: 2))));
      await repository.finishLot(id);
      final after = (await repository.getLots()).single;
      expect(after.isFinished, isTrue);
      expect(after.closedAt, isNotNull);
      expect(after.withdrawnReason, isNull,
          reason: 'nessun motivo per "terminato"');
      expect(after.withdrawnQuantity, isNull);
    });

    test('"Ritira": salva motivo, data, nota e quantità', () async {
      final id = await repository.createLot(lot(code: 'R1'));
      final when = DateTime.now().subtract(const Duration(hours: 2));
      await repository.withdrawLot(
        id: id,
        reason: LotWithdrawalReason.expired,
        closedAt: when,
        note: 'trovato in frigo oltre termine',
        quantity: '1,5 kg',
        operatorName: 'Bianchi',
      );
      final after = (await repository.getLots()).single;
      expect(after.isWithdrawn, isTrue);
      expect(after.withdrawnReason, LotWithdrawalReason.expired);
      expect(after.closedAt, when);
      expect(after.closingNote, 'trovato in frigo oltre termine');
      expect(after.withdrawnQuantity, '1,5 kg');
      expect(after.closedBy, 'Bianchi');
    });

    test('riattivazione: torna attivo e annota la data nella nota',
        () async {
      final id = await repository.createLot(lot(code: 'RE1'));
      await repository.withdrawLot(
          id: id, reason: LotWithdrawalReason.damaged, note: 'goccia frigo');
      await repository.reopenLot(id, operatorName: 'Verdi');
      final after = (await repository.getLots()).single;
      expect(after.isActive, isTrue);
      expect(after.closedAt, isNull);
      expect(after.withdrawnReason, isNull);
      expect(after.closingNote, contains('Riattivato il'));
      expect(after.closingNote, contains('Verdi'));
      expect(after.closingNote, contains('goccia frigo'),
          reason: 'lo storico della chiusura non si perde');
    });

    test('annullo immediato (annotate false): nessuna traccia nella nota',
        () async {
      final id = await repository.createLot(lot(code: 'RE2'));
      await repository.finishLot(id);
      await repository.reopenLot(id, annotate: false);
      final after = (await repository.getLots()).single;
      expect(after.isActive, isTrue);
      expect(after.closingNote, isNull,
          reason: 'l\u2019annullo dello snackbar non lascia rumore');
    });

    test('appendLotClosingNote aggiunge senza sovrascrivere', () async {
      final id = await repository.createLot(lot(code: 'AN1'));
      await repository.finishLot(id, note: 'prima nota');
      await repository.appendLotClosingNote(id, 'seconda nota');
      final after = (await repository.getLots()).single;
      expect(after.closingNote, contains('prima nota'));
      expect(after.closingNote, contains('seconda nota'));
    });
  });

  group('avvisi in "Oggi" (getTodos)', () {
    test('lotti chiusi: nessun avviso', () async {
      final past = DateTime.now().subtract(const Duration(days: 10));
      await repository.createLot(lot(code: 'C1', expiresAt: past));
      final id2 = await repository.createLot(lot(code: 'C2', expiresAt: past));
      await repository.finishLot(id2);
      final id3 = await repository.createLot(lot(code: 'C3', expiresAt: past));
      await repository.withdrawLot(id: id3, reason: LotWithdrawalReason.expired);

      final dashboard = await repository.getDashboard();
      final lotTodos =
          dashboard.todos.where((t) => t.target.startsWith('lots'));
      expect(lotTodos, hasLength(1),
          reason: 'solo il lotto attivo scaduto genera avviso');
      expect(lotTodos.single.severity, 0);
      expect(lotTodos.single.subtitle, contains('ritirare dall\u2019uso'),
          reason: 'nuovo testo dell\u2019avviso');
    });

    test('fino a 3 scaduti attivi: una riga per lotto', () async {
      for (var i = 0; i < 3; i++) {
        await repository.createLot(lot(
            code: 'E$i',
            expiresAt: DateTime.now().subtract(Duration(days: i + 1))));
      }
      final dashboard = await repository.getDashboard();
      final expiredTodos = dashboard.todos
          .where((t) => t.target == 'lots:expired')
          .toList();
      expect(expiredTodos, hasLength(3));
      for (final t in expiredTodos) {
        expect(t.title, startsWith('Lotto scaduto:'));
      }
    });

    test('oltre 3 scaduti attivi: UN solo avviso riepilogativo', () async {
      for (var i = 0; i < 5; i++) {
        await repository.createLot(lot(
            code: 'M$i',
            expiresAt: DateTime.now().subtract(Duration(days: i + 1))));
      }
      final dashboard = await repository.getDashboard();
      final expiredTodos = dashboard.todos
          .where((t) => t.target == 'lots:expired')
          .toList();
      expect(expiredTodos, hasLength(1));
      expect(expiredTodos.single.title, '5 lotti scaduti da gestire');
    });

    test('dopo la chiusura l\'avviso sparisce', () async {
      final id = await repository.createLot(lot(
          code: 'CLOSE',
          expiresAt: DateTime.now().subtract(const Duration(days: 2))));
      var dashboard = await repository.getDashboard();
      expect(
          dashboard.todos.where((t) => t.target.startsWith('lots')),
          isNotEmpty);
      await repository.finishLot(id);
      dashboard = await repository.getDashboard();
      expect(
          dashboard.todos.where((t) => t.target.startsWith('lots')), isEmpty);
    });

    test('in scadenza entro 7 giorni: avviso warning solo per attivi',
        () async {
      await repository.createLot(lot(
          code: 'SOON',
          expiresAt: DateTime.now().add(const Duration(days: 3))));
      final id2 = await repository.createLot(lot(
          code: 'SOON2',
          expiresAt: DateTime.now().add(const Duration(days: 3))));
      await repository.finishLot(id2);
      final dashboard = await repository.getDashboard();
      final soon = dashboard.todos
          .where((t) => t.target == 'lots' && t.severity == 1)
          .toList();
      expect(soon, hasLength(1));
      expect(soon.single.title, contains('SOON'));
    });
  });

  group('filtri elenco Lotti', () {
    test('Attivi / Scaduti / Archivio / Tutti + ricerca', () async {
      final activeId = await repository.createLot(lot(
          code: 'A-1', expiresAt: DateTime.now().add(const Duration(days: 9))));
      await repository.createLot(lot(
          code: 'S-1',
          expiresAt: DateTime.now().subtract(const Duration(days: 1))));
      final finId = await repository.createLot(lot(code: 'F-1'));
      final witId = await repository.createLot(lot(code: 'W-1'));
      await repository.finishLot(finId);
      await repository.withdrawLot(
          id: witId, reason: LotWithdrawalReason.recall);

      final all = await repository.getLots();

      final active = filterLotsForView(all, LotViewFilter.active);
      expect(active.map((l) => l.code), containsAll(['A-1', 'S-1']),
          reason: 'gli attivi includono i scaduti da gestire');
      expect(active.first.code, 'S-1',
          reason: 'i scaduti attivi restano in testa');

      final expired = filterLotsForView(all, LotViewFilter.expired);
      expect(expired.map((l) => l.code), ['S-1']);

      final archive = filterLotsForView(all, LotViewFilter.archive);
      expect(archive.map((l) => l.code), containsAll(['F-1', 'W-1']));

      final archiveFinished = filterLotsForView(all, LotViewFilter.archive,
          archiveSub: LotArchiveSubFilter.finished);
      expect(archiveFinished.map((l) => l.code), ['F-1']);
      final archiveWithdrawn = filterLotsForView(all, LotViewFilter.archive,
          archiveSub: LotArchiveSubFilter.withdrawn);
      expect(archiveWithdrawn.map((l) => l.code), ['W-1']);

      final every = filterLotsForView(all, LotViewFilter.all);
      expect(every, hasLength(4));

      // Ricerca testuale su tutti i filtri.
      final search = filterLotsForView(all, LotViewFilter.all, query: 'w-1');
      expect(search.map((l) => l.code), ['W-1']);
      final searchArchive =
          filterLotsForView(all, LotViewFilter.archive, query: 'F-1');
      expect(searchArchive.map((l) => l.code), ['F-1']);
      expect(activeId, greaterThan(0));
    });

    test('archivio ordinato per chiusura più recente prima', () async {
      final oldId = await repository.createLot(lot(code: 'OLD'));
      final newId = await repository.createLot(lot(code: 'NEW'));
      await repository.finishLot(oldId);
      // Chiusura del secondo almeno un secondo dopo.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await repository.finishLot(newId);
      final archive =
          filterLotsForView(await repository.getLots(), LotViewFilter.archive);
      expect(archive.first.code, 'NEW');
      expect(archive.last.code, 'OLD');
    });
  });

  group('tracciabilità include i lotti chiusi', () {
    test('searchTraceability e getLotsUsingReceipt mostrano lo stato',
        () async {
      final supplierId = await repository.dbInsertSupplier();
      final receiptId = await repository.dbInsertReceipt(supplierId);
      final openId = await repository.createLot(
        lot(code: 'TR-OPEN', expiresAt: DateTime.now().add(const Duration(days: 5))),
        ingredients: [
          LotIngredient(
              id: 0, lotId: 0, receiptId: receiptId, name: 'Passata'),
        ],
      );
      final closedId = await repository.createLot(
        lot(code: 'TR-CLOSED'),
        ingredients: [
          LotIngredient(
              id: 0,
              lotId: 0,
              receiptId: receiptId,
              name: 'Passata',
              supplierLot: 'FORN-9'),
        ],
      );
      await repository.withdrawLot(
          id: closedId, reason: LotWithdrawalReason.damaged);

      final byLot = await repository.searchTraceability('TR-CLOSED');
      expect(byLot.lots, hasLength(1));
      expect(byLot.lots.single.isWithdrawn, isTrue,
          reason: 'lo stato è visibile nella ricerca');

      final bySupplierLot = await repository.searchTraceability('FORN-9');
      // La ricerca incontra la consegna e TUTTI i lotti che la usano:
      // anche questo è tracciabilità inclusiva.
      expect(bySupplierLot.lots.map((l) => l.code),
          containsAll(['TR-OPEN', 'TR-CLOSED']));

      final downstream = await repository.getLotsUsingReceipt(receiptId);
      expect(downstream.map((l) => l.code), containsAll(['TR-OPEN', 'TR-CLOSED']),
          reason: 'la tracciabilità a valle NON perde i lotti archiviati');
      expect(openId, greaterThan(0));
    });
  });
}

extension on HaccpRepository {
  Future<int> dbInsertSupplier() async {
    final db = database.db;
    return db.insert('suppliers', {'name': 'Fornitore X'});
  }

  Future<int> dbInsertReceipt(int supplierId) async {
    final db = database.db;
    return db.insert('receipts', {
      'received_at': DateTime.now().toIso8601String(),
      'supplier_id': supplierId,
      'product': 'Passata',
      'category': 'shelf_stable',
      'supplier_lot': 'FORN-9',
      'operator_name': 'Rossi',
    });
  }
}
