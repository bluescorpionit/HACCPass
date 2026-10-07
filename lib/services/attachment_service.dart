import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';

/// Profilo di qualità per le NUOVE foto allegate (l'OCR usa sempre una sua
/// copia temporanea ad alta risoluzione, indipendente da questo profilo).
enum AttachmentQuality {
  risparmio('risparmio', 1280, 70),
  standard('standard', 1600, 80),
  alta('alta', 2000, 85);

  const AttachmentQuality(this.id, this.maxSide, this.quality);

  final String id;

  /// Lato lungo massimo in pixel.
  final int maxSide;
  final int quality;

  String get label => switch (this) {
        AttachmentQuality.risparmio => 'Risparmio (~1280 px)',
        AttachmentQuality.standard => 'Standard (~1600 px)',
        AttachmentQuality.alta => 'Alta (~2000 px)',
      };

  static AttachmentQuality byId(String? id) => AttachmentQuality.values
      .firstWhere((q) => q.id == id, orElse: () => AttachmentQuality.standard);
}

/// Statistiche di spazio degli allegati per la schermata "Spazio e
/// allegati".
class AttachmentStorageStats {
  const AttachmentStorageStats({
    required this.totalBytes,
    required this.fileCount,
    required this.byYear,
    required this.notSyncedCount,
  });

  /// Byte totali dei file locali (anteprime escluse).
  final int totalBytes;
  final int fileCount;

  /// Byte per anno di creazione del record.
  final Map<int, int> byYear;

  /// Allegati senza copia cloud (nessun cloud_id/synced_at): "non ancora
  /// al sicuro".
  final int notSyncedCount;
}

/// Allegato in fase di registrazione: il file vive in una cartella
/// temporanea e diventa record definitivo solo quando il salvataggio
/// della merce/lotto riesce. Se l'utente annulla, i file vengono eliminati:
/// nessun allegato orfano.
class PendingAttachment {
  PendingAttachment({
    required this.tempPath,
    required this.kind,
    this.label,
    this.note,
  });

  final String tempPath;

  /// `photo` o `document`.
  final String kind;

  /// Tipo documentale: DDT, Etichetta/lotto, Certificato, Altro.
  final String? label;
  final String? note;
}

/// Acquisizione e archiviazione di allegati (foto e documenti).
///
/// Le foto vengono compresse secondo il profilo di qualità scelto (vedi
/// [AttachmentQuality], standard: lato lungo ~1600 px, qualità ~80) prima
/// di essere salvate in `attachments/AAAA/MM/` nella cartella documenti
/// privata dell'app. I documenti vengono copiati cos\u00EC come sono.
///
/// V6 (Prompt 8, parte B): ogni file viene imprintato con SHA-256 e
/// deduplicato (lo stesso documento collegato a pi\u00F9 merci non duplica
/// il file), le foto ottengono una miniatura 256 px, e "Libera spazio"
/// pu\u00F2 rimuovere i file locali GI\u00C0 verificati sul cloud mantenendo
/// record, miniatura e riferimento Drive.
class AttachmentService {
  /// [baseDirectory] \u00E8 usato nei test per non dipendere da
  /// path_provider; in produzione gli allegati finiscono nella cartella
  /// documenti privata dell'app.
  AttachmentService({
    required this.repository,
    Directory? baseDirectory,
    Directory? tempDirectory,
  })  : _baseDirectory = baseDirectory,
        _tempDirectory = tempDirectory;

  final HaccpRepository repository;
  final Directory? _baseDirectory;
  final Directory? _tempDirectory;
  final _picker = ImagePicker();

  /// Amico dei test: callable per calcolare l'impronta di un file.
  @visibleForTesting
  Future<String> Function(File file) sha256OfFile = _defaultSha256;

  static Future<String> _defaultSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  // ---------------------------------------------------------------------------
  // Profilo qualità (applicato ai nuovi allegati)
  // ---------------------------------------------------------------------------

  Future<AttachmentQuality> qualityProfile() async =>
      AttachmentQuality.byId(await repository.getSetting('attachment_quality'));

  Future<void> setQualityProfile(AttachmentQuality quality) =>
      repository.setSetting('attachment_quality', quality.id);

  // ---------------------------------------------------------------------------
  // Acquisizione temporanea (per allegare DURANTE la registrazione)
  // ---------------------------------------------------------------------------

  Future<Directory> _tempDir() async {
    final override = _tempDirectory;
    if (override != null) {
      final dir = Directory(p.join(override.path, 'pending_attachments'));
      await dir.create(recursive: true);
      return dir;
    }
    final root = await getTemporaryDirectory();
    final dir = Directory(p.join(root.path, 'pending_attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Scatta una foto senza creare il record: resta in cartella temporanea.
  /// Il permesso fotocamera viene chiesto qui, al primo scatto.
  Future<PendingAttachment?> capturePhotoTemp() async {
    final quality = await qualityProfile();
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: quality.maxSide.toDouble(),
      maxHeight: quality.maxSide.toDouble(),
      imageQuality: quality.quality,
    );
    if (xfile == null) return null;
    return _compressToTemp(xfile, quality: quality, kind: 'photo');
  }

  /// Sceglie una foto dalla galleria senza creare il record.
  Future<PendingAttachment?> pickPhotoTemp() async {
    final quality = await qualityProfile();
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: quality.maxSide.toDouble(),
      maxHeight: quality.maxSide.toDouble(),
      imageQuality: quality.quality,
    );
    if (xfile == null) return null;
    return _compressToTemp(xfile, quality: quality, kind: 'photo');
  }

  /// Sceglie un documento dal selettore di sistema (inclusi i cloud)
  /// senza creare il record.
  Future<PendingAttachment?> pickDocumentTemp() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final file = result?.files.single;
    if (file == null) return null;

    final dir = await _tempDir();
    final name = 'doc_${_stamp()}_${_uniqueSuffix()}_'
        '${p.basename(file.name)}';
    final destination = p.join(dir.path, name);
    await File(file.path!).copy(destination);
    return PendingAttachment(tempPath: destination, kind: 'document');
  }

  Future<PendingAttachment> _compressToTemp(
    XFile xfile, {
    required AttachmentQuality quality,
    required String kind,
  }) async {
    final dir = await _tempDir();
    final name = 'foto_${_stamp()}_${_uniqueSuffix()}.jpg';
    final destination = p.join(dir.path, name);

    final compressed = await FlutterImageCompress.compressAndGetFile(
      xfile.path,
      destination,
      minWidth: quality.maxSide,
      minHeight: quality.maxSide,
      quality: quality.quality,
    );
    return PendingAttachment(
      tempPath: compressed?.path ?? destination,
      kind: kind,
    );
  }

  /// Copia in temporanea gli allegati gi\u00E0 registrati di una merce
  /// ricevuta (per riutilizzarli su un lotto senza doppio scatto).
  Future<PendingAttachment> cloneToTemp(Attachment source) async {
    final dir = await _tempDir();
    final name = 'copia_${_stamp()}_${_uniqueSuffix()}_'
        '${p.basename(source.localPath)}';
    final destination = p.join(dir.path, name);
    await File(source.localPath).copy(destination);
    return PendingAttachment(
      tempPath: destination,
      kind: source.kind,
      label: source.note,
    );
  }

  // ---------------------------------------------------------------------------
  // Persistenza con deduplica e miniature
  // ---------------------------------------------------------------------------

  /// Registra gli allegati pendenti sull'entit\u00E0 appena creata.
  ///
  /// Se un file con la stessa impronta SHA-256 \u00E8 gi\u00E0 archiviato,
  /// NON viene copiato: il nuovo record punta allo stesso file (e alla
  /// stessa miniatura). Un documento, pi\u00F9 merci: un solo file.
  Future<void> attachPending(
    AttachmentEntity entity,
    int entityId,
    List<PendingAttachment> pending,
  ) async {
    for (final item in pending) {
      await _persistFromTemp(
        entity: entity,
        entityId: entityId,
        tempPath: item.tempPath,
        kind: item.kind,
        note: [
          if (item.label != null && item.label!.isNotEmpty) item.label,
          if (item.note != null && item.note!.isNotEmpty) item.note,
        ].join(' \u2022 '),
      );
    }
  }

  Future<void> _persistFromTemp({
    required AttachmentEntity entity,
    required int entityId,
    required String tempPath,
    required String kind,
    String? note,
  }) async {
    final source = File(tempPath);
    if (!await source.exists()) {
      throw const FileSystemException(
        'File non trovato: potrebbe mancare spazio sul telefono. Libera '
        'spazio o usa Google Drive per gli allegati.',
      );
    }

    final sha = await sha256OfFile(source);
    final existing = await repository.findAttachmentBySha(sha);
    if (existing != null && await File(existing.localPath).exists()) {
      // Deduplica: stesso contenuto, riusa file e miniatura.
      await repository.addAttachment(
        Attachment(
          id: 0,
          entityType: entity.value,
          entityId: entityId,
          kind: kind,
          fileName: existing.fileName,
          localPath: existing.localPath,
          mime: existing.mime,
          size: existing.size,
          createdAt: DateTime.now(),
          note: note,
          sha256: sha,
          thumbPath: existing.thumbPath,
          width: existing.width,
          height: existing.height,
        ),
      );
      await source.delete();
      return;
    }

    final dir = await _baseDir();
    final name = _uniqueName(p.basename(tempPath));
    final destination = p.join(dir.path, name);
    try {
      await source.rename(destination);
    } on FileSystemException {
      // Rename tra volumi diversi: fallback con copia.
      await source.copy(destination);
      await source.delete();
    }

    await _register(
      entity: entity,
      entityId: entityId,
      kind: kind,
      fileName: name,
      localPath: destination,
      mime: kind == 'photo' ? 'image/jpeg' : _guessMime(name),
      note: note,
      sha: sha,
    );
  }

  /// Elimina i file temporanei degli allegati non salvati (annullamento).
  Future<void> discardPending(List<PendingAttachment> pending) async {
    for (final item in pending) {
      try {
        final file = File(item.tempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Gi\u00E0 rimosso o non accessibile: nessun allegato orfano resta
        // nella cartella definitiva in ogni caso.
      }
    }
  }

  String _uniqueSuffix() =>
      Random().nextInt(0x7FFFFFFF).toRadixString(36);

  Future<Directory> _baseDir() async {
    final now = DateTime.now();
    final override = _baseDirectory;
    final root = override ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(
      root.path,
      'attachments',
      '${now.year}',
      now.month.toString().padLeft(2, '0'),
    ));
    await dir.create(recursive: true);
    return dir;
  }

  /// Directory radice degli allegati (per statistiche e pulizia).
  Future<Directory> attachmentsRoot() async {
    final override = _baseDirectory;
    final root = override ?? await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  /// Miniatura 256 px lato lungo (~10-20 KB) per le foto: usata nelle
  /// liste e quando il file locale \u00E8 stato liberato.
  Future<String?> _makeThumbnail(String imagePath) async {
    try {
      final dir = await _baseDir();
      final base = p.basenameWithoutExtension(imagePath);
      final thumbPath = p.join(dir.path, '${base}_thumb.jpg');
      final thumb = await FlutterImageCompress.compressAndGetFile(
        imagePath,
        thumbPath,
        minWidth: 256,
        minHeight: 256,
        quality: 60,
      );
      return thumb?.path ?? thumbPath;
    } catch (_) {
      // La miniatura \u00E8 un'ottimizzazione: mai rompere il salvataggio.
      return null;
    }
  }

  Future<(int, int)?> _imageSize(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = (frame.image.width, frame.image.height);
      frame.image.dispose();
      codec.dispose();
      return size;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Acquisizione diretta (record immediato)
  // ---------------------------------------------------------------------------

  /// Scatta una foto con la fotocamera (il permesso viene chiesto qui).
  Future<Attachment?> takePhoto(
    AttachmentEntity entity,
    int entityId, {
    String? note,
  }) async {
    final quality = await qualityProfile();
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: quality.maxSide.toDouble(),
      maxHeight: quality.maxSide.toDouble(),
      imageQuality: quality.quality,
    );
    if (xfile == null) return null;
    return _saveImage(xfile, entity, entityId,
        kind: 'photo', note: note, quality: quality);
  }

  /// Sceglie una foto dalla galleria (photo picker di sistema, nessun
  /// permesso su Android 13+).
  Future<Attachment?> pickPhoto(
    AttachmentEntity entity,
    int entityId, {
    String? note,
  }) async {
    final quality = await qualityProfile();
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: quality.maxSide.toDouble(),
      maxHeight: quality.maxSide.toDouble(),
      imageQuality: quality.quality,
    );
    if (xfile == null) return null;
    return _saveImage(xfile, entity, entityId,
        kind: 'photo', note: note, quality: quality);
  }

  /// Sceglie un documento (PDF, immagine, altro) dal selettore di sistema,
  /// che include Google Drive, iCloud Drive, OneDrive e Dropbox: nessun
  /// accesso OAuth serve per importare file esistenti.
  Future<Attachment?> pickDocument(
    AttachmentEntity entity,
    int entityId, {
    String? note,
  }) async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final file = result?.files.single;
    if (file == null) return null;

    final source = File(file.path!);
    final dir = await _baseDir();
    final name = _uniqueName(file.name);
    final destination = p.join(dir.path, name);
    await source.copy(destination);

    final sha = await sha256OfFile(File(destination));
    return _register(
      entity: entity,
      entityId: entityId,
      kind: 'document',
      fileName: name,
      localPath: destination,
      mime: _guessMime(name),
      note: note,
      sha: sha,
    );
  }

  Future<Attachment?> _saveImage(
    XFile xfile,
    AttachmentEntity entity,
    int entityId, {
    required String kind,
    String? note,
    required AttachmentQuality quality,
  }) async {
    final dir = await _baseDir();
    final name = _uniqueName('foto_${_stamp()}.jpg');
    final destination = p.join(dir.path, name);

    final compressed = await FlutterImageCompress.compressAndGetFile(
      xfile.path,
      destination,
      minWidth: quality.maxSide,
      minHeight: quality.maxSide,
      quality: quality.quality,
    );

    final path = compressed?.path ?? destination;
    final sha = await sha256OfFile(File(path));
    return _register(
      entity: entity,
      entityId: entityId,
      kind: kind,
      fileName: p.basename(path),
      localPath: path,
      mime: 'image/jpeg',
      note: note,
      sha: sha,
    );
  }

  Future<Attachment> _register({
    required AttachmentEntity entity,
    required int entityId,
    required String kind,
    required String fileName,
    required String localPath,
    required String mime,
    String? note,
    String? sha,
  }) async {
    final file = File(localPath);
    final size = await file.length();
    final thumbPath =
        mime == 'image/jpeg' ? await _makeThumbnail(localPath) : null;
    final dimensions = mime == 'image/jpeg'
        ? await _imageSize(localPath)
        : null;

    final id = await repository.addAttachment(
      Attachment(
        id: 0,
        entityType: entity.value,
        entityId: entityId,
        kind: kind,
        fileName: fileName,
        localPath: localPath,
        mime: mime,
        size: size,
        createdAt: DateTime.now(),
        note: note,
        sha256: sha,
        thumbPath: thumbPath,
        width: dimensions?.$1,
        height: dimensions?.$2,
      ),
    );
    // Se un cloud \u00E8 attivo il file entra nella coda di caricamento.
    await repository.enqueueSync(
      kind: 'attachment',
      localPath: localPath,
      remoteFolder: 'Foto',
    );
    return Attachment(
      id: id,
      entityType: entity.value,
      entityId: entityId,
      kind: kind,
      fileName: fileName,
      localPath: localPath,
      mime: mime,
      size: size,
      createdAt: DateTime.now(),
      note: note,
      sha256: sha,
      thumbPath: thumbPath,
      width: dimensions?.$1,
      height: dimensions?.$2,
    );
  }

  // ---------------------------------------------------------------------------
  // Spazio, offload e manutenzione (Prompt 8, parte B)
  // ---------------------------------------------------------------------------

  /// Statistiche per la schermata "Spazio e allegati".
  Future<AttachmentStorageStats> storageStats() async {
    final all = await repository.getAllAttachments();
    final byYear = <int, int>{};
    var notSynced = 0;
    var totalBytes = 0;
    var fileCount = 0;
    for (final a in all) {
      if (a.cloudId == null || a.syncedAt == null) notSynced++;
      if (a.isOffloaded) continue;
      // Schermata "Spazio e allegati": usa i metadati del DB per evitare
      // I/O massivo in apertura (controllo file reale disponibile nel
      // pannello "Controllo integrità").
      fileCount++;
      totalBytes += a.size;
      byYear[a.createdAt.year] = (byYear[a.createdAt.year] ?? 0) + a.size;
    }
    return AttachmentStorageStats(
      totalBytes: totalBytes,
      fileCount: fileCount,
      byYear: byYear,
      notSyncedCount: notSynced,
    );
  }

  /// I file locali più grandi (20 di default), caricati separatamente dal
  /// riepilogo per rendere la schermata immediatamente reattiva.
  Future<List<Attachment>> largestLocalAttachments({int limit = 20}) =>
      repository.getLargestLocalAttachments(limit: limit);

  /// "Libera spazio": elimina il file locale degli allegati pi\u00F9 vecchi
  /// di [olderThan] GI\u00C0 verificati sul cloud (cloud_id E synced_at),
  /// mantenendo record, miniatura e riferimento. Non tocca mai file non
  /// caricati, caricamenti falliti, allegati di NC aperte o di lotti non
  /// ancora scaduti. Restituisce i byte liberati.
  Future<int> offloadOldAttachments({
    required Duration olderThan,
    required Set<int> protectedEntityIds,
  }) async {
    final all = await repository.getAllAttachments();
    var freed = 0;
    final cutoff = DateTime.now().subtract(olderThan);
    for (final a in all) {
      if (a.isOffloaded) continue;
      if (a.cloudId == null || a.syncedAt == null) continue;
      if (a.createdAt.isAfter(cutoff)) continue;
      if (protectedEntityIds.contains(a.id)) continue;
      final file = File(a.localPath);
      if (!await file.exists()) continue;
      // Il file \u00E8 condiviso da pi\u00F9 record: liberabile solo se TUTTI
      // i record che lo puntano sono eleggibili (stessa condizione).
      final siblings =
          await repository.findAttachmentRefsByPath(a.localPath);
      final allEligible = siblings.every((s) =>
          s.isOffloaded ||
          (s.cloudId != null &&
              s.syncedAt != null &&
              !s.createdAt.isAfter(cutoff)));
      if (!allEligible) continue;
      final size = a.size;
      await file.delete();
      await repository.markAttachmentOffloaded(a.id);
      freed += size;
    }
    return freed;
  }

  /// Riporta un allegato "solo su Drive" allo stato locale dopo il
  /// download (il chiamante ha gi\u00E0 scritto il file in localPath).
  Future<void> markDownloaded(Attachment attachment) =>
      repository.clearAttachmentOffloaded(attachment.id);

  /// Pulizia all'avvio: elimina i pending temporanei pi\u00F9 vecchi di
  /// 24 ore (attività di registrazione mai completate).
  Future<int> cleanupStalePending({Duration maxAge = const Duration(hours: 24)}) async {
    var removed = 0;
    try {
      final dir = await _tempDir();
      final cutoff = DateTime.now().subtract(maxAge);
      await for (final entry in dir.list()) {
        final file = File(entry.path);
        final stat = await file.stat();
        if (stat.type == FileSystemEntityType.file &&
            stat.modified.isBefore(cutoff)) {
          await file.delete();
          removed++;
        }
      }
    } catch (_) {
      // La pulizia non deve mai rompere l'avvio.
    }
    return removed;
  }

  /// File senza record (orfani) e record senza file, per il pulsante
  /// "Ripara" nella schermata Spazio e allegati.
  Future<({List<String> orphanFiles, List<Attachment> missingFiles})>
      findInconsistencies() async {
    final all = await repository.getAllAttachments();
    final knownPaths = <String>{};
    final missing = <Attachment>[];
    for (final a in all) {
      if (a.isOffloaded) continue;
      if (await File(a.localPath).exists()) {
        knownPaths.add(a.localPath);
        if (a.thumbPath != null &&
            await File(a.thumbPath!).exists()) {
          knownPaths.add(a.thumbPath!);
        }
      } else {
        missing.add(a);
      }
    }
    final orphans = <String>[];
    final root = await attachmentsRoot();
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is File && !knownPaths.contains(entry.path)) {
        orphans.add(entry.path);
      }
    }
    return (orphanFiles: orphans, missingFiles: missing);
  }

  /// Riparazione: elimina i file orfani (senza record). I record senza
  /// file NON vengono cancellati silenziosamente: restano e mostrano
  /// "File non disponibile" / "Solo su Drive". Restituisce i file rimossi.
  Future<List<String>> repairOrphanFiles() async {
    final result = await findInconsistencies();
    final removed = <String>[];
    for (final path in result.orphanFiles) {
      try {
        await File(path).delete();
        removed.add(path);
      } catch (_) {
        // Gi\u00E0 rimosso.
      }
    }
    return removed;
  }

  String _uniqueName(String base) {
    final r = Random().nextInt(0x7FFFFFFF);
    return '${_stamp()}_${r.toRadixString(36)}_$base';
  }

  String _stamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  String _guessMime(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.png' => 'image/png',
      '.heic' => 'image/heic',
      '.doc' || '.docx' => 'application/msword',
      '.txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  /// Registra un logo azienda (entit\u00E0 company) come allegato foto.
  Future<Attachment?> setCompanyLogo({required String sourcePath}) async {
    final quality = await qualityProfile();
    final xfile = XFile(sourcePath);
    return _saveImage(xfile, AttachmentEntity.company, 0,
        kind: 'photo', quality: quality);
  }
}

/// Utilit\u00E0 di formattazione per la UI (bytes leggibili).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
