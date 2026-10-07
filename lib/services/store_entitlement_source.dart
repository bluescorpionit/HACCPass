import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/license/entitlement_source.dart';

/// Verifica l'abbonamento interrogando direttamente lo store dell'app.
///
/// Comportamento per piattaforma:
/// - **Android**: `restorePurchases()` alla verifica (che in questa
///   versione del plugin esegue `queryPurchases`, quindi riporta SOLO gli
///   acquisti attivi) e attesa di un evento sullo `purchaseStream`: la
///   risposta (anche lista vuota) arriva come unico evento.
/// - **iOS**: `restorePurchases()` chiede l'accesso all'Apple ID, quindi
///   NON viene mai chiamato automaticamente: lo stato si aggiorna solo
///   dagli eventi di acquisto/ripristino avviati dall'utente.
/// - **Desktop**: store non disponibile, nessuna verifica.
///
/// LIMITI (vedi anche `docs/acquisti.md`): senza un server di verifica
/// (Play Developer API / App Store Server API) lo stato dipende dal
/// client. La verifica lato server è il passo futuro naturale e un
/// servizio come RevenueCat può sostituire questa classe dietro la stessa
/// interfaccia `EntitlementSource`.
class StoreEntitlementSource implements EntitlementSource {
  StoreEntitlementSource({
    required this.productId,
    this.timeout = const Duration(seconds: 10),
  });

  /// ID del prodotto abbonamento da verificare.
  final String productId;

  /// Tempo massimo di attesa della risposta dello store prima di
  /// considerare la verifica non riuscita (offline).
  final Duration timeout;

  bool? _lastKnownActive;
  DateTime? _lastVerifiedAt;

  @override
  Future<EntitlementState> current() async {
    final iap = InAppPurchase.instance;
    final platform = defaultTargetPlatform;
    final desktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
    if (desktop) {
      return _unverified();
    }
    if (platform == TargetPlatform.iOS) {
      // Mai interattivo su iOS all'avvio (Apple ID).
      return _unverified();
    }

    try {
      if (!await iap.isAvailable()) {
        return _unverified();
      }
    } catch (_) {
      return _unverified();
    }

    final purchases = await _queryOwned(iap);
    if (purchases == null) {
      return _unverified();
    }
    final active = purchases.any(
      (p) =>
          p.productID == productId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored),
    );
    _lastKnownActive = active;
    _lastVerifiedAt = DateTime.now();
    return EntitlementState(
      active: active,
      verifiedNow: true,
      verifiedAt: _lastVerifiedAt,
    );
  }

  /// Esegue la query degli acquisti posseduti (solo Android: vedi
  /// [current]). Ritorna null se lo store non risponde entro [timeout].
  Future<List<PurchaseDetails>?> _queryOwned(InAppPurchase iap) async {
    final response = Completer<List<PurchaseDetails>?>();
    late final StreamSubscription<List<PurchaseDetails>> sub;
    sub = iap.purchaseStream.listen(
      (purchases) {
        if (!response.isCompleted) response.complete(purchases);
      },
      onError: (Object _) {
        if (!response.isCompleted) response.complete(null);
      },
    );
    try {
      await iap.restorePurchases();
    } catch (_) {
      await sub.cancel();
      return null;
    }
    try {
      return await response.future.timeout(
        timeout,
        onTimeout: () => null,
      );
    } finally {
      await sub.cancel();
    }
  }

  EntitlementState _unverified() => EntitlementState(
        active: _lastKnownActive ?? false,
        verifiedNow: false,
        verifiedAt: _lastVerifiedAt,
      );
}
