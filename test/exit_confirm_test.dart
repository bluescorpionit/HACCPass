import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/app_shell.dart';
import 'package:haccpass/services/attachment_service.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/license_service.dart' show LicenseService;
import 'package:haccpass/services/reminder_service.dart';
import 'package:haccpass/services/sync_service.dart';
import 'package:haccpass/widgets/common_widgets.dart' show AppBottomBar;

/// Prompt 14, §3: conferma di uscita con il tasto Indietro.
/// (a) da "Oggi" dialog con Resta/Esci; (b) da altra scheda si torna a
/// "Oggi"; (c) con schermata pushata Indietro la chiude; (d) con foglio
/// modale Indietro chiude il foglio. Mai dialog fuori dalla radice.
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  initializeDateFormatting('it_IT');
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase db;
  late HaccpRepository repository;
  var exitCalls = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('exit_confirm');
  });

  setUp(() async {
    final dir = await tempDir.createTemp('db');
    db = AppDatabase(path: p.join(dir.path, 'blue_haccp.db'));
    await db.initialize();
    repository = HaccpRepository(db);
    exitCalls = 0;
  });

  tearDown(() async {
    await db.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          repository: repository,
          license: _StubLicense(),
          sync: SyncService(repository: repository),
          backup: BackupService(
            repository: repository,
            appVersion: 'test',
            attachmentsRootOverride: p.join(tempDir.path, 'attachments'),
          ),
          attachments: AttachmentService(repository: repository),
          reminders: ReminderService(repository: repository),
          onConfirmExit: () async => exitCalls++,
        ),
      ),
    );
    await tester.pump();
    // Le schermate della shell caricano dal database: dare tempo reale
    // alle future (pattern di onboarding_flow_test) e renderizzare.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets(
      '(a) da "Oggi" Indietro mostra il dialog; Resta chiude solo il dialog',
      (tester) async {
    // Android: il PopScope della conferma d'uscita \u00E8 attivo (su\r\n    // desktop il widget non intercetta).\r\n    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpShell(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Uscire da HACCPass?'), findsOneWidget);
      expect(find.textContaining('dati sono al sicuro'), findsOneWidget);
      expect(exitCalls, 0);

      await tester.tap(find.text('Resta'));
      await tester.pump();
      expect(find.text('Uscire da HACCPass?'), findsNothing);
      expect(exitCalls, 0, reason: 'Resta non chiude l\'app');

      // Secondo tentativo: "Esci" chiama l'handler iniettato.
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.tap(find.text('Esci'));
      await tester.pump();
      expect(exitCalls, 1, reason: 'Esci chiude l\'app (handler iniettato)');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(b) da un\'altra scheda Indietro torna a "Oggi" senza dialog',
      (tester) async {
    // Android: il PopScope della conferma d'uscita \u00E8 attivo (su\r\n    // desktop il widget non intercetta).\r\n    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpShell(tester);

      // Passa alla scheda "Controlli" (indice 1).
      await tester.tap(find.text('Controlli'));
      await tester.pump(const Duration(milliseconds: 200));
      final bar = tester.widget<AppBottomBar>(find.byType(AppBottomBar));
      expect(bar.currentIndex, 1);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Uscire da HACCPass?'), findsNothing,
          reason: 'nessun dialog: si torna alla scheda Oggi');
      expect(exitCalls, 0);
      final barAfter = tester.widget<AppBottomBar>(find.byType(AppBottomBar));
      expect(barAfter.currentIndex, 0, reason: 'torna alla scheda "Oggi"');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(c) con schermata pushata Indietro la chiude senza dialog',
      (tester) async {
    // Android: il PopScope della conferma d'uscita \u00E8 attivo (su\r\n    // desktop il widget non intercetta).\r\n    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpShell(tester);

      final navigator =
          tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Center(child: Text('Spinta'))),
      ));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Spinta'), findsNothing, reason: 'la pushata si chiude');
      expect(find.text('Uscire da HACCPass?'), findsNothing,
          reason: 'nessun dialog sotto una route pushata');
      expect(exitCalls, 0);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('(d) con foglio modale Indietro chiude il foglio senza dialog',
      (tester) async {
    // Android: il PopScope della conferma d'uscita \u00E8 attivo (su\r\n    // desktop il widget non intercetta).\r\n    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await pumpShell(tester);

      final context = tester.element(find.byType(AppShell));
      // NON aspettare qui: la future del foglio completa solo alla
      // chiusura (aspettarla ora sarebbe un deadlock nel FakeAsync).
      final sheetFuture = showModalBottomSheet<void>(
        context: context,
        builder: (sheetContext) =>
            const SizedBox(height: 150, child: Center(child: Text('Foglio'))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Foglio'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Foglio'), findsNothing, reason: 'il foglio si chiude');
      expect(find.text('Uscire da HACCPass?'), findsNothing);
      expect(exitCalls, 0);
      await sheetFuture; // ora completa: il foglio è stato chiuso.
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

/// Stub di LicenseService: costruire quella reale avvia in_app_purchase,
/// che nel loop di test esplode con una PlatformException (canale pigeon).
class _StubLicense implements LicenseService {
  @override
  bool get canWrite => true;

  @override
  bool get trialActive => false;

  @override
  String get chipLabel => 'Prova: 14 giorni';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('stub LicenseService');
}
