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
