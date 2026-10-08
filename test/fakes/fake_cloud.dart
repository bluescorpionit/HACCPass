import 'dart:io';
import 'dart:typed_data';

import 'package:haccpass/services/backup_service.dart';
import 'package:haccpass/services/cloud/cloud_storage.dart';

/// Provider cloud finto per i test: registra upload/download/delete e
/// serve un elenco di file configurabile.
class FakeCloudProvider extends CloudStorageProvider {
  FakeCloudProvider({
    this.connected = true,
    List<CloudFile>? backupFiles,
    this.connectResult = true,
  }) : backupFiles = backupFiles ?? <CloudFile>[];

  bool connected;
  bool connectResult;
  List<CloudFile> backupFiles;
  List<CloudFile> fotoFiles = [];

  final uploads = <String>[];
  final deletions = <String>[];
  final downloaded = <String>[];
  int uploadCalls = 0;
  int listCalls = 0;

  /// Contenuto (file locale) servito per id in download: id -> percorso.
  final filesById = <String, String>{};

  /// Se impostato, download lancia quest'errore.
  Object? downloadError;

  /// Se impostato, upload lancia quest'errore.
  Object? uploadError;

  /// Dimensione dichiarata nel list() per il file appena caricato
  /// (default: dimensione reale del file caricato).
  int Function(String localPath)? sizeForUpload;

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive (fake)';

  @override
  bool get isConnected => connected;

  @override
  String? get accountLabel => 'test@example.com';

  @override
  Future<bool> connect({bool interactive = true}) async => connectResult;

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<String> ensureFolder(String subfolder) async => 'folder-$subfolder';

  @override
  Future<String> upload({
    required String path,
    required String remoteName,
    required String folder,
  }) async {
    uploadCalls++;
    if (uploadError != null) throw uploadError!;
    uploads.add(remoteName);
    final id = 'id-${remoteName}_$uploadCalls';
    final size = sizeForUpload != null
        ? sizeForUpload!(path)
        : await File(path).length();
    backupFiles.add(CloudFile(
      id: id,
      name: remoteName,
      modifiedAt: DateTime.now(),
      size: size,
    ));
    filesById[id] = path;
    return id;
  }

  @override
  Future<List<CloudFile>> list(String folder) async {
    listCalls++;
    if (folder == 'Backup') return List.of(backupFiles);
    if (folder == 'Foto') return List.of(fotoFiles);
    return const [];
  }

  @override
  Future<void> download(
    String id,
    String destination, {
    void Function(int downloaded, int? total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    // La richiesta risulta sempre effettuata, anche se poi fallisce.
    downloaded.add(id);
    if (downloadError != null) throw downloadError!;
    final source = filesById[id];
    if (source == null) {
      throw StateError('file non registrato nel fake: $id');
    }
    await File(source).copy(destination);
    final total = await File(destination).length();
    onProgress?.call(total, total);
  }

  @override
  Future<Uint8List?> peekFirstBytes(String id, int count) async {
    final source = filesById[id];
    if (source == null) return null;
    final bytes = await File(source).readAsBytes();
    return Uint8List.fromList(bytes.take(count).toList());
  }

  @override
  Future<void> delete(String id) async {
    deletions.add(id);
    backupFiles.removeWhere((f) => f.id == id);
  }
}

/// Crea un CloudFile di backup con nome nel formato reale.
CloudFile backupFile(
  String name, {
  DateTime? modified,
  int? size,
}) =>
    CloudFile(
      id: 'id-$name',
      name: name,
      modifiedAt: modified ?? DateTime(2026, 1, 1),
      size: size ?? 1024,
    );

/// Nomi validi di backup per i test di retention: data/ora nel nome
/// crescente con n (formato AAAAMMGG_HHMM come i backup reali).
String dataBackupName(int n) => _stampName('HACCPass_backup', n);

String fullBackupName(int n) => _stampName('HACCPass_backup_completo', n);

String _stampName(String prefix, int n) {
  final day = (n + 1).toString().padLeft(2, '0');
  final minute = n.toString().padLeft(2, '0');
  return '${prefix}_202601${day}_00$minute.bhb';
}

bool isFullBackupName(String name) =>
    name.startsWith(BackupService.fullBackupPrefix);
