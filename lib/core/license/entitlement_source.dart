/// Contratto per conoscere lo stato dell'abbonamento (Prompt 10, B6).
///
/// `LicenseService` dipende SOLO da questa interfaccia: la sorgente può
/// essere lo store diretto ([StoreEntitlementSource] in
/// `lib/services/store_entitlement_source.dart`), un server di verifica
/// (Play Developer API / App Store Server API, passo futuro) o un
/// servizio come RevenueCat, senza toccare schermate o servizio.
library;

/// Stato dell'abbonamento secondo la sorgente.
class EntitlementState {
  const EntitlementState({
    required this.active,
    required this.verifiedNow,
    this.verifiedAt,
  });

  /// L'abbonamento `annual` risulta attivo (anche durante la prova
  /// gratuita gestita dallo store).
  final bool active;

  /// La sorgente è stata interrogata con successo ADesso: [active] è
  /// attendibile. Con `false` (rete assente, store non raggiungibile)
  /// vale l'ultimo stato noto e scatta il periodo di tolleranza.
  final bool verifiedNow;

  /// Data dell'ultima verifica riuscita.
  final DateTime? verifiedAt;
}

/// Sorgente del diritto d'uso dell'abbonamento.
abstract class EntitlementSource {
  /// Stato attuale dell'abbonamento `annual`.
  Future<EntitlementState> current();
}
