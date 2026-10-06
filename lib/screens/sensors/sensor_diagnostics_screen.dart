import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/sensors/ble_sensor_source.dart';
import '../../core/sensors/govee_h5179_decoder.dart';
import '../../core/sensors/sensor_model.dart';
import '../../widgets/common_widgets.dart';

/// FASE 0 (piano sensori Govee H5179): schermata DI SOLA DIAGNOSTICA,
/// visibile solo in build di debug (voce nascosta in "Altro").
///
/// Riusa il [SensorService] condiviso e il `sensorRegistry`: mostra nome,
/// MAC/ID, RSSI, `manufacturerData`/`serviceData` grezzi in esadecimale e
/// la lettura decodificata. Nessun dato viene salvato: serve a confrontare
/// byte e valori con display del sensore e app Govee Home e a registrare
/// l'esito in `docs/govee_h5179.md`.
class SensorDiagnosticsScreen extends StatefulWidget {
  const SensorDiagnosticsScreen({super.key});

  @override
  State<SensorDiagnosticsScreen> createState() =>
      _SensorDiagnosticsScreenState();
}

class _SensorDiagnosticsScreenState extends State<SensorDiagnosticsScreen> {
  bool _scanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    SensorService.instance.latest.addListener(_onChange);
    SensorService.instance.discovered.addListener(_onChange);
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SensorService.instance.latest.removeListener(_onChange);
    SensorService.instance.discovered.removeListener(_onChange);
    _stop();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    setState(() => _error = null);
    if (_scanning) {
      await _stop();
      return;
    }
    try {
      await SensorService.instance.start(
        timeout: const Duration(seconds: 30),
      );
      if (mounted) setState(() => _scanning = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'Impossibile avviare la scansione: $error\n'
              'Verifica Bluetooth attivo e permessi concessi.';
        });
      }
    }
  }

  Future<void> _stop() async {
    await SensorService.instance.stop();
    if (mounted) setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = SensorService.instance.discovered.value;

    return FeatureScaffold(
      title: 'Diagnostica sensori',
      subtitle: 'Solo debug (Fase 0): nessun dato viene salvato.',
      scrollable: false,
      padding: EdgeInsets.zero,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  onPressed: _toggleScan,
                  icon: Icon(
                    _scanning ? Icons.stop : Icons.bluetooth_searching,
                  ),
                  label: Text(
                    _scanning ? 'Ferma scansione' : 'Avvia scansione (30 s)',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'L\u2019H5179 pubblica i dati nella scan response: serve una '
                  'scansione ATTIVA e alcuni secondi. Con il sensore dentro '
                  'un frigo in acciaio avvicina il telefono allo sportello.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  '${devices.length} dispositivi visti',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: screenPadding(context, top: 8),
              children: [
                for (final device in devices) _DeviceCard(device: device),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});

  final BleAdvertisement device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = GoveeH5179Decoder.decode(
      localName: device.name,
      manufacturerData: device.manufacturerData,
    );
    final isGovee = GoveeH5179Decoder.isH5179Name(device.name);

    String hex(List<int> bytes) => bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Card(
        color: isGovee ? theme.colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      device.name.isEmpty ? '(senza nome)' : device.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(
                    '${device.rssi} dBm',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                device.systemId,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (reading != null) ...[
                const SizedBox(height: 8),
                StatusPill(
                  text: reading.toString(),
                  type: StatusType.success,
                  large: true,
                ),
              ] else if (isGovee) ...[
                const SizedBox(height: 8),
                const StatusPill(
                  text: 'Govee rilevato, pacchetto non decodificato',
                  type: StatusType.warning,
                ),
              ],
              if (device.manufacturerData.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final entry in device.manufacturerData.entries)
                  Text(
                    'mfr 0x${entry.key.toRadixString(16).padLeft(4, '0')}: '
                    '${hex(entry.value)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
              ],
              if (device.serviceData.isNotEmpty) ...[
                const SizedBox(height: 4),
                for (final entry in device.serviceData.entries)
                  Text(
                    'svc ${entry.key}: ${hex(entry.value)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
