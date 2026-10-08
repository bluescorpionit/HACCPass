import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/screens/first_run_choice_screen.dart';

/// Prompt 12, §A/H: la scelta "Nuova attività / Ripristina" e la
/// definizione di database "vuoto" che la governa.
void main() {
  sqfliteFfiInit();
  // Senza isolate: le future del DB completano anche nel widget test.
  databaseFactory = databaseFactoryFfiNoIsolate;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('first_run_test');
    appDatabase = AppDatabase(
      path:
          '${tempDir.path}/db_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
  });

  tearDown(() async {
    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  group('database "vuoto" (visibilità della schermata)', () {
    test('installazione nuova: vuoto (il seed NON conta come dati)',
        () async {
      expect(await repository.isOnboardingDone(), isFalse);
      expect(await repository.isDatabaseEmpty(), isTrue,
          reason: 'attrezzature e pulizie di esempio non sono dati');
    });

    test('azienda configurata: NON vuoto', () async {
      await repository.setSetting('company_name', 'Bar Centrale');
      await repository.setSetting('company_vat', '01234567890');
      expect(await repository.isDatabaseEmpty(), isFalse);
    });

    test('una registrazione qualsiasi: NON vuoto', () async {
      final equipment =
          (await repository.getEquipment()).first;
      await repository.saveTemperature(
        equipment: equipment,
        temperature: 4,
        operatorName: 'Op',
      );
      expect(await repository.isDatabaseEmpty(), isFalse);
    });

    test('un allegato: NON vuoto', () async {
      await appDatabase.db.insert('attachments', {
        'entity_type': 'receipt',
        'entity_id': 1,
        'kind': 'photo',
        'file_name': 'a.jpg',
        'local_path': 'x/a.jpg',
        'mime': 'image/jpeg',
        'size': 1,
        'created_at': DateTime.now().toIso8601String(),
      });
      expect(await repository.isDatabaseEmpty(), isFalse);
    });

    test('aziende senza P.IVA ma con nome reale: NON vuota', () async {
      await repository.setSetting('company_name', 'Da Gigi');
      expect(await repository.isDatabaseEmpty(), isFalse);
    });
  });

  group('FirstRunChoiceScreen', () {
    testWidgets('due scelte grandi e "Più tardi", i callback scattano',
        (tester) async {
      var newActivity = 0;
      var restore = 0;
      await tester.pumpWidget(MaterialApp(
        home: FirstRunChoiceScreen(
          onNewActivity: () async => newActivity++,
          onRestore: () async => restore++,
        ),
      ));

      expect(find.text('Nuova attività'), findsOneWidget);
      expect(find.text('Ho già usato HACCPass'), findsOneWidget);
      expect(find.text('Più tardi'), findsOneWidget);

      await tester.tap(find.text('Nuova attività'));
      await tester.pump();
      expect(newActivity, 1);

      await tester.tap(find.text('Più tardi'));
      await tester.pump();
      expect(newActivity, 2,
          reason: '"Più tardi" equivale a "Nuova attività"');

      await tester.tap(find.text('Ho già usato HACCPass'));
      await tester.pump();
      expect(restore, 1);
    });

    testWidgets('la scelta del ripristino spiega Drive e file',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: FirstRunChoiceScreen(
          onNewActivity: () async {},
          onRestore: () async {},
        ),
      ));
      expect(
        find.textContaining('Ripristina i miei dati'),
        findsOneWidget,
      );
      expect(
        find.textContaining('telefono'),
        findsWidgets,
        reason: 'il sottotitolo spiega il ripristino su telefono nuovo',
      );
    });
  });
}
