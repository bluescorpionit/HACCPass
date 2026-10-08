import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
///
/// Formati di cifratura:
/// - **BHB1** (storico): magic + salt(16) + nonce(12) + ciphertext,
///   PBKDF2-SHA256 a 120.000 iterazioni. Il salt era quasi costante:
///   viene letto per compatibilità ma non generato più.
/// - **BHB2** (attuale): magic + salt(16) casuale (`Random.secure()`) +
///   nonce(12) + iterazioni PBKDF2 (4 byte big-endian, default 600.000)
///   + ciphertext.
///
/// Il backup COMPLETO (con le foto) non è cifrabile: la cifratura
/// richiede l'archivio intero in memoria e i backup completi sono
/// scritti in streaming. L'interfaccia lo dichiara.
class BackupService {
  BackupService({
    required this.repository,
    required this.appVersion,
    this.attachmentsRootOverride,
    int? encryptionRounds,
  }) : _encryptionRounds = encryptionRounds ?? pbkdf2RoundsV2;

  final HaccpRepository repository;
  final String appVersion;

  /// Radice degli allegati iniettabile per i test (in produzione si usa
  /// la cartella documenti privata dell'app).
  final String? attachmentsRootOverride;

  /// Iterazioni PBKDF2 dei NUOVI backup cifrati (BHB2); iniettabile per
  /// tenere i test veloci. La lettura usa sempre le iterazioni scritte
  /// nell'intestazione del file.
  final int _encryptionRounds;

  static const magicV1 = 'BHB1';
  static const magicV2 = 'BHB2';
  static const pbkdf2RoundsV1 = 120000;
  static const pbkdf2RoundsV2 = 600000;
  static const _saltLength = 16;
  static const _nonceLength = 12;
  static const int keepCount = 14;

  /// Prefisso dei file di backup creati da HACCPass: SOLO i file con
  /// questo prefisso possono essere eliminati dalla conservazione cloud.
  static const backupPrefix = 'HACCPass_backup_';
  static const fullBackupPrefix = 'HACCPass_backup_completo_';

  final _sha256 = Sha256();
  final _gcm = AesGcm.with256bits();
  final _secure = Random.secure();

  Pbkdf2 _pbkdf2For(int iterations) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
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
        'format': magicV2,
        'schemaVersion': schemaVersion,
        'appVersion': appVersion,
        'createdAt': DateTime.now().toIso8601String(),
        'encrypted': password != null && password.isNotEmpty,
        'dbSha256': dbHash
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join(),
      };
      final manifestBytes = utf8.encode(jsonEncode(manifest));
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
  /// richiede l'archivio intero in RAM): il backup cifrato resta
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
    final attachmentsRoot = await attachmentsRootPath();

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
        'format': magicV2,
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
  /// prima con [RestoreService]. Gli allegati cifrati non sono previsti (i
  /// backup completi non sono cifrabili).
  Future<int> restoreAttachments(
    String backupPath, {
    void Function(int done, int total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final input = InputFileStream(backupPath);
    final archive = ZipDecoder().decodeStream(input);
    final attachmentsRoot = await attachmentsRootPath();
    final entries = archive.files
        .where((f) => !f.isFile ? false : f.name.startsWith('attachments/'))
        .toList();
    var done = 0;
    var cancelled = false;
    try {
      for (final entry in entries) {
        if (shouldCancel?.call() ?? false) {
          cancelled = true;
          break;
        }
        final relative = entry.name.substring('attachments/'.length);
        final destination = p.join(attachmentsRoot, relative);
        await Directory(p.dirname(destination)).create(recursive: true);
        final output = OutputFileStream(destination);
        entry.writeContent(output);
        await output.close();
        done++;
        onProgress?.call(done, entries.length);
      }
    } finally {
      await input.close();
    }
    if (cancelled) throw const BackupCancelledException();
    return entries.length;
  }

  /// Radice della cartella allegati: iniettabile per i test, in
  /// produzione è la cartella documenti privata dell'app. Usata anche
  /// dal riallineamento dei percorsi dopo un ripristino.
  Future<String> attachmentsRootPath() async {
    final override = attachmentsRootOverride;
    if (override != null) return override;
    final root = await getApplicationDocumentsDirectory();
    return p.join(root.path, 'attachments');
  }

  // ---------------------------------------------------------------------------
  // Cifratura (BHB1 lettura, BHB2 lettura + scrittura)
  // ---------------------------------------------------------------------------

  Future<Uint8List> _encrypt(Uint8List plaintext, String password) async {
    final rounds = _encryptionRounds;
    final secretKey = SecretKey(utf8.encode(password));
    final nonce = _gcm.newNonce();
    final salt =
        List<int>.generate(_saltLength, (_) => _secure.nextInt(256));
    final derived = await _pbkdf2For(rounds).deriveKey(
      secretKey: secretKey,
      nonce: salt,
    );

    final secretBox = await _gcm.encrypt(
      plaintext,
      secretKey: derived,
      nonce: nonce,
    );
    final cipherText = secretBox.cipherText + secretBox.mac.bytes;

    final roundsBytes = ByteData(4)..setUint32(0, rounds, Endian.big);
    final output = BytesBuilder(copy: false)
      ..add(utf8.encode(magicV2))
      ..add(salt)
      ..add(nonce)
      ..add(roundsBytes.buffer.asUint8List())
      ..add(cipherText);
    return output.takeBytes();
  }

  @visibleForTesting
  Future<Uint8List> encryptPublic(Uint8List plaintext, String password) =>
      _encrypt(plaintext, password);

  /// Solo per i test: cifra nel FORMATO STORICO BHB1 (salt nel file,
  /// PBKDF2 a 120.000 iterazioni) per verificare la lettura compatibile
  /// dei backup esistenti.
  @visibleForTesting
  Future<Uint8List> encryptAsV1ForTest(
    Uint8List plaintext,
    String password,
  ) async {
    final secretKey = SecretKey(utf8.encode(password));
    final nonce = _gcm.newNonce();
    final salt = List<int>.generate(_saltLength, (_) => _secure.nextInt(256));
    final derived = await _pbkdf2For(pbkdf2RoundsV1).deriveKey(
      secretKey: secretKey,
      nonce: salt,
    );
    final secretBox = await _gcm.encrypt(
      plaintext,
      secretKey: derived,
      nonce: nonce,
    );
    return (BytesBuilder(copy: false)
          ..add(utf8.encode(magicV1))
          ..add(salt)
          ..add(nonce)
          ..add(secretBox.cipherText)
          ..add(secretBox.mac.bytes))
        .takeBytes();
  }

  @visibleForTesting
  Future<Uint8List> decryptPublic(Uint8List input, String password) =>
      _decrypt(input, password);

  /// Decifra un backup cifrato BHB1 o BHB2. Lancia [BackupException] con
  /// messaggi in italiano.
  Future<Uint8List> _decrypt(Uint8List input, String password) async {
    if (input.length < 4) {
      throw const BackupException('File di backup non valido.');
    }
    final header = utf8.decode(input.sublist(0, 4), allowMalformed: true);
    var offset = 4;
    late int rounds;
    switch (header) {
      case magicV1:
        rounds = pbkdf2RoundsV1;
      case magicV2:
        if (input.length <= 4 + _saltLength + _nonceLength + 4 + 16) {
          throw const BackupException('File di backup non valido.');
        }
      default:
        throw const BackupException('File di backup non valido.');
    }
    final salt = input.sublist(offset, offset + _saltLength);
    offset += _saltLength;
    final nonce = input.sublist(offset, offset + _nonceLength);
    offset += _nonceLength;
    if (header == magicV2) {
      rounds = ByteData.sublistView(input, offset, offset + 4)
          .getUint32(0, Endian.big);
      offset += 4;
      if (rounds < pbkdf2RoundsV1 || rounds > 10000000) {
        throw const BackupException('File di backup non valido.');
      }
    }
    final cipherText = input.sublist(offset);

    final derived = await _pbkdf2For(rounds).deriveKey(
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
      throw const BackupException(
        'Password errata: impossibile aprire il backup.',
      );
    } on RangeError {
      throw const BackupException('File di backup non valido (troncato).');
    }
  }

  // ---------------------------------------------------------------------------
  // Lettura: integrità, manifest, streaming
  // ---------------------------------------------------------------------------

  /// Decifra e decomprime un backup, verificando manifest e integrità.
  /// Lancia [BackupException] con messaggi in italiano.
  ///
  /// Il database viene comunque scritto su file temporaneo tramite
  /// [openBackup]: questo metodo resta per i flussi che vogliono i byte
  /// (i backup cifrati di solo database sono piccoli).
  Future<BackupContent> readBackup(String path, {String? password}) async {
    final handle = await openBackup(path, password: password);
    try {
      final dbBytes = await File(handle.dbPath).readAsBytes();
      return BackupContent(
        dbBytes: dbBytes,
        manifest: handle.manifest,
        schemaVersion: handle.schemaVersion,
      );
    } finally {
      await handle.dispose();
    }
  }

  /// Apre un backup estraendo il database su FILE temporaneo (streaming),
  /// non in memoria: anche un backup completo con migliaia di foto non
  /// provoca picchi di RAM. Il manifest (piccolo) resta in memoria.
  ///
  /// I backup CIFRATI sono di solo database (dimensioni piccole): per
  /// quelli il file viene letto interamente in memoria, limite dichiarato.
  /// Chiama [BackupHandle.dispose] quando hai finito.
  Future<BackupHandle> openBackup(
    String path, {
    String? password,
  }) async {
    final file = File(path);
    if (!await file.exists()) {
      throw const BackupException('File di backup non trovato.');
    }
    final tempDir = await Directory.systemTemp.createTemp('bh_restore');
    final tempDb = p.join(tempDir.path, 'blue_haccp.db');

    try {
      final header = await _readHeader(file);
      final encrypted = header == magicV1 || header == magicV2;
      if (encrypted && (password == null || password.isEmpty)) {
        throw const BackupException(
          'Questo backup è protetto da password: inseriscila per continuare.',
        );
      }

      Map<String, Object?> manifest;
      if (encrypted) {
        final bytes =
            await _decrypt(await file.readAsBytes(), password!);
        try {
          final archive = ZipDecoder().decodeBytes(bytes);
          final dbEntry = archive.find('blue_haccp.db');
          final manifestEntry = archive.find('manifest.json');
          if (dbEntry == null || manifestEntry == null) {
            throw const BackupException(
              'Il file non contiene un backup di HACCPass.',
            );
          }
          await File(tempDb).writeAsBytes(dbBytesOf(dbEntry), flush: true);
          manifest = parseManifest(manifestBytesOf(manifestEntry));
        } on BackupException {
          rethrow;
        } catch (_) {
          throw const BackupException(
            'Password errata o file danneggiato.',
          );
        }
      } else {
        final input = InputFileStream(path);
        try {
          final archive = ZipDecoder().decodeStream(input);
          final dbEntry = archive.find('blue_haccp.db');
          final manifestEntry = archive.find('manifest.json');
          if (dbEntry == null || manifestEntry == null) {
            throw const BackupException(
              'Il file non contiene un backup di HACCPass.',
            );
          }
          manifest = parseManifest(manifestBytesOf(manifestEntry));
          final output = OutputFileStream(tempDb);
          dbEntry.writeContent(output);
          await output.close();
        } finally {
          await input.close();
        }
      }

      _validateManifest(manifest);
      return BackupHandle._(
        dbPath: tempDb,
        manifest: manifest,
        schemaVersion: (manifest['schemaVersion'] as num?)?.toInt() ?? 0,
        hasAttachments: manifest['attachments'] == true,
        tempDir: tempDir.path,
      );
    } catch (_) {
      await _tryDeleteDir(tempDir);
      rethrow;
    }
  }

  Future<String> _readHeader(File file) async {
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, 4)) {
        bytes.addAll(chunk);
        if (bytes.length >= 4) break;
      }
      if (bytes.length < 4) return '';
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

  void _validateManifest(Map<String, Object?> manifest) {
    final schemaVersion = (manifest['schemaVersion'] as num?)?.toInt() ?? 0;
    if (schemaVersion > appDatabaseVersion) {
      throw const BackupException(
        'Il backup è stato creato con una versione più recente '
        'dell\u2019app: aggiorna HACCPass prima di ripristinarlo.',
      );
    }
    // Il ripristino di backup con schema più vecchio è supportato: la
    // migrazione avviene alla prima apertura del DB ripristinato.
  }

  @visibleForTesting
  static List<int> dbBytesOf(ArchiveFile entry) =>
      List<int>.from(entry.content as List<int>);

  @visibleForTesting
  static List<int> manifestBytesOf(ArchiveFile entry) =>
      List<int>.from(entry.content as List<int>);

  @visibleForTesting
  static Map<String, Object?> parseManifest(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) return decoded;
    } catch (_) {
      // Manifest non leggibile: messaggio dedicato sotto.
    }
    throw const BackupException('Manifest del backup non leggibile.');
  }

  /// Verifica l'integrità SQLite del file database estratto.
  Future<bool> verifyIntegrity(String path) => _checkIntegrity(path);

  /// Ripristina un backup (flussi legacy): prima crea un backup di
  /// sicurezza locale, poi sostituisce il DB e lo riapre. Il flusso
  /// completo (sanificazione licenza, percorsi, allegati) è in
  /// [RestoreService].
  Future<void> restoreBackup(
    BackupContent content, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Creo un backup di sicurezza dei dati attuali…');
    final safetyPath = await createBackup();

    onProgress?.call('Verifico l\u2019integrità del database…');
    final tempDir = await Directory.systemTemp.createTemp('bh_restore');
    final tempDb = p.join(tempDir.path, 'check.db');
    try {
      await File(tempDb).writeAsBytes(content.dbBytes, flush: true);

      final integrityOk = await _checkIntegrity(tempDb);
      if (!integrityOk) {
        throw BackupException(
          'Il database nel backup non è integro. Ripristino annullato. '
          '(Il backup di sicurezza è in $safetyPath)',
        );
      }

      onProgress?.call('Sostituisco i dati…');
      await repository.closeForBackup();
      try {
        final dbPath = _database.path;
        await File(tempDb).copy(dbPath);
      } finally {
        await _database.initialize();
        repository.revision.value++;
      }
    } finally {
      await _tryDeleteDir(tempDir);
    }
  }

  Future<bool> _checkIntegrity(String path) async {
    // Apertura in sola lettura: verifica l'integrità del file.
    // Non impostare `version`: sqflite prova a scrivere `user_version`
    // anche in read-only e su Android genera SQLITE_READONLY.
    final db = await openDatabase(
      path,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final result = await db.rawQuery('PRAGMA integrity_check');
      return result.firstOrNull?['integrity_check'] == 'ok';
    } finally {
      await db.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Upload cloud e conservazione
  // ---------------------------------------------------------------------------

  /// Carica il backup sul cloud e applica la politica di conservazione:
  /// ultimi [keepCount] backup PER TIPO (solo dati e completi separati).
  /// I file più vecchi vengono eliminati solo dopo aver verificato che
  /// il file appena caricato sia integro (stessa dimensione remota e
  /// locale) e solo se il nome rispetta il prefisso `HACCPass_backup_`.
  /// Un errore di eliminazione è un avviso, non blocca il backup.
  Future<void> uploadBackup(
    CloudStorageProvider cloud,
    String localPath, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Carico il backup nel cloud…');
    final uploadedId = await cloud.upload(
      path: localPath,
      remoteName: p.basename(localPath),
      folder: 'Backup',
    );

    // Integrità post-caricamento: il file remoto deve avere la stessa
    // dimensione del locale PRIMA di cancellare qualsiasi cosa.
    final localSize = await File(localPath).length();
    final files = await cloud.list('Backup');
    CloudFile? uploaded;
    for (final f in files) {
      if (f.id == uploadedId || (f.name == p.basename(localPath))) {
        if (f.size == null || f.size == localSize) {
          uploaded = f;
          break;
        }
      }
    }
    if (uploaded == null) {
      // Upload non verificabile: NON si elimina niente.
      onProgress?.call(
        'Caricamento non ancora verificabile: la conservazione verrà '
        'riapplicata al prossimo backup.',
      );
      return;
    }

    onProgress?.call('Applico la politica di conservazione…');
    final warnings = <String>[];
    for (final group in _splitByType(files).values) {
      final sorted = group
        ..sort((a, b) => backupSortDate(b).compareTo(backupSortDate(a)));
      final excess = sorted.length > keepCount
          ? sorted.sublist(keepCount)
          : const <CloudFile>[];
      for (final old in excess) {
        if (!old.name.startsWith(backupPrefix)) continue;
        try {
          await cloud.delete(old.id);
        } catch (e) {
          warnings.add('${old.name}: ${cloud.humanError(e)}');
        }
      }
    }
    if (warnings.isNotEmpty) {
      onProgress?.call(
        'Alcuni backup vecchi non sono stati rimossi '
        '(${warnings.length}): la cartella Backup del cloud può essere '
        'ripulita anche a mano.',
      );
    }
  }

  Map<String, List<CloudFile>> _splitByType(List<CloudFile> files) {
    final dataOnly = <CloudFile>[];
    final full = <CloudFile>[];
    for (final f in files) {
      if (!f.name.startsWith(backupPrefix) || !f.name.endsWith('.bhb')) {
        continue;
      }
      if (f.name.startsWith(fullBackupPrefix)) {
        full.add(f);
      } else {
        dataOnly.add(f);
      }
    }
    return {'data': dataOnly, 'full': full};
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }
}

/// Data di ordinamento di un backup in cloud: prima il timestamp nel nome
/// (`HACCPass_backup[_completo]_AAAAMMGG_HHMM`), altrimenti `modifiedTime`.
DateTime backupSortDate(CloudFile file) {
  final match = RegExp(
    r'_(\d{4})(\d{2})(\d{2})_(\d{2})(\d{2})',
  ).firstMatch(file.name);
  if (match != null) {
    final date = DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
    if (date.year >= 2020) return date;
  }
  return file.modifiedAt ?? DateTime(2000);
}

Future<void> _tryDeleteDir(Directory dir) async {
  try {
    await dir.delete(recursive: true);
  } catch (_) {
    // Cleanup best effort: un eventuale file lock del SO non deve
    // interrompere il ripristino.
  }
}

/// Backup aperto in streaming: database estratto su file temporaneo
/// (`dbPath`) e manifest letto. Ricordati di chiamare [dispose].
class BackupHandle {
  BackupHandle._({
    required this.dbPath,
    required this.manifest,
    required this.schemaVersion,
    required this.hasAttachments,
    required this.tempDir,
  });

  final String dbPath;
  final Map<String, Object?> manifest;
  final int schemaVersion;
  final bool hasAttachments;
  final String tempDir;

  DateTime? get createdAt =>
      DateTime.tryParse((manifest['createdAt'] as String?) ?? '');

  String? get appVersion => manifest['appVersion'] as String?;

  int? get attachmentsCount => (manifest['attachmentsCount'] as num?)?.toInt();

  Future<void> dispose() => _tryDeleteDir(Directory(tempDir));
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

/// Ripristino annullato dall'utente: nessun dato è stato modificato.
class BackupCancelledException implements Exception {
  const BackupCancelledException();

  @override
  String toString() => 'Ripristino annullato.';
}

class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => message;
}
