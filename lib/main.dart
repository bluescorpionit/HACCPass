import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/database/app_database.dart';
import 'core/sensors/ble_sensor_source.dart';
import 'core/theme/app_theme.dart';
import 'repositories/haccp_repository.dart';
import 'screens/app_shell.dart';
import 'screens/first_run_choice_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/restore_wizard_screen.dart';
import 'services/attachment_service.dart';
import 'services/backup_service.dart';
import 'services/cloud/google_drive_provider.dart';
import 'services/daily_backup.dart';
import 'services/license_service.dart';
import 'services/reminder_service.dart';
import 'services/restore_service.dart';
import 'services/sync_service.dart';

/// Messenger radice: i messaggi fuori da uno Scaffold (es. invito al
/// ripristino dal controllo del backup automatico) passano da qui.
final rootMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Servizi dell'app inizializzati in background mentre la splash \u00E8
/// visibile.
class AppServices {
  const AppServices({
    required this.repository,
    required this.license,
    required this.attachments,
    required this.reminders,
    required this.backup,
    required this.sync,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final AttachmentService attachments;
  final ReminderService reminders;
  final BackupService backup;
  final SyncService sync;

  static Future<AppServices> load() async {
    final database = AppDatabase();
    await database.initialize();

    final repository = HaccpRepository(database);

    final license = LicenseService(
      readSetting: (key) async {
        final value = await repository.getSetting(key);
        return value.isEmpty ? null : value;
      },
      writeSetting: repository.setSetting,
    );
    await license.initialize();

    final attachments = AttachmentService(repository: repository);
    final reminders = ReminderService(repository: repository);
    await reminders.initialize();

    final backup = BackupService(repository: repository, appVersion: '1.0.0');
    final sync = SyncService(repository: repository);
    SyncService.instance = sync;
    await _restoreCloudSession(repository, sync);

    return AppServices(
      repository: repository,
      license: license,
      attachments: attachments,
      reminders: reminders,
      backup: backup,
      sync: sync,
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT');

  // Il bootstrap prosegue mentre la splash in-app mostra il logo:
  // durata minima 800 ms, mai bloccante.
  final services = AppServices.load();
  final minimumSplash = Future<void>.delayed(const Duration(milliseconds: 800));

  runApp(
    HaccpassApp(
      services: services,
      minimumSplash: minimumSplash,
    ),
  );
}

/// Ricollega il cloud salvato nelle impostazioni. SOLO silenzioso
/// (`interactive: false`): nessuna finestra di Google all'avvio, nemmeno
/// se il token è scaduto — in quel caso Drive viene segnato come "da
/// ricollegare" (Prompt 10, D) senza perdere la configurazione.
Future<void> _restoreCloudSession(
  HaccpRepository repository,
  SyncService sync,
) async {
  final provider = await repository.getSetting('cloud_provider');
  if (provider == 'gdrive' && (Platform.isAndroid || Platform.isIOS)) {
    final drive = GoogleDriveProvider();
    final connected = await drive.connect(interactive: false);
    if (connected) {
      sync.cloud = drive;
      await repository.setSetting('cloud_needs_reconnect', '');
      return;
    }
    // Configurazione conservata: solo avviso non bloccante.
    await repository.setSetting('cloud_needs_reconnect', '1');
  }
  // Provider "solo dispositivo": nessun collegamento da ripristinare.
  if (provider.isEmpty) {
    sync.cloud = null;
  }
}

class HaccpassApp extends StatelessWidget {
  const HaccpassApp({
    super.key,
    required this.services,
    required this.minimumSplash,
  });

  final Future<AppServices> services;
  final Future<void> minimumSplash;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HACCPass',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('it', 'IT')],
      locale: const Locale('it', 'IT'),
      scaffoldMessengerKey: rootMessengerKey,
      builder: (context, child) {
        // Barre di sistema coerenti col tema (edge-to-edge): icone scure su
        // sfondo chiaro e viceversa, barre trasparenti.
        final brightness = Theme.of(context).brightness;
        final dark = brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness:
                dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ),
          // Rispetta il ridimensionamento del testo di sistema,
          // limitandolo tra 0.9 e 1.15 per evitare rotture di layout.
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.15,
            child: child!,
          ),
        );
      },
      home: FutureBuilder<AppServices>(
        future: _waitForBoot(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _InAppSplash();
          }
          final loaded = snapshot.data!;
          return _Root(
            repository: loaded.repository,
            license: loaded.license,
            attachments: loaded.attachments,
            reminders: loaded.reminders,
            backup: loaded.backup,
            sync: loaded.sync,
          );
        },
      ),
    );
  }

  Future<AppServices> _waitForBoot() async {
    final loaded = await services;
    // Durata minima della splash: mai meno di 800 ms, mai bloccante
    // oltre il tempo di caricamento reale.
    await minimumSplash;
    return loaded;
  }
}

/// Splash in-app: logo con fade/scale di 400 ms mentre i servizi si
/// avviano. Rispetta l'impostazione di sistema "disattiva animazioni".
class _InAppSplash extends StatefulWidget {
  const _InAppSplash();

  @override
  State<_InAppSplash> createState() => _InAppSplashState();
}

class _InAppSplashState extends State<_InAppSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animationsDisabled =
        MediaQuery.disableAnimationsOf(context);
    final theme = Theme.of(context);

    final logo = Image.asset(
      'assets/images/logo.png',
      width: 160,
      height: 160,
      fit: BoxFit.contain,
      // Il logo \u00E8 RGB su fondo chiaro: in tema scuro resta in un
      // contenitore chiaro per garantire il contrasto.
    );

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Su fondo scuro il logo chiaro/su-bianco va incorniciato.
        theme.brightness == Brightness.dark
            ? Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: logo,
              )
            : logo,
        const SizedBox(height: 24),
        Text(
          'HACCPass',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );

    if (animationsDisabled) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(child: content),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Radice: wizard al primo avvio, poi shell con ripresa della coda cloud e
/// backup automatico giornaliero alla prima apertura utile.
class _Root extends StatefulWidget {
  const _Root({
    required this.repository,
    required this.license,
    required this.attachments,
    required this.reminders,
    required this.backup,
    required this.sync,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final AttachmentService attachments;
  final ReminderService reminders;
  final BackupService backup;
  final SyncService sync;

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> with WidgetsBindingObserver {
  var _onboarding = true;
  var _firstRunChoice = false;
  var _dailyBackupDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Sensori (Prompt 7): le letture BLE passano al repository, che salva
    // lo storico con throttling e retention. Nessuna scansione parte qui.
    SensorService.instance.attachSink(
      (sample) => unawaited(widget.repository.handleSensorReading(sample)),
    );
    // Allegati (Prompt 8): pulizia in background dei temporanei abbandonati
    // (registrazioni mai completate) più vecchi di 24 ore.
    unawaited(
      AttachmentService(repository: widget.repository)
          .cleanupStalePending(),
    );
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _onboarding = !await widget.repository.isOnboardingDone();
    // Prompt 12, §A: scelta "Nuova attività / Ripristina" SOLO al primo
    // avvio con database vuoto e scelta non ancora fatta.
    final choiceDone =
        await widget.repository.getSetting('first_run_choice_done') == '1';
    _firstRunChoice =
        _onboarding && !choiceDone && await widget.repository.isDatabaseEmpty();
    if (mounted) setState(() {});
    await _onAppResumed();

    // Promemoria: ricalcolati a ogni avvio (timezone e orari possono
    // cambiare).
    await widget.reminders.rescheduleAll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  /// Al ritorno in primo piano: svuota la coda di caricamento cloud,
  /// aggiorna l'ancora della prova (lastSeen / rilevamento orologio) e
  /// valuta il backup automatico giornaliero.
  Future<void> _onAppResumed() async {
    unawaited(widget.license.onAppResumed());
    await widget.sync.processQueue();
    await _maybeDailyBackup();
  }

  /// Scelta "Nuova attività" (o "Più tardi"): prosegue col wizard.
  Future<void> _startOnboardingFromChoice() async {
    await widget.repository.setSetting('first_run_choice_done', '1');
    if (mounted) setState(() => _firstRunChoice = false);
  }

  /// Scelta "Ripristina i miei dati": apre il wizard di ripristino
  /// (Prompt 12, §A).
  Future<void> _startRestoreFromChoice() async {
    await widget.repository.setSetting('first_run_choice_done', '1');
    if (!mounted) return;
    setState(() => _firstRunChoice = false);
    final result = await Navigator.of(context).push<RestoreResult>(
      MaterialPageRoute(
        builder: (_) => RestoreWizardScreen(
          repository: widget.repository,
          backup: widget.backup,
          license: widget.license,
          sync: widget.sync,
        ),
      ),
    );
    await _onRestoreFinished(result);
  }

  /// Dopo il ripristino: se il database ripristinato ha
  /// `onboarding_done = '1'` si apre direttamente la shell, altrimenti
  /// il wizard riprende dal passo salvato. I promemoria vengono
  /// riprogrammati sui dati ripristinati.
  Future<void> _onRestoreFinished(RestoreResult? result) async {
    if (result == null) return;
    await widget.reminders.rescheduleAll();
    if (!mounted) return;
    setState(() {
      _onboarding = !result.onboardingDone;
      _firstRunChoice = false;
    });
  }

  /// Backup automatico una volta al giorno, alla prima apertura utile,
  /// solo se un cloud collegato. Regole e protezioni (mai con database
  /// vuoto, mai prima della scelta del primo avvio, invito al ripristino
  /// se il cloud contiene gia backup) in [DailyBackupScheduler].
  Future<void> _maybeDailyBackup() async {
    if (_dailyBackupDone) return;
    final provider = widget.sync.cloud;
    if (provider == null || !provider.isConnected) return;

    final scheduler = DailyBackupScheduler(
      repository: widget.repository,
      backup: widget.backup,
    );
    final outcome = await scheduler.run(provider);
    if (outcome == DailyBackupOutcome.invitedToRestore) {
      _inviteToRestore();
    }
    if (outcome != DailyBackupOutcome.notDueYet &&
        outcome != DailyBackupOutcome.skippedNoCloud) {
      _dailyBackupDone = true;
    }
  }

  void _inviteToRestore() {
    rootMessengerKey.currentState?.showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 8),
        content: Text(
          'Il telefono non ha dati ma Google Drive contiene già dei backup: '
          'ripristinali da Altro → Documenti e backup → Ripristina da '
          'Google Drive.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_firstRunChoice) {
      return FirstRunChoiceScreen(
        onNewActivity: _startOnboardingFromChoice,
        onRestore: _startRestoreFromChoice,
      );
    }

    if (_onboarding) {
      return OnboardingScreen(
        repository: widget.repository,
        license: widget.license,
        attachments: widget.attachments,
        reminders: widget.reminders,
        sync: widget.sync,
        onFinished: () {
          setState(() => _onboarding = false);
          _maybeDailyBackup();
        },
      );
    }

    return AppShell(
      repository: widget.repository,
      license: widget.license,
      sync: widget.sync,
      backup: widget.backup,
      attachments: widget.attachments,
      reminders: widget.reminders,
    );
  }
}
