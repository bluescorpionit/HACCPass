import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'core/database/app_database.dart';
import 'core/theme/app_theme.dart';
import 'repositories/haccp_repository.dart';
import 'screens/app_shell.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'services/attachment_service.dart';
import 'services/backup_service.dart';
import 'services/cloud/google_drive_provider.dart';
import 'services/license_service.dart';
import 'services/printer_service.dart';
import 'services/reminder_service.dart';
import 'services/sync_service.dart';

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
    BlueHaccpApp(
      services: services,
      minimumSplash: minimumSplash,
      printerService: DemoPrinterService(),
    ),
  );
}

/// Ricollega il cloud salvato nelle impostazioni (senza riaprire l'OAuth se
/// la sessione \u00E8 ancora valida).
Future<void> _restoreCloudSession(
  HaccpRepository repository,
  SyncService sync,
) async {
  final provider = await repository.getSetting('cloud_provider');
  if (provider == 'gdrive' && (Platform.isAndroid || Platform.isIOS)) {
    final drive = GoogleDriveProvider();
    final connected = await drive.connect();
    if (connected) {
      sync.cloud = drive;
      return;
    }
  }
  // Provider "solo dispositivo": nessun collegamento da ripristinare.
  if (provider.isEmpty) {
    sync.cloud = null;
  }
}

class BlueHaccpApp extends StatelessWidget {
  const BlueHaccpApp({
    super.key,
    required this.services,
    required this.minimumSplash,
    required this.printerService,
  });

  final Future<AppServices> services;
  final Future<void> minimumSplash;
  final PrinterService printerService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Blue HACCP',
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
      builder: (context, child) {
        // Rispetta il ridimensionamento del testo di sistema,
        // limitandolo tra 0.9 e 1.3 per evitare overflow.
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.3,
          child: child!,
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
            printerService: printerService,
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
          'Blue HACCP',
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
    required this.printerService,
    required this.license,
    required this.attachments,
    required this.reminders,
    required this.backup,
    required this.sync,
  });

  final HaccpRepository repository;
  final PrinterService printerService;
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
  var _dailyBackupDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _onboarding = !await widget.repository.isOnboardingDone();
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

  /// Al ritorno in primo piano: svuota la coda di caricamento cloud.
  Future<void> _onAppResumed() async {
    await widget.sync.processQueue();
  }

  /// Backup automatico una volta al giorno, alla prima apertura utile,
  /// solo se un cloud \u00E8 collegato.
  Future<void> _maybeDailyBackup() async {
    if (_dailyBackupDone) return;
    final provider = widget.sync.cloud;
    if (provider == null || !provider.isConnected) return;

    final last = DateTime.tryParse(
      await widget.repository.getSetting('last_auto_backup_at'),
    );
    final now = DateTime.now();
    if (last != null &&
        now.difference(last).inHours < 24) {
      return;
    }

    _dailyBackupDone = true;
    try {
      // Il backup automatico non usa password (non pu\u00F2 chiederla in
      // automatico): resta protetto dall'account cloud del cliente. Il
      // backup manuale cifrato resta disponibile.
      final path = await widget.backup.createBackup();
      await widget.backup.uploadBackup(provider, path);
      await widget.repository.setSetting(
        'last_auto_backup_at',
        now.toIso8601String(),
      );
    } catch (_) {
      // Il backup automatico non deve mai interrompere l'uso dell'app.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_onboarding) {
      return OnboardingScreen(
        repository: widget.repository,
        license: widget.license,
        attachments: widget.attachments,
        reminders: widget.reminders,
        onFinished: () {
          setState(() => _onboarding = false);
          _maybeDailyBackup();
        },
      );
    }

    return AppShell(
      repository: widget.repository,
      printerService: widget.printerService,
      license: widget.license,
      sync: widget.sync,
      backup: widget.backup,
      attachments: widget.attachments,
      reminders: widget.reminders,
    );
  }
}
