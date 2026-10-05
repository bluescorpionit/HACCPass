import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:blue_haccp/core/database/app_database.dart';
import 'package:blue_haccp/repositories/haccp_repository.dart';
import 'package:blue_haccp/screens/onboarding/onboarding_screen.dart';
import 'package:blue_haccp/services/attachment_service.dart';
import 'package:blue_haccp/services/license_service.dart';
import 'package:blue_haccp/services/reminder_service.dart';

void main() {
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
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('spuntare i termini abilita il pulsante Avanti', (tester) async {
    await pumpWizard(tester);

    // Al passo 0 il pulsante Avanti \u00E8 disabilitato senza consenso.
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull,
        reason: 'Avanti deve essere disabilitato prima del consenso');

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump(const Duration(milliseconds: 300));

    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull,
        reason: 'la spunta dei termini deve abilitare Avanti');

    // Il consenso viene persistito.
    expect(await repository.getSetting('terms_accepted_at'), isNotEmpty);
  });

  testWidgets('senza tipo di attivit\u00E0 il passo 1 resta bloccato',
      (tester) async {
    await pumpWizard(tester);

    // Accetta i termini e avanza al passo 1.
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(FilledButton));
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
  });
}
