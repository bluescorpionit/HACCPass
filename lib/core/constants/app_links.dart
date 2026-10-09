/// Indirizzi pubblici dell'app (Prompt 11-bis, §6): UNA sola fonte.
/// Se il dominio o il percorso cambia si corregge solo qui.
library;

class AppLinks {
  AppLinks._();

  /// Percorso base delle pagine del prodotto.
  static const String base = 'https://www.bluescorpion.it/haacpass';

  static const String privacyUrl = '$base/privacy.html';

  static const String termsUrl = '$base/termini.html';

  /// Email di supporto mostrata ai clienti.
  static const String supportEmail = 'support@bluescorpion.it';
}
