# Backup: formato, involucro dell'app e ancora della prova (Prompt 20)

Come è fatto un file `.bhb`, cosa protegge l'involucro cifrato
dell'app, perché il backup su Drive non si apre più a mano e come si
comporta l'ancora firmata della prova al ripristino.

## Strati di un file `.bhb`

Dall'esterno all'interno:

1. **Involucro cifrato e autenticato dell'app (`HPBK1`)** — SEMPRE
   presente nei backup creati dal Prompt 20 in poi, anche se l'utente
   non ha scelto una password. AES-256-GCM a blocchi con chiave
   costante dell'app (vedi sotto). Un file alterato fallisce subito il
   ripristino: il tag GCM sostituisce ogni altro controllo di
   integrità del file.
2. **Cifratura con password dell'utente (facoltativa, solo backup di
   soli dati)** — `BHB2` (attuale) o `BHB1` (storico), invariata. La
   password dell'utente resta lo strato INTERNO: i due livelli si
   sommano.
3. **ZIP** con `blue_haccp.db` + `manifest.json` (+ `attachments/` nei
   backup completi).

Il **backup completo** (con le foto) continua a non accettare una
password (è scritto in streaming), ma riceve anche lui l'involucro
dell'app: la cifratura dell'involucro avviene a blocchi, un file alla
volta, senza picchi di memoria anche con migliaia di foto.

### Manifest

Oltre ai campi storici (`format`, `schemaVersion`, `appVersion`,
`createdAt`, `dbSha256`, `attachments`…), i backup nuovi possono
contenere:

- `trialAnchor`: l'**ancora firmata della prova** (stesso formato e
  stessa firma HMAC di `anchor/trial_anchor.json`:
  `{"v":1,"start","lastSeen","mac"}`). Solo due date e una firma:
  nessun altro dato personale. Omesso se non esiste ancora una data di
  prova o il segreto è vuoto (solo debug);
- `trialAnchorVersion: 1`: dice "questo backup è stato creato da una
  versione che scrive l'ancora". Se manca, il backup è della versione
  precedente e il ripristino si comporta come sempre. Nessun numero di
  versione del formato è stato introdotto: i lettori vecchi ignorano
  le chiavi sconosciute (verificato da test).

## Involucro HPBK1

```
intestazione in chiaro (22 byte):
  'HPBK1' (5) | keyId (1) | prefisso nonce (8, casuale) | plainLen (8, big-endian)
per ogni blocco (fino a 1 MiB di testo in chiaro):
  encLen (4) | ciphertext (encLen) | tag GCM (16)
```

- cifratura AES-256-GCM (pacchetto `cryptography`, già usato per la
  password): nonce del blocco *i* = prefisso(8) + contatore(i); AAD =
  intestazione + contatore. Riordino, troncamento (confronto con
  `plainLen`) e modifica di un singolo byte vengono tutti rilevati;
- chiave effettiva = **HKDF-SHA256** dalla costante
  `BackupEnvelope._masterKeys[keyId]`, con salt e info fissi.

### Regole per le chiavi (critiche)

- la costante con `keyId = 1` è **identica in ogni build e non cambia
  mai**: cambiarla renderebbe illeggibili tutti i backup dei clienti;
- **non dipende da `BH_ANCHOR_SECRET`**: cambiare il segreto di build
  non rende illeggibile nessun backup;
- per aggiungere una chiave futura si AGGIUNGE un nuovo `keyId`
  nell'elenco e i vecchi restano leggibili per sempre;
- `keyId` sconosciuto = backup creato da una versione più recente:
  messaggio "aggiorna HACCPass", nessun crash.

## Compatibilità

- **Backup vecchi** (senza marcatore `HPBK1`, ZIP nudo o cifrato con
  password BHB1/BHB2): si aprono e si ripristinano esattamente come
  prima. Coperto da test di regressione.
- **Backup nuovi su app vecchia**: la versione già pubblicata non
  riconosce il marcatore e mostra l'errore generico di ripristino non
  riuscito (niente crash: l'eccezione è catturata dalla schermata).
  La versione che introduce il formato riconosce `HPBK1` e rifiuta
  con un messaggio chiaro qualunque marcatore futuro non noto. La
  prima volta che si crea un backup con il nuovo formato l'app mostra
  una volta sola la nota "I backup creati da questa versione si aprono
  solo con HACCPass aggiornato".

## Perché il backup su Drive non si apre più a mano

Scelta intenzionale di prodotto: l'involucro rende il file
inutilizzabile fuori da HACCPass (estrazione manuale di foto o dati dal
file di backup sul Drive). Non è una promessa di inviolabilità — la
chiave sta nel binario — è una barriera contro la modifica e la
lettura casuale. La via d'uscita per l'utente restano le esportazioni
leggibili già esistenti e invariate: **dossier PDF** e **registri**
(esportabili/condivisibili dalle rispettive schermate).

Nei testi dell'app non scrivere mai che il backup è "inviolabile": la
formula corretta è "i backup sono protetti dall'app".

## Ancora della prova nel backup

Al momento di creare il backup, la data firmata è la data di inizio
effettiva della prova: la più antica tra database e ancora piattaforma
(quella calcolata da `TrialAnchor.synchronize`). Al ripristino:

- **ancora presente e firma valida** → la data ripristinata è la più
  antica tra telefono, ancora firmata e (se presente) data del
  database del backup. La data non si sposta mai in avanti;
- **ancora con firma non valida, o assente mentre `trialAnchorVersion
  ≥ 1` la dichiarava** → backup incompleto o manomesso: i dati si
  ripristinano comunque ma NESSUNA data della prova viene presa dal
  backup (resta quella del telefono). Solo un log, nessun blocco;
- **backup vecchio senza campo ancora** → comportamento storico: data
  del database ripristinato con la regola "la più antica vince";
- dopo il ripristino l'ancora della piattaforma (file Android /
  Keychain iOS) viene riallineata alla data effettiva, come fa
  `synchronize`.

Lo stato dell'abbonamento (`iap_active`, `license_*`) non viene MAI
importato dal backup.

### Limiti onesti

La firma è una protezione LEGGERA (il segreto sta nel binario):

- chi **non ripristina** i dati e reinstalla l'app riparte da 14
  giorni di prova locale (la prova dello store non si rigenera);
- chi usa **un altro account** o **modifica a mano il formato** con
  strumenti adeguati può aggirare la barriera;
- la difesa forte resta la prova gratuita e l'abbonamento gestiti dallo
  store (vedi `docs/acquisti.md`).

Se il segreto `BH_ANCHOR_SECRET` cambiasse fra le build, le ancore
firmate col vecchio segreto (file di piattaforma e backup) risulterebbero
non valide: vengono trattate come alterate, senza crash e senza giorni
regalati. Il segreto deve restare identico fra le build (vedi
`docs/identificativi.md`); la chiave dell'involucro è separata e non
risente di quel cambio.
