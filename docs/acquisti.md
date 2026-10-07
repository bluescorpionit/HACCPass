# Acquisti, prova gratuita e stati della licenza (Prompt 10)

Modello commerciale: **abbonamento annuale a 39 €/anno** con **14 giorni
di prova gratuita**, più la **chiave offline `BH1-…`** (vendita diretta,
nascosta su iOS). La licenza a vita **non è più offerta in-app**: resta
solo come chiave offline diretta.

- ID prodotto unico (su Play Console e App Store Connect):
  **`it.bluescorpion.haccpass.annual`**.
- Nel codice: `LicenseProductIds.annual`
  (`lib/services/license_service.dart`). `LicenseProductIds.lifetime` è
  stato **rimosso**: nessun prodotto a vita negli store.

## Le due prove gratuite

1. **Prova primaria, gestita dallo store.** L'abbonamento annuale ha
   un'offerta con fase gratuita di 14 giorni su Google Play e App Store.
   Gli store ricordano a quale account è già stata concessa la prova:
   **reinstallare l'app non la rigenera**. È il canale principale dopo
   la pubblicazione.
2. **Prova locale di riserva, senza store** (14 giorni,
   `LicenseService.trialDays`). Copre i dispositivi senza store (build
   di test, installazioni fuori store) e il periodo precedente alla
   pubblicazione. Resiste alla reinstallazione e all'alterazione
   dell'orologio tramite **ancora** (vedi sotto). Su un dispositivo
   normale, dopo la pubblicazione, l'utente vede la prova dello store:
   la riserva resta come rete di sicurezza.

### L'ancora della prova (`lib/core/license/trial_anchor.dart`)

La prova locale non vive solo nel database (Android lo cancella con
l'app): la data di inizio è replicata su un supporto che di norma
sopravvive alla disinstallazione.

- **iOS**: Keychain (`flutter_secure_storage`,
  `KeychainAccessibility.first_unlock_this_device`, NON
  `synchronizable`). Gli elementi Keychain non vengono rimossi alla
  disinstallazione.
- **Android**: la Keystore viene cancellata con l'app, quindi si usa il
  file `anchor/trial_anchor.json` nella cartella di supporto, incluso
  nel **backup automatico di Android** con le regole
  `android/app/src/main/res/xml/backup_rules.xml` (API < 31) e
  `data_extraction_rules.xml` (Android 12+): presenti gli `<include>`
  il backup contiene **solo i percorsi inclusi**, quindi unicamente
  l'ancora — database, allegati (`app_flutter`), preferenze, cache ed
  archivi esterni restano fuori (nessun ripristino parziale del
  database; per questo non servono `<exclude>` espliciti: il
  validatore di Android li rifiuta su percorsi non inclusi).

Contenuto firmato con HMAC-SHA256 (stesso segreto delle licenze,
`BH_LICENSE_SECRET`; vuoto consentito solo in debug):
`{"v":1,"start":"<ISO UTC>","lastSeen":"<ISO UTC>","mac":"<base64>"}`.
Un contenuto con MAC non valido è trattato come assente e registrato
come "alterato".

Regole:

- **Data di inizio effettiva = la più antica** tra database
  (`trial_started_at`), ancora piattaforma e file ripristinato dal
  backup. Alla lettura gli altri supporti vengono riallineati alla data
  più antica; la data non viene mai spostata in avanti.
- **Orologio**: a ogni avvio e ripresa dell'app viene aggiornato
  `lastSeen = max(lastSeen, now)`. Se `now < lastSeen - 24 h` la prova
  è considerata scaduta con stato esplicito "Orologio del dispositivo
  alterato: verifica data e ora": nessun crash, nessun dato cancellato,
  l'app resta in sola lettura finché la data non è corretta.

**Limite documentato (Android)**: il trucco del file nel backup funziona
solo se l'utente ha il **backup Google attivo** e il telefono ripristina
i dati alla reinstallazione. Se il backup non è attivo (o non viene
ripristinato) la prova locale riparte da 14 giorni: è il comportamento
best-effort documentato, non un difetto. La prova dello store non ha
questo limite.

## Creare l'abbonamento con prova gratuita

### Google Play Console

1. **Monetizzazione → Prodotti → Abbonamenti → Crea**:
   ID prodotto `it.bluescorpion.haccpass.annual`, nome "HACCPass
   annuale" (it-IT).
2. **Piano base**: `annual` con fatturazione **annuale**, prezzo
   **39,00 €** (tasse incluse come da Play).
3. **Offerta → Crea offerta**: ID `trial14`, tag offerta a piacere;
   **Configura fasi prezzo** con fase iniziale **Periodo di prova
   gratuita — 14 giorni** seguita dal rinnovo automatico al piano base
   (39,00 €/anno); ammissibilità: nuovi abbonati; senza altri piani
   nell'offerta.
4. Attivare piano base e offerta. La stessa offerta, con la stessa
   fase gratuita, è quella letta dall'app.

L'app legge le offerte da `GooglePlayProductDetails`
(`subscriptionOfferDetails`): sceglie quella con **prima fase gratuita**
e acquista con `GooglePlayPurchaseParam(offerToken: …)`. Il testo del
paywall (es. "14 giorni gratis, poi 39,00 €/anno") è costruito SOLO con
durate e importi restituiti dallo store: mai numeri scritti a mano.

### App Store Connect

1. **Funzionalità → Acquisti in-app → Abbonamenti**: gruppo "HACCPass",
   prodotto `it.bluescorpion.haccpass.annual` (abbonamento annuale,
   39,00 €).
2. Nella scheda del prezzo: **Offerta introduttiva → Prova gratuita**,
   durata **14 giorni**.
3. Localizzazione it-IT per nome e descrizione; screenshot del paywall
   per la revisione.

Su iOS l'offerta introduttiva è applicata da StoreKit al primo
acquisto: il paywall mostra prezzo e durata letti da `ProductDetails`.
Il pulsante **"Ripristina acquisti" resta sempre visibile** (richiesto
da Apple); `restorePurchases()` NON viene mai chiamato automaticamente
all'avvio (chiede l'accesso all'Apple ID), solo da pulsante.

## Stati della licenza e priorità

`LicenseService` risolve lo stato in quest'ordine (il primo valido
vince):

1. **Chiave offline valida** (`BH1-…` non scaduta; la data 9999-12-31 è
   la versione a vita venduta direttamente);
2. **Abbonamento attivo** secondo lo store, anche durante la prova
   gestita dallo store;
3. **Prova locale di riserva attiva** (14 giorni dall'ancora);
4. **Sola lettura**: consultazione sempre possibile, niente nuove
   registrazioni né esportazioni.

Se lo store è disponibile ma l'utente non ha abbonamento e non c'è
prova locale attiva, il paywall propone **"Inizia prova gratuita"**
(testo e prezzo dallo store).

## Verifica dell'abbonamento e tolleranza offline

- Ogni evento `purchased/restored` di `annual` imposta
  `iap_active = 1` e `iap_verified_at = ora`: **nessuna scadenza
  calcolata lato client** (niente "oggi + 365"). L'abbonamento è valido
  finché lo store lo riporta attivo.
- Ad ogni avvio (Android, se online) l'app interroga gli acquisti
  posseduti (`restorePurchases()`, che in questa versione del plugin
  esegue `queryPurchases`): se `annual` non risulta più attivo,
  `iap_active = 0`.
- **Senza rete** vale l'ultimo stato per un **periodo di tolleranza di
  7 giorni** da `iap_verified_at`; scaduto quello, sola lettura finché
  non si riesce a verificare.

**Limiti della verifica lato client**: senza un server di verifica
(Google Play Developer API / App Store Server API) lo stato dipende
dalla risposta del client allo store. La verifica lato server è il
passo futuro naturale; un servizio come RevenueCat può sostituire la
parte store dietro la stessa interfaccia `EntitlementSource`
(`lib/core/license/entitlement_source.dart`, implementazione attuale
`StoreEntitlementSource`): la schermata non cambia.

## Azzera prova e licenza (SOLO debug)

In **Altro → "Azzera prova e licenza (debug)"** (voce visibile solo con
`kDebugMode`, quindi assente dalle build di release; anche il metodo
`LicenseService.debugReset()` non fa nulla in release): cancella
`trial_started_at`, l'ancora (Keychain/file), le impostazioni
`license_*` e `iap_*`, poi riavvia lo stato del servizio (nuova prova
da 14 giorni). Utile per testare il paywall sul telefono di prova.

## Testare gli acquisti

- **Google Play**: Play Console → Configurazione → **Tester di
  licenza** (aggiungere l'email degli account Google di prova). I
  abbonamenti di test si rinnovano velocemente e possono essere
  cancellati/ripristinati a piacere; la prova gratuita di test non
  "consuma" quella reale dell'account.
- **App Store**: utenti **Sandbox** (App Store Connect → Utenti e
  accesso → Tester Sandbox). Sul dispositivo, StoreKit → utente sandbox
  nelle impostazioni dello sviluppatore; i rinnovi sandbox sono
  accelerati (abbonamento annuale ~1 ora).
- Sul telefono di prova si può anche azzerare la prova locale con la
  voce di debug (vedi sopra).

## Verifica manuale del comportamento alla reinstallazione

1. Installa la build di debug, annota i giorni di prova rimanenti.
2. Android: assicurati che il **backup Google** sia attivo
   (Impostazioni → Google → Backup). Disinstalla e reinstalla: la prova
   locale NON riparte da 14 (l'ancora torna dal backup). Se il backup
   non era attivo o non viene ripristinato, la prova locale riparte:
   comportamento documentato. Su iOS la Keychain sopravvive alla
   disinstallazione senza condizioni.
3. Con l'app pubblicata, la prova dello store non riparte comunque:
   se già concessa, Play/App Store addebitano subito.
4. Cambia la data del telefono indietro di alcuni giorni: l'app mostra
   lo stato "Orologio del dispositivo alterato", niente dati persi,
   sola lettura.
