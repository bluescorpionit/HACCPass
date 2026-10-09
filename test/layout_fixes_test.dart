import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/constants/haccp_rules.dart';
import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/printing/label_printer.dart';
import 'package:haccpass/core/theme/app_theme.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/checks_hub_screen.dart';
import 'package:haccpass/screens/dashboard_screen.dart';
import 'package:haccpass/screens/guide_screen.dart';
import 'package:haccpass/screens/printer_settings_screen.dart';
import 'package:haccpass/services/license_service.dart';
import 'package:haccpass/widgets/common_widgets.dart';

/// Stub di LicenseService per i widget test: costruire quella reale avvia la
/// connessione in-app purchase, che nel loop reale (runAsync) esplode con
/// una PlatformException.
class _StubLicense implements LicenseService {
  @override
  bool get canWrite => true;

  @override
  bool get trialActive => false;

  @override
  String get chipLabel => 'Prova: 14 giorni';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub LicenseService: ${invocation.memberName}');
}

/// Fix di layout (Prompt 6): inset edge-to-edge, Scaffold nelle schermate
/// pushate, fogli modali e azioni correttive.
void main() {
  sqfliteFfiInit();
  // Senza isolate: le future del DB completano come microtask anche nel
  // widget test runner.
  databaseFactory = databaseFactoryFfiNoIsolate;
  initializeDateFormatting('it_IT');

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('layout_test');
    appDatabase = AppDatabase(
      path:
          '${tempDir.path}/layout_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  group('Schermate pushate: mai senza Scaffold', () {
    testWidgets('ChecksHub standalone: Scaffold opaco e AppBar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: ChecksHubScreen(
            repository: repository,
            license: _StubLicense(),
            standalone: true,
          ),
        ),
      );
      // Durata fissa: pumpAndSettle non termina per gli indicatori di
      // caricamento ripetuti del LiveQuery.
      await tester.pump();
      // Il loader del LiveQuery passa per l'isolate di sqflite_ffi: le sue
      // future consegnano solo sul loop reale, non nel FakeAsync del test.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        AppTheme.light().scaffoldBackgroundColor,
        reason: 'sfondo dal tema, mai nero/trasparente',
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Controlli'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('GuideScreen (push): Scaffold con sfondo del tema',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: GuideScreen()),
      );
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor ?? AppTheme.light().scaffoldBackgroundColor,
        AppTheme.light().scaffoldBackgroundColor,
        reason: 'sfondo dal tema (null = default), mai nero/trasparente',
      );
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('Edge-to-edge: inset nelle schermate principali', () {
    testWidgets(
        'Dashboard a 360x640, scala 1.15, inset 24/48: padding corretto e '
        'nessun overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(top: 24, bottom: 48);
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DashboardScreen(
              repository: repository,
              license: _StubLicense(),
              onOpenTarget: (_) {},
              onNavigate: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
      // Loop reale per il loader del LiveQuery (vedi commento sopra).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Il padding dello scroll somma l'inset di stato (24) e ignora
      // l'inferiore (gestito dalla bottom bar della shell).
      final listView = tester.widget<ListView>(find.byType(ListView));
      expect(listView.padding, const EdgeInsets.fromLTRB(20, 40, 20, 32));

      // Nessuna eccezione di layout (strisce gialle/nere di overflow).
      expect(tester.takeException(), isNull);
    });

    testWidgets('Hub controlli (tab) a 360x640 scala 1.15 senza overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.15;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ChecksHubScreen(
              repository: repository,
              license: _StubLicense(),
            ),
          ),
        ),
      );
      await tester.pump();
      // Loop reale per il loader del LiveQuery (vedi commento sopra).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('Controlli'), findsOneWidget);
    });
  });

  group('Foglio modale (showFormSheet)', () {
    testWidgets(
        'con inset di sistema 24/48 il pulsante Salva resta sopra la barra '
        'di navigazione', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding = FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding = FakeViewPadding(top: 24, bottom: 48);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showFormSheet<bool>(
                  context: context,
                  title: 'Registra temperatura',
                  saveLabel: 'Salva controllo',
                  builder: (_) => Column(
                    children: [
                      for (var i = 0; i < 8; i++)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: TextField(
                            decoration: InputDecoration(
                              labelText: 'Campo',
                            ),
                          ),
                        ),
                    ],
                  ),
                  onSave: () => true,
                ),
                child: const Text('apri'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();

      final saveRect = tester.getRect(find.text('Salva controllo'));
      expect(
        saveRect.bottom,
        lessThanOrEqualTo(640 - 48),
        reason: 'il pulsante Salva non puo\' finire sotto la barra di '
            'navigazione di sistema (48 px simulati)',
      );

      // Il foglio non sale sopra la barra di stato (useSafeArea).
      final sheetTop = tester.getTopLeft(find.byType(BottomSheet).first).dy;
      expect(sheetTop, greaterThanOrEqualTo(24));

      expect(tester.takeException(), isNull);
    });
  });

  group('Azioni correttive', () {
    testWidgets('etichette lunghe integre a 360 dp e scala 1.3',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ListView(
              children: [
                CorrectiveActionPicker(
                  actions: temperatureCorrectiveActions,
                  selected: const {},
                  onToggle: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Ogni etichetta resta integrale (niente troncamento "…guarnizi…").
      for (final action in temperatureCorrectiveActions) {
        expect(find.text(action), findsOneWidget);
      }
      // Area di tocco >= 48 dp per riga.
      for (final tile in find.byType(CheckboxListTile).evaluate()) {
        expect(tile.renderObject!.paintBounds.height, greaterThanOrEqualTo(48));
      }
    });
  });

  group('Prompt 14: Stampante — barra di sistema e larghezze uniformi', () {
    Future<void> pumpPrinter(
      WidgetTester tester, {
      required Size size,
      double textScale = 1.0,
      EdgeInsets viewPadding = EdgeInsets.zero,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: viewPadding),
              child: PrinterSettingsScreen(
                repository: repository,
                // Motori finti con gli id/nomi dei reali.
                engines: [
                  _FakeEngine('brother', 'Brother QL'),
                  _FakeEngine('niimbot', 'Niimbot'),
                  _FakeEngine('generic', 'Stampante generica'),
                  _FakeEngine('system', 'Stampa di sistema'),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }

    testWidgets(
        'inset 48: "Anteprima" resta sopra la barra di navigazione (360×640)',
        (tester) async {
      await tester
          .runAsync(() => repository.setSetting('printer_engine', 'brother'));
      await pumpPrinter(
        tester,
        size: const Size(360, 640),
        viewPadding: const EdgeInsets.only(bottom: 48),
      );

      // Scorri fino in fondo alla lista.
      await tester.drag(
        find.byType(Scrollable).first,
        const Offset(0, -3000),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final rect = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Anteprima'),
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(640 - 48),
        reason: 'il bordo inferiore del pulsante non può finire sotto la '
            'barra di navigazione (640 − 48 = 592)',
      );
    });

    for (final (size, scale) in const [
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.15),
      (Size(412, 915), 1.0),
      (Size(412, 915), 1.15),
    ]) {
      testWidgets(
          'larghezze uniformi ${size.width}dp scala $scale '
          '(primaria piena, coppia uguale)', (tester) async {
        await tester
            .runAsync(() => repository.setSetting('printer_engine', 'brother'));
        await tester.runAsync(() =>
            repository.setSetting('printer_device_id', 'wifi:1.2.3.4|QL'));
        await pumpPrinter(tester, size: size, textScale: scale);

        // "Cerca stampanti" è in alto ma la lista è lazy: garantirne la
        // costruzione PRIMA di misurare, senza spostarlo se è in vista.
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Cerca stampanti'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        final cerca = tester.getRect(
          find.widgetWithText(FilledButton, 'Cerca stampanti'),
        );

        // I pulsanti d'azione sono in fondo alla lista: scorrere prima di
        // misurare (ListView lazy).
        await tester.drag(
          find.byType(Scrollable).first,
          const Offset(0, -3000),
        );
        await tester.pump();

        expect(tester.takeException(), isNull,
            reason: 'nessun overflow con larghezza ${size.width} e scala '
                '$scale');

        final contentWidth = size.width - 32; // margini 16 + 16
        final prova = tester.getRect(find.widgetWithText(
          FilledButton,
          'Stampa etichetta di prova',
        ));
        expect(prova.width, closeTo(contentWidth, 0.5),
            reason: 'azione primaria a larghezza piena');
        expect(cerca.width + 8 + 52, closeTo(contentWidth, 0.5),
            reason: 'riga Cerca: pulsante + icona stato 52×52');
        expect(cerca.left, closeTo(prova.left, 0.5),
            reason: 'stesso margine sinistro');

        final anteprima = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Anteprima'),
        );
        final scollega = tester.getRect(
          find.widgetWithText(OutlinedButton, 'Scollega'),
        );
        expect(anteprima.width, closeTo(scollega.width, 0.5),
            reason: 'secondarie in coppia a larghezza uguale');
        expect(anteprima.width, closeTo((contentWidth - 8) / 2, 0.5));
      });
    }
  });

  group('Prompt 16, §1–§2: ActionButtonRow e scheda lotto', () {
    List<ActionButtonData> lotActions(List<int> taps) => [
          ActionButtonData(
            icon: Icons.print_outlined,
            label: 'Stampa',
            onPressed: () => taps[0]++,
          ),
          ActionButtonData(
            icon: Icons.qr_code_2,
            label: 'Etichetta',
            onPressed: () => taps[1]++,
          ),
          ActionButtonData(
            icon: Icons.account_tree_outlined,
            label: 'Rintraccio',
            onPressed: () => taps[2]++,
          ),
          ActionButtonData(
            icon: Icons.attach_file,
            label: 'Allegati',
            onPressed: () => taps[3]++,
          ),
        ];

    Future<void> pumpRow(
      WidgetTester tester, {
      required Size size,
      double textScale = 1.0,
      List<ActionButtonData> actions = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(
          tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: ActionButtonRow(actions: actions),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    for (final (size, scale) in const [
      (Size(320, 640), 1.0),
      (Size(320, 640), 1.15),
      (Size(360, 640), 1.0),
      (Size(360, 640), 1.15),
      (Size(412, 915), 1.0),
      (Size(412, 915), 1.15),
    ]) {
      testWidgets(
          'quattro azioni uguali, 56 dp, testo su una riga '
          '(${size.width}dp, scala $scale)', (tester) async {
        final taps = [0, 0, 0, 0];
        await pumpRow(tester,
            size: size, textScale: scale, actions: lotActions(taps));

        expect(tester.takeException(), isNull,
            reason: 'nessun overflow a ${size.width} scala $scale');

        final rects = [
          for (final label in const ['Stampa', 'Etichetta', 'Rintraccio', 'Allegati'])
            tester.getRect(find.widgetWithText(OutlinedButton, label)),
        ];
        // Stessa altezza 56 e larghezze uguali, sempre.
        for (final rect in rects.skip(1)) {
          expect(rect.height, closeTo(56, 0.5));
          expect(rect.width, closeTo(rects.first.width, 0.5));
        }
        // Etichette su UNA riga: mai spezzate lettera per lettera.
        for (final label in const ['Stampa', 'Etichetta', 'Rintraccio', 'Allegati']) {
          final textRect = tester.getRect(find.text(label));
          expect(textRect.height, lessThan(24),
              reason: '$label deve stare su una riga');
        }

        if (size.width <= 320) {
          // 66 dp per pulsante < 72: due righe uguali (griglia).
          expect(rects[0].top, closeTo(rects[1].top, 0.5));
          expect(rects[2].top, greaterThan(rects[0].bottom));
        } else {
          // Una riga sola: stesso dy per tutti.
          for (final rect in rects.skip(1)) {
            expect(rect.top, closeTo(rects.first.top, 0.5));
          }
          expect(
            rects.last.right,
            lessThanOrEqualTo(size.width - 16),
          );
        }
      });
    }

    testWidgets('con 200 dp di larghezza passa alla griglia 2 colonne',
        (tester) async {
      tester.view.physicalSize = const Size(240, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final taps = [0, 0, 0, 0];
      await pumpRow(tester,
          size: const Size(240, 640), actions: lotActions(taps));

      expect(tester.takeException(), isNull);
      final rects = [
        for (final label in const ['Stampa', 'Etichetta', 'Rintraccio', 'Allegati'])
          tester.getRect(find.widgetWithText(OutlinedButton, label)),
      ];
      // Due colonne: larghezza ≈ metà, due righe diverse (dy diversi).
      final half = (240 - 32 - 8) / 2;
      for (final rect in rects) {
        expect(rect.width, closeTo(half, 1));
      }
      expect(rects[0].top, closeTo(rects[1].top, 0.5),
          reason: 'prima coppia sulla stessa riga');
      expect(rects[2].top, greaterThan(rects[0].bottom),
          reason: 'seconda coppia sotto');
    });

    testWidgets('il tocco chiama il callback giusto (3 e 4 azioni)',
        (tester) async {
      final taps4 = [0, 0, 0, 0];
      await pumpRow(tester,
          size: const Size(412, 800), actions: lotActions(taps4));
      for (final label in const ['Stampa', 'Etichetta', 'Rintraccio', 'Allegati']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(taps4, [1, 1, 1, 1]);

      final taps3 = [0, 0, 0, 0];
      await pumpRow(tester,
          size: const Size(412, 800), actions: lotActions(taps3).take(3).toList());
      for (final label in const ['Stampa', 'Etichetta', 'Rintraccio']) {
        await tester.tap(find.text(label));
        await tester.pump();
      }
      expect(taps3, [1, 1, 1, 0]);
    });
  });
}

/// Motore finto per i test di layout della schermata Stampante.
class _FakeEngine implements LabelPrinter {
  const _FakeEngine(this.id, this.displayName);

  @override
  final String id;

  @override
  final String displayName;

  @override
  Future<List<PrinterDevice>> discover() async => const [];

  @override
  Future<void> connect(PrinterDevice device) async {}

  @override
  Future<void> disconnect() async {}

  @override
  bool get isConnected => false;

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pages,
    LabelSpec spec, {
    int copies = 1,
  }) async =>
      const PrintResult(PrintOutcome.ok);

  @override
  Future<PrinterStatus> status() async => const PrinterStatus(connected: false);
}
