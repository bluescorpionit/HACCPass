import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:haccpass/core/license/entitlement_source.dart';
import 'package:haccpass/core/license/trial_anchor.dart';
import 'package:haccpass/services/license_service.dart';

class _MemSettings {
  final map = <String, String>{};

  Future<String?> read(String key) async => map[key];
  Future<void> write(String key, String value) async => map[key] = value;
}

class _MemAnchorStorage implements TrialAnchorStorage {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String v) async => value = v;

  @override
  Future<void> clear() async => value = null;
}

class _FakeEntitlement implements EntitlementSource {
  _FakeEntitlement(this.state);

  EntitlementState state;
  int calls = 0;

  @override
  Future<EntitlementState> current() async {
    calls++;
    return state;
  }
}

PurchaseDetails _purchase(PurchaseStatus status, [String? productId]) =>
    PurchaseDetails(
      productID: productId ?? LicenseProductIds.annual,
      purchaseID: 'test-purchase',
      status: status,
      transactionDate: '0',
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'test',
      ),
    );

void main() {
  // Evita il plugin in_app_purchase nei test: il servizio salta la
  // parte store (desktop) e la verifica passa dal fake.
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  TestWidgetsFlutterBinding.ensureInitialized();

  const secret = 'test-secret-123';

  LicenseService build(
    _MemSettings settings, {
    _FakeEntitlement? source,
    _MemAnchorStorage? anchor,
  }) =>
      LicenseService(
        readSetting: settings.read,
        writeSetting: settings.write,
        entitlementSource:
            source ?? _FakeEntitlement(const EntitlementState(active: false, verifiedNow: false)),
        trialAnchor: TrialAnchor(
          secret: secret,
          storage: anchor ?? _MemAnchorStorage(),
        ),
      );

  tearDown(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  group('LicenseService', () {
    test('prima attivazione: prova locale di 14 giorni', () async {
      final service = build(_MemSettings());
      await service.initialize();

      expect(service.kind, LicenseKind.trial);
      expect(service.trialActive, isTrue);
      expect(service.trialDaysLeft, lessThanOrEqualTo(14));
      expect(service.trialDaysLeft, greaterThan(12));
      expect(service.canWrite, isTrue);
    });

    test('la prova non riparte se l\u2019ancora sopravvive al database',
        () async {
      // Reinstallazione simulata: database vuoto, ancora con la data
      // della prima installazione (20 giorni prima).
      final anchorStorage = _MemAnchorStorage();
      final oldStart = DateTime.now().subtract(const Duration(days: 20));
      await TrialAnchor(secret: secret, storage: anchorStorage, now: () => oldStart)
          .synchronize();

      final service = build(_MemSettings(), anchor: anchorStorage);
      await service.initialize();

      expect(service.trialStartedAt!.isAtSameMomentAs(oldStart), isTrue);
      expect(service.trialDaysLeft, 0);
      expect(service.trialActive, isFalse);
      expect(service.canWrite, isFalse);
      expect(service.chipLabel, 'Prova scaduta');
    });

    test('orologio indietro: stato esplicito, nessun danno', () async {
      final anchorStorage = _MemAnchorStorage();
      // Ancora scritta "dal futuro": l'orologio del telefono risulta
      // indietro di 3 giorni.
      final future = DateTime.now().add(const Duration(days: 3));
      await TrialAnchor(secret: secret, storage: anchorStorage, now: () => future)
          .synchronize();

      final service = build(_MemSettings(), anchor: anchorStorage);
      await service.initialize();

      expect(service.clockTampered, isTrue);
      expect(service.trialActive, isFalse);
      expect(service.canWrite, isFalse);
      expect(service.chipLabel, 'Orologio alterato');
      expect(service.clockTamperedMessage, contains('Orologio'));
    });

    test('abbonamento attivo verificato dallo store', () async {
      final settings = _MemSettings()
        ..map['license_kind'] = 'iap'
        ..map['iap_active'] = '1'
        ..map['iap_verified_at'] =
            DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final service = build(
        settings,
        source: _FakeEntitlement(
          EntitlementState(active: true, verifiedNow: true),
        ),
      );
      await service.initialize();

      expect(service.iapActive, isTrue);
      expect(service.kind, LicenseKind.iap);
      expect(service.canWrite, isTrue);
      expect(service.chipLabel, 'Abbonamento attivo');
      expect(settings.map['iap_active'], '1');
    });

    test('abbonamento revocato: iap_active = false', () async {
      final settings = _MemSettings()
        ..map['license_kind'] = 'iap'
        ..map['iap_active'] = '1'
        ..map['trial_started_at'] =
            DateTime.now().subtract(const Duration(days: 20)).toIso8601String()
        ..map['iap_verified_at'] =
            DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
      final service = build(
        settings,
        source: _FakeEntitlement(
          EntitlementState(active: false, verifiedNow: true),
        ),
      );
      await service.initialize();

      expect(service.iapActive, isFalse);
      expect(settings.map['iap_active'], '0');
      // Prova locale di riserva già consumata: sola lettura.
      expect(service.trialActive, isFalse);
      expect(service.canWrite, isFalse);
    });

    test('offline entro 7 giorni: tolleranza attiva', () async {
      final settings = _MemSettings()
        ..map['license_kind'] = 'iap'
        ..map['iap_active'] = '1'
        ..map['iap_verified_at'] =
            DateTime.now().subtract(const Duration(days: 3)).toIso8601String();
      final service = build(
        settings,
        source: _FakeEntitlement(
          const EntitlementState(active: false, verifiedNow: false),
        ),
      );
      await service.initialize();

      expect(service.iapActive, isTrue);
      expect(service.canWrite, isTrue);
    });

    test('offline oltre 7 giorni: torna a sola lettura', () async {
      final settings = _MemSettings()
        ..map['license_kind'] = 'iap'
        ..map['iap_active'] = '1'
        ..map['trial_started_at'] =
            DateTime.now().subtract(const Duration(days: 20)).toIso8601String()
        ..map['iap_verified_at'] =
            DateTime.now().subtract(const Duration(days: 8)).toIso8601String();
      final service = build(
        settings,
        source: _FakeEntitlement(
          const EntitlementState(active: false, verifiedNow: false),
        ),
      );
      await service.initialize();

      expect(service.iapActive, isFalse);
      expect(service.trialActive, isFalse);
      expect(service.canWrite, isFalse);
    });

    test('chiave offline valida vince sull\u2019abbonamento', () async {
      final settings = _MemSettings()
        ..map['license_kind'] = 'offline'
        ..map['license_expires_at'] =
            DateTime.now().add(const Duration(days: 300)).toIso8601String()
        ..map['iap_active'] = '1';
      final service = build(
        settings,
        source: _FakeEntitlement(
          EntitlementState(active: true, verifiedNow: true),
        ),
      );
      await service.initialize();

      expect(service.kind, LicenseKind.offline);
      expect(service.canWrite, isTrue);
      expect(service.chipLabel, startsWith('Licenza attiva'));
    });

    test('priorità: abbonamento sopra la prova locale scaduta', () async {
      final settings = _MemSettings()
        ..map['trial_started_at'] =
            DateTime.now().subtract(const Duration(days: 20)).toIso8601String()
        ..map['iap_active'] = '1';
      final service = build(
        settings,
        source: _FakeEntitlement(
          EntitlementState(active: true, verifiedNow: true),
        ),
      );
      await service.initialize();

      expect(service.kind, LicenseKind.iap);
      expect(service.canWrite, isTrue);
    });

    test('eventi ripetuti non spostano alcuna scadenza', () async {
      final service = build(_MemSettings());
      await service.initialize();
      final trialStart = service.trialStartedAt;

      // Lo stream riconsegna la transazione a ogni avvio: nessun
      // "oggi + 365" e la data della prova non cambia.
      await service.handlePurchasesForTest(
        [_purchase(PurchaseStatus.purchased)],
      );
      await service.handlePurchasesForTest(
        [_purchase(PurchaseStatus.restored)],
      );
      await service.handlePurchasesForTest(
        [_purchase(PurchaseStatus.restored)],
      );

      expect(service.iapActive, isTrue);
      expect(service.kind, LicenseKind.iap);
      expect(service.canWrite, isTrue);
      expect(service.expiresAt, isNull,
          reason: 'l\u2019abbonamento non deve avere scadenze calcolate');
      expect(service.trialStartedAt!.isAtSameMomentAs(trialStart!), isTrue);
    });

    test('acquisto di un prodotto sconosciuto non attiva nulla', () async {
      final service = build(_MemSettings());
      await service.initialize();

      await service.handlePurchasesForTest(
        [_purchase(PurchaseStatus.purchased, 'altro.prodotto')],
      );

      expect(service.iapActive, isFalse);
      expect(service.kind, LicenseKind.trial);
    });

    test('lifetime non è più un prodotto in-app', () {
      expect(LicenseProductIds.all.contains('it.bluescorpion.haccpass.lifetime'),
          isFalse);
    });

    test('debugReset azzera tutto e riavvia lo stato', () async {
      final oldStart = DateTime.now().subtract(const Duration(days: 10));
      final settings = _MemSettings()
        ..map['license_kind'] = 'iap'
        ..map['iap_active'] = '1'
        ..map['trial_started_at'] = oldStart.toIso8601String()
        ..map['license_expires_at'] =
            DateTime.now().add(const Duration(days: 100)).toIso8601String();
      final anchorStorage = _MemAnchorStorage();
      await TrialAnchor(
        secret: secret,
        storage: anchorStorage,
        now: () => oldStart,
      ).synchronize();
      final service = build(settings, anchor: anchorStorage);
      await service.initialize();
      expect(service.trialDaysLeft, 3, reason: '10 giorni su 14 consumati');

      await service.debugReset();

      // L'ancora viene cancellata e riscritta dal riavvio dello stato:
      // la data vecchia è scartata, la prova riparte da 14 giorni.
      expect(anchorStorage.value, isNotNull);
      expect(
        service.trialStartedAt!.isAfter(oldStart.add(const Duration(days: 9))),
        isTrue,
        reason: 'la data di prova deve essere azzerata',
      );
      expect(service.trialDaysLeft, greaterThan(12));
      expect(service.kind, LicenseKind.trial);
      expect(service.iapActive, isFalse);
      expect(service.trialActive, isTrue);
    });
  });
}
