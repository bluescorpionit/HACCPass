# Govee H5179 — lettura automatica temperature (Fase 0)

Piano di integrazione dei termo-igrometri **Govee H5179** (Wi-Fi 2,4 GHz +
BLE, 3×AA, precisione dichiarata ±0,3 °C) con le attrezzature HACCP.
Questo documento registra l'esito della **Fase 0** (spike di verifica):
le fasi successive (associazione, registro, allarmi) partono SOLO se la
Fase 0 conferma la lettura BLE affidabile.

## Cosa è verificato (fonti pubbliche)

- Supporto BLE dell'H5179 nell'integrazione Home Assistant `govee_ble` e
  nella libreria **govee-ble** (Bluetooth-Devices, MIT) usata come
  riferimento del protocollo.
- `govee-ble` marca l'H5179 `requires_active_scan = true`: **il payload
  sta nella scan response**, quindi servono scansioni attive
  (`AndroidScanMode.lowLatency`) di durata sufficiente.
- Govee OpenAPI (cloud) come opzione alternativa, con API key personale
  dall'app Govee Home (non usata in questa fase).

## Protocollo (da govee-ble, nessun byte inventato)

Il decoder Dart è in `lib/core/sensors/govee_h5179_decoder.dart`
(test: `test/govee_decoder_test.dart`). L'H5179 advertise in due formati:

### Formato 9 byte — manufacturer id `0x8801` (o nome `*H5179*`)

```
ec 00 01 01 | TT TT HH HH BB
              int16 LE (temp ×100)
                   uint16 LE (umidità ×100)
                        uint8 (batteria %)
```

Pacchetto reale (dai test govee-ble, nome `Govee_H5179_3CD5`, RSSI −50):

```
mfr 0x8801: ec 00 01 01 0a 0a a4 06 64   →  25.7 °C • 17.0 % • bat 100 %
```

### Formato 6 byte — nome `GV5179_*` (famiglia H5108)

```
01 01 | MMM MMM BB
        3 byte: bit 23 = segno temperatura;
        int(mag/1000)/10 = |temp|, (mag % 1000)/10 = umidità
                  byte batteria: bit 7 = errore sensore (lettura scartata)
```

Pacchetto reale (nome `GV5179_6319`, RSSI −68):

```
mfr 0x0001: 01 01 03 b3 14 64   →  24.2 °C • 45.2 % • bat 100 %
```

Range validità: −40…+100 °C (fuori range o bit di errore → nessun dato,
mai valori inventati).

## Come eseguire la verifica (schermata "Diagnostica sensori")

Build di debug → "Altro" → **"Diagnostica sensori (debug)"** (voce visibile
solo con `flutter run`; i permessi Bluetooth vengono chiesti al primo uso).

La schermata mostra per ogni dispositivo: nome, MAC/ID, RSSI,
`manufacturerData` e `serviceData` in esadecimale e la lettura H5179
decodificata. Nessun dato viene salvato.

## ESITO FASE 0 — da compilare con il sensore reale (GATE per la Fase 1)

| # | Verifica | Esito | Note |
|---|----------|-------|------|
| 1 | Pacchetti visti in scansione passiva (senza connessione al sensore) | ☐ | nome `GVH5179_xxxx`/`Govee_H5179_xxxx`? ogni quanti secondi? |
| 2 | Formato ricevuto: 9 byte (mfr 0x8801) e/o 6 byte (GV5179) | ☐ | incollare qui i byte reali |
| 3 | Temperatura decodificata vs display sensore | ☐ | scarto entro ±0,3 °C? |
| 4 | Temperatura decodificata vs app Govee Home | ☐ | scarto entro ±0,3 °C? |
| 5 | Umidità decodificata vs display | ☐ | |
| 6 | Batteria % presente nel pacchetto | ☐ | |
| 7 | I dati BLE continuano con sensore connesso al Wi-Fi | ☐ | se no → Fase 2B cloud |
| 8 | Frigo 0–5 °C: trasmissioni e RSSI con sensore dentro (anta acciaio) | ☐ | telefono/tablet a che distanza? |
| 9 | Congelatore −18/−22 °C: batterie alcaline funzionano? display leggibile? | ☐ | consigliare litio AA se serve |
| 10 | Intervallo di aggiornamento osservato (dichiarato 2 s) | ☐ | |

**Regola di decisione:** se le righe 3–4 (±0,3 °C) o la 7–8 falliscono, la
lettura BLE non è affidabile: passare all'opzione cloud (Fase 2B) e
documentarlo qui.

Esito (da compilare): ______________________________

Data, operatore, sensore #serie: ______________________________

## Note legali/HACCP (già da tenere presenti per la Fase 1)

- Il sensore misura l'**aria** nel punto di installazione, non il cuore
  del prodotto: non sostituisce il termometro a sonda.
- L'H5179 è un sensore consumer, **non certificato/tarato** (EN 12830):
  l'app non lo presenterà mai come strumento conforme; va collegato alla
  "Verifica termometro" esistente (confronto ±1 °C con riferimento).
- Nessun offset di calibrazione invisibile: se impostato, mostrato e
  registrato con il dato.
- iOS non consente lettura BLE continua in background: per uso continuo
  suggerire un tablet Android fisso in cucina ("stazione").

## Stato implementazione

- ✅ Decoder H5179 + test unitari (pacchetti reali, negativi, batteria,
  malformati).
- ✅ Schermata "Diagnostica sensori" (solo debug) con byte grezzi, ora
  agganciata al servizio/registry condiviso.
- ✅ Architettura a modelli (Prompt 7): `SensorModel` + registry in
  `lib/core/sensors/`, `SensorService` singleton (stati live/stale/offline,
  scansione attiva solo quando serve, mai in background).
- ✅ Migrazione DB v5: tabelle `sensors`/`sensor_readings`, colonne
  `temp_source`/`sensor_id` su equipment (vincolo un sensore ↔ una sola
  attrezzatura), `source`/`sensor_label`/`sensor_offset`/`sensor_raw`/
  `sensor_reading_at` su temperature_logs. Test di migrazione e backup.
- ✅ Associazione: campo "Sorgente temperatura", foglio "Collega sensore"
  (scansione live, RSSI, "Già usato per", verifica con termometro ±1 °C,
  offset −3…+3 visibile), scollegamento, scelta nel wizard.
- ✅ Registro: tile stato in tempo reale, "Leggi dal sensore" (disabilitato
  con dato vecchio/non raggiungibile), sorgente nei log e nel PDF,
  "sensori non raggiungibili" in "Da fare ora".
- ⏸ Esiti Fase 0: **da confermare sul campo** — la tabella sopra va
  compilata con misure reali (confronto display e app Govee entro ±0,3 °C,
  frigo 0–5 °C, congelatore −18/−22 °C, comportamento con Wi-Fi collegato)
  prima di considerare affidabile la lettura BLE in produzione.
- ⏸ Fuori scopo (interfacce pronte): campionamento continuo in background,
  allarmi/NC automatici per fuori-limite prolungato, grafici storici,
  Wi-Fi/cloud Govee, gateway/tablet "stazione".
