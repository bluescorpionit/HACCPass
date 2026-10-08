import '../repositories/haccp_repository.dart';
import 'backup_service.dart';
import 'cloud/cloud_storage.dart';

/// Esito del controllo/esecuzione del backup automatico giornaliero.
enum DailyBackupOutcome {
  /// Backup creato e caricato.
  backedUp,

  /// Meno di 24 ore dall'ultimo: nulla da fare.
  notDueYet,

  /// Onboarding non completato o scelta del primo avvio non fatta:
  /// MAI un backup prima del ripristino (Prompt 12, §E).
  skippedIncompleteSetup,

  /// Database vuoto: nessun backup. Se il cloud contiene già backup
  /// l'utente va invitato a ripristinare, non a sovrascrivere.
  skippedEmptyDatabase,

  /// Database vuoto E il cloud contiene già backup: invito a
  /// ripristinare (messaggio all'utente).
  invitedToRestore,

  /// Provider non disponibile o errore: silenzio, si riprova al
  /// prossimo avvio/resume.
  skippedNoCloud,

  /// Backup tentato ma non riuscito: mai bloccante.
  failed,
}

/// Backup automatico giornaliero (Prompt 12, §E): alla prima apertura
/// utile, una volta ogni 24 ore, solo con cloud collegato, MAI con
/// database vuoto o prima che l'utente abbia scelto come partire.
class DailyBackupScheduler {
  DailyBackupScheduler({required this.repository, required this.backup});

  final HaccpRepository repository;
  final BackupService backup;

  Future<DailyBackupOutcome> run(CloudStorageProvider? provider) async {
    if (provider == null || !provider.isConnected) {
      return DailyBackupOutcome.skippedNoCloud;
    }

    // Mai prima del ripristino: setup completato e scelta fatta.
    if (await repository.getSetting('onboarding_done') != '1') {
      return DailyBackupOutcome.skippedIncompleteSetup;
    }
    if (await repository.getSetting('first_run_choice_done') != '1') {
      return DailyBackupOutcome.skippedIncompleteSetup;
    }

    if (await repository.isDatabaseEmpty()) {
      // Un backup di un database vuoto non deve mai diventare "il più
      // recente" nella cartella Backup del cloud.
      try {
        final backups = await provider.list('Backup');
        if (backups.any(
          (f) => f.name.startsWith(BackupService.backupPrefix),
        )) {
          return DailyBackupOutcome.invitedToRestore;
        }
      } catch (_) {
        // Elenco non disponibile: silenzio.
      }
      return DailyBackupOutcome.skippedEmptyDatabase;
    }

    final last = DateTime.tryParse(
      await repository.getSetting('last_auto_backup_at'),
    );
    final now = DateTime.now();
    if (last != null && now.difference(last).inHours < 24) {
      return DailyBackupOutcome.notDueYet;
    }

    try {
      // Il backup automatico non usa password (non può chiederla in
      // automatico): resta protetto dall'account cloud del cliente. Il
      // backup manuale cifrato resta disponibile.
      final path = await backup.createBackup();
      await backup.uploadBackup(provider, path);
      await repository.setSetting(
        'last_auto_backup_at',
        now.toIso8601String(),
      );
      return DailyBackupOutcome.backedUp;
    } catch (_) {
      // Il backup automatico non deve mai interrompere l'uso dell'app.
      return DailyBackupOutcome.failed;
    }
  }
}
