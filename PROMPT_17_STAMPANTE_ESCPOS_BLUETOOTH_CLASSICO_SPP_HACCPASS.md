# PROMPT 17 — Stampante ESC/POS Bluetooth classico (SPP) su Android, anche a scontrino 58 mm — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Prerequisito: Prompt 16 §7 applicato (configurazione della stampante generica che arriva al motore, **una sola connessione per lavoro**, immagine ESC/POS a bande, diagnostica "Verifica connessione"/"Prova solo testo", riepilogo ultimo invio). Questo prompt aggiunge il collegamento **Bluetooth classico (SPP/RFCOMM)**, usato dalla stampante ESC/POS Bluetooth dell'utente (tipo classica termica a scontrino): oggi in Impostazioni → Stampante generica la voce "Bluetooth classico (SPP) — non disponibile" è disattivata, e la ricerca Bluetooth dell'app (che cerca solo **Bluetooth LE**) non trova la stampante, anche se dalle impostazioni del telefono la stampante si **associa** correttamente. Va implementato, insieme alla gestione corretta della carta stretta (58 mm), perché è il caso reale.

Prima di modificare leggi: `lib/services/printing/{generic_label_printer,byte_transport,print_coordinator,bluetooth_permissions}.dart`, `lib/core/printing/{label_printer,label_rasterizer,escpos_encoder}.dart`, `lib/screens/printer_settings_screen.dart` (`_genericSection`), `android/app/src/main/AndroidManifest.xml`, `docs/stampanti.md`, `pubspec.yaml`. Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## 1. Trasporto `BluetoothSppByteTransport` (solo Android)

- Implementa lo stesso contratto `ByteTransport` (`connect`, `writeChunk`, `close`, `isConnected`) dei trasporti TCP e BLE. Collegamento RFCOMM con UUID SPP `00001101-0000-1000-8000-00805F9B34FB` verso l'indirizzo MAC del dispositivo associato.
- Sequenza di collegamento: verifica Bluetooth acceso e permesso concesso; `cancelDiscovery` se una scansione è in corso; socket sicuro; se fallisce, socket **non sicuro**; se fallisce ancora, ripiego `createRfcommSocket(1)` (stampanti vecchie); un nuovo tentativo dopo 1,5 s. Timeout di connessione 8–10 s.
- Scrittura: `OutputStream` a blocchi di **256 byte** (configurabile) con pausa di **20 ms** tra i blocchi (le stampanti Bluetooth hanno buffer piccoli: invii troppo veloci troncano l'immagine); `flush` alla fine, attesa 500 ms prima di chiudere, chiusura con `close()` senza `destroy` anticipato. Una sola connessione per lavoro (stesse regole del Prompt 16 §7.2).
- **Impostazione "Velocità di invio"** in Avanzate: *Normale* (blocchi 256 B, pausa 20 ms, bande 64 righe), *Lenta* (blocchi 128 B, pausa 50 ms, bande 24 righe) per stampanti che perdono dati, *Veloce* (512 B, 8 ms, bande 128 righe). Default Normale. Valori salvati in `printer_generic_speed`.
- **Libreria o codice nativo.** Verifica su pub.dev un pacchetto RFCOMM/SPP **mantenuto** (data dell'ultima release, issue aperte, compatibilità con AGP/`compileSdk` attuali e Android 12–15, licenza, permessi richiesti): candidati da valutare `flutter_classic_bluetooth`, `print_bluetooth_thermal`, `blue_thermal_printer`. **Non basare nulla di critico su un solo plugin:** se nessuno è affidabile o se aggiunge dipendenze/permessi inutili, scrivi un piccolo `MethodChannel` Kotlin interno all'app (elenco dei dispositivi associati, connessione SPP, scrittura, chiusura; poche decine di righe su `BluetoothAdapter`/`BluetoothSocket`) dietro `ByteTransport`: il resto del codice non cambia. Documenta la scelta in `docs/stampanti.md`.
- iOS: nessun supporto (il Bluetooth classico richiede il programma MFi di Apple); il trasporto non viene mai creato su iOS.

## 2. Elenco dispositivi e associazione

- Con trasporto "Bluetooth classico", il pulsante **"Cerca stampanti"** mostra i dispositivi **già associati** al telefono (nome + MAC abbreviato, es. `…:A1:B2`), con quelli che sembrano stampanti per primi (nomi con `printer`, `POS`, `BT`, `MTP`, `RPP`, `PT`, `XP`, `MHT`, ecc.) ma **tutti selezionabili**; dispositivo con nome vuoto → MAC. Scoperta di dispositivi non associati (`startDiscovery`) facoltativa: non necessaria.
- Pulsante a larghezza piena **"Associa nuova stampante"** che apre le impostazioni Bluetooth di Android (`android.settings.BLUETOOTH_SETTINGS`); al ritorno l'elenco si aggiorna. Testo guida: "Accendi la stampante, associala dalle impostazioni Bluetooth del telefono (PIN di solito 0000 o 1234), poi tocca Cerca stampanti e scegli il suo nome."
- Alla selezione: `printer_generic_transport = 'bluetooth'`, identificativo `bt:AA:BB:CC:DD:EE:FF` (già riconosciuto da `PrintCoordinator._transportOf`), nome mostrato salvato in `printer_device_name`.
- **Voce del menu Trasporto:** "Bluetooth classico (SPP)" **abilitata su Android**; su iPhone disattivata con "non disponibile su iPhone (usa Wi-Fi o Bluetooth LE)". Rimuovi la dicitura "— non disponibile" su Android. Nella lista Bluetooth LE vuota aggiungi il suggerimento: "Se la stampante compare nelle impostazioni Bluetooth del telefono ma non qui, è una stampante classica: scegli Bluetooth classico (SPP)".
- `GenericLabelPrinter.connect()` non deve aprire connessioni (solo memorizzare identificativo/trasporto) e deve rispettare `PrintTransport.bluetooth` invece di ricadere su `wifi`.
- **Permessi:** `BLUETOOTH_CONNECT` (Android 12+; `BLUETOOTH_SCAN` solo se usi la scoperta), `BLUETOOTH`/`BLUETOOTH_ADMIN` con `maxSdkVersion="30"`, posizione solo su Android ≤ 11 per la scoperta: richiesti **solo** alla pressione di "Cerca stampanti"/"Collega"/"Verifica connessione" tramite `requestBluetoothForPrinters()`, con spiegazione in italiano e scorciatoia alle impostazioni dell'app se negati. Mai all'avvio. Verifica il manifest.

## 3. Carta stretta (58 mm): l'etichetta non entra, niente tagli in silenzio

Una stampante ESC/POS a scontrino da 58 mm stampa al massimo circa **48 mm = 384 punti** a 203 dpi (80 mm → ~72 mm = 576 punti). I formati dell'app (62×40, 50×30, 40×30) sono più larghi: 62 e 50 mm **non entrano**, 40×30 sì. Oggi il motore rifiuta il lavoro con un errore; per l'utente reale serve una soluzione esplicita, **mai** una riduzione nascosta.

- Quando il formato non entra nell'area stampabile, mostra una scelta (dialog in prova di stampa e nel flusso di stampa):
  1. **"Riduci per adattare alla carta"** (consigliato): l'etichetta viene rasterizzata a **larghezza = area stampabile** mantenendo le proporzioni (testi e QR più piccoli);
  2. **"Scegli un formato più piccolo"** (40×30);
  3. **"Annulla"**.
  La scelta può essere ricordata (`printer_generic_fit_mode`: `ask` | `shrink` | `reject`, default `ask`) e modificata in Avanzate ("Se l'etichetta è più larga della carta: chiedi / riduci / rifiuta").
- Con riduzione: anteprima dell'immagine che sarà inviata (già prevista) e **controllo di leggibilità**: se il modulo del QR dopo la riduzione è inferiore a **3 punti** o il corpo del testo più piccolo è sotto ~**7 pt equivalenti**, avviso "L'etichetta ridotta può risultare poco leggibile: prova la stampa di prova e verifica il QR con il telefono".
- Il margine fisso del ritaglio (`cropWhiteBorder`) resta, ma la larghezza finale **non supera mai** l'area stampabile; la larghezza in punti è multipla di 8.
- **Area stampabile modificabile** in Avanzate ("Punti stampabili", già prevista) e preimpostata da carta dichiarata (58 → 384, 80 → 576 a 203 dpi).
- Carta continua (scontrino): niente sensore di etichetta; dopo l'immagine avanzamento configurabile (default 3–4 mm) e taglierina solo se "Taglierina" è attiva. L'altezza stampata è quella dell'immagine ritagliata.
- Test: 62×40 e 50×30 su 58 mm con `fit=reject` → rifiutati con messaggio; con `shrink` → larghezza finale 384, proporzioni mantenute, multipla di 8; 40×30 su 58 mm → nessuna riduzione; 62×40 su 80 mm → nessuna riduzione; avviso di leggibilità quando il QR scende sotto la soglia.

## 4. Errori e diagnostica in italiano

- Messaggi distinti: Bluetooth spento (proponi di attivarlo); permesso negato; stampante **non associata**; **spenta o fuori portata** ("Non riesco a collegarmi: accendi la stampante e avvicinala al telefono"); **occupata** o già collegata ad altro telefono ("Scollegala dall'altro dispositivo"); connessione caduta durante l'invio (nuovo tentativo, poi errore con numero di byte inviati). Nessun MAC completo né nomi di dispositivi nei log (`debugPrint`: tipo di errore e ultimi due byte).
- **"Verifica connessione"** (Prompt 16 §7.4) apre e chiude il socket RFCOMM e distingue non associata / non raggiungibile / occupata; **"Prova solo testo"** funziona via Bluetooth (`ESC @`, riga ASCII, avanzamento, taglio solo se attivo); il riepilogo dell'ultimo invio mostra "Bluetooth classico • N byte • blocchi da 256 B • velocità Normale".
- **Stato carta (facoltativo, sperimentale):** se la stampante risponde a `DLE EOT n` (stato in tempo reale su SPP), mostra "Carta presente/assente" e "Coperchio"; se non risponde entro 500 ms scrivi "stato non disponibile" e **non** inventare nulla. Spento di default; mai bloccare la stampa se non risponde.

## 5. Test automatici

- `GenericPrinterConfig`/coordinatore con `transport: 'bluetooth'` creano `BluetoothSppByteTransport`; l'identificativo `bt:AA:BB:…` diventa `PrintTransport.bluetooth`; `GenericLabelPrinter.connect()` non apre connessioni e non ricade su Wi-Fi.
- Trasporto finto: una sola connessione per lavoro anche con più copie; nuovo tentativo dopo errore; chiusura con attesa dopo l'ultimo `flush`; profili di velocità (blocchi/pausa/bande) applicati.
- Elenco associati con scanner finto: ordinamento stampanti per prime, nome vuoto → MAC, elenco vuoto → messaggio "Associa nuova stampante"; su iOS la voce è disattivata.
- Permessi negati → messaggio chiaro e scorciatoia; Bluetooth spento → proposta di attivarlo.
- Adattamento alla carta (§3) come descritto.
- Widget test della sezione generica con trasporto Bluetooth a 320/360/412 dp, scala 1.0 e 1.15: nessun overflow, pulsanti a larghezza piena, ultima card sopra la barra di sistema.

## 6. Documentazione e prova su hardware

- `docs/stampanti.md`: collegamento Bluetooth classico (come associare, PIN usuali, perché non compare nella ricerca BLE), limiti iOS/MFi, carta 58/80 mm e area stampabile, velocità di invio, riduzione dell'etichetta, risoluzione problemi (stampante occupata, associazione persa, testo ok ma immagine no → velocità Lenta/bande 24), tabella connessioni (Wi-Fi, BLE, Bluetooth classico solo Android, USB non disponibile).
- Dichiara il trasporto **non verificato** finché non provato su hardware: la stampante ESC/POS Bluetooth dell'utente è il primo banco di prova. Aggiungi una sezione "Esito prove" con modello, carta, velocità e impostazioni che funzionano.
- **Test manuale** (da fare sul telefono Android con la stampante reale): associa dal sistema → scegli Bluetooth classico → "Verifica connessione" → "Prova solo testo" → "Stampa etichetta di prova" 40×30 e, con "Riduci per adattare", 50×30 e 62×40 → controlla QR con il telefono → spegni la stampante a metà e verifica il messaggio → riavvia l'app e stampa di nuovo senza ripetere la ricerca.

## Criteri di accettazione

1. Su Android "Bluetooth classico (SPP)" è selezionabile; "Cerca stampanti" elenca i dispositivi associati e offre "Associa nuova stampante"; su iPhone resta disattivato con spiegazione.
2. La stampante ESC/POS Bluetooth dell'utente stampa la prova di solo testo e l'etichetta di prova, con una sola connessione per lavoro e senza ripetere la ricerca dopo il riavvio.
3. Un'etichetta più larga della carta non viene tagliata in silenzio: scelta esplicita (riduci, formato più piccolo, annulla), anteprima e avviso di leggibilità del QR.
4. Velocità di invio configurabile (Normale/Lenta/Veloce); immagine inviata a bande; permessi Bluetooth chiesti solo alla ricerca o al collegamento; nessun MAC completo nei log.
5. Errori in italiano distinti (Bluetooth spento, non associata, fuori portata, occupata, permesso negato); trasporto dichiarato "non verificato" finché non provato.
6. `docs/stampanti.md` aggiornato; `flutter analyze` e `flutter test` verdi.
