import 'package:flutter/material.dart';

import '../core/constants/haccp_rules.dart';
import '../core/utils/format.dart';
import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../services/pdf_service.dart';
import '../widgets/attachment_section.dart';
import '../widgets/common_widgets.dart';
import 'lots_screen.dart' show PdfPreviewScreen;

class NonConformitiesScreen extends StatelessWidget {
  const NonConformitiesScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<List<NonConformity>>(
      repository: repository,
      loader: repository.getNonConformities,
      builder: (context, items) {
        return FeatureScaffold(
          title: 'Non conformit\u00E0',
          subtitle:
              'Registro come da Allegato I: problema, azione correttiva, '
              'destino del prodotto, operatore.',
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'new_nc',
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _newNc(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Nuova NC'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isEmpty)
                EmptyState(
                  icon: Icons.verified_outlined,
                  title: 'Nessuna non conformit\u00E0',
                  message:
                      'Quando qualcosa non va (temperatura, merce, pulizia\u2026) '
                      'aprila qui: la chiusura richiede l\u2019azione correttiva.',
                  actionLabel: 'Apri NC',
                  onAction: () {
                    if (!license.ensureLicensed(context)) return;
                    _newNc(context);
                  },
                )
              else
                for (final nc in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _NcCard(
                      nc: nc,
                      repository: repository,
                      license: license,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _newNc(BuildContext context) async {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final actionController = TextEditingController();
    var category = ncCategories.first;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Nuova non conformit\u00E0',
      saveLabel: 'Apri non conformit\u00E0',
      saveIcon: Icons.report_outlined,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Categoria',
                  child: ChoiceRow<String>(
                    options: [for (final c in ncCategories) (c, c)],
                    selected: category,
                    onSelected: (v) => setSheetState(() => category = v),
                  ),
                ),
                LabeledField(
                  label: 'Titolo / problema',
                  child: TextField(controller: titleController),
                ),
                LabeledField(
                  label: 'Descrizione',
                  child: TextField(
                    controller: descriptionController,
                    maxLines: 3,
                  ),
                ),
                TextField(
                  controller: actionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Azione immediata (facoltativa)',
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () =>
          titleController.text.trim().isNotEmpty &&
          descriptionController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    final operator = await repository.defaultOperator();
    await repository.createNonConformity(
      category: category,
      title: titleController.text.trim(),
      description: descriptionController.text.trim(),
      correctiveAction: actionController.text.trim(),
      operatorName: operator,
    );
  }
}

class _NcCard extends StatelessWidget {
  const _NcCard({
    required this.nc,
    required this.repository,
    required this.license,
  });

  final NonConformity nc;
  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    nc.title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(
                  text: nc.isOpen ? 'Aperta' : 'Chiusa',
                  type: nc.isOpen ? StatusType.danger : StatusType.success,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${nc.category} \u2022 ${fmtDateTime(nc.openedAt)} \u2022 ${nc.operatorName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            Text(nc.description),
            if (nc.correctiveAction?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                'Azione: ${nc.correctiveAction}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (!nc.isOpen && nc.disposition != 'none') ...[
              const SizedBox(height: 4),
              Text(
                'Destino prodotto: ${nc.dispositionLabel}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                if (nc.isOpen)
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => _close(context),
                      child: const Text('Risolvi e chiudi'),
                    ),
                  )
                else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _printForm(context),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Modulo NC'),
                    ),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _printSign(context),
                    icon: const Icon(Icons.warning_amber_outlined),
                    label: const Text('Cartello'),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.outlined(
                  tooltip: 'Foto e allegati',
                  onPressed: () => showAttachmentsSheet(
                    context,
                    repository: repository,
                    entity: AttachmentEntity.nonConformity,
                    entityId: nc.id,
                    title: nc.title,
                  ),
                  icon: const Icon(Icons.attach_file),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _close(BuildContext context) async {
    final controller = TextEditingController(text: nc.correctiveAction ?? '');
    var disposition = NcDisposition.none;

    final saved = await showFormSheet<bool>(
      context: context,
      title: 'Chiudi non conformit\u00E0',
      saveLabel: 'Chiudi NC',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Azione correttiva (obbligatoria)',
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                  ),
                ),
                LabeledField(
                  label: 'Destino del prodotto',
                  child: ChoiceRow<NcDisposition>(
                    options: [
                      for (final d in NcDisposition.values) (d, d.label),
                    ],
                    selected: disposition,
                    onSelected: (v) =>
                        setSheetState(() => disposition = v),
                  ),
                ),
              ],
            );
          },
        );
      },
      onSave: () => controller.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    await repository.closeNonConformity(
      id: nc.id,
      correctiveAction: controller.text.trim(),
      disposition: disposition.code,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Non conformit\u00E0 chiusa.')),
      );
    }
  }

  Future<void> _printForm(BuildContext context) async {
    final pdf = PdfService(repository: repository, license: license);
    final bytes = await pdf.buildNcForm(nc);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: 'Modulo NC #${nc.id}',
        bytes: bytes,
        fileName: 'HACCP_ModuloNC_${nc.id}_${_stamp()}.pdf',
      ),
    ));
  }

  Future<void> _printSign(BuildContext context) async {
    if (!license.ensureLicensed(context)) return;
    final pdf = PdfService(repository: repository, license: license);
    final bytes = await pdf.buildNcSign(nc);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PdfPreviewScreen(
        title: 'Cartello prodotto non conforme',
        bytes: bytes,
        fileName: 'HACCP_CartelloNC_${nc.id}_${_stamp()}.pdf',
      ),
    ));
  }

  String _stamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
