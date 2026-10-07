# PROMPT 11 — Stampa etichette: Brother (QL) e Niimbot a scelta del cliente — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Obiettivo: oggi `main.dart` usa `DemoPrinterService` (la stampa è **simulata**) e esiste anche `PdfPrinterService` (finestra di stampa del sistema). Servono stampanti vere, scelte dal cliente: **Brother serie QL** (via SDK ufficiale) e **Niimbot** (via Bluetooth LE), più il ripiego "Stampa di sistema (PDF)". Le etichette sono già generate come PDF da `PdfService` (`buildLotLabel` 62×40 mm, `buildEquipmentQrLabel` 62×40 mm, `buildTestLabel` 62×40 / 50×30 / 40×30 mm): **non riscrivere i layout**, rasterizza quei PDF. Prima di modificare leggi `lib/services/printer_service.dart`, `lib/services/pdf_service.dart` (tre funzioni citate), `lib/screens/lots_screen.dart` (~riga 504), `lib/screens/onboarding/onboarding_screen.dart` (~riga 149, passo stampante del wizard), `lib/screens/temperature/equipment_history_sheet.dart` (~riga 125), `lib/main.dart` (~riga 90). Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Architettura (una sola interfaccia, tre motori)

- Nuova interfaccia in `lib/core/printing/label_printer.dart`:
  - `String get id` (`'brother'`, `'niimbot'`, `'system'`, `'demo'`), `String get displayName`.
  - `Future<List<PrinterDevice>> discover()` (nome, identificativo, trasporto: wifi/ble/bluetooth/usb).
  - `Future<void> connect(PrinterDevice d)`, `Future<void> disconnect()`, `bool get isConnected`.
  - `Future<PrintResult> printLabels(List<Uint8List> pdfPages, LabelSpec spec, {int copies = 1})` che riceve **i byte PDF** già costruiti da `PdfService` e restituisce un risultato tipizzato (`ok`, `notConnected`, `paperError`, `labelSizeNotSupported`, `cancelled`, `failed(message)`).
  - `Future<PrinterStatus> status()` (connessa, carta, coperchio, batteria se disponibile).
- `LabelSpec` = larghezza/altezza in mm, densità, taglio automatico. La dimensione deriva dal formato scelto nel wizard (`labelFormat`: `62x40`, `50x30`, `40x30`).
- Motori: `BrotherLabelPrinter` (§2), `NiimbotLabelPrinter` (§3), `SystemLabelPrinter` (ripiego, usa `Printing.layoutPdf` come `PdfPrinterService` oggi), `DemoLabelPrinter` (solo debug, mantiene la simulazione e va nascosto in release).
- **Rasterizzazione condivisa** (`label_rasterizer.dart`): `Printing.raster(pdfBytes, dpi: …)` → immagine monocromatica con soglia regolabile (default 128), larghezza in pixel multipla di 8, risoluzione della stampante, bordi ritagliati con margine fisso. Test unitari: dimensioni in pixel per 62×40 e 50×30 alle risoluzioni dei due motori, soglia, nessuna pagina vuota.
- Sostituisci `PrinterService`/`DemoPrinterService`/`PdfPrinterService` con la nuova interfaccia mantenendo la compatibilità dei chiamanti; aggiorna `AppServices` per costruire il motore salvato nelle impostazioni (`printer_engine`, `printer_device_id`, `printer_label_format`, `printer_density`) e `main.dart` per iniettarlo. Nessun `DemoLabelPrinter` in release.

## 2. Brother (serie QL, es. QL-810W, QL-820NWB)

- Dipendenza: `brother_native_print` (verifica versione e piattaforme su pub.dev; dichiara verificati solo QL-820NWB e RJ-2050, quindi **QL-810W va provata**: segnala nel codice e nella documentazione che è "non verificata" finché non c'è una stampante reale).
- Connessione: **Wi-Fi** (preferita, funziona senza programma MFi su iOS) e USB su Android; Bluetooth consentito su Android; su iOS il Bluetooth richiede l'iscrizione MFi con PPID Brother: **nascondilo su iOS** salvo configurazione esplicita (flag `enableBrotherBluetoothIos = false`) e documenta il motivo in `docs/stampanti.md`.
- Ricerca: `discoverPrinters()` per modelli Brother. Per il Bluetooth classico su Android spiega che la stampante va associata prima nelle impostazioni del telefono. Permessi runtime Bluetooth (Android 12+) richiesti **solo** al momento di cercare/collegare, con spiegazione in italiano; mai all'avvio.
- Carta: mappa il formato dell'app sui rotoli DK (es. 62 mm continuo o 62×… pre-tagliato); se il rotolo montato non corrisponde al formato scelto restituisci `labelSizeNotSupported` con il messaggio "Rotolo montato non adatto: …". Taglio automatico a fine etichetta.
- Una sola connessione attiva: gestisci `disconnect()` e un tentativo di recupero (`cancelPrinting` → `disconnect` → nuovo `connect`) con messaggio chiaro se la stampante è occupata.
- Test: finto motore Brother con risposte simulate (connessa, carta assente, coperchio aperto, errore).

## 3. Niimbot (B21, B1, D110/D11)

- Dipendenza: `niim_blue_flutter` (BLE; Android minSdk 21, iOS 12+, MIT; basato su niimbluelib). Il pacchetto è recente e non ufficiale: **non basare nulla di critico sul protocollo**; incapsulalo interamente in `NiimbotLabelPrinter` e in un adattatore sottile così da poterlo sostituire.
- Rilevamento del modello e della larghezza massima di stampa **dal dispositivo/pacchetto** (non scrivere larghezze a mano): se il formato scelto è più largo dell'area stampabile mostra "Questa stampante non stampa etichette da NN mm: scegli un formato più piccolo o un'altra stampante" invece di tagliare in silenzio. I modelli D11/D110 hanno etichette molto strette e non adatte a un'etichetta HACCP completa: avvisa e permetti di continuare solo con il formato che entra.
- Immagine: bianco/nero puro, larghezza multipla di 8, densità 1–5 (default 3) configurabile in Impostazioni → Stampante, orientamento corretto (prova di stampa verifica la direzione), anteprima in app dell'immagine che sarà inviata (aiuta a vedere testi troppo piccoli).
- Permessi: Bluetooth e posizione per Android ≤ 11, Bluetooth per Android 12+ (con `permission_handler` se serve), `NSBluetoothAlwaysUsageDescription` già presente su iOS: chiedili solo alla prima ricerca.
- Avviso permanente nella schermata di configurazione: "Stampante consumer con protocollo non ufficiale: un aggiornamento del firmware potrebbe richiedere un aggiornamento dell'app. Etichette termiche: verifica l'adesione su contenitori freddi o umidi e usa etichette con adesivo removibile."

## 4. Configurazione per il cliente

- **Impostazioni → Stampante** (e il passo stampante del wizard, `onboarding_screen.dart`): scelta del motore con tre card ("Brother QL", "Niimbot", "Stampa di sistema"), pulsante "Cerca stampanti", elenco dispositivi, "Collega", formato etichetta, densità, **"Stampa etichetta di prova"** (usa `buildTestLabel` con il formato scelto) e stato (connessa / non trovata / carta).
- Nessuna stampante configurata = l'app resta pienamente utilizzabile: i pulsanti "Stampa etichetta" propongono di configurarla oppure di "Condividi etichetta come PDF" (usa `Printing.sharePdf`).
- Dopo un riavvio l'app ricorda motore e dispositivo e prova a riconnettersi **solo quando serve** (alla prima stampa), non all'avvio; se non riesce propone "Seleziona stampante".
- In `lots_screen.dart` e `equipment_history_sheet.dart` usa il motore configurato; il numero di copie resta quello scelto dall'utente; stampa a coda (una etichetta alla volta, con avanzamento e annulla).
- Messaggi di errore in italiano per ogni `PrintResult`, mai stack trace all'utente (log in `debugPrint`).

## 5. Documentazione e test

- `docs/stampanti.md`: motori supportati, modelli verificati e **non verificati**, connessioni (Wi-Fi/USB/Bluetooth) con le limitazioni iOS/MFi, etichette consigliate (adesivo removibile per alimenti), procedura di prova, risoluzione problemi (stampante occupata, formato non adatto, permessi Bluetooth), come aggiungere in futuro un altro motore implementando `LabelPrinter`.
- Test unitari: rasterizzazione, selezione del motore dalle impostazioni, mappa formato→carta Brother, controllo larghezza Niimbot, risultati di errore, ripiego su sistema/PDF. Test widget: schermata Impostazioni → Stampante con motori finti (nessuna dipendenza da hardware).
- Test manuali da documentare in `docs/stampanti.md`: stampa di prova su ogni stampante disponibile con 62×40, 50×30 e 40×30, QR leggibile con telefono, testo piccolo leggibile, orientamento corretto, riconnessione dopo riavvio.

## Criteri di accettazione

1. Il cliente sceglie in Impostazioni tra Brother, Niimbot e stampa di sistema; la scelta persiste.
2. Le etichette di lotto, QR attrezzatura e prova escono dalla stampante scelta usando i PDF già esistenti (layout invariati).
3. Nessuna larghezza o capacità inventata: formato non adatto → messaggio chiaro, mai taglio silenzioso.
4. Permessi Bluetooth solo al momento della ricerca; Brother Bluetooth nascosto su iOS (MFi); l'app funziona senza stampante.
5. `DemoLabelPrinter` assente nelle build di release; nessun segreto o ID di dispositivo nei log.
6. `docs/stampanti.md` completo; modelli non provati dichiarati come tali; `flutter analyze` e `flutter test` verdi.
