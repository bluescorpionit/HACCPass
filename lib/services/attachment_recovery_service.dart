import 'dart:io';

import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import 'attachment_service.dart';
import 'cloud/cloud_storage.dart';

/// Esito del recupero di UNA foto mancante.
enum AttachmentRecoverStatus {
  /// File scaricato dal cloud (per `cloud_id` o per nome nella cartella
  /// `Foto`) e miniatura rigenerata.
  recovered,

  /// Il file locale esiste già: nessun download necessario.
  alreadyPresent,

  /// Nessuna copia trovata nel cloud.
  notFound,

  /// Errore di rete/scrittura: si riprova più tardi (mai un crash).
  failed,
}

/// Recupero delle foto dopo un ripristino da backup di solo database
/// (Prompt 12, §D.3).
///
/// Per ogni allegato il cui file locale manca:
/// - se ha `cloud_id`, scarica il file da Drive con quell'id;
/// - altrimenti prova PER NOME FILE nella cartella `Foto` (i nomi sono
///   unici, vedi `AttachmentService._uniqueName`) e, se lo trova, scrive
///   `cloud_id`/`synced_at` sull'allegato;
/// - le miniature si rigenerano dall'originale scaricato.
class AttachmentRecoveryService {
  AttachmentRecoveryService({
    required this.repository,
    required this.cloud,
    AttachmentService? attachments,
  }) : attachments = attachments ?? AttachmentService(repository: repository);

  final HaccpRepository repository;
  final CloudStorageProvider cloud;
  final AttachmentService attachments;

  List<CloudFile>? _fotoCache;

  /// Allegati il cui file locale manca (record non "liberato"
  /// volontariamente: quelli offloaded sono "Solo su Drive" per scelta).
  Future<List<Attachment>> missingLocalAttachments() async {
    final all = await repository.getAllAttachments();
    final missing = <Attachment>[];
    for (final a in all) {
      if (a.isOffloaded) continue;
      if (!await File(a.localPath).exists()) missing.add(a);
    }
    return missing;
  }

  /// Recupera tutte le foto mancanti. [onProgress] riceve (recuperate,
  /// totali); [shouldCancel] interrompe dopo il file corrente: il
  /// recupero è ripremibile chiamando di nuovo questo metodo.
  Future<int> recoverAll({
    void Function(int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final missing = await missingLocalAttachments();
    var done = 0;
    for (final attachment in missing) {
      if (shouldCancel?.call() ?? false) break;
      final status = await recoverOne(attachment);
      if (status == AttachmentRecoverStatus.recovered) done++;
      onProgress?.call(done, missing.length);
    }
    return done;
  }

  /// Recupera una singola foto (usato da "Scarica quando servono": il
  /// segnaposto "Scarica" scarica al tocco).
  Future<AttachmentRecoverStatus> recoverOne(Attachment attachment) async {
    final local = File(attachment.localPath);
    if (await local.exists()) {
      return AttachmentRecoverStatus.alreadyPresent;
    }
    try {
      await Directory(File(attachment.localPath).parent.path)
          .create(recursive: true);

      // 1. Copia nota: id del file remoto registrato all'upload.
      var cloudId = attachment.cloudId;
      if (cloudId != null && cloudId.isNotEmpty) {
        await cloud.download(cloudId, attachment.localPath);
      } else {
        // 2. Ricerca per nome file nella cartella Foto.
        cloudId = await _findInFotoByName(attachment.fileName);
        if (cloudId == null) return AttachmentRecoverStatus.notFound;
        await cloud.download(cloudId, attachment.localPath);
        await repository.updateAttachmentSync(
          id: attachment.id,
          cloudId: cloudId,
          syncedAt: DateTime.now(),
        );
      }

      if (attachment.mime == 'image/jpeg') {
        final thumb = await attachments.regenerateThumbnail(
          attachment.localPath,
        );
        if (thumb != null && (attachment.thumbPath == null ||
            attachment.thumbPath!.isEmpty)) {
          await repository.updateAttachmentThumb(attachment.id, thumb);
        }
      }
      await repository.clearAttachmentOffloaded(attachment.id);
      return AttachmentRecoverStatus.recovered;
    } on CloudDownloadCancelled {
      rethrow;
    } catch (_) {
      // Rete assente o scrittura non riuscita: la foto resta
      // "non ancora scaricata", nessun errore bloccante.
      if (await local.exists()) {
        try {
          await local.delete();
        } catch (_) {}
      }
      return AttachmentRecoverStatus.failed;
    }
  }

  Future<String?> _findInFotoByName(String fileName) async {
    if (!cloud.isConnected) return null;
    final files = _fotoCache ??= await cloud.list('Foto');
    for (final f in files) {
      if (f.name == fileName) return f.id;
    }
    return null;
  }
}
