import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/attachment_service.dart';
import '../../services/cloud/cloud_storage.dart';
import '../../widgets/common_widgets.dart';

/// Prompt 8, B2: "Spazio e allegati" (Altro → Backup/Archivio).
///
/// Mostra spazio usato, numero file, ripartizione per anno, i 20 file più
/// grandi e quanti allegati NON sono ancora al sicuro (nessun cloud).
/// Profili di qualità foto, "Libera spazio" (solo file verificati sul
/// cloud, con miniatura e riferimento conservati), conservazione
/// (predefinita "Mai") e riparazione file orfani.
class AttachmentStorageScreen extends StatefulWidget {
  const AttachmentStorageScreen({
    super.key,
    required this.repository,
    required this.attachments,
    this.cloud,
  });

  final HaccpRepository repository;
  final AttachmentService attachments;
  final CloudStorageProvider? cloud;

  @override
  State<AttachmentStorageScreen> createState() =>
      _AttachmentStorageScreenState();
}

class _AttachmentStorageScreenState extends State<AttachmentStorageScreen> {
  static const _statsTimeout = Duration(seconds: 12);
  static const _largestTimeout = Duration(seconds: 12);
  Future<AttachmentStorageStats>? _stats;
  Future<List<Attachment>>? _largest;

  @override
  void initState() {
    super.initState();
    _reload();
    // Pulizia all'avvio della schermata: pending temporanei > 24 h.
    widget.attachments.cleanupStalePending();
  }

  void _reload() {
    setState(() {
      _stats = widget.attachments.storageStats().timeout(_statsTimeout);
      _largest = widget.attachments
          .largestLocalAttachments()
          .timeout(_largestTimeout);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FeatureScaffold(
      title: 'Spazio e allegati',
      subtitle:
          'Le foto vivono nella memoria del telefono (cartella privata '
          'dell\u2019app): senza backup o Google Drive si perdono con il '
          'telefono.',
      body: FutureBuilder<AttachmentStorageStats>(
        future: _stats,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final isTimeout = snapshot.error is TimeoutException;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTimeout
                          ? 'Il calcolo dello spazio sta richiedendo troppo '
                              'tempo.'
                          : 'Impossibile calcolare lo spazio allegati.',
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Riprova'),
                    ),
                  ],
                ),
              ),
            );
          }
          final stats = snapshot.data!;
          final years = stats.byYear.entries.toList()
            ..sort((a, b) => b.key.compareTo(a.key));
          final cloudConnected = widget.cloud != null;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${formatBytes(stats.totalBytes)} \u2022 '
                        '${stats.fileCount} file',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Per anno: '
                        '${years.isEmpty ? '\u2014' : years.map((e) => '${e.key}: ${formatBytes(e.value)}').join(' \u2022 ')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Attachment>>(
                        future: _largest,
                        builder: (context, largestSnapshot) {
                          final (icon, text, type) = switch (
                              largestSnapshot.connectionState) {
                            ConnectionState.done when largestSnapshot.hasError =>
                              (
                                Icons.error_outline,
                                'Top 20 non disponibili (tocca Riprova sotto)',
                                StatusType.warning
                              ),
                            ConnectionState.done => (
                                Icons.check_circle_outline,
                                'Top 20 pronti',
                                StatusType.success,
                              ),
                            _ => (
                                Icons.hourglass_top_outlined,
                                'Top 20 in caricamento…',
                                StatusType.info,
                              ),
                          };
                          return Row(
                            children: [
                              Icon(
                                icon,
                                size: 16,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: StatusPill(
                                  text: text,
                                  type: type,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      if (stats.notSyncedCount > 0) ...[
                        const SizedBox(height: 8),
                        StatusPill(
                          text: '${stats.notSyncedCount} allegati solo su '
                              'questo telefono',
                          type: StatusType.warning,
                          large: true,
                        ),
                      ],
                      if (!cloudConnected) ...[
                        const SizedBox(height: 8),
                        const StatusPill(
                          text: 'Gli allegati sono solo su questo telefono. '
                              'Collega Google Drive per metterli al sicuro.',
                          type: StatusType.info,
                          large: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const SectionTitle('Qualità delle nuove foto'),
              _QualitySelector(
                attachments: widget.attachments,
                onChanged: _reload,
              ),
              const SectionTitle('Libera spazio'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Elimina i FILE LOCALI degli allegati più vecchi '
                        '(a scelta 6/12/24 mesi) GIÀ caricati e verificati '
                        'su Google Drive: restano record, miniatura e '
                        'riferimento al cloud. Mai i file non caricati né '
                        'gli allegati di non conformità aperte o lotti non '
                        'scaduti.',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: cloudConnected ? _offloadFlow : null,
                        icon: const Icon(Icons.cloud_done_outlined),
                        label: const Text('Libera spazio'),
                      ),
                      if (!cloudConnected)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Serve Google Drive collegato.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('Conservazione'),
              _RetentionSelector(repository: widget.repository),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I tempi di conservazione legali dipendono dal tipo '
                        'di documento e dalle indicazioni dell\u2019ASL o '
                        'del consulente. Verifica con il tuo consulente '
                        'HACCP prima di impostare un\u2019eliminazione '
                        'automatica.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SectionTitle('I 20 file più grandi'),
              FutureBuilder<List<Attachment>>(
                future: _largest,
                builder: (context, largestSnapshot) {
                  if (largestSnapshot.connectionState !=
                      ConnectionState.done) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Carico i file più grandi\u2026',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (largestSnapshot.hasError) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Impossibile caricare i file più grandi.',
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _reload,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Riprova'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final largest = largestSnapshot.data ?? const <Attachment>[];
                  if (largest.isEmpty) {
                    return const Card(
                      child: Padding(
                        padding: EdgeInsets.all(14),
                        child: Text('Nessun file locale.'),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final attachment in largest)
                        Card(
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              attachment.isPhoto
                                  ? Icons.photo
                                  : Icons.picture_as_pdf,
                            ),
                            title: Text(
                              attachment.fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${formatBytes(attachment.size)} \u2022 '
                              '${attachment.createdAt.year}',
                            ),
                            trailing: attachment.isOffloaded
                                ? const StatusPill(
                                    text: 'Solo su Drive',
                                    type: StatusType.info,
                                  )
                                : attachment.cloudId == null
                                    ? const StatusPill(
                                        text: 'Non al sicuro',
                                        type: StatusType.warning,
                                      )
                                    : const StatusPill(
                                        text: 'Su Drive',
                                        type: StatusType.success,
                                      ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              _RepairSection(
                attachments: widget.attachments,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _offloadFlow() async {
    final months = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Libera spazio'),
        children: [
          for (final value in [6, 12, 24])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, value),
              child: Text('Pi\u00F9 vecchi di $value mesi'),
            ),
        ],
      ),
    );
    if (months == null || !mounted) return;

    // Mai toccare allegati di NC aperte o lotti non scaduti.
    final openNcIds = (await widget.repository.getNonConformities())
        .where((nc) => nc.isOpen)
        .map((nc) => nc.id)
        .toSet();
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Confermi?'),
        content: Text(
          'Eliminer\u00F2 i file locali degli allegati pi\u00F9 vecchi di '
          '$months mesi gi\u00E0 verificati su Google Drive. Miniature e '
          'riferimenti restano: potrai riscaricare i file quando servono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Libera'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final freed = await widget.attachments.offloadOldAttachments(
      olderThan: Duration(days: 30 * months),
      protectedEntityIds: openNcIds,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Liberati ${formatBytes(freed)} dal telefono.')),
    );
    _reload();
  }
}

class _QualitySelector extends StatefulWidget {
  const _QualitySelector({
    required this.attachments,
    required this.onChanged,
  });

  final AttachmentService attachments;
  final VoidCallback onChanged;

  @override
  State<_QualitySelector> createState() => _QualitySelectorState();
}

class _QualitySelectorState extends State<_QualitySelector> {
  AttachmentQuality? _current;

  @override
  void initState() {
    super.initState();
    widget.attachments.qualityProfile().then(
          (value) => setState(() => _current = value),
        );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            for (final quality in AttachmentQuality.values)
              CheckboxListTile(
                value: _current == quality,
                dense: true,
                title: Text(quality.label),
                subtitle: quality == AttachmentQuality.standard
                    ? const Text('Predefinito')
                    : null,
                onChanged: (selected) async {
                  if (selected != true) return;
                  await widget.attachments.setQualityProfile(quality);
                  setState(() => _current = quality);
                  widget.onChanged();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RetentionSelector extends StatefulWidget {
  const _RetentionSelector({required this.repository});

  final HaccpRepository repository;

  @override
  State<_RetentionSelector> createState() => _RetentionSelectorState();
}

class _RetentionSelectorState extends State<_RetentionSelector> {
  static const options = {'mai': 'Mai (predefinito)', '2': '2 anni', '3': '3 anni', '5': '5 anni'};

  String _current = 'mai';

  @override
  void initState() {
    super.initState();
    widget.repository.getSetting('attachment_retention_years').then((value) {
      if (mounted) {
        setState(() => _current = options.containsKey(value) ? value : 'mai');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          children: [
            for (final entry in options.entries)
              CheckboxListTile(
                value: _current == entry.key,
                dense: true,
                title: Text(entry.value),
                onChanged: (selected) async {
                  if (selected != true) return;
                  await widget.repository.setSetting(
                      'attachment_retention_years', entry.key);
                  setState(() => _current = entry.key);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _RepairSection extends StatefulWidget {
  const _RepairSection({required this.attachments});

  final AttachmentService attachments;

  @override
  State<_RepairSection> createState() => _RepairSectionState();
}

class _RepairSectionState extends State<_RepairSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Controllo integrità'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trova file senza record (orfani) e record senza file. I '
                  'record senza file NON vengono cancellati: mostrano '
                  '"File non disponibile" o restano scaricabili da Drive.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await widget.attachments.findInconsistencies();
                    if (!context.mounted) return;
                    await showDialog<void>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: const Text('Controllo integrità'),
                        content: Text(
                          '${result.orphanFiles.length} file orfani\n'
                          '${result.missingFiles.length} record senza file',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: const Text('Chiudi'),
                          ),
                          if (result.orphanFiles.isNotEmpty)
                            FilledButton(
                              onPressed: () async {
                                final removed = await widget.attachments
                                    .repairOrphanFiles();
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          'Rimossi ${removed.length} file orfani.'),
                                    ),
                                  );
                                }
                              },
                              child: const Text('Ripara'),
                            ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.healing_outlined),
                  label: const Text('Controlla e ripara'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
