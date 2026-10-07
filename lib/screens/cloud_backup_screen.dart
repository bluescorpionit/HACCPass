import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../repositories/haccp_repository.dart';
import '../services/backup_service.dart';
import '../services/cloud/cloud_storage.dart';
import '../services/cloud/google_drive_provider.dart';
import '../services/sync_service.dart';
import '../widgets/common_widgets.dart';

/// Schermata "Documenti e backup": stato del cloud, backup cifrato,
/// ripristino, coda di caricamento.
class CloudBackupScreen extends StatefulWidget {
  const CloudBackupScreen({
    super.key,
    required this.repository,
    required this.backup,
    required this.sync,
  });

  final HaccpRepository repository;
  final BackupService backup;
  final SyncService sync;

  @override
  State<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends State<CloudBackupScreen> {
  var busy = false;
  String status = '';
  List<CloudFile> remoteBackups = [];
  var needsReconnect = false;

  CloudStorageProvider get _provider => widget.sync.cloud ?? LocalFilesProvider();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final lastBackup = await widget.repository.getSetting('last_backup_at');
    final lastParsed = DateTime.tryParse(lastBackup);
    final queue = await widget.repository.getSyncQueue();
    final configured = await widget.repository.getSetting('cloud_provider');
    final flagged =
        await widget.repository.getSetting('cloud_needs_reconnect');
    if (!mounted) return;
    setState(() {
      status = lastParsed == null
          ? 'Mai eseguito'
          : 'Ultimo backup: ${fmtDateTime(lastParsed)}';
      _pendingCount = queue.length;
      needsReconnect = configured == 'gdrive' && flagged == '1';
    });
    if (_provider.isConnected) {
      try {
        remoteBackups =
            await _provider.list('Backup');
        if (mounted) setState(() {});
      } catch (_) {
        // Elenco non disponibile: la connessione verr\u00E0 ritentata.
      }
    }
  }

  var _pendingCount = 0;

  Future<void> _connect() async {
    setState(() => busy = true);
    try {
      final provider = GoogleDriveProvider();
      // Dal pulsante il collegamento PUÒ mostrare le finestre Google
      // (selettore account / consenso scope).
      final connected = await provider.connect(interactive: true);
      if (!connected) {
        final failure = provider.lastConnectError;
        final message = failure == null
            ? 'Collegamento a Google Drive non completato.'
            : provider.humanError(failure);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
          ),
        );
        return;
      }
      widget.sync.cloud = provider;
      await widget.repository.setSetting('cloud_provider', provider.id);
      await widget.repository.setSetting('cloud_account', provider.accountLabel ?? '');
      await widget.repository.setSetting('cloud_needs_reconnect', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Google Drive collegato (${provider.accountLabel ?? ''}). '
              'Verr\u00E0 creata la cartella \u201CHACCPass\u201D.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
      _refresh();
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Scollegare il cloud?'),
        content: const Text(
          'I token di accesso vengono revocati e le credenziali cancellate. '
          'I file gi\u00E0 salvati nel tuo cloud restano al loro posto.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Scollega'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _provider.disconnect();
    widget.sync.cloud = null;
    await widget.repository.setSetting('cloud_provider', '');
    await widget.repository.setSetting('cloud_account', '');
    _refresh();
  }

  Future<void> _backupNow() async {
    setState(() => busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final originBox = context.findRenderObject() as RenderBox?;
    try {
      final encrypted = await widget.repository.getSetting('backup_encrypted') == '1';
      String? password;
      if (encrypted) {
        password = await _askPassword();
        if (password == null) return;
      }

      final path = await widget.backup.createBackup(password: password);
      await widget.repository.setSetting(
        'last_backup_at',
        DateTime.now().toIso8601String(),
      );

      if (_provider.isConnected) {
        await widget.backup.uploadBackup(
          _provider,
          path,
          onProgress: (message) => setState(() => status = message),
        );
        await widget.sync.processQueue();
      } else {
        // Nessun cloud: foglio di condivisione (Salva con nome).
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(path)],
            sharePositionOrigin: originBox != null
                ? originBox.localToGlobal(Offset.zero) & originBox.size
                : null,
          ),
        );
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('Backup completato.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is BackupException ? e.message : 'Backup non riuscito: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
      _refresh();
    }
  }

  /// Backup COMPLETO con allegati (Prompt 8, B4): streaming su disco, con
  /// progresso e annullamento. NON cifrabile (dichiarato all'utente): la
  /// cifratura attuale richiederebbe l'archivio intero in memoria.
  Future<void> _fullBackupNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final originBox = context.findRenderObject() as RenderBox?;
    var cancelled = false;
    try {
      final path = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return _FullBackupDialog(
            onCreated: (file) => Navigator.pop(dialogContext, file),
            onCancel: () {
              cancelled = true;
              Navigator.pop(dialogContext);
            },
            backup: widget.backup,
          );
        },
      );
      if (cancelled) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Backup completo annullato.')),
        );
        return;
      }
      if (path == null || !mounted) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          sharePositionOrigin: originBox != null
              ? originBox.localToGlobal(Offset.zero) & originBox.size
              : null,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Backup completo non riuscito: $e')),
      );
    }
  }

  Future<String?> _askPassword() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Password del backup'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (non recuperabile se dimenticata)',
          ),
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

  Future<void> _restore({CloudFile? remote}) async {
    final messenger = ScaffoldMessenger.of(context);
    String? path;
    if (remote != null) {
      setState(() => busy = true);
      try {
        final tempDir = await Directory.systemTemp.createTemp('bh_download');
        path = '${tempDir.path}/${remote.name}';
        await _provider.download(remote.id, path);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(_provider.humanError(e))),
          );
        }
        return;
      } finally {
        if (mounted) setState(() => busy = false);
      }
    } else {
      final picked = await FilePicker.platform.pickFiles();
      path = picked?.files.single.path;
    }
    if (path == null) return;

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ripristinare il backup?'),
        content: const Text(
          'I dati attuali verranno sostituiti. Prima del ripristino viene '
          'creato automaticamente un backup di sicurezza.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Ripristina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => busy = true);
    try {
      final content = await _readWithPasswordIfNeeded(path);
      if (content == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Ripristino annullato.')),
        );
        return;
      }
      await widget.backup.restoreBackup(
        content,
        onProgress: (message) => setState(() => status = message),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Backup ripristinato.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(e is BackupException ? e.message : 'Ripristino non riuscito: $e')),
      );
    } finally {
      if (mounted) setState(() => busy = false);
      _refresh();
    }
  }

  /// Legge il backup chiedendo la password se serve (con un secondo
  /// tentativo se la prima \u00E8 errata). Null = annullato dall\u2019utente.
  Future<BackupContent?> _readWithPasswordIfNeeded(String path) async {
    try {
      return await widget.backup.readBackup(path);
    } on BackupException catch (e) {
      if (!e.message.contains('password')) rethrow;
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final password = await _askPassword();
      if (password == null || password.isEmpty) return null;
      try {
        return await widget.backup.readBackup(path, password: password);
      } on BackupException catch (e) {
        if (!e.message.contains('Password errata')) rethrow;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password errata, riprova.')),
          );
        }
      }
    }
    return null;
  }

  Future<void> _processQueue() async {
    setState(() => busy = true);
    try {
      final uploaded = await widget.sync.processQueue();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$uploaded file caricati nel cloud.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = _provider.isConnected;

    return Scaffold(
      appBar: AppBar(title: const Text('Documenti e backup')),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: screenPadding(context),
              children: [
                PageHeader(
                  title: 'I tuoi dati, il tuo cloud',
                  subtitle:
                      'Locale sempre disponibile. Il cloud \u00E8 facoltativo: '
                      'i file vanno nel tuo Google Drive, mai su server '
                      'dello sviluppatore.',
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              connected
                                  ? Icons.cloud_done_outlined
                                  : Icons.cloud_off_outlined,
                              color: connected
                                  ? context.haccpColors.success
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                connected
                                    ? 'Collegato: ${_provider.label}'
                                    : 'Nessun cloud collegato',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                        if (connected) ...[
                          const SizedBox(height: 4),
                          Text(_provider.accountLabel ?? ''),
                        ],
                        const SizedBox(height: 6),
                        Text(status),
                        if (needsReconnect && !connected) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.sync_problem,
                                size: 18,
                                color: theme.colorScheme.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Google Drive da ricollegare: il '
                                  'collegamento automatico all\u2019avvio non '
                                  '\u00E8 riuscito (token scaduto o rete '
                                  'assente). La configurazione \u00E8 intatta: '
                                  'premi "Collega Google Drive".',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_pendingCount > 0) ...[
                          const SizedBox(height: 4),
                          Text('In attesa di caricamento: $_pendingCount file'),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _backupNow,
                    icon: const Icon(Icons.backup_outlined),
                    label: const Text('Esegui backup ora'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Il backup del database NON include le foto e i PDF: per '
                  'quelli usa Google Drive o il backup completo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _fullBackupNow,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Backup completo con allegati'),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Database + tutte le foto, scritto un file alla volta '
                  '(sicuro anche con migliaia di foto). Non \u00E8 cifrabile.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 10),
                if (connected) ...[
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _disconnect,
                      icon: const Icon(Icons.link_off),
                      label: Text(
                          'Scollega ${_provider.label}'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _connect,
                      icon: const Icon(Icons.cloud_outlined),
                      label: const Text('Collega Google Drive'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: () => _restore(),
                    icon: const Icon(Icons.restore),
                    label: const Text('Ripristina da file'),
                  ),
                ),
                if (_pendingCount > 0) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _processQueue,
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text('Carica ora ($_pendingCount in coda)'),
                    ),
                  ),
                ],
                const SectionTitle('Backup nel cloud'),
                if (!connected)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                          'Collega il cloud per vedere e ripristinare i '
                          'backup salvati.'),
                    ),
                  )
                else if (remoteBackups.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Nessun backup nel cloud per ora.'),
                    ),
                  )
                else
                  for (final file in remoteBackups.take(14))
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.archive_outlined),
                        title: Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          file.modifiedAt == null
                              ? ''
                              : fmtDateTime(file.modifiedAt!),
                        ),
                        trailing: OutlinedButton(
                          onPressed: () => _restore(remote: file),
                          child: const Text('Ripristina'),
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Backup automatico una volta al giorno alla prima '
                      'apertura con il cloud collegato; in cloud si '
                      'conservano gli ultimi ${BackupService.keepCount}. '
                      'Prima di ogni ripristino viene creato un backup di '
                      'sicurezza. Un\u2019attivit\u00E0 = un dispositivo '
                      'principale: gli altri possono ripristinare un backup.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}


/// Dialog di avanzamento del backup completo (streaming, annullabile).
class _FullBackupDialog extends StatefulWidget {
  const _FullBackupDialog({
    required this.backup,
    required this.onCreated,
    required this.onCancel,
  });

  final BackupService backup;
  final ValueChanged<String> onCreated;
  final VoidCallback onCancel;

  @override
  State<_FullBackupDialog> createState() => _FullBackupDialogState();
}

class _FullBackupDialogState extends State<_FullBackupDialog> {
  String _status = 'Preparazione...';
  var _cancelled = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final path = await widget.backup.createFullBackup(
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _status =
                'Scrittura file \$done di \$total (streaming, senza carico di memoria)...');
          }
        },
        shouldCancel: () => _cancelled,
      );
      if (_cancelled) {
        widget.onCancel();
        return;
      }
      if (path != null) widget.onCreated(path);
    } catch (_) {
      widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup completo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('Annulla'),
        ),
      ],
    );
  }
}