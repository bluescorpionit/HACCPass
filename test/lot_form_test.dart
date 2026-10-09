import 'dart:io';

import 'package:flutter/foundation.dart';
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

/// Prompt 16, §8: nuovo lotto con prodotto da menu ricercabile (tutti i
/// prodotti, nessun limite di 8), nessuna preselezione silenziosa,
/// "Lotto libero" con nome e "Nuovo prodotto" che crea e seleziona.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  initializeDateFormatting('it_IT');
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late HaccpRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lot_form');
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

  Future<void> createProducts(List<String> names,
      {int shelfLifeDays = 3}) async {
    for (final name in names) {
      await repository.saveProduct(Product(
        id: 0,
        name: name,
        shelfLifeDays: shelfLifeDays,
      ));
    }
  }

  Future<void> pumpLots(
    WidgetTester tester, {
    Size size = const Size(412, 900),
    double textScale = 1.0,
    Future<Product?> Function(
      BuildContext,
      HaccpRepository, {
      Product? existing,
    })? productEditor,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        home: LotsScreen(
          repository: repository,
          license: _StubLicense(),
          productEditor: productEditor,
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  Future<void> openNewLot(WidgetTester tester) async {
    await tester.tap(find.byType(FloatingActionButton));
    // _newLot legge prodotti/consegne dal DB: dare tempo reale.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
  }

  /// Apre il selettore prodotto e sceglie [name] (o il lotto libero).
  Future<void> pickProduct(WidgetTester tester, String name) async {
    await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(name));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('(b) nessuna preselezione: serve una scelta per creare',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester
          .runAsync(() => createProducts(['Margherita', 'Capricciosa']));
      await pumpLots(tester);
      await openNewLot(tester);

      expect(find.text('Seleziona il prodotto'), findsWidgets,
          reason: 'nessun prodotto preselezionato');
      expect(find.textContaining('Scegli un prodotto o crea una nuova scheda'),
          findsOneWidget);

      // "Crea lotto" senza scelta: resta aperto con messaggio.
      await tester.tap(find.text('Crea lotto'));
      await tester.pump();
      expect(find.text('Nuovo lotto di produzione'), findsOneWidget,
          reason: 'il foglio resta aperto');
      expect(find.textContaining('Scegli un prodotto o compila il nome'),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(a) con 12 prodotti la ricerca "panz" mostra Panzarotti',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.runAsync(() => createProducts([
            'Margherita',
            'Capricciosa',
            'Panzarotti',
            'Pizza bianca',
            'Calzone',
            'Focaccia',
            'Panino',
            'Piadina',
            'Tiramisu',
            'Cannolo',
            'Arancini',
            'Suppli',
          ]));
      await pumpLots(tester);
      await openNewLot(tester);

      // Apre il pannello di ricerca.
      await tester.tap(find.byIcon(Icons.arrow_drop_down).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Ricerca: resta solo Panzarotti.
      await tester.enterText(
        find.byKey(const Key('picker_search_field')),
        'panz',
      );
      await tester.pump();
      expect(find.text('Panzarotti'), findsOneWidget);
      expect(find.text('Margherita'), findsNothing);

      // Seleziona: il campo lo mostra e il codice ÃƒÆ’Ã‚Â¨ precompilato.
      await tester.tap(find.text('Panzarotti'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Panzarotti'), findsWidgets);

      final code =
          (tester.widget(find.byKey(const Key('lot_code_field'))) as TextField)
              .controller!
              .text;
      expect(code, isNotEmpty, reason: 'codice precompilato dal prodotto');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(c) "Nuovo prodotto" crea, seleziona e precompila',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.runAsync(() => createProducts(['Margherita']));
      var editorOpened = false;
      await pumpLots(
        tester,
        productEditor: (context, repo, {existing}) async {
          editorOpened = true;
          expect(existing, isNull, reason: 'creazione, non modifica');
          return Product(id: 99, name: 'Tiramisu', shelfLifeDays: 5);
        },
      );
      await openNewLot(tester);

      await tester.tap(find.byTooltip('Nuovo prodotto'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(editorOpened, isTrue);
      expect(find.text('Tiramisu'), findsWidgets,
          reason: 'nuovo prodotto selezionato');
      expect(find.textContaining('Durata 5 giorni'), findsOneWidget,
          reason: 'riepilogo del prodotto appena creato');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(c-bis) editor annullato: selezione invariata', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.runAsync(() => createProducts(['Margherita']));
      await pumpLots(
        tester,
        productEditor: (context, repo, {existing}) async => null,
      );
      await openNewLot(tester);

      await tester.tap(find.byTooltip('Nuovo prodotto'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Seleziona il prodotto'), findsWidgets,
          reason: 'annullato: resta la selezione precedente');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(d) codice modificato a mano non viene sovrascritto',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester
          .runAsync(() => createProducts(['Margherita', 'Capricciosa']));
      await pumpLots(tester);
      await openNewLot(tester);

      await pickProduct(tester, 'Margherita');

      final codeFinder = find.byKey(const Key('lot_code_field'));
      await tester.enterText(codeFinder, 'MANUALE1');
      await tester.pump();

      // Cambia prodotto: il codice resta MANUALE1 (flag dirty).
      await pickProduct(tester, 'Capricciosa');

      final code = (tester.widget(codeFinder) as TextField).controller!.text;
      expect(code, 'MANUALE1',
          reason: 'il codice modificato a mano non ÃƒÆ’Ã‚Â¨ toccato');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(e) Lotto libero richiede il nome e salva senza productId',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.runAsync(() => createProducts(['Margherita']));
      await pumpLots(tester);
      await openNewLot(tester);

      await pickProduct(tester, 'Lotto libero (senza scheda)');

      expect(find.text('Nome del lotto (obbligatorio)'), findsOneWidget);

      // Senza nome: il salvataggio ÃƒÆ’Ã‚Â¨ bloccato.
      await tester.tap(find.text('Crea lotto'));
      await tester.pump();
      expect(find.text('Nuovo lotto di produzione'), findsOneWidget);

      // Con il nome: crea il lotto libero.
      await tester.enterText(
        find.byKey(const Key('lot_free_name_field')),
        'Salsa bianca',
      );
      await tester.pump();
      await tester.tap(find.text('Crea lotto'));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      final lots = await tester.runAsync(() => repository.getLots());
      expect(lots, isNotEmpty);
      expect(lots!.single.productName, 'Salsa bianca');
      expect(lots.single.productId, isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(f) stato vuoto: menu disattivato e "Crea il primo prodotto"',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      var editorOpened = false;
      await pumpLots(
        tester,
        productEditor: (context, repo, {existing}) async {
          editorOpened = true;
          return Product(id: 7, name: 'Primo');
        },
      );
      await openNewLot(tester);

      expect(find.text('Nessuna scheda prodotto'), findsWidgets);
      expect(find.text('Crea il primo prodotto'), findsOneWidget);

      await tester.tap(find.text('Crea il primo prodotto'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(editorOpened, isTrue);
      expect(find.text('Primo'), findsWidgets,
          reason: 'il primo prodotto ÃƒÆ’Ã‚Â¨ selezionato dopo la creazione');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(g) 320ÃƒÆ’Ã¢â‚¬â€640 scala 1.15: nessun overflow nel foglio',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.runAsync(
          () => createProducts(['Margherita', 'Capricciosa', 'Panzarotti']));
      await pumpLots(
        tester,
        size: const Size(320, 640),
        textScale: 1.15,
      );
      await openNewLot(tester);

      await tester.drag(
        find.byType(Scrollable).last,
        const Offset(0, -2000),
      );
      await tester.pump();

      expect(tester.takeException(), isNull,
          reason: 'nessun overflow nel foglio a 320 dp scala 1.15');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
