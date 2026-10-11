# PROMPT 18 — Le notifiche pianificate (promemoria) non vengono eseguite — HACCPass

Progetto: `D:\DEV\App\HACCPass`. Segnalazione: i promemoria programmati (temperature mattina/pomeriggio, chiusura pulizie, verifiche periodiche) non compaiono all'orario previsto. Prima di modificare leggi `lib/services/reminder_service.dart`, `lib/main.dart` (`_bootstrap`, ~riga 348), `lib/screens/onboarding/onboarding_screen.dart` (~riga 90), la schermata Impostazioni/Promemoria, `android/app/src/main/AndroidManifest.xml`, `android/app/build.gradle.kts`, `android/app/proguard-rules.pro`, `pubspec.yaml` (`flutter_local_notifications ^22.3.1`, `timezone`, `flutter_timezone`, `permission_handler`). Dopo ogni gruppo di modifiche `flutter analyze` e `flutter test`.

## Diagnosi dal codice (da confermare con il punto 1)

1. **Pianificazione solo "inexact":** tutte le `zonedSchedule` usano `AndroidScheduleMode.inexactAllowWhileIdle`. Android può ritardare o saltare l'allarme in Doze/risparmio energetico (Samsung, Xiaomi, Huawei, Oppo sono aggressivi): per un promemoria "alle 08:30" è un difetto.
2. **Nessuna rete di sicurezza dopo il riavvio:** il manifest ha solo `POST_NOTIFICATIONS`. Mancano `RECEIVE_BOOT_COMPLETED` e i receiver del plugin; dopo un riavvio del telefono (o aggiornamento dell'app) gli allarmi vanno persi finché l'utente non riapre l'app.
3. **Permesso e stato non verificati:** `areEnabled()` guarda solo le richieste pendenti, non se le notifiche sono consentite né se il canale `blue_haccp_promemoria` è stato silenziato. Se l'utente ha negato il permesso nel wizard, `rescheduleAll()` programma comunque e non succede nulla, senza alcun avviso.
4. **Release/R8:** la build di release usa regole ProGuard che contengono solo ML Kit. Verifica se la build è minificata e se servono regole `keep` per `flutter_local_notifications` (Gson/TypeToken): senza, la pianificazione può fallire solo in release.
5. **Nessun modo di verificare:** non c'è una diagnostica per l'utente.

## 1. Verifica prima di cambiare (documenta l'esito in `docs/promemoria.md`)

- Verifica nel **manifest unito** della release (`android/app/build/intermediates/merged_manifests/release/.../AndroidManifest.xml` dopo `flutter build apk --release`) se compaiono `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver` e `RECEIVE_BOOT_COMPLETED` (il plugin può già aggiungerli). Aggiungi al manifest dell'app **solo quelli che mancano**, come da documentazione del plugin, con `android:exported="false"`.
- Controlla se la release è minificata (`isMinifyEnabled`/default Flutter) e se la pianificazione funziona in release e non solo in debug.

## 2. Affidabilità della pianificazione

- Aggiungi `RECEIVE_BOOT_COMPLETED` e i receiver mancanti (punto 1), così gli allarmi si ricreano dopo riavvio e aggiornamento dell'app.
- **Allarmi esatti con ripiego:** su Android 12+ usa `AndroidScheduleMode.exactAllowWhileIdle` solo se `canScheduleExactNotifications()` è `true`; altrimenti ripiega su `inexactAllowWhileIdle`. Dichiara `SCHEDULE_EXACT_ALARM` nel manifest (non `USE_EXACT_ALARM`: è riservato ad app sveglia/calendario e Play lo controlla). Se l'allarme esatto non è concesso, la schermata Promemoria mostra una riga "Per orari precisi consenti 'Sveglie e promemoria'" con pulsante che apre la pagina di sistema (`requestExactAlarmsPermission()`); mai richiesto all'avvio, solo dalla schermata Promemoria.
- `rescheduleAll()` deve: (a) non programmare nulla e restituire un esito chiaro se le notifiche non sono consentite; (b) restituire quanti promemoria ha programmato; (c) essere chiamata anche dopo che l'utente concede il permesso, dopo che cambia un orario e al ritorno in primo piano (`AppLifecycleState.resumed`), non solo all'avvio.
- Dopo il cambio di fuso orario o ora legale la prossima occorrenza va ricalcolata (la riprogrammazione al resume lo copre); verifica `_nextOccurrence` attorno al cambio ora (ultima domenica di marzo e ottobre) e che `DateTimeComponents.time` ripeta ogni giorno all'ora locale.
- Il canale `blue_haccp_promemoria` resta con lo stesso id e nome (non cambiarlo). Se importanza o canale sono stati disattivati dall'utente nelle impostazioni di sistema, rilevalo (`areNotificationsEnabled()`, stato del canale) e mostralo.

## 3. Schermata "Promemoria" con diagnostica

In Impostazioni (voce Promemoria, o dove sono gli orari oggi) aggiungi un blocco "Stato dei promemoria" con righe chiare in italiano:

- Notifiche consentite: Sì/No (se No: pulsante "Apri impostazioni notifiche", usa `openAppSettings()`).
- Allarmi precisi: Sì/No (se No: pulsante come al punto 2).
- Risparmio energetico: spiega in una frase che alcuni telefoni bloccano le notifiche delle app in background e proponi "Escludi HACCPass dall'ottimizzazione batteria" (`Permission.ignoreBatteryOptimizations`, richiesta **solo** al tocco; valuta se la policy Play lo consente per la tua app e, se hai dubbi, apri solo la pagina delle impostazioni batteria senza richiedere il permesso dedicato). Testo per i marchi più restrittivi (Samsung, Xiaomi, Huawei, Oppo, OnePlus): "Abilita l'avvio automatico e disattiva il risparmio energetico per HACCPass".
- Promemoria programmati: elenco dei `pendingNotificationRequests()` con titolo e prossima ora.
- Pulsante **"Prova una notifica tra 1 minuto"** (programma una notifica con `zonedSchedule` fra 60 secondi, con lo stesso canale e modalità dei promemoria veri) oltre a "Notifica immediata". Se la notifica immediata arriva e quella a 1 minuto no, il problema è la pianificazione/energia e non il permesso: dillo all'utente.

## 4. Release: regole e prova

- Se in release la pianificazione fallisce o il plugin viene rimosso da R8, aggiungi a `proguard-rules.pro` le regole `keep` raccomandate per `flutter_local_notifications`.
- Prova **in release** su un telefono reale (non solo emulatore): `flutter build apk --release`, installa, imposta un promemoria fra 2 minuti, chiudi l'app, schermo spento; poi con riavvio del telefono. Documenta modelli provati in `docs/promemoria.md`.

## 5. Test e documentazione

- Test unitari con plugin finto: `rescheduleAll` non programma se le notifiche sono negate; usa modalità esatta solo se consentita; ripiega su inexact; `_nextOccurrence` per ore prima/dopo `now`, a mezzanotte, nel cambio ora legale (Europe/Rome).
- `docs/promemoria.md`: come funzionano (locali, nessun server), permessi necessari, limiti dei telefoni con risparmio energetico, come si prova, risoluzione problemi.

## Criteri di accettazione

1. In release, con app chiusa e schermo spento, il promemoria arriva all'ora impostata (o con ritardo trascurabile dove gli allarmi esatti sono consentiti).
2. Dopo il riavvio del telefono i promemoria continuano ad arrivare senza riaprire l'app.
3. Se permessi/canale sono negati, la schermata Promemoria lo dice e indica come risolvere; l'app non finge che i promemoria siano attivi.
4. La schermata mostra stato, prossimi promemoria e il test "tra 1 minuto".
5. Nessun permesso chiesto all'avvio; `flutter analyze` e `flutter test` verdi; `docs/promemoria.md` aggiornato.
