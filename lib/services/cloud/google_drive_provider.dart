import 'dart:io';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'cloud_storage.dart';

/// Scope minimo: l'app vede solo i file che crea o che il cliente le apre.
/// Non usare scope pi\u00F9 ampi: richiederebbero la verifica di sicurezza.
const String driveFileScope = 'https://www.googleapis.com/auth/drive.file';

/// Archivio nel Google Drive **personale** del cliente.
///
/// Cartella visibile "HACCPass" con sottocartelle Backup, Report e Foto:
/// il cliente ritrova i suoi file da qualsiasi dispositivo.
/// Serve solo come archivio: mai "Accedi con Google" (guideline 4.8 Apple).
class GoogleDriveProvider extends CloudStorageProvider {
  GoogleDriveProvider();

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  drive.DriveApi? _api;

  static const _rootName = 'HACCPass';
  final _folderIds = <String, String>{};

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive';

  @override
  bool get isConnected => _api != null;

  @override
  String? get accountLabel => _account?.email;

  Future<void> _initSignIn() async {
    try {
      await _signIn.initialize();
    } on Exception {
      // Gi\u00E0 inizializzato: sicuro ignorare.
    }
  }

  @override
  Future<bool> connect() async {
    try {
      await _initSignIn();

      _account = await _signIn.attemptLightweightAuthentication();
      _account ??= await _signIn.authenticate(scopeHint: const [driveFileScope]);

      final authorizationClient = _account!.authorizationClient;
      var authorization = await authorizationClient
          .authorizationForScopes(const [driveFileScope]);
      authorization ??=
          await authorizationClient.authorizeScopes(const [driveFileScope]);

      final client = authorization.authClient(scopes: const [driveFileScope]);
      _api = drive.DriveApi(client);
      _folderIds.clear();
      return true;
    } catch (e) {
      _api = null;
      return false;
    }
  }

  drive.DriveApi get _drive {
    final api = _api;
    if (api == null) {
      throw StateError('Google Drive non collegato');
    }
    return api;
  }

  Future<String?> _findFolder(String name, {String? parent}) async {
    final parentClause =
        parent == null ? "'root' in parents" : "'$parent' in parents";
    final result = await _drive.files.list(
      q: "mimeType = 'application/vnd.google-apps.folder' "
          "and name = '$name' and trashed = false and $parentClause",
      $fields: 'files(id, name)',
    );
    return result.files?.firstOrNull?.id;
  }

  Future<String> _createFolder(String name, {String? parent}) async {
    final file = drive.File(
      name: name,
      mimeType: 'application/vnd.google-apps.folder',
      parents: parent == null ? null : [parent],
    );
    final created = await _drive.files.create(file);
    return created.id!;
  }

  @override
  Future<String> ensureFolder(String subfolder) async {
    final cached = _folderIds[subfolder];
    if (cached != null) return cached;

    var root = await _findFolder(_rootName);
    root ??= await _createFolder(_rootName);
    var child = await _findFolder(subfolder, parent: root);
    child ??= await _createFolder(subfolder, parent: root);

    _folderIds[subfolder] = child;
    return child;
  }

  @override
  Future<String> upload({
    required String path,
    required String remoteName,
    required String folder,
  }) async {
    final folderId = await ensureFolder(folder);
    final file = File(path);
    final stream = file.openRead();
    final media = drive.Media(stream, await file.length());

    final metadata = drive.File(
      name: remoteName,
      parents: [folderId],
    );
    final created = await _drive.files.create(metadata, uploadMedia: media);
    return created.id!;
  }

  @override
  Future<List<CloudFile>> list(String folder) async {
    final folderId = await ensureFolder(folder);
    final result = await _drive.files.list(
      q: "'$folderId' in parents and trashed = false",
      $fields: 'files(id, name, modifiedTime, size)',
      orderBy: 'modifiedTime desc',
    );
    return [
      for (final f in result.files ?? <drive.File>[])
        CloudFile(
          id: f.id!,
          name: f.name ?? '',
          modifiedAt: f.modifiedTime,
          size: int.tryParse(f.size ?? ''),
        ),
    ];
  }

  @override
  Future<void> download(String id, String destination) async {
    final media = await _drive.files.get(
      id,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final sink = File(destination).openWrite();
    await for (final chunk in media.stream) {
      sink.add(chunk);
    }
    await sink.close();
  }

  @override
  Future<void> disconnect() async {
    _api = null;
    _account = null;
    _folderIds.clear();
    try {
      await _initSignIn();
      await _signIn.disconnect();
    } catch (_) {
      // Disconnessione gi\u00E0 avvenuta o servizio non disponibile.
    }
  }

  @override
  String humanError(Object error) {
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return 'Collegamento annullato.';
    }
    return super.humanError(error);
  }
}
