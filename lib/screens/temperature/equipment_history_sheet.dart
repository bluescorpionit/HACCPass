import 'package:flutter/material.dart';

import '../../core/constants/haccp_rules.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../services/pdf_service.dart';
import '../../services/printing/print_label_flow.dart';
import '../../widgets/attachment_section.dart';
import '../../widgets/common_widgets.dart';
import '../lots_screen.dart' show PdfPreviewScreen;

/// Scheda attrezzatura: grafico 14 giorni con banda dei limiti, storico e
/// verifica termometro (PRP 4).
Future<void> showEquipmentHistory(
  BuildContext context,
  HaccpRepository repository,
  Equipment equipment,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    // Il foglio non sale mai sotto la barra di stato.
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: LiveQuery<List<TemperatureLog>>(
              repository: repository,
              loader: () => repository.getEquipmentHistory(equipment.id),
              builder: (context, logs) {
                final theme = Theme.of(context);
                final colors = context.haccpColors;
                return ListView(
                  controller: scrollController,
                  // Insets di sistema: il contenuto non finisce sotto la
                  // barra di navigazione.
                  padding: EdgeInsets.fromLTRB(
                    24,
                    4,
                    24,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    Text(
                      equipment.name,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      '${equipment.type} \u2022 ${equipment.rangeLabel}'
                      '${equipment.location.isEmpty ? '' : ' \u2022 ${equipment.location}'}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Andamento ultimi 14 giorni',
                      style: theme.textTheme.labelLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Sparkline(
                          points: [
                            for (final l in logs) (l.measuredAt, l.temperature),
                          ],
                          minLimit: equipment.minTemp,
                          maxLimit: equipment.maxTemp,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatusPill(
                            text: equipment.thermoVerifiedAt == null
                                ? 'Termometro mai verificato'
                                : 'Termometro verificato il '
                                    '${fmtDate(equipment.thermoVerifiedAt!)}',
                            type: equipment.thermoCheckOverdue
                                ? StatusType.warning
                                : StatusType.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _registerThermometerCheck(
                              sheetContext,
                              repository,
                              equipment,
                            ),
                            icon: const Icon(Icons.device_thermostat_outlined),
                            label: const Text('Verifica termometro'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final pdf = PdfService(repository: repository);
                              final bytes =
                                  await pdf.buildEquipmentQrLabel(equipment);
                              if (!sheetContext.mounted) return;
                              await showPrintLabelDialog(
                                sheetContext,
                                repository: repository,
                                pdfBytes: bytes,
                                title: 'Stampa etichetta QR',
                                pdfFileName:
                                    'HACCP_QR_${sanitizeFileName(equipment.name)}.pdf',
                              );
                            },
                            icon: const Icon(Icons.print_outlined),
                            label: const Text('Stampa QR'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final pdf = PdfService(repository: repository);
                              final bytes =
                                  await pdf.buildEquipmentQrLabel(equipment);
                              if (!sheetContext.mounted) return;
                              await Navigator.of(sheetContext).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => PdfPreviewScreen(
                                    title:
                                        'Etichetta QR ${equipment.name}',
                                    bytes: bytes,
                                    fileName:
                                        'HACCP_QR_${sanitizeFileName(equipment.name)}.pdf',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.qr_code_2),
                            label: const Text('Etichetta QR'),
                          ),
                        ),
                      ],
                    ),
                    const SectionTitle('Foto e libretto'),
                    AttachmentSection(
                      repository: repository,
                      entity: AttachmentEntity.equipment,
                      entityId: equipment.id,
                      compact: true,
                    ),
                    const SectionTitle('Storico letture'),
                    if (logs.isEmpty)
                      const Text('Nessuna lettura negli ultimi 14 giorni.')
                    else
                      for (final log in logs.reversed.take(40))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            log.compliant
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: log.compliant
                                ? colors.success
                                : colors.danger,
                          ),
                          title: Text(fmtDateTime(log.measuredAt)),
                          trailing: Text(
                            fmtTemp(log.temperature),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );
}

Future<void> _registerThermometerCheck(
  BuildContext context,
  HaccpRepository repository,
  Equipment equipment,
) async {
  final referenceController = TextEditingController(text: '0');
  final instrumentController = TextEditingController();

  final saved = await showFormSheet<bool>(
    context: context,
    title: 'Verifica termometro \u2013 ${equipment.name}',
    saveLabel: 'Salva verifica',
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final ref = double.tryParse(
              referenceController.text.trim().replaceAll(',', '.'));
          final inst = double.tryParse(
              instrumentController.text.trim().replaceAll(',', '.'));
          final deviation =
              (ref != null && inst != null) ? (inst - ref).abs() : null;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Confronto con temperatura di riferimento (es. ghiaccio e '
                'acqua 0 \u00B0C). Tolleranza \u00B11 \u00B0C; oltre \u00B13 '
                '\u00B0C il termometro va sostituito o riparato.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: referenceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Temperatura di riferimento (\u00B0C)',
                ),
                onChanged: (_) => setSheetState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: instrumentController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Temperatura dello strumento (\u00B0C)',
                ),
                onChanged: (_) => setSheetState(() {}),
              ),
              if (deviation != null) ...[
                const SizedBox(height: 12),
                StatusPill(
                  text: deviation > thermometerReplaceThreshold
                      ? 'Scostamento ${deviation.toStringAsFixed(1)} \u00B0C: sostituire o riparare'
                      : deviation > thermometerTolerance
                          ? 'Scostamento ${deviation.toStringAsFixed(1)} \u00B0C: oltre tolleranza'
                          : 'Scostamento ${deviation.toStringAsFixed(1)} \u00B0C: in tolleranza',
                  type: deviation > thermometerReplaceThreshold
                      ? StatusType.danger
                      : deviation > thermometerTolerance
                          ? StatusType.warning
                          : StatusType.success,
                  large: true,
                ),
              ],
            ],
          );
        },
      );
    },
    onSave: () =>
        double.tryParse(instrumentController.text.replaceAll(',', '.')) !=
        null,
  );

  if (saved != true) return;

  final operator = await repository.defaultOperator();
  await repository.saveThermometerCheck(
    equipment: equipment,
    referenceTemp: double.parse(
        referenceController.text.trim().replaceAll(',', '.')),
    instrumentTemp: double.parse(
        instrumentController.text.trim().replaceAll(',', '.')),
    operatorName: operator,
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verifica termometro registrata.')),
    );
  }
}
