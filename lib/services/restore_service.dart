import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/database/app_database.dart';
import '../core/license/app_integrity.dart';
import '../core/license/trial_anchor.dart';
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
    this.trialAnchorSuspect = false,
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

  /// Il backup dichiarava di contenere l'ancora della prova ma questa
  /// era assente o con firma non valida (Prompt 20): nessuna data della
  /// prova è stata importata dal backup, i dati sono ripristinati
  /// comunque.
  final bool trialAnchorSuspect;
}

/// Orchestrazione del ripristino (Prompt 12, §B): lettura in streaming →
/// verifica integrità → backup di sicurezza → sostituzione DB →
/// sanificazione impostazioni di licenza (§C) → riallineamento percorsi
/// (§D) → ripristino allegati → riapertura DB.
///
/// Dal Prompt 20 la data della prova può arrivare anche dall'**ancora
/// firmata** nel manifest del backup: vince la più antica; se l'ancora è
/// assente o alterata in un backup che la dichiarava, NESSUNA data della
/// prova viene presa dal backup (nessun giorno in più), ma i dati si
/// ripristinano comunque. Lo stato dell'abbonamento non viene MAI
/// importato dal backup.
///
/// Se un passo fallisce DOPO la sostituzione del database, il backup di
/// sicurezza viene automaticamente riapplicato: l'app resta nello stato
/// precedente e l'errore viene mostrato.
class RestoreService {
  RestoreService({
    required this.repository,
    required this.backup,
    TrialAnchor? trialAnchor,
  }) : _trialAnchorOverride = trialAnchor;

  final HaccpRepository repository;
  final BackupService backup;

  TrialAnchor? _trialAnchorOverride;

  /// Ancora della prova (iniettabile nei test; default: supporto della
  /// piattaforma con `AppIntegrity.anchorSecret`).
  TrialAnchor get _trialAnchor => _trialAnchorOverride ??=
      TrialAnchor.platform(secret: AppIntegrity.anchorSecret);

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
        // Data della prova nel database ripristinato: è NON firmata, da
        // sola non basta (Prompt 20): la data affidabile è quella
        // nell'ancora firmata del manifest.
        final restoredTrial =
            DateTime.tryParse(await repository.getSetting('trial_started_at'));

        // Ancora firmata del manifest (Prompt 20): il backup porta con
        // sé la data di inizio firmata; rimuoverla o alterarla non
        // regala giorni di prova.
        final anchor = _readBackupTrialAnchor(handle.manifest);
        if (anchor.suspect) {
          debugPrint(
            'Backup con ancora della prova assente o con firma non '
            'valida: nessuna data della prova importata dal backup '
            '(nessun giorno in pi\u00F9), i dati vengono ripristinati.',
          );
        }

        // Data effettiva = la più antica tra telefono, ancora firmata e
        // (se l'ancora non è sospetta) database ripristinato. Con l'ancora
        // sospetta NESSUNA data del backup viene usata: resta quella del
        // telefono (la data non si sposta mai in avanti).
        final localTrial =
            DateTime.tryParse(licenseSettings['trial_started_at'] ?? '');
        final DateTime? effectiveTrial;
        if (anchor.suspect) {
          effectiveTrial = localTrial;
        } else {
          effectiveTrial = _earliest([localTrial, anchor.start, restoredTrial]);
        }

        onProgress?.call(const RestoreProgress(
          phase: RestorePhase.sanitizing,
          message: 'Proteggo lo stato di licenza di questo telefono…',
        ));
        await repository.writeLicenseSettings(
          _withEarliestTrial(licenseSettings, effectiveTrial),
        );

        // Riallinea l'ancora della piattaforma (file/Keychain) con la
        // data effettiva, come fa synchronize (best-effort).
        try {
          await _trialAnchor.synchronize(databaseStart: effectiveTrial);
        } catch (_) {
          // L'ancora locale non blocca mai il ripristino: verrà
          // riallineata da LicenseService.reloadAfterRestore.
        }

        onProgress?.call(const RestoreProgress(
          phase: RestorePhase.realigning,
          message: 'Riallineo i percorsi delle foto…',
        ));
        final root = await backup.attachmentsRootPath();
        final realignment = await repository.realignAttachmentPaths(root);

        var attachmentsRestored = 0;
        if (handle.hasAttachments) {
          attachmentsRestored = await backup.restoreAttachments(
            handle.archivePath,
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
          trialAnchorSuspect: anchor.suspect,
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

  /// Valuta l'ancora firmata del manifest del backup (Prompt 20):
  ///
  /// - presente e con firma valida → [TrialAnchorBackup.start] è la
  ///   data firmata (vince la più antica tra questa, telefono e database
  ///   ripristinato);
  /// - presente ma con firma NON valida, oppure assente mentre il
  ///   backup dichiara `trialAnchorVersion` ≥ 1 (doveva esserci) →
  ///   [TrialAnchorBackup.suspect]: ancora alterata o backup
  ///   incompleto/manomesso. Nessun giorno in più: NESSUNA data della
  ///   prova viene presa dal backup, ma i dati si ripristinano;
  /// - assente in un backup VECCHIO (nessun `trialAnchorVersion`) →
  ///   comportamento storico: conta solo la data del database
  ///   ripristinato con la regola "la più antica vince";
  /// - segreto vuoto (solo debug, vedi `AppIntegrity`) → nessun
  ///   controllo, come i backup vecchi.
  _TrialAnchorBackup _readBackupTrialAnchor(Map<String, Object?> manifest) {
    if (_trialAnchor.secret.isEmpty) {
      // Segreto vuoto (solo debug): nessun controllo, come i backup vecchi.
      return const _TrialAnchorBackup.unchecked();
    }
    final raw = manifest['trialAnchor'] as String?;
    final declaredVersion =
        (manifest['trialAnchorVersion'] as num?)?.toInt() ?? 0;
    if (raw == null || raw.isEmpty) {
      return _TrialAnchorBackup(
        start: null,
        suspect: declaredVersion >= 1,
      );
    }
    final parsed = _trialAnchor.parseSigned(raw);
    if (parsed == null) {
      return const _TrialAnchorBackup(suspect: true);
    }
    return _TrialAnchorBackup(start: parsed.$1, suspect: false);
  }

  /// La più antica tra le date non nulle (null se non ce ne sono).
  DateTime? _earliest(List<DateTime?> dates) {
    final candidates = dates.whereType<DateTime>().toList();
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a.isBefore(b) ? a : b);
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

/// Esito della lettura dell'ancora firmata dal manifest del backup.
class _TrialAnchorBackup {
  const _TrialAnchorBackup({this.start, required this.suspect});

  const _TrialAnchorBackup.unchecked()
      : start = null,
        suspect = false;

  /// Data firmata dell'ancora (solo se la firma è valida).
  final DateTime? start;

  /// Ancora assente mentre doveva esserci, o con firma non valida:
  /// nessuna data della prova dal backup.
  final bool suspect;
}
