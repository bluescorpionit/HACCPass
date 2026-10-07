/// Collegamenti profondi (QR delle attrezzature, Prompt 9).
///
/// Sono validi DUE schemi:
/// - `haccpass://equipment/<id>`: attuale, generato nei PDF da Prompt 9;
/// - `bluehaccp://equipment/<id>`: storico, mantenuto per i QR già
///   stampati nei test (NON rimuovere).
///
/// Restituisce l'id dell'attrezzatura, null per link non riconosciuti.
int? parseEquipmentDeepLink(String? link) {
  if (link == null || link.isEmpty) return null;
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  if (uri.host != 'equipment') return null;
  if (uri.scheme != 'haccpass' && uri.scheme != 'bluehaccp') return null;
  final id = int.tryParse(uri.path.replaceFirst('/', '').trim());
  if (id == null || id <= 0) return null;
  return id;
}
