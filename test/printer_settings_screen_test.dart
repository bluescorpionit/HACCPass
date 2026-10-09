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

/// Prompt 11, §5: widget test della schermata Impostazioni → Stampante
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
          // Motori FINTI (Prompt 11, §5): nessun hardware coinvolto,
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
      expect(
          find.textContaining('compatibilit\u00E0 non garantita'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
  Future<PrinterStatus> status() async =>
      const PrinterStatus(connected: false);
}
