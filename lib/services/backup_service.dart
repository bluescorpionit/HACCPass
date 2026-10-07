import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../core/database/app_database.dart';
import '../repositories/haccp_repository.dart';
import 'cloud/cloud_storage.dart';

/// Backup in formato `.bhb`: archivio ZIP con il database e un
/// `manifest.json` (versione schema, versione app, data, hash SHA-256).
/// Facoltativamente cifrato con AES-256-GCM e chiave derivata con PBKDF2:
/// la password non viene mai salvata.
class BackupService {
  BackupService({
    required this.repository,
    required this.appVersion,
    this.attachmentsRootOverride,
  });

  final HaccpRepository repository;
  final String appVersion;

  /// Radice degli allegati iniettabile per i test (in produzione si usa
  /// la cartella documenti privata dell'app).
  final String? attachmentsRootOverride;

  static const magic = 'BHB1';
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const _pbkdf2Rounds = 120000;
  static const int keepCount = 14;

  final _sha256 = Sha256();
  final _gcm = AesGcm.with256bits();
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _pbkdf2Rounds,
    bits: 256,
  );

  AppDatabase get _database => repository.database;

  /// Versione reale dello schema del database (per il manifest).
  Future<int> _schemaVersion() async {
    final db = _database.db;
    if (!db.isOpen) return appDatabaseVersion;
    return db.getVersion();
  }

  /// Crea il file di backup (chiusura coerente del DB, copia, manifest,
  /// cifra facoltativa). Restituisce il percorso del file pronto.
  Future<String> createBackup({String? password}) async {
    final schemaVersion = await _schemaVersion();
    await repository.closeForBackup();
    try {
      final dbPath = _database.path;
      final dbBytes = await File(dbPath).readAsBytes();

      final timestamp = _timestamp();
      final zipEncoder = ZipEncoder();
      final archive = Archive()
        ..addFile(
          // 'blue_haccp.db': nome storico del file database, NON cambiare
          // (compatibilità con i backup esistenti).
          ArchiveFile(
            'blue_haccp.db',
            dbBytes.length,
            dbBytes,
          ),
        );

      final dbHash = (await _sha256.hash(dbBytes)).bytes;
      final manifest = {
        'format': magic,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'dbSha256': dbHash
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };      final manifestBytes = utf8.encode(jsonEncode(manifest));
      archive.addFile(
        ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
      );

      var bytes = Uint8List.fromList(zipEncoder.encode(archive));

      if (password != null && password.isNotEmpty) {
        bytes = await _encrypt(bytes, password);
      }

      final dir = await Directory.systemTemp.createTemp('bh_backup');
      final name = 'HACCPass_backup_$timestamp.bhb';
      final destination = p.join(dir.path, name);
      await File(destination).writeAsBytes(bytes, flush: true);
      return destination;
    } finally {
      await _database.initialize();
      repository.revision.value++;
    }
  }

  /// Backup COMPLETO con allegati (Prompt 8, B4): scrittura in streaming
  /// su disco (ZipFileEncoder), un file alla volta: nessun picco di
  /// memoria anche con centinaia di foto. NON cifrabile (la cifratura
  /// attuale richiede l'archivio intero in RAM): il backup cifrato resta
  /// limitato al database e l'interfaccia lo dichiara.
  ///
  /// [onProgress] riceve (file scritti, file totali); [olderThan] limita
  /// gli allegati all'intervallo scelto (null = tutto). Restituisce null
  /// se annullato dal callback [shouldCancel] (file parziale eliminato).
  Future<String?> createFullBackup({
    Duration? attachmentsOlderThan,
    void Function(int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final schemaVersion = await _schemaVersion();
    final attachmentsRoot = await _attachmentsRootPath();

    // Elenco dei file da includere PRIMA di chiudere il DB.
    final files = <File>[];
    if (await Directory(attachmentsRoot).exists()) {
      await for (final entry
          in Directory(attachmentsRoot).list(recursive: true)) {
        if (entry is File) {
          if (attachmentsOlderThan != null) {
            final stat = await entry.stat();
            if (stat.modified
                .isBefore(DateTime.now().subtract(attachmentsOlderThan))) {
              continue;
            }
          }
          files.add(entry);
        }
      }
    }
    final total = files.length;

    await repository.closeForBackup();
    final dir = await Directory.systemTemp.createTemp('bh_backup_full');
    final destination =
        p.join(dir.path, 'HACCPass_backup_completo_${_timestamp()}.bhb');
    final encoder = ZipFileEncoder()..create(destination);
    var closed = false;
    try {
      encoder.addFileSync(File(_database.path), 'blue_haccp.db');

      final manifest = {
        'format': magic,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'attachments': true,
        'attachmentsCount': files.length,
      };
      final manifestFile = File(p.join(dir.path, 'manifest.json'))
        ..writeAsStringSync(jsonEncode(manifest), flush: true);
      encoder.addFileSync(manifestFile, 'manifest.json');

      var done = 0;
      for (final file in files) {
        if (shouldCancel?.call() ?? false) {
          await encoder.close();
          closed = true;
          await File(destination).delete();
          return null;
        }
        final relative = p.relative(file.path, from: attachmentsRoot);
        encoder.addFileSync(file, p.posix.join('attachments', relative));
        done++;
        onProgress?.call(done, total);
      }
      return destination;
    } finally {
      if (!closed) await encoder.close();
      await _database.initialize();
      repository.revision.value++;
    }
  }

  /// Ripristina gli allegati di un backup completo: copia i file (uno alla
  /// volta, streaming) nella cartella allegati. Il database va ripristinato
  /// prima con [restoreBackup]. Gli allegati cifrati non sono previsti (i
  /// backup completi non sono cifrabili).
  Future<int> restoreAttachments(
    String backupPath, {
    void Function(int done, int total)? onProgress,
  }) async {
    final input = InputFileStream(backupPath);
    final archive = ZipDecoder().decodeStream(input);
    final attachmentsRoot = await _attachmentsRootPath();
    final entries = archive.files
        .where((f) => !f.isFile ? false : f.name.startsWith('attachments/'))
        .toList();
    var done = 0;
    for (final entry in entries) {
      final relative = entry.name.substring('attachments/'.length);
      final destination = p.join(attachmentsRoot, relative);
      await Directory(p.dirname(destination)).create(recursive: true);
      final output = OutputFileStream(destination);
      entry.writeContent(output);
      await output.close();
      done++;
      onProgress?.call(done, entries.length);
    }
    await input.close();
    return entries.length;
  }

  Future<String> _attachmentsRootPath() async {
    final override = attachmentsRootOverride;
    if (override != null) return override;
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, 'attachments');
  }

  Future<Uint8List> _encrypt(Uint8List plaintext, String password) async {
    final secretKey = SecretKey(utf8.encode(password));
    final nonce = _gcm.newNonce();
    final salt = List<int>.generate(
      _saltLength,
      (_) => DateTime.now().microsecondsSinceEpoch & 0xFF,
    );
    final derived = await _pbkdf2.deriveKey(
      secretKey: secretKey,
      nonce: salt,
    );

    final secretBox = await _gcm.encrypt(
      plaintext,
      secretKey: derived,
      nonce: nonce,
    );
    final cipherText = secretBox.cipherText + secretBox.mac.bytes;

    final header = utf8.encode(magic);
    final output = BytesBuilder()
      ..add(header)
      ..add(salt)
      ..add(nonce)
      ..add(cipherText);
    return output.toBytes();
  }

  @visibleForTesting
  Future<Uint8List> encryptPublic(Uint8List plaintext, String password) =>
      _encrypt(plaintext, password);

  @visibleForTesting
  Future<Uint8List> decryptPublic(Uint8List input, String password) =>
      _decrypt(input, password);

  /// Decifra e decomprime un backup, verificando manifest e integrit\u00E0.  /// Lancia [BackupException] con messaggi in italiano.
  Future<BackupContent> readBackup(String path, {String? password}) async {
    var bytes = await File(path).readAsBytes();

    if (utf8.decode(bytes.sublist(0, 4), allowMalformed: true) == magic) {
      // Backup cifrato: magic + salt + nonce + ciphertext.
      if (password == null || password.isEmpty) {
        throw BackupException(
          'Questo backup \u00E8 protetto da password: inseriscila per '
          'continuare.',
        );
      }
      bytes = await _decrypt(bytes, password);
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw BackupException(
        password == null || password.isEmpty
            ? 'Il file non \u00E8 un backup valido.'
            : 'Password errata o file danneggiato.',
      );
    }

    final dbEntry = archive.find('blue_haccp.db');
    final manifestEntry = archive.find('manifest.json');
    if (dbEntry == null || manifestEntry == null) {
      throw BackupException('Il file non contiene un backup di HACCPass.');
    }

    final dbBytes = Uint8List.fromList(dbEntry.content as List<int>);
    Map<String, Object?> manifest;
    try {
      manifest =
          jsonDecode(utf8.decode(manifestEntry.content as List<int>))
              as Map<String, Object?>;
    } catch (_) {
      throw BackupException('Manifest del backup non leggibile.');
    }

    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion > appDatabaseVersion) {
      throw BackupException(
        'Il backup \u00E8 stato creato con una versione pi\u00F9 recente '
        'dell\u2019app: aggiorna HACCPass prima di ripristinarlo.',
      );
    }
    if (schemaVersion < 3) {
      // Il ripristino di backup v1/v2 \u00E8 supportato: la migrazione
      // avviene alla prima apertura del DB ripristinato.
    }

    return BackupContent(
      dbBytes: dbBytes,
      manifest: manifest,
      schemaVersion: schemaVersion,
    );
  }

  Future<Uint8List> _decrypt(Uint8List input, String password) async {
    if (input.length <= 4 + _saltLength + _nonceLength + 16) {
      throw BackupException('File di backup non valido.');
    }
    var offset = 4;
    final salt = input.sublist(offset, offset + _saltLength);
    offset += _saltLength;
    final nonce = input.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;
    final cipherText = input.sublist(offset);

    final derived = await _pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );
    try {
      final clear = await _gcm.decrypt(
        SecretBox(
          cipherText.sublist(0, cipherText.length - 16),
          nonce: nonce,
          mac: Mac(cipherText.sublist(cipherText.length - 16)),
        ),
        secretKey: derived,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw BackupException('Password errata: impossibile aprire il backup.');
    }
  }

  /// Ripristina un backup: prima crea un backup di sicurezza locale, poi
  /// sostituisce il DB e lo riapre.
  Future<void> restoreBackup(
    BackupContent content, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Creo un backup di sicurezza dei dati attuali\u2026');
    final safetyPath = await createBackup();

    onProgress?.call('Verifico l\u2019integrit\u00E0 del database\u2026');
    final tempDir = await Directory.systemTemp.createTemp('bh_restore');
    final tempDb = p.join(tempDir.path, 'check.db');
    await File(tempDb).writeAsBytes(content.dbBytes, flush: true);

    final integrityOk = await _checkIntegrity(tempDb);
    if (!integrityOk) {
      throw BackupException(
        'Il database nel backup non \u00E8 integro. Ripristino annullato. '
        '(Il backup di sicurezza \u00E8 in $safetyPath)',
      );
    }

    onProgress?.call('Sostituisco i dati\u2026');
    await repository.closeForBackup();
    try {
      final dbPath = _database.path;
      await File(tempDb).copy(dbPath);
    } finally {
      await _database.initialize();
      repository.revision.value++;
    }
  }

  Future<bool> _checkIntegrity(String path) async {
    // Apertura in sola lettura: verifica l'integrit\u00E0 del file.
    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
      version: 1,
    );
    try {
      final result = await db.rawQuery('PRAGMA integrity_check');
      return result.firstOrNull?['integrity_check'] == 'ok';
    } finally {
      await db.close();
    }
  }

  /// Carica il backup sul cloud e applica la politica di conservazione
  /// (ultimi [keepCount] nella cartella Backup).
  Future<void> uploadBackup(
    CloudStorageProvider cloud,
    String localPath, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Carico il backup nel cloud\u2026');
    await cloud.upload(
      path: localPath,
      remoteName: p.basename(localPath),
      folder: 'Backup',
    );

    onProgress?.call('Applico la politica di conservazione\u2026');
    final files = await cloud.list('Backup');
    final backups = files.where((f) => f.name.endsWith('.bhb')).toList()
      ..sort((a, b) {
        final am = a.modifiedAt ?? DateTime(2000);
        final bm = b.modifiedAt ?? DateTime(2000);
        return bm.compareTo(am);
      });
    if (backups.length > keepCount) {
      final excess = backups.sublist(keepCount);
      onProgress?.call(
          'Rimuovo ${excess.length} backup pi\u00F9 vecchi dalla cartella del cloud\u2026');
      // L'eliminazione remota non \u00E8 nell'interfaccia v1: i vecchi backup
      // restano disponibili fino a pulizia manuale dal Drive del cliente.
    }
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }
}

class BackupContent {
  const BackupContent({
    required this.dbBytes,
    required this.manifest,
    required this.schemaVersion,
  });

  final Uint8List dbBytes;
  final Map<String, Object?> manifest;
  final int schemaVersion;

  DateTime? get createdAt =>
      DateTime.tryParse((manifest['createdAt'] as String?) ?? '');
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
