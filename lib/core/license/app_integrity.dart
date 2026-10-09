/// Segreto di integrità dell'ancora della prova (Prompt 13).
///
/// Le chiavi di licenza offline sono state rimosse dall'app: il
/// rinnovo, gli addebiti, i rimborsi e la prova gratuita sono gestiti
/// solo da Google Play e App Store. Questo valore NON protegge nessuna
/// licenza: serve esclusivamente per il MAC dell'ancora della prova
/// (`TrialAnchor`, `lib/core/license/trial_anchor.dart`).
///
/// AVVERTENZA: è una protezione LEGGERA contro la modifica casuale
/// dell'ancora (es. restore di file editati a mano). Il valore sta nel
/// binario, quindi non è un segreto forte, e una modifica mirata può
/// comunque ricalcolarlo. La licenza dipende SOLO dallo store.
///
/// Nome in build: `--dart-define=BH_ANCHOR_SECRET=<valore>`. Per
/// compatibilità con le configurazioni esistenti (`.vscode`, script) è
/// accettato come alias il vecchio `BH_LICENSE_SECRET`: se
/// `BH_ANCHOR_SECRET` è vuoto viene usato quello.
///
/// In release un valore vuoto fa fallire l'avvio con messaggio esplicito
/// (controllo in `LicenseService`); in debug è consentito con avviso.
library;

import 'package:flutter/foundation.dart';

class AppIntegrity {
  AppIntegrity._();

  static const String _anchorSecret =
      String.fromEnvironment('BH_ANCHOR_SECRET');

  /// Alias storico (era il segreto delle chiavi offline).
  static const String _legacySecret =
      String.fromEnvironment('BH_LICENSE_SECRET');

  /// Segreto per il MAC dell'ancora della prova.
  static const String anchorSecret =
      _anchorSecret.length > 0 ? _anchorSecret : _legacySecret;

  /// true quando il valore arriva dall'alias storico `BH_LICENSE_SECRET`
  /// (utile per l'avviso in console: il nome è deprecato).
  static const bool usingLegacySecretAlias =
      _anchorSecret.length == 0 && _legacySecret.length > 0;

  /// Verifica di boot: in release il segreto è obbligatorio, in debug
  /// manca solo un avviso.
  static void assertConfigured() {
    if (kReleaseMode && anchorSecret.isEmpty) {
      throw StateError(
        'BH_ANCHOR_SECRET mancante: build di release senza segreto di '
        'integrit\u00E0 dell\u2019ancora della prova. Ricompila con '
        '--dart-define=BH_ANCHOR_SECRET=<valore> (viene accettato anche '
        'il vecchio BH_LICENSE_SECRET come alias; vedi '
        'docs/identificativi.md).',
      );
    }
    assert(() {
      if (anchorSecret.isEmpty) {
        debugPrint(
          'AVVISO: BH_ANCHOR_SECRET vuoto (consentito solo in debug): '
          'l\u2019ancora della prova NON \u00E8 protetta da modifiche.',
        );
      } else if (usingLegacySecretAlias) {
        debugPrint(
          'AVVISO: usato l\u2019alias storico BH_LICENSE_SECRET come segreto '
          'dell\u2019ancora. Rinominarlo in BH_ANCHOR_SECRET nelle '
          'configurazioni di build.',
        );
      }
      return true;
    }());
  }
}
