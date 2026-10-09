# Stampanti di etichette (Prompt 11)

L'app stampa le **etichette di lotto, QR attrezzatura e di prova** così
come vengono generate da `PdfService` (layout invariati): i motori di
stampa ricevono i PDF e li rasterizzano (o li passano al SDK), senza
mai riscrivere i layout. Si sceglie il motore in
**Impostazioni → Stampante** (voce "Stampante" in "Altro") oppure dal
passo 11 del wizard; la scelta persiste e la riconnessione avviene
SOLO alla prima stampa, mai all'avvio. Senza stampante l'app è
pienamente utilizzabile: i pulsanti di stampa propongono di
configurarne una o di **condividere l'etichetta come PDF**.

Architettura: una sola interfaccia (`lib/core/printing/label_printer.dart`,
`LabelPrinter`) e cinque motori (`lib/services/printing/`). Il
coordinatore (`print_coordinator.dart`) ricostruisce il motore dalle
impostazioni (`printer_engine`, `printer_device_id`,
`printer_label_format`, `printer_density`, `printer_generic_*`), stampa
a coda (un'etichetta alla volta, con avanzamento e annulla) e traduce
ogni esito in un messaggio in italiano (mai stack trace all'utente).

## Motori

| Motore | Connessioni | Verificato su hardware | Note |
|---|---|---|---|
| **Brother QL** (`brother_native_print`, SDK ufficiale) | Wi-Fi (preferita), USB (Android), Bluetooth (solo Android) | **QL-820NWB** (dal plugin). **RJ-2050** supportato dal plugin ma pensato per scontrini. **QL-810W e ogni altro modello: NON verificati** e il plugin li rifiuta con un messaggio chiaro | Su iOS il Bluetooth Brother è **nascosto**: richiede l'iscrizione MFi con PPID Brother (vedi sotto) |
| **Niimbot** (B21, B1, D11/D110...; `niim_blue_flutter`, protocollo non ufficiale) | Bluetooth LE | **Nessun modello verificato** | Larghezza massima letta dal dispositivo (pixel testina / dpi), mai scritta a mano. Avviso permanente in app |
| **Stampante generica** (ESC/POS o TSPL) | Wi-Fi/LAN (TCP 9100), Bluetooth LE (non verificato) | **Tutti i modelli NON verificati** (es. CLABEL 221D, Zjiang, Xprinter, MUNBYN) | Bluetooth classico (SPP) e USB NON disponibili in questa versione (rimandati) |
| **Stampa di sistema** | Finestra di stampa di Android/iOS/desktop (AirPrint ecc.) | — | Ripiego sempre disponibile, un PDF per etichetta |
| **Demo** | Nessuna (simulazione) | — | Visibile **solo nelle build di debug** |

## Quale motore scegliere

- Ha una **Brother QL-820NWB** in rete? → motore Brother, ricerca
  Wi-Fi, rotolo DK da 62 mm per l'etichetta 62×40.
- Ha una **Niimbot** (B21/B1)? → motore Niimbot. I modelli **D11/D110
  hanno testine molto strette**: se il formato non entra l'app lo dice
  chiaramente ("Questa stampante non stampa etichette da NN mm") senza
  tagliare in silenzio.
- Ha una **termica economica** (etichette o scontrini)? → motore
  generico: dichiara **larghezza carta** (58/80 mm per ESC/POS),
  scegli la **risoluzione** (203/300 dpi) e prova il **linguaggio**:
  - **ESC/POS** (default): comando raster `GS v 0`, comune a quasi
    tutte le termiche; per le carte da 58/80 mm;
  - **TSPL**: `SIZE`/`GAP`/`BITMAP`, per le stampanti di etichette con
    carta a gap/tacca;
  - se la prova non esce o esce tagliata, **prova l'altro linguaggio**,
    regola larghezza e densità, ripeti la prova.
- **Area stampabile ESC/POS**: la testina non copre tutta la carta:
  58 mm → **384 punti** (~48 mm), 80 mm → **576 punti** (~72 mm) a
  203 dpi (proporzionale a 300 dpi). L'app rifiuta con un messaggio
  chiaro le etichette più larghe (es. la 50×30 su carta da 58 mm NON
  passa), mai tagli in silenzio. Se il tuo modello ha una testina
  diversa (432 o 640 punti), correggi "Punti stampabili in larghezza"
  in **Avanzate**.
- **Etichetta in negativo (TSPL)**: alcune TSPL interpretano 0 = nero:
  se l'etichetta esce a sfondo nero, attiva **"Inverti immagine"** in
  Avanzate (complementa i bit dell'immagine). La voce è spiegata accanto
  al pulsante di prova; se invece esce vuota o tagliata, prova l'altro
  linguaggio.
- Nessuna delle precedenti → **stampa di sistema**.

## Procedura di prova

1. Impostazioni → Stampante → scegli il motore → **Cerca stampanti**
   (i permessi Bluetooth vengono chiesti QUI, spiegati in italiano,
   mai all'avvio; su Android ≤ 11 serve anche la posizione per la
   ricerca) → **Collega**;
2. scegli il **formato** (62×40 / 50×30 / 40×30) e la **densità**
   (1–5 dove supportata);
3. **Stampa etichetta di prova**: verifica orientamento e leggibilità
   (l'**anteprima** mostra l'immagine monocromatica che sarà inviata:
   aiuta a vedere testi troppo piccoli);
4. per la stampante generica in Wi-Fi inserisci l'**indirizzo IP** a
   mano (nessuna ricerca automatica in LAN) e usa "Salva e collega".

**Stampanti multiple**: ogni stampante collegata viene salvata tra gli
elenchi "Stampanti salvate" (utile per cucina e magazzino): si imposta
la predefinita o si **dimentica** con l'apposito pulsante.

## Etichette consigliate

Etichette **termiche con adesivo removibile** per l'uso su alimenti e
contenitori (le termiche permanenti perdono adesione su superfici
fredde o umide: verifica sempre sul tuo contenitore). Per Brother usa
rotoli originali DK (62 mm continuo per il formato 62×40): il rotolo
montato viene letto dalla stampante e, se non corrisponde al formato
scelto, la stampa si ferma con "Rotolo montato non adatto: …".

## Limitazioni iOS

- **Brother Bluetooth**: Apple richiede l'iscrizione **MFi** con PPID
  rilasciato da Brother (https://secure6.brother.co.jp/mfi/Top.aspx).
  Senza PPID l'opzione è **nascosta su iOS** (il Wi-Fi Brother funziona
  senza MFi). Attivarla richiede un build dedicato
  (`BrotherLabelPrinter(enableBluetoothIos: true)`) e le chiavi
  `UISupportedExternalAccessoryProtocols` nel progetto.
- **Rete locale**: iOS 14+ richiede il consenso "rete locale" alla
  prima connessione a una stampante IP (`NSLocalNetworkUsageDescription`
  già configurato).
- **Bluetooth classico (SPP) e USB**: non disponibili su iOS (e lo SPP
  non è disponibile nemmeno su Android in questa versione).

## Risoluzione problemi

- **Stampante Brother "occupata"**: le QL accettano una sola
  connessione; l'app prova un recupero automatico (annulla stampa →
  disconnetti → ricollega → ristampa); se persiste, riavvia la
  stampante.
- **"Rotolo montato non adatto"**: il sensore della stampante legge un
  rotolo di larghezza diversa dal formato scelto: sostituisci il rotolo
  o cambia formato.
- **Niimbot non trova nulla**: Bluetooth acceso, stampante accesa e
  vicina; su Android ≤ 11 concedi anche la posizione (spiegato in app).
- **Generica: non esce nulla / etichetta tagliata**: prova l'altro
  linguaggio, controlla larghezza carta e dpi, stampa la prova; in BLE
  scegli la caratteristica giusta in "Avanzate" se ce n'è più di una.
- **Generica: etichetta in negativo (sfondo nero)**: attiva "Inverti
  immagine" in Avanzate.
- **"Permesso Bluetooth negato" / "Bluetooth spento"**: la ricerca BLE
  della generica lo dice esplicitamente: abilita il permesso o il
  Bluetooth dalle impostazioni del telefono e ripremi "Cerca stampanti"
  (la scansione parte SOLO da quel pulsante, mai in background).
- **Formato più largo della stampante**: l'app NON taglia in silenzio:
  per la generica ESC/POS mostra "L'etichetta è larga NN mm, la
  stampante ne stampa al massimo MM mm (carta da 58/80 mm)…"; per la
  Niimbot "…scegli un formato più piccolo o un'altra stampante".

## Test manuali da fare su hardware reale

- Stampa di prova con **62×40, 50×30 e 40×30** su ogni stampante
  disponibile;
- **QR leggibile** con la fotocamera del telefono;
- **testo piccolo leggibile** (densità diversa se serve);
- **orientamento corretto** (l'anteprima mostra l'immagine inviata);
- **etichetta in negativo?** → "Inverti immagine" in Avanzate;
- **riconnessione dopo riavvio** dell'app: alla prima stampa si
  ricollega da sola (Wi-Fi/BLE) o chiede di riselezionarla (USB/SPP);
- **coda e annulla**: più copie con avanzamento, "Annulla stampa".

## Note tecniche

- `flutter_blue_plus` è alla **1.x** (vincolo: `niim_blue_flutter` 1.0.1
  richiede ^1.36.8; le API usate dai sensori Govee e dalla stampa sono
  stabili tra 1.x e 2.x — sensori verificati da `flutter analyze` e
  dalla suite `sensor_registry`/`sensor_widgets`). Prima di passare alla
  2.x serve una nuova versione di `niim_blue_flutter` o la sostituzione
  dell'adattatore.
- **Ricerca BLE della generica** (`GenericBleScanner`): permessi chiesti
  PRIMA della scansione, controllo dello stato del Bluetooth
  (errore esplicito se spento), `startScan` con timeout 8 s, raccolta
  per tutta la durata con deduplicazione per `remoteId` e nomi vuoti
  scartati, `stopScan` sempre in `finally`. La scansione parte SOLO da
  "Cerca stampanti", mai in background.
- **Blocchi BLE e MTU** (`BleByteTransport`): dopo la connessione il
  blocco è `min(512, mtu − 3)` con un minimo di 20; se la
  caratteristica supporta la scrittura CON risposta la si usa (job
  piccoli affidabili), altrimenti `withoutResponse` con la pausa tra i
  blocchi.
- Il protocollo Niimbot è **non ufficiale** (niimbluelib): un
  aggiornamento del firmware potrebbe richiedere un aggiornamento
  dell'app. Tutto il pacchetto è confinato in `niim_blue_adapter.dart`
  dietro `NiimbotClientAdapter`: sostituirlo non tocca il motore.
- L'invio alla generica passa da `ByteTransport` (TCP/BLE/finto) a
  blocchi con pausa e un nuovo tentativo alla prima caduta.
- La stampante generica **non promette di rilevare la carta**: lo
  stato riporta solo "connessa / non raggiungibile".
- I log non contengono ID di dispositivi né segreti.
- **Permessi Android** (`AndroidManifest.xml`): `INTERNET` e
  `ACCESS_NETWORK_STATE` in `main`; permessi Bluetooth con
  `maxSdkVersion="30"` per i vecchi (`BLUETOOTH`, `BLUETOOTH_ADMIN`,
  posizione) e `BLUETOOTH_SCAN` (neverForLocation) + `BLUETOOTH_CONNECT`
  per Android 12+. Nessun permesso richiesto all'avvio: tutto al primo
  uso (ricerca stampanti, importazione contatti, fotocamera).

## Bluetooth classico (SPP) e USB: perché assenti e come aggiungerli

Le voci compaiono nell'elenco trasporti della generica ma sono
**disattivate**: non esiste oggi un pacchetto Dart **mantenuto e
verificato** per lo SPP Android (i candidati storici tipo
`flutter_bluetooth_serial` non sono più mantenuti) né per l'USB OTG
verso stampanti. Non si include codice nativo non verificabile.

Come aggiungerli in futuro:

1. implementa un nuovo `ByteTransport` (es. `SppByteTransport` con un
   pacchetto SPP mantenuto, `UsbByteTransport` con usb_serial):
   `connect / writeChunk / close / suggestedChunkSize`;
2. aggiungi il valore in `GenericPrinterConfig.transport` e la voce
   attiva nel menu della schermata stampante;
3. valutazione **dietro flag** (impostazione di sviluppo), mai come
   percorso critico: il ripiego resta TCP/BLE;
4. dichiara nella tabella dei motori cosa è stato verificato e su
   quale hardware.

## Aggiungere in futuro un altro motore

1. implementa `LabelPrinter` (`lib/core/printing/label_printer.dart`):
   `discover/connect/disconnect/isConnected/printLabels/status`;
2. aggiungi la factory in `PrintCoordinator.defaultEngineFactories`,
   l'istanza in `availableEngines()` e, se serve, una card con
   sottotitolo in `PrinterSettingsScreen` (`_engineSubtitle`);
3. riusa la rasterizzazione condivisa
   (`lib/core/printing/label_rasterizer.dart`) e gli encoder
   ESC/POS/TSPL già testati; mai layout nuovi nel motore;
4. dichiara nel prompt/docs cosa è verificato e cosa no: nessuna
   capacità inventata, messaggi chiari per ciò che il motore non sa.
