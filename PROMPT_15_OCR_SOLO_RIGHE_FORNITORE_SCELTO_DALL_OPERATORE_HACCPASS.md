# PROMPT 15 — OCR dei documenti: fornitore scelto dall'operatore, solo righe, mai lotti/quantità inventati — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Prova reale su una fattura di Carico Cash&Carry (6 articoli, nessun lotto né scadenza stampati): la schermata "Verifica dati letti" ha mostrato **9 righe** invece di 6, con errori gravi: fornitore "ARICO" (manca la C), N. documento vuoto, **codici a barre messi nel campo Lotto** (`8011058180165`, `8015255000516`), **prezzi e importi messi in Quantità** (`14.550`, `29.100`), il peso nel nome (`GR 20`) letto come quantità `20`, il prodotto `04` (codice IVA), righe quasi vuote, e i numeri dell'intestazione (telefono `081 8031774`) diventati Lotto `081` e Quantità `81`. Decisione di prodotto: **il fornitore lo sceglie l'operatore; l'OCR legge solo le righe** (descrizione e, quando è sicura, quantità). **Lotto e scadenza restano vuoti** se sul documento non sono esplicitamente indicati.

Prima di modificare leggi: `lib/services/ocr/{document_parser,document_scan_service,ocr_port,ocr_preprocess}.dart`, `lib/screens/goods/{document_scan_flow,receipts_screen,suppliers_screen,products_screen}.dart`, `docs/ocr.md`, `test/ocr/` e relative fixture. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Il fornitore lo sceglie l'operatore

- Nella schermata "Verifica dati letti" il campo **Fornitore è un selettore** (ricerca nell'elenco fornitori, più "Nuovo fornitore" che apre il modulo vuoto): obbligatorio per salvare. Se la scansione parte dalla scheda di un fornitore o dal "Nuovo ricevimento" con fornitore già scelto, arriva preselezionato.
- L'OCR **non crea, non assegna e non preseleziona** alcun fornitore e non propone nomi letti dal documento (rimuovi `_cleanCompanyName` e la ricerca del ragione sociale dall'output: restano solo come aiuto interno se servono ad altro, mai mostrati come fornitore).
- **P.IVA solo come controllo morbido.** Il documento contiene più P.IVA (fornitore e cliente: qui `03160231217` e `00868120940`): raccogli **tutte** le sequenze di 11 cifre con checksum valida. Se il fornitore scelto ha una P.IVA e **nessuna** di quelle lette coincide, mostra un avviso non bloccante "Il documento non sembra intestato a questo fornitore: controlla di aver scelto quello giusto"; se coincide non mostrare nulla. Non salvare mai automaticamente una P.IVA letta nella scheda fornitore.
- Data documento, tipo (DDT/Fattura) e numero restano **suggerimenti modificabili** (nella prova data e tipo erano corretti). Il numero documento si cerca anche vicino alle etichette "NUMERO DOCUMENTO", "N. DOC.", "DATA E NUMERO DOCUMENTO" (nella prova `93831` compare accanto alla data); se incerto resta vuoto con "Controlla".

## 2. Righe: solo righe vere, riconosciute dalla struttura della tabella

- Individua l'**intestazione** della tabella (parole come `DESCRIZIONE`, `UM`, `QUANTITA'`, `PREZZO`, `IMPORTO`, `COD. IVA`) con i riquadri (`OcrBox`) e ricava per ogni colonna l'intervallo orizzontale. L'area delle righe va **dall'intestazione fino al primo marcatore di fine tabella** (`TOTALE`, `IMPONIBILE`, `IVA`, `DOCUMENTO NON VALIDO`, `NETTO MERCE`, `TRASPORTO`, `ANNOTAZIONI`). Tutto ciò che sta **fuori** da quest'area (indirizzi, telefono, REA, capitale sociale, IBAN, bollini) **non produce righe**.
- Raggruppa i frammenti OCR nella stessa fascia verticale (centro Y vicino) in un'unica riga di tabella, assegnando ogni frammento alla colonna per sovrapposizione orizzontale.
- Una riga è **valida solo se ha una descrizione** (almeno 3 lettere, almeno il 60% di caratteri alfabetici, non una sola sigla/codice). Le righe senza descrizione si **scartano** e non compaiono nella revisione. La descrizione viene dalla colonna `DESCRIZIONE`; ripulisci spazi doppi, e caratteri non alfanumerici all'inizio (es. `*`). Non unire codici a barre né codici IVA alla descrizione.
- Il **codice a barre** (EAN-13/EAN-8/GTIN-14, solo cifre, 8–14 cifre) in colonna `CODICE A BARRE` è un **codice articolo**: non va mai in Lotto. Se il catalogo prodotti ha già un campo codice/barcode usalo per proporre il prodotto già noto; altrimenti mostralo solo come piccola didascalia "Cod. 8003184000172" e non cambiare lo schema del database.
- Se l'intestazione non è riconosciuta, usa il ripiego a righe libere ma con le stesse regole di scarto (nessuna riga senza descrizione, nessuna riga fuori dall'area plausibile) e segna **tutte** le righe "Controlla".

## 3. Quantità: solo se la colonna è certa

- La quantità si legge **solo** dalla colonna intestata `QUANTITA'`/`QUANTITÀ TOTALE`/`Q.TA`/`QTA` (non da `N. COLLI`, non da `QTA x CONF`, non da `PREZZO UNITARIO`, `IMPORTO`, `COD. IVA`, `PREZZO UNITARIO COMPRESO IVA`). Formato italiano `2,00` → 2; sono ammessi decimali con la virgola; l'unità viene dalla colonna `UM` (`PZ`, `KG`, `LT`…).
- **Mai** da pesi/volumi dentro la descrizione (`KG.25`, `GR 20`, `GR 500`, `1 LT`) né da importi con 3 decimali che sembrano quantità (`14,550` è un prezzo unitario).
- Se la colonna non è identificabile o il valore non è un numero plausibile (> 0, < 100000), il campo **resta vuoto**. Un campo vuoto è sempre meglio di un valore sbagliato.

## 4. Lotto e scadenza: vuoti se non scritti

- **Lotto** solo se il testo della riga o del blocco subito sotto contiene un'etichetta esplicita (`LOTTO`, `LOTTO N.`, `LOT`, `L.`, `L:` seguita da un codice alfanumerico) o un **GS1** valido (`(10)` per il lotto, `(17)` per la scadenza, già gestito da `Gs1Data`). Mai da codici solo numerici lunghi (≥ 8 cifre), da numeri di telefono, da codici IVA o da quantità.
- **Scadenza** solo con un'etichetta esplicita (`SCAD.`, `SCADENZA`, `DA CONSUMARSI ENTRO`, `TMC`, `EXP`) e data valida, o GS1 `(17)`. Mai la data del documento riusata come scadenza.
- Se non c'è: **campo bianco**, con suggerimento sotto il campo "Non risulta dal documento: inseriscilo dall'etichetta del prodotto". Se la regola attuale del ricevimento richiede il lotto per salvare, non bloccare in silenzio: evidenzia "Lotto mancante" sulla riga e chiedi conferma esplicita ("Salva senza lotto") **oppure** consenti il salvataggio e mostra le righe senza lotto in un elenco "Da completare" nella tracciabilità (verifica nel codice cosa esiste già e riusa quello).
- Aggiungi (opzionale, ma consigliato) un pulsante accanto al campo Lotto "Leggi dall'etichetta del prodotto" che apre la fotocamera su **una sola etichetta** e riusa `Gs1Data`/OCR solo per lotto e scadenza di **quella riga**. Se il costo è alto, lascialo come voce in `docs/ocr.md` per una versione successiva.

## 5. Schermata di revisione

- Sotto ogni riga una piccola didascalia **"Letto: …"** con il testo OCR originale (aiuta a controllare), eliminabile.
- Righe con confidenza bassa **deselezionate** per default; contatore "6 righe trovate" in cima; pulsanti "Aggiungi riga" e "Elimina riga" (icona cestino); nessuna riga vuota creata dall'app.
- Il pulsante flottante "Continua" **non deve coprire l'ultima riga** (in alto ai tuoi screenshot copre la parte destra delle card): padding di lista con `hasFab: true` in `screenPadding` (≥ 88 dp) e, se serve, sposta "Continua" in una barra inferiore fissa.
- Consiglio di scatto sopra la fotocamera/anteprima: "Tieni il foglio dritto e ben illuminato, inquadra la tabella intera". Se l'immagine è molto inclinata o sfocata, avviso "Foto poco leggibile: rifai lo scatto".
- Messaggi in italiano, tutto resta sul telefono (nessuna rete), nessun dato letto salvato senza conferma dell'operatore.

## 6. Test e fixture (senza dati personali)

- **Non committare la foto reale** della fattura: contiene dati di terze parti (cliente, fornitore, importi). Crea invece una **fixture sintetica** `test/fixtures/ocr/fattura_cash_carry.json` con le righe OCR e i riquadri come li produce ML Kit, riproducendo la struttura (intestazione tabella, 6 righe, colonne `CODICE A BARRE`, `DESCRIZIONE`, `UM`, `N. COLLI`, `QTA x CONF`, `QUANTITA' TOTALE`, `PREZZO UNITARIO`, `SC.`, `IMPORTO`, `COD. IVA`, piè di pagina con totali, telefono e P.IVA nell'intestazione) con nomi e partite IVA **inventati**.
- Risultato atteso sulla fixture: **6 righe**, descrizioni esatte `IMD FARINA PER PIZZA KG.25`, `SORRENTO GIRASOLE ALTOLEICO`, `EDRA FUNGHI PORCINI GR 20`, `AURORA SUPERFICI VERDE 1 LT`, `SMAPIU' BOMBA LAVASTOVIGLIE`, `LIEVITO PER PIZZA GR 500`; quantità `2, 1, 1, 1, 2, 1`; lotto e scadenza **vuoti** su tutte; data `01/10/2026`; tipo Fattura; nessun fornitore assegnato; nessuna riga dall'intestazione o dal piè di pagina.
- Test mirati: un codice a barre non diventa mai lotto; `14,550`, `29,100` e `GR 20` non diventano quantità; il telefono dell'intestazione non produce righe; riga senza descrizione scartata; descrizione con `*` iniziale ripulita; DDT con `LOTTO: L2310A` e `SCAD. 15/11/2026` → letti correttamente; GS1 `(10)`/`(17)` letti; più P.IVA nel documento con una sola coincidente → nessun avviso; nessuna coincidente → avviso; la scelta del fornitore è obbligatoria per salvare; intestazione non riconosciuta → ripiego con tutte le righe "Controlla".
- Aggiorna `docs/ocr.md`: cosa legge l'OCR (righe, date, numero), cosa **non** legge (fornitore, lotto/scadenza se non esplicitamente scritti), come scattare la foto, limiti dell'OCR su foto inclinate, test manuali con 3 documenti reali (da non committare).

## Criteri di accettazione

1. Il fornitore si sceglie sempre dall'elenco (o "Nuovo"); l'OCR non lo crea né lo preseleziona; avviso morbido se la P.IVA del documento non coincide.
2. Sul documento di prova la revisione mostra esattamente 6 righe con le descrizioni corrette.
3. Nessun codice a barre, prezzo, importo, peso o numero di telefono finisce in Lotto o Quantità; senza etichetta esplicita Lotto e Scadenza restano vuoti.
4. La quantità compare solo se letta dalla colonna "Quantità totale"; altrimenti vuota.
5. Il pulsante "Continua" non copre le righe; ogni riga ha "Letto: …", eliminazione e aggiunta.
6. Nessuna foto o dato reale nei test; `docs/ocr.md` aggiornato; `flutter analyze` e `flutter test` verdi.
