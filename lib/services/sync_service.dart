import 'dart:io';

import '../repositories/haccp_repository.dart';
import 'cloud/cloud_storage.dart';

/// Processa la coda di caricamento (`sync_queue`): PDF e allegati vanno
/// nella cartella cloud del cliente quando un servizio \u00E8 collegato.
///
/// Errori comprensibili e retry con backoff: mai bloccare l'uso dell'app.
/// Su iOS i caricamenti in background sono limitati: la coda si svuota
/// quando l'app \u00E8 aperta.
class SyncService {
  SyncService({required this.repository});

  static SyncService? instance;

  final HaccpRepository repository;
  CloudStorageProvider? cloud;

  int get pendingCount => _pending;

  var _pending = 0;

  /// Elabora tutta la coda. Ritorna il numero di file caricati.
  Future<int> processQueue({
    void Function(int pending)? onPending,
  }) async {
    final provider = cloud;
    if (provider == null || !provider.isConnected) return 0;

    final queue = await repository.getSyncQueue();
    _pending = queue.length;
    onPending?.call(_pending);

    var uploaded = 0;
    for (final entry in queue) {
      final id = (entry['id'] as num).toInt();
      final kind = entry['kind'] as String? ?? '';
      final localPath = entry['local_path'] as String? ?? '';
      final folder = entry['remote_folder'] as String? ?? 'Report';
      final attempts = (entry['attempts'] as num?)?.toInt() ?? 0;
      final attachmentId = (entry['attachment_id'] as num?)?.toInt();

      if (localPath.isEmpty || !await isReadableFile(localPath)) {
        await repository.dequeueSync(id);
        _pending--;
        onPending?.call(_pending);
        continue;
      }

      try {
        final remoteId = await provider.upload(
          path: localPath,
          remoteName: _remoteName(localPath),
          folder: folder,
        );
        // Legame allegato ↔ file remoto (Prompt 12, §D): dopo l'upload
        // si registra quale file di Drive corrisponde all'allegato, così
        // dopo un ripristino si sa cosa riscaricare.
        if (kind == 'attachment' && attachmentId != null) {
          await repository.updateAttachmentSync(
            id: attachmentId,
            cloudId: remoteId,
            syncedAt: DateTime.now(),
          );
        }
        await repository.dequeueSync(id);
        uploaded++;
      } catch (e) {
        final message = provider.humanError(e);
        // Backoff crescente; oltre 5 tentativi la voce resta in coda
        // visibile con l'ultimo errore.
        await repository.updateSyncQueueEntry(
          id,
          attempts: attempts + 1,
          lastError: message,
        );
        if (attempts + 1 >= 5) {
          // Lascia la voce in coda ma non blocca le successive.
          continue;
        }
      }
      _pending--;
      onPending?.call(_pending);
    }

    _pending = (await repository.getSyncQueue()).length;
    onPending?.call(_pending);
    return uploaded;
  }

  String _remoteName(String path) {
    final segments = path.replaceAll('\\', '/').split('/');
    return segments.last;
  }

  /// Accoda il PDF di un report generato, se il cloud \u00E8 attivo.
  Future<void> enqueuePdf(String localPath) {
    return repository.enqueueSync(
      kind: 'pdf',
      localPath: localPath,
      remoteFolder: 'Report',
    );
  }
}

/// Inizializzazione del task in background Android (workmanager).
/// Su iOS non registrato: la coda si svuota con l'app aperta.
void registerBackgroundSync() {
  if (!Platform.isAndroid) return;
  // La registrazione effettiva avviene in main.dart dopo la creazione dei
  // servizi, per avere disponibile [SyncService.instance].
}
