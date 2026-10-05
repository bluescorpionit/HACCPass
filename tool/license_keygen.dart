// Generatore di chiavi di licenza offline per Blue HACCP.
//
// Uso:
//   dart run tool/license_keygen.dart --secret <SEGRETO> --customer BAR001 --days 365
//   dart run tool/license_keygen.dart --secret <SEGRETO> --customer BAR001 --lifetime
//
// Il segreto deve coincidere con quello usato in build:
//   flutter build apk --dart-define=BH_LICENSE_SECRET=<SEGRETO>
import 'dart:io';

import 'package:blue_haccp/core/license/license_codec.dart';

void main(List<String> args) {
  String? secret;
  String? customer;
  int? days;
  var lifetime = false;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--secret':
        secret = ++i < args.length ? args[i] : null;
      case '--customer':
        customer = ++i < args.length ? args[i] : null;
      case '--days':
        final v = ++i < args.length ? int.tryParse(args[i]) : null;
        days = v;
      case '--lifetime':
        lifetime = true;
    }
  }

  if (secret == null || secret.isEmpty || customer == null || customer.isEmpty) {
    stderr.writeln(
      'Uso: dart run tool/license_keygen.dart --secret <SEGRETO> '
      '--customer <CODICE> [--days N | --lifetime]',
    );
    exitCode = 1;
    return;
  }

  final codec = LicenseCodec(secret: secret);
  final code = lifetime
      ? codec.generateLifetime(customerCode: customer.toUpperCase())
      : codec.generate(
          customerCode: customer.toUpperCase(),
          expiresAt: DateTime.now().add(Duration(days: days ?? 365)),
        );

  final info = codec.tryParse(code);
  stdout.writeln('Chiave: $code');
  if (info != null) {
    stdout.writeln(
      lifetime
          ? 'Tipo: licenza a vita (codice cliente ${info.customerCode})'
          : 'Scadenza: ${info.expiresAt.year}-${info.expiresAt.month.toString().padLeft(2, '0')}-${info.expiresAt.day.toString().padLeft(2, '0')}',
    );
  }
}
