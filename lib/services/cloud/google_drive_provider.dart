import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'cloud_storage.dart';
import 'drive_auth_gateway.dart';

export 'drive_auth_gateway.dart' show driveFileScope;


/// Archivio nel Google Drive **personale** del cliente.
///
/// Cartella visibile "HACCPass" con sottocartelle Backup, Report e Foto:
/// il cliente ritrova i suoi file da qualsiasi dispositivo.
/// Serve solo come archivio: mai "Accedi con Google" (guideline 4.8 Apple).
///
/// `connect(interactive: false)` (usato dal ripristino della sessione
/// all'avvio) usa SOLO autenticazione silenziosa: nessuna finestra di
/// Google; se manca qualcosa restituisce `false` e l'app segna Drive
/// come "da ricollegare" (Prompt 10, D).
class GoogleDriveProvider extends CloudStorageProvider {
  static const _serverClientId =
    String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  GoogleDriveProvider({DriveAuthGateway? gateway})
      : _gateway = gateway ??
            GoogleSignInDriveAuthGateway(serverClientId: _serverClientId);

  final DriveAuthGateway _gateway;

  /// `GoogleSignIn.instance.initialize()` va chiamato UNA sola volta per
  /// esecuzione (richiamarlo lancia un'eccezione).
  static bool _initialized = false;

  String? _accountEmail;
  drive.DriveApi? _api;
  Object? _lastConnectError;

  static const _rootName = 'HACCPass';
  final _folderIds = <String, String>{};

  @override
  String get id => 'gdrive';

  @override
  String get label => 'Google Drive';

  @override
  bool get isConnected => _api != null;

  @override
  String? get accountLabel => _accountEmail;

  Object? get lastConnectError => _lastConnectError;

  Future<void> _initSignIn() async {
    if (_initialized) return;
    await _gateway.initialize();
    _initialized = true;
  }

  void _validateConfiguration() {
    if (Platform.isAndroid && _serverClientId.isEmpty) {
      throw StateError(
        'Configurazione Google Drive incompleta su Android: '
        'manca GOOGLE_SERVER_CLIENT_ID (OAuth Web client ID).',
      );
    }
  }

  @override
  Future<bool> connect({bool interactive = true}) async {
    try {
      _lastConnectError = null;
      _validateConfiguration();
      await _initSignIn();

      // Prima solo silenzioso; le finestre di Google (authenticate /
      // authorizeScopes) sono riservate a interactive: true.
      var session = await _gateway.tryRestoreSession();
      if (session == null && interactive) {
        session = await _gateway.interactiveSession();
      }
      if (session == null) {
        return false;
      }

      _accountEmail = session.email;
      _api = session.api;
      _folderIds.clear();
      return true;
    } catch (e, st) {
      _lastConnectError = e;
      debugPrint('Drive connect fallito: $e\n$st');
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
    _accountEmail = null;
    _lastConnectError = null;
    _folderIds.clear();
    try {
      await _initSignIn();
      await _gateway.disconnect();
    } catch (_) {
      // Disconnessione gi\u00E0 avvenuta o servizio non disponibile.
    }
  }

  @override
  String humanError(Object error) {
    if (error is StateError &&
        error.message
            .toString()
            .contains('manca GOOGLE_SERVER_CLIENT_ID')) {
      return 'Google Drive non configurato: manca GOOGLE_SERVER_CLIENT_ID '
          '(OAuth Web client ID) nella build Android.';
    }
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.clientConfigurationError) {
      return 'Configurazione Google non valida: su Android serve il '
          'serverClientId (OAuth Web client ID).';
    }
    if (error is GoogleSignInException &&
        error.code == GoogleSignInExceptionCode.canceled) {
      return 'Collegamento annullato.';
    }
    return super.humanError(error);
  }
}
