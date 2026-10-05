import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';

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
/// Le foto vengono compresse (lato lungo ~1600 px, qualit\u00E0 ~80) prima
/// di essere salvate in `attachments/AAAA/MM/` nella cartella documenti
/// privata dell'app. I documenti vengono copiati cos\u00EC come sono.
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
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (xfile == null) return null;
    return _compressToTemp(xfile, kind: 'photo');
  }

  /// Sceglie una foto dalla galleria senza creare il record.
  Future<PendingAttachment?> pickPhotoTemp() async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (xfile == null) return null;
    return _compressToTemp(xfile, kind: 'photo');
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
    required String kind,
  }) async {
    final dir = await _tempDir();
    final name = 'foto_${_stamp()}_${_uniqueSuffix()}.jpg';
    final destination = p.join(dir.path, name);

    final compressed = await FlutterImageCompress.compressAndGetFile(
      xfile.path,
      destination,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
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

  /// Registra gli allegati pendenti sull'entit\u00E0 appena creata:
  /// sposta i file nella cartella definitiva e crea i record.
  Future<void> attachPending(
    AttachmentEntity entity,
    int entityId,
    List<PendingAttachment> pending,
  ) async {
    for (final item in pending) {
      final dir = await _baseDir();
      final name = _uniqueName(p.basename(item.tempPath));
      final destination = p.join(dir.path, name);
      try {
        await File(item.tempPath).rename(destination);
      } on FileSystemException {
        // Rename tra volumi diversi: fallback con copia.
        await File(item.tempPath).copy(destination);
        await File(item.tempPath).delete();
      }

      final note = [
        if (item.label != null && item.label!.isNotEmpty) item.label,
        if (item.note != null && item.note!.isNotEmpty) item.note,
      ].join(' \u2022 ');

      final size = await File(destination).length();
      await repository.addAttachment(
        Attachment(
          id: 0,
          entityType: entity.value,
          entityId: entityId,
          kind: item.kind,
          fileName: name,
          localPath: destination,
          mime: item.kind == 'photo' ? 'image/jpeg' : _guessMime(name),
          size: size,
          createdAt: DateTime.now(),
          note: note.isEmpty ? null : note,
        ),
      );
    }
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
    if (override != null) {
      final dir = Directory(p.join(
        override.path,
        'attachments',
        '${now.year}',
        now.month.toString().padLeft(2, '0'),
      ));
      await dir.create(recursive: true);
      return dir;
    }
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(
      root.path,
      'attachments',
      '${now.year}',
      now.month.toString().padLeft(2, '0'),
    ));
    await dir.create(recursive: true);
    return dir;
  }

  /// Scatta una foto con la fotocamera (il permesso viene chiesto qui).
  Future<Attachment?> takePhoto(
    AttachmentEntity entity,
    int entityId, {
    String? note,
  }) async {
    final xfile = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (xfile == null) return null;
    return _saveImage(xfile, entity, entityId,
        kind: 'photo', note: note);
  }

  /// Sceglie una foto dalla galleria (photo picker di sistema, nessun
  /// permesso su Android 13+).
  Future<Attachment?> pickPhoto(
    AttachmentEntity entity,
    int entityId, {
    String? note,
  }) async {
    final xfile = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 80,
    );
    if (xfile == null) return null;
    return _saveImage(xfile, entity, entityId, kind: 'photo', note: note);
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

    return _register(
      entity: entity,
      entityId: entityId,
      kind: 'document',
      fileName: name,
      localPath: destination,
      mime: _guessMime(name),
      note: note,
    );
  }

  Future<Attachment?> _saveImage(
    XFile xfile,
    AttachmentEntity entity,
    int entityId, {
    required String kind,
    String? note,
  }) async {
    final dir = await _baseDir();
    final name = _uniqueName('foto_${_stamp()}.jpg');
    final destination = p.join(dir.path, name);

    final compressed = await FlutterImageCompress.compressAndGetFile(
      xfile.path,
      destination,
      minWidth: 1600,
      minHeight: 1600,
      quality: 80,
    );

    final path = compressed?.path ?? destination;
    return _register(
      entity: entity,
      entityId: entityId,
      kind: kind,
      fileName: p.basename(path),
      localPath: path,
      mime: 'image/jpeg',
      note: note,
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
  }) async {
    final size = await File(localPath).length();
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
    );
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
    final xfile = XFile(sourcePath);
    return _saveImage(xfile, AttachmentEntity.company, 0, kind: 'photo');
  }
}
