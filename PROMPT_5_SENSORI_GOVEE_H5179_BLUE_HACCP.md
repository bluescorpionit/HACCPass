# PROMPT 5 — Lettura automatica temperature da sensori Govee H5179 (Blue HACCP)

Obiettivo: collegare i termoigrometri **Govee H5179** (Wi-Fi 2.4 GHz + Bluetooth LE, batterie AA) alle attrezzature (frigo/celle) per registrare in automatico le temperature nel registro, con allarmi e non conformità. Procedi per fasi e NON passare alla successiva senza il risultato della Fase 0.

## Cosa è verificato e cosa NO
Verificato da fonti pubbliche: il modello H5179 è supportato dall'integrazione Bluetooth di Home Assistant (`govee_ble`) e da integrazioni che usano la **Govee OpenAPI** (cloud, richiede API key personale ottenuta dall'app Govee Home). Specifiche dichiarate dal produttore: precisione ±0,3 °C, umidità ±3% RH, aggiornamento ogni 2 s, storico cloud 20 giorni con export CSV, 3 batterie AA, Wi-Fi solo 2,4 GHz.
NON verificato (da controllare sul dispositivo reale, non assumere): il formato esatto dei dati nel pacchetto BLE dell'H5179, se i dati BLE sono trasmessi sempre o solo in certe condizioni (es. quando non connesso al Wi-Fi), l'intervallo operativo (importante per i congelatori a −18/−22 °C), i limiti di richieste della OpenAPI. Non inventare offset o byte: usa la libreria open source `govee-ble` (Bluetooth-Devices) come riferimento del protocollo e conferma con prove reali.

## FASE 0 — Spike di verifica (obbligatoria, piccola)
1. Crea una schermata nascosta "Diagnostica sensori" (solo debug) che fa scansione BLE e mostra per ogni dispositivo: nome (`GVH5179_xxxx`), MAC/ID, RSSI, `manufacturerData` grezzo in esadecimale, `serviceData`.
2. Implementa il decodificatore H5179 seguendo `govee-ble`; confronta temperatura/umidità decodificate con il display del sensore e con l'app Govee Home (tolleranza ±0,3 °C). Registra l'esito nel README (`docs/govee_h5179.md`) con screenshot e byte di esempio.
3. Verifica: i dati arrivano senza connettersi al sensore (advertisement passivo)? ogni quanti secondi? continuano con il sensore collegato al Wi-Fi? Cosa succede a 0–5 °C in frigo e a −20 °C (congelatore): batterie alcaline, display, trasmissione?
4. Se i dati BLE non sono leggibili in modo affidabile, passa all'opzione cloud (Fase 2B) e documentalo.

## FASE 1 — Lettura via Bluetooth (opzione principale, offline)
- Dipendenza: `flutter_blue_plus` (o equivalente mantenuto). Android: permessi `BLUETOOTH_SCAN` (con `neverForLocation`), `BLUETOOTH_CONNECT`, e `ACCESS_FINE_LOCATION` per Android ≤ 11. iOS: `NSBluetoothAlwaysUsageDescription` in italiano. Mai richiedere i permessi all'avvio: chiedili alla prima associazione, con spiegazione.
- Modello dati (migrazione incrementale DB v5): tabella `sensors` (id, equipment_id, vendor 'govee', model 'H5179', ble_id, label, last_seen, last_temp, last_humidity, battery_note, enabled, calibration_offset), tabella `sensor_readings` (id, sensor_id, ts, temp, humidity, source 'ble'|'cloud'|'manual', rssi). Nessun offset di calibrazione invisibile: se impostato, va mostrato e registrato.
- Associazione: nella scheda attrezzatura (frigo/cella) pulsante "Collega sensore": scansione, lista dei `GVH5179_*` con RSSI, conferma guidata (es. "scalda il sensore con la mano e verifica che la temperatura salga"), assegnazione all'attrezzatura.
- Acquisizione: campionamento ogni 5 min (configurabile 1–30) in memoria, salvataggio in DB solo se cambia ≥0,2 °C o ogni 15 min; retention configurabile (default 90 giorni, poi aggregato min/max/medio).
- **Funzionamento in background:**
  - Android: foreground service con notifica persistente "Monitoraggio temperature attivo" (opt-in, spiegando consumo batteria); gestione esclusione ottimizzazione batteria.
  - iOS: la lettura continua in background è limitata; l'app deve dichiararlo chiaramente e leggere in foreground + al risveglio. Suggerisci per uso continuo un **tablet Android fisso in cucina** come "stazione di monitoraggio" (modalità "Stazione").
  - Mostra sempre "ultimo dato ricevuto alle hh:mm"; se oltre 15 min (configurabile) → stato "Sensore offline" e NC/avviso (batterie, fuori portata).
- Portata: il frigo in acciaio scherma il BLE. Spiega nell'app: posizionare sensore appeso dentro e telefono/tablet vicino; mostra RSSI e qualità del segnale in tempo reale.

## FASE 2A — Integrazione con il registro temperature
- Il registro giornaliero (mattina/sera) può essere **precompilato** con l'ultima lettura automatica ed è proposto come "Letture automatiche (sensore)": l'operatore **conferma con un tocco** (firma/operatore resta umano). Le letture automatiche NON sostituiscono la verifica visiva: etichetta `Automatica` nei PDF e nel registro, con ID sensore e intervallo di campionamento.
- Controllo limiti per attrezzatura (es. 0/+4, −18, limiti configurati): fuori limite per più di N minuti (default 20, configurabile, per ignorare l'apertura porta) → notifica locale + apertura **non conformità automatica** con azione correttiva suggerita e dati (min/max/durata).
- Sbrinamento/pulizia: finestra di esclusione programmabile (es. 03:00–04:00).
- Grafico andamento 24 h/7 gg/30 gg per attrezzatura con fascia dei limiti, min/max, tempo fuori limite; esportazione nel PDF registro temperature (grafico + tabella riassuntiva) e CSV.
- Dashboard: card "Sensori" (online/offline, ultima lettura, batteria da verificare), riga "Da fare ora" se sensore offline.

## FASE 2B — Opzione cloud (solo se la Fase 0 la rende necessaria o come alternativa)
- Govee OpenAPI con API key personale dell'utente, **conservata nello storage sicuro** (`flutter_secure_storage`), mai nel backup in chiaro né nei log. Polling a intervalli lunghi con gestione errori e backoff; rispetta i limiti di richieste (verificali nella documentazione ufficiale developer.govee.com prima di fissare gli intervalli). Segnala all'utente che dipende da internet e dal servizio Govee.
- Stessa tabella `sensor_readings` con `source='cloud'`.

## FASE 3 (facoltativa) — Gateway sempre acceso
- Documenta nella Guida l'opzione "gateway": mini-PC/ESP32/tablet che legge i sensori e li inoltra all'app (es. endpoint LAN o file condiviso). Non implementare ora: prepara solo un'interfaccia `SensorSource` (BLE, Cloud, Manual, in futuro Gateway) per poter aggiungere sorgenti senza toccare il registro.

## Accorgimenti HACCP e legali (da mostrare in app)
- Il sensore misura la temperatura dell'aria nel punto in cui è installato, non al cuore del prodotto; non sostituisce le misure con termometro a sonda (cottura, abbattimento, ricevimento merce).
- Il Govee H5179 è un sensore consumer: **non è uno strumento certificato/tarato** (es. EN 12830). L'app non deve presentarlo come tale. Collegalo alla funzione "Verifica termometro" (confronto con termometro di riferimento ±1 °C, già presente) e mostra la data dell'ultima verifica del sensore; blocca la dicitura "conforme" se la verifica è scaduta e avvisa l'utente.
- Il responsabile deve riesaminare periodicamente le registrazioni automatiche (promemoria settimanale "Rivedi le temperature") e firmare.
- Batterie: mostra il livello se disponibile dal pacchetto BLE; in celle frigorifere e congelatori le batterie alcaline si scaricano più in fretta e sotto circa −20 °C le prestazioni calano: suggerisci batterie al litio AA per i congelatori e controlla l'intervallo operativo dichiarato dal produttore prima di consigliare l'uso in abbattitori o congelatori molto freddi.

## Test e criteri di accettazione
1. Fase 0 documentata con byte reali e confronto con display/app Govee entro ±0,3 °C.
2. Decoder con test unitari su pacchetti campione (positivi, negativi sotto zero, umidità, batteria) e su pacchetti malformati (nessun crash).
3. Associazione sensore ↔ attrezzatura, lettura automatica, stato offline, notifiche e NC automatica funzionanti; nessun dato inventato quando il sensore è offline (mai "riempire" buchi).
4. PDF registro con indicazione chiara "lettura automatica", ID sensore e intervallo; grafico leggibile in bianco e nero.
5. Permessi richiesti solo al momento dell'uso; l'app resta pienamente utilizzabile senza sensori (funzione opzionale).
6. `flutter analyze` pulito; test di migrazione DB v4→v5; backup/ripristino includono `sensors` e le letture aggregate.
