# PROMPT 3 — Correzioni colori/navigazione + aggiornamenti normativi + nuovi moduli (Blue HACCP)

Contesto: il Prompt 1 è stato implementato. Questo prompt corregge i difetti visivi rimasti, aggiorna l'app alle norme vigenti e aggiunge moduli derivati dal terzo manuale (MGSA-0415 Rev.2 09/2020). Lavora per fasi, esegui `flutter analyze` e `flutter test` al termine di ciascuna, non rompere la migrazione DB esistente (aggiungi solo migrazioni incrementali).

---

## FASE A — Bug colori e navigazione (PRIORITÀ MASSIMA)

### A1. Sfondo nero / titoli illeggibili / niente pulsante indietro
**Causa:** le schermate aperte con `Navigator.push(MaterialPageRoute(...))` da `app_shell.dart::_openTarget` e `checks_hub_screen.dart::_open` (TemperatureScreen, CleaningScreen, ReceiptsScreen, LotsScreen, PestsScreen, StructuresScreen, NonConformitiesScreen, StaffScreen, CompanyScreen, ecc.) usano `Scaffold(backgroundColor: Colors.transparent)` e non hanno AppBar. Quando non sono dentro la shell non c'è nulla dietro: sfondo nero, titolo scuro su nero, nessun "indietro".

**Fix:**
1. Rimuovi `backgroundColor: Colors.transparent` da TUTTI gli Scaffold delle schermate di funzione (grep: `backgroundColor: Colors.transparent`). Lo sfondo deve venire da `scaffoldBackgroundColor` del tema.
2. Crea un widget `FeatureScaffold` (in `common_widgets.dart`) con: `Scaffold` + `AppBar` (titolo, freccia indietro automatica, `foregroundColor` dal tema, elevation 0, `surfaceTintColor: transparent`), `body` in `SafeArea`, parametro `floatingActionButton`. Usalo in tutte le schermate che si aprono via push. Le schermate che sono tab della shell restano senza AppBar ma con sfondo tema opaco.
3. Sostituisci `PageHeader` duplicato col titolo AppBar quando la schermata è pushata (evita il titolo doppio).
4. `bottomSheetTheme`: `backgroundColor` e `modalBackgroundColor` devono essere `colors.surface` (non trasparente), con `showDragHandle: true` e bordi superiori arrotondati 24. Rimuovi i `Colors.transparent` e i `Colors.white` hardcoded (common_widgets.dart ~834, ~1074-1075) usando i colori del tema.
5. Test widget: per ogni schermata pushata verifica che esista `AppBar`, che `Scaffold.backgroundColor` non sia trasparente e che il titolo abbia contrasto ≥ 4.5:1 su sfondo in light e dark.

### A2. Tutto "marrone" nei Da fare ora
**Causa:** `haccp_repository.dart` assegna `severity: 1` (warning=marrone `8A4B00`) a quasi tutto: letture mancanti, pulizie in scadenza, verifica termometro. Il colore perde significato.

**Nuova semantica (obbligatoria):**
- `danger` (rosso): non conformità aperte, formazione scaduta, fuori limite non risolto, prodotto scaduto.
- `warning` (ambra): SOLO elementi già in ritardo o in scadenza entro 7 giorni (verifica termometro scaduta, lotto in scadenza, pest threshold vicino).
- `info` (teal/blu): attività giornaliere ordinarie da eseguire (letture temperatura del giorno, pulizie previste oggi).
- `success` (verde): completato.
Aggiorna le assegnazioni `severity` (righe ~977-1096) di conseguenza e mantieni l'ordinamento.

### A3. Palette (sostituire in `app_theme.dart`)
Errore mio nel Prompt 1: il bordo `#C3D1CE` dichiarato "3:1" in realtà è 1.58:1. Valori corretti (verificati ≥3:1 per bordi/icone, ≥4.5:1 per testo):

| Token | Light | Dark |
|---|---|---|
| border / outline (campi input, bordi controlli) | `#6B7B78` | `#6F8581` |
| divider / bordo card decorativo | `#D5DFDC` | `#2A3B37` |
| warning testo/icona | `#B45309` (5.0:1 su bianco) | `#F5C67C` |
| warning stripe | `#D97706` | `#F59E0B` |
| warningBg | `#FFF1DB` | `#352711` |

- Non usare `#F59E0B` per testo/icone su fondo chiaro.
- `scheme.outline` = border controlli; `scheme.outlineVariant` = divider. I `TextField`, `Checkbox`, `Switch` off, `Chip` devono usare `outline` (3:1).
- **Bug `lerp`** in `HaccpColors`: `warning: Color.lerp(warning, other.warningBg, t)!` → `other.warning`. Controlla tutti i campi di lerp/copyWith per refusi analoghi e aggiungi un test che verifichi `lerp(a,b,1) == b` per ogni campo.
- Snackbar: `contentTextStyle` con colore preso dal tema (`onInverseSurface`), non `Colors.white` condizionale.
- Aggiungi un test automatico di contrasto (funzione `contrastRatio`) su tutte le coppie testo/sfondo e bordo/sfondo di light e dark; il test deve fallire sotto soglia.
- Verifica manuale con screenshot su emulatore: light, dark, testo ingrandito 130%.

---

## FASE B — Aggiornamenti normativi (verificati)

Nota: non esiste una nuova legge nazionale HACCP 2024-2026. Gli aggiornamenti rilevanti sono i seguenti (non inventare altri riferimenti normativi; ignora fonti che citano un "Reg. UE 2025/636" come HACCP: riguarda certificati sanitari all'importazione).

1. **Reg. UE 2021/382** (modifica Reg. CE 852/2004, allegato II): obbligo di **cultura della sicurezza alimentare**, gestione allergeni, ridistribuzione degli alimenti, procedure contro contaminazione crociata.
   - Nuovo modulo "Cultura della sicurezza alimentare": politica firmata dal titolare, impegno della direzione, registro delle comunicazioni al personale, verifica annuale (checklist + data + firma).
2. **Comunicazione Commissione 2022/C 355/01** (orientamenti su gestione allergeni): 
   - Registro allergeni **scritto** per piatto/prodotto (14 allergeni, Reg. UE 1169/2011, D.Lgs. 231/2017), non solo QR/menu digitale; stampabile in PDF e consultabile al banco.
   - Procedura contaminazione crociata: checklist di pulizia attrezzature condivise e verifica residui, collegata al piano di pulizia.
3. **Formazione**: la durata di validità dell'attestato è regolata a livello regionale (es. Emilia-Romagna L.R. 9/2025, Toscana DGR 540/2024). Rendi il periodo di rinnovo **configurabile per attività/regione** (default 36 mesi, modificabile) e aggiungi il "piano di formazione annuale".
4. **Ridistribuzione alimenti** (facoltativa): registro donazioni (data, prodotto, quantità, ente, temperatura/stato).
5. Aggiungi nella schermata Guida una sezione "Riferimenti normativi" con data di ultimo aggiornamento dei contenuti e il disclaimer: "Contenuti di supporto, non sostituiscono la consulenza di un tecnico HACCP o le disposizioni della propria ASL/Regione."

---

## FASE C — Nuovi contenuti dal manuale MGSA-0415 (DP15)

Implementa come **parametri e registri configurabili** (default da manuale, modificabili e disattivabili in impostazioni; i moduli si attivano in base al tipo di attività scelto nel wizard).

### C1. Cottura e rigenerazione (PR COT)
- Temperatura minima al cuore dopo cottura: **≥ +75 °C**; rigenerazione: **≥ +65 °C** al cuore; sughi/salse: portare a ebollizione.
- Frittura: **max 180 °C**, nessun rabbocco dell'olio con olio fresco; svuotare e pulire vasca e filtro a fine uso.
- Tabella linee guida PR COT 01 (cuore/tempo): carni bovine e suine pezzo intero 72 °C/2 min; roast-beef 63 °C/3 min; uova fresche in guscio 63 °C/15 s; preparati a base di pesce/carne/selvaggina allevata 68 °C/15 s; pollame, carne, pesce, pasta ripiena 74 °C/15 s; muscolo intero/bistecche/scaloppine/costate 63 °C/15 s sulla superficie; altri alimenti di origine animale 63 °C/15 s. Offri una **schermata "Registra cottura"** con selezione categoria, inserimento temperatura al cuore, esito automatico conforme/non conforme e apertura NC con azione correttiva (ricottura o eliminazione + assistenza tecnica).
- Registro **Validazione olio da frittura** (PR COT 02): data, friggitrice, temperatura, esito organolettico, cambio olio sì/no, operatore. Promemoria periodico.

### C2. Abbattimento e raffreddamento (PR ABB)
- Abbattimento positivo: **a +3 °C entro 2 ore**; negativo: **a −18 °C entro 2 ore** (valori di PR ABB); la tabella PR COT 01 riporta anche limiti più ampi (<10 °C entro 2 h positivo; <−20 °C entro 4 h negativo): rendi i limiti configurabili con default PR ABB.
- Registro cicli di abbattimento: prodotto, ora inizio/fine, T iniziale/finale, esito, etichetta con data di produzione e scadenza (collegata a lotto interno). Anomalia → ritiro e distruzione (NC).

### C3. Mantenimento, trasporto, somministrazione (PR TRA / PR SOM)
- Mantenimento caldo **60–65 °C**; freddo **< +10 °C**; gelati/surgelati confezionati **−15/−20 °C**.
- Trasporto catering: freddi **< 10 °C**, caldi **> 65 °C**; checklist automezzo/contenitori (puliti, sanificati) e registrazione temperature a partenza e arrivo.

### C4. Pasto campione (PR CAMP 01)
- Registro campioni: piatto, data prelievo, ≥ **100 g**, etichetta "campione ad uso interno", conservazione **0/+4 °C per almeno 72 ore**; scadenza di conservazione calcolata automaticamente e promemoria di smaltimento. Obbligatorio per catering esterno e piatti con ingredienti di origine animale.

### C5. Acqua potabile e ghiaccio (PR APO)
- Promemoria annuale analisi microbiologica acqua (con upload referto come allegato); pulizia periodica filtri/rompigetto; **sanificazione mensile del produttore di ghiaccio** (registro con data, operatore, esito).

### C6. Allergeni (PR ALL 01)
- Scheda informativa al personale da firmare all'assunzione (data/firma/versione) archiviata nell'anagrafica personale; collegamento con il registro allergeni (Fase B).

### C7. Rintracciabilità e crisi/ritiro (PR RIN)
- Modulo "Ritiro/richiamo": selezione lotto, elenco clienti/destinatari, azioni, comunicazione ASL, esito. Esportazione PDF.
- Mantieni la rintracciabilità tramite DDT/etichetta del fornitore e dicitura prodotto + data di preparazione per i semilavorati.

### C8. PDF e riepilogo
- Aggiungi al generatore PDF i nuovi registri (cottura, abbattimento, olio, campioni, acqua/ghiaccio, ritiro, cultura sicurezza, allergeni scritto) con stessa impaginazione e intestazione azienda, firma digitale/immagine e condivisione dallo smartphone.
- Pagina "Prospetto riassuntivo" nell'app: elenco moduli, frequenza di compilazione e responsabile, stato (compilato/da compilare), ispirato al prospetto allegati/moduli del manuale.

---

## Criteri di accettazione
1. Nessuna schermata con sfondo nero o titolo illeggibile in light/dark/testo 130%; tutte le schermate pushate hanno freccia indietro.
2. "Da fare ora" mostra colori coerenti con la semantica A2.
3. Test contrasto e test lerp passano; `flutter analyze` senza errori.
4. Migrazioni DB incrementali (v3→v4 o successiva) senza perdita dati; test di migrazione.
5. Tutti i nuovi limiti sono parametri modificabili con default dal manuale; ogni fuori limite apre una NC con azione correttiva suggerita.
6. Tutte le stringhe in italiano, nessun testo hardcoded fuori dalle risorse già usate nel progetto.
7. Disclaimer normativo visibile nella Guida e nei PDF.
