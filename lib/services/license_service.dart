import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../core/license/app_integrity.dart';
import '../core/license/entitlement_source.dart';
import '../core/license/trial_anchor.dart';
import '../screens/license_screen.dart';
import 'store_entitlement_source.dart';

/// ID prodotto configurabili per gli acquisti in-app. Vanno creati
/// identici su Play Console e App Store Connect.
///
/// L'unico prodotto è l'abbonamento annuale con offerta di prova
/// gratuita di 14 giorni gestita dallo store (Prompt 13): rinnovi,
/// addebiti, rimborsi e prove dipendono SOLO dagli store. Le chiavi di
/// licenza offline sono state rimosse (codice storico in
/// `tool/archive/`).
class LicenseProductIds {
  static const String annual = 'it.bluescorpion.haccpass.annual';
  static const Set<String> all = {annual};
}

enum LicenseKind { none, trial, iap, debug }

/// Licenza store-only (Prompt 13). Priorità dello stato:
/// abbonamento attivo (anche in prova dello store) > prova locale di
/// riserva attiva > sola lettura; `debug` solo nelle build di debug.
///
/// Nessuna scadenza calcolata come "oggi + 365": l'abbonamento è valido
/// finché lo store lo riporta attivo ([EntitlementSource]); offline vale
/// il periodo di tolleranza [offlineTolerance] da `iap_verified_at`.
///
/// Un database o un backup manomesso non concede nulla: le righe di
/// licenza storiche (`license_kind`, `license_expires_at`,
/// `license_key`, `license_customer`) non sono più lette per concedere
/// nulla e vengono ripulite al primo avvio (migrazione silenziosa).
class LicenseService extends ChangeNotifier {
  LicenseService({
    required Future<String?> Function(String key) readSetting,
    required Future<void> Function(String key, String value) writeSetting,
    EntitlementSource? entitlementSource,
    TrialAnchor? trialAnchor,
  })  : _readSetting = readSetting,
        _writeSetting = writeSetting,
        _entitlement =
            entitlementSource ?? StoreEntitlementSource(productId: LicenseProductIds.annual),
        _trialAnchor =
            trialAnchor ?? TrialAnchor.platform(secret: AppIntegrity.anchorSecret) {
    AppIntegrity.assertConfigured();
  }

  static const int trialDays = 14;

  /// Tolleranza offline della verifica abbonamento (giorni).
  static const Duration offlineTolerance = Duration(days: 7);

  final Future<String?> Function(String key) _readSetting;
  final Future<void> Function(String key, String value) _writeSetting;
  final EntitlementSource _entitlement;
  final TrialAnchor _trialAnchor;

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;
  List<ProductDetails> _annualProducts = [];

  LicenseKind kind = LicenseKind.none;
  DateTime? trialStartedAt;

  /// Abbonamento attivo secondo l'ultima verifica dello store.
  bool iapActive = false;
  DateTime? iapVerifiedAt;

  /// La verifica è riuscita in questa sessione (store raggiunto ora).
  bool iapVerifiedNow = false;

  /// Lo store ha risposto che l'abbonamento non è più attivo (scaduto,
  /// sospeso o disdetto poi scaduto): messaggi dedicati finché non si
  /// riattiva.
  bool subscriptionEnded = false;

  /// Pagamento in sospeso (evento `pending` dello store): avviso non
  /// bloccante con "Gestisci abbonamento".
  bool paymentIssue = false;

  /// Orologio del dispositivo risultato indietro: sola lettura con
  /// stato esplicito, nessun dato cancellato.
  bool clockTampered = false;

  /// Testi reali letti dallo store (mai importi o durate scritti a mano).
  String annualPrice = '';
  String annualOfferText = '';

  /// Offerta con fase gratuita iniziale disponibile (Android: letta dalle
  /// offerte; iOS: applicata automaticamente da StoreKit).
  bool freeTrialAvailable = false;

  bool iapAvailable = false;
  bool loading = true;
  String? lastError;

  /// Piattaforme senza store (build di sviluppo desktop): lì la licenza
  /// non si vende, si usa la prova locale poi sola lettura.
  bool get isDesktop {
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;
  }

  bool get trialActive {
    if (clockTampered) return false;
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

  /// Giorni di tolleranza offline residui (da `iap_verified_at`).
  int get offlineToleranceDaysLeft {
    final verifiedAt = iapVerifiedAt;
    if (verifiedAt == null) return 0;
    final elapsed = DateTime.now().difference(verifiedAt);
    if (elapsed >= offlineTolerance) return 0;
    return offlineTolerance.inDays - elapsed.inDays;
  }

  /// Messaggio esplicito quando l'orologio risulta alterato.
  String? get clockTamperedMessage => clockTampered
      ? 'Orologio del dispositivo alterato: verifica data e ora. I tuoi '
          'dati sono al sicuro; l\'app resta in sola lettura finché la '
          'data non è corretta.'
      : null;

  /// true se si possono registrare nuovi dati o esportare PDF.
  bool get canWrite {
    switch (kind) {
      case LicenseKind.iap:
        return iapActive;
      case LicenseKind.debug:
        return true;
      case LicenseKind.trial:
        return trialActive;
      case LicenseKind.none:
        return false;
    }
  }

  /// Etichetta sintetica per il chip in dashboard.
  String get chipLabel {
    if (clockTampered) return 'Orologio alterato';
    if (kind == LicenseKind.iap) return 'Abbonamento attivo';
    if (kind == LicenseKind.debug) return 'Sblocchi di prova (debug)';
    if (trialActive) return 'Prova: $trialDaysLeft giorni';
    return 'Prova scaduta';
  }

  Future<void> initialize() async {
    await _loadState();
    await _maybeInitIap();
    await _verifyEntitlement();
    loading = false;
    notifyListeners();
  }

  /// Ricarica lo stato dal database dopo un ripristino (Prompt 12, §C):
  /// le impostazioni di licenza sono state sanificate dal
  /// [RestoreService] (mai importate dal backup) e vanno rilette con la
  /// rivalutazione dell'ancora della prova.
  Future<void> reloadAfterRestore() async {
    await _loadState();
    await _verifyEntitlement();
    loading = false;
    notifyListeners();
  }

  /// "Riprova" della schermata licenza: reinizializza gli acquisti
  /// (utile dopo il ripristino della rete o di Google Play).
  Future<void> retryStoreInit() async {
    lastError = null;
    await _maybeInitIap();
    await _verifyEntitlement();
    notifyListeners();
  }

  /// Alla ripresa dell'app: aggiorna `lastSeen` dell'ancora e ricontrolla
  /// l'orologio (Prompt 10, A).
  Future<void> onAppResumed() async {
    final anchor = await _trialAnchor.synchronize(databaseStart: trialStartedAt);
    if (trialStartedAt == null || anchor.start.isBefore(trialStartedAt!)) {
      trialStartedAt = anchor.start;
      await _writeSetting(
        'trial_started_at',
        trialStartedAt!.toIso8601String(),
      );
    }
    clockTampered = anchor.clockTampered;
    notifyListeners();
  }

  Future<void> _loadState() async {
    final storedKind = await _readSetting('license_kind');
    final trialRaw = await _readSetting('trial_started_at');
    final dbTrialStart = DateTime.tryParse(trialRaw ?? '');

    // Ancora della prova (Keychain iOS / file incluso nel backup Android):
    // la data effettiva è la più antica tra i supporti; il database resta
    // una copia allineata.
    final anchor = await _trialAnchor.synchronize(databaseStart: dbTrialStart);
    trialStartedAt = anchor.start;
    clockTampered = anchor.clockTampered;
    if (anchor.anchorAltered) {
      debugPrint('Ancora della prova con MAC non valido: trattata come '
          'assente e riscritta.');
    }
    await _writeSetting(
      'trial_started_at',
      trialStartedAt!.toIso8601String(),
    );

    iapActive = await _readSetting('iap_active') == '1';
    iapVerifiedAt = _trustedVerifiedAt(
      DateTime.tryParse(await _readSetting('iap_verified_at') ?? ''),
    );

    switch (storedKind) {
      case 'iap':
        kind = LicenseKind.iap;
      case 'debug':
        kind = kDebugMode ? LicenseKind.debug : LicenseKind.trial;
      default:
        // 'offline' e valori sconosciuti: mai concesso nulla (Prompt 13,
        // compatibilità dati). Un backup manomesso con license_kind/
        // license_expires_at/license_key non sblocca l'app.
        kind = LicenseKind.trial;
    }

    // Migrazione silenziosa delle righe delle vecchie chiavi offline:
    // al primo avvio vengono pulite.
    if (storedKind == 'offline') {
      for (final key in const [
        'license_key',
        'license_expires_at',
        'license_customer',
      ]) {
        final value = await _readSetting(key);
        if (value != null && value.isNotEmpty) {
          await _writeSetting(key, '');
        }
      }
    }

    _applyPriority();
    await _persistKind();
  }

  /// `iap_verified_at` è creduto solo se non è nel futuro (orologio
  /// alterato o riga manomessa: Prompt 12, §C) e non oltre la tolleranza
  /// offline. Valori oltre i limiti valgono come "da verificare".
  DateTime? _trustedVerifiedAt(DateTime? value) {
    if (value == null) return null;
    final now = DateTime.now();
    if (value.isAfter(now.add(const Duration(minutes: 5)))) return null;
    if (now.difference(value) > offlineTolerance) return null;
    return value;
  }

  /// Priorità: abbonamento attivo (anche in prova store) > prova locale >
  /// sola lettura. `debug` resta sopra solo nelle build di debug.
  void _applyPriority() {
    if (kind == LicenseKind.iap && !iapActive) {
      kind = LicenseKind.trial;
    }
    if ((kind == LicenseKind.trial || kind == LicenseKind.none) && iapActive) {
      kind = LicenseKind.iap;
    }
  }

  Future<void> _maybeInitIap() async {
    if (isDesktop) {
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
      final products = response.productDetails
          .where((p) => p.id == LicenseProductIds.annual)
          .toList();
      _annualProducts = products;
      _updateStoreTexts(products);
      notifyListeners();
    } catch (e) {
      // Store non raggiungibile: la schermata licenza propone "Riprova".
      iapAvailable = false;
      lastError = 'Store non disponibile: $e';
    }
  }

  /// Testi e prezzi mostrati nel paywall, letti DALLO store.
  void _updateStoreTexts(List<ProductDetails> products) {
    if (products.isEmpty) return;
    final trial = _freeTrialProduct(products);
    if (trial != null) {
      freeTrialAvailable = true;
      annualOfferText = _describeGoogleOffer(trial);
      final phases = _phasesOf(trial);
      String? paidPrice;
      if (phases != null) {
        for (final phase in phases) {
          if (phase.priceAmountMicros > 0) {
            paidPrice = phase.formattedPrice;
            break;
          }
        }
      }
      annualPrice = paidPrice ?? trial.price;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS: l'offerta introduttiva (prova gratuita) è applicata
      // automaticamente da StoreKit al primo acquisto; il plugin non
      // espone durata/fasi, quindi si mostra prezzo e durata letti da
      // ProductDetails, senza numeri scritti a mano.
      freeTrialAvailable = true;
      annualPrice = products.first.price;
    } else {
      annualPrice = products.first.price;
    }
  }

  /// Offerta con fase gratuita iniziale (prova gratuita dello store),
  /// se presente tra quelle restituite da Google Play.
  GooglePlayProductDetails? _freeTrialProduct(List<ProductDetails> products) {
    for (final product in products) {
      if (product is! GooglePlayProductDetails) continue;
      final phases = _phasesOf(product);
      if (phases == null || phases.isEmpty) continue;
      if (phases.first.priceAmountMicros == 0) return product;
    }
    return null;
  }

  List<PricingPhaseWrapper>? _phasesOf(GooglePlayProductDetails product) {
    final index = product.subscriptionIndex;
    final offers = product.productDetails.subscriptionOfferDetails;
    if (index == null || offers == null || index >= offers.length) {
      return null;
    }
    return offers[index].pricingPhases;
  }

  /// Frase dell'offerta costruita SOLO con durate e importi dello store,
  /// es. "14 giorni gratis, poi 39,99 €/anno".
  String _describeGoogleOffer(GooglePlayProductDetails product) {
    final phases = _phasesOf(product) ?? const <PricingPhaseWrapper>[];
    final buffer = StringBuffer();
    if (phases.isNotEmpty && phases.first.priceAmountMicros == 0) {
      buffer.write('${_describePeriod(phases.first.billingPeriod)} gratis');
    }
    for (final phase in phases) {
      if (phase.priceAmountMicros > 0) {
        if (buffer.isNotEmpty) buffer.write(', poi ');
        buffer.write(
          '${phase.formattedPrice}/'
          '${_describePeriod(phase.billingPeriod, short: true)}',
        );
        break;
      }
    }
    return buffer.toString();
  }

  /// Periodo ISO 8601 dello store (es. P14D, P1W, P1M, P1Y) in italiano.
  static String _describePeriod(String iso, {bool short = false}) {
    final match = RegExp(
      r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$',
    ).firstMatch(iso.toUpperCase());
    if (match == null) {
      return short ? 'periodo' : 'periodo di prova';
    }
    int? valueOf(String? group) =>
        group == null ? null : int.tryParse(group);
    final years = valueOf(match.group(1));
    final months = valueOf(match.group(2));
    final weeks = valueOf(match.group(3));
    final days = valueOf(match.group(4));
    if (years != null && years > 0) {
      return short ? 'anno' : (years == 1 ? '1 anno' : '$years anni');
    }
    if (months != null && months > 0) {
      return short ? 'mese' : (months == 1 ? '1 mese' : '$months mesi');
    }
    if (weeks != null && weeks > 0) {
      return short
          ? 'settimana'
          : (weeks == 1 ? '1 settimana' : '$weeks settimane');
    }
    if (days != null && days > 0) {
      return short ? 'giorno' : (days == 1 ? '1 giorno' : '$days giorni');
    }
    return short ? 'periodo' : 'periodo di prova';
  }

  /// Verifica periodica dell'abbonamento (Prompt 10, B5).
  ///
  /// Se lo store risponde e `annual` non risulta più posseduto/attivo,
  /// `iap_active = false`. Senza rete vale l'ultimo stato per il periodo
  /// di tolleranza [offlineTolerance] da `iap_verified_at`, poi sola
  /// lettura finché non si riesce a verificare.
  Future<void> _verifyEntitlement() async {
    iapVerifiedNow = false;
    if (!iapActive && kind != LicenseKind.iap) return;
    final EntitlementState state;
    try {
      state = await _entitlement.current();
    } catch (e) {
      lastError = 'Verifica abbonamento non riuscita: $e';
      return;
    }
    if (state.verifiedNow && state.active) {
      iapActive = true;
      iapVerifiedNow = true;
      subscriptionEnded = false;
      iapVerifiedAt = state.verifiedAt ?? DateTime.now();
    } else if (state.verifiedNow) {
      if (iapActive) subscriptionEnded = true;
      iapActive = false;
    } else {
      // Non verificato (offline): tolleranza da iap_verified_at.
      final verifiedAt = iapVerifiedAt;
      if (verifiedAt == null ||
          DateTime.now().difference(verifiedAt) > offlineTolerance) {
        iapActive = false;
      }
    }
    _applyPriority();
    await _persistIap();
    notifyListeners();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (purchase.productID == LicenseProductIds.annual) {
            // Nessuna scadenza calcolata: lo stato dipende dallo store.
            iapActive = true;
            iapVerifiedNow = true;
            subscriptionEnded = false;
            paymentIssue = false;
            iapVerifiedAt = DateTime.now();
            _applyPriority();
            await _persistIap();
          }
          await _complete(purchase);
        case PurchaseStatus.pending:
          if (purchase.productID == LicenseProductIds.annual) {
            paymentIssue = true;
            notifyListeners();
          }
          await _complete(purchase);
        case PurchaseStatus.error:
          lastError = purchase.error?.message ?? 'Errore di acquisto';
          notifyListeners();
          await _complete(purchase);
        case PurchaseStatus.canceled:
          await _complete(purchase);
      }
    }
    notifyListeners();
  }

  /// Ingestione degli eventi di acquisto per i test (la schermata riceve
  /// gli stessi eventi dallo `purchaseStream` del plugin).
  @visibleForTesting
  Future<void> handlePurchasesForTest(List<PurchaseDetails> purchases) =>
      _onPurchases(purchases);

  Future<void> _complete(PurchaseDetails purchase) async {
    try {
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    } catch (_) {
      // completePurchase non critico: il riconoscimento è già avvenuto.
    }
  }

  /// Acquista l'abbonamento annuale. Su Android sceglie l'offerta con
  /// fase gratuita iniziale (prova dello store) se presente.
  Future<void> buyOrRestore(ProductDetails product) async {
    if (!iapAvailable) return;
    final PurchaseParam param;
    if (product is GooglePlayProductDetails) {
      param = GooglePlayPurchaseParam(
        productDetails: product,
        offerToken: product.offerToken,
      );
    } else {
      param = PurchaseParam(productDetails: product);
    }
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Prodotto da acquistare: l'offerta con prova gratuita se presente,
  /// altrimenti il piano base.
  ProductDetails? productToBuy() {
    if (_annualProducts.isEmpty) return null;
    return _freeTrialProduct(_annualProducts) ?? _annualProducts.first;
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

  /// Sblocco di prova: disponibile solo in build debug.
  Future<bool> debugUnlock() async {
    if (!kDebugMode) return false;
    kind = LicenseKind.debug;
    await _persistKind();
    notifyListeners();
    return true;
  }

  /// Azzera prova e licenza: SOLO build debug (voce "Sviluppo" nascosta
  /// in "Altro"). Cancella `trial_started_at`, l'ancora (Keychain/file),
  /// le impostazioni di licenza (incluse le righe storiche delle chiavi
  /// offline) e `iap_*`, poi riavvia lo stato del servizio. Nelle build
  /// di release il metodo non fa nulla.
  Future<void> debugReset() async {
    if (!kDebugMode) return;
    for (final key in const [
      'trial_started_at',
      'license_kind',
      'license_expires_at',
      'license_customer',
      'license_key',
      'iap_active',
      'iap_verified_at',
    ]) {
      await _writeSetting(key, '');
    }
    await _trialAnchor.clear();
    kind = LicenseKind.none;
    trialStartedAt = null;
    iapActive = false;
    iapVerifiedAt = null;
    iapVerifiedNow = false;
    subscriptionEnded = false;
    paymentIssue = false;
    clockTampered = false;
    // Riavvia lo stato: nuova prova (ancora vuota) e priorità ricalcolata.
    await _loadState();
    notifyListeners();
  }

  Future<void> _persistKind() async {
    await _writeSetting('license_kind', kind.name);
  }

  Future<void> _persistIap() async {
    await _writeSetting('iap_active', iapActive ? '1' : '0');
    await _writeSetting(
      'iap_verified_at',
      iapVerifiedAt?.toIso8601String() ?? '',
    );
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
