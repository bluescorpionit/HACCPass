# Acquisti, prova gratuita e stati della licenza (Prompt 13)

Modello **store-only**: rinnovo annuale, addebiti, rimborsi e prova
gratuita sono gestiti **solo da Google Play e App Store** tramite
l'abbonamento auto-rinnovabile **`it.bluescorpion.haccpass.annual`**
(**49 €/anno**, prova gratuita di 14 giorni dello store).

Le **chiavi di licenza offline `BH1-…` non esistono più** nell'app di
release (Prompt 13): il codice storico è archiviato in
`tool/archive/`, fuori da `lib/` e dalla suite di test, riattivabile
solo in caso di ripresa della vendita diretta. In release l'unico modo
di sbloccare l'app è l'abbonamento dello store (o le prove: quella
dello store e la riserva locale).

- Un database o un backup manomesso (`license_kind`,
  `license_expires_at`, `license_key`, `license_customer`) **non
  concede nulla**: quelle righe non sono più lette per concedere nulla
  e vengono ripulite al primo avvio (migrazione silenziosa; le righe di
  licenza non sono mai importate dai backup, Prompt 12).
- Il pulsante di sblocco di prova e la voce "Azzera prova e licenza"
  esistono SOLO nelle build debug (`kDebugMode`, costante compile-time:
  in release non sono raggiungibili né compilabili).

## Le due prove gratuite

1. **Prova primaria, gestita dallo store.** L'abbonamento annuale ha
   un'offerta con fase gratuita di 14 giorni su Google Play e App Store.
   Gli store ricordano a quale account è già stata concessa la prova:
   **reinstallare l'app non la rigenera**.
2. **Prova locale di riserva, senza store** (14 giorni,
   `LicenseService.trialDays`). Copre i dispositivi senza store (build
   di test, installazioni fuori dallo store) e il periodo precedente
   alla pubblicazione. Resiste alla reinstallazione e all'alterazione
   dell'orologio tramite **ancora** (vedi sotto).

### L'ancora della prova (`lib/core/license/trial_anchor.dart`)

La prova locale non vive solo nel database (Android lo cancella con
l'app): la data di inizio è replicata su un supporto che di norma
sopravvive alla disinstallazione.

- **iOS**: Keychain (`flutter_secure_storage`,
  `KeychainAccessibility.first_unlock_this_device`, NON
  `synchronizable`).
- **Android**: file `anchor/trial_anchor.json` nella cartella di
  supporto, incluso nel **backup automatico di Android** con le regole
  `android/app/src/main/res/xml/backup_rules.xml` (API < 31) e
  `data_extraction_rules.xml` (Android 12+): presenti gli `<include>`
  il backup contiene **solo i percorsi inclusi** (il database e gli
  allegati restano fuori, nessun ripristino parziale).

Contenuto firmato con HMAC-SHA256 usando `BH_ANCHOR_SECRET` (vedi
`lib/core/license/app_integrity.dart`). Un contenuto con MAC non valido
è trattato come assente e registrato come "alterato". Regole: data
effettiva = la più antica tra database, ancora e file ripristinato
(mai spostata in avanti); `lastSeen = max(lastSeen, now)` ad avvio e
ripresa; se `now < lastSeen − 24 h` stato esplicito "Orologio del
dispositivo alterato", sola lettura, nessuna perdita di dati.

**Limiti documentati**: su Android il file nel backup sopravvive alla
reinstallazione solo se l'utente ha il **backup Google attivo** (altrimenti la prova locale riparte da 14 giorni: best-effort
documentato; la prova dello store non ha questo limite). Inoltre il
segreto è una protezione LEGGERA: sta nel binario, non è un segreto
forte e **non protegge nessuna licenza** (che dipende solo dallo
store).

## Creare l'abbonamento con prova gratuita

### Google Play Console

1. **Monetizzazione → Prodotti → Abbonamenti → Crea**:
   ID prodotto `it.bluescorpion.haccpass.annual`, nome "HACCPass
   annuale" (it-IT).
2. **Piano base**: `annual` con fatturazione **annuale**, prezzo
   **49,00 €**.
3. **Offerta → Crea offerta**: fase iniziale **Periodo di prova
   gratuita — 14 giorni** seguita dal rinnovo automatico al piano base
   (49,00 €/anno); ammissibilità: nuovi abbonati.
4. Attivare piano base e offerta.

L'app legge le offerte da `GooglePlayProductDetails`
(`subscriptionOfferDetails`): sceglie quella con **prima fase
gratuita** e acquista con `GooglePlayPurchaseParam(offerToken: …)`. Il
testo del paywall (es. "14 giorni gratis, poi 49,00 €/anno") è
costruito SOLO con durate e importi restituiti dallo store.

### App Store Connect

1. **Funzionalità → Acquisti in-app → Abbonamenti**: gruppo "HACCPass",
   prodotto `it.bluescorpion.haccpass.annual` (abbonamento annuale,
   49,00 €).
2. Nella scheda del prezzo: **Offerta introduttiva → Prova gratuita**,
   durata **14 giorni**.
3. Localizzazione it-IT; screenshot del paywall per la revisione.

Su iOS l'offerta introduttiva è applicata da StoreKit al primo
acquisto; il pulsante **"Ripristina acquisti" resta sempre visibile**
(richiesto da Apple) e `restorePurchases()` non viene mai chiamato
automaticamente all'avvio (chiede l'accesso all'Apple ID).

## Stati dell'abbonamento e comportamento dell'app

Stati di Google Play per un abbonamento e cosa fa l'app (fonte: il
risultato di `queryPurchases` restituito dal plugin):

| Stato Play | Cosa vede l'app | Comportamento |
|---|---|---|
| Attivo (in prova o pagato) | `annual` tra gli acquisti posseduti | `iap_active = 1`: tutte le funzioni, card "Abbonamento attivo" |
| Disdetto ma non scaduto | `annual` ANCORA tra gli acquisti posseduti (regola Play: resta valido fino alla scadenza) | L'app lo mostra attivo: è la regola di Google Play, **non va tolto prima** |
| Sospeso (payment on hold) | `annual` tra i posseduti + evento `pending` | Avviso non bloccante "Pagamento in sospeso" con "Gestisci abbonamento" |
| In grazia (grace period) | come attivo | funzioni attive; Play poi risolve addebito o sospende |
| Scaduto / cancellato | `annual` NON più tra i posseduti | `iap_active = 0`: "Abbonamento scaduto o sospeso", sola lettura (o prova residua) |
| App offline | store non raggiungibile | tolleranza di **7 giorni** da `iap_verified_at`: "In verifica (offline: ancora N giorni)", poi sola lettura |

Il plugin non distingue "in prova", "disdetto fino alla scadenza" o la
data di rinnovo: la card mostra solo ciò che si sa, **mai una scadenza
inventata**.

Priorità dello stato licenza: **abbonamento attivo (anche in prova
dello store) > prova locale di riserva attiva > sola lettura**
(`debug` solo nelle build di debug).

### Limiti della verifica lato client

Senza un server di verifica (Google Play Developer API / App Store
Server API) lo stato dipende dalla risposta del client allo store. Da
valutare quando il volume lo giustifica: un backend con le API ufficiali
oppure un servizio come **RevenueCat**, collegato dietro la stessa
interfaccia `EntitlementSource`
(`lib/core/license/entitlement_source.dart`, implementazione attuale
`StoreEntitlementSource`): la schermata non cambia.

## Codici promozionali (al posto delle chiavi)

Per regali, sconti e prove ai clienti non ci sono più chiavi: usare i
codici degli store.

- **App Store**: offer code / codici promozionali. Nell'app il
  pulsante **"Hai un codice?"** (solo iOS) apre il foglio di riscatto
  di StoreKit (`presentCodeRedemptionSheet`).
- **Google Play**: promo code. Nell'app una riga spiega che si
  riscattano dal Play Store (Impostazioni → Play Points / scheda
  offerta); l'applicazione è automatica al prossimo acquisto.

## Assistenza senza chiavi

Come aiutare un cliente che "non vede più la licenza":

1. **Ripristina acquisti** nella schermata licenza (richiede l'account
   dello store usato per l'acquisto);
2. **Gestisci abbonamento** (pulsante nell'app) per verificare stato,
   metodo di pagamento e rinnovo nello store;
3. se ha cambiato telefono/account: ripristinare sul nuovo account o
   usare un **codice promozionale**;
4. per i test: **tester di licenza** Play (Play Console →
   Configurazione) e **utenti Sandbox** (App Store Connect → Utenti e
   accesso → Tester Sandbox); i rinnovi di test sono accelerati e la
   prova di test non consuma quella reale.

## Desktop e piattaforme senza store

L'app è per Android e iOS. Su Windows/Linux/macOS (build di sviluppo)
gli acquisti non esistono: la schermata licenza mostra "La licenza si
acquista dall'app per Android o iPhone"; lo stato resta prova locale e
poi sola lettura. Nessuna chiave reintrodotta per questo caso.

## Azzera prova e licenza (SOLO debug)

In **Altro → "Azzera prova e licenza (debug)"** (visibile solo con
`kDebugMode`, assente dalle build di release): cancella
`trial_started_at`, l'ancora, le impostazioni di licenza (incluse le
righe storiche delle chiavi) e `iap_*`, poi riavvia lo stato del
servizio.
