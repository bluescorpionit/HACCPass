# QA layout — edge-to-edge, barre di sistema, wizard, font (Prompt 6)

Questo documento descrive i fix di layout applicati e la checklist di
verifica manuale da eseguire su telefono reale prima di ogni rilascio.
L'app gira in modalità edge-to-edge (Android 15 / targetSdk recente): i
contenuti si estendono sotto barra di stato e barra di navigazione, quindi
ogni schermata, foglio e dialog deve gestire gli inset di sistema.

## Fix applicati (con test automatici)

| # | Problema | Fix | Copertura automatica |
|---|----------|-----|----------------------|
| 1 | Contenuti sotto la barra di stato (titolo "Oggi" coperto dall'ora) | Helper `screenPadding()` in `common_widgets.dart` applicato a tutti i ListView/SingleChildScrollView radice (tab e schermate push); `AnnotatedRegion<SystemUiOverlayStyle>` in `main.dart` per icone/barre coerenti col tema | `layout_fixes_test.dart`: padding esatto con inset 24/48 simulati |
| 2 | "Controlli" nera quando aperta via push | `ChecksHubScreen(standalone: true)` si avvolge in `FeatureScaffold` (Scaffold + AppBar + sfondo del tema); nessuna schermata pushata senza Scaffold | `layout_fixes_test.dart`: Scaffold opaco e AppBar su hub standalone e guida |
| 3 | Fogli modali coperti dalla barra di sistema | `showFormSheet`: `useSafeArea: true`, altezza max `(altezza - padding.top) * 0.92`, pulsante Salva fisso in `SafeArea(top: false)` con padding `max(16, viewPadding.bottom)` e `viewInsets` per la tastiera. Stesso trattamento a `showAttachmentsSheet` e `showEquipmentHistory` | `layout_fixes_test.dart`: Salva sopra inset 48 simulato, foglio sotto la barra di stato |
| 4 | Chip "Azioni correttive" tagliati ("…guarnizi…") | Nuovo `CorrectiveActionPicker`: righe checkbox dense (testo integro su più righe, area di tocco >= 48 dp) al posto dei `FilterChip` | `layout_fixes_test.dart`: etichette integre a 360 dp con scala 1.3 |
| 5 | "Problema" spezzato a metà parola; FAB copre l'ultima card (Pulizie) | Etichette `maxLines: 1` + `FittedBox(scaleDown)`; sotto 360 dp i pulsanti si impilano; badge sotto il titolo (mai compressi); padding lista >= 88 dp quando c'è un FAB (`hasFab: true`) | Verifica manuale + test overflow generali |
| 6 | Wizard: "Salta questo passo" spezzato lettera per lettera; "Avanti" nell'ultimo passo | Barra a due livelli: riga 1 = Indietro + Avanti/Inizia; riga 2 = "Salta questo passo" su una riga propria a larghezza piena. Ultimo passo (Riepilogo): niente "Avanti", "Inizia" fisso in barra, avanzamento al 100%. Altezza < 600 dp (landscape): riga unica con "Salta" breve + tooltip | `onboarding_flow_test.dart` (flusso passi 0→1) |
| 7 | Font eccessivi, a capo e overflow | Scala tipografica unica in `AppTheme` (display 28 … labelSmall 11, Poppins ridotta ~10%), titoli card `w600`, anello "Controlli di oggi" 88 dp, etichette pulsanti 15 sp, `MediaQuery.withClampedTextScaling` 0.9–1.15 | `layout_fixes_test.dart`: nessun overflow a 360×640 con scala 1.15 |
| 8 | Landscape | Fogli limitati allo spazio utile, wizard compatto sotto 600 dp di altezza, contenuti scrollabili | Verifica manuale (checklist) |
| 9 | Impostazioni → Stampante: la barra di navigazione copriva l'ultimo pulsante ("Anteprima") | `screenPadding(context, horizontal: 16)` al posto di `EdgeInsets.all(16)`: la lista scorre SOPRA la barra e l'ultimo elemento resta visibile e tappabile (3 tasti e gesti). Controllo trasversale con grep su tutte le schermate pushate (cloud backup, licenza, lotti, altro, NC, restore wizard, temperature, allegati, guida, ricevute, infestanti, dashboard): tutte usavano già `screenPadding` o SafeArea; l'unico difetto era la schermata Stampante | `layout_fixes_test.dart`: inset 48 simulato, 360×640, bordo inferiore di "Anteprima" sopra 640−48 |
| 10 | Schermata Stampante: pulsanti con larghezze diverse (Wrap con prova/anteprima/scollega disallineati) | Regola di layout: **azioni primarie a larghezza piena (52 dp), azioni secondarie in coppia a larghezza uguale** ("Anteprima"/"Scollega" con `Expanded`×2; "Anteprima" sola se non c'è una stampante collegata). "Cerca stampanti" a riga piena con icona stato 52×52 fissa. Contenuto centrato con `ConstrainedBox(maxWidth: 640)` per i tablet; etichette con `FittedBox(scaleDown)` (mai tagliate); righe del formato in Card con lo stesso allineamento dei motori; `isExpanded` sul menu a tendina. `cloud_backup_screen` e `license_screen` verificate: non mostrano il difetto (nessun pulsante sparso in Wrap) | `layout_fixes_test.dart`: 360×640 e 412×915, scala 1.0 e 1.15: primaria a larghezza piena, coppia uguale, stesso margine, nessun overflow |
| 11 | Il tasto/gesto Indietro chiudeva l'app dalla schermata principale senza chiedere | `ExitConfirmScope` (PopScope): dialog "Uscire da HACCPass?" con "Resta"/"Esci" SOLO sulle radici (shell, primo avvio, wizard al passo 0). Dalla shell, se la scheda non è "Oggi" Indietro prima torna a "Oggi"; schermate pushate e fogli si chiudono normalmente (il PopScope della radice non scatta sotto altre route). `android:enableOnBackInvokedCallback="true"` nel manifest per il predictive back (Android 13+/14+) | `exit_confirm_test.dart`: dialog da "Oggi" (Resta non esce, Esci esce), tab → "Oggi", route pushata e foglio modale chiusi senza dialog |
| 12 | Scheda lotto: tre pulsanti + graffetta in una `Row` di `Expanded` → ~90 dp ciascuno, testo **una lettera per riga**, card inutilizzabile | Nuovo `ActionButtonRow` (`common_widgets.dart`): N pulsanti **uguali in orizzontale**, icona sopra e testo sotto su UNA riga (`FittedBox(scaleDown)`, mai parole spezzate), altezza 56, area tappa ≥ 48, `Semantics(button)` + tooltip; sotto i 72 dp per pulsante → griglia a due colonne uguali. Scheda lotto a 4 azioni (Stampa, Etichetta, Rintraccio, **Allegati** con testo). Stessa correzione dove c'erano 3+ azioni in riga: **Acqua e ghiaccio** (Analisi/Filtri/Ghiaccio) e **scheda non conformità** (Risolvi-o-Modulo/Cartello/Allegati). Titolo lotto maxLines 2 + codice una riga. REGOLA DI PROGETTO: **più di due azioni in riga → `ActionButtonRow`; mai `Expanded(OutlinedButton.icon)` con tre o più pulsanti** (il `minimumSize` del tema NON si tocca) | `layout_fixes_test.dart`: 320/360/412 × scala 1.0/1.15 (a 320 griglia 2×2 come da regola), 240 dp → griglia, tocchi ai callback |
| 13 | Form stampante generica: overflow del menu Trasporto (voci disabilitate lunghe misurate TUTTE dal dropdown), campo "Dispositivo BLE" attaccato al menu, chip sparsi senza titolo, "Salva e collega" di larghezza diversa | Voci brevi + `selectedItemBuilder` con ellissi e `isExpanded`; campi uno sotto l'altro con spazio fisso 12 e helperText; gruppi con titolo e `SegmentedButton` a segmenti uguali (Linguaggio, Risoluzione, Larghezza carta); Avanzate a larghezza piena; "Salva e collega" piena 52; diagnostica a piena larghezza; guida "La stampante non stampa?"; sezioni Brother/Niimbot verificate coerenti | `printer_settings_screen_test.dart`: BLE e Wi-Fi a 320/360/412 × 1.0/1.15 senza overflow; inset 48: ultima sezione sopra la barra |

## Checklist di verifica manuale (telefono Android reale)

Combinazioni da provare: **tema chiaro/scuro** × **font di sistema 100% e
130%** × **navigazione a 3 tasti e a gesti** × **portrait e landscape** ×
**larghezza 360 dp e 412 dp**.

1. **Oggi**: titolo e orologio non si sovrappongono; nessun testo sotto la
   barra di stato; anello percentuale leggibile.
2. **Controlli** (da tab e da push tramite "Pulizie"/"Merce in arrivo"):
   sfondo del tema, titolo leggibile, freccia indietro se pushata.
3. **Foglio "Registra temperatura"** (anche con esito fuori limite): il
   pulsante "Salva controllo" è interamente visibile sopra barra di sistema
   e tastiera; le azioni correttive lunghe vanno a capo senza troncamenti.
4. **Pulizie**: "Fatto/Problema" su una riga senza spezzare parole
   (verificare anche a 320-360 dp: pulsanti impilati); l'ultima card non è
   coperta dal FAB; il badge "Da fare oggi" non comprime il titolo.
5. **Wizard passi 1-12**: "Salta questo passo" su una riga propria;
   Riepilogo senza "Avanti" con "Inizia" fisso in basso; barra mai coperta
   dalla navigazione di sistema; in landscape riga unica compatta.
6. **Generale**: nessun overflow (strisce gialle/nere), nessuna schermata
   nera, nessun errore in console (`flutter run --verbose` se serve).
7. **Stampante / Licenza / Backup / Altro** (Prompt 14): con navigazione
   a 3 TASTI e con GESTI, l'ultimo elemento di ogni schermata resta
   interamente visibile e tappabile sopra la barra; nessun contenuto
   coperto. Nella schermata Stampante: "Stampa etichetta di prova" a
   larghezza piena, "Anteprima"/"Scollega" della stessa larghezza tra
   loro, "Cerca stampanti" con l'icona di stato allineata a destra.
8. **Indietro** (Prompt 14, solo Android): dalla scheda "Oggi" compare
   "Uscire da HACCPass?" con "Resta"/"Esci"; da Controlli/Lotti/Report/
   Altro si torna prima a "Oggi" senza dialog; le schermate aperte via
   push e i fogli (Registra temperatura, etichetta lotto…) si chiudono
   normalmente con Indietro; nel wizard al primo passo compare la
   conferma, dai passi successivi torna al passo precedente. Provare
   sia il tasto triangolo sia il gesto (predictive back).
9. **Lotti e produzione** (Prompt 16): scheda lotto con 4 pulsanti
   uguali in orizzontale (Stampa/Etichetta/Rintraccio/Allegati), testo
   su una riga, a 360 e 412 dp con font 100% e 130% e con navigazione a
   3 tasti e a gesti; a 320 dp i pulsanti passano su due righe uguali
   (mai testo verticale). Stesso controllo su Acqua e ghiaccio e scheda
   non conformità. Foglio "Nuovo lotto": menu prodotto, "Nuovo prodotto"
   e fogli senza overflow a 320/412 e font 115%.

Stato: fix applicati e coperti da test automatici
(`flutter test test/layout_fixes_test.dart`); la checklist sopra va
eseguita e firmata su dispositivo prima della pubblicazione.

## Note

- Landscape: tutte le schermate restano scrollabili; nessun orientamento è
  bloccato. Se in futuro una schermata non supporta il landscape, bloccare
  il verticale solo lì e documentarlo qui.
- Scala testo: l'app limita il font di sistema tra 0.9 e 1.15
  (`main.dart`): a 1.15 non ci sono overflow; oltre, il sistema operativo
  mostra comunque testi più grandi nelle schermate native (picker, dialog
  di condivisione).
- I due test storicamente rossi in `onboarding_flow_test.dart` erano causati
  dalle future dell'isolate `sqflite_ffi` mai consegnate nel FakeAsync dei
  widget test: ora usano `tester.runAsync` e passano.
