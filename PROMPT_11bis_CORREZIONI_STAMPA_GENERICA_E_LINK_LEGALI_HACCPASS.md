# PROMPT 11-bis — Correzioni stampa (generica/TSPL/BLE), documentazione e link legali — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Il Prompt 11 è stato applicato; dalla revisione del codice restano i punti sotto. Prima di modificare leggi `lib/services/printing/generic_label_printer.dart`, `byte_transport.dart`, `lib/core/printing/{escpos_encoder,tspl_encoder,label_rasterizer}.dart`, `lib/screens/printer_settings_screen.dart`, `lib/core/sensors/ble_sensor_source.dart`. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test` (devono restare verdi: sono ancora da eseguire dopo il Prompt 11).

## 1. Larghezza carta ESC/POS: confronto con l'area stampabile

`GenericLabelPrinter.printLabels` confronta `spec.widthMm` con `paperWidthMm` (58/80), ma l'area stampabile è più piccola: 58 mm → circa 48 mm (384 punti a 203 dpi), 80 mm → circa 72 mm (576 punti). Un'etichetta 50×30 su carta da 58 mm passa il controllo e viene tagliata in silenzio.

- Aggiungi `printableWidthDots` alla configurazione (default da carta dichiarata: 58→384, 80→576 a 203 dpi; a 300 dpi scala proporzionalmente) e rendilo **modificabile** in "Avanzate" (alcuni modelli hanno 432 o 640 punti).
- Il controllo confronta la larghezza in pixel dell'immagine rasterizzata (`rasterWidthForMm`) con `printableWidthDots`; se non entra: `labelSizeNotSupported` con "L'etichetta è larga NN mm, la stampante ne stampa al massimo MM mm (carta da 58/80 mm): scegli un formato più piccolo o carta più larga". Mai scalare o tagliare in silenzio.
- Test: 62×40 su 58 mm → rifiutato; 50×30 su 58 mm → rifiutato; 40×30 su 58 mm → ok; 62×40 su 80 mm → ok; 300 dpi.

## 2. TSPL: polarità dei bit e controllo dell'immagine

L'encoder invia `BITMAP` con 1 = nero (come ESC/POS). Molte stampanti TSPL usano il contrario (0 = nero) e produrrebbero un'etichetta **in negativo**. Non lo si può stabilire senza hardware.

- Aggiungi l'impostazione `printer_generic_invert` (default `false`) e la voce "Inverti immagine (se l'etichetta esce in negativo)" per la generica, applicata dall'encoder TSPL (complementa i byte dell'immagine). Un solo interruttore, spiegato in UI con una riga.
- Il testo accanto all'etichetta di prova dice: "Se l'etichetta esce in negativo (sfondo nero) attiva Inverti immagine; se esce vuota o tagliata prova l'altro linguaggio".
- Nel ritaglio `cropWhiteBorder` il contenuto resta allineato in alto; per TSPL centra verticalmente nell'altezza dell'etichetta (`SIZE`) con `BITMAP x,y` calcolato, così il testo non finisce attaccato al bordo superiore.
- Test: l'encoder con `invert = true` produce i byte complementari; il centraggio verticale calcola `y` corretto per 62×40, 50×30, 40×30.

## 3. Ricerca Bluetooth LE della generica

`GenericLabelPrinter.discover()` ascolta `FlutterBluePlus.scanResults` senza mai avviare la scansione e senza chiedere i permessi: restituisce quasi sempre un elenco vuoto.

- Prima chiama `requestBluetoothForPrinters()` (da `bluetooth_permissions.dart`), poi `FlutterBluePlus.startScan(timeout: 8 s)`, raccogli i risultati per tutta la durata (stream con deduplicazione per `remoteId`, nome non vuoto), `stopScan()` in `finally`. Se i permessi sono negati restituisci un errore tipizzato con messaggio in italiano ("Permesso Bluetooth negato: abilitalo nelle impostazioni del telefono"), non una lista vuota muta.
- Se Bluetooth è spento chiedi di accenderlo (stato adattatore `BluetoothAdapterState`).
- Avvio della scansione **solo** su pressione di "Cerca stampanti".
- Verifica che il codice dei sensori Govee (`ble_sensor_source.dart`) compili e funzioni con `flutter_blue_plus ^1.36.8` (declassato da 2.x per `niim_blue_flutter`): `flutter analyze` e test dei sensori verdi; documenta il vincolo in `docs/stampanti.md`.
- Test con scanner finto: risultati deduplicati, permesso negato, adattatore spento, timeout.

## 4. Dimensione dei blocchi BLE

`BleByteTransport` scrive blocchi da 512 byte senza considerare l'MTU negoziata.

- Dopo la connessione leggi `device.mtuNow`; il blocco è `min(512, mtu - 3)`, con un minimo di 20. Per `withoutResponse` mantieni la pausa tra i blocchi; se la caratteristica supporta `write` con risposta usa quella per i job piccoli.
- Test: con trasporto finto e MTU simulate (23, 185, 517) i blocchi non superano il limite.

## 5. Funzioni previste dal Prompt 11 ma non ancora presenti

- **Bluetooth classico (SPP) e USB per la generica:** oggi assenti e non selezionabili. Mantienili disattivati ma scrivi in `docs/stampanti.md` perché (nessun pacchetto affidabile verificato) e come si aggiungono implementando `ByteTransport`. Se esiste un pacchetto SPP mantenuto per Android, valutalo e proponi l'aggiunta dietro un flag, senza renderlo critico.
- **`docs/stampanti.md`** (assente): motori supportati con ESC/POS e TSPL e come scegliere il linguaggio; modelli **verificati** e **non verificati** (tutti non verificati finché non provati su hardware reale; esempio CLABEL 221D); connessioni Wi-Fi/LAN (porta 9100), BLE, limitazioni iOS/MFi per Brother; etichette consigliate (adesivo removibile); procedura di prova su 62×40, 50×30, 40×30 (QR leggibile, testo piccolo, orientamento, riconnessione dopo riavvio, **etichetta in negativo → Inverti immagine**); risoluzione problemi (occupata, formato non adatto, permessi, rete locale iOS); vincolo `flutter_blue_plus 1.x`; come aggiungere un motore implementando `LabelPrinter`.
- Verifica nel manifest Android: `INTERNET` presente in `main` (c'è), e che i permessi Bluetooth/posizione restino con `maxSdkVersion` corretto; nessun permesso richiesto all'avvio.

## 6. Link legali (privacy e termini) nell'app

I testi sono pubblicati su `https://www.bluescorpion.it/haacpass` (pagine: `…/privacy`, `…/termini`). Il percorso base va tenuto **in una sola costante** (`lib/core/constants/app_links.dart`: `AppLinks.base`, `privacyUrl`, `termsUrl`, `supportEmail`), così si corregge in un punto solo se cambia.

- Schermata Licenza e Altro/Impostazioni: righe "Informativa sulla privacy" e "Termini e condizioni" che aprono l'URL in app esterna con `url_launcher`; sotto il pulsante di acquisto la frase "Il rinnovo è automatico; gestisci o disdici dallo store. Continuando accetti i [Termini] e l'[Informativa privacy]" (obbligatoria per Apple 3.1.2: anche prezzo, durata e rinnovo letti dallo store).
- Primo avvio / wizard: collegamento alle stesse pagine; nessun consenso inventato (l'app non raccoglie dati da consentire).
- Rimuovi il permesso `READ_CONTACTS` dal manifest **solo se** l'importazione dei fornitori dai contatti non serve: se resta, la schermata che lo usa spiega lo scopo prima della richiesta e il permesso è chiesto soltanto al tocco di "Importa dai contatti".
- Test widget: le righe compaiono, aprono l'URL corretto (url_launcher finto), e `AppLinks` è l'unica fonte degli indirizzi (grep: nessun URL scritto altrove).

## Criteri di accettazione

1. Nessun formato più largo dell'area stampabile esce tagliato: errore chiaro in italiano; area stampabile modificabile in Avanzate.
2. L'opzione "Inverti immagine" esiste, funziona sull'encoder TSPL ed è spiegata vicino alla prova di stampa.
3. "Cerca stampanti" per BLE avvia davvero la scansione dopo aver chiesto i permessi e mostra errori espliciti.
4. Blocchi BLE rispettano l'MTU; sensori Govee ancora funzionanti con `flutter_blue_plus 1.x`.
5. `docs/stampanti.md` completo; limitazioni (SPP/USB assenti) dichiarate.
6. Link a privacy e termini presenti in schermata licenza e impostazioni, da un'unica costante; `flutter analyze` e `flutter test` verdi.
