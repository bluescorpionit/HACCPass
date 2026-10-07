import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/services/cloud/drive_auth_gateway.dart';
import 'package:haccpass/services/cloud/google_drive_provider.dart';

/// Gateway finto: registra quali metodi (silenziosi o interattivi)
/// vengono usati, senza il plugin Google Sign-In.
class _FakeGateway implements DriveAuthGateway {
  int initializeCalls = 0;
  int restoreCalls = 0;
  int interactiveCalls = 0;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  Future<DriveSession?> tryRestoreSession() async {
    restoreCalls++;
    return null; // mai riuscito: nessun client API da costruire
  }

  @override
  Future<DriveSession?> interactiveSession() async {
    interactiveCalls++;
    return null;
  }

  @override
  Future<void> disconnect() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoogleDriveProvider.connect non interattivo', () {
    // ATTENZIONE all'ordine: _initialized è statico per esecuzione, quindi
    // questo test deve essere il PRIMO a chiamare connect().
    test('initialize() viene chiamato una sola volta per esecuzione',
        () async {
      final first = _FakeGateway();
      await GoogleDriveProvider(gateway: first).connect(interactive: false);
      expect(first.initializeCalls, 1);

      // Secondo provider (es. nuovo tentativo): il flag statico salta
      // la seconda initialize(), che GoogleSignIn rifiuterebbe.
      final second = _FakeGateway();
      await GoogleDriveProvider(gateway: second).connect(interactive: false);
      expect(second.initializeCalls, 0,
          reason: 'gi\u00E0 inizializzato in questa esecuzione');
    });

    test('interactive: false NON chiama mai i metodi interattivi', () async {
      final gateway = _FakeGateway();
      final provider = GoogleDriveProvider(gateway: gateway);

      final connected = await provider.connect(interactive: false);

      expect(connected, isFalse);
      expect(gateway.restoreCalls, 1,
          reason: 'il tentativo silenzioso viene fatto');
      expect(gateway.interactiveCalls, 0,
          reason: 'nessuna finestra di Google all\u2019avvio');
    });

    test('interactive: true può usare i metodi interattivi', () async {
      final gateway = _FakeGateway();
      final provider = GoogleDriveProvider(gateway: gateway);

      final connected = await provider.connect(interactive: true);

      expect(connected, isFalse);
      expect(gateway.restoreCalls, 1);
      expect(gateway.interactiveCalls, 1);
    });
  });
}
