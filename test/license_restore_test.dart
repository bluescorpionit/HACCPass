import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/license/entitlement_source.dart';
import 'package:haccpass/core/license/trial_anchor.dart';
import 'package:haccpass/services/license_service.dart';

/// Prompt 13, §1.1 (compatibilità dati) + Prompt 12, C.2: le righe di
/// licenza storiche del database NON concedono più nulla (le chiavi
/// offline sono state rimosse): `license_kind = 'offline'` viene trattato
/// come prova e le chiavi legacy vengono ripulite al primo avvio.
/// `iap_verified_at` nel futuro o oltre la tolleranza viene ignorato.
void main() {
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  TestWidgetsFlutterBinding.ensureInitialized();

  const secret = 'test-secret-123';

  tearDown(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  });

  LicenseService build(
    Map<String, String> settings, {
    EntitlementState Function()? entitlement,
    TrialAnchorStorage? anchor,
  }) {
    final entitlements = entitlement ??
        () => const EntitlementState(active: false, verifiedNow: false);
    final storage = anchor ?? _MemAnchorStorage();
    return LicenseService(
      readSetting: (key) async =>
          settings[key] == null || settings[key]!.isEmpty
              ? null
              : settings[key],
      writeSetting: (key, value) async => settings[key] = value,
      entitlementSource: _FakeEntitlement(entitlements),
      trialAnchor: TrialAnchor(secret: secret, storage: storage),
    );
  }

  group('license_kind = offline ereditato (Prompt 13)', () {
    test('righe offline manomesse: mai concesso nulla, stato prova',
        () async {
      final settings = {
        'license_kind': 'offline',
        'license_key': 'BH1-CLIENTE9-20310630-DEADBEEF01',
        // RIGHE MANOMETTUTE: devono essere ignorate.
        'license_expires_at': '9999-12-31T00:00:00.000',
        'license_customer': 'TRUFFATORE',
      };
      final service = build(settings);
      await service.initialize();

      expect(service.kind, LicenseKind.trial,
          reason: 'nessuna licenza offline esiste più');
      // La prova è appena iniziata (nessuna data precedente): si può
      // scrivere, MA per la prova, non per la licenza manomessa.
      expect(service.canWrite, isTrue);
      expect(service.trialActive, isTrue);
    });

    test('righe offline ripulite al primo avvio (migrazione silenziosa)',
        () async {
      final settings = {
        'license_kind': 'offline',
        'license_key': 'BH1-CLIENTE9-20310630-DEADBEEF01',
        'license_expires_at': '9999-12-31T00:00:00.000',
        'license_customer': 'TRUFFATORE',
      };
      final service = build(settings);
      await service.initialize();

      expect(settings['license_key'], '',
          reason: 'la chiave legacy viene pulita');
      expect(settings['license_expires_at'], '',
          reason: 'la scadenza legacy viene pulita');
      expect(settings['license_customer'], '',
          reason: 'il cliente legacy viene pulito');
      expect(settings['license_kind'], isNot('offline'),
          reason: 'il kind risolto viene riscritto');
    });

    test('abbonamento attivo vince sulle righe offline residue', () async {
      final settings = {
        'license_kind': 'offline',
        'license_key': 'BH1-CLIENTE9-20310630-DEADBEEF01',
        'license_expires_at': '9999-12-31T00:00:00.000',
        'iap_active': '1',
        'iap_verified_at': DateTime.now().toIso8601String(),
      };
      final service = build(
        settings,
        entitlement: () =>
            const EntitlementState(active: true, verifiedNow: true),
      );
      await service.initialize();

      expect(service.kind, LicenseKind.iap);
      expect(service.canWrite, isTrue);
      expect(settings['license_key'], '');
    });
  });

  group('iap_verified_at non è creduto se alterato', () {
    test('iap_verified_at nel futuro: ignorato, serve lo store', () async {
      final service = build({
        'iap_active': '1',
        'iap_verified_at':
            DateTime.now().add(const Duration(days: 365)).toIso8601String(),
      });
      await service.initialize();

      // Il futuro non è creduto e lo store (fake) non conferma: nessuna
      // tolleranza offline "infinita" regalata dalla riga manomessa.
      expect(service.iapVerifiedAt, isNull,
          reason: 'iap_verified_at nel futuro scartato al caricamento');
      expect(service.iapActive, isFalse);
      expect(service.kind, isNot(LicenseKind.iap),
          reason: 'lo stato abbonamento dipende solo dallo store');
    });

    test('iap_verified_at oltre la tolleranza di 7 giorni: ignorato',
        () async {
      final service = build({
        'iap_active': '1',
        'iap_verified_at': DateTime.now()
            .subtract(const Duration(days: 30))
            .toIso8601String(),
      });
      await service.initialize();

      expect(service.iapVerifiedAt, isNull);
      expect(service.iapActive, isFalse);
    });

    test('iap_verified_at recente e offline: tolleranza di 7 giorni rispettata',
        () async {
      // Store non raggiungibile (eccezione): vale l'ultima verifica
      // recente entro la tolleranza.
      final service = build(
        {
          'iap_active': '1',
          'iap_verified_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
        entitlement: () => throw const SocketExceptionFake(),
      );
      await service.initialize();

      expect(service.iapActive, isTrue,
          reason: 'entro 7 giorni dalla verifica si resta attivi offline');
      expect(service.canWrite, isTrue);
    });
  });
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
  _FakeEntitlement(this.provider);

  final EntitlementState Function() provider;

  @override
  Future<EntitlementState> current() async => provider();
}

/// Eccezione di rete finta (il tipo reale non è const-costruibile).
class SocketExceptionFake implements SocketException {
  const SocketExceptionFake();

  @override
  String get message => 'rete assente';

  @override
  OSError? get osError => null;

  @override
  InternetAddress? get address => null;

  @override
  int? get port => null;
}
