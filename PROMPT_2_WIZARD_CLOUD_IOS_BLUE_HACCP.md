# PROMPT 2 PER AI DI SVILUPPO: Wizard di prima configurazione, documenti e backup su cloud, versione iOS di "Blue HACCP"

Questo prompt è il **seguito** di `PROMPT_REDESIGN_BLUE_HACCP.md` (redesign, registri HACCP, PDF, licenza). Se quel lavoro non è ancora stato fatto, eseguilo prima o insieme: qui si riusano il design system, il database v2, i servizi PDF e la `LicenseService` descritti là. Non duplicare né rifare ciò che esiste.

Fornisci all'AI di sviluppo la cartella del progetto `HaccpPro`, i due manuali HACCP in PDF e questo documento.

---

## 1. RUOLO E OBIETTIVO

Sei un senior Flutter developer con esperienza di onboarding, sincronizzazione file e pubblicazione su App Store e Google Play. Devi aggiungere tre cose:

1. **Wizard di prima configurazione**: al primo avvio il cliente inserisce i dati dell'attività, descrive cosa possiede (frigoriferi, congelatori, locali, personale) e ottiene un'app già pronta all'uso, con piano pulizie, attrezzature e promemoria precompilati.
2. **Documenti e foto, con backup su cloud**: allegare foto e documenti ai registri, collegare facoltativamente un cloud personale del cliente (Google Drive; su iPhone anche i servizi nativi Apple) per il salvataggio automatico di backup, PDF e foto.
3. **Versione iOS**: tutto deve funzionare e passare la revisione App Store, con le differenze di piattaforma indicate nella sezione 7.

Obiettivo di prodotto: dal download all'app **usabile in meno di 5 minuti**, senza mai obbligare a creare un account Blue Scorpion. Tutto in **italiano**.

---

## 2. PRINCIPI NON NEGOZIABILI

- **Local-first**: l'app funziona completamente senza cloud e senza account. Il cloud è un'opzione.
- **I dati restano del cliente**: i file vanno nel **suo** Google Drive o nel **suo** spazio Apple, mai su server di Blue Scorpion. Nessuna telemetria, nessuna analisi, nessun SDK pubblicitario.
- **Consenso esplicito** prima di ogni permesso (fotocamera, foto, contatti, notifiche, cloud). Chiedi il permesso **nel momento in cui serve**, spiegandone il motivo in una riga.
- Il wizard è **saltabile, riprendibile e rieseguibile**: ogni passo salva subito, si può uscire e rientrare dove si era, e tutto è modificabile dopo da "Altro > Configurazione guidata".
- Il wizard **non blocca mai la prova gratuita**: i 14 giorni partono al primo avvio come da prompt 1.
- Applicare i dati del wizard deve essere **idempotente**: rieseguirlo non duplica attrezzature, pulizie o prodotti.
- Rispetta i criteri di leggibilità del prompt 1 (contrasto AA, target 48 dp, nessun testo tagliato, tema chiaro e scuro).

---

## 3. WIZARD DI PRIMA CONFIGURAZIONE

### 3.1 Comportamento generale

- Parte al primo avvio se `onboarding_done != 1`. Schermata a tutto schermo, **barra di avanzamento** con nome del passo ("Passo 3 di 10 · Attrezzature").
- Ogni passo ha: titolo chiaro, una frase di spiegazione, contenuto, pulsante grande **Avanti**, **Indietro** e **Salta questo passo** (testo ben visibile, non nascosto).
- Stato persistito in `settings` (`onboarding_step`, `onboarding_done`, `onboarding_business_types`) dopo ogni passo. Se l'app viene chiusa, alla riapertura propone "Riprendi la configurazione" o "Salta".
- Su tablet e desktop: layout a due colonne (passi a sinistra, contenuto a destra).
- Transizioni leggere, nessuna animazione che rallenti. Pulsante di uscita sempre disponibile.
- Nella dashboard, finché la configurazione è incompleta, una card **"Completa la configurazione: 70%"** riporta al primo passo mancante. Calcola la percentuale da dati reali (anagrafica compilata, almeno 1 attrezzatura, piano pulizie, responsabile, cloud scelto, ecc.).

### 3.2 Passi

**Passo 0 · Benvenuto e privacy.** Spiega in 3 righe cosa fa l'app. Mostra e fai accettare **Termini di servizio e Informativa privacy** (link a pagine web esterne configurabili; salva versione e data di accettazione). Avviso chiaro: l'app aiuta a tenere i registri ma la responsabilità dell'autocontrollo resta dell'operatore.

**Passo 1 · Tipo di attività.** Scelta multipla con grandi card: bar/caffetteria, ristorante/trattoria, pizzeria, pub/paninoteca, gastronomia/rosticceria, pasticceria/panificio, macelleria/salumeria, pescheria, caseificio/laboratorio, mensa/catering, altro. La scelta pilota i modelli dei passi successivi (sezione 3.3).

**Passo 2 · Dati dell'azienda.** Ragione sociale, indirizzo, CAP, città, provincia, P.IVA (**validazione** formale: 11 cifre con controllo di checksum), codice fiscale, ATECO (suggerito in base al tipo di attività, modificabile), telefono, email, PEC, **numero di notifica sanitaria/registrazione**, **logo** (scatta o scegli dalla galleria, ritaglio quadrato, usato su PDF ed etichette). Scrittura nel profilo azienda già previsto dal prompt 1.

**Passo 3 · Responsabili e personale.** Titolare e **responsabile HACCP**, **sostituto**, aggiunta rapida dei collaboratori (nome, mansione). Per ciascuno: data e scadenza dell'attestato di formazione alimentarista con **foto dell'attestato** come allegato (sezione 4). Elenco degli **operatori** selezionabili su ogni registrazione (chip), con operatore predefinito.

**Passo 4 · Locali e attrezzature.** Domanda guida: *"Cosa hai nella tua attività?"* Card con **contatore +/-** per: frigoriferi, congelatori, celle frigorifere, banchi frigo/vetrine refrigerate, abbattitori, mantenimento a caldo (bagnomaria, scaldavivande), lavastoviglie. Per ogni elemento creato:
- nome automatico ("Frigo 1", "Congelatore 2") rinominabile al volo, posizione (cucina, sala, magazzino...);
- **limiti di temperatura precompilati** dal preset (vedi prompt 1, sezione 5.2) e modificabili, con nota "valori di riferimento";
- **foto** facoltativa dell'attrezzatura;
- funzione facoltativa **QR per attrezzatura**: genera e stampa/condividi un'etichetta con QR; scansionandolo con l'app si apre direttamente la registrazione della temperatura di quell'attrezzatura (package `mobile_scanner`, richiede permesso fotocamera chiesto al momento).
Alla fine del passo mostra l'elenco creato con possibilità di eliminare o correggere.

**Passo 5 · Piano di pulizia.** Proposta automatica in base ai tipi di attività e alle attrezzature scelte (sezione 3.3), con interruttore per ogni voce, frequenza modificabile, prodotto usato e metodo. Il cliente conferma o toglie voci. Frequenze coerenti con prompt 1 (dopo ogni utilizzo, giornaliera, 2 volte al giorno, settimanale, mensile, semestrale, annuale, al bisogno).

**Passo 6 · Disinfestazione e strutture.** Nome e telefono della **ditta di disinfestazione** (facoltativo), cadenza mensile, numero e tipo di postazioni (roditori, striscianti, volanti) con ubicazione. Cadenza consigliata per il controllo strutture (semestrale).

**Passo 7 · Fornitori.** Aggiunta manuale rapida (nome, telefono, prodotti) oppure **importa dai contatti del telefono** (permesso contatti chiesto qui, mai prima). Si può saltare: i fornitori si creano anche al primo ricevimento merce.

**Passo 8 · Prodotti e allergeni.** Elenco di prodotti tipici proposti dal tipo di attività (sezione 3.3), ognuno con allergeni preselezionati **modificabili**. Il cliente spunta quelli che usa e aggiunge i propri. Avviso visibile: "Gli allergeni proposti sono indicativi: verifica sempre ricette ed etichette dei fornitori".

**Passo 9 · Documenti e backup.** Scelta del dove salvare backup, PDF e foto (dettagli in sezione 5): *Solo su questo dispositivo* / *Google Drive* / (su iPhone) *File e iCloud Drive*. Opzione per **cifrare i backup con una password** scelta dal cliente, con avviso che senza password non si recupera nulla. Si può rimandare.

**Passo 10 · Promemoria.** Orari dei promemoria locali: controllo temperature (es. 9:00 e 17:00), chiusura pulizie (es. 22:00), scadenze formazione e verifiche periodiche. Il permesso notifiche si chiede qui. Usa notifiche **locali** (`flutter_local_notifications` + fuso `Europe/Rome`), niente server. Su Android 13+ gestisci `POST_NOTIFICATIONS`, evita gli allarmi esatti se non indispensabili. Se il permesso è negato, mostra come riattivarlo senza insistere.

**Passo 11 · Stampa ed etichette.** Formato etichetta (es. 62x40 mm), stampante scelta dal sistema (AirPrint su iOS, servizio di stampa su Android), pulsante **"Stampa una prova"**.

**Passo 12 · Riepilogo.** Elenco di cosa è stato creato (N attrezzature, N pulizie, N prodotti, N persone) e di cosa resta da fare. Pulsante principale **"Inizia"**. Secondo pulsante **"Genera il Piano di autocontrollo (PDF)"**: documento personalizzato con anagrafica, planimetria testuale dei locali, elenco attrezzature con limiti, piano pulizie, piano infestanti, elenco fornitori e figure responsabili, riferimenti ai manuali e al Reg. CE 852/2004, costruito con il servizio PDF del prompt 1. Segna `onboarding_done = 1`.

### 3.3 Modelli per tipo di attività

Crea `core/constants/business_templates.dart` con una classe `BusinessTemplate` per ogni tipo, contenente: attrezzature suggerite (nome, preset), voci di pulizia (area, titolo, frequenza, prodotto, metodo), prodotti tipici con allergeni, codice ATECO suggerito, postazioni infestanti consigliate, categorie di merce in arrivo più frequenti. Esempi minimi:
- **Bar**: 1 frigo bevande, 1 frigo latticini/farciture (+4), 1 congelatore, vetrina brioche; pulizia macchina caffè e macinadosatore, superfici banco dopo ogni uso, servizi igienici, pavimenti 2 volte al giorno; prodotti: cappuccino (latte), brioche (glutine, uova, latte), panino (glutine, ...), spremuta.
- **Pizzeria**: cella/frigo impasti e ingredienti, congelatore, frigo bibite, forno e piani di lavoro, impastatrice; prodotti: pizza margherita (glutine, latte), ecc.
- **Ristorante**: celle carne/pesce/verdure separate, abbattitore, mantenimento a caldo, lavastoviglie (lavaggio ad alta temperatura), affettatrice.
- **Gastronomia, pasticceria, macelleria, pescheria, caseificio**: stesso schema con le attrezzature e i prodotti specifici.
I dati dei modelli sono **suggerimenti**: segnali in app che l'operatore deve adattarli. Riferisciti ai valori dei manuali allegati per limiti e frequenze. Non copiare testi dei manuali.

### 3.4 Architettura

- `OnboardingController` (`ChangeNotifier`), un widget per passo, `OnboardingScreen` con `PageView` non scorrevole a mano.
- Applicazione dei dati con **transazione SQLite per passo**. Per evitare duplicati aggiungi colonna `source` (`'wizard'`, `'user'`) e `template_key` alle tabelle `equipment`, `cleaning_tasks`, `products`, `pest_stations`, e ricostruisci solo le righe `source='wizard'` non modificate dall'utente.
- Il passo 12 registra una riga di audit (`settings`): data completamento e versione dei modelli applicati.

---

## 4. ALLEGATI: FOTO E DOCUMENTI

Obiettivo: poter associare prove documentali ai registri (DDT, etichette, foto del problema, attestati, schede tecniche).

- Tabella `attachments`: `id`, `entity_type` (`receipt`, `nonconformity`, `staff`, `equipment`, `supplier`, `lot`, `company`), `entity_id`, `kind` (`photo`, `document`), `file_name`, `local_path`, `mime`, `size`, `created_at`, `cloud_id`, `synced_at`, `note`.
- File salvati nella cartella documenti privata dell'app (`path_provider`), sottocartelle `attachments/AAAA/MM/`.
- **Acquisizione**: foto con fotocamera o galleria (`image_picker`), documenti e PDF con il selettore di sistema (`file_picker`). Le foto vengono **compresse** (lato lungo ~1600 px, qualità ~80) prima di salvarle.
- **Importazione dal cloud senza SDK**: il selettore documenti nativo di Android e iOS mostra già Google Drive, iCloud Drive, OneDrive e Dropbox. Usalo per "Importa da un servizio cloud": **non serve alcun accesso OAuth** per importare file esistenti (logo, attestati, schede tecniche, manuali).
- Visualizzatore con zoom, condivisione, eliminazione (con conferma) e nota.
- Dove compaiono: ricevimento merci (foto DDT/etichetta/merce), non conformità (foto del problema), personale (attestato), attrezzature (foto, libretto), fornitori (dichiarazione di autocontrollo, schede tecniche), lotti (foto etichetta).
- Nei PDF: le foto delle NC e dei ricevimenti respinti compaiono in **appendice fotografica** del dossier (miniature con didascalia), con interruttore "includi foto".
- Permessi: su Android 13+ usa il photo picker di sistema (nessun permesso), su iOS fornisci le stringhe in italiano (sezione 7).

---

## 5. CLOUD E BACKUP

### 5.1 Strategia in due livelli

1. **Sempre disponibile, senza SDK**: condivisione e salvataggio nei **File** del telefono tramite foglio di condivisione / dialogo "Salva con nome" (`share_plus`, `file_picker`). Funziona con qualsiasi cloud installato.
2. **Opzionale, automatico**: collegamento a **Google Drive** (Android e iOS) per backup e copia di PDF e foto. Su iPhone, in una seconda fase, **iCloud Drive** nativo (sezione 7.4).

Non costruire sincronizzazione in tempo reale tra più dispositivi nella v1: è un'altra categoria di prodotto. Documenta il limite: **un dispositivo principale per attività**; gli altri possono ripristinare un backup.

### 5.2 Architettura

Interfaccia astratta `CloudStorageProvider`: `isConnected`, `accountLabel`, `connect()`, `disconnect()`, `ensureFolder()`, `upload({path, remoteName, folder})`, `list({folder})`, `download(id, destination)`. Implementazioni: `GoogleDriveProvider`, `LocalFilesProvider` (condivisione/salvataggio di sistema), `ICloudProvider` (fase 2, solo iOS). Un `BackupService` e un `SyncService` che dipendono solo dall'interfaccia.

### 5.3 Google Drive

- Pacchetti: `google_sign_in`, `googleapis` (Drive v3), `extension_google_sign_in_as_googleapis_auth`. **Verifica sulla documentazione aggiornata** le API della versione scelta di `google_sign_in`: sono cambiate tra le versioni maggiori, non andare a memoria.
- **Scope minimo: solo `drive.file`.** È uno scope non sensibile: l'app vede soltanto i file che crea o che l'utente le apre. Non usare scope più ampi (`drive`, `drive.readonly`): sono "ristretti" e richiedono una verifica di sicurezza a pagamento. L'app crea la cartella visibile **"Blue HACCP"** (sottocartelle `Backup`, `Report`, `Foto`) così il cliente ritrova i suoi file da qualsiasi dispositivo.
- Configurazione da documentare nel README, senza mai inserire segreti nel codice: progetto Google Cloud, schermata di consenso OAuth (nome app, logo, link privacy), ID client Android (con **impronte SHA-1 di debug, release e della firma Play App Signing**) e iOS (**reversed client ID** come URL scheme in `Info.plist`, `GIDClientID`).
- Pulsante **"Scollega"** che revoca i token e cancella le credenziali locali. Mostra l'account collegato (email) e lo stato.
- Il collegamento a Google serve **solo come archivio**, non come accesso all'app: nel testo dell'interfaccia usa "Collega Google Drive", mai "Accedi con Google".

### 5.4 Backup del database

- Esporta il DB in un file singolo `BlueHACCP_backup_AAAAMMGG_HHmm.bhb` (copia coerente del DB più un `manifest.json` con versione schema, versione app, data, hash SHA-256).
- **Cifratura facoltativa** con password: AES-256-GCM con chiave derivata (PBKDF2 o Argon2) tramite il package `cryptography`; salt e nonce nel file. Nessuna password salvata.
- Politica: backup automatico **una volta al giorno** alla prima apertura utile con rete Wi-Fi, mantieni gli **ultimi 14** (elimina i più vecchi solo dalla cartella che l'app ha creato). Backup manuale sempre disponibile. Prima di ogni **ripristino** crea automaticamente un backup di sicurezza locale.
- **Ripristino**: elenco dei backup in cloud o selezione file, verifica hash e versione schema, conferma esplicita ("sostituirà i dati attuali"), migrazione se il backup è di una versione precedente, rifiuto con messaggio chiaro se è di una versione più recente dell'app.
- Il backup deve includere le tabelle e il riferimento agli allegati. Gli allegati hanno una propria coda di caricamento.

### 5.5 Caricamento di PDF e foto

- Tabella `sync_queue` (`id`, `kind`, `local_path`, `remote_folder`, `attempts`, `last_error`, `created_at`). Ogni PDF generato e ogni allegato, se il cloud è attivo, entra in coda.
- Esecuzione: all'apertura e al ritorno in primo piano dell'app, e in background su Android con `workmanager`. **Su iOS lo sfondo è limitato**: non promettere caricamenti garantiti in background, mostra "In attesa di caricamento (N file)" e completa quando l'app è aperta.
- Retry con backoff, errori in italiano comprensibile ("Spazio Google Drive esaurito", "Rete non disponibile"), nessun blocco dell'uso dell'app.
- Schermata **"Documenti e backup"** (in Altro): stato collegamento, ultimo backup riuscito, spazio usato dall'app, coda, pulsanti "Esegui backup ora", "Ripristina", "Cambia servizio", "Scollega".

### 5.6 Privacy e GDPR

I dati del personale (nomi, attestati) sono personali: cifratura backup consigliata nel wizard, testo privacy aggiornato, nessun dato inviato a Blue Scorpion, e funzione **"Elimina tutti i dati dell'app"** con doppia conferma.

---

## 6. LICENZA E ONBOARDING

- La prova gratuita parte al primo avvio, prima del wizard.
- Il paywall non compare durante il wizard. Compare a prova scaduta come da prompt 1.
- Un cliente che ripristina un backup su un nuovo telefono **non** deve ottenere una nuova prova: salva lo stato licenza fuori dal solo DB (es. in aggiunta nel backup cifrato) e valida acquisti con `restorePurchases`.

---

## 7. VERSIONE iOS (APPLE)

### 7.1 Premesse pratiche

- Stesso codice Flutter, ma **la compilazione iOS richiede macOS con Xcode**. Chi sviluppa su Windows può usare un servizio cloud (Codemagic, GitHub Actions con runner macOS, Xcode Cloud) o un Mac in affitto. Prepara una **pipeline CI** documentata che produca la build firmata per TestFlight.
- Serve l'iscrizione all'**Apple Developer Program** (quota annuale: verificare l'importo attuale su developer.apple.com). Servono Bundle ID, certificati, profili di provisioning e un record dell'app in App Store Connect.
- Distribuzione di prova con **TestFlight** prima della pubblicazione.

### 7.2 Acquisti e licenza su iOS

- Gli acquisti digitali nell'app passano da **StoreKit** (`in_app_purchase` lo gestisce). Configura in App Store Connect un gruppo di abbonamenti e/o un acquisto "licenza a vita", con testi in italiano e screenshot per la revisione.
- Programma **Small Business Program**: commissione ridotta al **15%** per chi resta sotto 1 milione di USD di ricavi annui. Va richiesta in App Store Connect.
- Il paywall deve mostrare **prezzo, durata, rinnovo automatico e link a Termini e Privacy**, più il pulsante **"Ripristina acquisti"** (obbligatorio).
- **Chiavi di licenza offline: nascondile su iOS.** Sbloccare funzioni con un codice digitato nell'app può violare la guideline 3.1.1 di Apple. Abilita il campo chiave solo su Android e desktop (`Platform.isIOS` falso). Prima di usarlo su iOS verifica con la guideline 3.1.3 (servizi per aziende) o chiedi conferma ad Apple. Alternativa da valutare per i clienti B2B: **distribuzione di "Custom App" tramite Apple Business Manager**.

### 7.3 Accesso e privacy

- Guideline 4.8: se un'app offre un login con servizi di terze parti (Google, Facebook) per l'accesso o la registrazione, deve offrire anche **Accedi con Apple** o un'alternativa equivalente. In Blue HACCP **non esistono account**: Google serve solo come archivio. Mantieni quindi la dicitura "Collega Google Drive", **non** "Accedi con Google", e spiega questa scelta nelle **note per la revisione** di App Store Connect. Se la revisione dovesse contestarla, la soluzione di ripiego è proporre su iOS il salvataggio nei File/iCloud come opzione principale.
- **Etichette di privacy** in App Store Connect: se l'app non invia dati a server dello sviluppatore, dichiarare "Dati non raccolti". Pubblica una **pagina privacy** (URL obbligatorio) e una pagina di supporto.
- Aggiungi `PrivacyInfo.xcprivacy` con i motivi delle API "required reason" usate dall'app (preferenze, timestamp dei file, spazio disco) e verifica che i plugin in uso includano le proprie dichiarazioni.

### 7.4 Cloud su iPhone

1. **v1**: Salvataggio e importazione tramite l'app **File** (iCloud Drive, Google Drive, OneDrive...) con `file_picker` e il foglio di condivisione, più il collegamento a Google Drive di 5.3. Nessun SDK aggiuntivo, funziona subito.
2. **v2 (opzionale)**: **iCloud Drive nativo** con backup automatico in un contenitore dell'app (capability iCloud, ID contenitore dedicato, plugin come `icloud_storage` o codice nativo). Limite: i dati nel contenitore non sono visibili da Android.

### 7.5 Dettagli tecnici iOS da non dimenticare

- **Foglio di condivisione su iPad**: serve un'origine (`sharePositionOrigin` in `share_plus`, `bounds` in `Printing.sharePdf`), altrimenti l'app può bloccarsi. Passa sempre il rettangolo del pulsante che l'ha attivato.
- Stampa con **AirPrint** tramite `printing`: nessuna configurazione extra.
- `Info.plist` con testi **in italiano**, specifici e onesti: `NSCameraUsageDescription` (foto di attrezzature, DDT, problemi, QR), `NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`, `NSContactsUsageDescription` (importazione fornitori), eventuale `NSFaceIDUsageDescription` se aggiungi blocco biometrico. Il permesso notifiche si richiede a runtime.
- URL scheme di Google Sign-In (reversed client ID) e `GIDClientID`.
- `Podfile`: piattaforma minima coerente con i plugin; esegui `pod install` pulito. Icone e launch screen dedicati (sostituisci i placeholder del progetto: oggi le icone iOS sono quelle di default di Flutter).
- Supporto **iPad**: o lo si rifinisce (layout a due colonne già previsto) e si forniscono gli screenshot iPad, o lo si disattiva in Xcode.
- Dynamic Type e modalità scura già coperti dal design system; controlla safe area, gesto "indietro", tastiera sul foglio dei form.
- Categoria suggerita: Business (valuta anche Food & Drink). Descrizione, parole chiave e screenshot in italiano. Dichiarazione chiara che l'app **non sostituisce la consulenza di un tecnico** o gli obblighi di legge.
- Account demo: l'app non richiede login, perciò la revisione può usarla subito. Spiega nelle note come provare l'acquisto in ambiente sandbox.

### 7.6 Android (parità)

Scheda **Sicurezza dei dati** di Google Play coerente con i dati realmente trattati, `POST_NOTIFICATIONS` per Android 13+, `applicationId` definitivo (oggi `com.example.blue_haccp`), firma di release e Play App Signing con le SHA-1 registrate in Google Cloud.

---

## 8. DATABASE v3 (riferimento)

Migrazione v2 → v3 con `onUpgrade`, senza perdita di dati:
- Nuove tabelle: `attachments`, `sync_queue`.
- Nuove colonne: `source` e `template_key` su `equipment`, `cleaning_tasks`, `products`, `pest_stations`; `photo_attachment_id` opzionale dove utile.
- Nuove chiavi `settings`: `onboarding_done`, `onboarding_step`, `onboarding_business_types`, `terms_accepted_at`, `terms_version`, `cloud_provider`, `cloud_account`, `backup_encrypted`, `last_backup_at`, `reminder_*`, `logo_attachment_id`.

---

## 9. DIPENDENZE (versioni da verificare con `flutter pub add`)

`image_picker`, `file_picker`, `flutter_image_compress`, `google_sign_in`, `googleapis`, `extension_google_sign_in_as_googleapis_auth`, `cryptography`, `workmanager`, `flutter_local_notifications` (+ `timezone`, `flutter_timezone`), `mobile_scanner`, `flutter_contacts` (o equivalente). Per ognuna controlla la **documentazione della versione installata** e le istruzioni di configurazione Android (Gradle, manifest) e iOS (Podfile, Info.plist). Evita pacchetti non più mantenuti. Se un pacchetto crea conflitti di build, preferisci un'alternativa a un hack.

---

## 10. ORDINE DI LAVORO

1. Migrazione DB v3, tabella allegati, modelli e repository.
2. Modelli per tipo di attività (`business_templates.dart`) e logica idempotente di applicazione.
3. Wizard: struttura, persistenza, passi 0-3.
4. Wizard: passi 4-8 (attrezzature, pulizie, infestanti, fornitori, prodotti).
5. Allegati: acquisizione, compressione, visualizzatore, inserimento nei PDF.
6. Promemoria locali e passo 10, poi stampa/etichette.
7. `CloudStorageProvider`, backup cifrato, ripristino, Google Drive, coda di caricamento, schermata "Documenti e backup".
8. Piano di autocontrollo PDF (passo 12).
9. Preparazione iOS: Info.plist, privacy manifest, Podfile, icone, CI, StoreKit, paywall conforme, nascondere le chiavi offline.
10. Test, `flutter analyze`, aggiornamento README.

Dopo ogni punto esegui `flutter analyze` e correggi prima di continuare.

---

## 11. CRITERI DI ACCETTAZIONE

- [ ] Al primo avvio compare il wizard; chiudendo l'app a metà e riaprendola si riprende dal passo corretto.
- [ ] Un bar si configura (dati, 3 frigoriferi, pulizie, personale) in meno di 5 minuti e arriva alla dashboard con attività già pianificate.
- [ ] Rieseguire il wizard non crea duplicati e non cancella modifiche fatte a mano.
- [ ] La P.IVA errata viene segnalata; il logo compare nei PDF.
- [ ] Il cliente può allegare una foto a un ricevimento merci e a una NC, e la vede nel PDF.
- [ ] Il collegamento a Google Drive usa solo lo scope `drive.file`; backup, ripristino e scollegamento funzionano.
- [ ] Un backup cifrato non si apre con password errata e si ripristina con quella giusta, anche su un altro telefono.
- [ ] Nessun permesso viene chiesto prima del momento in cui serve.
- [ ] Su iOS: build firmata su TestFlight, condivisione PDF funzionante su iPad, acquisto sandbox riuscito, "Ripristina acquisti" presente, campo chiave offline assente.
- [ ] `flutter analyze` pulito, test verdi, README aggiornato con la guida di configurazione di Google Cloud e App Store Connect.

---

## 12. CONSEGNA

Elenca i file creati o modificati, i comandi di esecuzione e di build per Android e iOS, i passaggi manuali che restano al titolare (progetto Google Cloud, App Store Connect, firma, pagina privacy), e un elenco onesto di ciò che **non** hai potuto verificare (login Google reale, acquisti reali, backup in background su iOS, build su Mac, stampa su stampante fisica).
