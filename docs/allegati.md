# Spazio e sicurezza degli allegati (Prompt 8 parte B)

## Dove sono e quanto pesano

- Percorso: cartella **privata dell'app**,
  `<documenti app>/attachments/AAAA/MM/`. Su Android viene eliminata con
  la disinstallazione; senza backup o Google Drive **le foto si perdono
  con il telefono** (nessun permesso di archiviazione richiesto).
- Foto: JPEG compresso secondo il profilo scelto (Standard: lato lungo
  ~1600 px, qualità 80 → ordine di grandezza di centinaia di KB ciascuna;
  la misura va rilevata sul dispositivo con la schermata "Spazio e
  allegati" e riportata qui). PDF: copiati senza ricompressione, possono
  pesare megabyte.
- La schermata **Altro → "Spazio e allegati"** mostra: totale, numero file,
  ripartizione per anno, i 20 file più grandi e quanti allegati **non sono
  ancora al sicuro** (nessun cloud), con l'avviso non bloccante su Google
  Drive.

## Modello dati (migrazione v6)

Colonne su `attachments`: `sha256` (deduplica), `thumb_path` (miniatura
256 px ~10-20 KB), `width`, `height`, `offloaded_at` (file locale rimosso,
resta record + miniatura + riferimento cloud). Indici su `sha256` e
`created_at`.

- **Deduplica**: SHA-256 al salvataggio; lo stesso documento collegato a
  più merci = un solo file, più record.
- **Miniature**: generate al salvataggio per le foto, usate nelle liste e
  nel dossier PDF (allegati "solo su Drive" → miniatura + dicitura).
- **Pulizia**: all'avvio vengono eliminati i `pending_attachments`
  temporanei più vecchi di 24 ore; la schermata segnala file orfani e
  record senza file con pulsante "Ripara" (mai cancellazioni silenziose
  di record).
- `deleteAttachment` elimina file e miniatura solo quando nessun altro
  record li referenzia.

## Qualità foto (nuovi allegati)

| Profilo | Lato lungo | Qualità |
|---|---|---|
| Risparmio | ~1280 px | 70 |
| **Standard (predefinito)** | ~1600 px | 80 |
| Alta | ~2000 px | 85 |

Si applica ai nuovi allegati; l'OCR usa sempre la SUA copia temporanea ad
alta risoluzione (~2200 px), eliminata dopo il riconoscimento.

## Libera spazio

Elimina i FILE LOCALI degli allegati più vecchi di 6/12/24 mesi **già
caricati e verificati su Google Drive** (cloud_id e synced_at presenti),
conservando record, miniatura e riferimento. Regole dure:
- MAI file non caricati o con caricamento fallito;
- MAI allegati di non conformità aperte (i lotti non scaduti restano
  protetti dalla stessa logica di esclusione);
- conferma esplicita con riepilogo dei byte liberati.

Un allegato "su Drive" mostra miniatura, tag "Solo su Drive" e download a
richiesta (senza rete: messaggio chiaro).

## Conservazione

Opzione "Elimina allegati più vecchi di: **Mai (predefinito)** / 2 / 3 / 5
anni". I tempi di conservazione legali dipendono dal tipo di documento e
dalle indicazioni dell'ASL/consulente: l'app non preimposta periodi e
mostra la nota di verifica con il consulente HACCP.

## Backup

- **Backup del database** (`.bhb`, cifrabile): NON include le foto —
  dichiarato nella schermata. `manifest.schemaVersion` ora riporta la
  versione REALE dello schema (6).
- **Backup completo con allegati** (opzione): database + tutte le foto,
  scritto **un file alla volta** (ZipFileEncoder, streaming: nessun picco
  di memoria anche con migliaia di foto), con progresso e annullamento.
  NON cifrabile (la cifratura AES-GCM attuale richiede l'archivio intero
  in RAM): dichiarato all'utente.
- Ripristino: il DB si ripristina come sempre; gli allegati tornano con
  "Backup completo → ripristino allegati". Record che puntano a file
  assenti: "File non disponibile" senza errori; se c'è `cloud_id` restano
  scaricabili da Drive.
- Il percorso consigliato per le foto resta **Google Drive** (coda
  incrementale `sync_queue`, stato di sincronizzazione visibile).
- Spazio insufficiente al salvataggio: messaggio comprensibile e nessun
  record parziale.

## Test

`test/attachments_v6_test.dart`: migrazione v5→v6, deduplica, eliminazione
consapevole dei riferimenti, regole "Libera spazio" (file non sincronizzati
mai toccati), statistiche, backup completo con 200 file + annullamento,
ripristino allegati, pulizia pending >24 h.
