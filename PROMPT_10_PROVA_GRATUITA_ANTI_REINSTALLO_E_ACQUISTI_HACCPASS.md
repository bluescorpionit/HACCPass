# PROMPT 10 — Prova gratuita che non riparte alla reinstallazione, acquisti verificati, Drive all'avvio — HACCPass

Progetto: `D:\DEV\App\HACCPass` (package `it.bluescorpion.haccpass`). Prima di modificare leggi lo stato attuale del codice: `lib/services/license_service.dart`, `lib/core/license/license_codec.dart`, `lib/screens/license_screen.dart`, `lib/services/cloud/google_drive_provider.dart`, `lib/main.dart` (`_restoreCloudSession`), `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist`. Dopo ogni gruppo di modifiche esegui `flutter analyze` e `flutter test`. Non committare segreti.

## Problemi da risolvere (verificati nel codice)

1. **La prova da 14 giorni riparte dopo disinstallazione/reinstallazione.** `LicenseService._loadState` legge `trial_started_at` dalla tabella impostazioni del database locale; Android cancella il database con l'app, quindi alla reinstallazione la data viene rigenerata (`DateTime.now()`).
2. **L'acquisto annuale si "rinnova" da solo.** `_activateIap` imposta `expiresAt = now + 365 giorni` a ogni evento `purchased/restored`: lo stream degli acquisti riconsegna le transazioni a ogni avvio, quindi la scadenza slitta ogni volta e non si perde mai l'accesso, anche dopo una disdetta. Inoltre `buyOrRestore` ha due rami identici.
3. **Il collegamento Drive all'avvio può aprire finestre Google.** `main.dart::_restoreCloudSession` chiama `GoogleDriveProvider.connect()`, che se l'accesso silenzioso fallisce passa a `authenticate()` e `authorizeScopes()` (interattivi). Con la schermata di consenso in "Test" il token scade dopo circa 7 giorni: il cliente vedrebbe il selettore account appena apre l'app.
4. **`GoogleSignIn.initialize()` viene richiamato a ogni `connect()`**; va chiamato una sola volta.
5. **Igiene del repository:** sono tracciati in git file che non devono starci (`_backup_pre_redesign_*.tar.gz`, `pubspec-1.yaml`, `android/app/google-services.json`).

## Modello deciso

- **Prova gratuita primaria: gestita dallo store.** L'abbonamento annuale `it.bluescorpion.haccpass.annual` (39 €/anno) ha un'offerta con **14 giorni gratuiti** su Google Play e App Store. Gli store ricordano a quale account è già stata concessa la prova: reinstallare non la rigenera.
- **Prova locale di riserva (senza store):** resta per i dispositivi dove lo store non è disponibile (build di test, installazioni fuori dallo store) e per il periodo precedente alla pubblicazione, ma deve resistere alla reinstallazione (vedi punto A) e all'alterazione dell'orologio.
- **L'acquisto a vita non è più offerto in-app.** Resta solo la chiave offline `BH1-…` (vendita diretta, nascosta su iOS). Rimuovi `LicenseProductIds.lifetime` e ogni suo uso, oppure lascialo solo se serve a test esistenti, documentandolo. L'unico prodotto in-app è `annual`.

## A. Ancora della prova che sopravvive alla reinstallazione

Crea `lib/core/license/trial_anchor.dart` (classe `TrialAnchor`, testabile con un'interfaccia di storage iniettabile):

- **iOS:** salva la data di primo avvio nella **Keychain** con `flutter_secure_storage` (`IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device)`; non usare `synchronizable`). La Keychain di norma sopravvive alla disinstallazione.
- **Android:** la Keystore viene cancellata con l'app, quindi non usarla. Salva `trial_anchor.json` in una cartella interna dell'app (es. `getApplicationSupportDirectory()/anchor/trial_anchor.json`) e includila nel **backup automatico di Android**: nel manifest imposta `android:allowBackup="true"`, `android:fullBackupContent` (o `android:dataExtractionRules` per Android 12+) con regole `<include>` solo per quel file e `<exclude>` per database, allegati e cache (niente ripristino parziale del database). Documenta che funziona solo se l'utente ha il backup Google attivo.
- **Contenuto firmato:** `{"v":1,"start":"<ISO UTC>","lastSeen":"<ISO UTC>","mac":"<HMAC-SHA256 base64>"}` con HMAC calcolato con lo stesso segreto della licenza (`LicenseService.appSecret`, in debug anche vuoto). Un file con MAC non valido è trattato come assente e registrato come "alterato".
- **Data di inizio effettiva = la più antica** tra database (`trial_started_at`), ancora piattaforma e (Android) file ripristinato. Alla lettura riallinea gli altri supporti alla data più antica; non spostare mai la data in avanti.
- **Orologio:** aggiorna `lastSeen = max(lastSeen, now)` a ogni avvio e a ogni ripresa dell'app. Se `now < lastSeen - 24 h` la prova è considerata **scaduta** con stato esplicito "Orologio del dispositivo alterato: verifica data e ora" (nessun crash, nessun dato cancellato; resta lettura/export).
- **Test unitari** (storage finto): prima installazione, riapertura, supporto database cancellato ma ancora presente (reinstallazione simulata), file con MAC alterato, orologio indietro di 3 giorni, data più antica che vince, date oltre il 14° giorno.

Integra `TrialAnchor` in `LicenseService._loadState` al posto della semplice lettura/scrittura di `trial_started_at` (il database resta una copia). Mantieni `trialDays = 14`.

## B. Acquisti: prova gestita dallo store e scadenza reale

1. **Offerta con prova gratuita.** Documenta in `docs/acquisti.md` come creare l'abbonamento annuale con piano base e offerta "prova gratuita 14 giorni" su Play Console e l'equivalente "offerta introduttiva: prova gratuita 14 giorni" su App Store Connect (prezzo 39 €/anno), con ID `it.bluescorpion.haccpass.annual`.
2. **Android:** nella schermata licenza leggi dalle `GooglePlayProductDetails` le offerte (`subscriptionOfferDetails`), scegli quella con fase gratuita se presente e acquista con `GooglePlayPurchaseParam(offerToken: …)`. Mostra il testo reale dallo store ("14 giorni gratis, poi 39 €/anno"), mai importi o durate scritti a mano.
3. **iOS:** l'offerta introduttiva è applicata da StoreKit; mostra prezzo e durata letti da `ProductDetails`. Il pulsante "Ripristina acquisti" resta visibile (richiesto da Apple); su iOS NON chiamare `restorePurchases()` all'avvio (chiede l'accesso all'Apple ID): solo da pulsante e in ascolto sullo stream.
4. **Niente più `now + 365`.** Rimuovi `_activateIap` con scadenza calcolata. Introduci `iap_active` e `iap_verified_at` (impostazioni): una transazione di `annual` con stato `purchased/restored` imposta `iap_active = true` e `iap_verified_at = now`; **non** modifica scadenze. L'abbonamento è valido finché lo store lo riporta come attivo.
5. **Verifica periodica.** Ad ogni avvio (Android, se online) interroga gli acquisti posseduti (`InAppPurchaseAndroidPlatformAddition`/`restorePurchases` secondo l'API disponibile nella versione in uso): se `annual` non risulta più posseduto/attivo, imposta `iap_active = false`; se non c'è rete mantieni l'ultimo stato per un **periodo di tolleranza di 7 giorni** da `iap_verified_at`, poi torna a sola lettura finché non si riesce a verificare. Scrivi nel codice e in `docs/acquisti.md` il limite: senza un server di verifica (Play Developer API / App Store Server API) lo stato dipende dal client; la verifica lato server è un possibile passo futuro, e un servizio come RevenueCat potrebbe sostituire questa parte dietro la stessa interfaccia.
6. Crea l'interfaccia `EntitlementSource` (metodo `Future<EntitlementState> current()`) con implementazione `StoreEntitlementSource` e fai usare a `LicenseService` solo questa: così in futuro si può cambiare sorgente senza toccare la schermata.
7. **Priorità dello stato licenza:** chiave offline valida > abbonamento attivo (anche in prova store) > prova locale di riserva attiva > sola lettura. Se lo store è disponibile ma l'utente non ha ancora abbonamento e non c'è prova locale attiva, la schermata propone "Inizia prova gratuita".
8. **Test:** `LicenseService` con `EntitlementSource` e storage finti: abbonamento attivo, abbonamento revocato, offline entro e oltre 7 giorni, chiave offline, prova locale scaduta, priorità degli stati, assenza di slittamento della scadenza a eventi ripetuti.

## C. Comando di azzeramento solo per il debug

Nella schermata diagnostica sensori (o in una voce "Sviluppo" già nascosta) aggiungi **"Azzera prova e licenza"** visibile solo con `kDebugMode`: cancella `trial_started_at`, l'ancora (Keychain/file), `license_*` e `iap_*`, poi riavvia lo stato del servizio. Nelle build di release il codice non deve essere raggiungibile (verifica con `flutter build apk --release`).

## D. Google Drive all'avvio (correzioni a `GoogleDriveProvider`)

1. `connect({bool interactive = true})`: con `interactive: false` usa **solo** `attemptLightweightAuthentication()` e `authorizationClient.authorizationForScopes(...)`; se manca qualcosa restituisce `false` senza mostrare finestre (nessun `authenticate`, nessun `authorizeScopes`). `main.dart::_restoreCloudSession` usa `interactive: false`; il pulsante di collegamento in `cloud_backup_screen.dart` usa `interactive: true`.
2. Se all'avvio il collegamento silenzioso non riesce, l'app segna Drive come "da ricollegare" (messaggio non bloccante nella schermata Cloud e un avviso nel riepilogo backup), senza perdere la configurazione.
3. `_initSignIn()` con flag statico `_initialized`: chiama `GoogleSignIn.instance.initialize(...)` una sola volta per esecuzione.
4. Mantieni `GOOGLE_SERVER_CLIENT_ID` obbligatorio su Android (già presente); in release il controllo deve restare. Aggiungi un test sul comportamento non interattivo con un finto provider.

## E. Igiene del repository

- `git rm --cached` per `_backup_pre_redesign_20261004.tar.gz`, `pubspec-1.yaml`, `android/app/google-services.json`; aggiungili a `.gitignore` (insieme a `*.tar.gz` nella radice del progetto e `ios/Runner/GoogleService-Info.plist`) e lascia i file sul disco.
- Aggiungi `tool/build_release.bat` (e `.sh`) che richiede come variabili d'ambiente `BH_LICENSE_SECRET` e `GOOGLE_SERVER_CLIENT_ID`, fallisce con messaggio chiaro se mancano e lancia `flutter build appbundle --release --dart-define=...`; nessun segreto scritto nel file.
- `.vscode/launch.json` e `settings.json` con `dev-secret`: lascia così per lo sviluppo, aggiungi in `docs/identificativi.md` l'avvertenza che quel valore non va mai usato per build distribuite.

## Documentazione

`docs/acquisti.md` (nuovo): modello di prova (store + riserva locale), come creare abbonamento e offerta su Play e App Store, stati della licenza e priorità, periodo di tolleranza, limiti della verifica lato client, come azzerare la prova in debug, come testare con account di prova delle licenze (Play: tester di licenza; App Store: utenti Sandbox). Aggiorna README e `docs/identificativi.md`.

## Verifiche

- `flutter analyze` e `flutter test` verdi, nuovi test inclusi.
- `flutter build apk --debug` riuscita; `flutter build apk --release --dart-define=BH_LICENSE_SECRET=test --dart-define=GOOGLE_SERVER_CLIENT_ID=test` riuscita (con `key.properties`).
- Prova manuale su telefono: avvia, annota i giorni di prova, **disinstalla e reinstalla** dopo aver attivato il backup Google: la prova non riparte da 14 (se il backup non è stato ripristinato, il comportamento è documentato). Cambia la data del telefono indietro di giorni: l'app mostra lo stato "orologio alterato".
- All'avvio con token Drive scaduto non compare nessuna finestra di Google; la schermata Cloud indica "da ricollegare".
- `git ls-files` non contiene più tar.gz, `pubspec-1.yaml`, `google-services.json`.

## Criteri di accettazione

1. Disinstallare e reinstallare non azzera la prova (Keychain su iOS, backup Android per la prova locale, store per l'abbonamento).
2. Nessuna scadenza calcolata come "oggi + 365": l'abbonamento è valido solo se lo store lo riporta attivo (tolleranza offline 7 giorni).
3. Prova gratuita dello store mostrata con testi e prezzi letti dallo store; acquisto a vita non offerto in-app.
4. Orologio indietro rilevato; nessuna perdita di dati, solo sola lettura.
5. Drive all'avvio mai interattivo; `initialize()` chiamato una volta.
6. Comando di azzeramento presente solo in debug.
7. Repository pulito dai file indicati, script di build di release senza segreti.
