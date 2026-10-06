import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/constants/haccp_rules.dart';
import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/theme/app_theme.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/checks_hub_screen.dart';
import 'package:haccpass/screens/dashboard_screen.dart';
import 'package:haccpass/screens/guide_screen.dart';
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
        'nessun overflow',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      tester.view.padding =
          FakeViewPadding(top: 24, bottom: 48);
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
      tester.view.padding =
          FakeViewPadding(top: 24, bottom: 48);
      tester.view.viewPadding =
          FakeViewPadding(top: 24, bottom: 48);
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
      final sheetTop =
          tester.getTopLeft(find.byType(BottomSheet).first).dy;
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
        expect(tile.renderObject!.paintBounds.height,
            greaterThanOrEqualTo(48));
      }
    });
  });
}
