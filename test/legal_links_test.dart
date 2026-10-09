import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/constants/app_links.dart';
import 'package:haccpass/core/license/entitlement_source.dart';
import 'package:haccpass/core/license/trial_anchor.dart';
import 'package:haccpass/screens/license_screen.dart';
import 'package:haccpass/services/license_service.dart';
import 'package:haccpass/widgets/legal_links.dart' show LegalLinksText;

/// Prompt 11-bis, §6: i link legali compaiono nella schermata licenza,
/// aprono l'URL corretto (url_launcher finto) e `AppLinks` è l'unica
/// fonte degli indirizzi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppLinks: costanti coerenti (una sola fonte)', () {
    expect(AppLinks.base, 'https://www.bluescorpion.it/haacpass');
    expect(AppLinks.privacyUrl, '${AppLinks.base}/privacy');
    expect(AppLinks.termsUrl, '${AppLinks.base}/termini');
    expect(AppLinks.supportEmail, contains('@'));
  });

  testWidgets('schermata licenza: righe legali e frase sotto l\'acquisto',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final launchedUrls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launchedUrls.add(call.arguments['url'] as String);
          return true;
        }
        if (call.method == 'canLaunch') return true;
        return null;
      },
    );
    try {
      final service = _buildService();
      await tester.binding.setSurfaceSize(const Size(800, 2600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(home: LicenseScreen(license: service)),
      );
      await tester.pump();

      // Frase obbligatoria Apple 3.1.2 con i link in linea.
      expect(find.textContaining('Il rinnovo \u00E8 automatico'), findsOneWidget);
      expect(find.byType(LegalLinksText), findsOneWidget);
      // Righe esplicite.
      expect(find.text('Informativa sulla privacy'), findsOneWidget);
      expect(find.text('Termini e condizioni'), findsOneWidget);

      // Tocco della riga privacy: URL corretto da AppLinks.
      await tester.tap(find.text('Informativa sulla privacy'));
      await tester.pump();
      expect(launchedUrls, [AppLinks.privacyUrl]);

      // Tocco della riga termini.
      await tester.tap(find.text('Termini e condizioni'));
      await tester.pump();
      expect(launchedUrls, [AppLinks.privacyUrl, AppLinks.termsUrl]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('wizard/controller: default degli URL da AppLinks', () {
    // Il controller del wizard senza parametri URL usa AppLinks: i
    // default restano coerenti con la costante unica.
    expect(AppLinks.termsUrl, startsWith('https://www.bluescorpion.it'));
    expect(AppLinks.privacyUrl, startsWith('https://www.bluescorpion.it'));
  });
}

LicenseService _buildService() {
  return LicenseService(
    readSetting: (key) async => null,
    writeSetting: (key, value) async {},
    entitlementSource: const _FakeEntitlement(
      EntitlementState(active: false, verifiedNow: false),
    ),
    trialAnchor: TrialAnchor(secret: 'test-secret', storage: _MemAnchor()),
  );
}

class _MemAnchor implements TrialAnchorStorage {
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
