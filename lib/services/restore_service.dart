import 'dart:io';

import '../core/database/app_database.dart';
import '../repositories/haccp_repository.dart';
import 'backup_service.dart';

/// Fasi del ripristino, mostrate all'utente con il progresso.
enum RestorePhase {
  opening('Lettura del backup'),
  integrity('Verifica integrità'),
  safetyBackup('Backup di sicurezza'),
  replacing('Sostituzione dati'),
  sanitizing('Protezione licenza'),
  realigning('Riallineamento percorsi'),
  attachments('Ripristino foto e allegati'),
  done('Completato');

  const RestorePhase(this.label);

  final String label;
}

class RestoreProgress {
  const RestoreProgress({
    required this.phase,
    required this.message,
    this.done,
    this.total,
  });

  final RestorePhase phase;
  final String message;
  final int? done;
  final int? total;
}

/// Esito di un ripristino riuscito.
class RestoreResult {
  const RestoreResult({
    required this.manifest,
    required this.realignment,
    required this.attachmentsRestored,
    required this.safetyBackupPath,
    required this.onboardingDone,
  });

  final Map<String, Object?> manifest;

  /// Statistiche del riallineamento percorsi (§D).
  final PathRealignmentResult realignment;

  /// Numero di file allegato ripristinati dal backup (0 per i backup di
  /// solo database).
  final int attachmentsRestored;

  /// Percorso del backup di sicurezza dei dati precedenti.
  final String safetyBackupPath;

  /// `onboarding_done` del database ripristinato: se '1' l'app si apre
  /// direttamente nella shell, altrimenti il wizard riprende.
  final bool onboardingDone;
}

/// Orchestrazione del ripristino (Prompt 12, §B): lettura in streaming →
/// verifica integrità → backup di sicurezza → sostituzione DB →
/// sanificazione impostazioni di licenza (§C) → riallineamento percorsi
/// (§D) → ripristino allegati → riapertura DB.
///
/// Se un passo fallisce DOPO la sostituzione del database, il backup di
/// sicurezza viene automaticamente riapplicato: l'app resta nello stato
/// precedente e l'errore viene mostrato.
class RestoreService {
  RestoreService({required this.repository, required this.backup});

  final HaccpRepository repository;
  final BackupService backup;

  AppDatabase get _database => repository.database;

  /// Ripristina un file di backup `.bhb` (solo dati o completo).
  ///
  /// [password] serve solo per i backup cifrati; [shouldCancel] è
  /// controllato tra le fasi e durante il ripristino degli allegati:
  /// l'annullamento riporta il database allo stato precedente.
  Future<RestoreResult> restoreFromFile(
    String path, {
    String? password,
    void Function(RestoreProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    onProgress?.call(const RestoreProgress(
      phase: RestorePhase.opening,
      message: 'Leggo il backup…',
    ));
    final handle = await backup.openBackup(path, password: password);
    try {
      if (shouldCancel?.call() ?? false) {
        throw const BackupCancelledException();
      }

      onProgress?.call(const RestoreProgress(
        phase: RestorePhase.integrity,
        message: 'Verifico l\u2019integrità del database…',
      ));
      if (!await backup.verifyIntegrity(handle.dbPath)) {
        throw const BackupException(
          'Il database nel backup non è integro. Ripristino annullato.',
        );
      }

      onProgress?.call(const RestoreProgress(
        phase: RestorePhase.safetyBackup,
        message: 'Creo un backup di sicurezza dei dati attuali…',
      ));
      final safetyPath = await backup.createBackup();

      // Impostazioni di licenza locali: il ripristino NON importa mai lo
      // stato di licenza dal backup (§C). Si salva PRIMA della
      // sostituzione e si riscrive DOPO.
      final licenseSettings = await repository.readLicenseSettings();

      onProgress?.call(const RestoreProgress(
        phase: RestorePhase.replacing,
        message: 'Sostituisco i dati…',
      ));
      await _replaceDatabase(handle.dbPath);

      try {
        // Data della prova nel database ripristinato: serve per la regola
        // "mai indietro nel tempo" (vedi _withEarliestTrial).
        final restoredTrial =
            DateTime.tryParse(await repository.getSetting('trial_started_at'));

        onProgress?.call(const RestoreProgress(
          phase: RestorePhase.sanitizing,
          message: 'Proteggo lo stato di licenza di questo telefono…',
        ));
        await repository.writeLicenseSettings(
          _withEarliestTrial(licenseSettings, restoredTrial),
        );

        onProgress?.call(const RestoreProgress(
          phase: RestorePhase.realigning,
          message: 'Riallineo i percorsi delle foto…',
        ));
        final root = await backup.attachmentsRootPath();
        final realignment = await repository.realignAttachmentPaths(root);

        var attachmentsRestored = 0;
        if (handle.hasAttachments) {
          attachmentsRestored = await backup.restoreAttachments(
            path,
            onProgress: (done, total) => onProgress?.call(RestoreProgress(
              phase: RestorePhase.attachments,
              message: 'Ripristino foto e allegati $done di $total…',
              done: done,
              total: total,
            )),
            shouldCancel: shouldCancel,
          );
        }

        repository.revision.value++;
        final onboardingDone = await repository.isOnboardingDone();
        onProgress?.call(const RestoreProgress(
          phase: RestorePhase.done,
          message: 'Ripristino completato.',
        ));
        return RestoreResult(
          manifest: handle.manifest,
          realignment: realignment,
          attachmentsRestored: attachmentsRestored,
          safetyBackupPath: safetyPath,
          onboardingDone: onboardingDone,
        );
      } catch (_) {
        // Un fallimento dopo la sostituzione: si torna allo stato
        // precedente con il backup di sicurezza.
        await _rollbackTo(safetyPath);
        rethrow;
      }
    } finally {
      await handle.dispose();
    }
  }

  /// La prova non torna mai indietro nel tempo (regola dell'ancora,
  /// §C): la data effettiva è la più antica tra quella locale e quella
  /// del database ripristinato.
  Map<String, String> _withEarliestTrial(
    Map<String, String> settings,
    DateTime? restored,
  ) {
    if (restored == null) return settings;
    final local = DateTime.tryParse(settings['trial_started_at'] ?? '');
    if (local == null || restored.isBefore(local)) {
      return {...settings, 'trial_started_at': restored.toIso8601String()};
    }
    return settings;
  }

  Future<void> _replaceDatabase(String sourceDbPath) async {
    await repository.closeForBackup();
    try {
      await File(sourceDbPath).copy(_database.path);
    } finally {
      await _database.initialize();
    }
  }

  /// Riapplica il backup di sicurezza dopo un fallimento.
  Future<void> _rollbackTo(String safetyPath) async {
    try {
      final handle = await backup.openBackup(safetyPath);
      try {
        await _replaceDatabase(handle.dbPath);
      } finally {
        await handle.dispose();
      }
      repository.revision.value++;
    } catch (_) {
      // Il rollback è best-effort: l'errore originale resta quello
      // mostrato all'utente. Il backup di sicurezza resta su disco.
    }
  }
}
