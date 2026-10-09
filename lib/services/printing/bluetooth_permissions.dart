import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Permessi runtime Bluetooth per la ricerca delle stampanti (Prompt 11).
///
/// Chiesti SOLO al momento di cercare/collegare una stampante, mai
/// all'avvio. Su Android 12+ servono `BLUETOOTH_SCAN` (neverForLocation)
/// e `BLUETOOTH_CONNECT`; su Android ≤ 11 la ricerca richiede anche la
/// posizione. Su iOS nessun permesso dedicato: chiede il sistema all'uso.
Future<bool> requestBluetoothForPrinters() async {
  if (kIsWeb || !Platform.isAndroid) return true;

  try {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    bool ok(Permission p) {
      final s = statuses[p] ?? PermissionStatus.denied;
      return s.isGranted || s.isLimited || s.isProvisional;
    }

    final scanConnectOk =
        ok(Permission.bluetoothScan) && ok(Permission.bluetoothConnect);
    // Solo su Android ≤ 11 la posizione blocca davvero la ricerca.
    final locationNeeded = _androidMajor() != null && _androidMajor()! <= 11;
    final granted = scanConnectOk &&
        (!locationNeeded || ok(Permission.locationWhenInUse));
    if (!granted) {
      debugPrint('Permessi Bluetooth stampanti non concessi: $statuses');
    }
    return granted;
  } catch (e) {
    debugPrint('Richiesta permessi Bluetooth fallita: $e');
    return false;
  }
}

/// Major della release Android (es. "Android 14" → 14), null se non
/// interpretabile. Android ≤ 11 = permessi Bluetooth storici + posizione.
int? _androidMajor() {
  if (!Platform.isAndroid) return null;
  final match =
      RegExp(r'(\d+)').firstMatch(Platform.operatingSystemVersion);
  return match == null ? null : int.tryParse(match.group(1)!);
}
