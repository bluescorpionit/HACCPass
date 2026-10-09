# Stampanti di etichette (Prompt 11)

L'app stampa le **etichette di lotto, QR attrezzatura e di prova** cosÃ¬
come vengono generate da `PdfService` (layout invariati): i motori di
stampa ricevono i PDF e li rasterizzano (o li passano al SDK), senza
mai riscrivere i layout. Si sceglie il motore in
**Impostazioni â†’ Stampante** (voce "Stampante" in "Altro") oppure dal
passo 11 del wizard; la scelta persiste e la riconnessione avviene
SOLO alla prima stampa, mai all'avvio. Senza stampante l'app Ã¨
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
| **Brother QL** (`brother_native_print`, SDK ufficiale) | Wi-Fi (preferita), USB (Android), Bluetooth (solo Android) | **QL-820NWB** (dal plugin). **RJ-2050** supportato dal plugin ma pensato per scontrini. **QL-810W e ogni altro modello: NON verificati** e il plugin li rifiuta con un messaggio chiaro | Su iOS il Bluetooth Brother Ã¨ **nascosto**: richiede l'iscrizione MFi con PPID Brother (vedi sotto) |
| **Niimbot** (B21, B1, D11/D110...; `niim_blue_flutter`, protocollo non ufficiale) | Bluetooth LE | **Nessun modello verificato** | Larghezza massima letta dal dispositivo (pixel testina / dpi), mai scritta a mano. Avviso permanente in app |
| **Stampante generica** (ESC/POS o TSPL) | Wi-Fi/LAN (TCP 9100), Bluetooth LE (non verificato), **Bluetooth classico SPP (solo Android, Prompt 17, non verificato)** | **Tutti i modelli NON verificati** (es. CLABEL 221D, Zjiang, Xprinter, MUNBYN) | USB non disponibile (rimandato) |
| **Stampa di sistema** | Finestra di stampa di Android/iOS/desktop (AirPrint ecc.) | â€” | Ripiego sempre disponibile, un PDF per etichetta |
| **Demo** | Nessuna (simulazione) | â€” | Visibile **solo nelle build di debug** |

## Quale motore scegliere

- Ha una **Brother QL-820NWB** in rete? â†’ motore Brother, ricerca
  Wi-Fi, rotolo DK da 62 mm per l'etichetta 62Ã—40.
- Ha una **Niimbot** (B21/B1)? â†’ motore Niimbot. I modelli **D11/D110
  hanno testine molto strette**: se il formato non entra l'app lo dice
  chiaramente ("Questa stampante non stampa etichette da NN mm") senza
  tagliare in silenzio.
- Ha una **termica economica** (etichette o scontrini)? â†’ motore
  generico: dichiara **larghezza carta** (58/80 mm per ESC/POS),
  scegli la **risoluzione** (203/300 dpi) e prova il **linguaggio**:
  - **ESC/POS** (default): comando raster `GS v 0`, comune a quasi
    tutte le termiche; per le carte da 58/80 mm;
  - **TSPL**: `SIZE`/`GAP`/`BITMAP`, per le stampanti di etichette con
    carta a gap/tacca;
  - se la prova non esce o esce tagliata, **prova l'altro linguaggio**,
    regola larghezza e densitÃ , ripeti la prova.
- **Area stampabile ESC/POS**: la testina non copre tutta la carta:
  58 mm â†’ **384 punti** (~48 mm), 80 mm â†’ **576 punti** (~72 mm) a
  203 dpi (proporzionale a 300 dpi). L'app rifiuta con un messaggio
  chiaro le etichette piÃ¹ larghe (es. la 50Ã—30 su carta da 58 mm NON
  passa), mai tagli in silenzio. Se il tuo modello ha una testina
  diversa (432 o 640 punti), correggi "Punti stampabili in larghezza"
  in **Avanzate**.
- **Etichetta in negativo (TSPL)**: alcune TSPL interpretano 0 = nero:
  se l'etichetta esce a sfondo nero, attiva **"Inverti immagine"** in
  Avanzate (complementa i bit dell'immagine). La voce Ã¨ spiegata accanto
  al pulsante di prova; se invece esce vuota o tagliata, prova l'altro
  linguaggio.
- Nessuna delle precedenti â†’ **stampa di sistema**.

## Procedura di prova

1. Impostazioni â†’ Stampante â†’ scegli il motore â†’ **Cerca stampanti**
   (i permessi Bluetooth vengono chiesti QUI, spiegati in italiano,
   mai all'avvio; su Android â‰¤ 11 serve anche la posizione per la
   ricerca) â†’ **Collega**;
2. scegli il **formato** (62Ã—40 / 50Ã—30 / 40Ã—30) e la **densitÃ **
   (1â€“5 dove supportata);
3. **Stampa etichetta di prova**: verifica orientamento e leggibilitÃ 
   (l'**anteprima** mostra l'immagine monocromatica che sarÃ  inviata:
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
rotoli originali DK (62 mm continuo per il formato 62Ã—40): il rotolo
montato viene letto dalla stampante e, se non corrisponde al formato
scelto, la stampa si ferma con "Rotolo montato non adatto: â€¦".

## Limitazioni iOS

- **Brother Bluetooth**: Apple richiede l'iscrizione **MFi** con PPID
  rilasciato da Brother (https://secure6.brother.co.jp/mfi/Top.aspx).
  Senza PPID l'opzione Ã¨ **nascosta su iOS** (il Wi-Fi Brother funziona
  senza MFi). Attivarla richiede un build dedicato
  (`BrotherLabelPrinter(enableBluetoothIos: true)`) e le chiavi
  `UISupportedExternalAccessoryProtocols` nel progetto.
- **Rete locale**: iOS 14+ richiede il consenso "rete locale" alla
  prima connessione a una stampante IP (`NSLocalNetworkUsageDescription`
  giÃ  configurato).
- **Bluetooth classico (SPP)**: disponibile SOLO su Android (Prompt 17);
  su iOS richiede l'iscrizione MFi. **USB**: non disponibile in questa
  versione.

## Risoluzione problemi

- **Stampante Brother "occupata"**: le QL accettano una sola
  connessione; l'app prova un recupero automatico (annulla stampa â†’
  disconnetti â†’ ricollega â†’ ristampa); se persiste, riavvia la
  stampante.
- **"Rotolo montato non adatto"**: il sensore della stampante legge un
  rotolo di larghezza diversa dal formato scelto: sostituisci il rotolo
  o cambia formato.
- **Niimbot non trova nulla**: Bluetooth acceso, stampante accesa e
  vicina; su Android â‰¤ 11 concedi anche la posizione (spiegato in app).
- **Generica: non esce nulla / etichetta tagliata**: prova l'altro
  linguaggio, controlla larghezza carta e dpi, stampa la prova; in BLE
  scegli la caratteristica giusta in "Avanzate" se ce n'Ã¨ piÃ¹ di una.
- **Generica: etichetta in negativo (sfondo nero)**: attiva "Inverti
  immagine" in Avanzate.
- **"Permesso Bluetooth negato" / "Bluetooth spento"**: la ricerca BLE
  della generica lo dice esplicitamente: abilita il permesso o il
  Bluetooth dalle impostazioni del telefono e ripremi "Cerca stampanti"
  (la scansione parte SOLO da quel pulsante, mai in background).
- **Formato piÃ¹ largo della stampante**: l'app NON taglia in silenzio:
  per la generica ESC/POS mostra "L'etichetta Ã¨ larga NN mm, la
  stampante ne stampa al massimo MM mm (carta da 58/80 mm)â€¦"; per la
  Niimbot "â€¦scegli un formato piÃ¹ piccolo o un'altra stampante".

## Test manuali da fare su hardware reale

- Stampa di prova con **62Ã—40, 50Ã—30 e 40Ã—30** su ogni stampante
  disponibile;
- **QR leggibile** con la fotocamera del telefono;
- **testo piccolo leggibile** (densitÃ  diversa se serve);
- **orientamento corretto** (l'anteprima mostra l'immagine inviata);
- **etichetta in negativo?** â†’ "Inverti immagine" in Avanzate;
- **riconnessione dopo riavvio** dell'app: alla prima stampa si
  ricollega da sola (Wi-Fi/BLE) o chiede di riselezionarla (USB/SPP);
- **coda e annulla**: piÃ¹ copie con avanzamento, "Annulla stampa".

## Bluetooth classico (SPP) â€” solo Android (Prompt 17)

Per le termiche ESC/POS Bluetooth **classiche** (tipo scontrino 58 mm)
che si associano dalle impostazioni del telefono ma NON compaiono nella
ricerca Bluetooth LE: in Impostazioni â†’ Stampante â†’ Stampante generica
scegli **"Bluetooth classico (SPP)"**. Su iPhone la voce resta
disattivata (il Bluetooth classico richiede il programma MFi di Apple).

**Come si usa**: accendi la stampante e associala dalle impostazioni
Bluetooth del telefono (PIN di solito 0000 o 1234) oppure dal pulsante
**"Associa nuova stampante"** nell'app; poi "Cerca stampanti": l'app
elenca i dispositivi **giÃ  associati** (nome + MAC abbreviato), con
quelli che sembrano stampanti per primi ma **tutti selezionabili**. La
scelta persiste (`bt:MAC`): dopo il riavvio l'app ristampa senza
ripetere la ricerca.

**Implementazione**: canale interno `haccpass/spp` (Kotlin in
`BluetoothSppPlugin.kt`, poche decine di righe su
`BluetoothAdapter`/`BluetoothSocket`) dietro l'interfaccia
`ByteTransport`. Valutato `flutter_classic_bluetooth` 1.7.0 (publisher
verificato, MIT, aggiornato) ma richiede Flutter 3.44: su questa
toolchain pub risolverebbe la 1.3.0; il canale interno evita che nulla
di critico dipenda da un solo plugin ed Ã¨ sostituibile senza toccare il
motore. Sequenza di collegamento: socket **sicuro** â†’ **non sicuro** â†’
canale 1 (stampanti vecchie), timeout 9 s, nuovo tentativo dopo 1,5 s.
UUID SPP standard `00001101-â€¦-00805F9B34FB`.

**VelocitÃ  di invio** (Avanzate â†’ "VelocitÃ  di invio", prompt Â§1): le
stampanti Bluetooth hanno buffer piccoli e invii veloci troncano
l'immagine. *Normale* = blocchi 256 B, pausa 20 ms, bande 64 righe;
*Lenta* = 128 B, 50 ms, bande 24 (se il testo esce ma l'immagine no);
*Veloce* = 512 B, 8 ms, bande 128. UNA connessione per lavoro; chiusura
con flush + attesa 500 ms.

**Carta stretta (58 mm)**: una 58 mm stampa al massimo ~48 mm (384 punti
a 203 dpi): le etichette 62Ã—40 e 50Ã—30 NON entrano, la 40Ã—30 sÃ¬. Quando
non entra, l'app **chiede** (mai riduzioni nascoste): "Riduci per
adattare" (consigliato; etichetta rasterizzata a larghezza =
area stampabile, multipla di 8, con avviso di leggibilitÃ  del QR),
"Formato piÃ¹ piccolo" (40Ã—30) o "Annulla". La scelta si puÃ² ricordare
(Avanzate â†’ "Se l'etichetta Ã¨ piÃ¹ larga della carta": Chiedi /
Riduci / Rifiuta).

**Errori distinti** in italiano: Bluetooth spento (proposta di attivarlo),
permesso negato (con scorciatoia alle impostazioni), non associata,
spenta/fuori portata ("accendi la stampante e avvicinala"), occupata
("scollegala dall'altro dispositivo"), connessione caduta durante l'invio
(un nuovo tentativo, poi errore). "Verifica connessione" apre/chiude il
socket RFCOMM; "Prova solo testo" funziona via Bluetooth; il riepilogo
mostra "Bluetooth classico â€¢ N byte â€¢ blocchi da 256 B â€¢ velocitÃ 
Normale". Nessun MAC completo nÃ© nome dispositivo nei log. Lo stato
carta via `DLE EOT` NON Ã¨ implementato (sperimentale, default "stato
non disponibile": non si inventa nulla).

**Permessi** (giÃ  nel manifest): `BLUETOOTH_CONNECT` (Android 12+),
`BLUETOOTH`/`BLUETOOTH_ADMIN` e posizione con `maxSdkVersion="30"`;
richiesti SOLO alla pressione di "Cerca stampanti"/"Collega"/"Verifica
connessione", mai all'avvio.

### Esito prove su hardware (Prompt 17)

**Non ancora eseguite**: il trasporto SPP Ã¨ dichiarato **non verificato**
finchÃ© non provato sulla stampante ESC/POS Bluetooth dell'utente.
Prova manuale da documentare qui: modello, carta (58/80 mm), velocitÃ 
(Normale/Lenta/Veloce), bande, esito di "Verifica connessione", "Prova
solo testo", etichetta 40Ã—30 e (con Riduci) 50Ã—30/62Ã—40, leggibilitÃ 
del QR, comportamento spegnendo la stampante a metÃ  stampa e dopo il
riavvio dell'app.

## La stampante generica non stampa? (diagnosi, Prompt 16 Â§7)

Nella sezione della stampante generica, sotto "Salva e collega", ci
sono tre azioni di diagnosi con messaggi distinti:

1. **"Verifica connessione"**: apre il socket verso IP:porta, misura il
   tempo e chiude. Distingue *raggiungibile* / *rifiutata (porta chiusa
   o stampante occupata)* / *timeout (IP errato, Wi-Fi diverso o
   isolamento client)* / *rete non disponibile* e mostra l'IP del
   telefono per verificare la sottorete.
2. **"Prova solo testo"**: invia `ESC @`, una riga di testo e 3 righe di
   avanzamento (piÃ¹ il taglio se "Taglierina" Ã¨ attiva). Se NON esce
   nemmeno questo il problema Ã¨ rete/porta/linguaggio; se esce questo ma
   non l'etichetta, il problema Ã¨ l'immagine: prova l'altro linguaggio o
   riduci le "Righe per banda".
3. **"Stampa etichetta di prova"** con sotto il **riepilogo
   dell'ultimo invio**: "Inviati N byte a IP:porta in X ms (B bande,
   ESC/POS, 203 dpi, carta 58 mm)" â€” distingue "non raggiunta" da
   "inviata ma non stampata" (linguaggio/larghezza sbagliati).

Correzioni funzionali del Prompt 16 (causa reale di "non stampa"):

- **le impostazioni arrivano al motore che stampa**: il coordinatore
  costruisce la stampante generica CON la configurazione salvata
  (linguaggio, dpi, carta, punti stampabili, inversione, bande,
  taglierina, porta, caratteristica BLE);
- **una sola connessione TCP per lavoro** (molte termiche ne accettano
  una sola): niente connessioni di prova prima di stampare; se la porta
  Ã¨ ancora occupata si riprova dopo 1,5 s; chiusura con attesa dopo
  l'ultimo flush (mai chiusure brusche che scartano il buffer);
- **immagine ESC/POS a bande** (default 128 righe per blocco, 24 per i
  modelli vecchi in Avanzate): molti modelli ignorano i blocchi alti
  quanto tutta l'etichetta; avanzamento configurabile in mm, **nessun
  `GS V` se la "Taglierina" non Ã¨ dichiarata** e form feed opzionale
  per la carta a gap;
- guida "La stampante non stampa?" in app con i sei controlli:
  autotest della stampante (tasto Feed all'accensione), stessa rete
  Wi-Fi (niente isolamento client), `Test-NetConnection <IP> -Port 9100`
  o `nc -vz <IP> 9100` dal PC, linguaggio alternativo (le etichette a
  gap spesso usano TSPL), larghezze (58 mm â‰ˆ 48 stampabili, 80 â‰ˆ 72),
  IP fisso/prenotato sul router.

## Note tecniche

- `flutter_blue_plus` Ã¨ alla **1.x** (vincolo: `niim_blue_flutter` 1.0.1
  richiede ^1.36.8; le API usate dai sensori Govee e dalla stampa sono
  stabili tra 1.x e 2.x â€” sensori verificati da `flutter analyze` e
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
  blocco Ã¨ `min(512, mtu âˆ’ 3)` con un minimo di 20; se la
  caratteristica supporta la scrittura CON risposta la si usa (job
  piccoli affidabili), altrimenti `withoutResponse` con la pausa tra i
  blocchi.
- Il protocollo Niimbot Ã¨ **non ufficiale** (niimbluelib): un
  aggiornamento del firmware potrebbe richiedere un aggiornamento
  dell'app. Tutto il pacchetto Ã¨ confinato in `niim_blue_adapter.dart`
  dietro `NiimbotClientAdapter`: sostituirlo non tocca il motore.
- L'invio alla generica passa da `ByteTransport` (TCP/BLE/finto) a
  blocchi con pausa e un nuovo tentativo alla prima caduta.
- La stampante generica **non promette di rilevare la carta**: lo
  stato riporta solo "connessa / non raggiungibile".
- I log non contengono ID di dispositivi nÃ© segreti.
- **Permessi Android** (`AndroidManifest.xml`): `INTERNET` e
  `ACCESS_NETWORK_STATE` in `main`; permessi Bluetooth con
  `maxSdkVersion="30"` per i vecchi (`BLUETOOTH`, `BLUETOOTH_ADMIN`,
  posizione) e `BLUETOOTH_SCAN` (neverForLocation) + `BLUETOOTH_CONNECT`
  per Android 12+. Nessun permesso richiesto all'avvio: tutto al primo
  uso (ricerca stampanti, importazione contatti, fotocamera).

## USB: perché assente e come aggiungerlo

Lo SPP è arrivato con il Prompt 17 (vedi la sezione dedicata): resta
**disattivato** solo l'USB OTG, per cui non esiste oggi un pacchetto
Dart mantenuto e verificato verso stampanti. Non si include codice
nativo non verificabile oltre a quello già indispensabile.

Come aggiungerlo in futuro:

1. implementa un nuovo `ByteTransport` (`UsbByteTransport` con
   usb_serial): `connect / writeChunk / close / suggestedChunkSize`;
2. aggiungi il valore in `GenericPrinterConfig.transport` e la voce
   attiva nel menu della schermata stampante;
3. valutazione **dietro flag** (impostazione di sviluppo), mai come
   percorso critico: il ripiego resta TCP/BLE/SPP;
4. dichiara nella tabella dei motori cosa Ã¨ stato verificato e su
   quale hardware.

## Aggiungere in futuro un altro motore

1. implementa `LabelPrinter` (`lib/core/printing/label_printer.dart`):
   `discover/connect/disconnect/isConnected/printLabels/status`;
2. aggiungi la factory in `PrintCoordinator.defaultEngineFactories`,
   l'istanza in `availableEngines()` e, se serve, una card con
   sottotitolo in `PrinterSettingsScreen` (`_engineSubtitle`);
3. riusa la rasterizzazione condivisa
   (`lib/core/printing/label_rasterizer.dart`) e gli encoder
   ESC/POS/TSPL giÃ  testati; mai layout nuovi nel motore;
4. dichiara nel prompt/docs cosa Ã¨ verificato e cosa no: nessuna
   capacitÃ  inventata, messaggi chiari per ciÃ² che il motore non sa.
