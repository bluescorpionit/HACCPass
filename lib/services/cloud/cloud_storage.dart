/// Astrazione del servizio di archiviazione cloud scelto dal cliente.
///
/// Principio: i file vanno nel cloud **personale** del cliente, mai su
/// server dello sviluppatore. L'implementazione locale usa solo la
/// condivisione/il selettore di sistema.
library;

import 'dart:io';
import 'dart:typed_data';

abstract class CloudStorageProvider {
  /// Codice persistito in settings (`cloud_provider`).
  String get id;

  String get label;

  bool get isConnected;

  /// Email o descrizione dell'account collegato (se connesso).
  String? get accountLabel;

  /// Chiede il collegamento (OAuth o selettore di sistema).
  ///
  /// [interactive] è riservato all'azione esplicita dell'utente (pulsante
  /// "Collega"): solo in quel caso possono comparire finestre di Google.
  /// Restituisce true se collegato.
  Future<bool> connect({bool interactive = true});

  /// Revoca i token e cancella le credenziali locali.
  Future<void> disconnect();

  /// Garantisce che esista la cartella radice "HACCPass" (o equivalente)
  /// e le sottocartelle indicate. Restituisce l'identificativo della
  /// sottocartella richiesta.
  Future<String> ensureFolder(String subfolder);

  /// Carica un file locale in una sottocartella di "HACCPass".
  /// Restituisce l'id remoto del file caricato.
  Future<String> upload({
    required String path,
    required String remoteName,
    required String folder,
  });

  /// Elenca i file di una sottocartella: (id, nome, data modifica).
  Future<List<CloudFile>> list(String folder);

  /// Scarica un file remoto in un percorso locale.
  ///
  /// [onProgress] riceve i byte scaricati e la dimensione totale (se
  /// nota); [shouldCancel] permette di interrompere lo scaricamento:
  /// in quel caso il file parziale viene eliminato e viene lanciata
  /// [CloudDownloadCancelled].
  Future<void> download(
    String id,
    String destination, {
    void Function(int downloaded, int? total)? onProgress,
    bool Function()? shouldCancel,
  });

  /// Legge i primi [count] byte di un file remoto senza scaricarlo
  /// tutto (usato per riconoscere i backup cifrati). Null se il
  /// provider non supporta la lettura parziale.
  Future<Uint8List?> peekFirstBytes(String id, int count) async => null;

  /// Elimina un file remoto (conservazione dei backup). I provider che
  /// non la supportano lanciano [UnsupportedError]; "solo questo
  /// dispositivo" è un no-op (nessun file remoto).
  Future<void> delete(String id) async {
    throw UnsupportedError(
      'Questo servizio cloud non supporta l\u2019eliminazione remota.',
    );
  }

  /// Caricare in cloud pu\u00F2 fallire per molti motivi: questi messaggi
  /// sono pensati per l'operatore, in italiano.
  String humanError(Object error) {
    if (error is CloudDownloadCancelled) return error.toString();
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

/// Scaricamento annullato dall'utente: il file parziale è già stato
/// eliminato dal provider.
class CloudDownloadCancelled implements Exception {
  const CloudDownloadCancelled();

  @override
  String toString() => 'Scaricamento annullato.';
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
  Future<bool> connect({bool interactive = true}) async => true;

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
  Future<void> download(
    String id,
    String destination, {
    void Function(int downloaded, int? total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    throw UnsupportedError('Nessun cloud collegato.');
  }

  @override
  Future<void> delete(String id) async {}
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
