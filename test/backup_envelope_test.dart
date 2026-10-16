import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/services/backup_envelope.dart';

/// Prompt 20, §2-bis: involucro cifrato e autenticato dell'app
/// (marcatore HPBK1). Roundtrip, alterazioni, troncamenti, keyId
/// sconosciuto, flusso a blocchi su file.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final envelope = BackupEnvelope();
  // Blocchi piccoli: forzano più blocchi anche con payload modesti.
  final chunked = BackupEnvelope(chunkSize: 64);

  test('roundtrip byte: marcatore HPBK1 e contenuto identico', () async {
    final payload =
        Uint8List.fromList(List.generate(5000, (i) => (i * 7) % 251));
    final sealed = await envelope.sealBytes(payload);

    expect(String.fromCharCodes(sealed.take(5)), 'HPBK1');
    expect(sealed.length, greaterThan(payload.length));

    final opened = await envelope.openBytes(sealed);
    expect(opened, payload);
  });

  test('roundtrip multi-blocco con chunkSize ridotto', () async {
    final payload =
        Uint8List.fromList(List.generate(1000, (i) => i & 0xFF));
    final sealed = await chunked.sealBytes(payload);
    expect(sealed.length, greaterThan(payload.length));

    final opened = await chunked.openBytes(sealed);
    expect(opened, payload);
  });

  test('un byte alterato al centro: errore pulito, nessun dato', () async {
    final sealed = await envelope.sealBytes(
      Uint8List.fromList(List.generate(2000, (i) => i % 256)),
    );
    final tampered = Uint8List.fromList(sealed);
    tampered[tampered.length ~/ 2] ^= 0xFF;

    await expectLater(
      envelope.openBytes(tampered),
      throwsA(isA<BackupEnvelopeException>().having(
        (e) => e.message,
        'message',
        contains('alterato o danneggiato'),
      )),
    );
  });

  test('byte alterato nell\'ultimo blocco multi-blocco', () async {
    final sealed = await chunked.sealBytes(
      Uint8List.fromList(List.filled(300, 9)),
    );
    final tampered = Uint8List.fromList(sealed);
    tampered[tampered.length - 20] ^= 0x01;

    await expectLater(
      chunked.openBytes(tampered),
      throwsA(isA<BackupEnvelopeException>()),
    );
  });

  test('coda troncata: errore pulito (nessun giorno regalato)', () async {
    final sealed = await envelope.sealBytes(
      Uint8List.fromList(List.filled(500, 3)),
    );
    final truncated = Uint8List.sublistView(sealed, 0, sealed.length - 40);
    await expectLater(
      envelope.openBytes(truncated),
      throwsA(isA<BackupEnvelopeException>()),
    );
  });

  test('intestazione troncata: errore pulito', () async {
    final short = Uint8List.fromList(List.filled(10, 1));
    await expectLater(
      envelope.openBytes(short),
      throwsA(isA<BackupEnvelopeException>()),
    );
  });

  test('keyId sconosciuto: messaggio di aggiornare l\'app', () async {
    final sealed = await envelope.sealBytes(Uint8List.fromList([1, 2, 3]));
    final future = Uint8List.fromList(sealed);
    future[5] = 99; // keyId inesistente
    await expectLater(
      envelope.openBytes(future),
      throwsA(isA<BackupEnvelopeException>().having(
        (e) => e.message,
        'message',
        allOf(contains('aggiorna'), contains('versione pi\u00F9 recente')),
      )),
    );
  });

  test('input senza marcatore: rifiutato, non decifrato', () async {
    final notEnvelope = Uint8List.fromList(List.filled(300, 0x50));
    // Un file qualsiasi lungo abbastanza: il formato interno non è
    // un involucro HPBK1 valido e viene rifiutato senza restituire dati.
    await expectLater(
      envelope.openBytes(notEnvelope),
      throwsA(isA<BackupEnvelopeException>()),
    );
  });

  test('isEnvelopeMagic: riconosce HPBK1, non i backup vecchi', () {
    expect(BackupEnvelope.isEnvelopeMagic('HPBK1'), isTrue);
    expect(BackupEnvelope.isEnvelopeMagic('HPBK1xx'), isTrue);
    expect(BackupEnvelope.isEnvelopeMagic('BHB2'), isFalse);
    expect(BackupEnvelope.isEnvelopeMagic('PK\u0003\u0004'), isFalse);
    expect(BackupEnvelope.isEnvelopeMagic(''), isFalse);
  });

  group('flusso su file (backup completi)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hpbk_test');
    });

    tearDown(() async {
      try {
        await tempDir.delete(recursive: true);
      } catch (_) {}
    });

    test('roundtrip file con più blocchi, contenuto identico', () async {
      final source = File('${tempDir.path}/backup.zip');
      final payload = List<int>.generate(300 * 1024, (i) => i % 253);
      await source.writeAsBytes(payload, flush: true);

      final sealedPath = '${tempDir.path}/backup.bhb';
      await chunked.sealFile(source.path, sealedPath);
      expect(await File(sealedPath).length(), greaterThan(payload.length));

      final openedPath = '${tempDir.path}/inner.bhb';
      await chunked.openToFile(sealedPath, openedPath);
      expect(await File(openedPath).readAsBytes(), payload);
    });

    test('file alterato: openToFile fallisce con errore pulito', () async {
      final source = File('${tempDir.path}/backup.zip');
      await source.writeAsBytes(List.filled(5000, 1), flush: true);

      final sealedPath = '${tempDir.path}/backup.bhb';
      await chunked.sealFile(source.path, sealedPath);

      final sealed = await File(sealedPath).readAsBytes();
      sealed[sealed.length - 5] ^= 0xFF;
      await File(sealedPath).writeAsBytes(sealed, flush: true);

      final openedPath = '${tempDir.path}/inner.bhb';
      await expectLater(
        chunked.openToFile(sealedPath, openedPath),
        throwsA(isA<BackupEnvelopeException>().having(
          (e) => e.message,
          'message',
          contains('alterato o danneggiato'),
        )),
      );
    });

    test('file troncato a metà: errore pulito', () async {
      final source = File('${tempDir.path}/backup.zip');
      await source.writeAsBytes(List.filled(5000, 1), flush: true);

      final sealedPath = '${tempDir.path}/backup.bhb';
      await chunked.sealFile(source.path, sealedPath);
      final sealed = await File(sealedPath).readAsBytes();
      await File(sealedPath)
          .writeAsBytes(sealed.sublist(0, sealed.length ~/ 2), flush: true);

      final openedPath = '${tempDir.path}/inner.bhb';
      await expectLater(
        chunked.openToFile(sealedPath, openedPath),
        throwsA(isA<BackupEnvelopeException>()),
      );
    });
  });
}
