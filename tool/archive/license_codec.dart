/// Codifica e verifica delle chiavi di licenza offline.
///
/// Formato: `BH1-<CODICECLIENTE>-<AAAAMMGG>-<FIRMA>`
/// FIRMA = primi 5 byte (hex maiuscolo) di HMAC-SHA256 sul payload
/// `BH1|CODICE|DATA`, con il segreto fornito in build tramite
/// `--dart-define=BH_LICENSE_SECRET=...`.
///
/// File Dart puro, senza import Flutter, per essere riusato da
/// `tool/license_keygen.dart` e dai test.
library;

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

@immutable
class LicenseInfo {
  const LicenseInfo({
    required this.customerCode,
    required this.expiresAt,
    required this.signature,
  });

  final String customerCode;
  final DateTime expiresAt;

  /// Data 9999-12-31 = licenza a vita.
  final String signature;

  bool get isLifetime =>
      expiresAt.year >= 9999;

  bool get isValid => DateTime.now().isBefore(expiresAt);

  int get daysLeft => expiresAt.difference(DateTime.now()).inDays;
}

class LicenseCodec {
  LicenseCodec({required this.secret});

  /// Segreto HMAC (da --dart-define).
  final String secret;

  static const String prefix = 'BH1';
  static const String lifetimeDate = '99991231';

  String sign(String customerCode, String yyyymmdd) {
    final payload = '$prefix|$customerCode|$yyyymmdd';
    final digest = Hmac(sha256, secret.codeUnits).convert(payload.codeUnits);
    return digest.bytes
        .take(5)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  String generate({
    required String customerCode,
    required DateTime expiresAt,
  }) {
    final yyyymmdd = _formatDate(expiresAt);
    final signature = sign(customerCode, yyyymmdd);
    return '$prefix-$customerCode-$yyyymmdd-$signature';
  }

  String generateLifetime({required String customerCode}) =>
      generate(customerCode: customerCode, expiresAt: _lifetimeDate());

  LicenseInfo? tryParse(String raw) {
    final cleaned = raw.trim().toUpperCase();
    final parts = cleaned.split('-');
    if (parts.length != 4) return null;
    if (parts[0] != prefix) return null;

    final customerCode = parts[1];
    final datePart = parts[2];
    final signature = parts[3];
    if (customerCode.isEmpty || !RegExp(r'^[A-Z0-9]{3,12}$').hasMatch(customerCode)) {
      return null;
    }
    if (!RegExp(r'^\d{8}$').hasMatch(datePart)) return null;

    final expected = sign(customerCode, datePart);
    if (expected != signature) return null;

    final year = int.parse(datePart.substring(0, 4));
    final month = int.parse(datePart.substring(4, 6));
    final day = int.parse(datePart.substring(6, 8));
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    return LicenseInfo(
      customerCode: customerCode,
      expiresAt: DateTime(year, month, day, 23, 59, 59),
      signature: signature,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  DateTime _lifetimeDate() => DateTime(9999, 12, 31);
}
