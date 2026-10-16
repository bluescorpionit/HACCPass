# PROMPT 20 — Data di inizio prova firmata nel backup (reinstallazione e ripristino) — HACCPass

Progetto: `D:\DEV\App\HACCPass`. L'app è già in produzione: **nessuna installazione e nessun backup esistente deve rompersi**.

Situazione attuale (verificata nel codice):
- `RestoreService` (`lib/services/restore_service.dart`, ~righe 117–200) salva le impostazioni di licenza locali, sostituisce il database, legge `trial_started_at` dal database ripristinato e applica `_withEarliestTrial`: vince la data **più antica**. Lo stato di licenza dell'abbonamento non viene mai importato.
- Quella data, dentro il database, **non è firmata**: chi modifica il file di backup e cancella o svuota `trial_started_at` fa sì che `restoredTrial` sia `null`, e resta la data locale (una prova nuova di 14 giorni).
- L'ancora firmata HMAC esiste già (`lib/core/license/trial_anchor.dart`: `_encode`, `_parse`, `_mac`, segreto `AppIntegrity.anchorSecret` / `BH_ANCHOR_SECRET`), ma vive solo nel file `anchor/trial_anchor.json` (backup automatico Android) e nel Keychain iOS, **non nel backup Drive**.

Obiettivo: il backup porta con sé l'ancora **firmata** e il ripristino la usa, così rimuovere o alterare la data nel backup non regala giorni di prova. È una barriera leggera, non una protezione assoluta: non promettere altro nei testi.

Prima di modificare leggi: `lib/core/license/trial_anchor.dart`, `lib/core/license/app_integrity.dart`, `lib/services/backup_service.dart` (creazione backup, manifest, versione del formato), `lib/services/restore_service.dart`, `lib/services/license_service.dart`, `lib/repositories/haccp_repository.dart` (`readLicenseSettings`, `writeLicenseSettings`), `docs/acquisti.md`, `docs/identificativi.md`, test esistenti su backup/ripristino e ancora. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Il backup contiene l'ancora firmata

- Nel **manifest** del backup (non nel database) aggiungi un campo facoltativo `trialAnchor` con lo stesso formato dell'ancora esistente: `{"v":1,"start":"<ISO UTC>","lastSeen":"<ISO UTC>","mac":"<base64>"}`, prodotto da `TrialAnchor` (aggiungi un metodo pubblico, es. `exportSigned(DateTime start, DateTime lastSeen)` e `parseSigned(String)` che riusano `_encode`/`_parse`/`_mac`, senza duplicare la logica né cambiare il formato del file `trial_anchor.json`).
- Al momento di creare il backup, la `start` è la data di inizio effettiva della prova (la più antica tra database e ancora, già calcolata da `TrialAnchor.synchronize`). Se non esiste ancora una data (caso di installazione ancora senza avvio completato), il campo si omette.
- Aggiungi nel manifest un indicatore di formato (es. `trialAnchorVersion: 1`) che dice "questo backup è stato creato da una versione che scrive l'ancora". Aumenta la versione di formato del backup solo se oggi esiste già un numero di versione nel manifest e solo di **uno**, mantenendo la lettura di tutte le versioni precedenti.
- Il campo non deve contenere altri dati personali: solo le due date e la firma.

## 2. Il ripristino usa l'ancora firmata

In `RestoreService`, al posto della sola data letta dal database:

1. Leggi `trialAnchor` dal manifest del backup.
2. **Se presente e con firma valida** → la sua `start` è la data ripristinata; vince la più antica tra questa, la data locale e (se presente) quella del database ripristinato. Riscrivi le impostazioni come oggi con `_withEarliestTrial`.
3. **Se presente ma con firma NON valida** → trattala come ancora **alterata** (stesso comportamento già previsto in `TrialAnchor`: contenuto con MAC non valido = assente, registrato come alterato). Non concedere giorni in più: non ripristinare la data del backup, ma neppure bloccare il ripristino dei dati. Mostra un messaggio sobrio solo se il progetto ha già un punto per segnalare un'ancora alterata; altrimenti solo log.
4. **Se assente e il backup dichiara `trialAnchorVersion` ≥ 1** (cioè doveva esserci) → backup incompleto o manomesso: stessa gestione del punto 3.
5. **Se assente e il backup è di una versione precedente** (nessun `trialAnchorVersion`) → comportamento di oggi invariato: si usa la data del database ripristinato con la regola "più antica vince". Nessun backup vecchio si rompe.
6. Dopo il ripristino riallinea l'ancora della piattaforma (file/Keychain) con la data effettiva, come fa `synchronize`.

Resta fermo: **lo stato dell'abbonamento non viene mai importato dal backup**; la regola di priorità abbonamento > prova locale > sola lettura non cambia; la data non si sposta mai in avanti.

## 2-bis. Cifratura esterna del backup (strato dell'app, in più della password dell'utente)

Decisione di prodotto: ogni backup nuovo viene chiuso in un **involucro cifrato e autenticato dall'app**, sempre, anche se l'utente non ha scelto una password. Se l'utente ha già attivato la cifratura con la sua password (funzione esistente di backup protetto), quella resta **dentro**: i due strati si sommano (utente = interno, app = esterno).

- **Algoritmo:** cifratura autenticata (AES-256-GCM o ChaCha20-Poly1305, con il pacchetto crittografico già presente nel progetto, es. `cryptography`/`pointycastle`; se nessuno è presente scegli quello più semplice già disponibile e documentalo). Nonce casuale per backup; la verifica del tag **sostituisce** il controllo di integrità del file (un file alterato fallisce subito).
- **Chiave dell'app:** una chiave dedicata ai backup, **costante nel codice e MAI cambiata** (non usare `BH_ANCHOR_SECRET`: quel segreto viene passato in build e se cambiasse renderebbe illeggibili tutti i backup dei clienti). Deriva la chiave effettiva con HKDF da questa costante e da un identificativo di versione della chiave (`keyId`), scritto in chiaro nell'intestazione, così in futuro si può **aggiungere** una chiave nuova senza perdere la lettura delle vecchie (le vecchie si tengono per sempre).
- **Intestazione** in chiaro e piccola: marcatore magico (es. `HPBK1`), `keyId`, nonce. Il resto è cifrato.
- **Ripristino:** se il file inizia con il marcatore → rimuovi lo strato esterno (tag non valido = "backup alterato o danneggiato", nessun giorno di prova ripristinato, nessun crash) e prosegui con il flusso attuale (che chiede la password dell'utente se c'è lo strato interno). Se non c'è il marcatore → è un backup **vecchio**: flusso attuale invariato.
- **Compatibilità in avanti:** una versione dell'app precedente non può aprire i backup nuovi (formato non riconosciuto). Mostra nella versione nuova, **la prima volta** che si crea un backup, una nota sobria "I backup creati da questa versione si aprono solo con HACCPass aggiornato"; e se l'app vecchia ripristina un file con il marcatore deve fallire con un messaggio comprensibile, non con un crash (verifica come reagisce oggi `restore_service.dart` a un formato sconosciuto; se serve, correggi quel messaggio solo se è già nel codice nuovo).
- **Supporto:** il backup su Drive non è più apribile a mano per estrarre foto o dati. Documentalo in `docs/backup.md` come scelta intenzionale; prevedi un'**esportazione leggibile** esistente (dossier PDF e i registri) come via d'uscita per l'utente, senza cambiarla.
- **Onestà nei testi:** nell'app non scrivere che il backup è "inviolabile". Se compare una nota, usa "i backup sono protetti dall'app".
- **Test:** roundtrip cifra/decifra; file alterato (un byte cambiato) → errore pulito; backup vecchio senza marcatore → ripristino come oggi; backup nuovo con password utente (doppio strato) e senza; `keyId` sconosciuto → messaggio "aggiorna l'app"; intestazione tronca; backup di grandi dimensioni (con allegati) senza caricare tutto in memoria (usa flusso a blocchi se oggi il backup è a flusso).

## 3. Compatibilità con la produzione (vincolo prioritario)

- Un backup creato dalla versione **pubblicata** (senza `trialAnchor`) si ripristina con la nuova app esattamente come oggi.
- Un backup creato dalla nuova versione deve poter essere letto anche da una versione precedente dell'app (campi manifest sconosciuti ignorati, nessun crash): verifica con un test che un parser che ignora il campo non fallisce, e cosa fa oggi il lettore del manifest con chiavi sconosciute; se rifiutasse chiavi non note, non aumentare la versione del formato e fai in modo che il campo nuovo sia innocuo.
- Nessun cambiamento di schema del database, nessuna migrazione, nessun cambio di `blue_haccp.db`, id canali notifiche o identificativi.
- Se `AppIntegrity.anchorSecret` è vuoto (solo debug) non firmare né verificare: comportamento attuale.
- Se il segreto nella build cambia, le ancore firmate con il vecchio segreto risultano invalide: documentalo in `docs/identificativi.md` (il segreto deve restare identico fra le build; per le app già in produzione è quello della build corrente) e non cambiarlo.

## 4. Test e documentazione

- Test unitari: `exportSigned`/`parseSigned` roundtrip; firma modificata → invalida; backup con ancora valida più antica della locale → la data ripristinata è quella dell'ancora; più recente della locale → resta la locale; backup nuovo con ancora **rimossa** → trattato come alterato, nessun giorno in più; backup nuovo con data nel database rimossa ma ancora valida → data dell'ancora; backup **vecchio** (senza campo) → comportamento attuale (test di regressione); backup nuovo letto con un parser che ignora il campo; segreto vuoto (debug) → nessun controllo.
- Test di ripristino end-to-end con file di backup sintetici (nessun dato reale); verifica che abbonamento, `iap_active` e le altre impostazioni di licenza restino quelli del telefono.
- Aggiorna `docs/acquisti.md` (sezioni "Le due prove gratuite" e "L'ancora della prova"): dove vive ora la data (database, ancora, backup Drive firmato), cosa succede con backup alterati o vecchi, e i **limiti onesti**: chi non ripristina i dati e reinstalla riparte da 14 giorni; chi usa un altro account o modifica a mano il formato può aggirare la barriera; la difesa forte resta la prova dello store.

## Criteri di accettazione

1. Un backup nuovo contiene `trialAnchor` firmato; il ripristino su una reinstallazione riporta la data di inizio originale (la più antica).
2. Togliere o alterare la data nel backup non concede giorni di prova in più (backup nuovi); i dati si ripristinano comunque.
3. I backup della versione già pubblicata si ripristinano come oggi, senza errori.
4. L'abbonamento e le altre impostazioni di licenza non vengono mai importati dal backup.
5. I backup nuovi sono sempre chiusi in un involucro cifrato e autenticato dall'app (la password dell'utente, se presente, resta lo strato interno); un file alterato non si ripristina; i backup vecchi si ripristinano come oggi.
6. La chiave dell'app per i backup è costante, identificata da un `keyId`, e non dipende da `BH_ANCHOR_SECRET`: cambiare il segreto di build non rende illeggibile nessun backup.
7. Nessuna migrazione del database; `flutter analyze` e `flutter test` verdi; `docs/acquisti.md` e `docs/backup.md` aggiornati con i limiti.
