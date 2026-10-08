import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/cloud/cloud_storage.dart';
import 'package:haccpass/services/license_service.dart';
import 'package:haccpass/services/restore_service.dart';
import 'package:haccpass/services/sync_service.dart';
import 'package:haccpass/screens/restore_wizard_screen.dart';

import 'fakes/fake_cloud.dart';

/// Prompt 12, H: widget test del wizard di ripristino con provider e
/// servizio di backup finti (lista, cifrato, spazio insufficiente,
/// annulla, nessun backup trovato → fallback file).
///
/// Le future del DB (sqflite_ffi) e di I/O dei file consegnano solo sul
/// loop di eventi reale: ogni attesa diretta passa da `tester.runAsync`
/// e la guida a video alterna pump e flush (pattern di
/// onboarding_flow_test).
void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;
  late BackupService backup;
  late LicenseService license;
  int pickFileCalls = 0;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('wizard_restore_test');
  });

  setUp(() async {
    // Evita il plugin in_app_purchase (channel-error del plugin Android
    // non catturabile nel runner): su "windows" il servizio salta lo
    // store, come in onboarding_flow_test.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final dbPath = p.join(
      tempDir.path,
      'db_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    appDatabase = AppDatabase(path: dbPath);
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
    backup = BackupService(
      repository: repository,
      appVersion: '1.2.3',
      attachmentsRootOverride: p.join(tempDir.path, 'attachments'),
    );
    license = LicenseService(
      readSetting: (key) async {
        final value = await repository.getSetting(key);
        return value.isEmpty ? null : value;
      },
      writeSetting: repository.setSetting,
    );
    pickFileCalls = 0;
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await appDatabase.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// Un passo di avanzamento: pump del frame + flush del loop reale
  /// (completano le future di I/O) + pump del frame risultante.
  Future<void> step(
    WidgetTester tester, {
    Duration frame = const Duration(milliseconds: 50),
    Duration flush = const Duration(milliseconds: 80),
  }) async {
    await tester.pump(frame);
    await tester.runAsync(
      () => Future<void>.delayed(flush),
    );
    await tester.pump(frame);
  }

  /// Crea un backup reale di soli dati e lo registra nel provider finto.
  Future<CloudFile> seedBackup(
    FakeCloudProvider provider,
    String name, {
    String? password,
  }) async {
    await repository.setSetting('company_name', 'Trattoria Uno');
    final path = await backup.createBackup(password: password);
    final file = backupFile(name, size: await File(path).length());
    final remote = p.join(p.dirname(path), name);
    await File(path).rename(remote);
    provider.filesById[file.id] = remote;
    provider.backupFiles.add(file);
    return file;
  }

  Future<void> pumpWizard(
    WidgetTester tester, {
    required FakeCloudProvider provider,
    Future<int?> Function(String)? freeSpace,
    RestoreService? restoreService,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: RestoreWizardScreen(
        repository: repository,
        backup: backup,
        license: license,
        sync: SyncService(repository: repository),
        driveProvider: provider,
        restoreService: restoreService,
        freeSpace: freeSpace ?? (_) async => 100 * 1024 * 1024 * 1024,
        pickFile: () async {
          pickFileCalls++;
          return null;
        },
      ),
    ));
    await tester.pump();
  }

  /// Apre il flusso Drive: sorgente → collega → elenco.
  Future<void> openDriveList(WidgetTester tester) async {
    await tester.tap(find.text('Google Drive').first);
    await step(tester);
    // Il testo compare sia nel titolo sia nel pulsante: mira al pulsante.
    await tester
        .tap(find.widgetWithText(FilledButton, 'Collega Google Drive'));
    // connect + list + peekFirstBytes per ogni voce.
    for (var i = 0; i < 12; i++) {
      await step(tester);
    }
  }

  testWidgets('elenco: tipo, dimensione, badge cifrato, preselezione',
      (tester) async {
    try {
      final provider = FakeCloudProvider();

      // Il seeding chiude/riapre il DB (createBackup): PRIMA di pompare
      // il widget, così nessuna future dell'initState resta orfana.
      await tester.runAsync(() async {
        await seedBackup(provider, 'HACCPass_backup_20260101_0800.bhb');
        await repository.setSetting('company_name', 'Altro telefono');
        final clearPath = await backup.createBackup();
        final clear = backupFile('HACCPass_backup_20261008_0900.bhb',
            size: await File(clearPath).length());
        provider.filesById[clear.id] = clearPath;
        provider.backupFiles.add(clear);

        final encryptedPath = await backup.createBackup(password: 'segreta');
        final enc = backupFile('HACCPass_backup_completo_20261008_0930.bhb',
            size: await File(encryptedPath).length());
        provider.filesById[enc.id] = encryptedPath;
        provider.backupFiles.add(enc);
      });

      await pumpWizard(tester, provider: provider);
      await openDriveList(tester);

      expect(find.text('Solo dati'), findsNWidgets(2));
      expect(find.text('Completo con foto'), findsOneWidget);
      expect(find.textContaining('Cifrato'), findsOneWidget);
      // Il più recente (20261008_0930) è preselezionato e il pulsante attivo.
      expect(find.text('Ripristina questo backup'), findsOneWidget);
    } finally {
      // La verifica invarianti del framework gira PRIMA del tearDown:
      // la variabile debug va ripristinata dentro il corpo.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('nessun backup trovato: spiegazione e fallback con il selettore',
      (tester) async {
    try {
      final provider = FakeCloudProvider();
      await pumpWizard(tester, provider: provider);

      await openDriveList(tester);

      expect(find.textContaining('Nessun backup trovato'), findsOneWidget);
      expect(find.textContaining('drive.file'), findsOneWidget,
          reason: 'spiega il limite dello scope ridotto');

      expect(pickFileCalls, 0);
      await tester.tap(find.textContaining('Scegli un file'));
      await step(tester);
      expect(pickFileCalls, 1, reason: 'fallback sul selettore di sistema');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('spazio insufficiente: messaggio chiaro, nessun download',
      (tester) async {
    try {
      final provider = FakeCloudProvider();
      await tester.runAsync(() async {
        await seedBackup(provider, 'HACCPass_backup_20261008_1000.bhb');
      });

      await pumpWizard(
        tester,
        provider: provider,
        freeSpace: (_) async => 1024, // 1 KB liberi
      );
      await openDriveList(tester);

      await tester.tap(find.text('Ripristina questo backup'));
      await step(tester, flush: const Duration(milliseconds: 150));

      expect(find.textContaining('Spazio insufficiente'), findsOneWidget);
      expect(
        find.textContaining('servono almeno'),
        findsOneWidget,
        reason: 'spiega lo spazio richiesto (2,5 volte il file)',
      );
      expect(provider.downloaded, isEmpty);
      await tester.tap(find.text('Ho capito'));
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('annullamento durante lo scaricamento: si torna all\'elenco',
      (tester) async {
    try {
      final provider = FakeCloudProvider()
        ..downloadError = const CloudDownloadCancelled();
      await tester.runAsync(() async {
        await seedBackup(provider, 'HACCPass_backup_20261008_1100.bhb');
      });

      await pumpWizard(tester, provider: provider);
      await openDriveList(tester);

      await tester.tap(find.text('Ripristina questo backup'));
      for (var i = 0; i < 6; i++) {
        await step(tester);
      }

      // Tornati all'elenco senza errori bloccanti.
      expect(find.text('Ripristina questo backup'), findsOneWidget);
      expect(provider.downloaded, isNotEmpty,
          reason: 'il download era partito');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('ripristino completo dal fake cloud fino al risultato',
      (tester) async {
    try {
      final provider = FakeCloudProvider();
      await tester.runAsync(() async {
        await repository.setSetting('onboarding_done', '1');
        await repository.setSetting('company_name', 'Telefono precedente');
        final path = await backup.createBackup();
        final file = backupFile('HACCPass_backup_20261008_1200.bhb',
            size: await File(path).length());
        provider.filesById[file.id] = path;
        provider.backupFiles.add(file);
      });

      await pumpWizard(
        tester,
        provider: provider,
        restoreService:
            RestoreService(repository: repository, backup: backup),
      );

      await openDriveList(tester);
      await tester.tap(find.text('Ripristina questo backup'));
      for (var i = 0; i < 10; i++) {
        await step(tester);
      }

      // Riepilogo prima della sostituzione.
      expect(find.textContaining('Riepilogo'), findsOneWidget);
      expect(find.textContaining('backup di sicurezza'), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget,
          reason: 'versione app dal manifest');

      await tester.tap(find.text('Ripristina ora'));
      // Il ripristino vero tocca DB e file: molti flush.
      for (var i = 0; i < 60; i++) {
        await step(tester);
      }

      expect(find.textContaining('Ripristino completato'), findsOneWidget);

      await tester.tap(find.text('Continua'));
      for (var i = 0; i < 10; i++) {
        await step(tester);
      }
      expect(find.textContaining('Ripristina i tuoi dati'), findsNothing,
          reason: 'il wizard si è chiuso');

      // I dati del backup sono nel database di destinazione (lettura sul
      // loop reale).
      final companyName = await tester.runAsync(
        () => repository.getSetting('company_name'),
      );
      final onboardingDone = await tester
          .runAsync(() => repository.isOnboardingDone());
      expect(companyName, 'Telefono precedente');
      expect(onboardingDone, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
