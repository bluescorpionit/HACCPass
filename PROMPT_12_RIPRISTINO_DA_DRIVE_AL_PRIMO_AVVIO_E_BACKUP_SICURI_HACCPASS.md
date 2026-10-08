# PROMPT 12 — Ripristino da Google Drive al primo avvio, backup sicuri e correzioni dal controllo — HACCPass

Progetto: `C:\DEV\HACCPass` (o `D:\DEV\App\HACCPass`, stessa base di codice). Prima di modificare leggi lo stato attuale: `lib/main.dart` (`AppServices.load`, `_restoreCloudSession`, `_RootState`, `_maybeDailyBackup`), `lib/services/backup_service.dart`, `lib/services/cloud/{cloud_storage,google_drive_provider,drive_auth_gateway}.dart`, `lib/services/sync_service.dart`, `lib/services/attachment_service.dart`, `lib/services/license_service.dart`, `lib/core/license/{trial_anchor,license_codec}.dart`, `lib/screens/cloud_backup_screen.dart`, `lib/screens/onboarding/{onboarding_screen,onboarding_steps}.dart` (CloudStep), `lib/services/onboarding/onboarding_controller.dart`, `lib/core/database/app_database.dart` (tabelle `attachments`, `sync_queue`, `settings`), `lib/repositories/haccp_repository.dart` (`updateAttachmentSync`, `getSyncQueue`, `isOnboardingDone`). Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`. Non committare segreti.

Obiettivo principale: **al primo avvio (app nuova, database vuoto) il cliente può collegare Google Drive e ripristinare i propri dati e le foto da un backup precedente**, anche su un telefono diverso. Lo stesso percorso è riusabile da Impostazioni → Documenti e backup. In più, correzioni emerse dal controllo del codice (sotto, parti B–H).

## Problemi verificati nel codice (da correggere)

1. **Il backup automatico giornaliero non parte mai.** `_maybeDailyBackup()` viene chiamato solo da `onFinished` del wizard (`main.dart`, ~riga 414). `_bootstrap`/`_onAppResumed` non lo chiamano.
2. **Un backup può portare con sé la licenza.** `LicenseService._loadState` si fida di `license_kind`, `license_expires_at`, `license_customer` (e `iap_active`) letti dalle impostazioni del database. Un backup `.bhb` è uno ZIP con un SQLite non cifrato: modificando quelle righe e ripristinando si ottiene una licenza gratis. Il ripristino da Drive renderebbe l'attacco banale. (Nota: il Prompt 13 elimina la chiave offline e rende lo stato di licenza dipendente solo dallo store; qui basta che il ripristino non importi mai nessuno stato di licenza. Se il Prompt 13 è già applicato, la rivalidazione di `license_key` non serve più.)
3. **Il ripristino non gestisce gli allegati.** `BackupService.restoreAttachments` non è chiamato da nessuna schermata; `readBackup` legge l'intero file in RAM (`readAsBytes` + `ZipDecoder().decodeBytes`), quindi un backup completo con molte foto può far finire la memoria.
4. **Percorsi assoluti.** `attachments.local_path`, `thumb_path` e `sync_queue.local_path` sono assoluti: dopo un ripristino su un telefono nuovo (o su iOS dopo reinstallazione, quando il percorso del contenitore cambia) puntano a file inesistenti.
5. **`cloud_id` e `synced_at` degli allegati non vengono mai scritti** (`updateAttachmentSync` non è chiamato): `SyncService.processQueue` carica il file in `Foto` ma non registra quale file remoto corrisponde a quale allegato. Senza questo legame non si sa cosa riscaricare dopo un ripristino.
6. **Un backup vuoto potrebbe sovrascrivere i dati.** Su un'app nuova con Drive collegato e backup automatico attivo, il primo backup (database vuoto) sarebbe il più recente nella cartella `Backup`.
7. **Conservazione non implementata.** `uploadBackup` calcola gli "eccedenti" ma non li elimina (commento "l'eliminazione remota non è nell'interfaccia"): la cartella `Backup` cresce senza limite.
8. **Cifratura:** in `_encrypt` il salt è `DateTime.now().microsecondsSinceEpoch & 0xFF` ripetuto 16 volte (quasi costante, non casuale); PBKDF2 a 120.000 iterazioni è basso per SHA-256.
9. **Wizard, passo 9 (Documenti e backup):** scegliere "Google Drive" salva solo `cloud_provider = 'gdrive'` senza collegare; al primo avvio successivo `_restoreCloudSession` segna "da ricollegare". Il campo "Password dei backup" non viene usato da nessuno (`backupPassword` non è salvata né usata: la password si chiede al momento del backup).

## A. Primo avvio: scelta "Nuova attività" o "Ripristina"

- Mostra la schermata `FirstRunChoiceScreen` **solo** se: onboarding non completato, database "vuoto" (nessuna azienda configurata, nessuna registrazione, nessun allegato) e impostazione `first_run_choice_done != '1'`. Due scelte grandi: **"Nuova attività"** (prosegue col wizard) e **"Ho già usato HACCPass: ripristina i miei dati"**. Un link discreto "Più tardi" equivale a "Nuova attività". Imposta `first_run_choice_done = '1'` all'uscita da questa schermata.
- "Ripristina i miei dati" apre `RestoreWizardScreen` con tre vie: **Google Drive** (principale), **File dal telefono** (riuso di `FilePicker`) e, su iOS, **File e iCloud Drive** (selettore file di sistema).
- Flusso Google Drive:
  1. Spiegazione breve: "Si apre l'accesso Google. L'app vede solo i file creati da HACCPass nella cartella HACCPass del tuo Drive." Pulsante **Collega Google Drive** → `GoogleDriveProvider.connect(interactive: true)` (solo da pulsante, mai in automatico). Errori tradotti con `humanError`.
  2. Dopo il collegamento elenca la cartella `Backup` ordinando per data di creazione **del manifest** quando disponibile (altrimenti per `modifiedTime`). Per ogni voce mostra: tipo (**Solo dati** oppure **Completo con foto**, dedotto da nome `HACCPass_backup_completo_*` e dal manifest `attachments`), data, dimensione (`CloudFile.size`), e se è **cifrato** (primi 4 byte `BHB1`/`BHB2` prima dello ZIP). Preseleziona il più recente.
  3. Se la cartella è vuota o non visibile: schermata esplicativa "Nessun backup trovato con questo account. Con l'accesso ridotto di HACCPass (drive.file) vengono mostrati solo i backup creati da HACCPass. Puoi scegliere un file dal telefono o dal tuo Drive con il selettore di sistema" e pulsante **Scegli un file…** (`FilePicker`, che su Android apre anche i documenti di Drive).
  4. Scarica con progresso (byte scaricati / totali) e possibilità di annullare; controllo dello spazio libero **prima** (richiesto ≥ 2,5 × dimensione del file; se manca, messaggio chiaro con quanto spazio servirebbe).
  5. Se cifrato chiede la password (fino a 3 tentativi, poi esce senza modifiche).
  6. Mostra un **riepilogo** prima di sostituire i dati: data del backup, versione app e schema, numero di allegati, "I dati attuali dell'app (vuoti) verranno sostituiti". Su un'app nuova il backup di sicurezza è breve; se l'app contiene già dati, resta obbligatorio il backup di sicurezza esistente di `restoreBackup`.
  7. Ripristina database e (se completo) allegati con progresso per fase. Poi vedi §B/§C/§D.
- **Dopo il ripristino**: se il database ripristinato ha `onboarding_done = '1'` apri direttamente la shell; altrimenti prosegui il wizard dal passo salvato. Mantieni `cloud_provider = 'gdrive'` e `cloud_account` con l'email collegata adesso (non quella del vecchio telefono), `cloud_needs_reconnect = ''`.
- Disponibile anche in **Altro → Documenti e backup → "Ripristina da Google Drive"**, con la stessa schermata (le voci "Ripristina" per singola riga già presenti restano).

## B. Ripristino robusto (BackupService)

1. **Streaming:** per i backup completi non usare `readAsBytes`. Leggi manifest e database estraendoli dal file ZIP con `InputFileStream`/`ZipDecoder().decodeStream` scrivendo il database su file temporaneo (non in RAM); gli allegati continuano a essere estratti un file alla volta con `restoreAttachments`. Mantieni il percorso in memoria solo per i backup cifrati di solo database (dimensioni piccole) e dichiara nel codice il limite.
2. Nuovo `RestoreService` (o metodo `restoreFromFile(path, {password, includeAttachments, onProgress, shouldCancel})`) che orchestra: lettura → verifica integrità (`PRAGMA integrity_check` già presente) → backup di sicurezza → sostituzione DB → **sanificazione impostazioni (§C)** → **riallineamento percorsi (§D)** → ripristino allegati → riapertura DB → `repository.revision.value++`. Se un passo fallisce dopo la sostituzione del DB, ripristina automaticamente il backup di sicurezza e mostra l'errore.
3. Collega `restoreAttachments` a questo flusso e alla voce "Ripristina" di `cloud_backup_screen.dart` (oggi chiama solo `restoreBackup`).
4. **Spazio:** controlla lo spazio libero prima di scaricare ed estrarre (usa `path_provider`/un controllo equivalente; se non disponibile sulla piattaforma, gestisci l'errore di scrittura con messaggio chiaro e pulizia dei file temporanei).
5. Cartelle temporanee (`bh_download`, `bh_restore`) sempre eliminate in `finally`.

## C. Sicurezza della licenza nel ripristino (importante)

1. **Prima** di sostituire il DB leggi e conserva in memoria le impostazioni locali di licenza: `license_kind`, `license_expires_at`, `license_customer`, `license_key`, `iap_active`, `iap_verified_at`, `trial_started_at`. **Dopo** la sostituzione riscrivile (o cancellale se vuote): **il ripristino non importa mai lo stato di licenza dal backup**. Per `trial_started_at` vale la regola esistente di `TrialAnchor`: la data effettiva è la più antica tra ancora e database; non portarla in avanti.
2. In `LicenseService._loadState`: `license_kind = 'offline'` e `license_expires_at` letti dal database **non vanno creduti** (la chiave offline sarà rimossa dal Prompt 13; fino ad allora trattali come prova). Per `iap_active`: considera valido solo se verificato dallo store al caricamento (la tolleranza offline di 7 giorni resta, ma `iap_verified_at` non è creduto se è nel futuro rispetto all'orologio o oltre la tolleranza).
3. Test: backup manomesso con `license_kind='offline'`, `license_expires_at='9999-12-31'` → dopo il ripristino lo stato è prova/sola lettura; backup di un altro telefono con abbonamento attivo → lo stato locale resta quello del telefono; `iap_verified_at` nel futuro → ignorata.
4. Aggiungi anche un test che il backup NON includa mai segreti: nessun token OAuth, nessuna password.

## D. Allegati dopo il ripristino

1. **Riallineamento dei percorsi:** dopo la sostituzione del DB converti `attachments.local_path`, `attachments.thumb_path` e `sync_queue.local_path` ricostruendoli dalla parte relativa (`attachments/AAAA/MM/nomefile`, cioè ciò che segue l'ultima occorrenza della cartella `attachments`) rispetto alla cartella allegati **attuale** (`AttachmentService`/`BackupService._attachmentsRootPath`). Funziona tra telefoni, tra Android e iOS e dopo reinstallazione. Se il percorso non contiene la cartella attesa, lasciare la riga com'è e segnarla come "da recuperare".
2. **Legame con Drive (fix punto 5):** aggiungi alla tabella `sync_queue` la colonna `attachment_id` (migrazione incrementale, versione schema successiva, `appDatabaseVersion` aggiornata, test di migrazione; aggiorna il manifest del backup con la versione reale). `AttachmentService._register` accoda con quell'`attachment_id`; `SyncService.processQueue`, dopo `upload`, chiama `repository.updateAttachmentSync(id, cloudId: <id remoto>, syncedAt: now)` per le voci `kind = 'attachment'`.
3. **Recupero foto dopo il ripristino:** `AttachmentRecoveryService` elenca gli allegati il cui file locale manca. Per ognuno: se ha `cloud_id`, scarica da Drive; altrimenti prova per **nome file** nella cartella `Foto` (i nomi sono unici, `_uniqueName`) e, se trovato, scrive `cloud_id`/`synced_at`. Mostra una schermata "Recupero foto" con tre opzioni: **Scarica tutte ora** (progresso, annullabile, riprendibile), **Scarica quando servono** (le miniature e le foto mancanti mostrano un segnaposto con "Scarica" e scaricano al tocco) e **Più tardi**. Le miniature (`thumb_path`) si rigenerano dall'originale quando scaricato (`AttachmentService._makeThumbnail`); le foto già verificate come presenti non si riscaricano. Con la rete assente non va in errore: mostra "Foto non ancora scaricate" in `attachment_storage_screen.dart`.
4. Gli allegati di un backup **completo** vengono ripristinati dal file; il recupero da Drive serve per il backup di solo database.

## E. Backup automatico: farlo partire davvero e senza rischi

1. Richiama `_maybeDailyBackup()` da `_bootstrap` (dopo `_restoreCloudSession`) e da `_onAppResumed`, non solo a fine wizard. Mantieni la regola "una volta ogni 24 ore" e il flag `_dailyBackupDone` per esecuzione.
2. **Mai prima del ripristino:** non eseguire backup automatici se `onboarding_done != '1'` o se il database è "vuoto" (stessa definizione di §A) o se `first_run_choice_done != '1'`. Se il database è vuoto e Drive contiene già backup, non sovrascrivere niente: mostra l'invito a ripristinare.
3. Il nome dei file include timestamp ma, in cloud, ordina e mostra in base a `createdAt` nel manifest quando leggibile; per un backup cifrato (manifest non leggibile senza password) usa `modifiedTime`.
4. **Conservazione:** aggiungi `Future<void> delete(String id)` a `CloudStorageProvider` (default `UnsupportedError`; `LocalFilesProvider` no-op) e implementala in `GoogleDriveProvider` (`files.delete`, ammesso con `drive.file` per i file creati dall'app). In `uploadBackup` dopo il caricamento conserva gli ultimi `keepCount` backup **per tipo** (solo dati e completi separati) ed elimina i più vecchi solo dopo aver verificato che l'upload sia riuscito; mai eliminare file che non rispettano il prefisso `HACCPass_backup_`. Errore di eliminazione = avviso non bloccante.
5. Verifica dell'integrità dopo il caricamento: controlla che il file remoto abbia la stessa dimensione del locale prima di cancellare i vecchi.

## F. Cifratura più solida (compatibile con i backup esistenti)

- Nuovo formato `BHB2`: salt di 16 byte da `Random.secure()`, nonce da `AesGcm.newNonce()`, iterazioni PBKDF2 scritte nell'intestazione (default 600.000, SHA-256). `readBackup` legge sia `BHB1` (120.000 iterazioni, salt nel file) sia `BHB2`. Test: round-trip BHB2, lettura di un file BHB1 generato dal codice attuale, password errata, file troncato.
- Backup completi: resta non cifrabile; dichiaralo sia nella schermata di backup sia in quella di ripristino.

## G. Wizard, passo 9 (cloud)

- Scegliendo **Google Drive** compare il pulsante **"Collega ora"** (interactive) con stato "Collegato: email". Se l'utente va avanti senza collegare, `saveCloudChoice` imposta `cloud_provider = 'gdrive'` **solo se** collegato, altrimenti `'local'` e mostra una riga "Puoi collegare Google Drive in Altro → Documenti e backup".
- Rimuovi il campo "Password dei backup": mostra invece "Ti chiederemo la password a ogni backup manuale: il backup automatico non può chiederla e non è cifrato".
- Mantieni lo switch "Cifra i backup con una password" ma spiega che vale solo per i backup manuali del solo database.

## H. Documentazione e test

- `docs/ripristino.md`: casi d'uso (telefono nuovo, reinstallazione, cambio piattaforma Android↔iOS), flusso del primo avvio, differenze tra backup solo dati e completo, cosa non viene mai ripristinato (licenza, token, impostazioni locali sensibili), come recuperare le foto, limiti dell'accesso `drive.file` e fallback con selettore di sistema, risoluzione problemi (spazio, password, schema più recente).
- Test unitari: sanificazione impostazioni (nessuno stato di licenza importato), riallineamento percorsi (Android→Android, Android→iOS, percorso senza `attachments`), scheduler del backup (parte all'avvio dopo 24 h, non parte con DB vuoto, non parte prima della scelta del primo avvio), retention (14 per tipo, mai file estranei, nessuna cancellazione se l'upload non è verificato), streaming del ripristino con file grande finto, migrazione schema con `attachment_id`, cifratura BHB1/BHB2. Test widget: `FirstRunChoiceScreen` (visibile solo con DB vuoto), `RestoreWizardScreen` con provider e servizio di backup finti (lista, cifrato, spazio insufficiente, annulla, nessun backup trovato → fallback file).
- Prova manuale da riportare in `docs/ripristino.md`: (1) Android: crea backup completo e backup automatico con foto, disinstalla, reinstalla, ripristina da Drive; (2) cambio telefono; (3) **verifica reale che dopo la reinstallazione i file in `HACCPass/Backup` e `HACCPass/Foto` siano ancora visibili all'app con lo scope `drive.file`**, e se lo sono anche con la build firmata release rispetto alla debug e su iOS (stesso progetto Google Cloud). Se non lo fossero, documenta e usa il fallback del selettore di sistema.

## Criteri di accettazione

1. Al primo avvio con database vuoto compare la scelta "Nuova attività / Ripristina"; da "Ripristina" con Google Drive si elencano i backup, si scarica con progresso, si ripristina e si arriva all'app con i dati; le foto si recuperano come scelto.
2. Il ripristino non importa mai la licenza dal backup; un backup manomesso non sblocca nulla (stato di licenza solo da store e ancora della prova).
3. Nessuna foto o miniatura rotta per percorsi assoluti dopo il ripristino; `cloud_id`/`synced_at` scritti a ogni caricamento.
4. Backup automatico quotidiano realmente attivo, mai con database vuoto, con retention a 14 per tipo.
5. File grandi ripristinati senza picchi di memoria; spazio verificato prima.
6. Nuova cifratura BHB2 con salt casuale; lettura compatibile con BHB1.
7. Wizard: Drive si collega davvero dal passo 9 o non viene salvato come provider.
8. `docs/ripristino.md` completo; `flutter analyze` e `flutter test` verdi.
