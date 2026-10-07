import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

/// Scope minimo: l'app vede solo i file che crea o che il cliente le
/// apre. Non usare scope più ampi: richiederebbero la verifica di
/// sicurezza. (Costante condivisa da provider e gateway.)
const String driveFileScope = 'https://www.googleapis.com/auth/drive.file';

/// Sessione Drive già autorizzata: email dell'account e client API pronto.
class DriveSession {
  const DriveSession({required this.email, required this.api});

  final String email;
  final drive.DriveApi api;
}

/// Seam di autenticazione di Google Drive (Prompt 10, D): il provider
/// usa SOLO questo contratto, così i test possono iniettare un gateway
/// finto e verificare il comportamento non interattivo senza il plugin.
abstract class DriveAuthGateway {
  /// Inizializza il sign-in (chiamato una sola volta per esecuzione dal
  /// provider).
  Future<void> initialize();

  /// Sessione silenziosa: account leggero + autorizzazione scope già
  /// concessa. MAI finestre di Google. Null se non riuscita.
  Future<DriveSession?> tryRestoreSession();

  /// Sessione interattiva: può mostrare il selettore account e la
  /// schermata di consenso Google.
  Future<DriveSession?> interactiveSession();

  /// Revoca i token e disconnette l'account.
  Future<void> disconnect();
}

/// Implementazione reale su `google_sign_in` + autorizzazione apis.
class GoogleSignInDriveAuthGateway implements DriveAuthGateway {
  GoogleSignInDriveAuthGateway({String? serverClientId})
      : _serverClientId = serverClientId;

  final String? _serverClientId;

  GoogleSignIn get _signIn => GoogleSignIn.instance;

  @override
  Future<void> initialize() {
    final clientId = _serverClientId;
    return _signIn.initialize(
      serverClientId:
          clientId == null || clientId.isEmpty ? null : clientId,
    );
  }

  @override
  Future<DriveSession?> tryRestoreSession() async {
    final account = await _signIn.attemptLightweightAuthentication();
    if (account == null) return null;
    final authorizationClient = account.authorizationClient;
    final authorization = await authorizationClient
        .authorizationForScopes(const [driveFileScope]);
    if (authorization == null) return null;
    return DriveSession(
      email: account.email,
      api: drive.DriveApi(
        authorization.authClient(scopes: const [driveFileScope]),
      ),
    );
  }

  @override
  Future<DriveSession?> interactiveSession() async {
    final account = await _signIn.authenticate(
      scopeHint: const [driveFileScope],
    );
    final authorizationClient = account.authorizationClient;
    var authorization = await authorizationClient
        .authorizationForScopes(const [driveFileScope]);
    authorization ??= await authorizationClient
        .authorizeScopes(const [driveFileScope]);
    return DriveSession(
      email: account.email,
      api: drive.DriveApi(
        authorization.authClient(scopes: const [driveFileScope]),
      ),
    );
  }

  @override
  Future<void> disconnect() => _signIn.disconnect();
}
