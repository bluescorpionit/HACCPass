# PROMPT 9 — Identificativo definitivo dell'app (`it.bluescorpion.haccpass`) e firma di release — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Obiettivo: sostituire l'identificativo provvisorio `com.example.blue_haccp` con quello definitivo **`it.bluescorpion.haccpass`**, allineare i prodotti di acquisto in-app e preparare la firma di release. L'app non è ancora pubblicata: è il momento giusto, perché dopo la pubblicazione l'identificativo non si può più cambiare. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## Occorrenze trovate nel progetto (cerca comunque con grep anche dopo)
- Android: `android/app/build.gradle.kts` (`namespace` riga ~8 e `applicationId` riga ~21 = `com.example.blue_haccp`); `android/app/src/main/kotlin/com/example/blue_haccp/MainActivity.kt` (package).
- iOS: `ios/Runner.xcodeproj/project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER = com.example.blueHaccp`, più `.RunnerTests`).
- macOS: `macos/Runner/Configs/AppInfo.xcconfig` (identificativo e copyright), `macos/Runner.xcodeproj/project.pbxproj` (`.RunnerTests`).
- Linux: `linux/CMakeLists.txt` (`APPLICATION_ID`).
- Windows: `windows/runner/Runner.rc` (`CompanyName`, `LegalCopyright` con "com.example").
- Acquisti in-app: `lib/services/license_service.dart` (`LicenseProductIds.annual = 'dev.bluehaccp.app.annual'`, `lifetime = 'dev.bluehaccp.app.lifetime'`).
- Collegamento profondo (QR delle attrezzature): schema `bluehaccp` in `AndroidManifest.xml` (~riga 51) e `lib/services/pdf_service.dart` (~riga 1651, `bluehaccp://equipment/<id>`).

## Modifiche richieste
1. **Android:** `namespace = "it.bluescorpion.haccpass"` e `applicationId = "it.bluescorpion.haccpass"`. Sposta `MainActivity.kt` in `android/app/src/main/kotlin/it/bluescorpion/haccpass/` con `package it.bluescorpion.haccpass`, elimina la vecchia cartella `com/example/blue_haccp` vuota. Controlla il manifest (nessun riferimento al vecchio package, label "HACCPass" già presente) e i file di debug/profile.
2. **iOS e macOS:** bundle identifier `it.bluescorpion.haccpass` (target di test: `it.bluescorpion.haccpass.RunnerTests`). Nome visualizzato "HACCPass". Copyright: "© 2026 Blue Scorpion".
3. **Linux/Windows:** `APPLICATION_ID = "it.bluescorpion.haccpass"`; in `Runner.rc` `CompanyName` = "Blue Scorpion" e `LegalCopyright` = "Copyright (C) 2026 Blue Scorpion. All rights reserved.".
4. **Acquisti in-app:** nuovi identificativi `it.bluescorpion.haccpass.annual` e `it.bluescorpion.haccpass.lifetime` (se l'offerta a vita non è più prevista dal modello a 39 €/anno, lascia solo l'annuale e documentalo). Aggiorna `LicenseProductIds`, test e README. Nessun riferimento ai vecchi ID resta nel codice.
5. **Collegamento profondo (QR attrezzature):** aggiungi il nuovo schema `haccpass://equipment/<id>` e **mantieni valido** `bluehaccp://` nel manifest/gestore (eventuali QR già stampati nei test continuano a funzionare). I nuovi PDF generano `haccpass://`. Test sul parser dei link per entrambi gli schemi.
6. **Da NON cambiare** (compatibilità dati): nome del file del database `blue_haccp.db` (e il suo uso in `app_database.dart`, `backup_service.dart` e test), id del canale notifiche `blue_haccp_promemoria`. Scrivi in un commento il motivo ("nome storico, non cambiare").
7. **Firma di release Android:** configura `signingConfigs.release` in `build.gradle.kts` leggendo `android/key.properties` (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`); se il file non esiste la build di release deve fallire con messaggio chiaro (non ripiegare sulla chiave di debug). Aggiungi `android/key.properties`, `*.jks`, `*.keystore` al `.gitignore`. Nessun segreto nel repository.
8. **Build di release e segreto di licenza:** se `BH_LICENSE_SECRET` è vuoto in una build di release, la compilazione/avvio deve fallire in modo esplicito (un segreto vuoto renderebbe forgiabili le chiavi). In debug resta consentito vuoto con avviso.
9. **Documentazione** `docs/identificativi.md`: tabella identificativi (Android, iOS, macOS, Windows, Linux, acquisti, schemi URL), come ottenere le impronte **SHA-1/SHA-256** (`keytool -list -v -keystore <file> -alias <alias>` oppure `gradlew signingReport`), come creare la keystore di upload (comando `keytool -genkeypair ...` con avvertenza di conservarla e copiarla al sicuro in più luoghi: senza di essa non si possono aggiornare le app non gestite da Play App Signing), e l'elenco dei valori da inserire poi su Google Cloud (package name + SHA-1 di debug, upload e Play App Signing) e negli store. Aggiorna il README (sezione "Configurazione manuale").

## Verifiche
- `flutter clean`, `flutter pub get`, `flutter analyze`, `flutter test` verdi.
- `flutter build apk --debug` riuscita; `flutter build apk --release --dart-define=BH_LICENSE_SECRET=test` riuscita solo con `key.properties` presente, fallisce chiaramente senza.
- `grep -rIn "com.example\|bluehaccp\|dev.bluehaccp" android ios macos linux windows lib test pubspec.yaml` non trova più occorrenze, tranne lo schema `bluehaccp://` mantenuto per compatibilità, il nome DB e l'id del canale notifiche, tutti commentati.
- Nota in `docs/identificativi.md`: cambiare l'`applicationId` crea di fatto una **nuova app** sui telefoni di prova: va disinstallata la vecchia e i dati di prova non si migrano (database in cartella privata dell'app). Nessun utente reale è coinvolto perché l'app non è ancora distribuita.

## Criteri di accettazione
1. Un solo identificativo, `it.bluescorpion.haccpass`, su tutte le piattaforme; nessun `com.example` residuo.
2. ID acquisti allineati e documentati; schema QR doppio funzionante.
3. Release firmata con la chiave di upload tramite `key.properties` non versionato; build di release senza segreto di licenza rifiutata.
4. `docs/identificativi.md` completo (impronte SHA-1, keystore, valori per Google Cloud e store).
