# PROMPT 19 — Lotti: stati "Terminato" e "Ritirato/smaltito", archivio e avvisi corretti — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Problema: un lotto resta per sempre nell'elenco Lotti e, quando la scadenza passa, genera in "Oggi" un avviso rosso fisso ("Lotto scaduto: … ritirare ed eliminare", `haccp_repository.dart` ~riga 1391), **anche se il lotto è stato consumato per intero prima della scadenza**. Non esiste modo di registrare che un lotto è finito normalmente né che è stato ritirato e smaltito: l'avviso non sparisce mai e "Oggi" si riempie di lotti vecchi.

Decisione di prodotto: un lotto ha **tre stati** con significati diversi, e **la sua registrazione non si cancella mai** (serve alla rintracciabilità e al dossier):

- **Attivo**: il lotto è in uso.
- **Terminato**: consumato o venduto del tutto, fine normale. Un solo tocco, nessun motivo da compilare, nessun avviso.
- **Ritirato / smaltito**: tolto dall'uso perché scaduto, alterato, richiamato o altro. Serve data, motivo e nota.

Prima di modificare leggi: `lib/models/haccp_models.dart` (`ProductionLot`, `LotIngredient`), `lib/core/database/app_database.dart` (schema `lots`, `_addColumn`, versione e migrazioni), `lib/repositories/haccp_repository.dart` (`getLots` ~883, `saveLot`, `getTodos` ~1391, ricerche di lotti per ricevimento ~919/949), `lib/screens/lots_screen.dart` (`_LotCard`, elenco, `_newLot`), `lib/screens/goods/receipts_screen.dart`, i punti dove i lotti entrano nel dossier PDF (`lib/services/pdf_service.dart`), `backup_service.dart`, `restore_service.dart`, `docs/`. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 0. L'app è già in produzione: nessuna installazione deve rompersi (vincolo prioritario)

Esistono installazioni reali con dati veri. Ogni scelta di questo prompt è subordinata a questo vincolo:

- **Solo modifiche additive allo schema.** Aggiungi colonne nullable o con valore di default; **mai** `DROP`, `RENAME`, ricreazione o svuotamento di tabelle, mai `DELETE`/`UPDATE` massivi sui dati esistenti, mai cambiare tipo o significato di colonne esistenti. Non toccare la logica degli altri registri.
- **Migrazione idempotente e sicura.** Aumenta la versione del database di **uno** rispetto a quella pubblicata; ogni `ALTER TABLE ... ADD COLUMN` va protetto controllando prima con `PRAGMA table_info('lots')` che la colonna non esista già (si riusa `_addColumn` solo se già fa questo controllo, altrimenti correggilo senza cambiarne il comportamento per le migrazioni passate). Esegui la migrazione in una transazione; se fallisce, il database resta alla versione precedente e l'app **non va in crash**: mostra un messaggio chiaro con invito a fare un backup, e continua a funzionare in sola lettura se possibile.
- **Copia di sicurezza prima di migrare.** Alla prima apertura dopo l'aggiornamento, prima di applicare la migrazione, copia il file del database (nome storico `blue_haccp.db`) in una copia di sicurezza nella cartella privata dell'app (es. `blue_haccp.db.pre_v<N>.bak`), tenendo solo le ultime due; la copia non va nei backup Drive e viene rimossa dopo alcuni avvii riusciti. Se la copia fallisce per mancanza di spazio, procedi solo se la migrazione è puramente additiva (lo è) e registra l'avviso nei log.
- **Tutti i valori esistenti restano com'erano.** I lotti presenti diventano `active` esattamente come oggi: nessun lotto passa da solo a "terminato" o "ritirato", nessun dato viene riscritto. Il comportamento dell'app per chi non usa le nuove azioni resta identico, salvo i due avvisi nuovi (punto 4).
- **Compatibilità dei backup in entrambe le direzioni.**
  - Un backup creato dalla versione **pubblicata** (senza i nuovi campi) si ripristina nella versione nuova senza errori: i lotti risultano `active`.
  - Un backup creato dalla versione **nuova** deve poter essere letto da `restore_service.dart` sulla stessa versione; verifica cosa fa il ripristino con colonne sconosciute e con una `schemaVersion` più recente di quella dell'app: **mai** crash né perdita silenziosa, ma un messaggio chiaro ("Il backup è stato creato da una versione più recente di HACCPass: aggiorna l'app").
  - Il formato di export/backup non cambia la sua struttura per i dati esistenti: i nuovi campi si **aggiungono** e si ignorano se assenti.
- **Primo avvio dopo l'aggiornamento, utenti con molti lotti scaduti.** Le installazioni reali probabilmente hanno già molti lotti con la scadenza passata e mai chiusi: al primo avvio comparirebbero tutti come "da gestire". Per evitare un muro di avvisi: usa l'avviso riepilogativo ("N lotti scaduti da gestire") e aggiungi nel filtro "Scaduti" l'azione **"Chiudi in blocco"** con selezione multipla e scelta tra "Segna come terminati" e "Ritira come scaduti", **sempre con conferma esplicita** e anteprima del numero di lotti; nessuna chiusura automatica.
- **Aggiornamento e rilascio.** Alza il numero di build in `pubspec.yaml` (`+N`), non cambiare identificativi, id canali notifiche né nome del file database. Suggerisci nelle note di rilascio il **lancio graduale** in Play Console (percentuale crescente), così un problema imprevisto non raggiunge subito tutti.
- **Test obbligatori di aggiornamento.** Conserva in `test/fixtures/` un database **sintetico** con lo schema della versione pubblicata e alcuni lotti (attivi, scaduti, con ingredienti collegati a ricevimenti): un test apre quel database con il codice nuovo, esegue la migrazione e verifica che (a) i dati siano identici, (b) i lotti siano `active`, (c) tracciabilità, dossier e avvisi funzionino, (d) la migrazione sia idempotente (eseguita due volte non cambia nulla). Test del ripristino di un backup della versione pubblicata. Nessun dato reale di clienti nei test.
- Se per qualsiasi punto del prompt la soluzione più semplice richiede di toccare dati esistenti o di rendere incompatibile un backup, **fermati e scegli l'alternativa additiva**.

## 1. Stato del lotto (schema e modello)

- Nuove colonne in `lots` con migrazione additiva (non rompere database e backup esistenti; aumenta la versione dello schema e usa `_addColumn`):
  - `status` TEXT, default `'active'` (valori: `active`, `finished`, `withdrawn`);
  - `closed_at` TEXT (ISO 8601, nullable): data/ora di chiusura, per `finished` e `withdrawn`;
  - `withdrawn_reason` TEXT (nullable, solo per `withdrawn`): `expired` (scaduto), `damaged` (alterato/danneggiato), `recall` (richiamo), `other` (altro, con nota);
  - `closing_note` TEXT (nullable): nota libera per entrambi gli stati;
  - `withdrawn_quantity` TEXT (nullable): quantità smaltita, opzionale, solo per `withdrawn`;
  - `closed_by` TEXT (nullable): nome operatore se l'app ha già il concetto di operatore, altrimenti vuoto.
- `ProductionLot`: aggiungi i campi e le proprietà derivate `isActive`, `isFinished`, `isWithdrawn`, `isClosed` (finito o ritirato), `isExpired` (scadenza passata **a fine giornata della data di scadenza**: un lotto che scade oggi non è scaduto fino alle 23:59 locali) e `isExpiringSoon` (entro 7 giorni). `isExpired` e `isExpiringSoon` valgono **solo per i lotti `active`**: un lotto chiuso non è mai "scaduto" ai fini degli avvisi.
- Tutti i lotti esistenti diventano `active` dopo la migrazione. **Nessuna riga viene cancellata** dalla migrazione né dal codice nuovo.
- Backup e ripristino includono i nuovi campi; un backup vecchio (senza i campi) si ripristina senza errori e i lotti risultano `active`.

## 2. Azioni sul lotto

Nella scheda del lotto (`_LotCard`) e nel suo dettaglio, per i lotti `active` (con la regola di progetto sui pulsanti: `ActionButtonRow`, mai testo verticale):

- **"Segna come terminato"** (azione principale, in primo piano). Un solo tocco con una conferma leggera (snackbar con "Annulla" per qualche secondo, oppure dialog minimo): salva `finished`, `closed_at = adesso`. Nessun foglio con motivi. Facoltativa la nota, richiedibile con un'azione secondaria "Aggiungi nota", mai obbligatoria.
- **"Ritira / smaltisci"** (azione secondaria). Apre un foglio con: motivo (scaduto/alterato/richiamo/altro; **preselezionato "scaduto"** se la scadenza è passata), quantità smaltita **opzionale**, nota libera (obbligatoria solo per "altro"), data/ora (default adesso, modificabile), conferma "Ritira lotto". Testo: "Il lotto resta nel registro ma non sarà più usabile".
- Per i lotti **già scaduti e ancora attivi** i pulsanti sono gli stessi, ma "Ritira / smaltisci" è evidenziato come azione consigliata (badge rosso "Scaduto il gg/mm/aaaa — da ritirare"); "Segna come terminato" resta disponibile (es. il lotto era finito e nessuno lo aveva registrato).
- **Riattiva** (per `finished` e `withdrawn`, con conferma): riporta il lotto a `active` per correggere un errore, annotando la data di riattivazione nella nota; lo storico non va perso.
- **Nessuna eliminazione** per i lotti collegati a ingredienti o a legami di tracciabilità. Se oggi l'app permette di cancellare un lotto già usato, chiedi conferma rafforzata ("Cancellare un lotto elimina la rintracciabilità: di solito conviene segnarlo come terminato o ritirarlo") e proponi "Terminato"/"Ritira" come azioni principali. L'eliminazione resta possibile solo per un lotto creato per errore e senza legami.
- Opzionale ma consigliato: nel foglio di ritiro con motivo "alterato" o "richiamo" offri il pulsante secondario **"Segnala non conformità"**, che apre il modulo di nuova NC già compilato con lotto e prodotto (usa la schermata e il repository NC esistenti, senza duplicare logica). **Nessuna NC viene creata in automatico.**

## 3. Elenco Lotti: filtri e archivio

- Filtro in alto (`SegmentedButton`): **Attivi** · **Scaduti** · **Archivio** · **Tutti**.
  - **Attivi** (predefinito): lotti `active`. I lotti `active` con scadenza passata **restano visibili e in testa**, con il badge rosso "Scaduto il … — da ritirare", altrimenti l'avviso si perde.
  - **Scaduti**: solo `active` con scadenza passata (da ritirare o chiudere).
  - **Archivio**: `finished` e `withdrawn`, ordinati per data di chiusura (più recenti prima). Sotto-filtro opzionale "Terminati / Ritirati". Ogni scheda mostra "Terminato il gg/mm/aaaa" oppure "Ritirato il gg/mm/aaaa (motivo)", ed è in sola lettura salvo "Riattiva".
  - **Tutti**: tutto, con gli stati ben distinguibili.
- Contatori nei filtri (es. "Scaduti (3)"). La ricerca testuale esistente resta valida su tutti i filtri.
- Stile: i lotti chiusi sono attenuati; "Terminato" con icona neutra/verde spenta, "Ritirato" con icona di avviso; colori accessibili (non solo il colore: sempre anche testo).

## 4. Avvisi in "Oggi" (`getTodos`)

- Gli avvisi "Lotto scaduto" e "Lotto in scadenza entro 7 giorni" compaiono **solo per i lotti `active`**. Un lotto terminato o ritirato non produce **alcun** avviso.
- L'avviso rosso scaduto dice: "Scaduto il …: ritirare dall'uso e registrarlo (o segnarlo come terminato)", con `target: 'lots'` e il filtro "Scaduti" preselezionato (passalo nella navigazione).
- Più di 3 lotti scaduti attivi: **un solo avviso riepilogativo** ("5 lotti scaduti da gestire") invece di una riga per lotto.
- Una volta chiuso, il lotto sparisce da "Oggi".

## 5. Uso come ingrediente e tracciabilità

- Un lotto **scaduto o chiuso (terminato/ritirato) non è selezionabile come ingrediente** in un nuovo lotto: per i lotti scaduti attivi e per la merce in ingresso con scadenza passata mostra un avviso "Scaduto il …: non usarlo", con possibilità di proseguire solo con conferma esplicita ("Usa comunque") registrata nella nota; per i lotti chiusi non offrire la scelta. Scegli l'approccio più semplice nel codice esistente e documentalo.
- Le ricerche di tracciabilità ("da un lotto agli ingredienti", "da un ricevimento ai lotti", ~919/949) includono **anche** i lotti chiusi, con lo stato visibile: la tracciabilità non deve perdere i lotti archiviati.

## 6. Dossier PDF e registri

- Il dossier PDF e gli export dei lotti riportano **tutti** i lotti del periodo, anche chiusi, con colonne stato / data chiusura / motivo (per i ritirati). Per i periodi che li contengono aggiungi una piccola sezione "Lotti ritirati dall'uso" con data, motivo e nota; i lotti terminati compaiono con stato "Terminato" nella tabella principale, senza sezione dedicata.
- Non cambiare gli altri registri.

## 7. Conservazione (testo, non cancellazioni)

- **Non implementare cancellazioni automatiche** di lotti vecchi. Nella guida dell'app e in `docs/lotti.md` scrivi una nota sobria: "I lotti terminati e ritirati restano nel registro per la rintracciabilità. Per quanto tempo conservarli dipende dal tipo di prodotto e dalle indicazioni dell'autorità sanitaria: verifica con il tuo consulente HACCP o con l'ASL." Nessun numero di anni scritto come obbligo di legge.
- Se esiste una funzione di pulizia dello spazio (`attachment_storage_screen.dart`), verifica che **non tocchi mai i lotti**, né gli allegati di lotti attivi (regola già presente ~riga 378: mantienila); gli allegati dei lotti chiusi si possono ripulire solo con conferma esplicita.

## 8. Test e documentazione

- Test unitari: migrazione da schema vecchio → lotti `active`; `isExpired` il giorno stesso della scadenza (non scaduto) e il giorno dopo (scaduto); `isExpired`/`isExpiringSoon` falsi per lotti chiusi; "Terminato" salva `finished` e `closed_at` senza motivo; "Ritira" salva motivo/data/nota/quantità; riattivazione; `getTodos` non genera avvisi per lotti chiusi e genera l'avviso riepilogativo oltre 3 scaduti attivi; filtri Attivi/Scaduti/Archivio/Tutti; la ricerca di tracciabilità include i chiusi; backup → ripristino conserva stati e motivi; ripristino di un backup vecchio senza i nuovi campi.
- Test widget: la scheda di un lotto attivo mostra "Segna come terminato" e "Ritira / smaltisci" in orizzontale senza overflow a 360 dp e scala testo 1.15; il lotto scaduto mostra il badge e l'azione consigliata; dopo "Segna come terminato" il lotto passa in "Archivio" (con "Annulla" funzionante) e sparisce da "Oggi"; dopo "Ritira" lo stesso, con motivo e data visibili.
- `docs/lotti.md` (nuovo o aggiornato): i tre stati e quando usarli, ritiro, archivio, perché non si cancella, dossier, avvisi.

## Criteri di accettazione

1. Un lotto attivo con scadenza passata resta visibile nell'elenco Lotti (filtro "Scaduti") e genera avviso in "Oggi"; dopo "Segna come terminato" o "Ritira / smaltisci" l'avviso sparisce.
2. "Segna come terminato" richiede un solo tocco e nessun motivo; "Ritira / smaltisci" registra data, motivo e nota.
3. I lotti terminati e ritirati restano nel registro (filtro "Archivio"), con stato distinguibile, e sono riattivabili.
4. Nessun lotto viene cancellato né cambiato di stato automaticamente; l'aggiornamento di un'installazione esistente conserva tutti i dati, la migrazione è additiva e idempotente, con copia di sicurezza prima di migrare; il ripristino di backup della versione pubblicata funziona (test con database sintetico della versione pubblicata).
5. I lotti scaduti o chiusi non si usano come ingredienti senza un avviso esplicito; la tracciabilità li include sempre.
6. Il dossier PDF include anche i lotti chiusi con stato e motivo.
7. Nessun obbligo di legge inventato nei testi; `flutter analyze` e `flutter test` verdi; `docs/lotti.md` aggiornato.
