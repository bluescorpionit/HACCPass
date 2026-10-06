import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/haccp_rules.dart';
import '../../../core/sensors/ble_sensor_source.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../models/haccp_models.dart';
import '../../../repositories/haccp_repository.dart';
import '../../../services/license_service.dart';
import '../../../widgets/common_widgets.dart';
import 'equipment_editor.dart';
import 'equipment_history_sheet.dart';
import '../sensors/link_sensor_sheet.dart';

class TemperatureScreen extends StatelessWidget {
  const TemperatureScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  Widget build(BuildContext context) {
    return LiveQuery<_TemperatureData>(
      repository: repository,
      loader: () async => _TemperatureData(
        equipment: await repository.getEquipmentWithSensors(),
        logs: await repository.getTodayTemperatureLogs(),
        operatorName: await repository.defaultOperator(),
      ),
      builder: (context, data) {
        final theme = Theme.of(context);
        final readToday = data.logs.map((l) => l.equipmentId).toSet();

        return FeatureScaffold(
          title: 'Temperature',
          subtitle:
              'Registra la lettura: se \u00E8 fuori limite l\u2019app '
              'propone le azioni correttive (PRP 11).',
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              if (!license.ensureLicensed(context)) return;
              _openEditor(context);
            },
            icon: const Icon(Icons.add),
            label: const Text('Attrezzatura'),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...data.equipment.map(
                (entry) {
                  final (equipment, sensor) = entry;
                  final done = readToday.contains(equipment.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => showRegisterTemperatureSheet(
                          context,
                          repository: repository,
                          license: license,
                          equipment: equipment,
                          operatorName: data.operatorName,
                          sensor: sensor,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    done
                                        ? Icons.check_circle_outline
                                        : Icons.thermostat,
                                    size: 30,
                                    color: done
                                        ? context.haccpColors.success
                                        : theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Flexible(
                                              child: Text(
                                                equipment.name,
                                                style: theme
                                                    .textTheme.titleSmall
                                                    ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            if (sensor != null) ...[
                                              const SizedBox(width: 6),
                                              Icon(
                                                Icons.sensors,
                                                size: 16,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant,
                                                semanticLabel:
                                                    'Sorgente sensore',
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${equipment.type} \u2022 ${equipment.rangeLabel}'
                                          '${equipment.location.isEmpty ? '' : ' \u2022 ${equipment.location}'}',
                                          style:
                                              theme.textTheme.bodySmall?.copyWith(
                                            color: theme
                                                .colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    onPressed: () =>
                                        showRegisterTemperatureSheet(
                                      context,
                                      repository: repository,
                                      license: license,
                                      equipment: equipment,
                                      operatorName: data.operatorName,
                                      sensor: sensor,
                                    ),
                                    child: const Text('Registra'),
                                  ),
                                  IconButton(
                                    tooltip: 'Storico',
                                    onPressed: () => showEquipmentHistory(
                                      context,
                                      repository,
                                      equipment,
                                    ),
                                    icon: const Icon(Icons.show_chart),
                                  ),
                                ],
                              ),
                              if (sensor != null)
                                _SensorLiveTile(
                                  repository: repository,
                                  equipment: equipment,
                                  sensor: sensor,
                                )
                              else
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: TextButton.icon(
                                    onPressed: () => showLinkSensorSheet(
                                      context,
                                      repository: repository,
                                      equipment: equipment,
                                    ),
                                    icon: const Icon(Icons.sensors, size: 18),
                                    label: const Text('Collega sensore'),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SectionTitle('Letture di oggi'),
              if (data.logs.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text('Nessuna temperatura registrata oggi.'),
                  ),
                )
              else
                ...data.logs.map(
                  (log) {
                    final colors = context.haccpColors;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: ListTile(
                          leading: Icon(
                            log.compliant
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: log.compliant
                                ? colors.success
                                : colors.danger,
                          ),
                          title: Text(
                            '${log.equipmentName ?? ''} \u2022 '
                            '${fmtTemp(log.temperature)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${fmtTime(log.measuredAt)} \u2022 ${log.operatorName}'
                            '${log.fromSensor ? ' \u2022 ${log.sourceLabel}' : ''}'
                            '${log.correctiveAction?.isNotEmpty == true ? '\nAzione: ${log.correctiveAction}' : ''}',
                          ),
                          isThreeLine:
                              log.correctiveAction?.isNotEmpty == true,
                          trailing: StatusPill(
                            text: log.compliant
                                ? 'Conforme'
                                : 'Fuori limite',
                            type: log.compliant
                                ? StatusType.success
                                : StatusType.danger,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tips_and_updates_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Zona di rischio: tra +10 e +60 \u00B0C. Oltre 2 '
                              'ore il prodotto va riportato a temperatura o '
                              'valutato (Reg. CE 852/2004).',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EquipmentEditor(repository: repository),
    ));
  }
}

/// Dato letto dal sensore nel foglio di registrazione (per source/raw).
class _SensorRead {
  _SensorRead({
    required this.raw,
    required this.value,
    required this.at,
    required this.offset,
  });

  final double raw;
  final double value;
  final DateTime at;
  final double offset;
}

/// FASE 4 (Prompt 7): foglio "Registra temperatura". Se l'attrezzatura ha
/// un sensore, il campo valore ha "Leggi dal sensore": compila la
/// temperatura (offset applicato) e mostra l'orario. Con dato vecchio o
/// sensore non raggiungibile il pulsante è disabilitato con spiegazione e
/// resta l'inserimento manuale. Se l'operatore modifica il valore letto,
/// la sorgente torna Manuale.
Future<void> showRegisterTemperatureSheet(
  BuildContext context, {
  required HaccpRepository repository,
  required LicenseService license,
  required Equipment equipment,
  required String operatorName,
  Sensor? sensor,
}) async {
  if (!license.ensureLicensed(context)) return;

  final controller = TextEditingController();
  final noteController = TextEditingController();
  final selectedActions = <String>{};

  var saved = false;
  var temperature = 0.0;
  _SensorRead? sensorRead;
  var injected = false;

  final service = SensorService.instance;
  final live = sensor == null ? null : service.latestFor(sensor.deviceKey);
  final status =
      sensor == null ? SensorStatus.offline : service.statusFor(sensor.deviceKey);

  final result = await showFormSheet<bool>(
    context: context,
    title: equipment.name,
    saveLabel: 'Salva controllo',
    saveIcon: Icons.thermostat,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final parsed = double.tryParse(
            controller.text.trim().replaceAll(',', '.'),
          );
          final compliant =
              parsed != null && equipment.isCompliant(parsed);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Limiti di riferimento: ${equipment.rangeLabel}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 12),
              if (sensor != null) ...[
                // Leggi dal sensore: attivo solo con dato live.
                OutlinedButton.icon(
                  onPressed: status == SensorStatus.live && live != null
                      ? () {
                          final adjusted =
                              live.tempC + sensor.calibrationOffset;
                          injected = true;
                          controller.text = adjusted.toStringAsFixed(1);
                          sensorRead = _SensorRead(
                            raw: live.tempC,
                            value: adjusted,
                            at: live.timestamp,
                            offset: sensor.calibrationOffset,
                          );
                          setSheetState(() {});
                        }
                      : null,
                  icon: const Icon(Icons.sensors),
                  label: Text(
                    status == SensorStatus.live
                        ? 'Leggi dal sensore (${sensor.displayName})'
                        : status == SensorStatus.stale
                            ? 'Sensore: dato vecchio, inserisci a mano'
                            : 'Sensore non raggiungibile, inserisci a mano',
                  ),
                ),
                if (sensorRead != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Letto dal sensore alle '
                      '${fmtTime(sensorRead!.at)}'
                      '${sensorRead!.offset != 0 ? ' \u2022 offset ${sensorRead!.offset > 0 ? '+' : ''}${sensorRead!.offset.toStringAsFixed(1)} \u00B0C' : ''}. '
                      'Se modifichi il valore la sorgente diventa manuale.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                    RegExp(r'^-?[0-9]*[.,]?[0-9]*'),
                  ),
                ],
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'Temperatura rilevata (\u00B0C)',
                  suffixText: '\u00B0C',
                ),
                onChanged: (_) {
                  // Valore modificato dopo la lettura: sorgente manuale.
                  if (injected) {
                    injected = false;
                  } else {
                    final read = sensorRead;
                    if (read != null &&
                        double.tryParse(controller.text
                                .trim()
                                .replaceAll(',', '.')) !=
                            read.value) {
                      sensorRead = null;
                    }
                  }
                  setSheetState(() {});
                },
              ),
              const SizedBox(height: 10),
              if (parsed != null)
                ComplianceIndicator(
                  compliant: compliant,
                  hasValue: true,
                ),
              if (parsed != null && !compliant) ...[
                const SizedBox(height: 14),
                Text(
                  'Azioni correttive adottate',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                // Righe checkbox: le etichette lunghe vanno a capo restando
                // integre (i chip le tronavano) e il tocco resta >= 48 dp.
                CorrectiveActionPicker(
                  actions: temperatureCorrectiveActions,
                  selected: selectedActions,
                  onToggle: (action) => setSheetState(() {
                    selectedActions.contains(action)
                        ? selectedActions.remove(action)
                        : selectedActions.add(action);
                  }),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Nota (facoltativa)',
                ),
              ),
            ],
          );
        },
      );
    },
    onSave: () {
      final parsed =
          double.tryParse(controller.text.trim().replaceAll(',', '.'));
      if (parsed == null) return false;
      temperature = parsed;
      saved = true;
      return true;
    },
  );

  if (result != true || !saved) return;

  final correctiveAction = selectedActions.isEmpty
      ? null
      : selectedActions.join('; ');

  await repository.saveTemperature(
    equipment: equipment,
    temperature: temperature,
    operatorName: operatorName,
    note: noteController.text.trim(),
    correctiveAction: correctiveAction,
    source: sensorRead != null ? 'sensor' : 'manual',
    sensorId: sensorRead != null ? sensor?.id : null,
    sensorLabel: sensorRead != null ? sensor?.displayName : null,
    sensorOffset: sensorRead?.offset,
    sensorRaw: sensorRead?.raw,
    sensorReadingAt: sensorRead?.at,
  );

  if (!context.mounted) return;
  final colors = context.haccpColors;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        equipment.isCompliant(temperature)
            ? 'Temperatura registrata: conforme.'
            : 'Temperatura fuori limite: aperta una non conformit\u00E0 '
                'con le azioni correttive.',
      ),
      backgroundColor: equipment.isCompliant(temperature)
          ? colors.success
          : colors.danger,
    ),
  );
}

/// Scheda del sensore collegato: temperatura attuale in evidenza, stato
/// (In linea / Dato vecchio da X min / Non raggiungibile), orario ultimo
/// dato, colore secondo i limiti (token del tema) sempre con icona e
/// testo, pulsante Aggiorna, offset visibile e scollegamento.
class _SensorLiveTile extends StatefulWidget {
  const _SensorLiveTile({
    required this.repository,
    required this.equipment,
    required this.sensor,
  });

  final HaccpRepository repository;
  final Equipment equipment;
  final Sensor sensor;

  @override
  State<_SensorLiveTile> createState() => _SensorLiveTileState();
}

class _SensorLiveTileState extends State<_SensorLiveTile> {
  @override
  void initState() {
    super.initState();
    SensorService.instance.latest.addListener(_onChange);
  }

  @override
  void dispose() {
    SensorService.instance.latest.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    try {
      // Scansione breve avviata dall'utente: i permessi si chiedono al
      // primo uso. Nessuna scansione continua in background.
      await SensorService.instance.start(
        timeout: const Duration(seconds: 15),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Bluetooth non disponibile o permesso negato: il sensore '
              'resta non raggiungibile (l\u2019app funziona in manuale).',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;
    final service = SensorService.instance;
    final equipment = widget.equipment;
    final sensor = widget.sensor;

    final sample = service.latestFor(sensor.deviceKey);
    final status = service.statusFor(sensor.deviceKey);
    final raw = sample?.tempC ?? sensor.lastTemp;
    final lastSeen = sample?.timestamp ?? sensor.lastSeen;
    final adjusted = raw == null ? null : raw + sensor.calibrationOffset;
    final compliant = adjusted != null && equipment.isCompliant(adjusted);

    final (statusText, statusIcon, statusColor) = switch (status) {
      SensorStatus.live => (
          'In linea',
          Icons.check_circle_outline,
          colors.success,
        ),
      SensorStatus.stale => (
          lastSeen == null
              ? 'Non raggiungibile'
              : 'Dato vecchio da '
                  '${DateTime.now().difference(lastSeen).inMinutes} min',
          Icons.schedule,
          colors.warning,
        ),
      SensorStatus.offline => (
          lastSeen == null
              ? 'Non raggiungibile'
              : 'Ultimo dato alle ${fmtTime(lastSeen)} (sessione scaduta)',
          Icons.cloud_off_outlined,
          colors.warning,
        ),
    };

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                statusIcon,
                color: statusColor,
                semanticLabel: statusText,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${sensor.displayName} \u2022 $statusText',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Aggiorna dal sensore',
                visualDensity: VisualDensity.compact,
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 20),
              ),
              PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'offset':
                      await _editOffset(context);
                    case 'verify':
                      await offerSensorVerification(
                        context,
                        repository: widget.repository,
                        equipment: equipment,
                        sensorId: sensor.id,
                        deviceKey: sensor.deviceKey,
                      );
                    case 'unlink':
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: const Text('Scollegare il sensore?'),
                          content: Text(
                            '${equipment.name} torna a sorgente Manuale. Le '
                            'letture passate restano nello storico.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, false),
                              child: const Text('Annulla'),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(dialogContext, true),
                              child: const Text('Scollega'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await widget.repository
                            .unlinkSensorFromEquipment(equipment.id);
                      }
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'offset',
                    child: Text('Offset di calibrazione'),
                  ),
                  PopupMenuItem(
                    value: 'verify',
                    child: Text('Verifica con termometro'),
                  ),
                  PopupMenuItem(
                    value: 'unlink',
                    child: Text('Scollega sensore'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(
                compliant ? Icons.check_circle : Icons.warning_amber,
                color: compliant ? colors.success : colors.danger,
                semanticLabel: compliant ? 'Entro i limiti' : 'Fuori limite',
              ),
              const SizedBox(width: 8),
              Text(
                adjusted == null
                    ? '\u2014 \u00B0C'
                    : '${adjusted.toStringAsFixed(1)} \u00B0C',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: compliant ? colors.success : colors.danger,
                ),
              ),
              const Spacer(),
              if (lastSeen != null)
                Text(
                  'ultimo dato ${fmtTime(lastSeen)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (sensor.calibrationOffset != 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Offset applicato: ${sensor.calibrationOffset > 0 ? '+' : ''}'
                '${sensor.calibrationOffset.toStringAsFixed(1)} \u00B0C '
                '(registrato nei log e nel PDF)',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          if (sensor.verificationOverdue)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Verifica con termometro di riferimento da fare '
                '(\u00B11 \u00B0C).',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (sensor.lastVerifiedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Verificato il ${fmtDate(sensor.lastVerifiedAt!)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editOffset(BuildContext context) async {
    var offset = widget.sensor.calibrationOffset;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Offset di calibrazione'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Valore applicato alle letture di questo sensore: '
                '${offset > 0 ? '+' : ''}${offset.toStringAsFixed(1)} \u00B0C. '
                'Sempre visibile e registrato insieme ai dati.',
              ),
              Slider(
                value: offset,
                min: -3,
                max: 3,
                divisions: 60,
                label: '${offset.toStringAsFixed(1)} \u00B0C',
                onChanged: (v) => setDialogState(() => offset = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Salva'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await widget.repository.setSensorCalibration(widget.sensor.id, offset);
    }
  }
}

class _TemperatureData {
  const _TemperatureData({
    required this.equipment,
    required this.logs,
    required this.operatorName,
  });

  final List<(Equipment, Sensor?)> equipment;
  final List<TemperatureLog> logs;
  final String operatorName;
}
