# PROMPT 13 — Licenza solo tramite gli store (abbonamento annuale), senza chiavi offline — HACCPass

Progetto: `C:\DEV\HACCPass` (o `D:\DEV\App\HACCPass`). Decisione: il rinnovo annuale, gli addebiti, i rimborsi e la prova gratuita sono gestiti **solo da Google Play e App Store** (abbonamento auto-rinnovabile `it.bluescorpion.haccpass.annual`, 49 €/anno, prova di 14 giorni dello store). La **chiave di licenza offline `BH1-…` viene rimossa dall'app di release**. Prima di modificare leggi: `lib/services/license_service.dart`, `lib/screens/license_screen.dart`, `lib/core/license/{license_codec,trial_anchor,entitlement_source}.dart`, `lib/services/store_entitlement_source.dart`, `tool/{license_keygen.dart,build_release.bat,build_release.sh}`, `test/{license_codec_test,license_service_test,trial_anchor_test}.dart`, `docs/identificativi.md`, `docs/acquisti.md` (se esiste), `README.md`, `lib/screens/more_screen.dart` e ogni punto che mostra lo stato licenza. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## Attenzione: il segreto serve ancora per l'ancora della prova

`TrialAnchor.platform(secret: appSecret)` usa `LicenseService.appSecret` (`BH_LICENSE_SECRET`) per il MAC dell'ancora. Quindi **non eliminare il segreto**: rinominalo, perché non è più "il segreto delle chiavi":

- Nuova costante `AppIntegrity.anchorSecret = String.fromEnvironment('BH_ANCHOR_SECRET')` (file `lib/core/license/app_integrity.dart`).
- In **release** un valore vuoto fa fallire l'avvio con messaggio esplicito (come oggi), in debug è consentito con avviso (`assert`).
- Accetta per compatibilità anche `BH_LICENSE_SECRET` come alias (se `BH_ANCHOR_SECRET` è vuoto usa quello) e documentalo; così le configurazioni esistenti (`.vscode`, script) non si rompono. Aggiorna `tool/build_release.bat`/`.sh` e `docs/identificativi.md` con il nuovo nome e con l'avvertenza: "il valore è una protezione leggera contro la modifica casuale dell'ancora; non è un segreto forte (sta nel binario) e **non** protegge nessuna licenza, che dipende solo dallo store".

## 1. Rimozione della chiave offline

1. In `LicenseService`:
   - Elimina `unlockWithKey`, il campo `codec`, l'import di `license_codec.dart`, `customerCode`, `expiresAt` (se usato solo da offline/debug: tienilo solo per debug o sostituiscilo con un flag), `LicenseKind.offline`, e le righe di `_loadState`, `_persist`, `_applyPriority`, `chipLabel`, `canWrite`, `isLifetime` che lo riguardano. `LicenseKind` diventa `{ none, trial, iap, debug }` (`debug` raggiungibile solo con `kDebugMode`).
   - **Compatibilità dati:** se nelle impostazioni c'è `license_kind = 'offline'` (installazioni di prova), trattalo come prova e **non** concedere nulla; pulisci le chiavi `license_key`, `license_expires_at`, `license_customer` al primo avvio (migrazione silenziosa).
   - La priorità diventa: **abbonamento attivo (anche in prova dello store) > prova locale di riserva > sola lettura**; `debug` solo in debug.
2. `lib/core/license/license_codec.dart`: rimuovi dal progetto di release; sposta `license_codec.dart`, `tool/license_keygen.dart` e `test/license_codec_test.dart` in `tool/archive/` fuori da `lib/` e dai test, con un `README.md` che spiega "codice storico delle chiavi offline, non incluso nelle build; riattivabile in caso di vendita diretta futura". Niente riferimenti a `LicenseCodec` rimasti in `lib/`.
3. `lib/screens/license_screen.dart`: elimina `_offlineKeySection`, `keyController`, l'import `dart:io` se resta inutilizzato e ogni riferimento alla "chiave di licenza". Il testo della card "Acquisti in-app non disponibili su questo dispositivo" diventa: "Gli acquisti non sono disponibili ora: controlla la connessione e che sul telefono sia attivo Google Play (o App Store), poi riprova." con pulsante **Riprova** che richiama l'inizializzazione degli acquisti.
4. Cerca con grep `BH1`, `chiave di licenza`, `offline`, `license_key`, `codec`, `unlockWithKey` in `lib/`, `test/`, `README.md`, `docs/`, `tool/` e adegua tutto.

## 2. Nuove funzioni utili per un modello store-only

1. **"Gestisci abbonamento"** nella schermata licenza (visibile quando c'è un abbonamento): apre la pagina di gestione dello store (`https://play.google.com/store/account/subscriptions?sku=it.bluescorpion.haccpass.annual&package=it.bluescorpion.haccpass` su Android, `https://apps.apple.com/account/subscriptions` su iOS) con `url_launcher` (aggiungi la dipendenza se manca; apertura in app esterna).
2. **Codice promozionale (solo iOS):** pulsante "Hai un codice?" che chiama `InAppPurchaseStoreKitPlatformAddition.presentCodeRedemptionSheet()` (pacchetto `in_app_purchase_storekit`, verifica nome e disponibilità nella versione in uso). Su Android i codici si riscattano da Play Store: una riga di testo lo spiega.
3. **Ripristina acquisti** resta sempre visibile (obbligatorio su iOS).
4. **Stato chiaro dell'abbonamento** nella card: "Abbonamento attivo", "Prova gratuita in corso", "In verifica (offline: ancora N giorni)", "Abbonamento scaduto o sospeso", "Disdetto: attivo fino alla scadenza" quando è deducibile dallo store (Android: un abbonamento disdetto ma non scaduto compare ancora tra gli acquisti posseduti: **non toglierlo prima**, regola di Google Play). Se lo stato non è distinguibile con il plugin, mostra solo ciò che si sa, mai una scadenza inventata.
5. **Avviso di pagamento** (se i dati lo permettono): quando lo store segnala un problema di pagamento, mostra un messaggio non bloccante con il pulsante "Gestisci abbonamento".
6. Nessun importo, durata o testo di prova scritto a mano: tutto da `ProductDetails` (già così).

## 3. Desktop e piattaforme senza store

L'app è per Android e iOS. Su Windows/Linux/macOS (build di sviluppo) gli acquisti non esistono: lì lo stato resta prova locale poi sola lettura, e la schermata licenza mostra "La licenza si acquista dall'app per Android o iPhone". Non reintrodurre chiavi per questo caso.

## 4. Test

- Aggiorna `test/license_service_test.dart` con `EntitlementSource` finto: abbonamento attivo → scrittura abilitata; prova store; abbonamento revocato; offline entro/oltre tolleranza 7 giorni; priorità degli stati; `license_kind = 'offline'` ereditato → trattato come prova e ripulito; **nessun metodo/valore di sblocco in release**; `debugUnlock` e `debugReset` funzionano solo con `kDebugMode`.
- Rimuovi `test/license_codec_test.dart` dalla suite (archiviato, vedi §1). `test/trial_anchor_test.dart` resta e deve passare con `BH_ANCHOR_SECRET` (e con l'alias `BH_LICENSE_SECRET`).
- Widget test: `LicenseScreen` senza sezione chiave offline; con store non disponibile mostra "Riprova"; con abbonamento mostra "Gestisci abbonamento"; su iOS (simulato) compare "Hai un codice?".
- Verifica di release: `flutter build apk --release --dart-define=BH_ANCHOR_SECRET=test --dart-define=GOOGLE_SERVER_CLIENT_ID=test` riuscita; senza `BH_ANCHOR_SECRET` l'avvio in release fallisce con messaggio chiaro; nessun simbolo `LicenseCodec`/`BH1` nel codice compilato (grep sui sorgenti).

## 5. Documentazione

`docs/acquisti.md` (aggiorna o crea): modello store-only; come creare l'abbonamento e l'offerta di prova su Play Console e App Store Connect; stati di Google Play (attivo, periodo di tolleranza, sospeso, disdetto fino alla scadenza, scaduto) e comportamento dell'app per ciascuno; limiti della verifica lato client e quando passare a un servizio di verifica (RevenueCat o server con Play Developer API / App Store Server API); codici promozionali (Apple offer code, Google Play promo code) al posto delle chiavi per regali e prove ai clienti; assistenza senza chiavi (come aiutare un cliente: ripristina acquisti, gestione abbonamento, tester di licenza); account tester per le prove. Aggiorna README e `docs/identificativi.md` (nuovo nome `BH_ANCHOR_SECRET`, niente più chiavi, fine del flusso di generazione).

## Criteri di accettazione

1. Nella build di release non esiste alcun modo di sbloccare l'app se non l'abbonamento dello store (o la prova locale/store); nessuna chiave offline, nessun codec, nessun keygen incluso.
2. Un database o un backup manomesso (`license_kind`, `license_expires_at`, `license_key`) non concede nulla.
3. L'ancora della prova continua a funzionare, con `BH_ANCHOR_SECRET` obbligatorio in release.
4. La schermata licenza ha: prova gratuita dello store, abbonamento annuale, ripristina acquisti, gestisci abbonamento, codice promozionale (iOS), stati chiari e nessun riferimento a chiavi.
5. Codice storico archiviato fuori dalla build con spiegazione; documentazione aggiornata; `flutter analyze` e `flutter test` verdi.
