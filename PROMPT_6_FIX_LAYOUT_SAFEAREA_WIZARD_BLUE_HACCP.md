# PROMPT 6 — Fix layout: barre di sistema, schermata nera, wizard, font (Blue HACCP)

Questo prompt è solo testuale (nessuna immagine allegata): ogni problema è descritto con sintomo, causa probabile, file e correzione. Prima di modificare, verifica nel codice lo stato attuale: alcune correzioni dei Prompt 3 e 4 (AppBar, sfondi, chip) potrebbero essere già parziali; non rifarle, completale. Dopo ogni gruppo di fix esegui `flutter analyze` e `flutter test`. Test su telefono Android reale con navigazione a 3 tasti e con gesti.

Contesto tecnico: l'app gira in modalità edge-to-edge (Android 15 / targetSdk recente): i contenuti si estendono SOTTO barra di stato (ora, icone) e barra di navigazione di sistema (3 tasti o gesture bar). Ogni schermata deve gestire questi inset.

---

## 1. Contenuti sotto la barra di stato (titolo coperto dall'ora)

**Sintomo:** nella schermata "Oggi" il titolo/saluto in alto si sovrappone all'orologio e alle icone di stato; stessa cosa in "Controlli". L'ora non si legge.

**Causa:** i `ListView` delle schermate usano `padding: EdgeInsets.fromLTRB(20, 16, 20, 32)` esplicito. Quando si passa `padding` a un `ListView`, Flutter NON aggiunge più automaticamente l'inset di sistema (`MediaQuery.padding`). Succede su dashboard, hub controlli e le altre schermate tab senza AppBar.

**Fix:**
- Crea in `common_widgets.dart` un helper `EdgeInsets screenPadding(BuildContext c, {double top=16, double bottom=32, double horizontal=20, bool hasBottomBar=false, bool hasFab=false})` che somma: `MediaQuery.paddingOf(c).top` (solo se la schermata non ha AppBar), `MediaQuery.paddingOf(c).bottom` (solo se non c'è la bottom bar che già lo gestisce) e un extra di 88 dp se `hasFab`.
- Applicalo a TUTTI i `ListView`/`SingleChildScrollView` radice: dashboard_screen, checks_hub_screen, lots_screen, reports_screen, more_screen e tutte le schermate di funzione. Cerca con grep `padding: const EdgeInsets.fromLTRB(20, 16` e simili.
- In alternativa avvolgi il body in `SafeArea(bottom: false)` quando la schermata non ha AppBar. Scegli UN solo approccio e usalo ovunque.
- Imposta lo stile della status bar per tema (`AnnotatedRegion<SystemUiOverlayStyle>` o `SystemChrome.setSystemUIOverlayStyle`): icone scure su sfondo chiaro, chiare su dark, barra trasparente, e `systemNavigationBarContrastEnforced` coerente.

## 2. Schermata "Controlli" nera con testi illeggibili

**Sintomo:** aprendo "Controlli" (hub dei registri) lo sfondo è nero, titolo "Controlli" e sottotitolo quasi invisibili (scuro su nero), assente la barra di navigazione inferiore e l'ora di sistema non si legge. Le card bianche sono corrette.

**Causa:** `ChecksHubScreen` restituisce direttamente un `ListView` senza `Scaffold`. Se viene aperta con `Navigator.push` (da `app_shell._openTarget` o da altre schermate) non c'è alcun `Material`/`Scaffold` dietro: sfondo nero e nessuna AppBar.

**Fix:**
- Se la schermata è una TAB della shell: lascia come sta ma con padding corretto (punto 1).
- Se è aperta via `push`: avvolgi in un `FeatureScaffold` (Scaffold + AppBar con freccia indietro e titolo, sfondo del tema, `SafeArea`).
- Regola generale: nessuna schermata pushata può restituire un widget senza `Scaffold`. Aggiungi un test widget che apre ogni schermata raggiungibile dal menu e verifica la presenza di `Scaffold` con sfondo non trasparente.

## 3. Fogli modali (bottom sheet) coperti dalla barra di sistema

**Sintomo:** nel foglio "Abbattitore" (registrazione temperatura) il pulsante "Salva controllo" in basso è sovrapposto/coperto dalla barra di navigazione di sistema; il foglio sale fin sotto la barra di stato.

**Causa:** `showFormSheet` (`common_widgets.dart`, ~riga 508) non usa `useSafeArea`, imposta `maxHeight = 85% dell'altezza schermo` (inclusa la barra di sistema) e non aggiunge `MediaQuery.viewPaddingOf(context).bottom` sopra il pulsante.

**Fix:**
- `showModalBottomSheet(useSafeArea: true, isScrollControlled: true, ...)`.
- Altezza massima = `(altezza - padding.top) * 0.92` oppure `DraggableScrollableSheet`; contenuto scrollabile, pulsante Salva **fisso in basso** in una barra con `SafeArea(top:false)` e padding inferiore `max(16, viewPadding.bottom)`.
- Con tastiera aperta il pulsante resta visibile sopra la tastiera (usa `viewInsets.bottom`).
- Applica lo stesso a tutti gli altri `showModalBottomSheet`/`showAttachmentsSheet`/dialog personalizzati.

## 4. Chip e testi lunghi tagliati

**Sintomo:** nelle "Azioni correttive adottate" le opzioni lunghe sono tagliate a destra ("Verificata chiusura della porta e delle guarnizi…", "Valutato il prodotto per aspetto e tempo/temp…"), senza andare a capo.

**Fix:** per i chip/azioni con testo lungo usa etichette multilinea (`Text(maxLines: 2, softWrap: true)`) e `ConstrainedBox(maxWidth: larghezza disponibile)`; oppure sostituiscili con `CheckboxListTile` densi (più adatti a testi lunghi, area di tocco ≥ 48 dp). Mai `overflow: clip` silenzioso. Aggiungi test con testo ingrandito 130%.

## 5. Pulsanti "Fatto / Problema" e FAB che copre i contenuti (Pulizie)

**Sintomo:** nella schermata "Pulizie e sanificazione" il pulsante "Problema" va a capo a metà parola ("Problem" / "a"); il pulsante flottante "+ Attività" copre la parte bassa dell'ultima card (es. badge di stato).

**Fix:**
- Riga azioni: `Fatto` e `Problema` in `Row` con `Expanded` ma etichette `maxLines: 1` e `FittedBox(fit: scaleDown)`, oppure riduci icona/padding; sotto 360 dp di larghezza impila i due pulsanti in colonna. Mai andare a capo dentro una parola.
- Il titolo lungo ("Attrezzature meccaniche (affettatrice, tritacarne)") e il badge "Da fare oggi" non devono comprimersi a vicenda: se manca spazio il badge va sotto il titolo (usa `Wrap`).
- ListView con `padding.bottom ≥ 88 + inset` quando c'è un FAB (helper del punto 1, `hasFab: true`) così l'ultima card scorre sopra il FAB. Valuta di sostituire il FAB esteso con un FAB compatto (solo icona "+") sotto i 360 dp.

## 6. Wizard (configurazione guidata): barra inferiore

**Sintomo:** nel passo 11 di 12 il pulsante "Salta questo passo" è schiacciato in una colonna stretta tra "Indietro" e "Avanti" e il testo va a capo lettera per lettera ("Salta / ques / to / pass / o"). Nel passo 12 (Riepilogo) compare ancora "Avanti" accanto a "Indietro" anche se è l'ultimo passo e c'è già "Inizia".

**Fix in `onboarding_screen.dart` (bottomNavigationBar ~riga 222):**
- Nuovo layout a due livelli: riga 1 = `Indietro` (outlined, larghezza fissa) + `Avanti` (filled, `Expanded`); riga 2 (solo se il passo è saltabile) = `TextButton('Salta questo passo')` centrato a larghezza piena, testo su una riga, altezza minima 40 dp. Se lo spazio verticale è scarso (landscape o altezza < 600 dp) metti "Salta" sulla stessa riga come testo breve "Salta" con `Tooltip`/semantica completa "Salta questo passo".
- **Ultimo passo (Riepilogo):** rimuovi il pulsante "Avanti" (resta "Indietro" e il pulsante principale "Inizia" già presente nel corpo, che deve essere ben visibile e fisso in basso). La barra di avanzamento resta al 100%.
- Il passo 0 (benvenuto) mostra solo "Avanti" (già così).
- Tutta la barra dentro `SafeArea` con padding inferiore che rispetta la barra di navigazione (non coperta).
- Landscape: il contenuto del passo scorre; la barra inferiore occupa al massimo ~64 dp (una riga sola: Indietro | Salta | Avanti con testi brevi).

## 7. Riduzione dei font e scala tipografica

**Sintomo:** testi molto grandi (es. "0 su 19 completati" nella card Oggi; "Completa la configurazione: 90%"; titoli delle card) occupano troppo spazio e causano a capo.

**Fix:**
- Definisci una scala unica in `AppTheme` (Poppins è largo, scendi di ~10%): displayLarge/hero 28, headlineSmall 20, titleLarge 18, titleMedium 15, titleSmall 14, bodyLarge 15, bodyMedium 14, bodySmall 12, labelLarge 14, labelSmall 11–12 (mai sotto 11). Titoli di card `w600` invece di `w700/w800` dove possibile.
- Card "Controlli di oggi": numero grande max 28 sp, testo secondario 14 sp; anello percentuale 88 dp invece di ~110.
- `MediaQuery.withClampedTextScaling` (main.dart): porta il massimo da 1.3 a **1.15** (e min 0.9) per evitare rotture; verifica comunque che a 1.15 non ci siano overflow.
- Etichette pulsanti 14–15 sp; chip 12–13 sp.
- Mantieni ≥ 4.5:1 di contrasto e area di tocco ≥ 48 dp: ridurre il font non deve ridurre gli elementi toccabili.

## 8. Orientamento orizzontale (landscape)

- Verifica tutte le schermate in landscape su telefono (altezza ~360 dp): contenuti scrollabili, nessun overflow giallo/nero, bottom sheet con altezza massima limitata allo spazio disponibile e pulsante Salva sempre raggiungibile (barra azioni fissa o scroll).
- Wizard e dialog: su altezza < 500 dp usa layout compatto (meno padding, descrizioni collassabili).
- Se per certe schermate il landscape non è supportato, blocca l'orientamento verticale solo lì e documentalo; altrimenti deve funzionare.

---

## Checklist di verifica manuale (da eseguire e documentare nel README, `docs/qa_layout.md`)
Per ogni combinazione: tema chiaro/scuro × font di sistema 100% e 130% × navigazione a 3 tasti e a gesti × portrait e landscape × larghezza 360 dp e 412 dp:
1. Oggi: titolo e orologio non si sovrappongono; nessun testo sotto la barra di sistema.
2. Controlli (da tab e da push): sfondo del tema, titolo leggibile, freccia indietro se pushata.
3. Foglio "Registra temperatura" (anche con esito fuori limite): pulsante "Salva" interamente visibile sopra barra di sistema e tastiera; chip lunghi su più righe.
4. Pulizie: "Fatto/Problema" su una riga senza spezzare parole; l'ultima card non è coperta dal FAB.
5. Wizard passi 1–12: "Salta questo passo" su una riga; Riepilogo senza "Avanti"; barra non coperta dalla navigazione di sistema.
6. Nessun overflow (nessuna striscia gialla/nera) e nessun errore in console.

## Criteri di accettazione
- Nessun contenuto sotto barra di stato o di navigazione in nessuna schermata, foglio o dialog.
- Nessuna schermata con sfondo nero né senza Scaffold.
- Wizard: ultimo passo senza "Avanti"; "Salta" su una riga.
- Scala tipografica ridotta e clamp 0.9–1.15; nessun overflow a 130% di testo.
- Test widget automatici per: presenza Scaffold nelle schermate pushate, nessun overflow a 360×640 con scala 1.15 nelle schermate principali, pulsante Salva dei fogli visibile con inset di sistema simulati (`MediaQuery` con padding bottom 48).
- `flutter analyze` pulito.
