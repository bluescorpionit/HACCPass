import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../repositories/haccp_repository.dart';
import '../services/attachment_recovery_service.dart';
import '../services/attachment_service.dart' show formatBytes;
import '../services/backup_service.dart';
import '../services/cloud/cloud_storage.dart';
import '../services/cloud/google_drive_provider.dart';
import '../services/license_service.dart';
import '../services/restore_service.dart';
import '../services/storage_space.dart';
import '../services/sync_service.dart';
import '../widgets/common_widgets.dart';
import 'recovery/photo_recovery_screen.dart';

/// Wizard di ripristino (Prompt 12, §A): Google Drive (principale),
/// file dal telefono e, su iOS, File e iCloud Drive. Riusabile dal primo
/// avvio e da Altro → Documenti e backup.
///
/// All'uscita fa `Navigator.pop(context, RestoreResult?)`: il chiamante
/// decide se aprire la shell (onboarding completato) o riprendere il
/// wizard.
class RestoreWizardScreen extends StatefulWidget {
  const RestoreWizardScreen({
    super.key,
    required this.repository,
    required this.backup,
    required this.license,
    required this.sync,
    this.driveProvider,
    this.restoreService,
    this.freeSpace = StorageSpace.freeBytes,
    this.pickFile = _defaultPickFile,
  });

  final HaccpRepository repository;
  final BackupService backup;
  final LicenseService license;
  final SyncService sync;

  /// Provider Drive iniettabile per i test.
  final CloudStorageProvider? driveProvider;

  /// Servizio di ripristino iniettabile per i test.
  final RestoreService? restoreService;

  /// Spazio libero (byte) nel volume del percorso; null se non
  /// determinabile: in quel caso si gestisce l'errore di scrittura.
  final Future<int?> Function(String path) freeSpace;

  /// Selettore file di sistema (FilePicker): su Android apre anche i
  /// documenti di Drive, su iOS l'app File con iCloud Drive.
  final Future<String?> Function() pickFile;

  static Future<String?> _defaultPickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    return result?.files.single.path;
  }

  @override
  State<RestoreWizardScreen> createState() => _RestoreWizardScreenState();
}

enum _Stage {
  source,
  driveIntro,
  list,
  downloading,
  summary,
  restoring,
  restored,
}

class _RestoreWizardScreenState extends State<RestoreWizardScreen> {
  _Stage _stage = _Stage.source;
  CloudStorageProvider? _drive;
  String? _driveError;
  bool _dbEmptyAtStart = true;

  final _entries = <_BackupEntry>[];
  _BackupEntry? _selected;
  bool _loadingList = false;
  String? _listError;

  int _downloaded = 0;
  int? _downloadTotal;
  bool _cancelRequested = false;

  BackupHandle? _handle;
  String? _pendingPath;
  String? _password;
  bool _pendingPathIsTemp = false;

  RestoreProgress? _restoreProgress;
  String? _restoreError;
  RestoreResult? _result;

  Directory? _downloadDir;

  @override
  void initState() {
    super.initState();
    widget.repository.isDatabaseEmpty().then((empty) {
      if (mounted) setState(() => _dbEmptyAtStart = empty);
    });
  }

  @override
  void dispose() {
    _handle?.dispose();
    final dir = _downloadDir;
    if (dir != null) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {
        // Best effort.
      }
    }
    super.dispose();
  }

  CloudStorageProvider get _provider =>
      widget.driveProvider ?? _drive ?? GoogleDriveProvider();

  // -------------------------------------------------------------------------
  // Sorgente
  // -------------------------------------------------------------------------

  Future<void> _chooseDrive() async {
    setState(() => _stage = _Stage.driveIntro);
  }

  Future<void> _connectDrive() async {
    final provider = _provider;
    setState(() => _driveError = null);
    var connected = false;
    Object? error;
    try {
      connected = await provider.connect(interactive: true);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    if (!connected) {
      setState(() {
        _driveError = error != null
            ? provider.humanError(error)
            : provider is GoogleDriveProvider &&
                    provider.lastConnectError != null
                ? provider.humanError(provider.lastConnectError!)
                : 'Collegamento a Google Drive non completato.';
      });
      return;
    }
    _drive = provider;
    await _loadBackups(provider);
  }

  Future<void> _loadBackups(CloudStorageProvider provider) async {
    setState(() {
      _loadingList = true;
      _listError = null;
      _stage = _Stage.list;
    });
    try {
      final files = await provider.list('Backup');
      final backups = files
          .where((f) =>
              f.name.startsWith(BackupService.backupPrefix) &&
              f.name.endsWith('.bhb'))
          .toList()
        ..sort((a, b) => backupSortDate(b).compareTo(backupSortDate(a)));
      final entries = <_BackupEntry>[];
      for (final file in backups.take(30)) {
        final header = await provider.peekFirstBytes(file.id, 4);
        final encrypted = header == null
            ? null
            : utf8LikeDecode(header) == BackupService.magicV1 ||
                utf8LikeDecode(header) == BackupService.magicV2;
        entries.add(_BackupEntry(file: file, encrypted: encrypted));
      }
      if (!mounted) return;
      setState(() {
        _entries
          ..clear()
          ..addAll(entries);
        _loadingList = false;
        // Preseleziona il più recente.
        _selected = entries.isEmpty ? null : entries.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError = provider.humanError(e);
      });
    }
  }

  /// Solo i file creati dall'app sono visibili con lo scope `drive.file`.
  Future<void> _fallbackToFilePicker() async {
    final path = await widget.pickFile();
    if (path == null || !mounted) return;
    await _openLocalFile(path);
  }

  Future<void> _openLocalFile(String path) async {
    final ok = await _checkSpaceFor(path);
    if (!ok) return;
    await _openHandleFor(path, isTemp: false);
  }

  // -------------------------------------------------------------------------
  // Scaricamento, password, riepilogo
  // -------------------------------------------------------------------------

  /// Controllo dello spazio libero PRIMA di scaricare: serve almeno 2,5×
  /// la dimensione del file (file + estrazione + backup di sicurezza).
  Future<bool> _checkSpaceFor(String path) async {
    int? size;
    try {
      size = await File(path).length();
    } catch (_) {
      return true;
    }
    return _checkSpaceSize(size);
  }

  Future<bool> _checkSpaceSize(int size) async {
    final required = (size * 2.5).round();
    final free = await widget.freeSpace(Directory.systemTemp.path);
    if (free == null) return true;
    if (free < required) {
      if (!mounted) return false;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Spazio insufficiente'),
          content: Text(
            'Per ripristinare questo backup servono almeno '
            '${formatBytes(required)} liberi nel telefono (file + '
            'estrazione). Ora ne sono disponibili '
            '${formatBytes(free)}. Libera spazio e riprova.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Ho capito'),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _startDownload() async {
    final entry = _selected;
    if (entry == null) return;
    final size = entry.file.size;
    if (size != null && !await _checkSpaceSize(size)) return;

    setState(() {
      _stage = _Stage.downloading;
      _downloaded = 0;
      _downloadTotal = size;
      _cancelRequested = false;
    });
    final provider = _provider;
    final dir = await Directory.systemTemp.createTemp('bh_download');
    _downloadDir = dir;
    final destination = p.join(dir.path, entry.file.name);
    try {
      await provider.download(
        entry.file.id,
        destination,
        onProgress: (downloaded, total) {
          if (mounted) {
            setState(() {
              _downloaded = downloaded;
              _downloadTotal = total ?? size;
            });
          }
        },
        shouldCancel: () => _cancelRequested,
      );
    } on CloudDownloadCancelled {
      await _cleanupDownload();
      if (mounted) setState(() => _stage = _Stage.list);
      return;
    } catch (e) {
      await _cleanupDownload();
      if (mounted) {
        setState(() => _stage = _Stage.list);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.humanError(e))),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.summary);
    await _openHandleFor(destination, isTemp: true);
  }

  Future<void> _cleanupDownload() async {
    final dir = _downloadDir;
    _downloadDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Apre il backup chiedendo la password se serve (fino a 3 tentativi,
  /// poi esce senza modifiche). Mostra il riepilogo prima di sostituire
  /// i dati.
  Future<void> _openHandleFor(String path, {required bool isTemp}) async {
    _pendingPath = path;
    _pendingPathIsTemp = isTemp;
    var password = _password;
    for (var attempt = 0; attempt < 3; attempt++) {
      BackupHandle handle;
      try {
        handle = await widget.backup.openBackup(path, password: password);
      } on BackupException catch (e) {
        final needsPassword =
            e.message.contains('password') || e.message.contains('Password');
        if (!needsPassword) {
          await _abortOpen(e.message);
          return;
        }
        password = await _askPassword(attempt);
        if (password == null || password.isEmpty) {
          await _abortOpen(null);
          return;
        }
        _password = password;
        continue;
      }
      await _handle?.dispose();
      _handle = handle;
      if (mounted) setState(() => _stage = _Stage.summary);
      return;
    }
    await _abortOpen(
      'Troppi tentativi con la password: ripristino annullato, nessun '
      'dato è stato modificato.',
    );
  }

  Future<void> _abortOpen(String? message) async {
    if (_pendingPathIsTemp) await _cleanupDownload();
    _pendingPath = null;
    _password = null;
    if (!mounted) return;
    setState(() => _stage = _Stage.list);
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Future<String?> _askPassword(int attempt) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: attempt == 0,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Password del backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              attempt == 0
                  ? 'Questo backup è protetto da password.'
                  : 'Password errata. Tentativo ${attempt + 1} di 3.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Password (non recuperabile se dimenticata)',
              ),
              onSubmitted: (value) => Navigator.pop(dialogContext, value),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Continua'),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Ripristino
  // -------------------------------------------------------------------------

  Future<void> _startRestore() async {
    final handle = _handle;
    final path = _pendingPath;
    if (handle == null || path == null) return;
    final service = widget.restoreService ??
        RestoreService(repository: widget.repository, backup: widget.backup);

    setState(() {
      _stage = _Stage.restoring;
      _restoreError = null;
      _restoreProgress = const RestoreProgress(
        phase: RestorePhase.opening,
        message: 'Preparazione…',
      );
    });
    try {
      final result = await service.restoreFromFile(
        path,
        password: _password,
        onProgress: (progress) {
          if (mounted) setState(() => _restoreProgress = progress);
        },
        shouldCancel: () => false,
      );
      _result = result;

      // Il provider collegato ADESSO diventa il cloud dell'app (non
      // quello del telefono di origine, §A).
      if (_drive != null) {
        widget.sync.cloud = _drive;
        await widget.repository.setSetting('cloud_provider', _drive!.id);
        await widget.repository
            .setSetting('cloud_account', _drive!.accountLabel ?? '');
        await widget.repository.setSetting('cloud_needs_reconnect', '');
      }
      await widget.license.reloadAfterRestore();

      if (!mounted) return;
      setState(() => _stage = _Stage.restored);
    } on BackupCancelledException {
      await _afterFailedRestore('Ripristino annullato: nessuna modifica.');
    } catch (e) {
      await _afterFailedRestore(
        e is BackupException ? e.message : 'Ripristino non riuscito: $e',
      );
    }
  }

  Future<void> _afterFailedRestore(String message) async {
    if (_pendingPathIsTemp) await _cleanupDownload();
    _pendingPath = null;
    _password = null;
    await _handle?.dispose();
    _handle = null;
    if (!mounted) return;
    setState(() {
      _stage = _Stage.list;
      _restoreError = message;
    });
  }

  /// Chiusura dopo il ripristino: se mancano foto con il cloud collegato
  /// propone il recupero, poi esce con il risultato.
  Future<void> _finish() async {
    final result = _result;
    if (result != null) {
      final provider = _drive;
      var hasMissingPhotos = false;
      if (provider != null && provider.isConnected) {
        final recovery = AttachmentRecoveryService(
          repository: widget.repository,
          cloud: provider,
        );
        hasMissingPhotos =
            (await recovery.missingLocalAttachments()).isNotEmpty;
      }
      if (hasMissingPhotos && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PhotoRecoveryScreen(
              repository: widget.repository,
              cloud: provider!,
            ),
          ),
        );
      }
    }
    if (_pendingPathIsTemp) await _cleanupDownload();
    await _handle?.dispose();
    _handle = null;
    if (!mounted) return;
    Navigator.of(context).pop(_result);
  }

  // -------------------------------------------------------------------------
  // Interfaccia
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = switch (_stage) {
      _Stage.source => _buildSource(context),
      _Stage.driveIntro => _buildDriveIntro(context),
      _Stage.list => _buildList(context),
      _Stage.downloading => _buildDownloading(context),
      _Stage.summary => _buildSummary(context),
      _Stage.restoring => _buildRestoring(context),
      _Stage.restored => _buildRestored(context),
    };

    return PopScope(
      canPop: _stage != _Stage.restoring,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Ripristina i tuoi dati'),
          automaticallyImplyLeading: _stage != _Stage.restoring,
        ),
        body: SafeArea(
          child: ListView(
            padding: screenPadding(context),
            children: [
              if (_stage != _Stage.restored) ...[
                _StageProgressIndicator(stage: _stage),
                const SizedBox(height: 16),
              ],
              content,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSource(BuildContext context) {
    final theme = Theme.of(context);
    final onIOS = !kIsWeb && Platform.isIOS;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Da dove ripristino?',
          subtitle:
              'Scegli un backup di HACCPass: i dati attuali (vuoti) verranno '
              'sostituiti. Prima viene comunque creato un backup di '
              'sicurezza.',
        ),
        _SourceCard(
          icon: Icons.cloud_outlined,
          title: 'Google Drive',
          subtitle:
              'Consigliato: elenca i backup nella cartella HACCPass/Backup '
              'del tuo Drive.',
          emphasized: true,
          onTap: _chooseDrive,
        ),
        const SizedBox(height: 12),
        _SourceCard(
          icon: Icons.folder_outlined,
          title: onIOS ? 'File e iCloud Drive' : 'File dal telefono',
          subtitle: onIOS
              ? 'Selettore File di sistema: include iCloud Drive.'
              : 'Selettore di sistema: include anche i documenti di Drive.',
          onTap: () async {
            final path = await widget.pickFile();
            if (path != null && mounted) await _openLocalFile(path);
          },
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Il ripristino non tocca mai la licenza di questo telefono, '
              'né i token degli account. I backup completi con le foto non '
              'sono cifrabili: solo i backup del database possono essere '
              'protetti da password.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDriveIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Collega Google Drive',
          subtitle:
              'Si apre l\u2019accesso Google. L\u2019app vede solo i file '
              'creati da HACCPass nella cartella HACCPass del tuo Drive: '
              'nessun altro file, nessun invio di dati.',
        ),
        if (_driveError != null) ...[
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_driveError!),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _connectDrive,
            icon: const Icon(Icons.link),
            label: const Text('Collega Google Drive'),
          ),
        ),
        const SizedBox(height: 10),
        TextButton(
          onPressed: _fallbackToFilePicker,
          child: const Text('Oppure scegli un file dal telefono'),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    if (_loadingList) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_listError != null) {
      return Column(
        children: [
          Text(_listError!, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _loadBackups(_provider),
            child: const Text('Riprova'),
          ),
        ],
      );
    }
    if (_entries.isEmpty) {
      // §A.3: cartella vuota o non visibile con lo scope drive.file.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.search_off,
            size: 44,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'Nessun backup trovato con questo account.',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Con l\u2019accesso ridotto di HACCPass (drive.file) vengono '
            'mostrati solo i backup creati da HACCPass. Puoi scegliere un '
            'file dal telefono o dal tuo Drive con il selettore di '
            'sistema.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 54,
            child: FilledButton.tonalIcon(
              onPressed: _fallbackToFilePicker,
              icon: const Icon(Icons.folder_open),
              label: const Text('Scegli un file…'),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_restoreError != null) ...[
          Card(
            color: theme.colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_restoreError!),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final entry in _entries)
          Card(
            color: _selected == entry
                ? theme.colorScheme.primaryContainer
                : null,
            child: ListTile(
              leading: _encryptedIcon(entry, theme),
              title: Text(
                entry.isFull ? 'Completo con foto' : 'Solo dati',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                '${fmtDateTime(entry.sortDate)}'
                '${entry.file.size == null ? '' : ' • ${formatBytes(entry.file.size!)}'}'
                '${entry.encrypted == true ? ' • Cifrato' : ''}',
              ),
              trailing: _selected == entry
                  ? const Icon(Icons.check_circle)
                  : null,
              onTap: () => setState(() => _selected = entry),
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _selected == null ? null : _startDownload,
            icon: const Icon(Icons.restore),
            label: const Text('Ripristina questo backup'),
          ),
        ),
      ],
    );
  }

  Widget? _encryptedIcon(_BackupEntry entry, ThemeData theme) {
    if (entry.encrypted == true) {
      return Icon(Icons.lock_outline, color: theme.colorScheme.primary);
    }
    if (entry.encrypted == null) return const Icon(Icons.help_outline);
    return entry.isFull
        ? const Icon(Icons.photo_library_outlined)
        : const Icon(Icons.archive_outlined);
  }

  Widget _buildDownloading(BuildContext context) {
    final theme = Theme.of(context);
    final total = _downloadTotal;
    final value = total == null || total == 0
        ? null
        : (_downloaded / total).clamp(0.0, 1.0);
    return Column(
      children: [
        CircularProgressIndicator(value: value),
        const SizedBox(height: 16),
        Text(
          total == null
              ? 'Scarico il backup…'
              : 'Scarico il backup… ${formatBytes(_downloaded)} di '
                  '${formatBytes(total)}',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => setState(() => _cancelRequested = true),
          child: const Text('Annulla'),
        ),
      ],
    );
  }

  Widget _buildSummary(BuildContext context) {
    final handle = _handle;
    if (handle == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final createdAt = handle.createdAt;
    final dbEmpty = _dbEmptyAtStart;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: 'Riepilogo prima di sostituire',
          subtitle:
              'Controlla che sia il backup giusto: i dati attuali '
              'dell\u2019app verranno sostituiti.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SummaryRow(
                  label: 'Backup del',
                  value: createdAt == null ? '—' : fmtDateTime(createdAt),
                ),
                _SummaryRow(
                  label: 'Tipo',
                  value: handle.hasAttachments
                      ? 'Completo con foto '
                          '(${handle.attachmentsCount ?? '?'} file)'
                      : 'Solo dati (le foto si recuperano dopo)',
                ),
                _SummaryRow(
                  label: 'Versione app',
                  value: handle.appVersion ?? '—',
                ),
                _SummaryRow(
                  label: 'Versione dati',
                  value: 'schema ${handle.schemaVersion}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: context.haccpColors.warningBg,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              dbEmpty
                  ? 'I dati attuali dell\u2019app (vuoti) verranno '
                      'sostituiti. Prima viene comunque creato un backup '
                      'di sicurezza.'
                  : 'I dati attuali dell\u2019app verranno sostituiti. '
                      'Prima viene creato un backup di sicurezza.',
              style: TextStyle(color: context.haccpColors.warning),
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _startRestore,
            icon: const Icon(Icons.restore),
            label: const Text('Ripristina ora'),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await _abortOpen(null);
          },
          child: const Text('Annulla'),
        ),
      ],
    );
  }

  Widget _buildRestoring(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _restoreProgress;
    final phase = progress?.phase ?? RestorePhase.opening;
    final total = progress?.total;
    final done = progress?.done;
    final value = total == null || total == 0
        ? null
        : (done! / total).clamp(0.0, 1.0);
    return Column(
      children: [
        CircularProgressIndicator(value: value),
        const SizedBox(height: 16),
        Text(
          phase.label,
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          progress?.message ?? '',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (_restoreError != null) ...[
          const SizedBox(height: 12),
          Text(_restoreError!, style: TextStyle(color: theme.colorScheme.error)),
        ],
      ],
    );
  }

  Widget _buildRestored(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: context.haccpColors.success,
        ),
        const SizedBox(height: 12),
        Text(
          'Ripristino completato',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          result == null
              ? ''
              : '${result.attachmentsRestored} allegati ripristinati dal '
                  'file di backup.\n'
                  'Un backup di sicurezza dei dati precedenti è in:\n'
                  '${result.safetyBackupPath}',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 54,
          child: FilledButton(
            onPressed: _finish,
            child: const Text('Continua'),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: emphasized ? theme.colorScheme.primaryContainer : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 30,
                color: emphasized
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: emphasized
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: emphasized
                            ? theme.colorScheme.onPrimaryContainer
                                .withValues(alpha: 0.85)
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: emphasized
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Indicatore dei passi del wizard: Scegli → Scarica → Ripristina.
class _StageProgressIndicator extends StatelessWidget {
  const _StageProgressIndicator({required this.stage});

  final _Stage stage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = [
      ('Scegli', stage.index >= 0),
      ('Scarica', stage.index >= _Stage.downloading.index),
      ('Ripristina', stage.index >= _Stage.restoring.index),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          Icon(
            steps[i].$2 ? Icons.check_circle : Icons.radio_button_off,
            size: 18,
            color: steps[i].$2
                ? theme.colorScheme.primary
                : theme.colorScheme.outline,
          ),
          const SizedBox(width: 4),
          Text(
            steps[i].$1,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight:
                  steps[i].$2 ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
          if (i < steps.length - 1) ...[
            const SizedBox(width: 6),
            const Expanded(child: Divider()),
            const SizedBox(width: 6),
          ],
        ],
      ],
    );
  }
}

class _BackupEntry {
  _BackupEntry({required this.file, this.encrypted});

  final CloudFile file;
  final bool? encrypted;

  bool get isFull => file.name.startsWith(BackupService.fullBackupPrefix);

  DateTime get sortDate => backupSortDate(file);
}

String utf8LikeDecode(List<int> bytes) {
  return String.fromCharCodes(bytes);
}
