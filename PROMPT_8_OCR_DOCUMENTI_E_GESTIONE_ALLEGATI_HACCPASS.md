# PROMPT 8 — Riconoscimento testo dai documenti (ML Kit) + gestione dello spazio degli allegati — HACCPass

Progetto: `D:\DEV\App\HACCPass` (package `haccpass`). Due parti: **A)** lettura automatica dei campi da foto/PDF di DDT e fatture con `google_mlkit_text_recognition` (tutto sul telefono, nessun server); **B)** archiviazione degli allegati che non deve crescere senza controllo. Procedi per fasi; dopo ciascuna `flutter analyze` e `flutter test`. Migrazione DB incrementale dalla versione corrente (non rinominare il file `blue_haccp.db`).

## Stato verificato nel codice (non rifare)
- `lib/services/attachment_service.dart`: acquisizione con `image_picker`, compressione con `flutter_image_compress` (lato lungo 1600 px, qualità 80), salvataggio in `getApplicationDocumentsDirectory()/attachments/AAAA/MM/` (cartella privata dell'app), documenti/PDF copiati **così come sono**, flusso `PendingAttachment` → `attachPending` / `discardPending` (nessun orfano all'annullamento).
- Tabella `attachments`: `entity_type, entity_id, kind, file_name, local_path, mime, size, created_at, cloud_id, synced_at, note`; coda `sync_queue` verso Google Drive (`lib/services/sync_service.dart`, `cloud/`).
- **Lacuna da correggere:** `lib/services/backup_service.dart` salva nel backup SOLO il database (`blue_haccp.db` + `manifest.json`): le foto non sono incluse. Dopo un ripristino su un nuovo telefono i record puntano a file inesistenti. Inoltre `manifest.schemaVersion` è fissato a `3` mentre il DB è più avanti: usa la versione reale.
- Ricevimento merci: `lib/screens/goods/receipts_screen.dart` (`_newReceipt`, campi prodotto, categoria, temperatura, lotto fornitore, DDT, quantità, scadenza, controlli) già con sezione "Documenti e foto".
- `printing` è già nelle dipendenze (serve per rasterizzare i PDF), `mobile_scanner` pure.

---

# PARTE A — OCR dei documenti ricevuti

## A0. Dipendenza e requisiti di piattaforma
- Aggiungi `google_mlkit_text_recognition` (ultima versione compatibile con le altre dipendenze). È on-device; include di base il modello **Latin** (l'italiano è latino: non aggiungere altri script). Requisiti dichiarati dal pacchetto: iOS 15.5+ (64 bit), Android minSdk 21, targetSdk 35.
- iOS: oggi il deployment target del progetto è 13.0 (`ios/Runner.xcodeproj`): portalo a **15.5** (e `platform :ios, '15.5'` nel Podfile quando verrà generato su Mac). Non posso verificare i Pod: annota in `docs/ocr.md` che serve un `pod install` su Mac e un controllo di conflitto con i pod ML Kit già usati da `mobile_scanner`.
- Android: verifica che `minSdk` effettivo sia ≥ 21 e che la dimensione dell'APK/AAB non esploda (documenta l'aumento in `docs/ocr.md`).
- Nessuna chiamata di rete per l'OCR, nessun invio di immagini a servizi esterni: indicalo nella Guida e nell'informativa privacy.

## A1. Architettura (testabile)
In `lib/services/ocr/`:
- `ocr_port.dart`: interfaccia `abstract interface class TextRecognizerPort { Future<OcrResult> recognize(String imagePath); }` con `OcrResult { List<OcrLine> lines; }` e `OcrLine { String text; Rect box; double? confidence; }` (le righe con il rettangolo di delimitazione, ordinate). Implementazione reale `MlkitTextRecognizer` (script Latin) e `FakeTextRecognizer` per i test.
- `document_parser.dart`: **solo Dart puro**, nessuna dipendenza da Flutter/ML Kit, input `OcrResult`, output `ParsedDocument`:
  ```dart
  class ParsedDocument {
    ParsedField<String>? supplierName, supplierVat, docNumber;
    ParsedField<DateTime>? docDate;
    DocKind kind; // ddt | fattura | sconosciuto
    List<ParsedLine> lines;
  }
  class ParsedLine {
    ParsedField<String>? description, lot, unit;
    ParsedField<double>? quantity;
    ParsedField<DateTime>? expiry;
  }
  class ParsedField<T> { T value; double confidence; Rect? sourceBox; String rawText; }
  ```
- `ocr_preprocess.dart`: per l'OCR usa una copia temporanea a risoluzione adeguata (lato lungo ~2000–2400 px, orientamento EXIF corretto, eventuale aumento del contrasto/scala di grigi); la copia **salvata come allegato** resta quella compressa standard. La copia OCR si elimina subito dopo.
- `pdf_rasterizer.dart`: i DDT arrivano spesso come PDF (email, WhatsApp). Rasterizza le pagine con `Printing.raster` (già disponibile; ~200 dpi, massimo 6 pagine per documento) e passale all'OCR come immagini; l'allegato originale resta il PDF intatto.

## A2. Regole del parser (italiano)
- Riconosci i campi dalle etichette, tolleranti a maiuscole/punteggiatura/errori OCR: lotto (`Lotto`, `Lot.`, `LOTTO N.`, `Batch`, `L.`), scadenza (`Scad.`, `Scadenza`, `Da consumarsi entro`, `Da consumare entro`, `TMC`, `Termine minimo di conservazione`, `Data scad.`), quantità (`Q.tà`, `Qta`, `Quantità`, `Q.ta`), unità (`KG`, `Kg`, `PZ`, `NR`, `CF`, `COLLI`, `LT`, `GR`), numero documento (`DDT n.`, `Documento di trasporto n.`, `Fattura n.`), data documento, partita IVA (11 cifre, con controllo di validità), nome fornitore (intestazione in alto, più grande/più alta).
- Date: `gg/mm/aaaa`, `gg-mm-aa`, `gg.mm.aaaa`, `mm/aaaa`; scarta date impossibili; la scadenza deve essere ≥ data documento (altrimenti segnala).
- Numeri in formato italiano (virgola decimale, punto migliaia). Correzioni di confusioni OCR (`O`↔`0`, `l`/`I`↔`1`, `S`↔`5`, `B`↔`8`) **solo** in contesti numerici/data.
- Tabelle: individua le colonne dalle posizioni orizzontali delle intestazioni (Descrizione, Lotto, Scad., Q.tà, UM) e assegna le celle per allineamento; gestisci righe di descrizione su più linee e lotto/scadenza scritti sotto la descrizione.
- **Mai inventare:** se un campo non si trova resta vuoto. Ogni campo ha una confidenza (0–1) calcolata da qualità del match, validazione (data valida, numero plausibile), posizione e confidenza OCR.
- Corrispondenza con i dati esistenti: confronto approssimato (normalizzazione, similarità) del fornitore con l'elenco fornitori (e P.IVA se già salvata) e della descrizione con i prodotti, per precompilare categoria/allergeni. Se non c'è corrispondenza, proponi "Nuovo fornitore/prodotto" senza crearlo da solo.

## A3. Flusso utente (`Merce in arrivo`)
- Pulsante **"Scansiona documento"** nel foglio "Nuova merce in arrivo" (e in "Lotti"): scatta una o più pagine, o scegli foto/PDF dal telefono. Suggerimenti sul riquadro: luce, documento piano, tutto nel campo.
- Mentre elabora mostra un indicatore con testo ("Leggo il documento…"); l'elaborazione non deve bloccare la UI (isolate o chiamate async brevi) e dev'essere annullabile.
- Schermata **"Verifica dati letti"**: anteprima del documento con riquadri evidenziati sulle zone lette; sotto, le righe prodotto riconosciute come schede modificabili (prodotto, lotto, scadenza, quantità, unità). Campi a bassa confidenza evidenziati con colori del tema (warning + icona + testo "Controlla", mai solo colore); campi non trovati vuoti con segnaposto. Selezione delle righe da registrare (casella), "Aggiungi riga" manuale.
- Alla conferma: per ogni riga selezionata si apre il normale foglio di registrazione **già precompilato** (fornitore, prodotto, DDT, lotto, scadenza, quantità) in una coda "Riga 1 di 3": l'operatore completa i controlli HACCP (temperatura, integrità, ecc.) e salva. Nulla viene salvato senza conferma esplicita.
- L'allegato (foto/PDF del documento) viene collegato a **tutte** le merci create dallo stesso documento (un solo file, più record collegati o un riferimento condiviso; non duplicare il file).
- Se l'OCR non trova nulla o fallisce: messaggio chiaro e ripiego sull'inserimento manuale con il documento comunque allegato.
- Permesso fotocamera chiesto solo al primo scatto; tutto in italiano.

## A4. Opzionale (stessa funzione, bassa priorità): etichette con codice GS1
`mobile_scanner` è già presente: se il codice letto è GS1-128/DataMatrix, estrai gli identificatori applicativi `(01)` GTIN, `(10)` lotto, `(17)` scadenza (AAMMGG; giorno `00` = fine mese), `(37)`/`(310x)` quantità/peso, e usali per precompilare lotto e scadenza. Un EAN-13 semplice dà solo il prodotto. Test con stringhe GS1 d'esempio.

## A5. Test Parte A
- `test/ocr/document_parser_test.dart` con fixture JSON in `test/fixtures/ocr/` (righe + rettangoli) per almeno 6 impaginazioni diverse di DDT/fattura (tabella con lotto e scadenza, lotto sotto la descrizione, date `mm/aaaa`, numeri con virgola, fornitore in alto, righe multiple). Le fixture devono essere **sintetiche o anonimizzate** (nessun dato reale di clienti nel repository).
- Test di: confusioni OCR in contesto numerico; scadenza prima della data documento → segnalata; nessuna invenzione quando i campi mancano; abbinamento fornitore/prodotto; GS1.
- Test widget con `FakeTextRecognizer`: verifica dati, modifica di un campo, creazione coda di righe, annullamento senza file residui.
- `docs/ocr.md`: limiti noti (foto sfocate, carta piegata, stampe ad aghi), procedura per aggiungere fixture reali anonimizzate, requisiti iOS.

---

# PARTE B — Gestione dello spazio e sicurezza degli allegati

## B1. Dove sono e quanto pesano (documenta in `docs/allegati.md`)
- Percorso: cartella privata dell'app, `attachments/AAAA/MM/`. Su Android viene eliminata con la disinstallazione; senza backup/cloud le foto si perdono con il telefono.
- Foto: JPEG ~1600 px qualità 80 (ordine di grandezza di centinaia di KB ciascuna; misura sul dispositivo e riportalo nel documento). PDF: copiati senza ricompressione, possono pesare megabyte.
- Mostra all'utente in modo chiaro: spazio usato dagli allegati, numero, ripartizione per tipo e per anno.

## B2. Schermata "Spazio e allegati" (Altro → Backup/Archivio)
- Totale spazio usato, numero file, ripartizione per tipo (foto/PDF) e per anno, i 20 file più grandi, e quanti allegati **non sono ancora al sicuro** (nessun `cloud_id`/`synced_at`).
- Avviso, se Google Drive non è collegato: "Gli allegati sono solo su questo telefono. Collega Google Drive per metterli al sicuro." (non bloccante).
- Impostazioni: **qualità foto** con 3 profili (Risparmio ~1280 px/q70, Standard ~1600 px/q80 predefinito, Alta ~2000 px/q85); si applica ai nuovi allegati; l'OCR usa sempre la sua copia ad alta risoluzione temporanea.
- Azione **"Libera spazio"**: per gli allegati più vecchi di N mesi (scelta dell'utente, es. 6/12/24) e **già verificati sul cloud** (`cloud_id` valorizzato, `synced_at` presente, e conferma dell'esistenza remota quando possibile), elimina il file locale e conserva: record, miniatura (256 px, ~10–20 KB) e un riferimento al cloud. Mai eliminare file non caricati o con caricamento fallito. Mai toccare allegati di non conformità aperte o di lotti non ancora scaduti. Conferma esplicita con riepilogo ("Libererai 420 MB, 1.250 file").
- Un allegato "su Drive" mostra la miniatura, il tag "Solo su Drive" e il pulsante **Scarica/Apri** (scarica a richiesta, lo riporta locale o lo apre temporaneo). Senza rete: messaggio chiaro.
- Conservazione: opzione "Elimina allegati più vecchi di… (mai / 2 / 3 / 5 anni)" **predefinita "Mai"**. I tempi di conservazione legali dipendono dal tipo di documento e dalle indicazioni dell'ASL/consulente: mostra la nota "Verifica con il tuo consulente HACCP prima di impostare un'eliminazione automatica" e non preimpostare periodi.

## B3. Modello dati e manutenzione
- Migrazione incrementale: colonne su `attachments`: `sha256 TEXT`, `thumb_path TEXT`, `width INTEGER`, `height INTEGER`, `offloaded_at TEXT` (file locale rimosso, resta su cloud). Indice su `sha256` e su `created_at`.
- **Deduplica:** calcola lo SHA-256 al salvataggio; se esiste già lo stesso file riusa il record/file invece di duplicarlo (utile per lo stesso DDT collegato a più merci).
- **Miniature:** genera una miniatura 256 px al salvataggio e usala nelle liste (meno memoria e scorrimento più fluido); l'immagine piena si apre solo nel visualizzatore.
- **Pulizia:** all'avvio (in background, a bassa priorità) elimina `pending_attachments` più vecchi di 24 ore; segnala file senza record (orfani) e record senza file, con pulsante "Ripara" nella schermata Spazio e allegati (mai cancellazioni silenziose di file con record).
- `deleteAttachment` rimuove file e miniatura; se l'allegato è condiviso da più entità, elimina il file solo quando non resta nessun riferimento.
- PDF dossier/report (`pdf_service.dart`, `getDossierPhotos`): per gli allegati "solo su Drive" usa la miniatura e la dicitura "allegato su Drive", senza errori.

## B4. Backup e ripristino con gli allegati
- Il backup attuale (solo DB) resta, ma indica chiaramente nella schermata che **non include le foto**, e `manifest.schemaVersion` deve riportare la versione reale del database.
- Aggiungi **"Backup completo con allegati"** (opzione) senza mai caricare tutti i file in memoria: scrittura in streaming su disco (`archive_io`/`ZipFileEncoder` o equivalente), con progresso e possibilità di annullare. Opzione di intervallo (ultimo anno / tutto). Se è attiva la cifratura, applicala senza leggere l'intero archivio in RAM (cifratura a blocchi) oppure, se non fattibile, limita il backup cifrato al solo DB e dillo all'utente.
- Il percorso consigliato per le foto resta **Google Drive** (coda `sync_queue` incrementale, solo Wi-Fi come opzione, ripresa dopo errore). Verifica che ogni nuovo allegato venga messo in coda e che lo stato di sincronizzazione sia visibile (icona nella lista).
- **Ripristino:** se il record punta a un file assente ma c'è `cloud_id`, mostra "Solo su Drive" (scaricabile); se non c'è nemmeno quello, "File non disponibile" senza errori né crash.
- Test: backup completo con 200 file finti senza picchi di memoria, ripristino con file mancanti, deduplica, libera-spazio che non tocca file non sincronizzati né allegati di NC aperte.

## B5. Android/iOS
- Nessun permesso di archiviazione nuovo (cartella privata dell'app). Non escludere la cartella dai backup di sistema iOS (lascia il comportamento predefinito di iCloud/dispositivo).
- Gestisci spazio insufficiente: se il salvataggio fallisce, messaggio comprensibile ("Spazio insufficiente: libera spazio o usa Google Drive") e nessun record parziale.

---

## Criteri di accettazione
1. "Scansiona documento" da foto e da PDF precompila fornitore, numero documento, data e righe (prodotto, lotto, scadenza, quantità) con evidenza dei campi incerti; nulla viene salvato senza conferma; con OCR fallito resta l'inserimento manuale.
2. L'OCR è interamente sul telefono: nessuna chiamata di rete; nessun dato reale nelle fixture; parser testato su almeno 6 impaginazioni.
3. Lo stesso documento collegato a più merci non duplica il file.
4. La schermata "Spazio e allegati" mostra spazio, conteggi, file più grandi e allegati non ancora al sicuro; profili di qualità foto funzionanti; "Libera spazio" elimina solo file già verificati su cloud, mantenendo miniatura e riferimento.
5. Backup: schemaVersion reale; opzione "con allegati" in streaming senza picchi di memoria; ripristino robusto con file mancanti.
6. iOS portato a 15.5+ (nota per `pod install` su Mac); `flutter analyze` pulito e test passano.
