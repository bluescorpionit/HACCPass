import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/license/license_codec.dart';

void main() {
  const secret = 'test-secret-123';

  group('LicenseCodec', () {
    test('genera e verifica una chiave annuale', () {
      final codec = LicenseCodec(secret: secret);
      final key = codec.generate(
        customerCode: 'BAR001',
        expiresAt: DateTime.now().add(const Duration(days: 365)),
      );

      expect(key.startsWith('BH1-BAR001-'), isTrue);

      final info = codec.tryParse(key);
      expect(info, isNotNull);
      expect(info!.customerCode, 'BAR001');
      expect(info.isValid, isTrue);
      expect(info.isLifetime, isFalse);
    });

    test('licenza a vita: 99991231', () {
      final codec = LicenseCodec(secret: secret);
      final key = codec.generateLifetime(customerCode: 'RISTO9');
      final info = codec.tryParse(key);

      expect(info, isNotNull);
      expect(info!.isLifetime, isTrue);
      expect(info.isValid, isTrue);
      expect(key, contains('-99991231-'));
    });

    test('chiave scaduta non valida', () {
      final codec = LicenseCodec(secret: secret);
      final key = codec.generate(
        customerCode: 'BAR001',
        expiresAt: DateTime.now().subtract(const Duration(days: 1)),
      );

      final info = codec.tryParse(key);
      expect(info, isNotNull);
      expect(info!.isValid, isFalse);
    });

    test('firma manomessa rifiutata', () {
      final codec = LicenseCodec(secret: secret);
      final key = codec.generate(
        customerCode: 'BAR001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      final tampered = key.substring(0, key.length - 1) +
          (key.endsWith('A') ? 'B' : 'A');

      expect(codec.tryParse(tampered), isNull);
    });

    test('segreto diverso rifiutato', () {
      final generator = LicenseCodec(secret: secret);
      final verifier = LicenseCodec(secret: 'altro-segreto');

      final key = generator.generate(
        customerCode: 'BAR001',
        expiresAt: DateTime.now().add(const Duration(days: 30)),
      );
      expect(verifier.tryParse(key), isNull);
    });

    test('formato errato rifiutato', () {
      final codec = LicenseCodec(secret: secret);
      expect(codec.tryParse('BH1-BAR001-20991231'), isNull);
      expect(codec.tryParse('BH1-'), isNull);
      expect(codec.tryParse('XXXX-BAR001-20991231-ABCDE'), isNull);
      expect(codec.tryParse('BH1-BAR001-20991399-ABCDE'), isNull);
    });

    test('codice cliente con caratteri non validi rifiutato', () {
      final codec = LicenseCodec(secret: secret);
      final signature = codec.sign('BAR 1', '20991231');
      expect(
        codec.tryParse('BH1-BAR 1-20991231-$signature'),
        isNull,
      );
    });
  });
}
