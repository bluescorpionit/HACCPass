# Identificativi definitivi dell'app e firma di release (Prompt 9)

Identificativo unico: **`it.bluescorpion.haccpass`**. L'app non è ancora
publicata: dopo la pubblicazione l'identificativo non si può più cambiare.

## Tabella identificativi

| Piattaforma | Chiave | Valore |
|---|---|---|
| Android | `namespace` / `applicationId` | `it.bluescorpion.haccpass` |
| Android | Package `MainActivity` | `it.bluescorpion.haccpass` (`android/app/src/main/kotlin/it/bluescorpion/haccpass/`) |
| Android | Nome visualizzato (label) | `HACCPass` |
| iOS | `PRODUCT_BUNDLE_IDENTIFIER` | `it.bluescorpion.haccpass` (test: `it.bluescorpion.haccpass.RunnerTests`) |
| macOS | `PRODUCT_BUNDLE_IDENTIFIER` | `it.bluescorpion.haccpass` (test: `it.bluescorpion.haccpass.RunnerTests`) |
| macOS | Copyright | © 2026 Blue Scorpion. All rights reserved. |
| Windows | `CompanyName` / `LegalCopyright` | Blue Scorpion / Copyright (C) 2026 Blue Scorpion. All rights reserved. |
| Linux | `APPLICATION_ID` | `it.bluescorpion.haccpass` |
| Acquisti in-app | Annuale | `it.bluescorpion.haccpass.annual` (49 €/anno, offerta con prova gratuita 14 giorni — vedi `docs/acquisti.md`); **unico prodotto**: la licenza è solo store |
| Acquisti in-app | A vita / chiavi offline | **Rimossi dal Prompt 13**: nessuna chiave `BH1-…` nell'app di release (codice storico in `tool/archive/`); per regali e prove usare i codici promozionali degli store |
| QR attrezzature | Schema attuale | `haccpass://equipment/<id>` (generato nei PDF) |
| QR attrezzature | Schema storico | `bluehaccp://equipment/<id>` — **mantenuto valido** per i QR già stampati nei test (entrambi nel manifest Android e nel parser `lib/core/deep_links.dart`) |

### NON cambiare (compatibilità dati)

- Nome file database `blue_haccp.db` (commenti "nome storico" in
  `app_database.dart` e `backup_service.dart`): i dispositivi di prova e i
  backup esistenti puntano a questo file nella cartella privata dell'app.
- Id canale notifiche `blue_haccp_promemoria` (`reminder_service.dart`):
  cambiarlo creerebbe un secondo canale perdendo le impostazioni utente.

## Avvertenza: nuova app sui telefoni di prova

Cambiare l'`applicationId` crea di fatto una **nuova app** sui telefoni di
prova: la vecchia (`com.example.blue_haccp`) va **disinstallata** e i dati
di prova NON si migrano (il database vive nella cartella privata
dell'app). Nessun utente reale è coinvolto perché l'app non è ancora
distribuita. Chi vuole conservare i dati di prova può prima fare un
backup completo e ripristinarlo sulla nuova installazione.

## Firma di release Android

La build di release legge `android/key.properties` (NON versionato, è nel
`.gitignore` insieme a `*.jks`/`*.keystore`):

```properties
storeFile=percorso/assoluto/o/relativo/della/keystore.jks
storePassword=...
keyAlias=...
keyPassword=...
```

**Senza `key.properties` la build di release fallisce con messaggio
chiaro** (mai ripiego sulla chiave di debug).

### Creare la keystore di upload

```
keytool -genkeypair -v ^
  -keystore haccpass-upload.jks ^
  -alias haccpass-upload ^
  -keyalg RSA -keysize 2048 -validity 10000
```

(linux/macOS: usare `\` a capo riga invece di `^`). **AVVERTENZA**: la
keystore di upload va conservata al sicuro e **copiata in più luoghi**
(drive cifrato, gestore password con allegati): senza di essa NON si
possono aggiornare le app non gestite da Play App Signing. Se si attiva
Play App Signing (consigliato), Google conserva la chiave di firma finale
e la keystore di upload serve per gli aggiornamenti futuri.

### Impronte SHA-1 / SHA-256

```
keytool -list -v -keystore haccpass-upload.jks -alias haccpass-upload
```

oppure, per tutte le configurazioni di build:

```
cd android && gradlew signingReport
```

## Valori da inserire su Google Cloud e negli store

Google Cloud Console → credenziali OAuth 2.0 (richieste da Google Sign-In
per il backup su Drive), UNA VOCE PER CHIAVE con il package
`it.bluescorpion.haccpass`:

1. **SHA-1 della chiave di debug** (sviluppo: `gradlew signingReport`,
   configurazione debug);
2. **SHA-1 della chiave di upload** (da `keytool` sulla keystore di
   upload);
3. **SHA-1 di Play App Signing** (dalla scheda Firma dell'app in Play
   Console, dopo il primo caricamento) — per gli OAuth client delle build
   distribuite.

### `GOOGLE_SERVER_CLIENT_ID` (obbligatorio su Android)

Per collegare Google Drive con `google_sign_in` su Android, la build deve
ricevere anche il **Web OAuth client ID** come `dart-define`:

```
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-oauth-client-id>
```

e per release:

```
flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=<web-oauth-client-id>
```

Se il valore manca, il collegamento Drive fallisce con errore di
configurazione (`serverClientId must be provided on Android`).

Da registrare poi:

- **Play Console**: applicazione con package `it.bluescorpion.haccpass`;
  abbonamento `it.bluescorpion.haccpass.annual` con offerta di prova
  gratuita 14 giorni (procedura in `docs/acquisti.md`), prezzi e tasse;
- **App Store Connect**: app con Bundle ID `it.bluescorpion.haccpass`
  (registrare l'id su developer.apple.com) e acquisti in-app con gli
  stessi id prodotto.

## Segreto dell'ancora della prova (BH_ANCHOR_SECRET)

Dal Prompt 13 le chiavi di licenza offline `BH1-…` **non esistono più**
nell'app (codice storico in `tool/archive/`). Il segreto serve SOLO per
il MAC dell'ancora della prova (`lib/core/license/app_integrity.dart`,
usato da `TrialAnchor`):

- **AVVERTENZA**: il valore è una protezione LEGGERA contro la
  modifica casuale dell'ancora. Sta nel binario, non è un segreto
  forte e **non protegge nessuna licenza**: la licenza dipende solo
  dallo store (abbonamento `it.bluescorpion.haccpass.annual`).
- Build di **release** con il valore vuoto: l'app **si rifiuta di
  avviarsi** con errore esplicito (`AppIntegrity.assertConfigured`).
- In **debug** resta consentito, con avviso in console.
- **Alias di compatibilità**: se `BH_ANCHOR_SECRET` è vuoto viene usato
  il vecchio `BH_LICENSE_SECRET` (le configurazioni esistenti —
  `.vscode`, script — continuano a funzionare; meglio rinominarlo).

```
flutter build apk --release --dart-define=BH_ANCHOR_SECRET=<valore>
```

### AVVERTENZA: `dev-secret` in `.vscode/launch.json` e `settings.json`

Le configurazioni VS Code usano un segreto **di solo sviluppo**
(`dev-secret`, passato come `BH_LICENSE_SECRET` e quindi accettato via
alias) per comodità di `flutter run`. Quel valore è noto (sta nel
repository): **NON va mai usato per build distribuite** — né TestFlight
né Play né APK/IPA consegnati a clienti. Ogni build distribuita usa il
segreto reale passato come variabile d'ambiente tramite
`tool/build_release.bat` / `tool/build_release.sh` (vedi sotto).

### Script di build di release

`tool/build_release.bat` (Windows) e `tool/build_release.sh`
(Linux/macOS) richiedono come **variabili d'ambiente**
`BH_ANCHOR_SECRET` (accettato anche l'alias `BH_LICENSE_SECRET`) e
`GOOGLE_SERVER_CLIENT_ID`, falliscono con messaggio chiaro se mancano
(o se manca `android/key.properties`) e lanciano
`flutter build appbundle --release --dart-define=...`. Nessun segreto
è scritto negli script né nel repository.

### Fine del flusso di generazione chiavi

`tool/license_keygen.dart` e `LicenseCodec` sono archiviati in
`tool/archive/` (con `README.md` che spiega la riattivazione): non
compaiono più nelle build né nella suite di test. I codici promozionali
degli store sostituiscono le chiavi per regali e prove ai clienti (vedi
`docs/acquisti.md`).
