# PROMPT PER AI DI SVILUPPO: Redesign e potenziamento di "Blue HACCP" (Flutter)

Copia tutto questo documento nella AI di sviluppo, con accesso alla cartella del progetto `HaccpPro` (Flutter, SQLite locale, nessun server). In allegato vanno forniti anche i due manuali HACCP in PDF (Manuale di corretta prassi FIDA 2020 e Manuale autocontrollo bar didattico).

---

## 1. RUOLO E OBIETTIVO

Sei un senior Flutter developer e product designer. Devi trasformare l'app starter **Blue HACCP** in un prodotto **a pagamento**, pronto per lo store, per l'autocontrollo alimentare (HACCP) di piccoli esercizi italiani (bar, ristoranti, pizzerie, gastronomie, caseifici, laboratori).

Tre priorità, in quest'ordine:

1. **Interfaccia leggibile e a prova di cucina**: oggi pulsanti e testi non si leggono bene. Va ridisegnata.
2. **Completezza funzionale rispetto ai manuali HACCP** (sezione 5): oggi l'app copre solo una parte dei registri obbligatori.
3. **Generazione di PDF dei registri**, condivisibili dallo smartphone (WhatsApp, email, stampa), utilizzabili in un'ispezione ASL.

Tono dell'app: professionale, rassicurante, veloce. Tutto in **italiano**. Un operatore con le mani bagnate, in piedi, deve registrare un controllo in meno di 10 secondi.

---

## 2. STATO ATTUALE DEL PROGETTO (da non perdere)

Stack: Flutter (Material 3), `sqflite`, `intl`, `shared_preferences`, `uuid`. Package `blue_haccp`. Dati solo locali.

Struttura esistente in `lib/`:

- `main.dart`, `core/database/app_database.dart` (DB v1), `core/theme/app_theme.dart`
- `models/haccp_models.dart` (Equipment, CleaningTask, ProductionLot, NonConformity)
- `repositories/haccp_repository.dart`
- `services/printer_service.dart` (interfaccia `PrinterService` + `DemoPrinterService`)
- `screens/`: `app_shell`, `dashboard_screen`, `temperature_screen`, `cleaning_screen`, `lots_screen`, `non_conformities_screen`, `settings_screen`
- `widgets/common_widgets.dart` (SectionTitle, MetricCard, StatusPill)

Funzioni presenti: dashboard, temperature con NC automatica se fuori soglia, pulizie con conferma, lotti con anteprima etichetta, NC, impostazioni, dati demo.

**Vincoli di compatibilità:**

- Il DB è alla versione 1 e può contenere dati reali di prova. Fai **migrazione a v2 con `onUpgrade`** (ALTER TABLE + nuove tabelle), senza cancellare dati.
- Mantieni l'architettura a livelli (database / repository / services / screens / widgets) e l'astrazione `PrinterService`.
- Nessun backend, nessun account cloud: **offline-first**.
- Non usare API deprecate (`withOpacity`, `MaterialStateProperty`, `Color.value`). Usa `withValues(alpha:)`, `WidgetState*`.
- Il codice deve passare `flutter analyze` senza errori e warning rilevanti, e compilare per Android (priorità), iOS e Windows.

---

## 3. PROBLEMI DI INTERFACCIA DA RISOLVERE (diagnosi sullo screenshot)

Screenshot analizzato: emulatore Android, schermata "Oggi".

1. **Barra di navigazione inferiore illeggibile.** Con 6 voci le etichette vanno a capo e si spezzano ("Temperatur/e", "Impostazio/ni"), l'icona non selezionata è grigio chiaro, il testo è minuscolo.
2. **Contrasto troppo basso.** Testi secondari `#667270` su sfondo `#F4F7F6`, bordi `#E4ECEA` quasi invisibili, icone nei cerchietti con alpha 10%.
3. **Gerarchia debole.** Tutto ha lo stesso peso. La schermata "Oggi" non dice cosa fare adesso.
4. **Target tocco piccoli** nelle liste (bottoni dentro `ListTile.trailing`).
5. **Stato "0%" ambiguo**: con 0 attività completate e nessun avviso la schermata non guida l'utente.
6. **Navigazione sovraccarica**: 6 tab, con "Impostazioni" e "NC" allo stesso livello delle funzioni quotidiane.

---

## 4. SPECIFICHE DEL NUOVO DESIGN

### 4.1 Principi

- Leggibilità prima dell'estetica: **contrasto minimo WCAG AA 4.5:1** per il testo, 3:1 per icone e bordi. Verifica i valori, non a occhio.
- Nessun testo che va a capo o si taglia nella barra di navigazione. Usa `FittedBox(fit: BoxFit.scaleDown)` o etichette brevi, `maxLines: 1`.
- **Target tocco minimo 48 dp**, bottoni principali 54-56 dp di altezza, larghezza piena nei bottom sheet.
- Lo stato non è mai comunicato solo dal colore: sempre **icona + testo** (es. "Conforme", "Fuori limite").
- Rispetta il ridimensionamento del testo di sistema (limitalo tra 0.9 e 1.3 nel `MediaQuery`), nessun overflow.
- Supporto **tema chiaro e scuro** (`ThemeMode.system`).
- Una sola azione primaria evidente per schermata.

### 4.2 Design system

- **Font**: Poppins (Regular 400, Medium 500, Bold 700) incluso negli `assets/fonts`, oppure Inter. Dichiaralo in `pubspec.yaml`. Il font deve essere incorporato anche nei PDF (vedi 6).
- **Colori (chiaro)**: primario `#0B6B66`, primario scuro `#064A47`, testo `#10201F`, testo secondario `#3F4D4B`, sfondo `#F1F5F4`, bordo `#C3D1CE`.
  Successo testo `#16703C` su `#DDF3E6`. Avviso testo `#8A4B00` su `#FFEBCC`. Errore testo `#B3261E` su `#FBE0DD`. Info `#1B4F8F` su `#DCE9FA`.
- **Colori (scuro)**: definisci l'equivalente con gli stessi rapporti di contrasto.
- Implementa i colori semantici come `ThemeExtension<HaccpColors>` con `copyWith` e `lerp`, e un'estensione su `BuildContext` per accedervi.
- **Pulsanti** (tema globale): `FilledButton` min 64x54, raggio 16, testo 16 Bold. `OutlinedButton` con bordo 1.6 px colore primario. `TextButton` min 48x48.
- **Input**: label sempre visibile e ad alto contrasto, bordo 1.4 px (2.2 px in focus), raggio 14.
- **Card**: raggio 20, bordo visibile, nessuna ombra pesante.
- **Bottom sheet**: raggio superiore 28, maniglia visibile, bottone di salvataggio sempre raggiungibile (sopra la tastiera).
- **Preferisci i chip di scelta** (`ChoiceChip`, `FilterChip`) ai dropdown per le selezioni brevi: più veloci da toccare. Evita `DropdownButtonFormField` per compatibilità tra versioni di Flutter.

### 4.3 Navigazione (da 6 a 5 tab)

Barra inferiore **custom** (non `NavigationBar` standard) con 5 voci, ognuna con icona 26 px dentro una "pillola" evidenziata e l'etichetta su una riga:

1. **Oggi** (dashboard)
2. **Controlli** (hub: temperature, pulizie, merce in arrivo, infestanti, strutture, non conformità, eliminazione prodotti, ognuno con badge di stato)
3. **Lotti** (produzione, etichette, rintracciabilità)
4. **Report** (generazione PDF)
5. **Altro** (anagrafica azienda, attrezzature, fornitori, prodotti e allergeni, personale, piano pulizie, guida HACCP, backup, licenza)

Sulle larghezze >= 900 dp usa `NavigationRail` con le stesse 5 voci. Mantieni lo stato delle tab (`IndexedStack`). Aggiorna i dati in automatico dopo ogni scrittura (es. `ValueNotifier<int> revision` nel repository + widget `LiveQuery`).

### 4.4 Schermata "Oggi"

1. Intestazione: nome azienda, data estesa in italiano, chip della licenza ("Prova: 12 giorni") che apre la schermata di acquisto.
2. **Card "hero"** con gradiente verde scuro, testo bianco: anello di avanzamento disegnato con `CustomPainter`, "x su y controlli completati", messaggio di stato ("Tutto in regola" / "3 attività da completare").
3. **"Da fare ora"**: elenco generato dalle regole del repository (vedi 5.10), ordinato per gravità (danger, warning, info), ogni riga con striscia colorata, icona, titolo, sottotitolo e pulsante "Vai".
4. **Azioni rapide**: griglia 2x3 di tile grandi (icona 32 px, etichetta Bold): Temperatura, Pulizie, Merce in arrivo, Nuovo lotto, Non conformità, Report PDF.
5. Banner "Completa l'anagrafica azienda" finché mancano ragione sociale e responsabile HACCP (servono per i PDF).

### 4.5 Componenti riutilizzabili

Crea in `widgets/`: `PageHeader`, `SectionTitle`, `AppCard`, `StatusPill` (icona + testo), `MetricTile`, `EmptyState` (icona, titolo, messaggio, azione), `BigButton`, `FormSheet` (helper per bottom sheet con tastiera), `ChoiceRow`, `DateField`, `FutureView/LiveQuery`, `AppBottomBar`, grafico a linee `Sparkline` con banda dei limiti.

---

## 5. FUNZIONALITÀ DA AGGIUNGERE (derivate dai manuali)

Ogni funzione deve produrre dati che finiscono nei PDF (sezione 6). Le soglie indicate vengono dai manuali allegati: mettile in un unico file di costanti (`core/constants/haccp_rules.dart`) per poterle modificare, e mostra sempre che sono valori di riferimento che l'operatore può adattare.

### 5.1 Anagrafica azienda
Ragione sociale, indirizzo, città, P.IVA, **responsabile HACCP**, **sostituto responsabile**, telefono, email, PEC, numero notifica sanitaria, codice ATECO, descrizione attività, operatore predefinito. Il manuale del bar apre con questa scheda. Serve per intestare tutti i PDF.

### 5.2 Attrezzature e temperature (PRP 11)
- CRUD attrezzature: nome, tipo (frigorifero, congelatore, cella, banco frigo, abbattitore, mantenimento a caldo), posizione, limiti min/max.
- **Preset** selezionabili: frigo +4 °C (0/+4), frigo verdure e uova (0/+7), frigo bevande (0/+8), congelatore -18 °C (-30/-18), mantenimento a caldo (+60/+90), cotti da consumare freddi (max +10).
- Registrazione: campo numerico grande (tastiera con virgola e segno meno), **indicatore in tempo reale** conforme/fuori limite. Se fuori limite compaiono le **azioni correttive suggerite** a scelta multipla (verificata chiusura porta e guarnizioni; nuova misura dopo 30 minuti; prodotti spostati; valutato il prodotto per aspetto e tempo/temperatura; prodotto smaltito; contattata assistenza) più nota libera. Si crea una NC collegata e l'azione correttiva viene salvata.
- Scheda attrezzatura con **grafico andamento** ultimi 14 giorni e banda dei limiti, storico, modifica.
- Il controllo visivo giornaliero è il minimo richiesto: nella dashboard segnala le attrezzature non ancora controllate oggi.
- Regola utile da mostrare nella guida: la zona di rischio è tra +10 °C e +60 °C; oltre le 2 ore in zona di rischio il prodotto va riportato a temperatura o valutato.

### 5.3 Verifica termometri (PRP 4)
Registro della verifica periodica (ogni 6 mesi): temperatura di riferimento, temperatura dello strumento, scostamento. **Tolleranza ±1 °C**; oltre ±3 °C il termometro va sostituito o riparato (crea NC). Aggiorna `thermo_verified_at` sull'attrezzatura. Segnala le verifiche scadute.

### 5.4 Pulizie e sanificazione (PRP 2)
- Frequenze reali dei manuali: dopo ogni utilizzo, giornaliera, **2 volte al giorno**, settimanale, mensile, semestrale (pulizia completa frigoriferi e congelatori), annuale, al bisogno.
- Logica di scadenza: per le giornaliere conta quante esecuzioni mancano oggi; per le lunghe calcola "scade tra N giorni" / "scaduta".
- **Storico esecuzioni** in tabella `cleaning_logs` (oggi esiste solo `last_completed_at`: va mantenuto come cache ma non basta per i registri).
- Conferma in **un solo tocco** ("Fatto", operatore predefinito) più un pulsante "Problema" che apre una NC (superficie non idonea: sporco visibile, tracce di unto, odori).
- Per ogni attività: area, titolo, prodotto usato, **metodo** (testo guida), frequenza. CRUD del piano. Raggruppa per area.
- Dati demo coerenti con i manuali: piani di lavoro e utensili (dopo ogni utilizzo), superfici a contatto col cliente, attrezzature meccaniche (giornaliera), pavimenti (2 volte al giorno), servizi igienici, scaffalature (settimanale), frigoriferi e freezer (semestrale).

### 5.5 Ricevimento merci e fornitori (PRP 10, Allegati IV e V)
- Registro **fornitori**: ragione sociale, P.IVA, indirizzo, telefono, email, prodotti forniti, qualificato sì/no, note.
- Registrazione **merce in arrivo**: fornitore, prodotto, categoria, **temperatura all'arrivo** (con limite per categoria), lotto del fornitore, n. DDT, scadenza, quantità, e 4 controlli sì/no: integrità confezioni, etichetta corretta, scadenza valida, mezzo di trasporto igienico. Esito: Accettata / Accettata con riserva / **Respinta**. Se un controllo fallisce o la temperatura è fuori limite, proponi "Respinta" e crea la NC con il **modulo di non conformità fornitore** (Allegato IV).
- Limiti di temperatura all'arrivo per categoria: latticini e formaggi freschi 0/+4; carni fresche e insaccati -1/+7; pesce fresco -1/+2; surgelati max -15 (conservazione -18); carni congelate max -15; pasta fresca max +4 con tolleranza 2; dolci con panna o crema max +4; ortofrutta IV gamma max +8; cotti caldi min +60; cotti freddi max +10; uova, ortofrutta, secco e bevande a temperatura ambiente.
- Segnala i fornitori con **non conformità ripetute** (il manuale lo prevede come criterio di sostituzione).

### 5.6 Prodotti, allergeni, lotti, rintracciabilità (Reg. 1169/2011, Reg. 178/2002)
- **Schede prodotto**: nome, categoria, ingredienti, durata (giorni) per calcolare la scadenza, conservazione, **14 allergeni** selezionabili: glutine, crostacei, uova, pesce, arachidi, soia, latte, frutta a guscio, sedano, senape, sesamo, solfiti, lupini, molluschi.
- **Lotti di produzione**: codice automatico (editabile), data produzione, scadenza precompilata dalla durata, quantità e unità, conservazione, operatore, allergeni ereditati dal prodotto (modificabili), **ingredienti collegati alle consegne** (scelta tra le merci ricevute negli ultimi 60 giorni non respinte, più ingrediente libero).
- **Rintracciabilità a monte e a valle**: ricerca per codice lotto, prodotto o lotto del fornitore. Da una consegna si vedono tutti i lotti prodotti che la contengono. Serve per ritiro/richiamo.
- **Etichetta** (62x40 mm configurabile): azienda, prodotto, lotto, produzione, scadenza, conservazione, **allergeni in grassetto**, QR con il codice lotto. Stampa tramite `printing` (anche su stampanti Bluetooth/Wi-Fi viste da Android) con numero di copie. Mantieni `PrinterService` e aggiungi un'implementazione PDF.
- **Scheda di rintracciabilità del lotto** in PDF (lotto, ingredienti con fornitore e lotto fornitore, destinazioni se note).
- Promemoria sui tempi di conservazione della documentazione: freschi 3 mesi; "da consumarsi entro" 6 mesi dopo; "preferibilmente entro" 12 mesi; altri 2 anni. **Non cancellare mai i dati** automaticamente.

### 5.7 Non conformità (Allegati I, II, III)
- Registro NC come Allegato I (data, tipo, azione correttiva, firma/operatore, stato).
- Categorie: temperatura, ricevimento merci, materia prima, pulizia, infestanti, attrezzatura, strutture, scadenza, etichettatura, allergeni, personale, altro.
- Chiusura con azione correttiva **obbligatoria** e **destino del prodotto** (nessuna, smaltito, reso al fornitore, isolato in attesa, utilizzato dopo cottura).
- PDF **"Cartello PRODOTTO NON CONFORME"** (Allegato III: "non idoneo per essere utilizzato, venduto o somministrato, si conserva in attesa di smaltimento o reso al fornitore") da stampare e appendere.
- PDF **modulo NC singola** con firma.
- Registro **Eliminazione prodotti alimentari** (Allegato II): data, prodotto, motivo (scaduto, alterato, contaminato, confezione danneggiata, temperatura non conforme, restituito, altro), quantità, lotto, operatore.

### 5.8 Infestanti (PRP 3)
- Postazioni configurabili (roditori, striscianti, volanti) con ubicazione.
- Registrazione conteggi per postazione con **livello automatico**: roditori: 0 accettabile, 1 o più notevole. Striscianti (somma): 0-3 accettabile, 4-7 modesto, 8 o più notevole. Volanti (per trappola): fino a 20 accettabile, 21-30 modesto, 31 o più notevole.
- Flag "controllo eseguito dalla ditta specializzata". Se il livello è **notevole** crea NC e mostra le azioni: sospendere l'attività, allontanare gli alimenti a rischio, coprire attrezzature, aerare e pulire prima di riprendere, chiamare la ditta.
- Promemoria se non c'è un monitoraggio da oltre 30 giorni.

### 5.9 Strutture e attrezzature (Allegato VII), personale (Allegato VI)
- **Monitoraggio strutture**: checklist per area (esterno, locale di lavorazione, stoccaggio, servizi igienici, apparecchiature refrigeranti, attrezzature) con voci: distacco di intonaco o vernice, integrità pavimento e piastrelle, integrità porte finestre e retine, rubinetti gocciolanti, presenza di umidità, integrità guarnizioni, anomalie meccaniche. Ogni voce OK / Anomalia con nota; le anomalie generano una NC riepilogativa. Cadenza consigliata semestrale.
- **Personale e formazione**: nome, mansione, ruolo, data attestato formazione alimentarista, **scadenza**, note. Stato: valido / in scadenza (30 giorni) / scaduto / mancante, con avviso in dashboard.

### 5.10 Motore "Da fare ora" (dashboard)
`getDashboard()` nel repository compone la lista con queste regole, in ordine di gravità:

- Attrezzature senza lettura oggi.
- Pulizie dovute (giornaliere mancanti, lunghe scadute).
- NC aperte (danger).
- Formazione scaduta (danger) o in scadenza (warning).
- Verifica termometri scaduta o mai fatta (warning/info).
- Monitoraggio infestanti > 30 giorni (info).
- Controllo strutture > 182 giorni (info).
- Anagrafica azienda incompleta (info).

Il progresso giornaliero conta solo i controlli giornalieri (letture temperatura + pulizie giornaliere).

---

## 6. GENERAZIONE PDF (funzione di punta)

Dipendenze: `pdf`, `printing`, `share_plus`, `path_provider`. Carica il font da asset (`pw.Font.ttf`) e usa `pw.ThemeData.withFont`, altrimenti accenti e simboli come ’ – • °C si rompono.

### 6.1 Documenti
1. **Dossier HACCP completo** per periodo: copertina (nome app, azienda, periodo, responsabile, data di generazione e riferimento Reg. CE 852/2004), anagrafica, riepilogo con indicatori (controlli, % conformi, NC aperte/chiuse), poi i registri: temperature, verifica termometri, pulizie, merce in arrivo, lotti e rintracciabilità, non conformità, eliminazione prodotti, infestanti, strutture, formazione, fornitori. **Le sezioni vuote restano** con la dicitura "Nessuna registrazione nel periodo": in ispezione dimostra che il controllo è stato fatto.
2. **Singoli registri** (uno per ciascuna sezione sopra), con lo stesso periodo.
3. **Menù allergeni** per i clienti (tabella prodotti x 14 allergeni, legenda numerata, formato orizzontale).
4. **Cartello prodotto non conforme** e **modulo NC**.
5. **Etichetta lotto** e **scheda di rintracciabilità lotto**.

### 6.2 Requisiti
- Intestazione su ogni pagina (azienda, titolo, periodo) e piè di pagina "Pagina X di Y" con data di generazione.
- Tabelle con riga di intestazione che si ripete (`pw.TableRow(repeat: true)`), righe a fasce alternate, colonne dimensionate, testo leggibile (>= 9 pt).
- Blocco **firma del responsabile** con data a fine dossier.
- Costruisci le tabelle con `pw.Table` e `pw.TableRow` (non dipendere da helper deprecati tra versioni).
- Schermata **Report**: selettore periodo (Oggi, 7 giorni, mese corrente, mese scorso, 3 mesi, personalizzato), pulsante grande "Dossier completo", elenco registri con anteprima, scorciatoie per menù allergeni e cartello NC.
- **Anteprima** con `PdfPreview` (`useActions: false`) e tre pulsanti grandi: **Condividi** (`Printing.sharePdf`, apre il foglio di condivisione di Android/iOS), **Stampa** (`Printing.layoutPdf`), **Salva/Invia per email**. Nome file: `HACCP_<Registro>_<Azienda>_<AAAA-MM-GG>.pdf`.
- La generazione di dossier grandi non deve bloccare la UI: mostra un indicatore di avanzamento.

### 6.3 Backup
Esporta il file del DB con `share_plus` e ripristina con `file_picker` (conferma esplicita, chiusura e riapertura del DB). Aggiungi un controllo di integrità prima di sostituire il file.

---

## 7. MODELLO COMMERCIALE (app a pagamento)

- **Prova gratuita di 14 giorni** a funzionalità complete (data di avvio salvata alla prima apertura).
- A prova scaduta l'app resta **in sola lettura**: si consulta tutto, ma niente nuove registrazioni né export PDF. Mostra la schermata di acquisto (paywall) con elenco dei vantaggi.
- Due canali di sblocco:
  1. **Acquisti in-app** con `in_app_purchase`: abbonamento annuale e licenza a vita (ID prodotto configurabili in costanti). Gestisci `purchaseStream`, `restorePurchases`, `completePurchase`, disponibilità non garantita su desktop (try/catch e controllo piattaforma).
  2. **Chiave di licenza offline** per vendita diretta ai clienti (il titolare vende software su misura): formato `BH1-<CODICECLIENTE>-<AAAAMMGG>-<FIRMA>`, firma = primi 5 byte (hex maiuscolo) di HMAC-SHA256 sul payload `BH1|CODICE|DATA`, con segreto passato via `--dart-define=BH_LICENSE_SECRET=...`. Data `99991231` = licenza a vita. Metti la logica in un file Dart puro (`license_codec.dart`, senza import Flutter) e crea `tool/license_keygen.dart` per generare le chiavi da riga di comando.
- Un unico punto di controllo (`LicenseService` come `ChangeNotifier` + helper `ensureLicensed(context)`) usato da ogni azione di scrittura e dall'export PDF.
- In modalità debug aggiungi uno sblocco di prova, assente nelle build release.
- **Non inventare prezzi**: leggi quelli dallo store (`ProductDetails.price`) e mostra un testo neutro se non disponibili.

---

## 8. SCHEMA DATABASE v2 (riferimento)

Tabelle nuove: `thermometer_checks`, `cleaning_logs`, `suppliers`, `receipts`, `products`, `lot_ingredients`, `pest_stations`, `pest_logs`, `staff`, `structure_checks`, `waste_logs`.

Colonne aggiunte:
- `equipment`: `location`, `thermo_verified_at`, `notes`
- `temperature_logs`: `corrective_action`
- `cleaning_tasks`: `freq_code`, `method`
- `lots`: `allergens` (codici separati da virgola), `product_id`
- `non_conformities`: `disposition`

Migrazione v1 → v2: mappa le frequenze testuali esistenti sui nuovi codici (`after_use`, `daily`, `twice_daily`, `weekly`, `monthly`, `semiannual`, `annual`, `as_needed`), porta `last_completed_at` nello storico `cleaning_logs`, crea postazioni infestanti di esempio e salva `trial_started_at` se manca.

Aggiungi indici su `measured_at`, `done_at`, `received_at`.

---

## 9. ALTRI INTERVENTI TECNICI

- `MaterialApp`: `localizationsDelegates` + `supportedLocales` per `it_IT` (aggiungi `flutter_localizations` e usa `intl` coerente), `themeMode: ThemeMode.system`, `textScaler` limitato.
- Android: etichetta app "Blue HACCP" nel manifest (oggi `blue_haccp`). **Segnala** che `applicationId = com.example.blue_haccp` va sostituito prima della pubblicazione sullo store, senza farlo alla cieca se richiede spostare package Kotlin.
- Aggiorna `README.md` (funzioni, avvio, struttura, licenze, generazione chiavi) e il widget test di esempio affinché non fallisca.
- Aggiungi test unitari per: `CleaningTask.state`, livelli infestanti, conformità temperature per categoria, codec licenza.
- Il repository espone `ValueNotifier<int> revision` incrementato dopo ogni scrittura.

---

## 10. ORDINE DI LAVORO CONSIGLIATO

1. Tema e design system (4.2) e nuova barra di navigazione: **verifica subito la leggibilità sull'emulatore**.
2. Costanti HACCP, migrazione DB v2, modelli, repository.
3. Dashboard e hub Controlli.
4. Temperature, pulizie, verifica termometri.
5. Merce in arrivo, fornitori, prodotti, lotti, rintracciabilità.
6. NC, eliminazione prodotti, infestanti, strutture, personale.
7. Servizio PDF, schermata Report, anteprima, condivisione, etichette.
8. Licenza, paywall, chiavi offline, backup.
9. Guida HACCP in-app, test, `flutter analyze`, aggiornamento README.

Dopo ogni punto esegui `flutter analyze` e correggi prima di procedere.

---

## 11. CRITERI DI ACCETTAZIONE

- [ ] Nessuna etichetta della barra di navigazione va a capo o viene tagliata, anche con testo di sistema al 130%.
- [ ] Tutti i testi rispettano il contrasto AA in tema chiaro e scuro.
- [ ] Un controllo di temperatura si registra in massimo 3 tocchi dalla dashboard.
- [ ] Una temperatura fuori limite crea una NC con azione correttiva salvata.
- [ ] Il PDF "Dossier completo" si genera, si apre in anteprima e si condivide dallo smartphone con caratteri accentati corretti.
- [ ] Tutte le registrazioni compaiono nel PDF del periodo selezionato.
- [ ] La migrazione da DB v1 conserva i dati esistenti.
- [ ] A prova scaduta le scritture e l'export sono bloccati e compare il paywall; una chiave offline valida sblocca l'app.
- [ ] `flutter analyze` pulito, test unitari verdi, build Android riuscita.
- [ ] L'app dichiara chiaramente che i limiti sono valori di riferimento e che la responsabilità dell'autocontrollo resta dell'operatore.

---

## 12. CONSEGNA

Al termine fornisci: elenco dei file creati o modificati, comandi per eseguire (`flutter pub get`, `flutter analyze`, `flutter test`, `flutter run`), come generare una chiave di licenza, e un elenco onesto di ciò che **non** è stato verificato (acquisti in-app reali, stampa su stampante fisica, build iOS).

Non copiare testo dai manuali allegati nell'app: usa solo i valori numerici e le strutture dei registri, riformulando le istruzioni con parole tue e citando i riferimenti normativi (Reg. CE 852/2004, 178/2002, UE 1169/2011).
