import 'package:brother_native_print/brother_native_print.dart' as brother;
import 'package:flutter/foundation.dart';

import '../../core/printing/label_printer.dart';
import 'bluetooth_permissions.dart';

/// Motore Brother serie QL/RJ tramite SDK ufficiale `brother_native_print`
/// (Prompt 11, §2).
///
/// Modelli VERIFICATI dal plugin: **QL-820NWB** e **RJ-2050**. Ogni altro
/// modello (es. **QL-810W**: NON verificata) viene rifiutato da
/// `connect()` del plugin: l'utente riceve un messaggio chiaro, niente
/// promesse.
///
/// Connessioni: **Wi-Fi** (preferita: funziona anche su iOS senza
/// programma MFi) e USB su Android; Bluetooth consentito su Android. Su
/// iOS il Bluetooth Brother richiede l'iscrizione MFi con PPID Brother:
/// **nascosto** salvo [enableBluetoothIos] esplicito (vedi
/// `docs/stampanti.md`).
///
/// Le stampanti Bluetooth classico vanno **associate prima** nelle
/// impostazioni del telefono (il plugin non scopre dispositivi non
/// associati).
class BrotherLabelPrinter implements LabelPrinter {
  BrotherLabelPrinter({this.enableBluetoothIos = false});

  /// Solo per build distribuite con PPID MFi Brother registrato.
  final bool enableBluetoothIos;

  final brother.BrotherNativePrint _plugin = brother.BrotherNativePrint();
  final Map<String, brother.BrotherPrinter> _discovered = {};
  bool _connected = false;

  /// Formato app → larghezza (mm) del rotolo DK atteso.
  static const Map<String, int> formatRollWidthMm = {
    '62x40': 62,
    '50x30': 50,
    '40x30': 40,
  };

  @override
  String get id => 'brother';

  @override
  String get displayName => 'Brother QL';

  @override
  Future<List<PrinterDevice>> discover() async {
    final list = await _plugin.discoverPrinters();
    _discovered.clear();
    final devices = <PrinterDevice>[];
    for (final printer in list) {
      if (_hideBluetoothOnIos &&
          printer.connectionType ==
              brother.BrotherConnectionType.bluetooth) {
        continue;
      }
      final id = stableIdOf(printer);
      _discovered[id] = printer;
      final transport = switch (printer.connectionType) {
        brother.BrotherConnectionType.wifi => PrintTransport.wifi,
        brother.BrotherConnectionType.bluetooth => PrintTransport.bluetooth,
        brother.BrotherConnectionType.usb => PrintTransport.usb,
      };
      devices.add(PrinterDevice(
        name: printer.model,
        id: id,
        transport: transport,
        detail:
            printer.ipAddress ?? printer.macAddress ?? printer.serialNumber,
      ));
    }
    return devices;
  }

  bool get _hideBluetoothOnIos =>
      defaultTargetPlatform == TargetPlatform.iOS && !enableBluetoothIos;

  /// Id stabile per ricollegarsi dopo un riavvio.
  @visibleForTesting
  static String stableIdOf(brother.BrotherPrinter p) {
    final key = switch (p.connectionType) {
      brother.BrotherConnectionType.wifi => 'wifi:${p.ipAddress ?? ''}',
      brother.BrotherConnectionType.bluetooth => 'bt:${p.macAddress ?? ''}',
      brother.BrotherConnectionType.usb => 'usb:${p.serialNumber}',
    };
    return '$key|${p.model}';
  }

  /// Ricostruisce la stampante dalle impostazioni salvate (Wi-Fi: da
  /// indirizzo IP; Bluetooth/USB serve una nuova ricerca).
  brother.BrotherPrinter? _fromSavedId(String id) {
    final parts = id.split('|');
    if (parts.length != 2) return null;
    final (prefix, model) = (parts[0], parts[1]);
    if (prefix.startsWith('wifi:')) {
      final ip = prefix.substring(5);
      if (ip.isEmpty) return null;
      return brother.BrotherPrinter(
        model: model,
        connectionType: brother.BrotherConnectionType.wifi,
        ipAddress: ip,
        serialNumber: '',
      );
    }
    return _discovered[id];
  }

  @override
  Future<void> connect(PrinterDevice device) async {
    if (device.transport == PrintTransport.bluetooth ||
        device.transport == PrintTransport.ble) {
      final granted = await requestBluetoothForPrinters();
      if (!granted) {
        throw StateError(
          'Permessi Bluetooth mancanti: consentili nelle impostazioni per '
          'collegare la stampante.',
        );
      }
    }
    final printer = _discovered[device.id] ?? _fromSavedId(device.id);
    if (printer == null) {
      throw StateError(
        'Stampante non pi\u00F9 raggiungibile: cerca di nuovo (per il '
        'Bluetooth/USB serve una nuova ricerca dopo il riavvio).',
      );
    }
    final ok = await _plugin.connect(printer);
    if (!ok) {
      _connected = false;
      throw StateError(
        'Collegamento non riuscito: modello non verificato (il motore '
        'supporta QL-820NWB e RJ-2050; la QL-810W ad esempio NON \u00E8 '
        'ancora verificata) oppure stampante spenta/non raggiungibile.',
      );
    }
    _connected = true;
    _discovered[device.id] = printer;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    await _plugin.disconnect();
  }

  @override
  bool get isConnected => _connected;

  /// Verifica carta e formato: il rotolo montato deve corrispondere alla
  /// larghezza dell'etichetta scelta (i dati arrivano dal sensore della
  /// stampante, nessuna capacità inventata).
  @visibleForTesting
  Future<PrintResult?> validateMedia(LabelSpec spec) async {
    final status = await _plugin.getPrinterStatus();
    if (status == null) return null;
    if (!status.isOk) {
      final code = status.errorCode ?? '';
      if (code.contains('outOfPaper') || code.contains('empty')) {
        return const PrintResult(PrintOutcome.paperError);
      }
      if (code.contains('coverOpen')) {
        return const PrintResult(PrintOutcome.coverOpen);
      }
      if (code.contains('busy')) {
        return const PrintResult(PrintOutcome.busy);
      }
    }
    final expectedMm = formatRollWidthMm[spec.format] ?? 62;
    final mountedMm = status.mediaWidthMm;
    if (mountedMm != 0 && mountedMm != expectedMm) {
      return PrintResult(
        PrintOutcome.labelSizeNotSupported,
        'Rotolo montato non adatto: montato $mountedMm mm, l\u2019etichetta '
        'scelta \u00E8 da $expectedMm mm. Sostituisci il rotolo DK o cambia '
        'formato in Impostazioni \u2192 Stampante.',
      );
    }
    return null;
  }

  @override
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  }) async {
    final mediaError = await validateMedia(spec);
    if (mediaError != null) return mediaError;

    final status = await _plugin.getPrinterStatus();
    // Rotolo effettivo: il tipo rilevato dalla stampante se disponibile,
    // altrimenti il rotolo continuo da 62 mm.
    final paperType =
        status?.detectedPaperType ?? (spec.widthMm == 62 ? 'RollW62' : null);

    for (final page in pdfPages) {
      for (var i = 0; i < copies.clamp(1, 999); i++) {
        final result = await _plugin.printPdf(
          page,
          options: brother.PrintOptions(
            copies: 1,
            paperType: paperType,
            autoCut: spec.autoCut,
          ),
        );
        if (result.success) continue;
        final outcome = switch (result.error?.code) {
          brother.BrotherPrintErrorCode.outOfPaper => PrintOutcome.paperError,
          brother.BrotherPrintErrorCode.coverOpen => PrintOutcome.coverOpen,
          brother.BrotherPrintErrorCode.printerUnreachable ||
          brother.BrotherPrintErrorCode.communicationLost =>
            PrintOutcome.notConnected,
          _ => null,
        };
        if (outcome != null) {
          return PrintResult(outcome, result.error?.message);
        }
        // Tentativo di recupero (stampante "occupata"): annulla,
        // disconnetti, ricollega, riprova una volta.
        final recovered = await _recoverAndRetry(page, paperType, spec);
        if (recovered != null) return recovered;
      }
    }
    return const PrintResult(PrintOutcome.ok);
  }

  /// cancelPrinting → disconnect → connect → nuova stampa (Prompt 11, §2).
  Future<PrintResult?> _recoverAndRetry(
    Uint8List page,
    String? paperType,
    LabelSpec spec,
  ) async {
    debugPrint('Stampante Brother occupata: tentativo di recupero.');
    try {
      await _plugin.cancelPrinting();
      await _plugin.disconnect();
      final stillThere = await _plugin.getConnectedPrinter();
      final ok = stillThere != null && await _plugin.connect(stillThere);
      if (!ok) {
        _connected = false;
        return PrintResult(
          PrintOutcome.busy,
          'Stampante occupata: riavvia la stampante e riprova.',
        );
      }
      final retry = await _plugin.printPdf(
        page,
        options: brother.PrintOptions(
          copies: 1,
          paperType: paperType,
          autoCut: spec.autoCut,
        ),
      );
      if (retry.success) return null; // prosegui il resto della coda
      return PrintResult(
        PrintOutcome.failed,
        'Stampa non riuscita (${retry.error?.message ?? 'errore SDK'}).',
      );
    } catch (e) {
      debugPrint('Recupero Brother fallito: $e');
      return const PrintResult(PrintOutcome.busy);
    }
  }

  @override
  Future<PrinterStatus> status() async {
    final connected = await _plugin.getConnectedPrinter();
    if (connected == null) {
      _connected = false;
      return const PrinterStatus(connected: false, ok: false);
    }
    final hw = await _plugin.getPrinterStatus();
    if (hw == null) {
      return PrinterStatus(connected: true, ok: false, detail: connected.model);
    }
    final code = hw.errorCode ?? '';
    return PrinterStatus(
      connected: true,
      ok: hw.isOk,
      paperOut: code.contains('outOfPaper') || code.contains('empty'),
      coverOpen: code.contains('coverOpen'),
      detail: '${connected.model}'
          '${hw.mediaWidthMm > 0 ? ' \u2022 rotolo ${hw.mediaWidthMm} mm' : ''}',
    );
  }
}
