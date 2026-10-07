# OCR dei documenti ricevuti (ML Kit, Prompt 8 parte A)

Lettura automatica di fornitore, numero documento, data e righe prodotto
(lotto, scadenza, quantità, unità) da foto o PDF di DDT e fatture, per
precompilare la registrazione della merce in arrivo.

## Come funziona

- **Tutto sul telefono**: `google_mlkit_text_recognition` con script Latin
  (l'italiano è coperto). NESSUNA chiamata di rete, nessuna immagine inviata
  a servizi esterni (dichiarato anche in Guida e informativa privacy).
- Architettura testabile in `lib/services/ocr/`:
  - `ocr_port.dart`: `TextRecognizerPort` (ML Kit + `FakeTextRecognizer`),
    `OcrResult`/`OcrLine`/`OcrBox` senza dipendenze da Flutter;
  - `document_parser.dart`: parser **Dart puro** (regole italiane, date,
    numeri con virgola, P.IVA con checksum, tabelle, confidenze, GS1);
  - `ocr_preprocess.dart`: copia temporanea ~2200 px per l'OCR (l'allegato
    salvato resta alla qualità scelta dall'utente); la copia si elimina
    dopo il riconoscimento;
  - `pdf_rasterizer.dart`: PDF rasterizzati (~200 dpi, max 6 pagine)
    tramite `printing`; il PDF allegato resta intatto;
  - `document_scan_service.dart`: coordinamento, più pagine, annullabile.
- Flusso utente: "Scansiona documento" (Merce in arrivo) → foto o file →
  "Leggo il documento…" annullabile → **Verifica dati letti** (campi incerti
  con "Controlla", righe modificabili e selezionabili, aggiunta manuale) →
  coda di fogli "Riga 1 di N" precompilati: l'operatore completa i controlli
  HACCP e conferma. **Nulla viene salvato senza conferma esplicita.**
- Il documento si collega a tutte le merci create (deduplica SHA-256:
  un solo file, più record).
- OCR fallito o illeggibile: messaggio chiaro e ripiego manuale.
- GS1 (opzionale): `parseGs1()` estrae (01) GTIN, (10) lotto, (17)
  scadenza (giorno 00 = fine mese), (37) pezzi, (310x) peso.

## Requisiti di piattaforma

- **iOS 15.5+**: il deployment target del progetto è stato portato da 13.0
  a **15.5** (`ios/Runner.xcodeproj`). **DA FARE SU MAC**: `pod install`
  dopo il primo build e controllo conflitti con i pod ML Kit già usati da
  `mobile_scanner` (entrambi usano ML Kit: di norma coesistono, verifica i
  warning di CocoaPods). Nel Podfile (quando generato) `platform :ios, '15.5'`.
- Android: minSdk già ≥ 21, targetSdk 35. Il modello Latin è incluso nel
  plugin: la build di release universale (fat APK, tutte le ABI) pesa
  **~121 MB** (misurata con `flutter build apk --release`): conviene
  `flutter build apk --split-per-abi` (~40-45 MB per architettura) oppure
  l'AAB su Play (download per dispositivo più piccoli).
- Nessun permesso nuovo: la fotocamera era già richiesta al primo scatto.

## Test

- `test/ocr/document_parser_test.dart`: primitive (date, numeri, P.IVA,
  confusioni OCR), 6 impaginazioni sintetiche in `test/fixtures/ocr/`
  (tabella a colonne, lotto sotto la descrizione, fattura con testata,
  scadenza mm/aaaa, confusioni OCR, righe multiple senza tabella),
  "mai inventare", scadenza precedente alla data documento, GS1.
- `test/ocr/review_screen_test.dart`: widget con `FakeTextRecognizer`
  (verifica, modifica, coda, annullamento; nessun overflow a 360×640 con
  scala 1.15).

## Aggiungere fixture reali (procedura)

1. Scattare la foto di un DDT/fattura **propri**, con dati sensibili
   rimossi o sostituiti (nessun dato reale di clienti nel repository).
2. Salvare in `test/fixtures/ocr/` un JSON con
   `"lines": [{"text": "...", "box": [l,t,r,b], "confidence": 0.9}]`
   (le posizioni si ricavano dalla diagnostica o da un DebugPrint dell'
   `OcrResult`).
3. Aggiungere il test atteso in `document_parser_test.dart`.

## Limiti noti

Foto sfocate o con poca luce, carta piegata, stampe ad aghi (caratteri
spezzati) e documenti con colonne non allineate riducono l'accuratezza:
per questo ogni campo porta una confidenza, i valori bassi sono evidenziati
con "Controlla" e nulla viene salvato senza la conferma dell'operatore.
I box ML Kit sono per RIGA (non per parola): l'assegnazione alle colonne
delle tabelle usa il riconoscimento per forma (data/lotto/quantità/unità),
non la posizione esatta.
