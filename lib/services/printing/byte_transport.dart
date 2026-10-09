/// Trasporti byte per la stampante generica (Prompt 11, §3 bis).
///
/// L'invio non dipende da un singolo plugin: passa da [ByteTransport]
/// con implementazioni TCP raw (porta 9100, Android e iOS) e BLE
/// (flutter_blue_plus, non verificato su hardware reale). Il Bluetooth
/// classico SPP e l'USB non sono disponibili in questa versione (vedi
/// `docs/stampanti.md`).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Contratto di trasporto dei byte verso la stampante.
abstract class ByteTransport {
  /// Apre la connessione (la chiusa, se era aperta).
  Future<void> connect();

  /// Scrive UN blocco (già ridotto a blocchi da [write]).
  Future<void> writeChunk(List<int> bytes);

  Future<void> close();

  /// Dimensione dei blocchi consigliata dal trasporto: 512 byte di
  /// default; il BLE la calcola dall'MTU negoziata (Prompt 11-bis, §4).
  int get suggestedChunkSize => 512;

  /// Scrive [bytes] a blocchi (dimensione [chunkSize] o quella
  /// consigliata dal trasporto) con una piccola pausa tra i blocchi
  /// (le termiche economiche soffrono i burst).
  Future<void> write(
    List<int> bytes, {
    int? chunkSize,
    Duration pause = const Duration(milliseconds: 8),
  }) async {
    final size = chunkSize ?? suggestedChunkSize;
    for (var i = 0; i < bytes.length; i += size) {
      final end = (i + size).clamp(0, bytes.length);
      await writeChunk(bytes.sublist(i, end));
      await Future<void>.delayed(pause);
    }
  }

  bool get isConnected;
}

/// Rete/Wi-Fi: TCP raw sulla porta 9100 (JetDirect), funziona su
/// Android e iOS. Nessuna capacità inventata: la carta non si interroga.
class TcpByteTransport extends ByteTransport {
  TcpByteTransport(this.host, {this.port = 9100, this.timeout});

  final String host;
  final int port;
  final Duration? timeout;

  Socket? _socket;

  @override
  bool get isConnected => _socket != null;

  @override
  Future<void> connect() async {
    await close();
    _socket = await Socket.connect(
      host,
      port,
      timeout: timeout ?? const Duration(seconds: 5),
    );
  }

  @override
  Future<void> writeChunk(List<int> bytes) async {
    final socket = _socket;
    if (socket == null) {
      throw StateError('TCP non connesso');
    }
    socket.add(bytes);
    // Flush periodico per non saturare il buffer.
    if (bytes.length >= 512) {
      await socket.flush();
    }
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    await socket?.flush();
    await socket?.close();
  }
}

/// Bluetooth LE: scrive su una caratteristica scrivibile del servizio
/// scelto (o sulla prima trovata). NON VERIFICATO su hardware reale:
/// dichiarato come tale nella UI e nella documentazione.
class BleByteTransport extends ByteTransport {
  BleByteTransport({
    required this.deviceId,
    this.characteristicId,
  });

  final String deviceId;
  final String? characteristicId;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _characteristic;

  /// Blocchi calcolati dall'MTU negoziata dopo la connessione
  /// (Prompt 11-bis, §4): `min(512, mtu - 3)`, mai sotto 20.
  @override
  int suggestedChunkSize = 512;

  @override
  bool get isConnected => _device?.isConnected ?? false;

  @override
  Future<void> connect() async {
    await close();
    final device = BluetoothDevice(remoteId: DeviceIdentifier(deviceId));
    await device.connect(timeout: const Duration(seconds: 10));
    _device = device;
    final services = await device.discoverServices();
    for (final service in services) {
      for (final characteristic in service.characteristics) {
        if (characteristicId != null) {
          if (characteristic.uuid.str128.toLowerCase() ==
              characteristicId!.toLowerCase()) {
            _characteristic = characteristic;
            break;
          }
        } else if (characteristic.properties.write ||
            characteristic.properties.writeWithoutResponse) {
          _characteristic = characteristic;
          break;
        }
      }
      if (_characteristic != null) break;
    }
    if (_characteristic == null) {
      await device.disconnect();
      _device = null;
      throw StateError(
        'Nessuna caratteristica scrivibile trovata (provare "Avanzate" e '
        'scegliere la caratteristica della stampante)',
      );
    }
    // MTU negoziata: overhead ATT di 3 byte, blocco mai sotto 20.
    final mtu = device.mtuNow;
    suggestedChunkSize = mtu > 0 ? (mtu - 3).clamp(20, 512) : 20;
  }

  @override
  Future<void> writeChunk(List<int> bytes) async {
    final characteristic = _characteristic;
    if (characteristic == null) {
      throw StateError('BLE non connesso');
    }
    // Se la caratteristica supporta la scrittura CON risposta la si usa
    // (affidabile per i job piccoli); altrimenti withoutResponse e la
    // pausa tra i blocchi resta gestita da [write].
    await characteristic.write(
      Uint8List.fromList(bytes),
      withoutResponse: !characteristic.properties.write,
    );
  }

  @override
  Future<void> close() async {
    _characteristic = null;
    await _device?.disconnect();
    _device = null;
  }
}

/// Trasporto finto per i test: registra byte e dimensione dei blocchi,
/// può simulare una MTU negoziata e la perdita di connessione al
/// [failAtBytes]-esimo byte scritto.
class FakeByteTransport extends ByteTransport {
  FakeByteTransport({this.failAtBytes, int? mtu})
      : suggestedChunkSize = mtu == null || mtu <= 0
            ? 512
            : (mtu - 3).clamp(20, 512);

  final List<int> written = [];

  /// Dimensione di OGNI blocco ricevuto (per i test MTU).
  final List<int> chunkSizes = [];
  final int? failAtBytes;
  int connectCalls = 0;
  int closeCalls = 0;
  bool _connected = false;
  bool _failedOnce = false;

  @override
  int suggestedChunkSize;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    connectCalls++;
    // Nuova connessione: il registro dei byte riparte (come uno stream
    // reale appena aperto).
    written.clear();
    chunkSizes.clear();
    _connected = true;
  }

  @override
  Future<void> writeChunk(List<int> bytes) async {
    if (failAtBytes != null && !_failedOnce && written.length >= failAtBytes!) {
      _failedOnce = true;
      _connected = false;
      throw const SocketException('connessione persa (test)');
    }
    chunkSizes.add(bytes.length);
    written.addAll(bytes);
  }

  @override
  Future<void> close() async {
    closeCalls++;
    _connected = false;
  }
}

/// Invio con UN nuovo tentativo: alla prima caduta chiude, ricollega e
/// riprova una volta (Prompt 11, §3 bis). Restituisce false se anche il
/// secondo tentativo fallisce. La dimensione dei blocchi è quella
/// consigliata dal trasporto (MTU per il BLE).
Future<bool> sendWithRetry(
  ByteTransport transport,
  List<int> bytes, {
  int? chunkSize,
}) async {
  try {
    await transport.write(bytes, chunkSize: chunkSize);
    return true;
  } catch (e) {
    // Nessun indirizzo/ID nei log (criterio Prompt 11): solo il tipo.
    debugPrint(
        'Trasporto stampante: primo invio fallito (${e.runtimeType}), riprovo.');
  }
  try {
    await transport.close();
    await transport.connect();
    await transport.write(bytes, chunkSize: chunkSize);
    return true;
  } catch (e) {
    debugPrint(
        'Trasporto stampante: nuovo tentativo fallito (${e.runtimeType}).');
    await transport.close();
    return false;
  }
}
