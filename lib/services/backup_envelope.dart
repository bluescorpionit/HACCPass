import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Involucro cifrato e autenticato dell'app per OGNI backup nuovo
/// (Prompt 20, §2-bis), esterno a ogni eventuale cifratura con password
/// dell'utente (che resta lo strato INTERNO). Scopi:
///
/// - integrità forte del file: un byte alterato fa fallire subito il
///   ripristino con messaggio chiaro (il tag GCM sostituisce ogni altro
///   controllo di integrità del file);
/// - il backup su Drive non è più apribile a mano per estrarre foto o
///   dati (scelta intenzionale, vedi `docs/backup.md`; via d'uscita per
///   l'utente: dossier PDF e registri esportabili, invariati).
///
/// Formato `HPBK1` (tutti gli interi big-endian):
///
/// ```
/// intestazione in chiaro (22 byte):
///   'HPBK1' (5) | keyId (1) | prefisso nonce (8, casuale) | plainLen (8)
/// poi, per ogni blocco di plaintext (fino a [chunkSize] byte):
///   encLen (4) | ciphertext (encLen) | tag GCM (16)
/// ```
///
/// - cifratura: AES-256-GCM; nonce del blocco *i* =
///   `prefisso(8) || contatore32(i)`; AAD del blocco *i* =
///   `intestazione(22) || contatore32(i)`: riordino, troncamento e
///   modifica vengono tutti rilevati (il conteggio byte viene
///   confrontato con `plainLen`);
/// - chiave: HKDF-SHA256 dalla costante `_masterKeys[keyId]`, con salt
///   e info fissi. La costante è IDENTICA in ogni build e NON dipende
///   da `BH_ANCHOR_SECRET`: cambiare il segreto di build non rende
///   illeggibile nessun backup. Per aggiungere una chiave futura si
///   aggiunge un nuovo `keyId` e le vecchie restano leggibili per
///   sempre;
/// - i backup creati prima di questo formato (nessun marcatore `HPBK1`)
///   si aprono esattamente come prima.
///
/// È una protezione dell'app sui FILE, non un segreto forte: la chiave
/// sta nel binario e un attacco mirato può rimuoverla. Non scrivere
/// mai che il backup è "inviolabile": "i backup sono protetti
/// dall'app".
class BackupEnvelope {
  BackupEnvelope({this.chunkSize = defaultChunkSize});

  /// Dimensione dei blocchi di cifratura (1 MiB).
  static const int defaultChunkSize = 1024 * 1024;

  static const String magic = 'HPBK1';
  static const int magicLength = 5;
  static const int headerLength = magicLength + 1 + 8 + 8;

  /// Versione della chiave usata per i NUOVI backup.
  static const int currentKeyId = 1;

  /// Chiavi master dell'involucro, per `keyId`.
  ///
  /// REGOLA CRITICA: i valori esistenti NON cambiano MAI (renderanno
  /// illeggibili tutti i backup dei clienti). Per una chiave nuova si
  /// AGGIUNGE un `keyId` e i vecchi restano qui per sempre.
  static const Map<int, List<int>> _masterKeys = {
    1: [
      0x6b, 0x19, 0x2e, 0xf4, 0x53, 0x87, 0xc1, 0x0d,
      0x9a, 0x64, 0x3b, 0xd8, 0x21, 0x7f, 0xe0, 0x46,
      0x8c, 0x35, 0xa9, 0x72, 0x0f, 0xbe, 0x5d, 0x61,
      0xd4, 0x08, 0x93, 0xc7, 0x36, 0xab, 0x70, 0x2c,
    ],
  };

  /// Dimensione dei blocchi (iniettabile per i test).
  final int chunkSize;

  final _gcm = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final _secure = Random.secure();

  /// true se i primi byte letti da un file iniziano con il marcatore
  /// dell'involucro (gli ingressi più corti del marcatore non lo sono
  /// mai: sono backup vecchi o file qualsiasi).
  static bool isEnvelopeMagic(String firstBytes) =>
      firstBytes.length >= magicLength &&
      firstBytes.substring(0, magicLength) == magic;

  /// Legge (al massimo [count] byte) il marcatore di un file.
  static Future<String> readMagic(File file, [int count = magicLength]) async {
    try {
      final bytes = <int>[];
      await for (final chunk in file.openRead(0, count)) {
        bytes.addAll(chunk);
        if (bytes.length >= count) break;
      }
      if (bytes.isEmpty) return '';
      return String.fromCharCodes(bytes);
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Chiavi
  // ---------------------------------------------------------------------------

  Future<SecretKey> _keyFor(int keyId) async {
    final master = _masterKeys[keyId];
    if (master == null) {
      throw const BackupEnvelopeException(
        'Backup creato con una versione pi\u00F9 recente di HACCPass: '
        'aggiorna l\u2019app e riprova.',
      );
    }
    return _hkdf.deriveKey(
      secretKey: SecretKey(master),
      nonce: utf8.encode('HACCPass-backup-envelope-v1'),
      info: utf8.encode('keyId=$keyId'),
    );
  }

  Uint8List _header(int keyId, Uint8List noncePrefix, int plainLength) {
    final header = Uint8List(headerLength);
    header.setRange(0, magicLength, magic.codeUnits);
    header[magicLength] = keyId;
    header.setRange(magicLength + 1, magicLength + 1 + 8, noncePrefix);
    ByteData.sublistView(header, magicLength + 1 + 8)
        .setUint64(0, plainLength, Endian.big);
    return header;
  }

  /// Nonce del blocco [index]: prefisso casuale + contatore.
  Uint8List _chunkNonce(Uint8List noncePrefix, int index) {
    final nonce = Uint8List(12);
    nonce.setRange(0, 8, noncePrefix);
    ByteData.sublistView(nonce, 8).setUint32(0, index, Endian.big);
    return nonce;
  }

  /// AAD del blocco [index]: intestazione + contatore (lega ogni blocco
  /// alla sua posizione e alla lunghezza totale dichiarata).
  List<int> _chunkAad(Uint8List header, int index) {
    final counter = ByteData(4)..setUint32(0, index, Endian.big);
    return header + counter.buffer.asUint8List();
  }

  // ---------------------------------------------------------------------------
  // Byte (backup di soli dati: piccoli, già in memoria)
  // ---------------------------------------------------------------------------

  /// Chiude [plaintext] nell'involucro cifrato dell'app.
  Future<Uint8List> sealBytes(Uint8List plaintext) async {
    final key = await _keyFor(currentKeyId);
    final noncePrefix =
        Uint8List.fromList(List.generate(8, (_) => _secure.nextInt(256)));
    final header = _header(currentKeyId, noncePrefix, plaintext.length);
    final output = BytesBuilder(copy: false)..add(header);
    if (plaintext.isEmpty) {
      await _encryptChunkTo(
          Uint8List(0), output, key, noncePrefix, header, 0);
    } else {
      var index = 0;
      for (var offset = 0; offset < plaintext.length; offset += chunkSize) {
        final end = (offset + chunkSize).clamp(0, plaintext.length);
        await _encryptChunkTo(
          Uint8List.sublistView(plaintext, offset, end),
          output,
          key,
          noncePrefix,
          header,
          index,
        );
        index++;
      }
    }
    return output.takeBytes();
  }

  /// Rimuove l'involucro da [input]: verifica tag e lunghezza; lancia
  /// [BackupEnvelopeException] con messaggi in italiano se il file è
  /// alterato, troncato o di una versione non nota.
  Future<Uint8List> openBytes(Uint8List input) async {
    if (input.length < headerLength) {
      throw const BackupEnvelopeException('File di backup non valido.');
    }
    final keyId = input[magicLength];
    final key = await _keyFor(keyId);
    final noncePrefix = Uint8List.sublistView(
      input,
      magicLength + 1,
      magicLength + 1 + 8,
    );
    final plainLength = ByteData.sublistView(
      input,
      magicLength + 1 + 8,
      headerLength,
    ).getUint64(0, Endian.big);
    final header = Uint8List.sublistView(input, 0, headerLength);

    final output = BytesBuilder(copy: false);
    var offset = headerLength;
    var index = 0;
    var total = 0;
    while (offset < input.length) {
      if (offset + 4 > input.length) {
        throw const BackupEnvelopeException(
          'Backup alterato o danneggiato: ripristino annullato.',
        );
      }
      final encLen = ByteData.sublistView(input, offset, offset + 4)
          .getUint32(0, Endian.big);
      offset += 4;
      if (encLen > chunkSize || offset + encLen + 16 > input.length) {
        throw const BackupEnvelopeException(
          'Backup alterato o danneggiato: ripristino annullato.',
        );
      }
      final plain = await _decryptChunk(
        Uint8List.sublistView(input, offset, offset + encLen + 16),
        key,
        _chunkNonce(noncePrefix, index),
        _chunkAad(header, index),
      );
      output.add(plain);
      total += plain.length;
      offset += encLen + 16;
      index++;
    }
    if (total != plainLength) {
      throw const BackupEnvelopeException(
        'Backup alterato o danneggiato: ripristino annullato.',
      );
    }
    return output.takeBytes();
  }

  Future<void> _encryptChunkTo(
    Uint8List chunk,
    BytesBuilder output,
    SecretKey key,
    Uint8List noncePrefix,
    Uint8List header,
    int index,
  ) async {
    final box = await _gcm.encrypt(
      chunk,
      secretKey: key,
      nonce: _chunkNonce(noncePrefix, index),
      aad: _chunkAad(header, index),
    );
    final len = ByteData(4)..setUint32(0, chunk.length, Endian.big);
    output
      ..add(len.buffer.asUint8List())
      ..add(box.cipherText)
      ..add(box.mac.bytes);
  }

  Future<Uint8List> _decryptChunk(
    Uint8List record,
    SecretKey key,
    Uint8List nonce,
    List<int> aad,
  ) async {
    try {
      final clear = await _gcm.decrypt(
        SecretBox(
          record.sublist(0, record.length - 16),
          nonce: nonce,
          mac: Mac(record.sublist(record.length - 16)),
        ),
        secretKey: key,
        aad: aad,
      );
      return Uint8List.fromList(clear);
    } on SecretBoxAuthenticationError {
      throw const BackupEnvelopeException(
        'Backup alterato o danneggiato: ripristino annullato.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // File (backup completi: flusso a blocchi, niente RAM)
  // ---------------------------------------------------------------------------

  /// Chiude il file [sourcePath] nell'involucro e scrive il risultato
  /// in [destinationPath]: legge e scrive un blocco alla volta, senza
  /// caricare il file in memoria (backup completi con molte foto).
  Future<void> sealFile(String sourcePath, String destinationPath) async {
    final source = File(sourcePath);
    final plainLength = await source.length();
    final key = await _keyFor(currentKeyId);
    final noncePrefix =
        Uint8List.fromList(List.generate(8, (_) => _secure.nextInt(256)));
    final header = _header(currentKeyId, noncePrefix, plainLength);

    final input = await source.open();
    final output = await File(destinationPath).open(mode: FileMode.write);
    try {
      await output.writeFrom(header);
      var index = 0;
      while (true) {
        final chunk = await input.read(chunkSize);
        if (chunk.isEmpty) break;
        final builder = BytesBuilder(copy: false);
        await _encryptChunkTo(chunk, builder, key, noncePrefix, header, index);
        await output.writeFrom(builder.takeBytes());
        index++;
      }
      if (index == 0) {
        // File vuoto: un blocco vuoto autenticato mantiene il formato
        // valido (plainLen = 0).
        final builder = BytesBuilder(copy: false);
        await _encryptChunkTo(
            Uint8List(0), builder, key, noncePrefix, header, 0);
        await output.writeFrom(builder.takeBytes());
      }
    } finally {
      await input.close();
      await output.close();
    }
  }

  /// Rimuove l'involucro dal file [inputPath] e scrive il contenuto in
  /// chiaro in [outputPath], un blocco alla volta. Stessi controlli e
  /// errori di [openBytes].
  Future<void> openToFile(String inputPath, String outputPath) async {
    final input = await File(inputPath).open();
    final output = await File(outputPath).open(mode: FileMode.write);
    try {
      final header = await input.read(headerLength);
      if (header.length < headerLength) {
        throw const BackupEnvelopeException(
          'File di backup non valido (troncato).',
        );
      }
      final keyId = header[magicLength];
      if (!isEnvelopeMagic(String.fromCharCodes(header))) {
        throw const BackupEnvelopeException('File di backup non valido.');
      }
      final key = await _keyFor(keyId);
      final noncePrefix = Uint8List.sublistView(
        header,
        magicLength + 1,
        magicLength + 1 + 8,
      );
      final plainLength = ByteData.sublistView(
        header,
        magicLength + 1 + 8,
        headerLength,
      ).getUint64(0, Endian.big);

      var total = 0;
      var index = 0;
      while (true) {
        final lenBytes = await input.read(4);
        if (lenBytes.isEmpty) break;
        if (lenBytes.length < 4) {
          throw const BackupEnvelopeException(
            'Backup alterato o danneggiato: ripristino annullato.',
          );
        }
        final encLen =
            ByteData.sublistView(lenBytes).getUint32(0, Endian.big);
        if (encLen > chunkSize) {
          throw const BackupEnvelopeException(
            'Backup alterato o danneggiato: ripristino annullato.',
          );
        }
        final record = await input.read(encLen + 16);
        if (record.length < encLen + 16) {
          throw const BackupEnvelopeException(
            'File di backup non valido (troncato).',
          );
        }
        final plain = await _decryptChunk(
          record,
          key,
          _chunkNonce(noncePrefix, index),
          _chunkAad(header, index),
        );
        await output.writeFrom(plain);
        total += plain.length;
        index++;
      }
      if (total != plainLength) {
        throw const BackupEnvelopeException(
          'Backup alterato o danneggiato: ripristino annullato.',
        );
      }
    } finally {
      await input.close();
      await output.close();
    }
  }
}

/// Errore dell'involucro: messaggi in italiano pensati per l'utente
/// (il [BackupService] li riporta com'è).
class BackupEnvelopeException implements Exception {
  const BackupEnvelopeException(this.message);

  final String message;

  @override
  String toString() => message;
}
