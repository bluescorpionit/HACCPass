import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/format.dart';
import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import '../services/attachment_service.dart';
import 'common_widgets.dart';

/// Sezione allegati riutilizzabile: elenco, aggiunta foto/documento,
/// visualizzatore con zoom, condivisione ed eliminazione.
class AttachmentSection extends StatefulWidget {
  const AttachmentSection({
    super.key,
    required this.repository,
    required this.entity,
    required this.entityId,
    this.compact = false,
  });

  final HaccpRepository repository;
  final AttachmentEntity entity;
  final int entityId;
  final bool compact;

  @override
  State<AttachmentSection> createState() => _AttachmentSectionState();
}

class _AttachmentSectionState extends State<AttachmentSection> {
  late final AttachmentService _service =
      AttachmentService(repository: widget.repository);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LiveQuery<List<Attachment>>(
      repository: widget.repository,
      loader: () =>
          widget.repository.getAttachments(widget.entity.value, widget.entityId),
      builder: (context, items) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    items.isEmpty
                        ? 'Allegati (DDT, etichette, foto, attestati)'
                        : 'Allegati (${items.length})',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Scatta foto',
                  onPressed: () => _service
                      .takePhoto(widget.entity, widget.entityId),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
                IconButton(
                  tooltip: 'Foto dalla galleria',
                  onPressed: () => _service
                      .pickPhoto(widget.entity, widget.entityId),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: 'Documento (anche dai servizi cloud)',
                  onPressed: () => _service
                      .pickDocument(widget.entity, widget.entityId),
                  icon: const Icon(Icons.attach_file),
                ),
              ],
            ),
            if (items.isNotEmpty) ...[
              const SizedBox(height: 4),
              for (final attachment in items)
                _AttachmentTile(
                  attachment: attachment,
                  onOpen: () => _open(attachment),
                  onDelete: () => _confirmDelete(attachment),
                ),
            ] else if (!widget.compact) ...[
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Nessun allegato. Il selettore documenti include Google '
                  'Drive, iCloud e OneDrive senza accessi aggiuntivi.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _open(Attachment attachment) async {
    final file = File(attachment.localPath);
    final exists = await file.exists();
    if (!mounted) return;
    if (!exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File non trovato sul dispositivo.')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _AttachmentViewer(attachment: attachment),
      ),
    );
  }

  Future<void> _confirmDelete(Attachment attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminare l\u2019allegato?'),
        content: Text('"${attachment.fileName}" verr\u00E0 rimosso.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.repository.deleteAttachment(
        attachment.id,
        localPath: attachment.localPath,
      );
    }
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.onOpen,
    required this.onDelete,
  });

  final Attachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                attachment.isPhoto ? Icons.image_outlined : Icons.description_outlined,
                color: colors.info,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '${fmtDate(attachment.createdAt)} \u2022 ${(attachment.size / 1024).round()} KB'
                      '${attachment.syncedAt != null ? ' \u2022 salvato nel cloud' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Elimina',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentViewer extends StatelessWidget {
  const _AttachmentViewer({required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = File(attachment.localPath);
    final isImage = attachment.isPhoto || attachment.mime.startsWith('image/');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          attachment.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Condividi',
            onPressed: () async {
              final box = context.findRenderObject() as RenderBox?;
              await SharePlus.instance.share(
                ShareParams(
                  files: [XFile(attachment.localPath)],
                  sharePositionOrigin:
                      box!.localToGlobal(Offset.zero) & box.size,
                ),
              );
            },
            icon: const Icon(Icons.share_outlined),
          ),
        ],
      ),
      body: isImage
          ? InteractiveZoomImage(file: file)
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.description_outlined,
                        size: 72, color: theme.colorScheme.primary),
                    const SizedBox(height: 12),
                    Text(attachment.fileName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      'Tipo ${attachment.mime} \u2022 '
                      '${(attachment.size / 1024).round()} KB',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class InteractiveZoomImage extends StatelessWidget {
  const InteractiveZoomImage({super.key, required this.file});

  final File file;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 5,
      child: Center(child: Image.file(file)),
    );
  }
}

/// Foglio allegati riutilizzabile da liste e card.
Future<void> showAttachmentsSheet(
  BuildContext context, {
  required HaccpRepository repository,
  required AttachmentEntity entity,
  required int entityId,
  required String title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Il foglio non sale mai sotto la barra di stato.
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (context, scrollController) {
          return ListView(
            controller: scrollController,
            // Insets di sistema: il contenuto non finisce sotto la barra
            // di navigazione.
            padding: EdgeInsets.fromLTRB(
              24,
              4,
              24,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              AttachmentSection(
                repository: repository,
                entity: entity,
                entityId: entityId,
              ),
            ],
          );
        },
      );
    },
  );
}

/// Tipi documentali rapidi per gli allegati durante la registrazione.
const attachmentLabels = ['DDT', 'Etichetta/lotto', 'Certificato', 'Altro'];

/// Sezione "Documenti e foto" per i form di registrazione (merce, lotto):
/// raccoglie allegati in una lista temporanea [PendingAttachment]; il
/// chiamante li registra con `attachPending` dopo il salvataggio o li
/// elimina con `discardPending` se annulla.
class PendingAttachmentsSection extends StatefulWidget {
  const PendingAttachmentsSection({
    super.key,
    required this.service,
    required this.pending,
    this.hint,
  });

  final AttachmentService service;
  final List<PendingAttachment> pending;
  final String? hint;

  @override
  State<PendingAttachmentsSection> createState() =>
      _PendingAttachmentsSectionState();
}

class _PendingAttachmentsSectionState
    extends State<PendingAttachmentsSection> {
  Future<void> _add(Future<PendingAttachment?> Function() acquire) async {
    final item = await acquire();
    if (item == null || !mounted) return;

    // Menu rapido del tipo documentale (opzionale, annullabile).
    final label = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          children: [
            Text(
              'Che tipo di documento?',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final option in attachmentLabels)
              ListTile(
                title: Text(option),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(sheetContext, option),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      widget.pending.add(
        PendingAttachment(
          tempPath: item.tempPath,
          kind: item.kind,
          label: label,
          note: item.note,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Documenti e foto',
          style: theme.textTheme.labelLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (widget.hint?.isNotEmpty == true)
          Text(
            widget.hint!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Scatta foto DDT/etichetta'),
              onPressed: () =>
                  _add(widget.service.capturePhotoTemp).catchError((_) {}),
            ),
            ActionChip(
              avatar: const Icon(Icons.image_outlined, size: 18),
              label: const Text('Scegli da galleria'),
              onPressed: () =>
                  _add(widget.service.pickPhotoTemp).catchError((_) {}),
            ),
            ActionChip(
              avatar: const Icon(Icons.attach_file, size: 18),
              label: const Text('Aggiungi file (PDF)'),
              onPressed: () =>
                  _add(widget.service.pickDocumentTemp).catchError((_) {}),
            ),
          ],
        ),
        if (widget.pending.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < widget.pending.length; i++)
            _PendingTile(
              item: widget.pending[i],
              onRemove: () => setState(
                () => widget.pending.removeAt(i),
              ),
            ),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Puoi allegare ora foto del DDT, dell\u2019etichetta o '
              'documenti: verranno salvati insieme alla registrazione.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.item, required this.onRemove});

  final PendingAttachment item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;
    final isPhoto = item.kind == 'photo';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: isPhoto
                  ? Image.file(
                      File(item.tempPath),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.broken_image_outlined),
                      ),
                    )
                  : const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.description_outlined),
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label ?? (isPhoto ? 'Foto' : 'Documento'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    p.basename(item.tempPath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Rimuovi',
              visualDensity: VisualDensity.compact,
              onPressed: onRemove,
              icon: Icon(
                Icons.close,
                size: 20,
                color: colors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
