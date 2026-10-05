/// Astrazione del servizio di archiviazione cloud scelto dal cliente.
///
/// Principio: i file vanno nel cloud **personale** del cliente, mai su
/// server dello sviluppatore. L'implementazione locale usa solo la
/// condivisione/il selettore di sistema.
library;

import 'dart:io';

abstract class CloudStorageProvider {
  /// Codice persistito in settings (`cloud_provider`).
  String get id;

  String get label;

  bool get isConnected;

  /// Email o descrizione dell'account collegato (se connesso).
  String? get accountLabel;

  /// Chiede il collegamento (OAuth o selettore di sistema).
  /// Restituisce true se collegato.
  Future<bool> connect();

  /// Revoca i token e cancella le credenziali locali.
  Future<void> disconnect();

  /// Garantisce che esista la cartella radice "Blue HACCP" (o equivalente)
  /// e le sottocartelle indicate. Restituisce l'identificativo della
  /// sottocartella richiesta.
  Future<String> ensureFolder(String subfolder);

  /// Carica un file locale in una sottocartella di "Blue HACCP".
  /// Restituisce l'id remoto del file caricato.
  Future<String> upload({
    required String path,
    required String remoteName,
    required String folder,
  });

  /// Elenca i file di una sottocartella: (id, nome, data modifica).
  Future<List<CloudFile>> list(String folder);

  /// Scarica un file remoto in un percorso locale.
  Future<void> download(String id, String destination);

  /// Caricare in cloud pu\u00F2 fallire per molti motivi: questi messaggi
  /// sono pensati per l'operatore, in italiano.
  String humanError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('quota') || text.contains('storagequant')) {
      return 'Spazio del cloud esaurito.';
    }
    if (text.contains('network') || text.contains('failed host') ||
        text.contains('socket')) {
      return 'Rete non disponibile.';
    }
    if (text.contains('unauthorized') || text.contains('401') ||
        text.contains('invalid_grant')) {
      return 'Accesso scaduto: ricollega il servizio.';
    }
    return 'Operazione non riuscita: $error';
  }
}

class CloudFile {
  const CloudFile({
    required this.id,
    required this.name,
    required this.modifiedAt,
    this.size,
  });

  final String id;
  final String name;
  final DateTime? modifiedAt;
  final int? size;
}

/// Fornitore "solo questo dispositivo": nessun collegamento, nessun
/// caricamento automatico. Backup e PDF passano dal foglio di condivisione
/// o dal selettore "Salva con nome" di sistema (che include ogni cloud
/// installato, senza SDK n\u00E9 OAuth).
class LocalFilesProvider extends CloudStorageProvider {
  @override
  String get id => 'local';

  @override
  String get label => 'Solo su questo dispositivo';

  @override
  bool get isConnected => false;

  @override
  String? get accountLabel => null;

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<String> ensureFolder(String subfolder) async => '';

  @override
  Future<String> upload({
    required String path,
    required String remoteName,
    required String folder,
  }) async {
    throw UnsupportedError(
      'Con "Solo su questo dispositivo" i file si salvano con il foglio di '
      'condivisione di sistema.',
    );
  }

  @override
  Future<List<CloudFile>> list(String folder) async => const [];

  @override
  Future<void> download(String id, String destination) async {
    throw UnsupportedError('Nessun cloud collegato.');
  }
}

/// Verifica che un file esista e sia leggibile (usata dal ripristino).
Future<bool> isReadableFile(String path) async {
  try {
    final file = File(path);
    return await file.exists() && await file.length() > 0;
  } catch (_) {
    return false;
  }
}
