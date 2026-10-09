# PROMPT 14 — Schermata Stampante (barra di sistema, larghezze uniformi) e conferma di uscita con il tasto Indietro — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Tre interventi: (1) in **Impostazioni → Stampante** la barra di navigazione di Android (i tre tasti) copre il pulsante "Anteprima" in fondo alla lista; (2) i pulsanti della schermata hanno larghezze diverse (la prova è larga, "Anteprima" stretto, "Scollega" a parte): vanno uniformati; (3) toccando il tasto **Indietro** di Android dalla schermata principale l'app si chiude subito: serve una conferma. Prima di modificare leggi `lib/screens/printer_settings_screen.dart` (`build`, ~righe 365–560 con il blocco `Wrap` dei pulsanti), `lib/widgets/common_widgets.dart` (`screenPadding`), `docs/qa_layout.md`, `lib/screens/app_shell.dart`, `lib/main.dart`, `lib/screens/first_run_choice_screen.dart`, `lib/screens/onboarding/onboarding_screen.dart`, `android/app/src/main/AndroidManifest.xml`. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Barra di sistema che copre l'ultimo pulsante

Causa: l'app è edge-to-edge e `printer_settings_screen.dart` usa `ListView(padding: const EdgeInsets.all(16))`, che non somma l'inset inferiore della barra di navigazione (diversamente dalle altre schermate, che usano `screenPadding`, Prompt 6).

- Sostituisci il padding con `screenPadding(context, horizontal: 16)` (o equivalente che includa `MediaQuery.paddingOf(context).bottom` + 32 dp di respiro). Il contenuto deve poter scorrere sopra la barra: l'ultimo elemento (sezione "Stampanti salvate" o pulsanti) resta interamente visibile e tappabile con navigazione a 3 tasti **e** a gesti.
- **Controllo trasversale** (stesso difetto probabile altrove): cerca con grep i `ListView(`/`SingleChildScrollView(` con `padding: const EdgeInsets.all(…)` o `EdgeInsets.symmetric(...)` senza `screenPadding` nelle schermate raggiungibili da push: oggi compaiono in `cloud_backup_screen.dart`, `license_screen.dart`, `lots_screen.dart`, `more_screen.dart`, `non_conformities_screen.dart`, `restore_wizard_screen.dart`, `temperature_screen.dart`, `attachment_storage_screen.dart`, `guide_screen.dart`, `receipts_screen.dart`, `pests_screen.dart`, `dashboard_screen.dart`. Per ognuna verifica con inset simulato (48 dp) che l'ultimo elemento non sia coperto e applica `screenPadding` dove serve (`hasBottomBar`/`hasFab` se presenti), senza cambiare l'aspetto del resto.
- Aggiungi la voce al `docs/qa_layout.md` (tabella fix + checklist manuale: Stampante, Licenza, Backup, Altro, con 3 tasti e con gesti).
- Test (`layout_fixes_test.dart`): `PrinterSettingsScreen` con `MediaQuery` di `padding.bottom = 48` e schermo 360×640: scorri in fondo, il pulsante "Anteprima" (o l'ultimo elemento) ha il bordo inferiore **sopra** `640 − 48`.

## 2. Larghezze uniformi nella schermata Stampante

Oggi: "Stampa etichetta di prova" occupa metà schermo, "Anteprima" è più stretto e finisce sotto, "Scollega" è un terzo pulsante di larghezza diversa nel `Wrap`; "Cerca stampanti" + icona info hanno una larghezza propria; le card dei motori sono a tutta larghezza.

- Contenuto della schermata dentro un contenitore centrato con larghezza massima (es. `ConstrainedBox(maxWidth: 640)`) così su tablet non si allarga all'infinito; i margini laterali sono gli stessi per tutti gli elementi (16 dp).
- Pulsanti d'azione **tutti a larghezza piena e stessa altezza (52 dp)**, impilati con 8–12 dp di spazio, nell'ordine: "Stampa etichetta di prova" (riempito), poi una **riga con due pulsanti uguali** (`Expanded` ×2, stessa altezza): "Anteprima" e "Scollega" (se c'è una stampante collegata; se manca, "Anteprima" occupa tutta la riga). Niente `Wrap` per i pulsanti.
- "Cerca stampanti": pulsante a larghezza piena con l'icona stato (info) dentro la stessa riga con larghezza fissa 52×52; altezza 52 dp come gli altri.
- Card dei motori, card avvisi, card nota e le righe del formato etichetta: stesso allineamento e raggio; i `RadioListTile` del formato con riempimento uniforme (oggi il testo è molto rientrato rispetto alle card: allinea il rientro al bordo sinistro delle card, `contentPadding` coerente).
- Nessuna riga più larga dello schermo: a 360 dp e scala testo 1.15 nessun overflow (le etichette dei pulsanti vanno a capo su due righe o si adattano con `FittedBox(scaleDown)`, mai tagliate).
- Applica la **stessa regola di larghezza** (pulsanti d'azione a larghezza piena/coppie uguali, stesso margine laterale) alle altre schermate di impostazioni che hanno pulsanti sparsi in `Wrap` con larghezze diverse, **senza** ridisegnare le schermate: limita l'intervento a `cloud_backup_screen.dart` e `license_screen.dart` solo se mostrano lo stesso difetto; documenta in `docs/qa_layout.md` la regola ("azioni primarie a larghezza piena, azioni secondarie in coppia a larghezza uguale").
- Test widget: a 360×640 e 412×915, scala testo 1.0 e 1.15, i pulsanti "Stampa etichetta di prova", "Cerca stampanti" hanno la stessa larghezza; "Anteprima" e "Scollega" hanno larghezze uguali tra loro; nessun overflow.

## 3. Conferma di uscita con il tasto Indietro (solo Android)

Oggi, dalla schermata principale, il tasto/gesto Indietro chiude l'app senza chiedere nulla.

- Nuovo widget riutilizzabile `ExitConfirmScope` (`lib/widgets/exit_confirm_scope.dart`) basato su `PopScope(canPop: false, onPopInvokedWithResult: …)`: se l'invio non è già stato gestito (`didPop == false`) mostra un `AlertDialog` in italiano — titolo "Uscire da HACCPass?", testo "I tuoi dati sono al sicuro e salvati sul telefono.", pulsanti "Resta" (secondario, predefinito) e "Esci" (primario) — e solo con "Esci" chiude l'app con `SystemNavigator.pop()`.
- Dove si applica (**solo** schermate radice, mai quelle pushate): `AppShell` (le schede principali), e il flusso iniziale senza schermata sotto (`FirstRunChoiceScreen` e l'onboarding a passo 1 quando non c'è un passo precedente). Il comportamento resta quello attuale ovunque altrove: le schermate pushate tornano indietro normalmente; i fogli modali e i dialog si chiudono con Indietro **prima** (il `PopScope` della radice non scatta finché sopra c'è un'altra route).
- Dentro `AppShell`: se la scheda attiva **non** è la prima ("Oggi"), Indietro prima torna alla scheda "Oggi" (senza dialog); solo se si è già su "Oggi" compare la conferma. Nel wizard di onboarding, Indietro dai passi successivi al primo torna al passo precedente (già così: non rompere); al primo passo senza schermata sotto, conferma di uscita.
- Non toccare i `PopScope` già esistenti (restore wizard in corso, recupero foto, scansione documenti): hanno priorità e non devono mostrare la conferma di uscita.
- Android 13+ / predictive back: imposta `android:enableOnBackInvokedCallback="true"` sull'`<application>` del manifest (necessario perché `PopScope` intercetti il gesto su Android 14+) e verifica che la conferma compaia sia con il tasto triangolo sia con il gesto.
- iOS: nessun cambiamento (non esiste il tasto Indietro di sistema); desktop di sviluppo: nessun dialog.
- Nessuna conferma se in quel momento è in corso un'operazione critica già gestita altrove; nessun testo che prometta più di quel che l'app garantisce (dati "al sicuro" = salvati sul telefono; se l'ultimo backup non è recente non dire altro).
- Test widget: (a) dalla scheda "Oggi" Indietro mostra il dialog; "Resta" chiude solo il dialog; "Esci" chiama l'uscita (usa un handler iniettabile per non terminare il test); (b) da un'altra scheda Indietro torna a "Oggi" senza dialog; (c) con una schermata pushata Indietro torna alla radice senza dialog; (d) con un foglio modale aperto Indietro lo chiude senza dialog.

## Criteri di accettazione

1. In Impostazioni → Stampante l'ultimo pulsante è sempre interamente visibile e tappabile sopra la barra di navigazione (3 tasti e gesti).
2. I pulsanti hanno larghezze coerenti: azioni primarie a larghezza piena, "Anteprima"/"Scollega" in coppia uguale; nessun overflow a 360 dp con scala testo 1.15.
3. Le altre schermate pushate elencate non hanno contenuto coperto dalla barra di sistema (verificato con test a inset 48).
4. Il tasto/gesto Indietro dalla schermata principale (scheda "Oggi") mostra "Uscire da HACCPass?" con "Resta"/"Esci"; dalle altre schede torna a "Oggi"; schermate pushate e fogli si chiudono normalmente.
5. `enableOnBackInvokedCallback` attivo; `docs/qa_layout.md` aggiornato; `flutter analyze` e `flutter test` verdi.
