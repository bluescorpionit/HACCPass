# Ripristino dei dati — HACCPass

Come recuperare dati e foto da un backup, su un telefono nuovo, dopo una
reinstallazione o dopo un cambio piattaforma (Android ↔ iOS), e come si
comporta il backup automatico. Riferimento: Prompt 12.

## 1. Casi d'uso

| Caso | Percorso | Note |
|---|---|---|
| Telefono nuovo (Android→Android) | Primo avvio → "Ho già usato HACCPass" → Google Drive | I percorsi delle foto vengono riallineati automaticamente (§5) |
| Reinstallazione sullo stesso telefono | Come sopra, oppure Altro → Documenti e backup → Ripristina da Google Drive | Su iOS il percorso del contenitore cambia a ogni installazione: il riallineamento lo corregge |
| Cambio piattaforma (Android↔iOS) | Come sopra | I separatori `/` e `\` vengono normalizzati; il backup completo porta le foto con sé |
| Backup di soli dati, foto su Drive | Ripristino + schermata "Recupero foto" | Le foto si riscaricano da `HACCPass/Foto` per `cloud_id` o per nome file |
| Nessun backup in Drive con lo scope ridotto | Wizard → "Scegli un file…" | Il selettore di sistema vede anche i documenti di Drive (Android) e iCloud (iOS) |

## 2. Flusso del primo avvio

1. Al primo avvio con **database vuoto** (nessuna azienda configurata,
   nessuna registrazione, nessun allegato) e onboarding non completato
   compare `FirstRunChoiceScreen`:
   - **Nuova attività** (o il link "Più tardi") → configurazione guidata;
   - **Ho già usato HACCPass: ripristina i miei dati** → wizard di
     ripristino.
2. La scelta viene ricordata in `first_run_choice_done`: la schermata non
   si mostra più (rimane accessibile il wizard da Altro → Documenti e
   backup → Ripristina da Google Drive).
3. Flusso Google Drive nel wizard:
   - spiegazione dell'accesso ridotto e pulsante **Collega Google Drive**
     (mai in automatico, solo dal pulsante);
   - elenco della cartella `Backup` con tipo (Solo dati / Completo con
     foto, dal nome `HACCPass_backup_completo_*` e dal manifest), data,
     dimensione e badge "Cifrato" (primi 4 byte `BHB1`/`BHB2` letti con
     una richiesta Range, senza scaricare il file);
   - il più recente è preselezionato;
   - **controllo dello spazio** prima di scaricare: servono almeno
     2,5 × la dimensione del file (download + estrazione + backup di
     sicurezza). Se manca, un messaggio dice quanto serve;
   - download con avanzamento (byte scaricati / totali) e annullamento;
   - se il backup è cifrato: password (fino a 3 tentativi, poi esce
     senza modifiche);
   - **riepilogo** (data, versione app e schema, numero allegati) e
     conferma: "I dati attuali dell'app (vuoti) verranno sostituiti";
   - ripristino con avanzamento per fase; su un'app con dati già
     presenti il backup di sicurezza è sempre creato prima.
4. Dopo il ripristino: se il database ripristinato ha `onboarding_done =
   '1'` si apre direttamente l'app; altrimenti la configurazione guidata
   riprende dal passo salvato. Il cloud resta quello collegato **adesso**
   (`cloud_provider = 'gdrive'`, `cloud_account` = email attuale,
   `cloud_needs_reconnect = ''`).

## 3. Backup "solo dati" e backup "completo"

| | Solo dati (`.bhb`) | Completo (`HACCPass_backup_completo_*.bhb`) |
|---|---|---|
| Contenuto | database + manifest | database + manifest + cartella `attachments` (foto e documenti) |
| Cifratura | Opzionale (password, AES-256-GCM) | **Non cifrabile** (scritto in streaming) |
| Recupero foto | Successivo, da `HACCPass/Foto` sul Drive | Foto ripristinate dal file stesso |
| Lettura | Intero in memoria SOLO se cifrato (dimensioni piccole: solo database) | Streaming su file temporanei, nessun picco di RAM |

## 4. Cosa non viene MAI ripristinato

- **Licenza e prova**: `license_kind`, `license_expires_at`,
  `license_customer`, `license_key`, `iap_active`, `iap_verified_at`,
  `trial_started_at` sono letti dal telefono **prima** della
  sostituzione del database e riscritti dopo: un backup non può
  importare (né manomettere) lo stato di licenza. Dal Prompt 13 le
  righe delle vecchie chiavi offline non concedono comunque nulla
  (licenza solo store) e la data della
  prova non torna mai indietro (vince la più antica, regola dell'ancora).
- **Token OAuth** (google_sign_in): vivono nel secure storage di
  sistema, mai nel database né nei backup.
- **Password di cifratura**: mai salvata da nessuna parte.

Un backup manomesso (SQLite nello ZIP modificato con
`license_kind='offline'`, `license_expires_at='9999-12-31'`) dopo il
ripristino lascia il telefono nello stato di prima: prova/sola lettura.
Coperto da test (`restore_service_test.dart`, `license_restore_test.dart`).

## 5. Percorsi e foto dopo il ripristino

- `attachments.local_path`, `thumb_path` e `sync_queue.local_path` sono
  ricostruiti dalla parte relativa (quello che segue l'ultima cartella
  `attachments`) sulla radice attuale: funziona tra telefoni, tra
  Android e iOS e dopo reinstallazione. Se un percorso non contiene la
  cartella attesa la riga resta com'è e viene contata come "da
  recuperare".
- `sync_queue.attachment_id` (schema v7) lega la coda all'allegato:
  dopo ogni upload vengono scritti `cloud_id` e `synced_at`, quindi si
  sa sempre quale file remoto riscaricare.
- Schermata **Recupero foto** (dopo un ripristino di soli dati, o da
  Altro → Spazio e allegati): *Scarica tutte ora* (avanzamento,
  annullabile, riprendibile), *Scarica quando servono* (il segnaposto
  "Scarica" compare toccando l'allegato) e *Più tardi*. Le miniature si
  rigenerano dall'originale; le foto già presenti non si riscaricano.
  Con rete assente nessun errore: in "Spazio e allegati" resta il
  conteggio "N foto non ancora scaricate".

## 6. Backup automatico e conservazione

- Una volta ogni 24 ore, alla prima apertura utile (avvio o ritorno in
  primo piano), solo con cloud collegato.
- **Mai** con database vuoto o prima della scelta del primo avvio: un
  backup vuoto non può diventare "il più recente". Se il Drive contiene
  già backup e il telefono è vuoto, l'app invita a ripristinare.
- Ordinamento in cloud: timestamp nel nome del file (che coincide con il
  `createdAt` del manifest, scritti insieme alla creazione); se il nome
  non è leggibile si usa `modifiedTime`. Il riepilogo prima del
  ripristino mostra i valori precisi letti dal manifest.
- Conservazione: ultimi **14 backup per tipo** (solo dati e completi
  separati). Le copie più vecchie vengono eliminate solo dopo aver
  verificato che il file appena caricato abbia la stessa dimensione del
  locale, e solo file con prefisso `HACCPass_backup_`: mai file estranei.
  Un errore di eliminazione è un avviso non bloccante.

## 7. Cifratura

- **BHB2** (attuale): salt 16 byte da `Random.secure()`, nonce
  AES-GCM casuale, iterazioni PBKDF2-SHA256 scritte nell'intestazione
  (default 600.000).
- **BHB1** (storico): 120.000 iterazioni, salt nel file. Ancora leggibile
  per compatibilità; non più generato.
- Il backup completo con foto non è cifrabile (dichiarato nelle
  schermate di backup e di ripristino).

## 8. Limiti dell'accesso `drive.file` e fallback

Con lo scope ridotto `drive.file` l'app vede **solo i file che ha creato
lei** nella cartella `HACCPass` del Drive dell'utente: nessun altro file,
nessuna lettura generale del Drive. Conseguenza: se la cartella `Backup`
risulta vuota (account diverso, backup creato da un'altra installazione
non visibile), il wizard propone **Scegli un file…**: il selettore di
sistema (FilePicker) su Android apre anche i documenti di Drive e su iOS
l'app File con iCloud Drive.

## 9. Risoluzione problemi

| Problema | Cosa fare |
|---|---|
| "Spazio insufficiente" | Servono ≥ 2,5 × la dimensione del backup (file + estrazione + backup di sicurezza): libera spazio e riprova |
| "Password errata" (3 volte) | Il ripristino si interrompe senza modifiche: la password non è recuperabile |
| "Il backup è stato creato con una versione più recente dell'app" | Aggiorna HACCPass prima di ripristinare (controllo su `schemaVersion`) |
| Nessun backup trovato | Verifica l'account Google collegato; oppure usa "Scegli un file…" (selettore di sistema) |
| Foto non ancora scaricate | Altro → Spazio e allegati → "Recupera foto", oppure tocca la foto e "Scarica" |
| "Il database nel backup non è integro" | File danneggiato o scaricato male: riprova il download; i dati attuali non sono stati toccati |
| Ripristino interrotto a metà | Il backup di sicurezza viene riapplicato automaticamente: l'app resta nello stato precedente |

## 10. Prova manuale (da eseguire e annotare)

- [ ] **Android**: creare backup completo e backup automatico con foto →
      disinstallare → reinstallare → ripristinare da Drive (primo avvio)
      → verificare registri, foto e "Recupero foto".
- [ ] **Cambio telefono**: ripristino da Drive su un secondo telefono
      con lo stesso account; verificare riallineamento percorsi e
      recupero foto per nome in assenza di `cloud_id`.
- [ ] **Scope `drive.file` dopo reinstallazione**: verificare che i file
      in `HACCPass/Backup` e `HACCPass/Foto` restino visibili all'app
      reinstallata (debug), con la build firmata **release** (stesso
      progetto Google Cloud, stesso SHA-1/Package o client id iOS) e su
      iOS. Se i file NON fossero visibili (comportamento possibile con
      `drive.file` quando cambia la firma/l'origine dell'app), usare il
      fallback del selettore di sistema documentato in §8: è già parte
      del wizard ("Scegli un file…").

## 11. Note tecniche

- Ripristino: `RestoreService.restoreFromFile` (lettura streaming →
  `PRAGMA integrity_check` → backup di sicurezza → sostituzione DB →
  sanificazione licenza → riallineamento percorsi → allegati →
  `revision++`); se un passo fallisce dopo la sostituzione, il backup di
  sicurezza viene riapplicato automaticamente.
- Cartelle temporanee `bh_download` e `bh_restore` sempre eliminate in
  `finally`/`dispose`.
- Spazio libero: `df` su Android/Linux, PowerShell su Windows, non
  determinabile su iOS (si gestisce l'errore di scrittura con pulizia
  dei temporanei).
- Schema database: v7 (`sync_queue.attachment_id`); il manifest del
  backup riporta la versione reale.
