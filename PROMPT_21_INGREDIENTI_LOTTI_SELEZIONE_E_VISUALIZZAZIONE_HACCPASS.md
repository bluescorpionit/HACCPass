# PROMPT 21 — Lotti di produzione: scelta e visualizzazione degli ingredienti con i loro lotti — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Segnalazione di un cliente (app in produzione): in "Lotti e produzione" non si vedono **tutti** gli ingredienti con i relativi lotti. Dal codice (`lib/screens/lots_screen.dart`) le cause sono quattro:

1. **Limite silenzioso a 12:** nella scheda "Nuovo lotto" l'elenco ingredienti è `usableReceipts.take(12)` (~riga 467). Se ci sono più di 12 consegne nei giorni considerati, le altre **non compaiono** e non c'è modo di vederle.
2. **Finestra fissa di 60 giorni:** `repository.getUsableReceipts()` (`haccp_repository.dart` ~riga 822) prende solo le consegne degli ultimi 60 giorni. Merce con durata lunga (farina, surgelati, conserve) consegnata prima non è selezionabile, anche se ancora in uso.
3. **Etichette ambigue:** ogni scelta è una "chip" con solo `prodotto (lotto fornitore)`: se il lotto manca resta solo il nome (es. "Zucchine"), e prodotti con lo stesso nome (es. due "Patate Fresche") non si distinguono per fornitore, data di consegna o scadenza.
4. **Nella scheda del lotto** (~riga 704) gli ingredienti sono una sola riga di testo `nome (fornitore); nome (fornitore)…`: **non mostra il lotto del fornitore** (`supplierLot`), che è proprio il dato di tracciabilità, e con molti ingredienti la riga è illeggibile.

Vincolo prioritario: **l'app è in produzione**. Gli unici cambi ammessi allo schema sono quelli **additivi** del punto 0 (colonne nuove su `receipts`, con la stessa procedura sicura della migrazione V8 dei lotti); per il resto solo interfaccia e lettura dei dati. I lotti già salvati (con `LotIngredient`) devono continuare a funzionare e a vedersi (anche se `supplierLot` è vuoto). Se una scelta richiede di riscrivere o cancellare dati esistenti, scegli l'alternativa che non li tocca.

**Stato del codice (verificato):** il Prompt 19 è già applicato ai lotti di produzione (migrazione V8 con `status`, `closed_at`, `withdrawn_reason`, `closing_note`, `withdrawn_quantity`, `closed_by` su `lots`; `LotStatus` in `haccp_models.dart`; metodi di chiusura/ritiro/riattivazione nel repository; `docs/lotti.md`). Le **consegne** (`receipts`) invece hanno solo `outcome` (`accepted`/rifiutata): non hanno stati "terminata" né "ritirata", quindi una consegna finita da tempo resta nell'elenco ingredienti finché rientra nel periodo.

## 0. Stati delle consegne (merce in ingresso): terminata e ritirata

Decisione di prodotto: le consegne hanno gli **stessi tre stati** dei lotti di produzione, con lo stesso significato e la stessa regola "la registrazione non si cancella mai": **Attiva**, **Terminata** (merce finita, un tocco, nessun motivo) e **Ritirata/smaltita** (scaduta, alterata, richiamo, altro; con data, motivo, nota). Le consegne terminate o ritirate **non compaiono nel selettore degli ingredienti** (default), ma restano nel registro e nella tracciabilità.

- **Schema (additivo, V9):** riusa **esattamente** il meccanismo della migrazione V8 (`_addColumn` idempotente, transazione, copia di sicurezza prima di migrare, stessa gestione degli errori). Colonne su `receipts`: `status` TEXT default `'active'` (`active` | `finished` | `withdrawn`), `closed_at` TEXT, `withdrawn_reason` TEXT (`expired`/`damaged`/`recall`/`other`), `closing_note` TEXT, `closed_by` TEXT. **Niente** DROP/RENAME/UPDATE massivi: tutte le consegne esistenti diventano `active`. Aumenta la versione del database di uno rispetto a quella corrente; **non riusare** i nomi di colonna con significati diversi. Non confondere `status` con `outcome` (che resta com'è: accettata/rifiutata).
- **Modello e repository:** `Receipt` con i nuovi campi e `isActive`/`isFinished`/`isWithdrawn`/`isClosed`; metodi per terminare, ritirare e riattivare una consegna (stesso stile di quelli dei lotti), senza toccare gli altri metodi. Il backup e il ripristino includono i nuovi campi; un backup vecchio si ripristina senza errori (consegne `active`).
- **Azioni sulla consegna** nella schermata del carico merce (`receipts_screen.dart`) con la regola di progetto sui pulsanti (`ActionButtonRow`): **"Segna come terminata"** (un tocco, snackbar con "Annulla") e **"Ritira / smaltisci"** (foglio con motivo, nota, data), più "Riattiva" per correggere. Filtri nell'elenco consegne: **Attive** (predefinito) · **Archivio** (terminate/ritirate) · **Tutte**. Le consegne con scadenza passata ancora attive hanno il badge "Scaduta il … — da ritirare".
- **Tracciabilità sempre intatta:** un lotto di produzione già salvato continua a mostrare i suoi ingredienti anche se la consegna viene poi terminata o ritirata. La ricerca di tracciabilità (da una consegna ai lotti che l'hanno usata) include **anche** le consegne chiuse; una consegna ritirata per richiamo deve permettere di vedere quali lotti l'hanno usata.
- **Avvisi in "Oggi":** una consegna scaduta e ancora attiva può produrre l'avviso riepilogativo (stessa logica del Prompt 19); chiusa, nessun avviso. Se oggi non esiste un avviso per le consegne scadute, **non aggiungerlo** in questo prompt (fuori ambito).
- **Chiusura in blocco** dal filtro delle consegne scadute attive, con conferma esplicita e anteprima (come per i lotti). Mai chiusure automatiche.

Prima di modificare leggi: `lib/screens/lots_screen.dart` (`_newLot`, `_LotCard`, `_copyAttachmentsFromReceipts`), `lib/models/haccp_models.dart` (`Receipt`, `LotIngredient`, `ProductionLot`), `lib/repositories/haccp_repository.dart` (`getUsableReceipts`, `getReceipts`, `getLots`, salvataggio lotti), `lib/widgets/common_widgets.dart` (`FilterChipX`, `ChoiceRow`, `ActionButtonRow`, `screenPadding`), `docs/qa_layout.md`, i test sui lotti. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`. Rispetta le regole di progetto: nessun overflow a 360 dp e scala testo 1.15, nessuna etichetta tagliata o verticale, pulsanti orizzontali (`ActionButtonRow`), padding con `screenPadding`.

## 1. Scelta degli ingredienti nel "Nuovo lotto"

Sostituisci la nuvola di chip con un **selettore a elenco** (riusa il foglio modale esistente; nessuna nuova dipendenza):

- Nel modulo del lotto, sezione "Ingredienti": un riquadro con il **riepilogo degli ingredienti scelti** (righe compatte, vedi punto 2) e un pulsante **"Aggiungi ingredienti"** (e "Modifica" se ce ne sono). Il conteggio: "3 ingredienti scelti".
- "Aggiungi ingredienti" apre un foglio a schermo quasi intero con:
  - **Campo di ricerca** (prodotto, fornitore, lotto del fornitore) con risultati istantanei.
  - **Periodo**: `SegmentedButton` "60 giorni" (predefinito) · "6 mesi" · "Tutte". Così la merce consegnata prima resta selezionabile. Nessun limite al numero di righe: l'elenco scorre (`ListView.builder`), **mai** `take(n)`.
  - **Elenco di righe**, una per consegna, più recenti prima, ognuna con: nome del prodotto in evidenza; sotto, in piccolo: **fornitore**, **lotto fornitore** (se manca: "senza lotto" in grigio), **consegna del gg/mm/aaaa**, **scadenza** (se il dato esiste nel modello `Receipt`: riga rossa "Scaduto il …" se passata; arancione se entro 7 giorni), quantità e unità se disponibili. Casella di selezione a sinistra, intera riga toccabile. Le righe selezionate restano evidenziate.
  - **Raggruppamento per prodotto** (opzionale ma consigliato): intestazione con il nome del prodotto e, sotto, le sue consegne/lotti, così "Patate Fresche" ha una sola intestazione con due lotti distinti ben riconoscibili. Se complica troppo il codice, mantieni l'elenco piatto ordinato per data con prodotto e lotto sempre visibili.
  - **Consegne terminate o ritirate: nascoste.** Il selettore mostra solo le consegne `active` (e mai quelle con esito "rifiutata"). Un interruttore "Mostra anche terminate e ritirate", **spento** di default, le fa comparire attenuate e con il badge dello stato, solo per correggere errori; scegliere una consegna ritirata richiede la stessa conferma esplicita degli altri casi sconsigliati.
  - **Filtro rapido** "Solo non scaduti" (attivo di default) e un interruttore "Mostra anche scaduti"; le consegne scadute si possono comunque scegliere **solo dopo** un avviso "Scaduto il …: non usarlo", con conferma esplicita (comportamento coerente con il Prompt 19, se già applicato; altrimenti avviso semplice).
  - In basso, barra fissa con "N scelti" e pulsante **"Fatto"** (sempre visibile, non coperto dalla barra di sistema: `screenPadding`/inset). Il foglio non perde la selezione se si chiude e si riapre.
  - Se non ci sono consegne nel periodo scelto: messaggio "Nessuna consegna in questo periodo" con il pulsante per passare a "6 mesi/Tutte"; se non esiste alcuna consegna: "Nessuna consegna registrata" con il pulsante "Registra una consegna" che porta alla schermata di carico merce se esiste un percorso semplice.
- Il campo "Ingrediente libero (facoltativo)" resta, ma si **può aggiungere più di un ingrediente libero** (campo + pulsante "+" che accumula righe nel riepilogo, ciascuna con nome e lotto/note facoltativi). I liberi si salvano come `LotIngredient` senza `receiptId`, come oggi.
- L'azione "Copia gli allegati dal carico" resta e continua a funzionare sugli ingredienti scelti.

## 2. Riepilogo ingredienti nel modulo e nella scheda del lotto

- **Modulo "Nuovo lotto":** sotto "Ingredienti" una riga per ingrediente scelto: **nome**, e sotto "Fornitore · Lotto X · consegna gg/mm/aaaa · scad. gg/mm/aaaa" (le parti mancanti si omettono; lotto mancante = "senza lotto"), con icona per rimuoverlo. Nessuna riga tagliata: testo a capo, mai ellissi sui campi di tracciabilità (nome, lotto).
- **Scheda del lotto (`_LotCard`)**, al posto della riga unica `Ingredienti: a (f); b (f)`: una sezione "Ingredienti (N)" con **una riga per ingrediente**: nome, fornitore e **lotto del fornitore** (`supplierLot`), più la data di consegna e la scadenza dove sono note (dal ricevimento collegato `receiptId`). Con più di 4 ingredienti mostra i primi 4 e un pulsante "Mostra tutti (N)" che li espande; **nessun ingrediente va perso** né nella scheda né nel dossier.
- **Dettaglio/espansione:** se esiste una vista di dettaglio del lotto, usa lo stesso componente per le righe ingrediente (un widget unico `LotIngredientTile`, riusato in tutti i punti, con test widget).
- Per i lotti **già salvati** con `supplierLot` vuoto mostra "senza lotto" (non nascondere la riga), e per gli ingredienti liberi mostra solo il nome.

## 3. Dossier PDF e registri

Controlla in `lib/services/pdf_service.dart` (e negli export) come vengono stampati gli ingredienti dei lotti: devono comparire **tutti** gli ingredienti con **fornitore e lotto del fornitore**, uno per riga, senza troncamenti. Correggi solo se oggi manca il lotto del fornitore o se un limite li taglia; nessun cambiamento ai dati salvati.

## 4. Prestazioni

Il foglio deve restare fluido con centinaia di consegne: carica le consegne una volta (`getReceipts` con il periodo scelto, non solo `getUsableReceipts`; aggiungi al repository un metodo di lettura con parametro periodo, **senza** cambiare quelli esistenti per non toccare altre schermate), usa `ListView.builder` e filtra in memoria.

## 5. Test e documentazione

- Test widget: con 30 consegne il foglio le mostra **tutte** (scorrendo) e il conteggio dei risultati è corretto; la ricerca per prodotto, fornitore e lotto filtra; il periodo "6 mesi/Tutte" aggiunge consegne più vecchie; due "Patate Fresche" con lotti diversi sono distinguibili (lotto, fornitore, data visibili); le consegne scadute sono segnalate e non selezionabili senza conferma; la selezione resta chiudendo e riaprendo il foglio; il lotto salvato contiene tutti gli ingredienti scelti (ricevimenti + liberi).
- Test widget della scheda lotto: con 7 ingredienti mostra 4 + "Mostra tutti (7)", espandendo li mostra tutti con lotto del fornitore; un lotto vecchio con `supplierLot` vuoto mostra "senza lotto"; nessun overflow a 360 dp e scala 1.15.
- Test di regressione: un lotto già salvato con il vecchio schema di ingredienti si apre e si vede senza errori.
- Aggiorna `docs/lotti.md` (o crea il file) e `docs/qa_layout.md`: come si scelgono gli ingredienti, periodo e filtri, cosa mostra la scheda lotto, e la checklist manuale con 20+ consegne e 360 dp.

## Criteri di accettazione

1. Nel "Nuovo lotto" si possono scegliere **tutte** le consegne (nessun limite a 12), cercando e filtrando per periodo (60 giorni, 6 mesi, tutte).
2. Ogni consegna nell'elenco mostra prodotto, fornitore, lotto del fornitore (o "senza lotto"), data di consegna e scadenza dove nota: due prodotti con lo stesso nome si distinguono.
3. Il lotto salvato conserva tutti gli ingredienti scelti, più di un ingrediente libero è possibile.
4. La scheda del lotto elenca gli ingredienti **uno per riga, con il lotto del fornitore**, e permette di vederli tutti; il dossier PDF li riporta tutti con il lotto.
5. Le consegne **terminate o ritirate non compaiono** nel selettore degli ingredienti (salvo l'interruttore dedicato); restano nel registro, nell'archivio delle consegne e nella tracciabilità, e i lotti già salvati continuano a mostrare i loro ingredienti.
6. Le consegne hanno stati attiva/terminata/ritirata con azioni e filtri analoghi ai lotti di produzione; nessuna consegna viene chiusa in automatico.
7. L'unica modifica allo schema è la migrazione additiva V9 su `receipts` (stessa procedura della V8, con copia di sicurezza); tutte le consegne esistenti restano attive; i backup vecchi si ripristinano; i lotti già salvati si vedono correttamente.
8. Nessun overflow a 360 dp/scala 1.15; `flutter analyze` e `flutter test` verdi; `docs/lotti.md` e `docs/qa_layout.md` aggiornati.
