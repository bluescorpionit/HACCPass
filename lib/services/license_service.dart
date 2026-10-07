import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../core/license/license_codec.dart';
import '../screens/license_screen.dart';

/// ID prodotto configurabili per gli acquisti in-app (allineati
/// all'identificativo definitivo dell'app, Prompt 9). Vanno creati
/// identici su Play Console e App Store Connect.
class LicenseProductIds {
  static const String annual = 'it.bluescorpion.haccpass.annual';
  static const String lifetime = 'it.bluescorpion.haccpass.lifetime';
  static const Set<String> all = {annual, lifetime};
}

enum LicenseKind { none, trial, offline, iap, debug }

class LicenseService extends ChangeNotifier {
  LicenseService({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
  })  : _readSetting = readSetting,
        _writeSetting = writeSetting,
        codec = LicenseCodec(secret: appSecret) {
    // Un segreto vuoto renderebbe forgiabili le chiavi offline: in
    // release l'app si rifiuta di partire (build/avvio esplicito),
    // in debug resta consentito con avviso.
    if (kReleaseMode && appSecret.isEmpty) {
      throw StateError(
        'BH_LICENSE_SECRET mancante: build di release senza segreto di '
        'licenza. Ricompila con --dart-define=BH_LICENSE_SECRET=<valore> '
        '(vedi docs/identificativi.md).',
      );
    }
    assert(() {
      if (appSecret.isEmpty) {
        debugPrint(
          'AVVISO: BH_LICENSE_SECRET vuoto (consentito solo in debug): le '
          'chiavi offline NON sono sicure.',
        );
      }
      return true;
    }());
  }

  /// Segreto per la verifica offline delle chiavi.
  /// Passare in build: --dart-define=BH_LICENSE_SECRET=...
  static const String appSecret = String.fromEnvironment('BH_LICENSE_SECRET');

  static const int trialDays = 14;

  final Future<String?> Function(String key) _readSetting;
  final Future<void> Function(String key, String value) _writeSetting;
  final LicenseCodec codec;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  LicenseKind kind = LicenseKind.none;
  DateTime? trialStartedAt;
  DateTime? expiresAt;
  String customerCode = '';

  /// Prezzi letti dallo store (non inventati).
  String annualPrice = '';
  String lifetimePrice = '';
  bool iapAvailable = false;
  bool loading = true;
  String? lastError;

  bool get isLifetime => kind != LicenseKind.none && _isLifetimeDate(expiresAt);

  bool get trialActive {
    if (kind == LicenseKind.trial && trialStartedAt != null) {
      return DateTime.now().isBefore(trialStartedAt!.add(
        const Duration(days: trialDays),
      ));
    }
    return false;
  }

  int get trialDaysLeft {
    if (trialStartedAt == null) return trialDays;
    final end = trialStartedAt!.add(const Duration(days: trialDays));
    return end.difference(DateTime.now()).inDays.clamp(0, trialDays);
  }

  /// true se si possono registrare nuovi dati o esportare PDF.
  bool get canWrite {
    switch (kind) {
      case LicenseKind.offline:
      case LicenseKind.iap:
      case LicenseKind.debug:
        return _licenseValid;
      case LicenseKind.trial:
        return trialActive;
      case LicenseKind.none:
        return false;
    }
  }

  bool get _licenseValid => expiresAt == null || DateTime.now().isBefore(expiresAt!);

  bool _isLifetimeDate(DateTime? d) =>
      d != null && d.year >= 9999;

  /// Etichetta sintetica per il chip in dashboard.
  String get chipLabel {
    if (canWrite && isLifetime) return 'Licenza a vita';
    if (kind == LicenseKind.iap || kind == LicenseKind.offline) {
      final days = expiresAt?.difference(DateTime.now()).inDays ?? 0;
      return 'Licenza attiva ($days gg)';
    }
    if (kind == LicenseKind.debug) return 'Sblocchi di prova (debug)';
    if (trialActive) return 'Prova: $trialDaysLeft giorni';
    return 'Prova scaduta';
  }

  Future<void> initialize() async {
    await _loadState();
    await _maybeInitIap();
    loading = false;
    notifyListeners();
  }

  Future<void> _loadState() async {
    final storedKind = await _readSetting('license_kind');
    final trialRaw = await _readSetting('trial_started_at');
    trialStartedAt = DateTime.tryParse(trialRaw ?? '');
    if (trialStartedAt == null) {
      trialStartedAt = DateTime.now();
      await _writeSetting(
        'trial_started_at',
        trialStartedAt!.toIso8601String(),
      );
    }

    final expRaw = await _readSetting('license_expires_at');
    expiresAt = DateTime.tryParse(expRaw ?? '');
    customerCode = await _readSetting('license_customer') ?? '';

    switch (storedKind) {
      case 'offline':
        kind = LicenseKind.offline;
      case 'iap':
        kind = LicenseKind.iap;
      case 'debug':
        kind = kDebugMode ? LicenseKind.debug : LicenseKind.none;
      default:
        kind = LicenseKind.trial;
    }

    // Una licenza scaduta torna in prova scaduta.
    if ((kind == LicenseKind.offline || kind == LicenseKind.iap) &&
        !_licenseValid) {
      kind = LicenseKind.trial;
    }
  }

  Future<void> _maybeInitIap() async {
    final desktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (desktop) {
      iapAvailable = false;
      return;
    }
    try {
      iapAvailable = await _iap.isAvailable();
      if (!iapAvailable) return;

      _purchaseSub ??= _iap.purchaseStream.listen(
        _onPurchases,
        onError: (Object e) {
          lastError = 'Acquisto non completato: $e';
          notifyListeners();
        },
      );

      final response = await _iap.queryProductDetails(LicenseProductIds.all);
      for (final product in response.productDetails) {
        if (product.id == LicenseProductIds.annual) {
          annualPrice = product.price;
        } else if (product.id == LicenseProductIds.lifetime) {
          lifetimePrice = product.price;
        }
      }
      notifyListeners();
    } catch (e) {
      // Store non raggiungibile: l'app resta utilizzabile con gli altri canali.
      iapAvailable = false;
      lastError = 'Store non disponibile: $e';
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _activateIap(purchase.productID);
          await _complete(purchase);
        case PurchaseStatus.error:
          lastError = purchase.error?.message ?? 'Errore di acquisto';
          notifyListeners();
          await _complete(purchase);
        case PurchaseStatus.canceled:
        case PurchaseStatus.pending:
          await _complete(purchase);
      }
    }
  }

  Future<void> _complete(PurchaseDetails purchase) async {
    try {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    } catch (_) {
      // completePurchase non critico: il riconoscimento è già avvenuto.
    }
  }

  Future<void> _activateIap(String productId) async {
    kind = LicenseKind.iap;
    expiresAt = productId == LicenseProductIds.lifetime
        ? DateTime(9999, 12, 31)
        : DateTime.now().add(const Duration(days: 365));
    await _persist();
    notifyListeners();
  }

  /// Acquisto o ripristino acquisti in-app.
  Future<void> buyOrRestore(ProductDetails product) async {
    if (!iapAvailable) return;
    final param = PurchaseParam(productDetails: product);
    if (product.id == LicenseProductIds.annual) {
      await _iap.buyNonConsumable(purchaseParam: param);
    } else {
      await _iap.buyNonConsumable(purchaseParam: param);
    }
  }

  Future<void> restorePurchases() async {
    if (!iapAvailable) return;
    try {
      await _iap.restorePurchases();
    } catch (e) {
      lastError = 'Ripristino non riuscito: $e';
      notifyListeners();
    }
  }

  /// Attivazione con chiave offline (vendita diretta).
  Future<bool> unlockWithKey(String rawKey) async {
    final info = codec.tryParse(rawKey);
    if (info == null || !info.isValid) return false;
    kind = LicenseKind.offline;
    expiresAt = info.expiresAt;
    customerCode = info.customerCode;
    await _writeSetting('license_key', rawKey.trim().toUpperCase());
    await _persist();
    notifyListeners();
    return true;
  }

  /// Sblocco di prova: disponibile solo in build debug.
  Future<bool> debugUnlock() async {
    if (!kDebugMode) return false;
    kind = LicenseKind.debug;
    expiresAt = DateTime(9999, 12, 31);
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> _persist() async {
    await _writeSetting('license_kind', kind.name);
    await _writeSetting(
      'license_expires_at',
      expiresAt?.toIso8601String() ?? '',
    );
    await _writeSetting('license_customer', customerCode);
  }

  /// Punto univoco di controllo: se la licenza non consente scritture
  /// apre il paywall e restituisce false.
  bool ensureLicensed(BuildContext context) {
    if (canWrite) return true;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => LicenseScreen(license: this)),
    );
    return false;
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }
}
