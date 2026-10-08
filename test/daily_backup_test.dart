import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/daily_backup.dart';

import 'fakes/fake_cloud.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory baseDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;
  late BackupService backup;
  late FakeCloudProvider cloud;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('daily_backup_test');
  });

  setUp(() async {
    baseDir = await tempDir.createTemp('base');
    appDatabase = AppDatabase(
      path: '${baseDir.path}/db_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
    backup = BackupService(
      repository: repository,
      appVersion: 'test',
      attachmentsRootOverride: '${baseDir.path}/attachments',
    );
    cloud = FakeCloudProvider();
  });

  tearDown(() async {
    await appDatabase.close();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });

  /// App "pronta": onboarding completato, scelta fatta e dati presenti.
  Future<void> seedReadyApp() async {
    await repository.setSetting('onboarding_done', '1');
    await repository.setSetting('first_run_choice_done', '1');
    await repository.setSetting('company_name', 'Trattoria da test');
    await repository.setSetting('company_vat', '01234567890');
  }

  test('parte dopo 24 ore con dati e carica il backup', () async {
    await seedReadyApp();
    await repository.setSetting(
      'last_auto_backup_at',
      DateTime.now().subtract(const Duration(hours: 25)).toIso8601String(),
    );

    final scheduler =
        DailyBackupScheduler(repository: repository, backup: backup);
    final outcome = await scheduler.run(cloud);

    expect(outcome, DailyBackupOutcome.backedUp);
    expect(cloud.uploadCalls, 1);
    expect(cloud.uploads.single, startsWith('HACCPass_backup_'));
    final last = await repository.getSetting('last_auto_backup_at');
    expect(DateTime.tryParse(last)!.isAfter(DateTime.now().subtract(
      const Duration(minutes: 1),
    )), isTrue);
  });

  test('non parte se l\'ultimo backup ha meno di 24 ore', () async {
    await seedReadyApp();
    await repository.setSetting(
      'last_auto_backup_at',
      DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    );

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.notDueYet);
    expect(cloud.uploadCalls, 0);
  });

  test('non parte con database vuoto (nessun caricamento)', () async {
    await repository.setSetting('onboarding_done', '1');
    await repository.setSetting('first_run_choice_done', '1');
    // Database vuoto: azienda non configurata, nessuna registrazione.

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.skippedEmptyDatabase);
    expect(cloud.uploadCalls, 0);
  });

  test('database vuoto con backup in cloud: invito a ripristinare, mai upload',
      () async {
    await repository.setSetting('onboarding_done', '1');
    await repository.setSetting('first_run_choice_done', '1');
    cloud.backupFiles.add(backupFile('HACCPass_backup_20260101_1000.bhb'));

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.invitedToRestore);
    expect(cloud.uploadCalls, 0,
        reason: 'un backup vuoto non deve mai sovrascrivere i backup esistenti');
  });

  test('non parte prima della scelta del primo avvio', () async {
    await repository.setSetting('onboarding_done', '1');
    await repository.setSetting('company_name', 'Trattoria da test');
    await repository.setSetting('company_vat', '01234567890');
    // first_run_choice_done NON impostato.

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.skippedIncompleteSetup);
    expect(cloud.uploadCalls, 0);
  });

  test('non parte con onboarding incompleto', () async {
    await repository.setSetting('first_run_choice_done', '1');
    await repository.setSetting('company_name', 'Trattoria da test');
    await repository.setSetting('company_vat', '01234567890');
    // onboarding_done NON impostato.

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.skippedIncompleteSetup);
    expect(cloud.uploadCalls, 0);
  });

  test('senza cloud collegato: esito dedicato', () async {
    await seedReadyApp();
    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(null);
    expect(outcome, DailyBackupOutcome.skippedNoCloud);

    cloud.connected = false;
    expect(
      await DailyBackupScheduler(repository: repository, backup: backup)
          .run(cloud),
      DailyBackupOutcome.skippedNoCloud,
    );
  });

  test('backup non riuscito: mai bloccante, si riprova al prossimo avvio',
      () async {
    await seedReadyApp();
    cloud.uploadError = const SocketException('rete assente');

    final outcome = await DailyBackupScheduler(
      repository: repository,
      backup: backup,
    ).run(cloud);

    expect(outcome, DailyBackupOutcome.failed);
  });
}
