import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/license/entitlement_source.dart';
import 'package:haccpass/core/license/trial_anchor.dart';
import 'package:haccpass/screens/license_screen.dart';
import 'package:haccpass/services/license_service.dart';

/// Prompt 13: la schermata licenza è store-only. Nessuna sezione chiave
/// offline, "Riprova" quando lo store non c'è, "Gestisci abbonamento"
/// con l'abbonamento, "Hai un codice?" solo su iOS.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secret = 'test-secret-123';

  LicenseService buildService() {
    return LicenseService(
      readSetting: (key) async => null,
      writeSetting: (key, value) async {},
      entitlementSource: _FakeEntitlement(
        const EntitlementState(active: false, verifiedNow: false),
      ),
      trialAnchor: TrialAnchor(secret: secret, storage: _MemAnchorStorage()),
    );
  }

  Future<void> pumpScreen(WidgetTester tester, LicenseService service) async {
    // Schermo alto: il ListView della schermata è lazy e i pulsanti
    // sotto la piega non verrebbero proprio costruiti.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: LicenseScreen(license: service)),
    );
    await tester.pump();
  }

  testWidgets('nessuna sezione chiave di licenza offline', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = buildService();
      // Stato: prova scaduta, store non disponibile.
      service.iapAvailable = false;
      await pumpScreen(tester, service);

      expect(find.textContaining('Chiave di licenza'), findsNothing);
      expect(find.textContaining('BH1'), findsNothing);
      expect(find.textContaining('Attiva chiave'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('store non disponibile: testo nuovo e pulsante Riprova',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = buildService();
      service.iapAvailable = false;
      await pumpScreen(tester, service);

      expect(
        find.textContaining('Controlla la connessione e che sul telefono'),
        findsOneWidget,
      );
      expect(find.text('Riprova'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop: la licenza si acquista da telefono', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final service = buildService();
      service.iapAvailable = false;
      await pumpScreen(tester, service);

      expect(
        find.textContaining(
            'La licenza si acquista dall\u2019app per Android o iPhone'),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('con abbonamento: Gestisci abbonamento e stato attivo',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = buildService();
      service.iapAvailable = true;
      service.iapActive = true;
      service.iapVerifiedNow = true;
      service.kind = LicenseKind.iap;
      await pumpScreen(tester, service);

      expect(find.text('Gestisci abbonamento'), findsOneWidget);
      expect(find.text('Abbonamento attivo'), findsOneWidget);
      expect(find.textContaining('Licenza gi\u00E0 attiva'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iOS: compare "Hai un codice?" (riscatto Apple)', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final service = buildService();
      service.iapAvailable = true;
      await pumpScreen(tester, service);

      expect(find.text('Hai un codice?'), findsOneWidget);
      expect(find.text('Ripristina acquisti'), findsOneWidget);
      // Su iOS niente riga dei codici Play.
      expect(find.textContaining('Play Store'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android: i codici si riscattano dal Play Store', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final service = buildService();
      service.iapAvailable = true;
      await pumpScreen(tester, service);

      expect(find.textContaining('Play Store'), findsOneWidget);
      expect(find.text('Hai un codice?'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
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
  const _FakeEntitlement(this.state);

  final EntitlementState state;

  @override
  Future<EntitlementState> current() async => state;
}
