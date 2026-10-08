import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/attachment_recovery_service.dart';
import '../../services/attachment_service.dart';
import '../../services/cloud/cloud_storage.dart';
import '../../widgets/common_widgets.dart';

/// "Recupero foto" (Prompt 12, §D.3): mostrata dopo un ripristino da
/// backup di solo database (e da "Spazio e allegati") quando mancano i
/// file locali delle foto.
///
/// Tre opzioni:
/// - **Scarica tutte ora**: progresso, annullabile, ripremibile;
/// - **Scarica quando servono**: le foto mancanti mostrano un segnaposto
///   "Scarica" e si scaricano al tocco;
/// - **Più tardi**: si può tornare da "Spazio e allegati".
///
/// Con la rete assente non va mai in errore: le foto restano "non
/// ancora scaricate".
class PhotoRecoveryScreen extends StatefulWidget {
  const PhotoRecoveryScreen({
    super.key,
    required this.repository,
    required this.cloud,
    this.recovery,
    this.onFinished,
  });

  final HaccpRepository repository;
  final CloudStorageProvider cloud;
  final AttachmentRecoveryService? recovery;
  final VoidCallback? onFinished;

  @override
  State<PhotoRecoveryScreen> createState() => _PhotoRecoveryScreenState();
}

class _PhotoRecoveryScreenState extends State<PhotoRecoveryScreen> {
  late final AttachmentRecoveryService _recovery;
  var _missing = 0;
  var _loading = true;
  var _running = false;
  var _done = 0;
  var _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _recovery = widget.recovery ??
        AttachmentRecoveryService(
          repository: widget.repository,
          cloud: widget.cloud,
          attachments: AttachmentService(repository: widget.repository),
        );
    _countMissing();
  }

  Future<void> _countMissing() async {
    try {
      final missing = await _recovery.missingLocalAttachments();
      if (mounted) {
        setState(() {
          _missing = missing.length;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadAll() async {
    setState(() {
      _running = true;
      _done = 0;
      _cancelled = false;
      _error = null;
    });
    try {
      final recovered = await _recovery.recoverAll(
        onProgress: (done, total) {
          if (mounted) setState(() => _done = done);
        },
        shouldCancel: () => _cancelled,
      );
      if (!mounted) return;
      setState(() {
        _running = false;
        _done = recovered;
        _missing = 0;
      });
    } catch (e) {
      // Il messaggio usa la traduzione del provider (es. rete assente).
      if (mounted) {
        setState(() {
          _running = false;
          _error = widget.cloud.humanError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _running
            ? _buildRunning(context)
            : _buildChoice(context);

    return PopScope(
      canPop: !_running,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Recupero foto'),
          automaticallyImplyLeading: !_running,
        ),
        body: SafeArea(child: body),
      ),
    );
  }

  Widget _buildChoice(BuildContext context) {
    final theme = Theme.of(context);
    if (_missing == 0) {
      return ListView(
        padding: screenPadding(context),
        children: [
          const SizedBox(height: 24),
          Icon(
            Icons.cloud_done_outlined,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text(
            'Tutte le foto sono sul telefono.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _close,
            child: const Text('Continua'),
          ),
        ],
      );
    }
    return ListView(
      padding: screenPadding(context),
      children: [
        PageHeader(
          title: '$_missing foto da recuperare',
          subtitle:
              'Il backup non includeva le foto. Sono al sicuro in Google '
              'Drive (cartella HACCPass/Foto) e puoi scaricarle adesso o '
              'quando servono.',
        ),
        if (_error != null) ...[
          Card(
            color: context.haccpColors.warningBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.wifi_off_outlined,
                      color: context.haccpColors.warning),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: _downloadAll,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: const Text('Scarica tutte ora'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 54,
          child: OutlinedButton.icon(
            onPressed: _close,
            icon: const Icon(Icons.touch_app_outlined),
            label: const Text('Scarica quando servono'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Le miniature mancanti mostrano un segnaposto "Scarica": '
          'toccalo e la foto arriva in quel momento.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: _close,
            child: const Text('Più tardi'),
          ),
        ),
      ],
    );
  }

  Widget _buildRunning(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: screenPadding(context),
      children: [
        const SizedBox(height: 24),
        CircularProgressIndicator(
          value: _missing == 0 ? null : (_done / _missing).clamp(0.0, 1.0),
        ),
        const SizedBox(height: 16),
        Text(
          'Recupero foto… $_done di $_missing',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Puoi interrompere: il recupero riprende da dove l\u2019hai '
          'lasciato (le foto già verificate non si riscaricano).',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => setState(() => _cancelled = true),
          child: const Text('Interrompi'),
        ),
      ],
    );
  }

  void _close() {
    widget.onFinished?.call();
    if (mounted) Navigator.of(context).pop();
  }
}
