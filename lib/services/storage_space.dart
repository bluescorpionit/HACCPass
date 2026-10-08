import 'dart:io';

/// Spazio libero sul volume dell'app (Prompt 12, §B.4).
///
/// Non esiste un'API Dart multi-piattaforma per lo spazio libero: si usa
/// `df` dove disponibile (Android/Linux) e PowerShell su Windows. Dove il
/// valore non è determinabile (iOS) si restituisce null: il chiamante
/// gestisce l'eventuale errore di scrittura con un messaggio chiaro e la
/// pulizia dei file temporanei.
class StorageSpace {
  /// Byte liberi nel volume che contiene [path]; null se non
  /// determinabile su questa piattaforma/strumento.
  static Future<int?> freeBytes(String path) async {
    if (Platform.isLinux) return _dfFree(path);
    if (Platform.isAndroid) return _dfFree(path);
    if (Platform.isWindows) return _windowsFree(path);
    return null;
  }

  static Future<int?> _dfFree(String path) async {
    try {
      final result = await Process.run('df', ['-k', path]);
      final lines = (result.stdout as String).trim().split('\n');
      if (lines.length < 2) return null;
      // Filesystem 1024-blocks Used Available Capacity Mounted-on
      final parts = lines.last.split(RegExp(r'\s+'));
      if (parts.length < 4) return null;
      final kb = int.tryParse(parts[3]);
      return kb == null ? null : kb * 1024;
    } catch (_) {
      return null;
    }
  }

  static Future<int?> _windowsFree(String path) async {
    try {
      final drive = path.isEmpty ? 'C' : path.substring(0, 1);
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-PSDrive $drive).Free',
      ]);
      return int.tryParse((result.stdout as String).trim());
    } catch (_) {
      return null;
    }
  }
}
