import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/core/printing/label_printer.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/printer_settings_screen.dart';
import 'package:haccpass/services/printing/generic_label_printer.dart';

/// Prompt 11, Ã‚Â§5: widget test della schermata Impostazioni Ã¢â€ â€™ Stampante
/// con motori FINTI (nessuna dipendenza da hardware).
void main() {
  sqfliteFfiInit();
  // Senza isolate: le future del DB completano come microtask anche nel
  // widget test runner (pattern di onboarding_flow_test).
  databaseFactory = databaseFactoryFfiNoIsolate;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late HaccpRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('printer_settings');
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

  /// Le scritture del DB completano sul loop reale: flush prima delle
  /// asserzioni (pattern di onboarding_flow_test).
  Future<void> flushDb(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PrinterSettingsScreen(
          repository: repository,
          // Motori FINTI (Prompt 11, Ã‚Â§5): nessun hardware coinvolto,
          // stessi id e nomi dei reali.
          engines: [
            _FakeEngine('brother', 'Brother QL'),
            _FakeEngine('niimbot', 'Niimbot'),
            _FakeEngine('generic', 'Stampante generica'),
            _FakeEngine('system', 'Stampa di sistema'),
          ],
        ),
      ),
    );
    await tester.pump();
    await flushDb(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('quattro motori e app usabile senza stampante', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);
      expect(find.text('Brother QL'), findsOneWidget);
      expect(find.text('Niimbot'), findsOneWidget);
      expect(find.text('Stampante generica'), findsOneWidget);
      expect(find.text('Stampa di sistema'), findsOneWidget);
      expect(
        find.textContaining('senza stampante'),
        findsOneWidget,
        reason: 'l\'app resta usabile senza stampante',
      );
      expect(find.text('Stampa etichetta di prova'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('la scelta del motore persiste', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);
      await tester.tap(find.text('Stampante generica'));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));

      final engine = await tester.runAsync(
        () => repository.getSetting('printer_engine'),
      );
      expect(engine, 'generic');
      expect(
        find.textContaining('Trasporto'),
        findsOneWidget,
        reason: 'la sezione di configurazione generica compare',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('stampa di sistema: nessuna ricerca dispositivi', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);
      await tester.tap(find.text('Stampa di sistema'));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));

      final engine = await tester.runAsync(
        () => repository.getSetting('printer_engine'),
      );
      expect(engine, 'system');
      expect(find.textContaining('Cerca stampanti'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('formato etichetta persiste', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);
      await tester.tap(find.text('50 \u00D7 30 mm'));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));

      final format = await tester.runAsync(
        () => repository.getSetting('printer_label_format'),
      );
      final labelFormat = await tester.runAsync(
        () => repository.getSetting('label_format'),
      );
      expect(format, '50x30');
      expect(labelFormat, '50x30',
          reason: 'il formato resta allineato a quello del wizard');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('avvisi permanenti Niimbot e generica', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpScreen(tester);

      await tester.tap(find.text('Niimbot'));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('protocollo non ufficiale'), findsOneWidget);

      await tester.tap(find.text('Stampante generica'));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('compatibilit\u00E0 non garantita'),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('Prompt 17, fix "Cerca stampanti" con BT classico + ESC/POS', () {
    testWidgets(
        'la ricerca usa il trasporto selezionato e mostra i dispositivi '
        'associati (motore generico reale)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.runAsync(() async {
          await repository.setSetting('printer_engine', 'generic');
          await repository.setSetting('printer_generic_transport', 'bluetooth');
          await repository.setSetting('printer_generic_language', 'escpos');
        });
        tester.view.physicalSize = const Size(412, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        // Motore generico REALE con elenco associato finto: il bug era
        // che la schermata ripristinava transport='wifi' prima della
        // ricerca, e discover() restituiva sempre una lista vuota.
        final engine = GenericLabelPrinter(
          pairedLister: () async => const [
            (name: 'MTP-58 Printer', address: 'AA:BB:CC:DD:EE:01'),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: PrinterSettingsScreen(
              repository: repository,
              engines: [engine],
            ),
          ),
        );
        await tester.pump();
        await flushDb(tester);
        await tester.pump(const Duration(milliseconds: 300));

        // Trasporto salvato mostrato nel menu.
        expect(find.textContaining('Bluetooth classico'), findsWidgets);

        // Ricerca: il dispositivo associato compare nell'elenco.
        await tester.tap(find.text('Cerca stampanti'));
        await tester.pump();
        await flushDb(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(engine.config.transport, 'bluetooth',
            reason: 'la ricerca NON deve ripristinare wifi (bug fix)');
        expect(engine.config.language, GenericLanguage.escpos);
        expect(find.text('MTP-58 Printer'), findsOneWidget,
            reason: 'il dispositivo associato appare tra i risultati');
        expect(find.text('Collega'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('"Salva e collega" non ripristina wifi con BT selezionato',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.runAsync(() async {
          await repository.setSetting('printer_engine', 'generic');
          await repository.setSetting('printer_generic_transport', 'bluetooth');
        });
        tester.view.physicalSize = const Size(412, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: PrinterSettingsScreen(
              repository: repository,
              engines: [
                GenericLabelPrinter(
                  pairedLister: () async => const [
                    (name: 'MTP-58 Printer', address: 'AA:BB:CC:DD:EE:01'),
                  ],
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        await flushDb(tester);
        await tester.pump(const Duration(milliseconds: 300));

        await tester.scrollUntilVisible(
          find.text('Salva e collega'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Salva e collega'));
        await flushDb(tester);
        await tester.pump(const Duration(milliseconds: 300));

        final saved = await tester.runAsync(() => repository.getSetting(
              'printer_generic_transport',
            ));
        expect(saved, 'bluetooth',
            reason: 'il salvataggio mantiene il trasporto scelto');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('Prompt 16, Ã‚Â§6: form generica senza overflow', () {
    Future<void> pumpGeneric(
      WidgetTester tester, {
      required Size size,
      double textScale = 1.0,
      String transport = 'wifi',
      EdgeInsets viewPadding = EdgeInsets.zero,
    }) async {
      await tester.runAsync(() async {
        await repository.setSetting('printer_engine', 'generic');
        await repository.setSetting('printer_generic_transport', transport);
      });
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(padding: viewPadding),
              child: PrinterSettingsScreen(
                repository: repository,
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
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));
    }

    for (final (size, scale, transport) in const [
      (Size(320, 640), 1.0, 'wifi'),
      (Size(320, 640), 1.15, 'wifi'),
      (Size(320, 640), 1.0, 'ble'),
      (Size(320, 640), 1.15, 'ble'),
      (Size(360, 640), 1.15, 'ble'),
      (Size(360, 640), 1.0, 'bluetooth'),
      (Size(320, 640), 1.15, 'bluetooth'),
      (Size(412, 915), 1.0, 'wifi'),
      (Size(412, 915), 1.15, 'ble'),
    ]) {
      testWidgets('nessun overflow ${size.width}dp scala $scale ($transport)',
          (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await pumpGeneric(tester,
              size: size, textScale: scale, transport: transport);

          expect(tester.takeException(), isNull,
              reason: 'overflow con $transport a ${size.width} '
                  'scala $scale');

          // Scorrere fino al form (il menu ÃƒÂ¨ sotto le card dei motori).
          await tester.scrollUntilVisible(
            find.text('Linguaggio'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(find.text('Linguaggio'), findsOneWidget);
          expect(find.text('Risoluzione'), findsOneWidget);
          // Larghezza carta: solo ESC/POS (default).
          expect(find.text('Larghezza carta'), findsOneWidget);

          // "Salva e collega" a larghezza piena (52 di altezza).
          await tester.scrollUntilVisible(
            find.text('Salva e collega'),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pump();
          final salva = tester.getRect(
            find.widgetWithText(FilledButton, 'Salva e collega'),
          );
          final contentWidth = size.width - 32;
          expect(salva.width, closeTo(contentWidth, 0.5));
          expect(salva.height, 52);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    testWidgets(
        'inset 48: ultima card sopra la barra di sistema (Prompt 14/16)',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pumpGeneric(
          tester,
          size: const Size(360, 640),
          viewPadding: const EdgeInsets.only(bottom: 48),
        );

        expect(tester.takeException(), isNull);
        // L'ultimo elemento della sezione generica (diagnostica + guida)
        // resta sopra la barra di sistema.
        await tester.scrollUntilVisible(
          find.text('La stampante non stampa?'),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle(const Duration(milliseconds: 200));
        final guida = tester.getRect(
          find.text('La stampante non stampa?'),
        );
        expect(guida.bottom, lessThanOrEqualTo(640 - 48),
            reason: 'la guida/ultima sezione non finisce sotto i tasti');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}

/// Motore finto con id/nome configurabili: nessun hardware coinvolto.
class _FakeEngine implements LabelPrinter {
  _FakeEngine(this.id, this.displayName);

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
