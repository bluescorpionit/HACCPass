import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:blue_haccp/core/database/app_database.dart';
import 'package:blue_haccp/repositories/haccp_repository.dart';
import 'package:blue_haccp/services/backup_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('bh_backup_test');
  });

  test('formato .bhb: creazione e lettura senza password', () async {
    // Cifra/decrifra un payload arbitrario verificando il formato del
    // file: questi test coprono la logica di cifratura senza toccare il DB.
    final service = _TestableBackup();

    final payload = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final encrypted = await service.encryptForTest(payload, 'segretissima');
    expect(encrypted.length, greaterThan(payload.length));

    // Intestazione riconoscibile.
    expect(String.fromCharCodes(encrypted.take(4)), 'BHB1');

    // Decifratura con la password giusta.
    final decrypted = await service.decryptForTest(encrypted, 'segretissima');
    expect(decrypted, payload);

    // Con la password sbagliata: errore dedicato, nessun dato in chiaro.
    expect(
      () => service.decryptForTest(encrypted, 'sbagliata'),
      throwsA(isA<BackupException>()),
    );
  });

  test('payload diversi produano cifrati diversi (nonce/salt)', () async {
    final service = _TestableBackup();
    final payload = Uint8List.fromList(List.filled(64, 7));
    final a = await service.encryptForTest(payload, 'pw');
    final b = await service.encryptForTest(payload, 'pw');
    expect(a, isNot(equals(b)), reason: 'salt e nonce casuali');
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });
}

/// Espone le primitive di cifratura del [BackupService] per i test.
class _TestableBackup extends BackupService {
  _TestableBackup()
      : super(
          repository: _dummyRepository,
          appVersion: 'test',
        );

  Future<Uint8List> encryptForTest(Uint8List plaintext, String password) =>
      encryptPublic(plaintext, password);

  Future<Uint8List> decryptForTest(Uint8List input, String password) =>
      decryptPublic(input, password);
}

final _dummyRepository = HaccpRepository(AppDatabase());
