# PROMPT 11 — Stampa etichette: Brother (QL), Niimbot e stampante generica a scelta del cliente — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Obiettivo: oggi `main.dart` usa `DemoPrinterService` (la stampa è **simulata**) e esiste anche `PdfPrinterService` (finestra di stampa del sistema). Servono stampanti vere, scelte dal cliente: **Brother serie QL** (via SDK ufficiale), **Niimbot** (via Bluetooth LE) e **Stampante generica** (termiche economiche tipo CLABEL 221D, ESC/POS o TSPL, via Wi-Fi/LAN, Bluetooth o USB), più il ripiego "Stampa di sistema (PDF)". Le etichette sono già generate come PDF da `PdfService` (`buildLotLabel` 62×40 mm, `buildEquipmentQrLabel` 62×40 mm, `buildTestLabel` 62×40 / 50×30 / 40×30 mm): **non riscrivere i layout**, rasterizza quei PDF. Prima di modificare leggi `lib/services/printer_service.dart`, `lib/services/pdf_service.dart` (tre funzioni citate), `lib/screens/lots_screen.dart` (~riga 504), `lib/screens/onboarding/onboarding_screen.dart` (~riga 149, passo stampante del wizard), `lib/screens/temperature/equipment_history_sheet.dart` (~riga 125), `lib/main.dart` (~riga 90). Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Architettura (una sola interfaccia, quattro motori)

- Nuova interfaccia in `lib/core/printing/label_printer.dart`:
  - `String get id` (`'brother'`, `'niimbot'`, `'generic'`, `'system'`, `'demo'`), `String get displayName`.
  - `Future<List<PrinterDevice>> discover()` (nome, identificativo, trasporto: wifi/ble/bluetooth/usb).
  - `Future<void> connect(PrinterDevice d)`, `Future<void> disconnect()`, `bool get isConnected`.
  - `Future<PrintResult> printLabels(List<Uint8List> pdfPages, LabelSpec spec, {int copies = 1})` che riceve **i byte PDF** già costruiti da `PdfService` e restituisce un risultato tipizzato (`ok`, `notConnected`, `paperError`, `labelSizeNotSupported`, `cancelled`, `failed(message)`).
  - `Future<PrinterStatus> status()` (connessa, carta, coperchio, batteria se disponibile).
- `LabelSpec` = larghezza/altezza in mm, densità, taglio automatico. La dimensione deriva dal formato scelto nel wizard (`labelFormat`: `62x40`, `50x30`, `40x30`).
- Motori: `BrotherLabelPrinter` (§2), `NiimbotLabelPrinter` (§3), `GenericLabelPrinter` (§3 bis), `SystemLabelPrinter` (ripiego, usa `Printing.layoutPdf` come `PdfPrinterService` oggi), `DemoLabelPrinter` (solo debug, mantiene la simulazione e va nascosto in release).
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

## 3 bis. Stampante generica (termiche ESC/POS e TSPL)

Per chi ha già una stampante termica economica (etichette o scontrini, es. CLABEL 221D, Zjiang/Xprinter/MUNBYN e simili) che non è né Brother né Niimbot.

- Motore `GenericLabelPrinter` con **due linguaggi selezionabili** (default ESC/POS): **ESC/POS raster** (`GS v 0`, comune a quasi tutte le termiche) e **TSPL** (comando `BITMAP`, per le stampanti di etichette con carta a gap/tacca). Il linguaggio è un'impostazione (`printer_generic_language`: `escpos` | `tspl`); se la prova non esce, il cliente prova l'altro. Incapsula i comandi in classi separate (`EscPosEncoder`, `TsplEncoder`) con test unitari sui byte generati (intestazione, larghezza in byte, dimensione carta, numero copie, feed/taglio).
- Immagine: stessa rasterizzazione condivisa (§1) a **203 dpi** (configurabile: 203/300), bianco/nero, larghezza multipla di 8, densità/velocità regolabili dove il linguaggio lo prevede. Larghezza e altezza etichetta dal formato scelto (TSPL: `SIZE`, `GAP`); **larghezza carta dichiarata dal cliente** (58/80 mm per ESC/POS) e mai indovinata: se il formato non entra, messaggio chiaro, mai taglio silenzioso.
- Trasporti (scelti dal cliente):
  - **Rete/Wi-Fi (TCP raw, porta 9100)**: indirizzo IP inserito a mano (o scoperta mDNS se semplice); funziona su Android e iOS, nessun permesso speciale oltre a quello di rete locale su iOS (`NSLocalNetworkUsageDescription`, aggiungilo se manca).
  - **Bluetooth classico (SPP)**: solo **Android**; la stampante va prima associata nelle impostazioni del telefono, poi si sceglie dall'elenco degli associati. Su iOS il Bluetooth classico non è disponibile: nascondi l'opzione.
  - **Bluetooth LE**: Android e iOS, solo per modelli che espongono una caratteristica di scrittura nota; l'utente sceglie la caratteristica se ce n'è più di una (con un'opzione "Avanzate"). Dichiaralo "non verificato" finché non provato su un dispositivo reale.
  - **USB (OTG)**: solo Android, se un pacchetto affidabile lo permette; altrimenti rimanda a una versione futura e documentalo.
- Dipendenze: scegli pacchetti mantenuti e verifica versioni/piattaforme su pub.dev (per BLE `flutter_blue_plus`, per il classico Android un pacchetto SPP mantenuto; la rete usa `dart:io` `Socket`). **Non** basare nulla su un singolo plugin: l'invio dei byte passa da un'interfaccia `ByteTransport` (`connect`, `write(chunks)`, `close`) con tre implementazioni (tcp, bluetooth classico, ble) e un trasporto finto per i test. Invio a blocchi (es. 512 byte per BLE, con attesa tra i blocchi), timeout e un nuovo tentativo.
- Nessuna capacità inventata: lo stato carta/coperchio generalmente non è leggibile; `status()` riporta solo "connessa / non raggiungibile" e la UI non promette di rilevare la carta. Avviso nella schermata: "Stampante generica: compatibilità non garantita per ogni modello. Se non esce nulla o l'etichetta è tagliata, prova l'altro linguaggio (ESC/POS/TSPL), regola larghezza e densità e stampa l'etichetta di prova."
- Profili salvati per il cliente: nome, trasporto, indirizzo/identificativo, linguaggio, dpi, larghezza carta, densità; **più stampanti salvabili** con una predefinita (utile se il cliente ha stampante cucina e magazzino) e la possibilità di "Dimentica stampante".
- Test: encoder ESC/POS e TSPL (byte attesi), rasterizzazione alle dimensioni per 62×40 / 50×30 / 40×30 a 203 dpi, rifiuto di formato più largo della carta, trasporto finto con perdita di connessione e nuovo tentativo.

## 4. Configurazione per il cliente

- **Impostazioni → Stampante** (e il passo stampante del wizard, `onboarding_screen.dart`; per la stampante generica: trasporto, indirizzo IP o dispositivo associato, linguaggio, dpi, larghezza carta): scelta del motore con quattro card ("Brother QL", "Niimbot", "Stampante generica", "Stampa di sistema"), pulsante "Cerca stampanti", elenco dispositivi, "Collega", formato etichetta, densità, **"Stampa etichetta di prova"** (usa `buildTestLabel` con il formato scelto) e stato (connessa / non trovata / carta).
- Nessuna stampante configurata = l'app resta pienamente utilizzabile: i pulsanti "Stampa etichetta" propongono di configurarla oppure di "Condividi etichetta come PDF" (usa `Printing.sharePdf`).
- Dopo un riavvio l'app ricorda motore e dispositivo e prova a riconnettersi **solo quando serve** (alla prima stampa), non all'avvio; se non riesce propone "Seleziona stampante".
- In `lots_screen.dart` e `equipment_history_sheet.dart` usa il motore configurato; il numero di copie resta quello scelto dall'utente; stampa a coda (una etichetta alla volta, con avanzamento e annulla).
- Messaggi di errore in italiano per ogni `PrintResult`, mai stack trace all'utente (log in `debugPrint`).

## 5. Documentazione e test

- `docs/stampanti.md`: motori supportati (compresa la generica con ESC/POS e TSPL, come scegliere il linguaggio, esempi di modelli da provare), modelli verificati e **non verificati**, connessioni (Wi-Fi/USB/Bluetooth) con le limitazioni iOS/MFi, etichette consigliate (adesivo removibile per alimenti), procedura di prova, risoluzione problemi (stampante occupata, formato non adatto, permessi Bluetooth), come aggiungere in futuro un altro motore implementando `LabelPrinter`.
- Test unitari: rasterizzazione, selezione del motore dalle impostazioni, mappa formato→carta Brother, controllo larghezza Niimbot, risultati di errore, ripiego su sistema/PDF. Test widget: schermata Impostazioni → Stampante con motori finti (nessuna dipendenza da hardware).
- Test manuali da documentare in `docs/stampanti.md`: stampa di prova su ogni stampante disponibile con 62×40, 50×30 e 40×30, QR leggibile con telefono, testo piccolo leggibile, orientamento corretto, riconnessione dopo riavvio.

## Criteri di accettazione

1. Il cliente sceglie in Impostazioni tra Brother, Niimbot, stampante generica (ESC/POS o TSPL) e stampa di sistema; la scelta persiste.
2. Le etichette di lotto, QR attrezzatura e prova escono dalla stampante scelta usando i PDF già esistenti (layout invariati).
3. Nessuna larghezza o capacità inventata: formato non adatto → messaggio chiaro, mai taglio silenzioso.
4. Permessi Bluetooth solo al momento della ricerca (rete locale su iOS solo alla prima connessione generica); Brother Bluetooth nascosto su iOS (MFi); l'app funziona senza stampante.
5. `DemoLabelPrinter` assente nelle build di release; nessun segreto o ID di dispositivo nei log.
6. `docs/stampanti.md` completo; modelli non provati dichiarati come tali (generica: tutti non verificati finché non provati su hardware reale, es. CLABEL 221D); `flutter analyze` e `flutter test` verdi.