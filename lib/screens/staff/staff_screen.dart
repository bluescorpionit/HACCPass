import 'package:flutter/material.dart';

import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/license_service.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';

/// Personale e formazione (Allegato VI).
class StaffScreen extends StatelessWidget {
  const StaffScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personale e formazione')),
      body: LiveQuery<(List<StaffMember>, int)>(
        repository: repository,
        loader: () async {
          final staff = await repository.getStaff();
          return (staff, await repository.getTrainingRenewalMonths());
        },
        builder: (context, data) {
          final staff = data.$1;
          final renewalMonths = data.$2;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              PageHeader(
                title: 'Personale',
                subtitle:
                    'Attestati di formazione alimentarista con scadenza '
                    '(Allegato VI): la dashboard segnala scadenze e mancanze.',
              ),
              if (staff.isEmpty)
                EmptyState(
                  icon: Icons.badge_outlined,
                  title: 'Nessun membro del personale',
                  message:
                      'Registra il personale con la data dell\u2019attestato '
                      'formativo.',
                  actionLabel: 'Aggiungi persona',
                  onAction: () {
                    if (!license.ensureLicensed(context)) return;
                    _edit(context, null);
                  },
                )
              else
                for (final member in staff)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          Icons.badge_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          member.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            member.job.isEmpty ? member.role : member.job,
                            member.certificateAt == null
                                ? 'attestato mancante'
                                : 'attestato ${fmtDate(member.certificateAt!)}',
                          ].join(' \u2022 '),
                        ),
                        isThreeLine: false,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _statusPill(context, member, renewalMonths),
                            IconButton(
                              tooltip: 'Attestato e allegati',
                              onPressed: () => showAttachmentsSheet(
                                context,
                                repository: repository,
                                entity: AttachmentEntity.staff,
                                entityId: member.id,
                                title: member.name,
                              ),
                              icon: const Icon(Icons.attach_file, size: 20),
                            ),
                          ],
                        ),
                        onTap: () => _edit(context, member),
                      ),
                    ),
                  ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'new_staff',
        onPressed: () {
          if (!license.ensureLicensed(context)) return;
          _edit(context, null);
        },
        icon: const Icon(Icons.add),
        label: const Text('Persona'),
      ),
    );
  }

  Widget _statusPill(BuildContext context, StaffMember member, int months) {
    return switch (member.certificateStatus(months: months)) {
      'valid' => const StatusPill(text: 'Valido', type: StatusType.success),
      'expiring' => const StatusPill(
          text: 'In scadenza', type: StatusType.warning),
      'expired' => const StatusPill(text: 'Scaduto', type: StatusType.danger),
      _ => const StatusPill(text: 'Mancante', type: StatusType.danger),
    };
  }

  Future<void> _edit(BuildContext context, StaffMember? existing) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    final jobController = TextEditingController(text: existing?.job ?? '');
    final notesController = TextEditingController(text: existing?.notes ?? '');
    var role = existing?.role ?? 'Alimentarista';
    DateTime? certificateAt = existing?.certificateAt;

    final roles = ['Alimentarista', 'Responsabile', 'Sostituto responsabile'];

    final saved = await showFormSheet<bool>(
      context: context,
      title: existing == null ? 'Nuovo membro' : 'Modifica membro',
      saveLabel: 'Salva',
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'Nome',
                  child: TextField(controller: nameController),
                ),
                LabeledField(
                  label: 'Ruolo',
                  child: ChoiceRow<String>(
                    options: [for (final r in roles) (r, r)],
                    selected: role,
                    onSelected: (v) => setSheetState(() => role = v),
                  ),
                ),
                LabeledField(
                  label: 'Mansione',
                  child: TextField(controller: jobController),
                ),
                DateField(
                  label: 'Data attestato formazione',
                  value: certificateAt,
                  onChanged: (v) => setSheetState(() => certificateAt = v),
                  allowClear: true,
                ),
                TextField(
                  controller: notesController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Note'),
                ),
              ],
            );
          },
        );
      },
      onSave: () => nameController.text.trim().isNotEmpty,
    );

    if (saved != true) return;

    await repository.saveStaffMember(
      StaffMember(
        id: existing?.id ?? 0,
        name: nameController.text.trim(),
        role: role,
        job: jobController.text.trim(),
        certificateAt: certificateAt,
        notes: notesController.text.trim(),
      ),
      id: existing?.id,
    );
  }
}
