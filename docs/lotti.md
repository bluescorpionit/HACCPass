# Lotti: stati, archivio e avvisi

Un lotto ha **tre stati** e la sua registrazione **non si cancella mai**:
serve alla rintracciabilità (Reg. CE 178/2002) e al dossier HACCP.

| Stato | Significato | Come si chiude |
| --- | --- | --- |
| **Attivo** | Il lotto è in uso. | — |
| **Terminato** | Consumato o venduto del tutto: fine normale. | Un solo tocco su "Segna come terminato", nessun motivo, nessun avviso. |
| **Ritirato / smaltito** | Tolto dall'uso perché scaduto, alterato, richiamato o altro. | "Ritira / smaltisci": data, motivo (scaduto / alterato / richiamo / altro) e nota (obbligatoria solo per "altro"), quantità smaltita facoltativa. |

## Quando usare cosa

- Il lotto è finito normalmente → **Segna come terminato**. La conferma è
  leggera (snackbar con "Annulla" per qualche secondo): se è stato un
  errore, il lotto torna attivo senza lasciare tracce.
- Il lotto è scaduto, alterato, danneggiato o richiamato → **Ritira /
  smaltisci**. Il foglio preseleziona il motivo "scaduto" quando la
  scadenza è già passata. Con motivo "alterato" o "richiamo" puoi anche
  aprire una **non conformità** già compilata con lotto e prodotto:
  l'NC non viene mai creata in automatico, la confermi tu.
- Hai chiuso un lotto per sbaglio → **Riattiva** (con conferma). La data
  di riattivazione viene annotata nella nota: lo storico non si perde.

## Elenco Lotti

Il filtro in alto ha quattro viste:

- **Attivi** (predefinita): i lotti in uso. Quelli con la scadenza passata
  restano **in testa** con il badge rosso "Scaduto il … — da ritirare":
  l'avviso non si perde.
- **Scaduti**: solo gli attivi con scadenza passata, da ritirare o
  chiudere. Con il pulsante **"Chiudi in blocco"** puoi selezionarne
  più di uno e chiuderli come "terminati" o "ritirati come scaduti",
  sempre con conferma esplicita e anteprima del numero.
- **Archivio**: terminati e ritirati, ordinati per data di chiusura.
  Ogni scheda mostra "Terminato il gg/mm/aaaa" oppure "Ritirato il
  gg/mm/aaaa (motivo)"; è in sola lettura salvo "Riattiva" e
  "Aggiungi nota".
- **Tutti**: tutto l'elenco, con gli stati ben distinguibili.

La ricerca testuale funziona su tutte le viste.

## Avvisi in "Oggi"

Gli avvisi "Lotto scaduto" e "Lotto in scadenza entro 7 giorni" compaiono
**solo per i lotti attivi**: un lotto terminato o ritirato non produce
alcun avviso. Con più di 3 lotti scaduti, "Oggi" mostra un solo avviso
riepilogativo ("N lotti scaduti da gestire") che porta direttamente al
filtro "Scaduti". Toccando l'avviso di un lotto scaduto si apre l'elenco
Lotti con il filtro "Scaduti" già selezionato.

Un lotto risulta scaduto solo **dopo la fine della giornata** della data
di scadenza: un lotto che scade oggi non è scaduto fino alle 23:59.

## Uso come ingrediente e tracciabilità

- Un lotto **scaduto o chiuso non è selezionabile come ingrediente** in un
  nuovo lotto: per i lotti scaduti ancora attivi e per la merce in arrivo
  con scadenza passata l'app mostra "Scaduto il …: non usarlo" e si
  procede solo con il pulsante **"Usa comunque"**, e la scelta viene
  registrata nella nota del lotto. I lotti chiusi non vengono offerti.
- Le ricerche di tracciabilità ("da un lotto agli ingredienti", "da un
  ricevimento ai lotti prodotti") includono **sempre** anche i lotti
  chiusi, con lo stato visibile: l'archivio non toglie nulla alla
  rintracciabilità.

## Dossier PDF

Il dossier e l'export dei lotti riportano **tutti** i lotti del periodo,
anche chiusi, con colonna stato / data di chiusura / motivo (per i
ritirati). I periodi con ritiri hanno una sezione "Lotti ritirati
dall'uso" con data, motivo e nota; i terminati compaiono con stato
"Terminato" nella tabella principale.

## Perché non si cancella

La registrazione di un lotto non viene mai eliminata dall'app: chiusura,
archivio e riattivazione conservano dati e legami con le consegne. Non
esiste alcuna cancellazione automatica di lotti vecchi e la pulizia dello
spazio ("Libera spazio") non tocca mai i lotti attivi né i loro allegati.

> I lotti terminati e ritirati restano nel registro per la
> rintracciabilità. Per quanto tempo conservarli dipende dal tipo di
> prodotto e dalle indicazioni dell'autorità sanitaria: verifica con il
> tuo consulente HACCP o con l'ASL.

## Aggiornamento da versioni precedenti (per chi sviluppa)

- Migrazione del database **v8**, puramente additiva: colonne `status`,
  `closed_at`, `withdrawn_reason`, `closing_note`, `withdrawn_quantity`,
  `closed_by` su `lots`. Nessun dato esistente viene toccato: tutti i
  lotti restano `active`.
- Prima di migrare l'app copia il database in `blue_haccp.db.pre_v8.bak`
  (ultime due copie conservate, rimosse dopo alcuni avvii riusciti, mai
  incluse nei backup Drive). Se la migrazione fallisce, il database resta
  alla versione precedente: l'app mostra un avviso con invito al backup e
  continua a funzionare.
- I backup della versione pubblicata si ripristinano senza errori (i
  lotti risultano `active`); un backup creato da una versione più
  recente viene rifiutato con un messaggio chiaro.
- Test di aggiornamento: `test/fixtures/v7_database.dart` costruisce un
  database sintetico con lo schema della versione pubblicata; i test in
  `test/migration_v8_test.dart` verificano dati identici, stati `active`,
  idempotenza e compatibilità dei backup in entrambe le direzioni.
- Rilascio: build `1.0.2+3` (solo numero di build alzato: identificativi,
  canali di notifica e nome del database invariati). Note di rilascio
  consigliate per Play Console: descrivere stati e archivio e suggerire
  il **lancio graduale** (percentuale crescente), così un problema
  imprevisto dell'aggiornamento non raggiunge subito tutte le
  installazioni.
