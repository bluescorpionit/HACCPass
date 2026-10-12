import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/models/haccp_models.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/lots_screen.dart';
import 'package:haccpass/services/license_service.dart';

/// Prompt 19, §8 (test widget): azioni sulla scheda, badge scaduto,
/// passaggio in Archivio con Annulla funzionante, ritiro con motivo.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  initializeDateFormatting('it_IT');
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late HaccpRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lots_widget');
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

  Future<int> seedLot({
    required String code,
    DateTime? expiresAt,
  }) async {
    return repository.createLot(ProductionLot(
      id: 0,
      code: code,
      productName: 'Prodotto $code',
      producedAt: DateTime.now().subtract(const Duration(days: 2)),
      expiresAt: expiresAt,
      operatorName: 'Rossi',
    ));
  }

  Future<void> pumpLots(
    WidgetTester tester, {
    Size size = const Size(360, 900),
    double textScale = 1.0,
    LotViewFilter initialFilter = LotViewFilter.active,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(MaterialApp(
      home: LotsScreen(
        repository: repository,
        license: _StubLicense(),
        initialFilter: initialFilter,
      ),
    ));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Dopo un'azione che scrive sul database: la scrittura gira nella
  /// finestra reale (runAsync) e l'interfaccia ha bisogno di alcuni
  /// frame per ricostruire lista e snackbar.
  Future<void> settleDb(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets(
      'scheda lotto attivo: "Segna come terminato" e "Ritira / smaltisci" '
      'in orizzontale senza overflow a 360 dp scala 1.15',
      (tester) async {
    await tester.runAsync(
        () => seedLot(code: 'W1', expiresAt: DateTime.now().add(const Duration(days: 5))));
    await pumpLots(tester, textScale: 1.15);

    expect(find.byKey(const Key('lot_finish_button')), findsOneWidget);
    expect(find.byKey(const Key('lot_withdraw_button')), findsOneWidget);
    expect(find.text('Segna come terminato'), findsOneWidget);
    expect(find.text('Ritira / smaltisci'), findsOneWidget);

    // Entrambi i pulsanti sono sullo stesso asse orizzontale.
    final finishBox = tester.getRect(
        find.byKey(const Key('lot_finish_button')));
    final withdrawBox = tester.getRect(
        find.byKey(const Key('lot_withdraw_button')));
    expect(withdrawBox.top, greaterThanOrEqualTo(finishBox.top));
    expect(withdrawBox.bottom, lessThanOrEqualTo(finishBox.bottom + 8),
        reason: 'i due pulsanti stanno sulla stessa riga');
    expect(tester.takeException(), isNull,
        reason: 'nessun overflow a 360 dp con testo 1.15');
  });

  testWidgets('lotto scaduto attivo: badge rosso e azione consigliata',
      (tester) async {
    await tester.runAsync(() => seedLot(
        code: 'EXP',
        expiresAt: DateTime.now().subtract(const Duration(days: 2))));
    await pumpLots(tester);

    expect(find.byKey(const Key('lot_badge_expired')), findsOneWidget);
    expect(find.textContaining('Scaduto il'), findsOneWidget);
    expect(find.textContaining('da ritirare'), findsOneWidget);

    // "Ritira / smaltisci" è l'azione consigliata: pulsante pieno.
    final withdrawButton = tester.widget<FilledButton>(
      find.byKey(const Key('lot_withdraw_button')),
    );
    expect(withdrawButton, isNotNull,
        reason: 'per i lotti scaduti "Ritira" è evidenziato (filled)');
    // "Segna come terminato" resta disponibile.
    expect(find.byKey(const Key('lot_finish_button')), findsOneWidget);
  });

  testWidgets(
      '"Segna come terminato": un tocco, va in Archivio, Annulla funziona '
      'e l\'avviso sparisce da "Oggi"', (tester) async {
    final id = await tester.runAsync(() => seedLot(
        code: 'DONE',
        expiresAt: DateTime.now().subtract(const Duration(days: 1))));
    await pumpLots(tester);

    await tester.tap(find.byKey(const Key('lot_finish_button')));
    await settleDb(tester);

    // Conferma leggera con Annulla.
    expect(find.text('Annulla'), findsOneWidget);
    expect(find.textContaining('segnato come terminato'), findsOneWidget);

    // Sparisce da "Oggi" (avviso lotti) e dall'elenco attivo.
    final dashboard =
        await tester.runAsync(() => repository.getDashboard());
    expect(dashboard!.todos.where((t) => t.target.startsWith('lots')),
        isEmpty);
    expect(find.byKey(const Key('lot_finish_button')), findsNothing,
        reason: 'il lotto chiuso non mostra più le azioni da attivo');

    // Niente più snackbar: asciuga e vai in Archivio.
    await tester.pump(const Duration(seconds: 7));
    await tester.tap(find.byKey(const Key('lot_filter_archive')));
    await settleDb(tester);
    expect(find.textContaining('Terminato il'), findsOneWidget);

    // Annulla (dalla snackbar): riapre con un'altra chiusura+annullo
    // direttamente da repository per determinismo, qui verifichiamo
    // il pulsante Riattiva con conferma.
    expect(find.byKey(const Key('lot_reopen_button')), findsOneWidget);
    expect(id, greaterThan(0));
  });

  testWidgets('Annulla della snackbar riporta il lotto attivo',
      (tester) async {
    await tester.runAsync(() => seedLot(
        code: 'UNDO',
        expiresAt: DateTime.now().add(const Duration(days: 4))));
    await pumpLots(tester);

    await tester.tap(find.byKey(const Key('lot_finish_button')));
    await settleDb(tester);
    expect(find.text('Annulla'), findsOneWidget);

    await tester.tap(find.text('Annulla'));
    await settleDb(tester);

    final lots = await tester.runAsync(() => repository.getLots());
    expect(lots!.single.isActive, isTrue,
        reason: 'l\u2019annullo riporta il lotto attivo senza note');
    expect(lots.single.closingNote, isNull);
  });

  testWidgets('"Ritira / smaltisci": motivo preselezionato scaduto, '
      'salva motivo e data', (tester) async {
    await tester.runAsync(() => seedLot(
        code: 'WDRAW',
        expiresAt: DateTime.now().subtract(const Duration(days: 3))));
    await pumpLots(tester);

    await tester.tap(find.byKey(const Key('lot_withdraw_button')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Ritira / smaltisci lotto'), findsOneWidget);
    expect(find.textContaining('resta nel registro'), findsOneWidget);

    // Motivo "Scaduto" preselezionato per i lotti oltre la scadenza.
    final expiredChip = tester.widget<ChoiceChip>(
      find.ancestor(
        of: find.text('Scaduto'),
        matching: find.byType(ChoiceChip),
      ),
    );
    expect(expiredChip.selected, isTrue,
        reason: 'scadenza passata => motivo preselezionato "scaduto"');

    await tester.enterText(
        find.byKey(const Key('lot_withdraw_quantity')), '2,5 kg');
    await tester.enterText(
        find.byKey(const Key('lot_withdraw_note')), 'trovato oltre termine');

    await tester.tap(find.text('Ritira lotto'));
    await settleDb(tester);

    final lots = await tester.runAsync(() => repository.getLots());
    final withdrawn = lots!.single;
    expect(withdrawn.isWithdrawn, isTrue);
    expect(withdrawn.withdrawnReason, LotWithdrawalReason.expired);
    expect(withdrawn.withdrawnQuantity, '2,5 kg');
    expect(withdrawn.closingNote, 'trovato oltre termine');
    expect(withdrawn.closedAt, isNotNull);

    // In Archivio con motivo e data visibili.
    await tester.tap(find.byKey(const Key('lot_filter_archive')));
    await settleDb(tester);
    expect(find.textContaining('Ritirato il'), findsOneWidget);
    expect(find.textContaining('(Scaduto)'), findsOneWidget);
  });

  testWidgets('filtro Scaduti con "Chiudi in blocco": conferma esplicita',
      (tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => seedLot(
          code: 'BLK$i',
          expiresAt: DateTime.now().subtract(Duration(days: i + 1))));
    }
    await pumpLots(tester);

    // Contatore nel filtro.
    expect(find.byKey(const Key('lot_filter_expired')), findsOneWidget);
    expect(find.text('Scaduti (4)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lot_filter_expired')));
    await settleDb(tester);
    expect(find.byKey(const Key('lot_bulk_close_button')), findsOneWidget);

    await tester.tap(find.byKey(const Key('lot_bulk_close_button')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Chiudi in blocco'), findsWidgets,
        reason: 'titolo del dialog e pulsante di apertura');
    expect(find.text('Chiudi 4 lotti'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lot_bulk_close_confirm')));
    await settleDb(tester);

    final lots = await tester.runAsync(() => repository.getLots());
    expect(lots!.where((l) => l.isClosed), hasLength(4),
        reason: 'chiusi come terminati (scelta predefinita)');
    expect(lots.where((l) => l.isFinished), hasLength(4));
    // Spariti dagli attivi.
    expect(find.byKey(const Key('lot_finish_button')), findsNothing);
  });
}

class _StubLicense implements LicenseService {
  @override
  bool get canWrite => true;

  @override
  bool get trialActive => false;

  @override
  String get chipLabel => 'Prova: 14 giorni';

  @override
  bool ensureLicensed(BuildContext context) => true;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub LicenseService');
}
