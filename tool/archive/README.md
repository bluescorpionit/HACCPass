# Archivio: chiavi di licenza offline (Prompt 13)

Codice **storico** della vendita diretta con chiavi `BH1-…`, rimosso
dall'app di release: rinnovi, addebiti, rimborsi e prove gratuite sono
gestiti **solo da Google Play e App Store** (abbonamento
`it.bluescorpion.haccpass.annual`).

Contenuto:

- `license_codec.dart` — codifica/verifica delle chiavi `BH1-…`
  (HMAC-SHA256 sul payload `BH1|CODICE|DATA`);
- `license_keygen.dart` — generatore a riga di comando
  (`dart run tool/archive/license_keygen.dart --secret <SEGRETO> --customer COD --days 365`);
- `license_codec_test.dart` — test storici del codec (fuori dalla suite
  `flutter test`).

Nessuno di questi file è incluso nelle build (non sono in `lib/`) e
nessun riferimento a `LicenseCodec`/`BH1` resta nel codice compilato.

## Riattivarlo in futuro (eventuale vendita diretta)

1. Copiare `license_codec.dart` in `lib/core/license/` e il test in
   `test/`;
2. reintrodurre un tipo di licenza offline in `LicenseService`
   (rivalidando la chiave con HMAC a ogni caricamento, come faceva la
   versione pre-Prompt 13) e la sezione "chiave" nel paywall — su iOS
   resterebbe esclusa (guideline 3.1.1 di Apple);
3. usare il segreto di firma di allora: attenzione, `BH_LICENSE_SECRET`
   oggi è solo l'alias del segreto dell'ancora (`BH_ANCHOR_SECRET`,
   vedere `lib/core/license/app_integrity.dart`) e NON protegge
   nessuna licenza.
