import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:blue_haccp/core/database/app_database.dart';
import 'package:blue_haccp/models/haccp_models.dart';
import 'package:blue_haccp/repositories/haccp_repository.dart';
import 'package:blue_haccp/services/attachment_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  late Directory tempDir;
  late AppDatabase appDatabase;
  late HaccpRepository repository;
  late AttachmentService service;
  late Directory pendingDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('bh_pending_test');
    appDatabase = AppDatabase(
      path: '${tempDir.path}/db_${DateTime.now().millisecondsSinceEpoch}.db',
    );
    await appDatabase.initialize();
    repository = HaccpRepository(appDatabase);
    // Cartella base sovrascritta: nessuna dipendenza da path_provider.
    service = AttachmentService(
      repository: repository,
      baseDirectory: tempDir,
      tempDirectory: tempDir,
    );
    pendingDir = Directory('${tempDir.path}/pending');
    await pendingDir.create(recursive: true);
  });

  tearDown(() async {
    await appDatabase.close();
    await tempDir.delete(recursive: true);
  });

  File fakePendingFile(String name, {bool photo = true}) {
    final file = File('${pendingDir.path}/$name');
    file.writeAsBytesSync(List.generate(256, (i) => i % 251));
    return file;
  }

  Future<int> seedSupplier() {
    return repository.saveSupplier(
      const Supplier(id: 0, name: 'Caseificio Test'),
    );
  }

  test('attachPending: 2 allegati registrati con entity e id corretti',
      () async {
    final receiptId = await repository.saveReceipt(
      Receipt(
        id: 0,
        receivedAt: DateTime.now(),
        supplierId: await seedSupplier(),
        product: 'Stracchino',
        category: 'dairy',
        temperature: 3,
      ),
    );

    final pending = [
      PendingAttachment(
        tempPath: fakePendingFile('ddt.jpg').path,
        kind: 'photo',
        label: 'DDT',
      ),
      PendingAttachment(
        tempPath: fakePendingFile('certificato.pdf').path,
        kind: 'document',
        label: 'Certificato',
      ),
    ];

    await service.attachPending(
      AttachmentEntity.receipt,
      receiptId,
      pending,
    );

    final saved = await repository.getAttachments('receipt', receiptId);
    expect(saved, hasLength(2));
    expect(saved.every((a) => a.entityType == 'receipt'), isTrue);
    expect(saved.every((a) => a.entityId == receiptId), isTrue);
    expect(
      saved.where((a) => a.kind == 'photo').single.note,
      contains('DDT'),
    );
    // I file esistono nella destinazione definitiva (sotto attachments/).
    for (final attachment in saved) {
      expect(File(attachment.localPath).existsSync(), isTrue);
      expect(
        attachment.localPath.replaceAll('\\', '/'),
        contains('/attachments/'),
      );
    }

    // Conteggio per il badge della card.
    final counts = await repository.getAttachmentCounts('receipt');
    expect(counts[receiptId], 2);
  });

  test('discardPending: i file temporanei vengono eliminati (annullamento)',
      () async {
    final files = [
      fakePendingFile('a.jpg'),
      fakePendingFile('b.pdf'),
    ];
    final pending = [
      PendingAttachment(tempPath: files[0].path, kind: 'photo'),
      PendingAttachment(tempPath: files[1].path, kind: 'document'),
    ];

    await service.discardPending(pending);

    expect(files.every((f) => !f.existsSync()), isTrue);
    // Nessun record creato.
    final all = await repository.getAttachments('receipt', 1);
    expect(all, isEmpty);
  });

  test('cloneToTemp: copia un allegato esistente senza toccare l\u2019originale',
      () async {
    final source = fakePendingFile('etichetta.jpg');
    final receiptId = await repository.saveReceipt(
      Receipt(
        id: 0,
        receivedAt: DateTime.now(),
        supplierId: await seedSupplier(),
        product: 'Pasta fresca',
        category: 'fresh_pasta',
      ),
    );
    await service.attachPending(
      AttachmentEntity.receipt,
      receiptId,
      [PendingAttachment(tempPath: source.path, kind: 'photo')],
    );
    final stored = (await repository.getAttachments('receipt', receiptId))
        .single;

    final clone = await service.cloneToTemp(stored);
    expect(File(clone.tempPath).existsSync(), isTrue);
    expect(clone.tempPath, isNot(stored.localPath));
    expect(File(stored.localPath).existsSync(), isTrue);

    await service.discardPending([clone]);
    expect(File(clone.tempPath).existsSync(), isFalse);
  });
}
