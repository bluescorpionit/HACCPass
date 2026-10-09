# HACCPass

App Flutter per l'autocontrollo alimentare (HACCP) di piccoli esercizi italiani:
bar, ristoranti, pizzerie, gastronomie, caseifici, laboratori. **Offline-first**:
nessun server, nessun account, tutti i dati restano in un database SQLite locale.

> I limiti di temperatura e le soglie dell'app sono **valori di riferimento**
> desunti dai manuali di corretta prassi e dalla normativa (Reg. CE 852/2004,
> 178/2002, UE 1169/2011). L'operatore può adattarli alla propria attività:
> la responsabilità dell'autocontrollo resta dell'operatore.

## Funzioni

### Registri HACCP (v1)

- **Oggi** (dashboard): avanzamento controlli, "Da fare ora" per gravità,
  azioni rapide, chip licenza, card "Completa la configurazione: X%".
- **Controlli**: temperature (PRP 11) con azioni correttive e grafico 14
  giorni, verifica termometri (PRP 4), pulizie (PRP 2), merce in arrivo
  (PRP 10), infestanti (PRP 3), strutture (Allegato VII), non conformità
  (Allegati I e III) con destino del prodotto, eliminazione prodotti
  (Allegato II), personale (Allegato VI), fornitori.
- **Lotti**: codice automatico, scadenza precompilata, allergeni (14, Reg.
  UE 1169/2011), ingredienti collegati alle consegne, rintracciabilità a
  monte/valle (Reg. CE 178/2002), etichetta 62x40 con QR.
- **Report**: dossier HACCP completo per periodo (copertina, indicatori,
  registri, firma), singoli registri, menù allergeni, appendice fotografica
  (opzionale) delle NC e merci respinte, logo aziendale in intestazione.
- **Licenza**: prova 14 giorni (primaria gestita dallo store con offerta
  gratuita, riserva locale con "ancora" che sopravvive alla
  reinstallazione — vedi `docs/acquisti.md`), solo abbonamento annuale
  dello store: nessuna chiave offline dal Prompt 13.
- **Stampa etichette** (Prompt 11): motori a scelta del cliente —
  Brother QL (SDK ufficiale, Wi-Fi/USB), Niimbot (BLE, larghezza letta
  dal dispositivo), stampante generica ESC/POS o TSPL (TCP 9100 o BLE)
  e stampa di sistema — coda con avanzamento/annulla, etichetta di
  prova, anteprima, più stampanti salvate; senza stampante l'app resta
  pienamente utilizzabile (condivisione PDF). Dettagli e modelli
  verificati/non verificati in `docs/stampanti.md`.

### Correzioni visive e accessibilità (v3)

- `FeatureScaffold`: ogni schermata aperta via push ha AppBar con titolo e
  freccia indietro, sfondo opaco dal tema. Nessun `Colors.transparent`.
- Palette corretta: bordo controlli `#6B7B78`/`#6F8581` (≥3:1), divider
  `#D5DFDC`/`#2A3B37`, warning testo `#B45309` (5.0:1 su bianco) con striscia
  dedicata `#D97706`. Snackbar da `inverseSurface`/`onInverseSurface`.
  Bottom sheet opaco con maniglia e angoli 24.
- Semantica severity nel "Da fare ora": **danger** solo NC aperte, formazione
  scaduta, lotti scaduti; **warning** ciò che è in ritardo o in scadenza
  entro 7 giorni; **info** le attività giornaliere ordinarie.
- Test automatici: rapporto di contrasto WCAG su tutte le coppie
  testo/sfondo e bordo/superficie in light e dark, `lerp(a,b,1)==b` per ogni
  campo di `HaccpColors` (bug warning→warningBg corretto), widget test di
  `FeatureScaffold` (AppBar, sfondo, freccia indietro).

### Aggiornamenti normativi (v3, verificati)

- **Reg. UE 2021/382**: modulo "Cultura della sicurezza alimentare"
  (politica firmata, comunicazioni al personale, verifica annuale) e
  registro facoltativo **ridistribuzione alimenti** (donazioni).
- **Comunicazione 2022/C 355/01**: **registro scritto allergeni** per
  piatto/prodotto in PDF (oltre al menù a matrice) e checklist
  **contaminazione crociata** con verifica residui su attrezzature condivise.
- **Formazione**: mesi di rinnovo configurabili (default 36; es. L.R.
  Emilia-Romagna 9/2025, DGR Toscana 540/2024) in "Moduli e limiti".
- Guida con riferimenti aggiornati, data dei contenuti e disclaimer
  ("non sostituiscono la consulenza di un tecnico HACCP o le disposizioni
  della propria ASL/Regione"), ripreso anche nei PDF.

### Moduli dal manuale MGSA-0415 (v3, PR DP15)

Tutti con **limiti configurabili** e default dal manuale, ogni fuori limite
apre una NC con azione correttiva suggerita:

- **PR COT**: registrazione cottura/rigenerazione con tabella cuore/tempo
  (72 °C/2 min carni intere, 63 °C/15 s muscoli, 74 °C/15 s pollame e pasta
  ripiena…), cottura ≥ 75 °C, rigenerazione ≥ 65 °C, frittura max 180 °C;
  registro **validazione olio** con esito organolettico e cambio.
- **PR ABB**: cicli di abbattimento positivo (+3 °C/2 h) e negativo
  (−18 °C/2 h), limiti ampi alternativi configurabili; anomalia → ritiro e
  distruzione.
- **PR TRA/SOM**: mantenimento caldo 60-65 °C, freddo < 10 °C, trasporto
  catering con temperature partenza/arrivo e checklist automezzo/contenitori.
- **PR CAMP 01**: pasto campione ≥ 100 g, conservazione 0/+4 °C per 72 ore,
  scadenza di smaltimento calcolata e promemoria nella dashboard.
- **PR APO**: promemoria analisi annuale acqua (referto allegabile),
  pulizia filtri e sanificazione mensile produttore di ghiaccio.
- **PR ALL 01**: collegamento tra allergeni del personale (scheda firmata
  all'assunzione) e registro scritto.
- **PR RIN**: modulo ritiro/richiamo con lotto, destinatari, azioni,
  comunicazione ASL ed esportazione PDF.
- **PDF**: tutti i nuovi registri nel dossier (con firma), modulo ritiro,
  registro scritto allergeni e **prospetto riassuntivo moduli** (modulo,
  frequenza, stato).
- Schermata **"Moduli e limiti"** in Altro: limiti numerici modificabili e
  interruttori per attivare/disattivare ogni modulo (campione e donazioni
  disattivati di default).

### Wizard di prima configurazione (v2)

13 passi (0-12): benvenuto con Termini/Privacy (versione e data salvate),
tipo di attività (11 modelli con attrezzature, piano pulizie, prodotti e
allergeni suggeriti), anagrafica con P.IVA validata (checksum) e logo,
responsabili e personale, locali e attrezzature con contatori e limiti
precompilati, piano di pulizia proposto, disinfestazione e strutture,
fornitori (manuale o import dai contatti al momento dell'uso), prodotti e
allergeni, backup e cloud, promemoria locali (permesso chiesto al passo 10),
formato etichetta con stampa di prova, riepilogo con **Piano di
autocontrollo PDF** personalizzato.

- Saltabile, riprendibile (`onboarding_step`) e rieseguibile da
  "Altro > Configurazione guidata".
- **Idempotente**: le righe create dal wizard hanno `source='wizard'` e
  `template_key`; rieseguire ricostruisce solo quelle non modificate a mano
  (`source='user'`), mai duplicati né perdite di modifiche.
- Non blocca la prova gratuita; percentuale di completamento in dashboard.

### Allegati: foto e documenti (v2)

Tabella `attachments` (foto/documenti) su ricevimenti, NC, personale,
attrezzature, fornitori, lotti, azienda. Acquisizione con fotocamera/galleria
(`image_picker`, compressione lato lungo 1600 px q80) o selettore documenti
di sistema — che include Google Drive, iCloud, OneDrive e Dropbox senza
OAuth. Visualizzatore con zoom, condivisione, eliminazione. Le foto di NC e
merci respinte finiscono nell'appendice fotografica del dossier.

### Cloud e backup (v2)

- **Due livelli**: sempre disponibile il foglio di condivisione/"Salva con
  nome" (`share_plus`/`file_picker`, qualsiasi cloud installato);
  opzionale il collegamento a **Google Drive** per backup automatici e copia
  di PDF e foto. Su iPhone in v1 salvataggio tramite app File/iCloud.
- `CloudStorageProvider` astratto: `GoogleDriveProvider` (scope minimo
  **`drive.file`**, cartella visibile "HACCPass" con Backup/Report/Foto) e
  `LocalFilesProvider`. Pulsante "Scollega" che revoca i token.
- **Backup `.bhb`**: ZIP con DB + `manifest.json` (versione schema, versione
  app, data, hash SHA-256). Cifratura facoltativa AES-256-GCM con chiave
  PBKDF2 (120k iterazioni), password mai salvata. Un backup al giorno alla
  prima apertura utile, ultimi 14 conservati. Ripristino con verifica di
  integrità, backup di sicurezza automatico e rifiuto dei backup di versioni
  future.
- `sync_queue` con retry/backoff e messaggi in italiano; caricamento al
  ritorno in primo piano. Su iOS nessuna promessa di background.
- Schermata **"Documenti e backup"** in Altro: stato, ultimo backup, coda,
  backup ora, ripristino (cloud o file), collega/scollega.
- Limite dichiarato: **un dispositivo principale per attività**; gli altri
  ripristinano un backup. Nessuna sincronizzazione realtime multi-device.

### iOS (v2)

- `Info.plist` con permessi in italiano (fotocamera, foto, contatti).
- `PrivacyInfo.xcprivacy` con required-reason API; dichiarare "Dati non
  raccolti" in App Store Connect (nessun dato va a server dello sviluppatore).
- **Chiavi di licenza offline rimosse** (Prompt 13): licenza solo store,
  nessun campo chiave nell'app; per regali e prove usare i codici
  promozionali degli store ("Hai un codice?" su iOS apre il riscatto
  di StoreKit).
- Paywall con "Ripristina acquisti" (obbligatorio), "Gestisci
  abbonamento" e prezzo dallo store. Su iOS configurare **solo
  l'abbonamento annuale** (gruppo dedicato), niente licenza a vita.
- Google Drive = "Collega", non "Accedi" (guideline 4.8: nessun account).
- Foglio di condivisione su iPad: `sharePositionOrigin` sempre passato.
- Pipeline CI documentata in `.github/workflows/ios-testflight.yml`
  (runner macOS, firma, upload TestFlight).

## Comandi

```
flutter pub get && flutter run        # sviluppo (launch.json include il secret dev)
flutter analyze && flutter test       # verifiche
tool/build_release.bat                # release Android: richiede BH_ANCHOR_SECRET
                                      # e GOOGLE_SERVER_CLIENT_ID come variabili
                                      # d'ambiente + android/key.properties
flutter build ipa --release --dart-define=BH_ANCHOR_SECRET=<SEGRETO>  # iOS (macOS)
```

## Configurazione manuale (a carico del titolare)

### Google Cloud (per il collegamento a Drive)

1. Progetto in Google Cloud Console, abilitare **Google Drive API**.
2. Schermata di consenso OAuth: nome app, logo, link privacy; utente di test
   durante lo sviluppo.
3. ID client **Android** con SHA-1 di debug, release **e Play App Signing**.
4. ID client **iOS**: inserire in `ios/Runner/Info.plist` il
   `GIDClientID` e il reversed client ID come URL scheme (i punti da
   completare sono commentati nel file).
5. Nessuno scope oltre `drive.file`.

### App Store Connect

1. Bundle ID, certificati, profilo; record app; screenshot iPhone (+ iPad se
   supportato) in italiano.
2. **Un solo abbonamento annuale** (49 €/anno, offerta introduttiva prova
   gratuita 14 giorni) con testi in italiano; paywall con prezzo,
   durata, rinnovo, Termini/Privacy, Ripristina.
3. Small Business Program (commissione 15%) da richiedere.
4. Etichette privacy "Dati non raccolti"; pagina privacy e supporto online.
5. Note per la revisione: nessun account richiesto; Google solo come
   archivio; come provare l'acquisto in sandbox; i limiti sono valori di
   riferimento e l'app non sostituisce il tecnico.

### Google Play

Identificativo definitivo **`it.bluescorpion.haccpass`** (già configurato),
firma di release tramite `android/key.properties` NON versionato (senza il
file la build di release fallisce con messaggio chiaro: procedura keystore
e impronte SHA-1/SHA-256 in [`docs/identificativi.md`](docs/identificativi.md)),
Play App Signing con SHA-1 registrate in Google Cloud, scheda Sicurezza
dei dati coerente (dati solo locali e nel cloud del cliente), foto picker di
sistema (nessun permesso galleria), `POST_NOTIFICATIONS` dichiarato.

### Acquisti in-app

ID prodotto allineato all'identificativo: `it.bluescorpion.haccpass.annual`
(abbonamento annuale 49 € con offerta di prova gratuita di 14 giorni,
come descritto in `docs/acquisti.md`). **Licenza solo store dal Prompt
13**: nessuna chiave offline, nessun prodotto a vita (il codice storico
delle chiavi è in `tool/archive/`); per regali e prove ai clienti usare
i codici promozionali degli store.
Build di release SEMPRE con `--dart-define=BH_ANCHOR_SECRET=<valore>`
(segreto del MAC dell'ancora della prova; accettato anche il vecchio
`BH_LICENSE_SECRET` come alias): con segreto vuoto l'app si rifiuta di
avviarsi. QR attrezzature: schema
attuale `haccpass://`, lo storico `bluehaccp://` resta valido.

## Struttura

```
lib/
  core/
    constants/haccp_rules.dart       # soglie, preset, allergeni, livelli
    constants/business_templates.dart# 11 modelli di attività per il wizard
    database/app_database.dart       # SQLite v3, migrazioni v1->v2->v3
    license/app_integrity.dart      # segreto dell'ancora (BH_ANCHOR_SECRET)
    license/trial_anchor.dart       # ancora della prova (anti-reinstallazione)
    theme/app_theme.dart             # design system, HaccpColors
    utils/format.dart                # formattazione it
  models/haccp_models.dart           # modelli + Attachment
  repositories/haccp_repository.dart # dati, revision, "Da fare ora", wizard
  screens/                           # Oggi, Controlli, Lotti, Report, Altro,
                                     # onboarding/, goods/, nc/, ...
  services/
    onboarding/onboarding_controller.dart  # stato e applicazione idempotente
    attachment_service.dart          # foto/documenti con compressione
    cloud/                           # CloudStorageProvider, Google Drive, locale
    backup_service.dart              # .bhb + AES-256-GCM + PBKDF2
    sync_service.dart                # coda di caricamento
    reminder_service.dart            # notifiche locali (timezone)
    pdf_service.dart                 # dossier, piani, etichette, QR
    printing/                        # motori etichette (Prompt 11): brother,
                                     # niimbot, generica ESC/POS/TSPL, sistema
    license_service.dart             # prova, abbonamento store (EntitlementSource)
.github/workflows/ios-testflight.yml
```

### Database

Versione 4. `onUpgrade` senza perdita di dati: v1→v2 (registri HACCP), v2→v3
(allegati, sync_queue, source/template_key), v3→v4 (cooking_logs,
oil_validations, blast_chill_cycles, transport_logs, sample_meals,
water_checks, withdrawals, culture_log, cross_contamination_checks,
donations + default dei limiti PR COT/ABB/TRA/CAMP e interruttori moduli).
Test di migrazione reale con `sqflite_common_ffi`: crea un DB v3 con dati,
verifica tabelle, default e conservazione dei dati.

## Test

```
flutter test
```

Coprono: stati pulizie, livelli infestanti, conformità temperature per
categoria, termometri, **ancora della prova e licenza store-only**
(`trial_anchor_test`, `license_service_test`, `license_restore_test`,
`license_screen_test`), **validazione P.IVA**, **modelli di
attività e merge senza duplicati**, **cifratura backup** (roundtrip, password
errata, salt/nonce) e **fix di layout** (`layout_fixes_test.dart`: Scaffold
nelle schermate pushate, nessun overflow a 360×640 con scala 1.15, fogli
modali sopra la barra di navigazione con inset simulati, azioni correttive
integre a scala 1.3).

## Layout edge-to-edge e QA

L'app gira in edge-to-edge (Android 15): ogni schermata somma gli inset di
sistema tramite `screenPadding()` (`common_widgets.dart`), nessuna
schermata pushata resta senza Scaffold, i fogli modali tengono il pulsante
Salva sopra tastiera e barra di navigazione, la scala tipografica è
compatta (clamp 0.9–1.15). La checklist di verifica manuale su telefono
reale (tema × font × navigazione × orientamento) è in
[`docs/qa_layout.md`](docs/qa_layout.md).

## Sensori Govee H5179 (sperimentale)

Lettura automatica delle temperature dai termo-igrometri Govee H5179 via
Bluetooth: stato e protocollo in [`docs/govee_h5179.md`](docs/govee_h5179.md).
Ogni attrezzatura ha una "Sorgente temperatura": **Manuale** (default,
comportamento invariato) o **Sensore** collegato dal foglio "Collega
sensore" (scansione live, verifica con termometro ±1 °C, offset di
calibrazione sempre visibile). I log e il PDF riportano la sorgente; il
sensore non è mai presentato come strumento tarato. Architettura a
modelli (`lib/core/sensors/`): nuovi modelli futuri = una classe + una
riga nel registry. Funzione opzionale: l'app resta pienamente utilizzabile
senza sensori e senza permessi Bluetooth.

## Lettura documenti (OCR) e spazio allegati

"Scansiona documento" in Merce in arrivo legge fornitore, numero, data e
righe (lotto, scadenza, quantità) da foto o PDF di DDT/fatture con
**ML Kit, interamente sul telefono** (nessuna rete): schermata di verifica
con campi incerti evidenziati, coda di registrazioni precompilate, documento
allegato a tutte le merci create senza duplicare il file (SHA-256). Dettagli
e limiti in [`docs/ocr.md`](docs/ocr.md).

Gli allegati (foto ~1600 px o PDF) vivono nella cartella privata
dell'app: la schermata **Altro → Spazio e allegati** mostra spazio usato,
file più grandi e allegati non ancora al sicuro su Google Drive, con
profili di qualità foto, "Libera spazio" (solo file già verificati sul
cloud) e controllo integrità. Il backup del database non include le foto:
c'è l'opzione "Backup completo con allegati" in streaming. Dettagli in
[`docs/allegati.md`](docs/allegati.md).

## Prima della pubblicazione

Vedi "Configurazione manuale" sopra: progetto Google Cloud, App Store
Connect, firma, `applicationId`, pagina privacy. Compilare sempre con
`--dart-define=BH_ANCHOR_SECRET=...`.
