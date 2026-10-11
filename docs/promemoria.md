# Promemoria (notifiche pianificate) — Prompt 18

## Come funzionano

I promemoria sono **completamente locali** (`flutter_local_notifications`,
nessun server, nessun dato inviato): l'app programma un allarme per ogni
orario attivo e Android lo mostra come notifica all'ora stabilita, anche
a app chiusa.

- **Orari**: controllo temperature mattina/pomeriggio, chiusura pulizie
  (giornalieri, `reminder_*` in "HH:mm") e verifiche periodiche
  (`reminder_periodic`: `''` | `weekly` = lunedì 8:00 | `monthly` = giorno
  1 alle 8:00). Si impostano nel wizard (passo 10) e in
  **Impostazioni → Promemoria**.
- **Canale**: `blue_haccp_promemoria` (id storico: NON cambia, per non
  perdere le impostazioni di notifica scelte dall'utente).
- **Allarmi esatti con ripiego** (Android 12+): l'app usa
  `exactAllowWhileIdle` solo se "Sveglie e promemoria" è concesso
  (`SCHEDULE_EXACT_ALARM`, dichiarato nel manifest), altrimenti ripiega
  su `inexactAllowWhileIdle` e la schermata Promemoria dice che gli orari
  sono indicativi. Il permesso si chiede SOLO dalla schermata Promemoria.
- **Riprogrammazione automatica**: a ogni avvio, al ritorno in primo
  piano (copre permesso conceso in seguito, cambio orari, cambio
  fuso/ora legale) e al termine del ripristino di un backup. La prossima
  occorrenza è calcolata per componenti di data (il vecchio +24h slittava
  di un'ora nel giorno del cambio ora: testato su Europe/Rome).
- **Dopo il riavvio del telefono o l'aggiornamento dell'app**: gli
  allarmi si ricreano da soli grazie a `RECEIVE_BOOT_COMPLETED` e ai
  receiver `ScheduledNotificationReceiver` /
  `ScheduledNotificationBootReceiver` (dal plugin v19 NON sono più nel
  manifest del plugin: dichiarati nell'app — verificati nel manifest
  unito della release).

## Cosa era rotto (diagnosi, risolto in questo prompt)

1. Le **verifiche periodiche non venivano mai programmate**: il wizard
   salvava `'weekly'`/`'monthly'` ma il servizio accettava solo "HH:mm".
2. **Allarmi persi al riavvio**: mancavano `RECEIVE_BOOT_COMPLETED` e i
   receiver nel manifest dell'app (il plugin 22.x li dichiara solo
   `VIBRATE` + `POST_NOTIFICATIONS`).
3. Solo pianificazione `inexact`: in Doze/risparmio energetico Android
   può ritardare o saltare; ora esatta quando consentita.
4. Nessun controllo del permesso: con notifiche negate si programmano
   allarmi invisibili; ora `rescheduleAll` non programma nulla e la
   schermata Promemoria lo dice.
5. Nessuna diagnostica: ora esiste (vedi sotto).

## Permessi

| Permesso | Quando | Note |
|---|---|---|
| `POST_NOTIFICATIONS` (Android 13+) | wizard, passo 10 | se negato: schermata Promemoria → "Apri impostazioni notifiche" |
| `RECEIVE_BOOT_COMPLETED` | automatico | ricrea gli allarmi dopo il riavvio |
| `SCHEDULE_EXACT_ALARM` (Android 12+) | solo su richiesta, dalla schermata Promemoria | NON usare `USE_EXACT_ALARM` (riservato a sveglie/calendari, Play lo controlla) |
| `ignoreBatteryOptimizations` | solo al tocco in Promemoria → Stato | se la policy Play crea dubbi, aprire solo le impostazioni batteria e spiegare |

Nessun permesso richiesto all'avvio.

## Limiti dei telefini con risparmio energetico

Samsung, Xiaomi, Huawei, Oppo, OnePlus e simili possono bloccare le
notifiche delle app in background anche con tutti i permessi concessi.
La schermata Promemoria → "Stato dei promemoria" lo spiega e propone:

- "Escludi HACCPass dall'ottimizzazione batteria" (solo al tocco);
- per i marchi più restrittivi: "Abilita l'avvio automatico e disattiva
  il risparmio energetico per HACCPass" (istruzioni, nessun permesso).

## Diagnostica nella schermata Promemoria

- **Notifiche consentite: Sì/No** (+ "Apri impostazioni notifiche").
- **Allarmi precisi: Sì/No** (+ "Per orari precisi consenti 'Sveglie e
  promemoria'").
- **Promemoria programmati**: elenco delle notifiche in coda con titolo.
- **"Notifica immediata"** e **"Prova una notifica tra 1 minuto"** (stesso
  canale e modalità dei promemoria veri): se l'immediata arriva e quella
  a 1 minuto no, il problema è la pianificazione/l'energia e NON il
  permesso — e la schermata lo dice.
- Limiti noti: il plugin espone lo stato del permesso a livello di app;
  se l'utente ha silenziato SOLO il canale i promemoria non suonano ma
  lo stato risulta attivo (non si inventa nulla oltre a questo).

## Release / R8

La build di release oggi NON è minificata (nessun `isMinifyEnabled`), il
plugin non viene rimosso da R8. Se in futuro si attiva la minificazione,
in `android/app/proguard-rules.pro` ci sono già pronte (commentate) le
regole `keep` raccomandate per `flutter_local_notifications` (Gson).

## Come provare (telefono reale, non solo emulatore)

1. `flutter build apk --release` e installa;
2. imposta un promemoria a ~2 minuti da adesso, chiudi l'app, spegni lo
   schermo: la notifica deve arrivare all'ora;
3. "Prova una notifica tra 1 minuto" e "Notifica immediata";
4. riavvia il telefono senza aprire l'app: i promemoria continuano;
5. nega il permesso notifiche: la schermata Promemoria deve dirlo e non
   fingere che siano attivi;
6. prova su un telefono aggressivo (Samsung/Xiaomi) con e senza
   esclusione dall'ottimizzazione batteria.

## Modelli provati su hardware

**Da compilare dopo la prova reale**: modello telefono, versione
Android, build (debug/release), allarmi esatti concessi sì/no, esito con
schermo spento e dopo il riavvio.

## Risoluzione problemi

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| Nessuna notifica, nemmeno l'immediata | permesso negato o canale silenziato | Promemoria → Apri impostazioni notifiche |
| Immediata sì, "tra 1 minuto" no | pianificazione bloccata dall'energia | escludi dall'ottimizzazione batteria; avvio automatico (Samsung/Xiaomi/…) |
| Ritardi di alcuni minuti | allarmi inexact | consenti "Sveglie e promemoria" dalla schermata |
| Spariti dopo il riavvio del telefono | build senza receiver (vecchie versioni) | aggiorna l'app (ricever Boot ora dichiarato) |
| Verifiche periodiche mai arrivate | bug del valore 'weekly' (risolto) | aggiorna l'app |

## Test automatici

`test/reminder_service_test.dart` (plugin finto): non programma con
permesso negato; modalità esatta solo se consentita con ripiego inexact;
weekly/monthly programmate con la ripetizione giusta; `nextOccurrence`
per ore prima/dopo `now`, mezzanotte e ora legale (Europe/Rome,
29/03/2026 e 25/10/2026); prova "tra 1 minuto".
