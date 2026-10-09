# PROMPT 16 — Pulsanti scheda lotto, form stampante generica, stampa ESC/POS di rete selezione prodotto a tendina nel nuovo lotto — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Tre difetti visti sul telefono: **(C)** la stampa su stampante generica ESC/POS di rete (porta 9100) **non esce** (§7, prioritario: è un difetto funzionale); altre due modifiche di interfaccia: **(D)** nel foglio "Nuovo lotto di produzione" la scelta del prodotto con chip va sostituita da un menu a tendina con creazione del prodotto al volo (§8); e due di layout: **(A)** scheda lotto con pulsanti a testo verticale (§1–§5); **(B)** form della stampante generica con overflow e campi sovrapposti (§6). Per (A): nella schermata **Lotti e produzione** la scheda di ogni lotto ha tre pulsanti "Stampa", "Etichetta", "Rintraccio" più l'icona graffetta nella stessa `Row` (`lib/screens/lots_screen.dart`, ~righe 464–505). Sul telefono ognuno dei tre pulsanti riceve circa 90 dp: con icona + padding del tema (`minimumSize: Size(64, 54)` in `app_theme.dart`) resta pochissimo spazio per il testo e le etichette vanno a capo **una lettera per riga**, i pulsanti diventano altissimi e la scheda è inutilizzabile. Obiettivo: i pulsanti restano **in orizzontale, tutti uguali e bassi**, leggibili a 320–412 dp e a scala testo 1.15, senza mai spezzare le parole.

Prima di modificare leggi: `lib/screens/lots_screen.dart` (`_LotCard`, `_PdfPreview` in fondo al file), `lib/widgets/common_widgets.dart`, `lib/core/theme/app_theme.dart` (pulsanti, righe ~295–335), `docs/qa_layout.md`. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Nuovo componente: riga di azioni compatte

Crea in `lib/widgets/common_widgets.dart` (o file dedicato) un widget riutilizzabile `ActionButtonRow`:

- Input: lista di `ActionButtonData` (`icon`, `label`, `onPressed`, `tooltip`, facoltativo `badge`).
- Layout: **una riga orizzontale** con N pulsanti di **larghezza uguale** (`Expanded`), spazio fisso di 8 dp, altezza fissa **56 dp**, bordo e raggio coerenti con i pulsanti Outlined del tema.
- Ogni pulsante è **icona sopra e testo sotto** (colonna centrata): icona 22 dp, testo `labelMedium` (≈ 12–13 sp), `maxLines: 1`, `softWrap: false`, `overflow: TextOverflow.ellipsis` dentro `FittedBox(fit: BoxFit.scaleDown)` così a scala 1.15 il testo si riduce invece di andare a capo; padding orizzontale 4 dp. Area tappabile ≥ 48 dp. Mai testo spezzato a metà parola.
- Regola di adattamento: se la larghezza per pulsante scende sotto **72 dp** (schermi molto stretti o molti pulsanti) il widget passa a una griglia a **due colonne** (`Wrap` con larghezza metà), sempre pulsanti uguali; non crea mai scorrimento orizzontale né overflow.
- Accessibilità: `Semantics(button: true, label: …)` e tooltip lunghi per ogni azione.

## 2. Scheda lotto

- In `_LotCard` sostituisci la `Row` dei tre `OutlinedButton.icon` + `IconButton.outlined` con `ActionButtonRow` a **quattro azioni uguali**: **Stampa** (stampante), **Etichetta** (QR), **Rintraccio** (albero), **Allegati** (graffetta; il testo "Allegati" sostituisce il solo icona, il tooltip "Foto e allegati" resta). Stesse azioni e comportamenti di oggi (`_printLabel`, `_showLabel`, `_showTraceability`, `showAttachmentsSheet`): non cambia la logica.
- Se hai già l'indicatore di allegati presenti (numero foto), mostralo come piccolo badge sull'icona Allegati, non come testo extra.
- Verifica che il titolo del lotto e il codice (`L261009-AFF-1705`) in cima alla card non si sovrappongano: titolo con `maxLines: 2` ed ellissi, codice su una riga con `softWrap: false`; se non entrano insieme, il codice va sotto il titolo.
- Il pulsante flottante "Nuovo lotto" non deve coprire l'ultima card (padding lista ≥ 88 dp con `hasFab: true`, già presente: verificalo).

## 3. Controllo degli stessi difetti altrove

La stessa causa (3–4 pulsanti con icona e testo in una `Row` di `Expanded`) può produrre testo verticale su altre schede. Cerca con grep `Expanded(` seguito da `OutlinedButton.icon`/`FilledButton.icon`/`TextButton.icon` in `lib/screens` e `lib/widgets` (schede lotto, scheda ricevimenti, attrezzature, storico temperature, non conformità, infestanti, fornitori, prodotti, sensori, `_PdfPreview` e simili). Per ogni riga con **tre o più** pulsanti con icona + testo usa `ActionButtonRow`; per **due** pulsanti lascia `Row` di `Expanded` ma verifica a 320 dp con scala 1.15 che il testo non vada a capo lettera per lettera (altrimenti stessa soluzione). Non ridisegnare le schermate: sostituisci solo le righe di azioni. Elenca nel messaggio finale i punti trovati e corretti.

## 4. Regola di progetto

Non cambiare `minimumSize` globale dei pulsanti nel tema. Documenta invece in `docs/qa_layout.md` la regola: "più di due azioni in riga → `ActionButtonRow`; mai `Expanded(OutlinedButton.icon)` con tre o più pulsanti".

## 5. Test

- Widget test `layout_fixes_test.dart`: `_LotCard` (o la lista lotti con un lotto di prova) a **320×640, 360×640, 412×915**, scala testo **1.0 e 1.15**: i quattro pulsanti hanno la **stessa larghezza e altezza (56 dp)**, stanno sulla **stessa riga** (stesso `dy`) o su due righe uguali sotto i 72 dp, nessun overflow, e le etichette "Stampa", "Etichetta", "Rintraccio", "Allegati" non sono spezzate (altezza del testo ≤ una riga).
- Test su `ActionButtonRow`: con 3 e 4 azioni, tocco su ogni pulsante chiama il callback giusto; con larghezza 200 dp passa alla griglia a due colonne.
- Aggiorna `docs/qa_layout.md` (tabella fix + checklist manuale: Lotti con 3 tasti e con gesti, font 100% e 130%, 360 e 412 dp).

## 6. Impostazioni → Stampante: sezione "Stampante generica" (`printer_settings_screen.dart`, `_genericSection`)

Sul telefono, con trasporto "Bluetooth LE (non verificato)": compare la striscia gialla/nera **"OVERFLOWED BY 50 PIXELS"** sul menu Trasporto; l'etichetta del campo "Dispositivo BLE (cerca, oppure remoteId)" si sovrappone al bordo del menu (nessuno spazio tra i due campi) ed è troppo lunga; i gruppi di scelta (ESC/POS/TSPL, 203/300 dpi, Carta 58/80 mm) sono chip sparsi **senza titolo**, con andata a capo diversa ("Carta 80 mm" finisce sola su una terza riga) e due gruppi sembrano tutti "selezionati"; il pulsante "Salva e collega" non ha le stesse dimensioni degli altri. Correggi:

- **Overflow del menu Trasporto:** nelle voci del `DropdownButtonFormField` e nella voce selezionata usa `Text(..., maxLines: 1, overflow: TextOverflow.ellipsis)` con `selectedItemBuilder` dedicato, e accorcia le etichette: "Wi-Fi / LAN (porta 9100)", "Bluetooth LE", "Bluetooth classico — non disponibile", "USB — non disponibile". L'avviso "non verificato" va in un `helperText` sotto il menu o in una piccola etichetta, non dentro la voce. Cerca la causa vera dell'overflow (voci disabilitate lunghe dentro il dropdown, testo scalato, larghezza fissa) e documentala nel messaggio finale.
- **Campi uno sotto l'altro con spazio fisso di 12 dp** (`SizedBox(height: 12)`): titolo sezione → menu → campo indirizzo → gruppi. Etichette dei campi brevi e leggibili: "Indirizzo IP (es. 192.168.1.50)" e "Dispositivo Bluetooth" con `helperText` "Premi Cerca stampanti oppure incolla l'identificativo"; mai etichette più lunghe del campo.
- **Gruppi di scelta con titolo e segmenti uguali:** sostituisci i `Wrap` di `ChoiceChip` con tre gruppi, ciascuno con un titolo sopra e un `SegmentedButton` a **larghezza piena**, segmenti di larghezza uguale e altezza 48 dp: **"Linguaggio"** (ESC/POS | TSPL), **"Risoluzione"** (203 dpi | 300 dpi), **"Larghezza carta"** (58 mm | 80 mm, visibile solo con ESC/POS). Selezione chiaramente indicata, un solo segmento attivo per gruppo, stesso spazio verticale tra i gruppi.
- **"Avanzate"** invariata nei contenuti ma con gli stessi campi a larghezza piena e spazio di 12 dp; l'interruttore "Inverti immagine" con titolo su una riga e sottotitolo a capo, senza overflow.
- **Pulsante "Salva e collega"**: larghezza piena, altezza 52 dp, come "Stampa etichetta di prova" (stessa regola del Prompt 14 §2); le due card di avviso sotto con lo stesso margine laterale delle altre card.
- **Barra di sistema:** l'ultima card ("Stampante generica: compatibilità non garantita…") finisce sotto i tre tasti di Android come nel difetto del Prompt 14 §1: verifica che con `screenPadding` l'ultima card sia interamente visibile e scorrevole sopra la barra (se il Prompt 14 è già applicato, controlla soltanto).
- **Stesso controllo** per la sezione Niimbot e Brother della stessa schermata (campi, menu e chip a larghezza coerente, nessun overflow).
- Test widget: `PrinterSettingsScreen` con motore **generico** e trasporto **BLE** e **Wi-Fi**, a **320×640, 360×640, 412×915**, scala testo **1.0 e 1.15**: `tester.takeException()` nullo (nessun overflow), tutti i campi e i tre gruppi visibili con titolo, segmenti dello stesso gruppo di larghezza uguale, "Salva e collega" a larghezza piena; con inset inferiore 48 dp l'ultima card è raggiungibile scorrendo.

## 7. Stampante generica ESC/POS di rete (TCP 9100): "non stampa"

Sintomo: configurata una stampante ESC/POS di rete sulla porta 9100, la prova di stampa e le etichette non escono. Dalla lettura del codice emergono questi punti; correggi **tutti**, poi aggiungi la diagnostica (§7.4) così il problema non resta più opaco.

**7.1 Bug certo: le impostazioni della generica non arrivano al motore che stampa.**
`PrintCoordinator.defaultEngineFactories` crea il motore con `'generic': GenericLabelPrinter.new`, cioè con la configurazione di **default** (ESC/POS, 203 dpi, carta 58 mm, nessun punto stampabile personalizzato, nessuna inversione, nessuna caratteristica BLE). `PrintSettings.generic` (letto da `printer_generic_*`) non viene mai passato al motore: `printPdf` imposta solo `address`/`transport` in `connect()`. Conseguenze: linguaggio TSPL, risoluzione 300 dpi, carta 80 mm, "Punti stampabili", "Inverti immagine" e UUID BLE scelti in Impostazioni sono **ignorati** nella stampa reale; con carta 80 mm dichiarata ma default 58 mm un'etichetta 50×30 o 62×40 viene rifiutata ("larga … stampa al massimo 48 mm"). Correggi: il coordinatore costruisce `GenericLabelPrinter(config: settings.generic)` (le factory ricevono le `PrintSettings`); `connect()` non deve sovrascrivere nient'altro che indirizzo/trasporto. Test: con impostazioni salvate TSPL + 300 dpi + carta 80 mm il motore creato da `PrintCoordinator.loadFrom` ha esattamente quella configurazione.

**7.2 Connessioni TCP multiple ravvicinate.**
Prima di ogni stampa il codice apre e chiude una connessione di prova (`connect()` in `printPdf`, `status()`), poi ne apre un'altra per l'invio. Molte stampanti di rete accettano **una sola connessione alla volta** e impiegano qualche secondo a liberare la porta: la seconda connessione viene rifiutata o i dati scartati. Correggi:
- `GenericLabelPrinter.connect()` per il Wi-Fi **non** apre alcuna connessione: memorizza solo l'indirizzo; la verifica vera è un pulsante esplicito "Verifica connessione" (§7.4).
- `printLabels` apre **una sola** connessione per tutto il lavoro (tutte le pagine/copie) e la chiude alla fine; `status()` non deve essere chiamato prima di stampare.
- Chiusura corretta: dopo l'ultimo `flush`, attendi 300–500 ms e chiudi con `close()` e `await socket.done` (mai `destroy()` subito, che può scartare il buffer residuo); gestisci gli errori di `flush`/`close` senza far fallire la stampa già inviata.
- Se `Socket.connect` fallisce, un nuovo tentativo dopo 1,5 s (la stampante può ancora tenere la porta); poi messaggio chiaro in italiano con indirizzo e porta.

**7.3 Invio dell'immagine ESC/POS più compatibile.**
Oggi l'immagine è un unico blocco `GS v 0` alto quanto tutta l'etichetta (es. 320+ righe): molte stampanti economiche ignorano o troncano blocchi alti. Correggi:
- Dividi il raster in **bande di 24 o 128 righe** (impostazione `printer_generic_band_rows`, default 128; 24 per modelli molto vecchi) e invia una `GS v 0` per banda, di seguito, con una breve pausa (5–10 ms) tra le bande.
- Dopo l'immagine: avanzamento di **N righe** configurabile (default 3–4 mm, non 40 righe fisse), **nessun comando di taglio** se la stampante non è dichiarata "con taglierina" (nuova opzione in Avanzate "Taglierina", default spento; `GS V` può bloccare alcune stampanti di etichette), e per carta a etichette l'opzione "Avanza all'etichetta successiva" (`FF` 0x0C) in Avanzate, default spenta.
- Svuota il buffer iniziale con `ESC @` e, in Avanzate, comando opzionale "Imposta densità" (`GS ( K` / modello specifico) **solo se esplicitamente attivato**: mai comandi che il cliente non ha chiesto.
- Bit dell'immagine invariati (1 = nero per ESC/POS); l'inversione resta solo per TSPL.

**7.4 Diagnostica per capire dove si ferma.**
In Impostazioni → Stampante generica (sezione Avanzate o sotto "Salva e collega"), aggiungi tre azioni a larghezza piena (stessa regola layout §6), ciascuna con messaggio in italiano e dettaglio:
1. **"Verifica connessione"**: apre il socket TCP verso IP:porta (porta modificabile in Avanzate, default 9100), misura il tempo, chiude. Messaggi distinti: *raggiungibile* / *rifiutata (porta chiusa o stampante occupata)* / *timeout (IP errato, Wi-Fi diverso o isolamento client sul router)* / *rete non disponibile*. Mostra anche l'IP del telefono, per verificare che sia nella stessa sottorete della stampante.
2. **"Prova solo testo"**: invia `ESC @`, una riga di testo ASCII ("HACCPass prova 9100"), 3 avanzamenti riga e (se "Taglierina" attiva) il taglio. Se questo stampa e l'etichetta no, il problema è l'immagine/raster; se nemmeno questo stampa, il problema è rete/porta/linguaggio.
3. **"Stampa etichetta di prova"** (già esistente) con, sotto, il riepilogo dell'ultimo invio: "Inviati N byte a IP:9100 in X ms (B bande, linguaggio ESC/POS, 203 dpi, carta 58 mm)". Distingue "non raggiunta" da "inviata ma non stampata" (quest'ultima = linguaggio/larghezza sbagliati sulla stampante).
Il riepilogo dell'ultimo invio compare anche nell'avviso dopo ogni stampa riuscita ("Inviata alla stampante: N byte"), senza promettere che sia uscita la carta (la stampante generica non risponde).
Nessun dato sensibile nei log (`debugPrint`): solo tipi di errore, durata e dimensioni.

**7.5 Aiuto per l'utente (testo in app e in `docs/stampanti.md`)**
Nella sezione generica aggiungi una guida breve "La stampante non stampa?": (1) stampa dalla stampante la pagina di autotest (di solito tenendo premuto il tasto Feed all'accensione) e controlla IP, porta (9100) e linguaggio (ESC/POS / TSPL / ZPL); (2) telefono e stampante sulla stessa rete Wi-Fi (non la rete ospiti, niente "isolamento client"); (3) da un PC sulla stessa rete: `Test-NetConnection <IP> -Port 9100` (Windows) o `nc -vz <IP> 9100`; (4) le stampanti di etichette con carta a gap usano spesso **TSPL**, non ESC/POS: prova l'altro linguaggio; (5) larghezza carta e formato: 58 mm ≈ 48 mm stampabili, 80 mm ≈ 72 mm; (6) imposta un IP fisso/prenotato sul router.

**7.6 Test automatici**
- Coordinatore → motore: la configurazione generica salvata arriva intatta al motore (§7.1).
- Trasporto finto: una sola connessione per lavoro anche con più copie; nessuna connessione in `connect()` Wi-Fi; chiusura con attesa dopo l'ultimo flush; nuovo tentativo dopo rifiuto.
- Encoder ESC/POS a bande: un'immagine 496×320 con banda 128 produce 3 blocchi `GS v 0` con altezze 128, 128, 64 (`yL/yH` corretti) e gli stessi byte dell'immagine completa; assenza di `GS V` con "Taglierina" spenta; presenza con "Taglierina" accesa.
- "Prova solo testo": byte attesi (`ESC @`, testo, avanzamento).
- "Verifica connessione": esiti distinti con socket finto (accettata, rifiutata, timeout).

## 8. Nuovo lotto: prodotto da menu a tendina + "Nuovo prodotto" al volo (`lots_screen.dart`, `_newLot`)

Oggi il foglio "Nuovo lotto di produzione" mostra i prodotti come chip (`ChoiceRow`, `products.take(8)`): vanno a capo su più righe, occupano mezzo schermo e **mostrano solo i primi 8 prodotti** (dal nono in poi non si può scegliere la scheda: difetto reale). Il primo prodotto è inoltre preselezionato (`products.first`), quindi si rischia di creare un lotto del prodotto sbagliato.

- **Selettore a tendina con ricerca.** Sostituisci il `ChoiceRow` con un menu a tendina (`DropdownMenu`/`DropdownButtonFormField` a larghezza piena, con **ricerca per testo** quando i prodotti sono più di 6) che elenca **tutti** i prodotti ordinati per nome (nessun `take(8)`). Ogni voce: nome su una riga + sottotitolo piccolo con "durata N giorni" e gli allergeni se presenti (ellissi, mai overflow). Ultima voce fissa **"Lotto libero (senza scheda)"** per il caso attuale `product == null`; in quel caso compare un campo "Nome del lotto" (obbligatorio, usato come `productName` al posto di "Lotto libero" fisso).
- **Nessuna preselezione silenziosa.** Il menu parte su "Seleziona il prodotto" oppure sull'**ultimo prodotto usato** per un lotto (impostazione `last_lot_product_id`, solo se esiste ancora). "Crea lotto" resta disabilitato finché non c'è un prodotto scelto o "Lotto libero" con nome compilato; messaggio sotto il menu "Scegli un prodotto o crea una nuova scheda".
- **Pulsante "Nuovo prodotto" accanto al menu** (icona + e testo breve "Nuovo" in un pulsante di larghezza fissa 48 dp di altezza, stessa riga del menu; sotto i 340 dp passa sotto il menu a larghezza piena). Apre l'editor prodotto esistente (nome, categoria, ingredienti, durata in giorni, conservazione, allergeni) **sopra** il foglio del lotto, senza perderne i dati. Al salvataggio il nuovo prodotto è **selezionato automaticamente** nel menu e il lotto si riprecompila (codice, scadenza dalla durata, conservazione); se l'utente annulla non cambia nulla.
  - Riuso del codice: estrai `ProductsScreen._edit` (`lib/screens/goods/products_screen.dart`) in una funzione condivisa `Future<Product?> showProductEditor(BuildContext, HaccpRepository, {Product? existing})` che restituisce il prodotto salvato (con l'`id` assegnato da `saveProduct`) e usala **sia** dalla schermata Prodotti sia dal foglio lotto: nessuna duplicazione dei campi o delle regole di validazione. Il nome è obbligatorio e non duplicato (confronto senza maiuscole/spazi: se esiste già, proponi di selezionare quello esistente).
  - Stato vuoto: se non esistono prodotti, il menu è disattivato con il testo "Nessuna scheda prodotto" e il pulsante **"Crea il primo prodotto"** a larghezza piena (primario) al posto del vecchio avviso testuale; "Lotto libero" resta disponibile.
- **Cambio prodotto senza perdere i dati inseriti.** Alla selezione di un prodotto ricalcola codice lotto, "Utilizzare entro" e "Conservazione" **solo se l'utente non li ha modificati a mano** (tieni dei flag `dirty` per codice, scadenza, conservazione, azzerati quando si cambia prodotto e il campo è ancora al valore precalcolato); quantità, unità, note, ingredienti selezionati e allegati non vengono mai toccati dal cambio prodotto. Cambiando prodotto con ingredienti già scelti non chiedere conferma: restano selezionati.
- **Allergeni e durata visibili.** Sotto il menu, una riga di riepilogo del prodotto scelto: "Durata 3 giorni • Allergeni: glutine, latte" (o "Nessun allergene indicato"), così l'operatore vede cosa sta ereditando il lotto; tocco su "Modifica scheda" apre `showProductEditor` per quel prodotto.
- **Salvataggio:** invariato (`productId`, `productName`, `allergenCodes` dal prodotto). Aggiorna `last_lot_product_id` dopo il salvataggio del lotto.
- **Layout:** stessa regola dei campi (spazio 12 dp, etichette brevi, nessun overflow) e pulsante "Crea lotto" già fisso in basso: l'ultimo campo non finisce coperto (verifica con inset 48 dp, §Prompt 14).
- **Altri punti con lo stesso schema** (chip che mostrano i primi N elementi): grep `ChoiceRow` e `.take(` nei fogli di registrazione (ricevimento merce, temperature, pulizie, non conformità, infestanti); dove l'elenco può superare ~6 voci o crescere nel tempo (prodotti, fornitori, attrezzature, operatori) sostituisci con lo stesso menu a tendina ricercabile e, se manca la voce, il pulsante "Nuovo …" che apre l'editor esistente. Elenca nel messaggio finale i punti trovati e cambiati; non toccare i `ChoiceRow` con poche opzioni fisse (unità, esiti Sì/No, tipi).
- **Test widget:** (a) con 12 prodotti, tutti e 12 selezionabili dal menu e la ricerca "pan" mostra "Panzarotti"; (b) nessun prodotto preselezionato all'apertura se non c'è un ultimo usato; "Crea lotto" disabilitato finché non si sceglie; (c) "Nuovo prodotto" apre l'editor (usa un `showProductEditor` iniettabile/finto), al ritorno il nuovo prodotto è selezionato e codice/scadenza/conservazione sono precompilati; annullando non cambia nulla; (d) cambio prodotto con codice modificato a mano non sovrascrive il codice; con scadenza non modificata la ricalcola; (e) "Lotto libero" richiede il nome e salva `productId` nullo con quel `productName`; (f) stato vuoto con "Crea il primo prodotto"; (g) a 320×640 e scala 1.15 nessun overflow nel foglio.

## Criteri di accettazione

1. Nella scheda lotto i quattro pulsanti sono in orizzontale, uguali, alti 56 dp, con icona sopra e testo sotto su una sola riga; nessuna parola spezzata.
2. A 320 dp o scala 1.15 il testo si riduce o i pulsanti passano su due righe uguali: mai overflow né testo verticale.
3. Le altre schede con tre o più pulsanti in riga sono state corrette con lo stesso componente; elenco consegnato nel messaggio finale.
4. Le azioni (stampa, etichetta, rintraccio, allegati) funzionano come prima.
5. Nel form della stampante generica nessun overflow (né con BLE né con Wi-Fi, 320–412 dp, scala 1.15): menu Trasporto con testo ellissizzato, campi distanziati, gruppi Linguaggio/Risoluzione/Larghezza carta con titolo e segmenti uguali, pulsante "Salva e collega" a larghezza piena, ultima card sopra la barra di sistema.
6. Le impostazioni della stampante generica (linguaggio, dpi, carta, punti stampabili, inversione, taglierina, bande) arrivano al motore che stampa; una sola connessione TCP per lavoro; immagine ESC/POS inviata a bande; esiste la diagnostica "Verifica connessione" e "Prova solo testo" con messaggi che distinguono rete, porta e linguaggio.
7. Nel nuovo lotto il prodotto si sceglie da un menu a tendina ricercabile con **tutti** i prodotti (nessun limite di 8), senza preselezione silenziosa, con "Lotto libero" e un pulsante "Nuovo prodotto" che crea la scheda al volo, la seleziona e precompila il lotto senza perdere i dati inseriti; l'editor prodotto è lo stesso della schermata Prodotti.
8. `docs/qa_layout.md` e `docs/stampanti.md` aggiornati; `flutter analyze` e `flutter test` verdi.
