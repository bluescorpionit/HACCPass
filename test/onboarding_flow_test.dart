import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/onboarding/onboarding_screen.dart';
import 'package:haccpass/services/attachment_service.dart';
import 'package:haccpass/services/license_service.dart';
import 'package:haccpass/services/reminder_service.dart';

void main() {
  // Il wizard non usa lo store: forzando la piattaforma "desktop" il
  // servizio licenza salta in_app_purchase (che nel loop di test esplode
  // con un channel-error del plugin Android non catturabile). Settata e
  // azzerata intorno a OGNI test: le variabili debug foundation devono
  // essere ripristinate prima della verifica invarianti del framework.
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  sqfliteFfiInit();
  // Senza isolate: le future del DB completano come microtask anche nel
  // widget test runner (che non esegue I/O reale del loop di eventi).
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bh_wizard_test');
    appDatabase = AppDatabase(
      path: '${tempDir.path}/wizard_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  /// Le operazioni DB passano dall'isolate di sqflite_ffi: le loro future
  /// consegnano solo sul loop di eventi reale, non nel FakeAsync del widget
  /// test. Questo flush le completa prima delle asserzioni.
  Future<void> flushDb(WidgetTester tester) => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );

  Future<void> pumpWizard(WidgetTester tester) async {
    final license = LicenseService(
      readSetting: (key) async {
        final value = await repository.getSetting(key);
        return value.isEmpty ? null : value;
      },
      writeSetting: repository.setSetting,
    );
    // In ambiente test lo store non risponde: inizializzazione non attesa
    // (i passi 0-1 del wizard non usano la licenza).
    unawaited(license.initialize().catchError((_) {}));

    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          repository: repository,
          license: license,
          attachments: AttachmentService(repository: repository),
          reminders: ReminderService(repository: repository),
          onFinished: () {},
        ),
      ),
    );
    // Durata fissa: pumpAndSettle pu\u00F2 non terminare per animazioni
    // ripetute dell'indicatore in ambiente test.
    await tester.pump();
    await flushDb(tester);
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('spuntare i termini abilita il pulsante Avanti', (tester) async {
    // vedi setUp: la variabile debug va ripristinata DENTRO il corpo del
    // test (la verifica invarianti gira prima del tearDown).
    try {
      await pumpWizard(tester);

      // Al passo 0 il pulsante Avanti \u00E8 disabilitato senza consenso.
      var button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull,
          reason: 'Avanti deve essere disabilitato prima del consenso');

      await tester.tap(find.byType(CheckboxListTile));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));

      button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull,
          reason: 'la spunta dei termini deve abilitare Avanti');

      // Il consenso viene persistito (lettura DB sul loop reale: vedi
      // flushDb).
      final terms = await tester.runAsync(
        () => repository.getSetting('terms_accepted_at'),
      );
      expect(terms, isNotEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('senza tipo di attivit\u00E0 il passo 1 resta bloccato',
      (tester) async {
    try {
      await pumpWizard(tester);

      // Accetta i termini e avanza al passo 1.
      await tester.tap(find.byType(CheckboxListTile));
      await flushDb(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(FilledButton));
      // next() persiste il passo su DB: flush prima di aspettare la pagina.
      await flushDb(tester);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // La pagina del passo 1 \u00E8 effettivamente costruita.
      expect(find.text('Bar / Caffetteria'), findsOneWidget);

      var button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull,
          reason: 'Avanti disabilitato senza tipi selezionati');

      // Sceglie il primo modello di attivit\u00E0.
      await tester.ensureVisible(find.text('Bar / Caffetteria'));
      await tester.tap(find.text('Bar / Caffetteria'));
      await tester.pump(const Duration(milliseconds: 300));

      button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNotNull,
          reason: 'la selezione del tipo di attivit\u00E0 deve abilitare Avanti');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
