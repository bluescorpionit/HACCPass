# PROMPT 7 — Associazione sensori alle attrezzature (voci Temperature) — progetto HACCPass

Progetto: `D:\DEV\App\HACCPass` (package `haccpass`). Stato verificato leggendo il codice:
- Già presenti e funzionanti, **da riusare senza duplicare**: `lib/core/sensors/govee_h5179_decoder.dart` (decoder 9 byte/6 byte, con test in `test/govee_decoder_test.dart`), `lib/core/sensors/sensor_source.dart` (interfaccia `SensorSource`, `SensorSample`, `SensorSourceKind`), `lib/screens/sensors/sensor_diagnostics_screen.dart` (scansione BLE con `flutter_blue_plus`, `AndroidScanMode.lowLatency`, voce "Diagnostica sensori" solo `kDebugMode` in `more_screen.dart`), `docs/govee_h5179.md`.
- Il sensore reale viene rilevato e la diagnostica mostra la temperatura. Il resto (DB, associazione, uso nel registro) NON esiste ancora: database a `version: 4` in `lib/core/database/app_database.dart` (file DB `blue_haccp.db`: NON rinominarlo, per non perdere i dati degli utenti), nessuna tabella `sensors`.
- Schermate coinvolte: `lib/screens/temperature/temperature_screen.dart` (`_register`, foglio di registrazione), `lib/screens/temperature/equipment_editor.dart` (lista e foglio "Nuova/Modifica attrezzatura", menu "Storico e verifica termometro"), `equipment_history_sheet.dart`, `lib/models/haccp_models.dart` (`Equipment`, `TemperatureLog`), `lib/repositories/haccp_repository.dart` (`saveTemperature`, ~riga 170), `lib/services/pdf_service.dart` (registro temperature), `backup_service.dart`.
- Layout/tema già corretti nei prompt precedenti: usa `FeatureScaffold`, `screenPadding`, `showFormSheet` (con area sicura), `ChoiceChipX`, token di colore del tema. Non reintrodurre colori hardcoded né schermate senza Scaffold.

Obiettivo: ogni attrezzatura può avere come **sorgente della temperatura** **Manuale** (default, comportamento attuale invariato) oppure **Sensore** (oggi Govee H5179; in futuro altri modelli aggiungendo solo una classe). Procedi per fasi; dopo ciascuna `flutter analyze` e `flutter test`.

---

## FASE 1 — Catalogo modelli e servizio condiviso (estendibile)

In `lib/core/sensors/` aggiungi, appoggiandoti al codice esistente:
- `sensor_model.dart`:
  ```dart
  abstract class SensorModel {
    String get id;                 // 'govee_h5179'
    String get displayName;        // 'Govee H5179 (Bluetooth)'
    SensorSourceKind get transport; // ble | cloud | gateway
    bool matches(BleAdvertisement a);          // riconosce il modello da nome/mfr data
    String? stableKey(BleAdvertisement a);     // chiave stabile (suffisso del nome, es. 'AB12')
    SensorSample? decode(BleAdvertisement a);  // usa il decoder esistente
    SensorSpecs get specs;         // range operativo / precisione: null = "da verificare", MAI inventare valori
  }
  ```
- `govee_h5179_model.dart`: wrapper sottile attorno a `GoveeH5179Decoder` (nessuna logica duplicata; riusa `isH5179Name`).
- `sensor_registry.dart`: lista dei modelli disponibili (oggi solo Govee H5179). Aggiungere un modello futuro = nuova classe + una riga qui.
- `ble_sensor_source.dart`: implementa `SensorSource` con `flutter_blue_plus` (scansione attiva low latency, stessa configurazione della diagnostica). Singleton condiviso `SensorService` che tiene in memoria l'ultima lettura per sensore, espone `Stream` e `latestFor(key)`, e calcola lo stato: `live` (< 10 min, soglia configurabile), `stale` (≥ soglia), `offline` (mai visto nella sessione). Scansione avviata SOLO dalle schermate che la richiedono (Temperature, Collega sensore) e fermata all'uscita; nessuna scansione in background in questa fase. Gestisci adattatore Bluetooth spento e permessi negati con messaggio chiaro e ripiego Manuale.
- **Chiave stabile del sensore:** su iOS l'ID BLE cambia da telefono a telefono, quindi identifica il sensore con il **nome pubblicizzato** (`GVH5179_AB12` / `Govee_H5179_AB12` / `GV5179_AB12`) normalizzato al suffisso `AB12`; conserva l'ID di sistema solo come dato secondario.
- Aggiorna la diagnostica per usare il servizio/registry (resta solo debug).

## FASE 2 — Modello dati (migrazione v4 → v5)

Aggiorna `app_database.dart` (`version: 5`, `_onCreate` e `_onUpgrade`, con `_addColumn` già presente):
- Tabella `sensors`: `id INTEGER PK, model_id TEXT, device_key TEXT UNIQUE, system_id TEXT, label TEXT, calibration_offset REAL NOT NULL DEFAULT 0, last_temp REAL, last_humidity REAL, last_seen TEXT, battery INTEGER, enabled INTEGER NOT NULL DEFAULT 1, created_at TEXT`.
- `equipment`: aggiungi `temp_source TEXT NOT NULL DEFAULT 'manual'` e `sensor_id INTEGER` (indice univoco parziale su `sensor_id` dove non nullo: un sensore ↔ una sola attrezzatura).
- `temperature_logs`: aggiungi `source TEXT NOT NULL DEFAULT 'manual'`, `sensor_id INTEGER`, `sensor_label TEXT`, `sensor_reading_at TEXT`, `sensor_raw REAL`, `sensor_offset REAL`.
- Facoltativo (solo se serve per la schermata storico): `sensor_readings(sensor_id, ts, temp, humidity, rssi)` con salvataggio solo mentre l'app è aperta (max 1 ogni 5 min per sensore, o se la temperatura varia ≥ 0,2 °C; retention 90 giorni).
- Estendi `Equipment` e `TemperatureLog` (+ `fromMap`/`toMap`), `HaccpRepository` (CRUD sensori, `linkSensor`/`unlinkSensor`, `saveTemperature` con i nuovi campi) e il backup/ripristino (`backup_service.dart`) con le nuove tabelle/colonne. Test di migrazione v4→v5 (modello come `test/migration_v4_test.dart`) e round-trip di backup.
- Disattivare un'attrezzatura o scollegare un sensore NON cancella le letture passate né i log.

## FASE 3 — Interfaccia di associazione

In `equipment_editor.dart` (foglio Nuova/Modifica attrezzatura) e nella scheda attrezzatura:
1. Campo **"Sorgente temperatura"**: `Manuale` (default) / `Sensore`. Scegliendo Sensore, scelta del **modello** dal `SensorRegistry` (oggi "Govee H5179 (Bluetooth)").
2. Pulsante **"Collega sensore"** → foglio con scansione live: elenco dei dispositivi riconosciuti dal modello scelto, per ciascuno etichetta (`GVH5179_AB12`), **temperatura attuale**, umidità, barre RSSI, batteria; se già assegnato a un'altra attrezzatura mostra "Già usato per: …" (selezionabile solo con conferma di spostamento). Aiuto: "Scalda il sensore con la mano: quello che sale è il tuo", evidenziando la riga con la variazione maggiore.
3. Etichetta personalizzabile del sensore (es. "Sensore frigo carni 1").
4. Dopo il collegamento, proposta della **verifica con termometro di riferimento** riusando il flusso esistente "Storico e verifica termometro" (scarto sensore vs riferimento, tolleranza ±1 °C): se oltre, proponi offset di calibrazione oppure NC. Mostra "Verificato il gg/mm/aaaa".
5. **Offset di calibrazione** (−3,0…+3,0 °C, passo 0,1) sempre visibile con il valore; applicato e registrato ovunque (`sensor_raw`, `sensor_offset` nel log, nota nel PDF).
6. **Scollega / Cambia sensore** con conferma → torna a Manuale.
7. Wizard iniziale (passo attrezzature): per ogni attrezzatura "Manuale / Sensore (collego dopo)"; il collegamento vero avviene in Temperature.
8. Se i limiti dell'attrezzatura sono incompatibili con `specs` del modello (solo quando `specs` è valorizzato) mostra un avviso; se `specs` è null mostra "Range operativo da verificare nel manuale del sensore". Non scrivere range inventati.
9. Per abbattitori e cotture: il sensore dà la temperatura dell'ambiente, non del prodotto né del ciclo; il registro ciclo con sonda resta com'è, il sensore è solo monitoraggio ambiente (testo esplicativo nel foglio di collegamento).

## FASE 4 — Uso nel registro temperature

- Scheda attrezzatura con sensore (in `temperature_screen.dart`): temperatura attuale in evidenza, stato (`In linea` / `Dato vecchio da X min` / `Non raggiungibile`), orario ultimo dato, colore secondo i limiti con i token del tema e sempre anche icona + testo (non solo colore).
- Nel foglio di `_register`: se l'attrezzatura ha un sensore, accanto al campo valore compare **"Leggi dal sensore"**: compila la temperatura (offset applicato) e mostra "Letto dal sensore alle hh:mm". L'operatore conferma e salva (la firma resta umana). Se il dato è `stale`/`offline` il pulsante è disabilitato con motivo e resta l'inserimento manuale. Se l'operatore modifica il valore, `source` diventa `manual`.
- `saveTemperature` registra `source='sensor'`, `sensor_id`, `sensor_label`, `sensor_reading_at`, `sensor_raw`, `sensor_offset`. Fuori-limite → flusso azioni correttive/NC già esistente, identico.
- "Da fare ora": la lettura mancante si completa con "Registra dal sensore" (foglio già compilato). Nessuna registrazione automatica silenziosa in questa fase.
- Dashboard: badge sensore sulle attrezzature collegate; riga di avviso se sensore non raggiungibile oltre soglia (severità warning, coerente con la semantica dei colori già definita).
- `pdf_service.dart` (registro temperature): indicazione **"Sorgente"** (Manuale / Sensore GVH5179_AB12), nota a piè pagina se applicato un offset, nessuna dicitura che presenti il sensore come tarato/certificato.
- `docs/govee_h5179.md`: aggiorna "Stato implementazione". NON spuntare da solo le caselle dell'esito Fase 0 (richiedono misure con il sensore reale: confronto con display e app Govee, ±0,3 °C, frigo e congelatore): lascia lo spazio per l'utente e annota "da confermare sul campo".

## FASE 5 — Permessi, test, qualità

- Permessi BLE chiesti solo al primo "Collega sensore" (già dichiarati Android `neverForLocation` e iOS in italiano): se negati l'app resta pienamente utilizzabile in Manuale.
- Test unitari: `SensorRegistry`/`GoveeH5179Model.matches/stableKey/decode` (nomi `GVH5179_AB12`, `Govee_H5179_AB12`, `GV5179_AB12`, pacchetti validi e malformati senza crash), vincolo univoco sensore↔attrezzatura, stati live/stale/offline con orologio finto, offset e `sensor_raw`.
- Test widget con `FakeSensorService`: scelta sorgente, associazione, "Leggi dal sensore" (attivo/disabilitato), scollegamento; nessun overflow a 360×640 con scala testo 1,15; contrasto e area di tocco ≥ 48 dp.
- Test di migrazione v4→v5 con dati esistenti e di backup/ripristino.
- `flutter analyze` pulito.

## Fuori scopo adesso (predisponi solo le interfacce già previste)
Campionamento continuo in background, allarmi/NC automatici per fuori-limite prolungato, grafici storici, Wi-Fi/cloud Govee, altri modelli, gateway/tablet "stazione". Il registro deve dipendere solo da `SensorService` e `SensorModel`.

## Criteri di accettazione
1. Ogni attrezzatura ha "Sorgente temperatura": Manuale (default, nessuna regressione) o Sensore.
2. Il Govee H5179 reale si associa a un'attrezzatura mostrando la temperatura in tempo reale; un sensore non può servire due attrezzature senza conferma di spostamento.
3. "Leggi dal sensore" compila il valore con orario e offset; con dato vecchio o irraggiungibile è disabilitato e si inserisce a mano.
4. Log e PDF riportano la sorgente; il sensore non è mai presentato come strumento certificato.
5. Aggiungere un nuovo modello richiede una nuova classe `SensorModel` e una riga nel registry.
6. Migrazione v5, backup/ripristino, test e `flutter analyze` passano.
