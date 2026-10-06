import 'package:flutter/material.dart';

import '../../core/sensors/ble_sensor_source.dart';
import '../../core/sensors/sensor_model.dart';
import '../../core/sensors/sensor_registry.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../../widgets/common_widgets.dart';
import 'sensor_image.dart';

/// FASE 3 (Prompt 7): foglio "Collega sensore".
///
/// Scansione live filtrata dal modello scelto: per ogni dispositivo nome,
/// temperatura attuale, umidità, barre RSSI, batteria e l'eventuale tag
/// "Già usato per: …" (selezionabile solo dopo conferma di spostamento).
/// Aiuto all'identificazione: si evidenzia la riga con la variazione di
/// temperatura maggiore ("scalda il sensore con la mano").
///
/// La scansione parte qui (permessi Bluetooth chiesti al primo uso, mai
/// all'avvio) e si ferma alla chiusura del foglio.
Future<void> showLinkSensorSheet(
  BuildContext context, {
  required HaccpRepository repository,
  required Equipment equipment,
}) async {
  final service = SensorService.instance;
  final model = sensorRegistry.first;
  final labelController = TextEditingController(text: equipment.name);

  final selected = _Selection();
  var scanError = false;

  try {
    await service.start(timeout: const Duration(seconds: 60));
  } catch (_) {
    scanError = true;
  }
  if (!context.mounted) {
    await service.stop();
    return;
  }
  if (scanError) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Bluetooth non disponibile o permesso negato: resta Manuale, '
          'l\u2019app funziona normalmente. Puoi riprovare dal pulsante '
          'Collega sensore.',
        ),
      ),
    );
    await service.stop();
    return;
  }

  final linked = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final theme = Theme.of(sheetContext);
      final mq = MediaQuery.of(sheetContext);
      return Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: (mq.size.height - mq.padding.top) * 0.92,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Text(
                  'Collega sensore a ${equipment.name}',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: _LinkSheetBody(
                    repository: repository,
                    equipment: equipment,
                    model: model,
                    selection: selected,
                    labelController: labelController,
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    24, 8, 24, mq.viewPadding.bottom.clamp(16.0, double.infinity),
                  ),
                  child: ListenableBuilder(
                    listenable: selected,
                    builder: (context, _) => FilledButton.icon(
                      onPressed: selected.key == null
                          ? null
                          : () => Navigator.pop(sheetContext, true),
                      icon: const Icon(Icons.link),
                      label: const Text('Collega'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  await service.stop();
  if (linked != true || !context.mounted) return;

  final sensorId = await repository.linkSensor(
    equipmentId: equipment.id,
    modelId: model.id,
    deviceKey: selected.key!,
    systemId: selected.systemId,
    label: labelController.text.trim(),
  );

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${equipment.name} \u2190 ${selected.displayName}'),
      ),
    );
    await offerSensorVerification(
      context,
      repository: repository,
      equipment: equipment,
      sensorId: sensorId,
      deviceKey: selected.key!,
    );
  }
}

class _Selection extends ChangeNotifier {
  String? key;
  String? systemId;
  String displayName = '';
  bool confirmedMove = false;
  String? occupiedBy;

  void select(String key, String displayName, String? systemId,
      String? occupiedBy) {
    if (this.key == key && this.occupiedBy == occupiedBy) return;
    this.key = key;
    this.displayName = displayName;
    this.systemId = systemId;
    this.occupiedBy = occupiedBy;
    confirmedMove = false;
    notifyListeners();
  }

  void clear() {
    key = null;
    systemId = null;
    displayName = '';
    confirmedMove = false;
    occupiedBy = null;
    notifyListeners();
  }

  bool get needsMoveConfirmation =>
      occupiedBy != null && occupiedBy != displayName && !confirmedMove;

  void confirmMove() {
    confirmedMove = true;
    notifyListeners();
  }
}

class _LinkSheetBody extends StatefulWidget {
  const _LinkSheetBody({
    required this.repository,
    required this.equipment,
    required this.model,
    required this.selection,
    required this.labelController,
  });

  final HaccpRepository repository;
  final Equipment equipment;
  final SensorModel model;
  final _Selection selection;
  final TextEditingController labelController;

  @override
  State<_LinkSheetBody> createState() => _LinkSheetBodyState();
}

class _LinkSheetBodyState extends State<_LinkSheetBody> {
  final Map<String, double> _firstTemp = {};

  /// Mappa device_key → attrezzatura che usa il sensore ("Gi\u00E0 usato
  /// per:"). Caricata una volta sola: la future vive nello State.
  late final Future<Map<String, String>> _usageFuture =
      widget.repository.getSensorUsage();
  Map<String, String> _usage = {};

  @override
  void initState() {
    super.initState();
    SensorService.instance.latest.addListener(_onChange);
    SensorService.instance.discovered.addListener(_onChange);
    widget.selection.addListener(_onChange);
  }

  @override
  void dispose() {
    SensorService.instance.latest.removeListener(_onChange);
    SensorService.instance.discovered.removeListener(_onChange);
    widget.selection.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _usageFuture,
      builder: (context, usageSnapshot) =>
          _buildContent(context, usageSnapshot.data ?? const {}),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, String> usage) {
    _usage = usage;
    final theme = Theme.of(context);
    final service = SensorService.instance;
    final equipment = widget.equipment;
    final model = widget.model;

    // Dispositivi riconosciuti dal modello scelto, ordinati per RSSI.
    final devices = service.discovered.value
        .where(model.matches)
        .toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));

    final specs = model.specs;
    final rangeWarning = specs.verified &&
            !specs.coversRange(equipment.minTemp, equipment.maxTemp)
        ? 'Attenzione: il range operativo dichiarato del sensore '
            '(${specs.minTempC!.toStringAsFixed(0)}/'
            '${specs.maxTempC!.toStringAsFixed(0)} \u00B0C) non copre i '
            'limiti di questa attrezzatura.'
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SensorModelImage(model: model, size: 96),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Modello: ${model.displayName}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Cos\u00EC \u00E8 fatto il sensore: tienilo in mano per '
                    'riconoscerlo.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (!specs.verified)
                    Text(
                      'Range operativo da verificare nel manuale del sensore.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (rangeWarning != null) ...[
          const SizedBox(height: 8),
          StatusPill(
            text: rangeWarning,
            type: StatusType.warning,
            large: true,
          ),
        ],
        if (equipment.type.toLowerCase().contains('abbat')) ...[
          const SizedBox(height: 8),
          const StatusPill(
            text: 'Il sensore misura l\u2019ambiente, non il cuore del '
                'prodotto: il ciclo di abbattimento si registra con la '
                'sonda come sempre.',
            type: StatusType.info,
            large: true,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          'Scalda il sensore con la mano: quello che sale \u00E8 il tuo.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        if (devices.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          for (final device in devices) _deviceRow(context, device),
        const SizedBox(height: 8),
        LabeledField(
          label: 'Etichetta del sensore',
          child: TextField(
            controller: widget.labelController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'es. Sensore frigo carni 1',
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Sensore non tarato: va verificato con termometro di riferimento '
          '(\u00B11 \u00B0C). Ti proponiamo la verifica subito dopo il '
          'collegamento. $sensorTrademarkNote',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _deviceRow(BuildContext context, BleAdvertisement device) {
    final theme = Theme.of(context);
    final service = SensorService.instance;
    final model = widget.model;
    final key = model.stableKey(device) ?? device.systemId;
    final sample = service.latestFor(key);
    final occupiedBy = _usage[key];
    final isSelected = widget.selection.key == key;
    // Evidenzia la riga con la variazione maggiore: aiuto
    // all'identificazione ("quello che sale è il tuo").
    String? riserBadge;
    if (sample != null) {
      final first = _firstTemp.putIfAbsent(key, () => sample.tempC);
      final delta = sample.tempC - first;
      if (delta >= 0.8) {
        riserBadge = '\u25B2 +${delta.toStringAsFixed(1)} \u00B0C';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: isSelected
            ? theme.colorScheme.primaryContainer
            : riserBadge != null
                ? theme.colorScheme.secondaryContainer
                : null,
        child: InkWell(
          onTap: () {
            final name = device.name.isEmpty ? key : device.name;
            widget.selection.select(key, name, device.systemId, occupiedBy);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_off,
                      color: isSelected ? theme.colorScheme.primary : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        device.name.isEmpty ? key : device.name,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    _RssiBars(rssi: device.rssi),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  sample == null
                      ? 'In attesa di dati\u2026'
                      : '${sample.tempC.toStringAsFixed(1)} \u00B0C'
                          '${sample.humidity != null ? ' \u2022 ${sample.humidity!.toStringAsFixed(0)}%' : ''}'
                          '${sample.batteryPercent != null ? ' \u2022 bat ${sample.batteryPercent}%' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
                if (riserBadge != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    riserBadge,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (occupiedBy != null &&
                    occupiedBy != widget.equipment.name) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Gi\u00E0 usato per: $occupiedBy',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isSelected)
                    CheckboxListTile(
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: widget.selection.confirmedMove,
                      onChanged: (_) =>
                          widget.selection.confirmMove(),
                      title: const Text(
                        'Sposta il sensore a questa attrezzatura',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barre del segnale RSSI (4 tacche; mai solo colore: anche il valore in
/// dBm resta visibile nella diagnostica).
class _RssiBars extends StatelessWidget {
  const _RssiBars({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // -100..-40 dBm su 4 tacche.
    final level = ((rssi + 100) / 15).round().clamp(1, 4);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 5,
            height: 6.0 + i * 3,
            margin: const EdgeInsets.only(left: 2),
            color: i <= level
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
      ],
    );
  }
}

/// Proposta di verifica con termometro di riferimento dopo il
/// collegamento (riusa la logica della verifica termometri: ±1 °C).
Future<void> offerSensorVerification(
  BuildContext context, {
  required HaccpRepository repository,
  required Equipment equipment,
  required int sensorId,
  required String deviceKey,
}) async {
  final service = SensorService.instance;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Verifica con termometro'),
      content: const Text(
        'Confronta il valore del sensore con il tuo termometro di '
        'riferimento (tolleranza \u00B11 \u00B0C). Farlo ora?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Pi\u00F9 tardi'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Verifica ora'),
        ),
      ],
    ),
  );
  if (proceed != true || !context.mounted) return;

  final referenceController = TextEditingController();
  final verified = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final live = service.latestFor(deviceKey);
      return AlertDialog(
        title: const Text('Confronto valori'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              live == null
                  ? 'Sensore: nessun dato recente'
                  : 'Sensore: ${live.tempC.toStringAsFixed(1)} \u00B0C',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: referenceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Termometro di riferimento \u00B0C',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confronta'),
          ),
        ],
      );
    },
  );
  if (verified != true || !context.mounted) return;

  final reference = double.tryParse(
      referenceController.text.trim().replaceAll(',', '.'));
  final live = service.latestFor(deviceKey);
  if (reference == null || live == null) return;

  final diff = live.tempC - reference;
  if (diff.abs() <= 1) {
    await repository.setSensorVerified(sensorId, DateTime.now());
    if (context.mounted) {
      final day =
          '${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sensore verificato il $day.')),
      );
    }
    return;
  }

  // Fuori tolleranza: proponi offset di calibrazione (visibile) o NC.
  final suggested = ((-diff).clamp(-3.0, 3.0) * 10).roundToDouble() / 10;
  final apply = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Scarto oltre \u00B11 \u00B0C'),
      content: Text(
        'Sensore ${live.tempC.toStringAsFixed(1)} \u00B0C vs riferimento '
        '${reference.toStringAsFixed(1)} \u00B0C (scarto '
        '${diff.toStringAsFixed(1)} \u00B0C).\n\n'
        'Puoi applicare un offset di calibrazione di '
        '${suggested > 0 ? '+' : ''}$suggested \u00B0C (sempre visibile e '
        'registrato nei log) oppure registrare una non conformit\u00E0 dal '
        'menu Controlli.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Chiudi'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('Applica offset $suggested \u00B0C'),
        ),
      ],
    ),
  );
  if (apply == true) {
    await repository.setSensorCalibration(sensorId, suggested);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Offset di calibrazione $suggested \u00B0C applicato al sensore.',
          ),
        ),
      );
    }
  }
}
