/// Ancora della prova gratuita che sopravvive alla reinstallazione
/// (Prompt 10, punto A).
///
/// La prova locale di 14 giorni non può vivere solo nel database: Android
/// lo cancella insieme all'app e una reinstallazione rigenererebbe la
/// data. L'ancora replica la data di inizio su un supporto che (di norma)
/// sopravvive:
///
/// - **iOS**: Keychain (`flutter_secure_storage`,
///   `KeychainAccessibility.first_unlock_this_device`, NON
///   `synchronizable`): gli elementi Keychain non vengono rimossi alla
///   disinstallazione.
/// - **Android**: la Keystore viene cancellata con l'app, quindi si usa
///   un file `anchor/trial_anchor.json` nella cartella di supporto,
///   incluso SOLO esso nel backup automatico di Android
///   (`res/xml/backup_rules.xml` e `res/xml/data_extraction_rules.xml`:
///   database, allegati e cache sono esclusi). Il ripristino funziona
///   solo se l'utente ha il backup Google attivo e il telefono lo
///   ripristina: è un miglioramento best-effort, documentato in
///   `docs/acquisti.md`.
///
/// Contenuto firmato con HMAC-SHA256 (stesso segreto delle licenze,
/// `LicenseService.appSecret`; vuoto consentito solo in debug):
/// `{"v":1,"start":"<ISO UTC>","lastSeen":"<ISO UTC>","mac":"<base64>"}`.
/// Un contenuto con MAC non valido è trattato come assente e registrato
/// come "alterato".
///
/// Regole:
/// - la data di inizio effettiva è la **più antica** tra database
///   (`trial_started_at`), ancora piattaforma e file ripristinato; alla
///   lettura gli altri supporti vengono riallineati; la data non torna
///   mai indietro... cioè non viene MAI spostata in avanti;
/// - `lastSeen = max(lastSeen, now)` a ogni sincronizzazione (avvio e
///   ripresa dell'app);
/// - se `now < lastSeen - 24 h` l'orologio risulta alterato: la prova è
///   considerata scaduta con stato esplicito, senza crash e senza
///   cancellare dati.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Esito della sincronizzazione dell'ancora.
class TrialAnchorResult {
  const TrialAnchorResult({
    required this.start,
    required this.clockTampered,
    this.anchorAltered = false,
    this.firstInstall = false,
  });

  /// Data di inizio effettiva della prova (la più antica trovata).
  final DateTime start;

  /// Orologio del dispositivo indietro rispetto all'ultimo avvio
  /// (`now < lastSeen - 24 h`).
  final bool clockTampered;

  /// Ancora presente ma con MAC non valido: trattata come assente.
  final bool anchorAltered;

  /// Nessun supporto conteneva una data: la prova inizia adesso.
  final bool firstInstall;
}

/// Supporto di persistenza dell'ancora (iniettabile nei test).
abstract class TrialAnchorStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

/// iOS: Keychain. Gli elementi non vengono rimossi alla disinstallazione
/// dell'app; l'accessibilità `first_unlock_this_device` evita la
/// sincronizzazione tra dispositivi (che renderebbe l'ancora spostabile
/// a piacere).
class KeychainTrialAnchorStorage implements TrialAnchorStorage {
  KeychainTrialAnchorStorage();

  static const _key = 'it.bluescorpion.haccpass.trial_anchor';

  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Android/desktop: file `anchor/trial_anchor.json` nella cartella di
/// supporto dell'app (su Android è inclusa nel backup automatico, vedi
/// regole nel manifest).
class FileTrialAnchorStorage implements TrialAnchorStorage {
  FileTrialAnchorStorage({required Future<Directory> Function() supportDirectory})
      : _supportDirectory = supportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<File> _file() async {
    final root = await _supportDirectory();
    final dir = Directory(p.join(root.path, 'anchor'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File(p.join(dir.path, 'trial_anchor.json'));
  }

  @override
  Future<String?> read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return await file.readAsString();
    } catch (_) {
      // Leggibilità non garantita (storage assente, permessi): come assente.
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    final file = await _file();
    await file.writeAsString(value, flush: true);
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Già assente o non eliminabile: clear è best-effort.
    }
  }
}

/// Ancora della prova: calcola e mantiene la data di inizio effettiva.
class TrialAnchor {
  TrialAnchor({
    required this.secret,
    TrialAnchorStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage,
        _now = now ?? DateTime.now;

  /// Storage di default: Keychain su iOS, file (backup Android) altrove.
  factory TrialAnchor.platform({required String secret}) => TrialAnchor(
        secret: secret,
        storage: defaultStorage(),
      );

  final String secret;
  final TrialAnchorStorage? _storage;
  final DateTime Function() _now;

  static const int version = 1;
  static const Duration clockTolerance = Duration(hours: 24);

  /// Supporto predefinito per piattaforma (Keychain su iOS, file altrove).
  static TrialAnchorStorage defaultStorage() {
    if (Platform.isIOS) return KeychainTrialAnchorStorage();
    return FileTrialAnchorStorage(
      supportDirectory: getApplicationSupportDirectory,
    );
  }

  /// Riallinea tutti i supporti alla data più antica e aggiorna `lastSeen`.
  ///
  /// [databaseStart] è la data `trial_started_at` letta dal database
  /// locale (copia, non supporto primario).
  Future<TrialAnchorResult> synchronize({DateTime? databaseStart}) async {
    final now = _now();
    DateTime? anchorStart;
    DateTime? anchorLastSeen;
    var altered = false;

    final storage = _storage;
    if (storage != null) {
      try {
        final raw = await storage.read();
        if (raw != null && raw.isNotEmpty) {
          final parsed = _parse(raw);
          if (parsed == null) {
            altered = true;
          } else {
            anchorStart = parsed.$1;
            anchorLastSeen = parsed.$2;
          }
        }
      } catch (_) {
        // Storage illeggibile: trattato come assente.
      }
    }

    // Data effettiva = la più antica tra i supporti disponibili.
    final candidates = <DateTime?>[anchorStart, databaseStart]
        .whereType<DateTime>()
        .toList();
    var firstInstall = false;
    final DateTime start;
    if (candidates.isEmpty) {
      start = now;
      firstInstall = true;
    } else {
      start = candidates.reduce((a, b) => a.isBefore(b) ? a : b);
    }

    // Orologio indietro oltre la tolleranza: prova considerata scaduta
    // con stato esplicito (nessun crash, nessun dato cancellato).
    final lastSeen = anchorLastSeen;
    final clockTampered =
        lastSeen != null && now.isBefore(lastSeen.subtract(clockTolerance));

    // lastSeen non torna mai indietro.
    final newLastSeen =
        (lastSeen != null && lastSeen.isAfter(now)) ? lastSeen : now;

    if (storage != null) {
      try {
        await storage.write(_encode(start, newLastSeen));
      } catch (_) {
        // Scrittura non possibile: la data resta comunque nel database.
      }
    }

    return TrialAnchorResult(
      start: start,
      clockTampered: clockTampered,
      anchorAltered: altered,
      firstInstall: firstInstall,
    );
  }

  /// Cancella l'ancora (comando di debug).
  Future<void> clear() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      await storage.clear();
    } catch (_) {
      // Best-effort.
    }
  }

  String _mac(DateTime start, DateTime lastSeen) {
    final payload = 'trial-anchor|$version'
        '|${start.toUtc().toIso8601String()}'
        '|${lastSeen.toUtc().toIso8601String()}';
    final digest = Hmac(sha256, secret.codeUnits).convert(payload.codeUnits);
    return base64Encode(digest.bytes);
  }

  String _encode(DateTime start, DateTime lastSeen) => jsonEncode({
        'v': version,
        'start': start.toUtc().toIso8601String(),
        'lastSeen': lastSeen.toUtc().toIso8601String(),
        'mac': _mac(start, lastSeen),
      });

  /// Ritorna (start, lastSeen) se il contenuto è integro, altrimenti null.
  (DateTime, DateTime)? _parse(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return null;
      if (map['v'] != version) return null;
      final start = DateTime.tryParse(map['start'] as String? ?? '');
      final lastSeen = DateTime.tryParse(map['lastSeen'] as String? ?? '');
      final mac = map['mac'] as String? ?? '';
      if (start == null || lastSeen == null) return null;
      if (lastSeen.isBefore(start)) return null;
      if (mac != _mac(start, lastSeen)) return null;
      return (start, lastSeen);
    } catch (_) {
      return null;
    }
  }
}
