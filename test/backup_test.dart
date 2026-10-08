import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:haccpass/core/database/app_database.dart';
import 'package:haccpass/repositories/haccp_repository.dart';
import 'package:haccpass/services/backup_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('bh_backup_test');
  });

  /// Backup cifrato con PBKDF2 veloce: i test non devono durare secondi.
  BackupService fastBackup() => BackupService(
        repository: _dummyRepository,
        appVersion: 'test',
        encryptionRounds: BackupService.pbkdf2RoundsV1,
      );

  test('BHB2: round-trip con salt e nonce casuali', () async {
    final service = fastBackup();

    final payload = Uint8List.fromList(List.generate(5000, (i) => i % 251));
    final encrypted = await service.encryptPublic(payload, 'segretissima');
    expect(encrypted.length, greaterThan(payload.length));

    // Intestazione BHB2 riconoscibile + salt/nonce/rounds.
    expect(String.fromCharCodes(encrypted.take(4)), 'BHB2');

    final decrypted = await service.decryptPublic(encrypted, 'segretissima');
    expect(decrypted, payload);

    // Password sbagliata: errore dedicato, nessun dato in chiaro.
    await expectLater(
      service.decryptPublic(encrypted, 'sbagliata'),
      throwsA(isA<BackupException>()),
    );
  });

  test('payload diversi producono cifrati diversi (salt/nonce casuali)',
      () async {
    final service = fastBackup();
    final payload = Uint8List.fromList(List.filled(64, 7));
    final a = await service.encryptPublic(payload, 'pw');
    final b = await service.encryptPublic(payload, 'pw');
    expect(a, isNot(equals(b)), reason: 'salt e nonce casuali');

    // Anche i SALT sono diversi tra loro (BHB1 usava un salt quasi
    // costante: questa è la regressione che interessa).
    expect(a.sublist(4, 20), isNot(equals(b.sublist(4, 20))));
  });

  test('BHB1: lettura compatibile dei backup creati dal codice precedente',
      () async {
    final service = fastBackup();
    final payload = Uint8List.fromList(List.generate(300, (i) => i & 0xFF));

    // RICOSTRUISCE un file BHB1 (magic + salt + nonce + ciphertext,
    // PBKDF2 a 120.000 iterazioni) come lo scriveva il codice di prima.
    final bhb1 = await service.encryptAsV1ForTest(payload, 'vecchia');
    expect(String.fromCharCodes(bhb1.take(4)), 'BHB1');

    final decrypted = await service.decryptPublic(bhb1, 'vecchia');
    expect(decrypted, payload);

    await expectLater(
      service.decryptPublic(bhb1, 'errata'),
      throwsA(isA<BackupException>()),
    );
  });

  test('file troncato: errore chiaro, nessun dato parziale', () async {
    final service = fastBackup();
    final encrypted =
        await service.encryptPublic(Uint8List.fromList(List.filled(500, 3)), 'p');
    final truncated = Uint8List.sublistView(encrypted, 0, encrypted.length - 40);
    await expectLater(
      service.decryptPublic(truncated, 'p'),
      throwsA(isA<BackupException>()),
    );

    final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
    await expectLater(
      service.decryptPublic(garbage, 'p'),
      throwsA(isA<BackupException>()),
    );
  });

  test('il backup non contiene MAI segreti: né password né token', () async {
    final db = AppDatabase(
      path: '${tempDir.path}/no_secrets_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await db.initialize();
    final repository = HaccpRepository(db);
    addTearDown(() => db.close());

    await repository.setSetting('cloud_provider', 'gdrive');
    await repository.setSetting('cloud_account', 'cliente@example.com');

    final backup = BackupService(
      repository: repository,
      appVersion: 'test',
      encryptionRounds: BackupService.pbkdf2RoundsV1,
      attachmentsRootOverride: '${tempDir.path}/attachments',
    );
    final path = await backup.createBackup(password: 'segretissima');
    final bytes = await File(path).readAsBytes();

    // La password di cifratura non compare da nessuna parte nel file.
    final asText = String.fromCharCodes(bytes);
    expect(asText.contains('segretissima'), isFalse);

    // Il manifest contiene SOLO i metadati noti: nessun campo con
    // password o token.
    final handle = await backup.openBackup(path, password: 'segretissima');
    addTearDown(handle.dispose);
    final manifest = handle.manifest;
    for (final key in manifest.keys) {
      expect(key.toLowerCase().contains('token'), isFalse);
      expect(key.toLowerCase().contains('password'), isFalse);
      expect(key.toLowerCase().contains('secret'), isFalse);
    }
    expect(manifest['schemaVersion'], appDatabaseVersion);

    // Nessuna impostazione del database contiene chiavi con token o
    // password (i token OAuth vivono solo nel secure storage di
    // sistema, mai nel DB).
    final settings = await db.db.query('settings');
    for (final row in settings) {
      final key = (row['key'] as String).toLowerCase();
      expect(key.contains('token'), isFalse,
          reason: 'chiave sospetta nel database: $key');
      expect(key.contains('password'), isFalse,
          reason: 'chiave sospetta nel database: $key');
    }

    await File(path).delete();
  });

  tearDownAll(() async {
    await tempDir.delete(recursive: true);
  });
}

/// Repository minimo per costruire il servizio senza database aperto
/// (i test di cifratura non toccano il DB).
final _dummyRepository = HaccpRepository(AppDatabase());
