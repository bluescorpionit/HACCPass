import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:niim_blue_flutter/niim_blue_flutter.dart';

import '../../core/printing/label_printer.dart';
import '../../core/printing/label_rasterizer.dart';
import 'niimbot_label_printer.dart';

/// Implementazione reale dell'adattatore Niimbot su `niim_blue_flutter`
/// (flutter_blue_plus 2.x via dependency_overrides, vedi pubspec e
/// docs/stampanti.md). Tutto il pacchetto resta confinato qui.
class NiimBlueClientAdapter implements NiimbotClientAdapter {
  NiimbotBluetoothClient? _client;

  @override
  bool get isConnected => _client?.isConnected() ?? false;

  @override
  Future<List<PrinterDevice>> discover() async {
    try {
      final devices = await NiimbotBluetoothClient.listDevices();
      return [
        for (final device in devices)
          PrinterDevice(
            name: device.platformName.isEmpty
                ? 'Niimbot'
                : device.platformName,
            id: device.remoteId.str,
            transport: PrintTransport.ble,
          ),
      ];
    } catch (e) {
      debugPrint('Ricerca Niimbot fallita: $e');
      return const [];
    }
  }

  @override
  Future<NiimbotCapabilities> connect(String deviceId) async {
    await disconnect();
    final client = NiimbotBluetoothClient();
    _client = client;
    try {
      client.setDevice(BluetoothDevice(remoteId: DeviceIdentifier(deviceId)));
      await client.connect();
      final meta = client.getModelMetadata();
      if (meta == null) {
        throw StateError(
          'Modello Niimbot non riconosciuto dalla libreria: aggiorna '
          'l\u2019app (vedi docs/stampanti.md).',
        );
      }
      return NiimbotCapabilities(
        model: meta.model.name.toUpperCase(),
        dpi: meta.dpi,
        printheadPixels: meta.printheadPixels,
        densityMin: meta.densityMin,
        densityMax: meta.densityMax,
      );
    } catch (e) {
      await disconnect();
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    final client = _client;
    _client = null;
    try {
      await client?.dispose();
    } catch (e) {
      debugPrint('Disconnessione Niimbot: $e');
    }
  }

  @override
  Future<void> printMono(
    MonoBitmap image, {
    required int density,
    int copies = 1,
  }) async {
    final client = _client;
    if (client == null || !client.isConnected()) {
      throw StateError('Niimbot non collegata');
    }
    client.stopHeartbeat();
    client.setPacketInterval(0);
    final task = client.createPrintTask(
      PrintOptions(
        totalPages: copies,
        density: density,
        labelType: LabelType.withGaps, // etichette con gap (standard)
      ),
    );
    if (task == null) {
      client.startHeartbeat();
      throw StateError('Task di stampa non creato: modello non supportato.');
    }

    final page = PrintPage(image.width, image.height);
    page.addPixelData(
      ImageOptions(
        data: image.toPixelList(),
        imageWidth: image.width,
        imageHeight: image.height,
        x: 0,
        y: 0,
        width: image.width,
        height: image.height,
      ),
    );
    try {
      await task.printInit();
      await task.printPage(page.toEncodedImage(), copies);
      await task.waitForFinished();
    } finally {
      client.startHeartbeat();
    }
  }
}
