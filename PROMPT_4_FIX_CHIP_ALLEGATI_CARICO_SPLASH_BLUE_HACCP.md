# PROMPT 4 — Fix chip illeggibili, allegati in fase di carico merce/lotti, splash con logo (Blue HACCP)

Lavora per fasi. Dopo ogni fase esegui `flutter analyze` e `flutter test`. Nessuna modifica distruttiva al DB (versione attuale 4: se serve, migrazione incrementale a 5).

---

## FASE A — Fix grafici (chip, titolo wizard)

### A1. Chip selezionati con testo illeggibile (CAUSA ESATTA)
Screenshot: chip selezionati (frequenze nel wizard passo 5, fornitore/categoria in "Nuova merce in arrivo", Sì/No dei controlli) hanno sfondo teal scuro e testo scuro/verde/rosso illeggibile.

Cause in `lib/core/theme/app_theme.dart`:
1. `ColorScheme.light/dark(...)` imposta `secondary: primary` senza `secondaryContainer`. Il costruttore usa come fallback `secondary`, quindi i `ChoiceChip`/`FilterChip` selezionati (che in Material 3 usano `secondaryContainer`) diventano teal pieno.
2. `chipTheme.labelStyle` ha colore fisso `onSurfaceVariant` (scuro) anche da selezionato → testo scuro su teal scuro.
3. In `receipts_screen.dart::_checkTile` le etichette Sì/No forzano `colors.success` / `colors.danger` come colore del testo, quindi sul chip selezionato diventano verde/rosso scuro su teal.

**Fix:**
- Definisci nello `ColorScheme` esplicitamente: light `secondaryContainer: #D3ECEA`, `onSecondaryContainer: #064A47`; dark `secondaryContainer: #0A5450`, `onSecondaryContainer: #C9F2EE`.
- Nel `chipTheme` usa `WidgetStateProperty`/stati:
  - `backgroundColor`: surface (non selezionato); `selectedColor`: `secondaryContainer`.
  - `labelStyle` con colore dipendente dallo stato: non selezionato `onSurface`, selezionato `onSecondaryContainer` (usa `WidgetStateTextStyle.resolveWith` oppure `labelStyle` + `secondaryLabelStyle`).
  - `checkmarkColor: onSecondaryContainer`, `iconTheme` coerente.
  - bordo: non selezionato `outline` (3:1), selezionato `primary` spessore 1.5.
  - padding minimo per area di tocco 48 dp (`materialTapTargetSize`).
- Rimuovi gli override di colore del testo nei chip: in `_checkTile` (`receipts_screen.dart`) lascia al tema il colore del testo. Per distinguere Sì/No usa un'icona (✓ verde / ✕ rosso) nel chip e uno sfondo selezionato semantico: Sì selezionato = `successBg` + testo `success`; No selezionato = `dangerBg` + testo `danger` (coppie con contrasto ≥ 4.5:1 verificato).
- Crea un widget riusabile `ChoiceChipX`/`SegmentedChoice` in `common_widgets.dart` e sostituisci tutti i `ChoiceChip`/`FilterChip` sparsi (products_screen, receipts_screen, lots_screen, modules_screens, structures_screen, onboarding_steps, temperature_screen, common_widgets `ChoiceRow`) così lo stile è unico.
- Test widget golden/contrasto: per ogni combinazione (light/dark, selezionato/non, abilitato/disabilitato) il testo ha contrasto ≥ 4.5:1 sullo sfondo del chip.
- Chip disabilitati (switch spento nel wizard): testo visibile con `onSurface` al 60% e sfondo neutro, mai invisibili.

### A2. Wizard passo 5 (layout)
- Titolo AppBar troncato ("Passo 5 di 12..."): mostra su due righe: titolo grande `stepTitle`, sottotitolo piccolo "Passo 5 di 12"; oppure barra di avanzamento con testo breve. Rimuovi il troncamento.
- Le frequenze (7-8 chip) occupano troppo spazio: sostituisci con un unico campo/menu "Frequenza: Settimanale ▾" (bottom sheet di scelta o `DropdownMenu`) per ogni voce; resta lo switch di attivazione. Chip solo per le 3-4 frequenze più comuni se serve.
- Card più compatte, testo del chip ≥ 12 sp (non 11).

### A3. Altri controlli
- Verifica Switch, Checkbox, Radio, SegmentedButton, DropdownMenu, FilterChip nei due temi: testo e icone ≥ 4.5:1, bordi ≥ 3:1. Switch: traccia on = `primary`, thumb = `onPrimary`; off = traccia `surfaceContainerHighest` con bordo `outline`.
- Riesegui la scansione di `Colors.white`, `Colors.black`, `Color(0x...)` hardcoded fuori dal tema e sostituiscili con token.

---

## FASE B — Allegare foto/documenti già nella registrazione del carico merce e dei lotti

Oggi gli allegati si aggiungono solo dopo, dal pulsante "Foto e documenti" sulla card. Richiesta: allegare **durante la registrazione**.

### B1. Carico merce (`receipts_screen.dart::_newReceipt`)
- Nel form "Nuova merce in arrivo" aggiungi la sezione **"Documenti e foto"** sopra il pulsante Registra, con tre azioni: **Scatta foto DDT/etichetta**, **Scegli da galleria**, **Aggiungi file (PDF)**. Mostra miniature (immagini) e icone (PDF) con pulsante rimuovi; più allegati ammessi.
- Poiché il record non ha ancora un id, tieni gli allegati in una lista temporanea in memoria/cartella temporanea (`PendingAttachment { tempPath, kind, note }`) e, a salvataggio riuscito, registrali con `AttachmentService` usando l'id della merce creata (`AttachmentEntity.receipt`). Se l'utente annulla, elimina i file temporanei. Nessun allegato orfano.
- Aggiungi in `AttachmentService` un metodo `attachPending(entity, entityId, List<PendingAttachment>)`, e metodi `capturePhotoTemp()/pickPhotoTemp()/pickDocumentTemp()` che restituiscono il file senza creare record (stessa compressione 1600 px / qualità 80, nome file con data).
- Tipo allegato preimpostabile: "DDT", "Etichetta/lotto", "Certificato", "Altro" (menu rapido dopo lo scatto, opzionale).
- Facoltativo ma consigliato: se la merce ha esito RESPINTA, suggerisci "Scatta foto del problema" e collega gli allegati anche alla NC aperta automaticamente.
- Mostra nella card merce un'icona graffetta con il numero di allegati (già presente come pulsante: aggiungi badge).
- I PDF del registro ricevimento merci includono (opzionale, impostazione "Includi miniature allegati") le miniature delle foto DDT in appendice.

### B2. Lotti (`lots_screen.dart`)
- Stessa sezione "Documenti e foto" nel form di creazione/modifica lotto (foto etichetta del fornitore, foto del prodotto, scheda tecnica). Stesso flusso `PendingAttachment` con `AttachmentEntity.lot`.
- Nella traccia di rintracciabilità (`traceability_screen`) mostra gli allegati del lotto e della merce collegata.
- Se il lotto è generato da una merce in arrivo, offri "Copia gli allegati dal carico" per evitare doppi scatti.

### B3. Permessi e robustezza
- Permesso fotocamera chiesto solo al primo scatto, con messaggio in italiano e fallback alla galleria se negato.
- Android: file temporanei in `getTemporaryDirectory()`, definitivi nella cartella allegati dell'app; iOS: verifica `NSCameraUsageDescription` e `NSPhotoLibraryUsageDescription` (testi in italiano).
- Test: creazione merce con 2 allegati → 2 record `attachments` con `entity='receipt'` e id corretto; annullamento → nessun file residuo; backup/ripristino includono gli allegati.
- Il backup cloud (Google Drive) deve includere gli allegati nuovi come già previsto dal Prompt 2.

---

## FASE C — Splash screen e icona con il logo

L'utente ha aggiunto la cartella `assets/` con il logo di avvio. **Nota per chi implementa: al momento del controllo `assets/` conteneva solo `fonts/` (Poppins), nessun file logo.** Prima di procedere cerca il file del logo (`assets/images/`, `assets/logo*`, `assets/splash*`); se manca, fermati e chiedi il file all'utente senza inventare un logo.

Quando il logo è presente:
1. Dichiara in `pubspec.yaml` `assets/images/` (o il percorso reale) oltre a `assets/fonts/`.
2. **Splash nativa:** aggiungi `flutter_native_splash` (dev) con sfondo `#F1F5F4` (light) e `#0E1615` (dark), logo centrato; Android 12+ con icona/branding dedicata; iOS LaunchScreen. Esegui `dart run flutter_native_splash:create`.
3. **Splash in-app (`_Root`):** mentre si inizializzano DB/licenza/reminder mostra il logo con una breve animazione (fade/scale 400 ms, rispetta `MediaQuery.disableAnimations`), poi transizione al wizard/home. Durata minima 800 ms, massima non bloccante.
4. **Icona app:** se il logo è quadrato ad alta risoluzione (≥ 1024 px) genera le icone con `flutter_launcher_icons` (Android adaptive con foreground + sfondo `#0B6B66`, iOS senza trasparenza). Se non è adatto, segnalalo.
5. Usa il logo anche nell'intestazione dei PDF (se l'utente non ha caricato il proprio logo aziendale) e nella schermata "Informazioni/Licenza", in una versione chiara/scura se disponibile.
6. Verifica la qualità: logo nitido su schermi 3x, contrasto sullo sfondo light e dark (se il logo è scuro fornisci variante chiara per il dark o un contenitore chiaro).

---

## Criteri di accettazione
1. Chip selezionati e non selezionati leggibili (≥ 4.5:1) in light, dark e testo 130%; nessun `Color` hardcoded per il testo dei chip.
2. Wizard passo 5: titolo non troncato, frequenze in un menu compatto, nessun overflow a 360 dp di larghezza.
3. Dal form di nuova merce e di lotto si possono scattare/scegliere foto e PDF prima del salvataggio; nessun allegato orfano se si annulla; gli allegati compaiono nella card, nel backup e nei PDF (opzionale).
4. Splash nativa e in-app con il logo, icona app generata; se il logo manca, richiesta all'utente.
5. `flutter analyze` pulito, test aggiornati/aggiunti (contrasto chip, flusso allegati pendenti).
