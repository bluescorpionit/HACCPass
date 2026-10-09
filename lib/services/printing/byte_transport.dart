/// Trasporti byte per la stampante generica (Prompt 11, Ã‚Â§3 bis).
///
/// L'invio non dipende da un singolo plugin: passa da [ByteTransport]
/// con implementazioni TCP raw (porta 9100, Android e iOS), BLE
/// (flutter_blue_plus, non verificato su hardware reale) e Bluetooth
/// classico SPP/RFCOMM su Android (Prompt 17, canale interno
/// "haccpass/spp"). L'USB non ÃƒÂ¨ disponibile (vedi `docs/stampanti.md`).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Profilo di velocitÃƒÂ  di invio (Prompt 17, Ã‚Â§1): blocchi, pausa tra i
/// blocchi e righe per banda dell'immagine ESC/POS. Le stampanti
/// Bluetooth hanno buffer piccoli: invii veloci troncano l'immagine.
class PrintSpeedProfile {
  const PrintSpeedProfile({
    required this.id,
    required this.label,
    required this.chunkBytes,
    required this.pause,
    required this.bandRows,
  });

  /// 'normal' | 'slow' | 'fast' (impostazione `printer_generic_speed`).
  final String id;
  final String label;
  final int chunkBytes;
  final Duration pause;
  final int bandRows;

  static const normal = PrintSpeedProfile(
    id: 'normal',
    label: 'Normale',
    chunkBytes: 256,
    pause: Duration(milliseconds: 20),
    bandRows: 64,
  );

  /// Per stampanti che perdono dati.
  static const slow = PrintSpeedProfile(
    id: 'slow',
    label: 'Lenta',
    chunkBytes: 128,
    pause: Duration(milliseconds: 50),
    bandRows: 24,
  );

  static const fast = PrintSpeedProfile(
    id: 'fast',
    label: 'Veloce',
    chunkBytes: 512,
    pause: Duration(milliseconds: 8),
    bandRows: 128,
  );

  static const List<PrintSpeedProfile> all = [normal, slow, fast];

  static PrintSpeedProfile byId(String? id) =>
      all.firstWhere((p) => p.id == id, orElse: () => normal);
}

/// Contratto di trasporto dei byte verso la stampante.
abstract class ByteTransport {
  /// Apre la connessione (la chiusa, se era aperta).
  Future<void> connect();

  /// Scrive UN blocco (giÃƒÂ  ridotto a blocchi da [write]).
  Future<void> writeChunk(List<int> bytes);

  Future<void> close();

  /// Dimensione dei blocchi consigliata dal trasporto: 512 byte di
  /// default; il BLE la calcola dall'MTU negoziata (Prompt 11-bis, Ã‚Â§4),
  /// il Bluetooth classico dal profilo di velocitÃƒÂ  (Prompt 17, Ã‚Â§1).
  int get suggestedChunkSize => 512;

  /// Pausa consigliata tra i blocchi (SPP: 20/50/8 ms secondo profilo).
  Duration get suggestedPause => const Duration(milliseconds: 8);

  /// Scrive [bytes] a blocchi (dimensione [chunkSize] o quella
  /// consigliata dal trasporto) con una piccola pausa tra i blocchi
  /// (le termiche economiche soffrono i burst).
  Future<void> write(
    List<int> bytes, {
    int? chunkSize,
    Duration? pause,
  }) async {
    final size = chunkSize ?? suggestedChunkSize;
    final delay = pause ?? suggestedPause;
    for (var i = 0; i < bytes.length; i += size) {
      final end = (i + size).clamp(0, bytes.length);
      await writeChunk(bytes.sublist(i, end));
      await Future<void>.delayed(delay);
    }
  }

  bool get isConnected;
}

/// Rete/Wi-Fi: TCP raw sulla porta 9100 (JetDirect), funziona su
/// Android e iOS. Nessuna capacitÃƒÂ  inventata: la carta non si interroga.
///
/// Prompt 16, Ã‚Â§7.2: molte termiche di rete accettano UNA sola
/// connessione alla volta Ã¢â‚¬â€ se `Socket.connect` viene rifiutato si
/// attende 1,5 s e si riprova una volta (la porta puÃƒÂ² essere ancora
/// occupata dalla connessione precedente). La chiusura attende 400 ms
/// dopo l'ultimo flush e poi chiude con grazia (mai `destroy()`, che
/// puÃƒÂ² scartare il buffer residuo).
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
    final limit = timeout ?? const Duration(seconds: 5);
    try {
      _socket = await Socket.connect(host, port, timeout: limit);
    } catch (first) {
      // La stampante puÃƒÂ² tenere la porta ancora occupata: un nuovo
      // tentativo dopo 1,5 s prima di arrendersi.
      debugPrint(
          'TCP $host:$port rifiutato al primo colpo (${first.runtimeType}): '
          'nuovo tentativo tra 1,5 s.');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      try {
        _socket = await Socket.connect(host, port, timeout: limit);
      } catch (second) {
        throw StateError(
          'Stampante $host:$port non raggiungibile: connessione rifiutata '
          'o timeout (indirizzo errato, Wi-Fi diverso o porta occupata).',
        );
      }
    }
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
    if (socket == null) return;
    try {
      await socket.flush();
    } catch (_) {
      // La stampa ÃƒÂ¨ giÃƒÂ  stata inviata: gli errori di flush a fine lavoro
      // non la invalidano.
    }
    // Lascia alla stampante il tempo di leggere il buffer residuo prima
    // della chiusura del socket.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      await socket.close();
      await socket.done;
    } catch (_) {
      // GiÃƒÂ  chiusa dall'altro lato.
    }
  }
}

/// Esito della verifica di raggiungibilitÃƒÂ  TCP (Prompt 16, Ã‚Â§7.4):
/// messaggi distinti per porta rifiutata, timeout e rete non disponibile.
enum TcpProbeOutcome { reachable, refused, timeout, networkUnavailable }

class TcpProbeResult {
  const TcpProbeResult(this.outcome, this.elapsed, this.message);

  final TcpProbeOutcome outcome;
  final Duration elapsed;
  final String message;

  bool get isReachable => outcome == TcpProbeOutcome.reachable;
}

/// Apre un socket verso [host]:[port] solo per verificare la
/// raggiungibilitÃƒÂ  (diagnosi esplicita, mai prima di stampare).
Future<TcpProbeResult> probeTcpPrinter(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    try {
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await socket.close();
      await socket.done;
    } catch (_) {}
    return TcpProbeResult(
      TcpProbeOutcome.reachable,
      sw.elapsed,
      'Raggiungibile: $host:$port ha accettato la connessione '
      'in ${sw.elapsed.inMilliseconds} ms.',
    );
  } catch (e) {
    sw.stop();
    final text = e.toString();
    final refused = text.contains('Connection refused') ||
        e is SocketException &&
            (e.osError?.errorCode == 61 ||
                e.osError?.errorCode == 111 ||
                e.osError?.errorCode == 10061);
    final noNetwork = text.contains('Network is unreachable') ||
        text.contains('No route to host') ||
        text.contains('Failed host lookup');
    if (refused) {
      return TcpProbeResult(
        TcpProbeOutcome.refused,
        sw.elapsed,
        'Connessione rifiutata da $host:$port: porta chiusa o stampante '
        'occupata (molte stampanti accettano una sola connessione: '
        'attendi qualche secondo e riprova).',
      );
    }
    if (noNetwork) {
      return TcpProbeResult(
        TcpProbeOutcome.networkUnavailable,
        sw.elapsed,
        'Rete non disponibile o indirizzo inesistente ($host): controlla '
        'Wi-Fi e IP della stampante.',
      );
    }
    return TcpProbeResult(
      TcpProbeOutcome.timeout,
      sw.elapsed,
      'Timeout verso $host:$port: IP errato, Wi-Fi diverso o '
      'isolamento client del router.',
    );
  }
}

/// Indirizzo IPv4 del telefono (per verificare che sia nella stessa
/// sottorete della stampante). Null se non disponibile.
Future<String?> phoneIpv4() async {
  try {
    final interfaces = await NetworkInterface.list();
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.type == InternetAddressType.IPv4 && !address.isLoopback) {
          return address.address;
        }
      }
    }
  } catch (_) {}
  return null;
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
  /// (Prompt 11-bis, Ã‚Â§4): `min(512, mtu - 3)`, mai sotto 20.
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
/// puÃƒÂ² simulare una MTU negoziata e la perdita di connessione al
/// [failAtBytes]-esimo byte scritto.
/// Bluetooth classico SPP/RFCOMM, SOLO Android (Prompt 17, Ã‚Â§1): canale
/// interno "haccpass/spp" (Kotlin in `BluetoothSppPlugin.kt`) con UUID
/// SPP standard. Sequenza lato nativo: socket sicuro Ã¢â€ â€™ non sicuro Ã¢â€ â€™
/// canale 1 (stampanti vecchie); qui si chiedono i permessi, si mappano
/// gli errori in italiano e si riprova dopo 1,5 s. Blocchi e pausa dal
/// profilo di velocitÃƒÂ ; UNA connessione per lavoro; chiusura con flush,
/// attesa 500 ms e `close()` (mai chiusure brusche).
///
/// NON VERIFICATO su hardware reale: la stampante ESC/POS Bluetooth
/// dell'utente ÃƒÂ¨ il primo banco di prova (vedi docs/stampanti.md).
/// Su iOS non viene mai creato (Bluetooth classico = programma MFi).
class BluetoothSppByteTransport extends ByteTransport {
  BluetoothSppByteTransport(this.address,
      {this.profile = PrintSpeedProfile.normal});

  /// Indirizzo MAC del dispositivo ASSOCIATO.
  final String address;

  final PrintSpeedProfile profile;

  static const _channel = MethodChannel('haccpass/spp');

  bool _connected = false;

  int _sentBytes = 0;

  /// Byte inviati nell'ultima connessione (diagnostica).
  int get sentBytes => _sentBytes;

  @override
  int get suggestedChunkSize => profile.chunkBytes;

  @override
  Duration get suggestedPause => profile.pause;

  @override
  bool get isConnected => _connected;

  /// Messaggi in italiano distinti per codice (Prompt 17, Ã‚Â§4).
  @visibleForTesting
  static String messageForCode(String code) => switch (code) {
        'off' => 'Bluetooth spento: attivalo dalle impostazioni del '
            'telefono e riprova.',
        'permission' => 'Permesso Bluetooth negato: abilitalo per '
            'HACCPass nelle impostazioni del telefono.',
        'not_bonded' => 'Stampante non associata: associala dalle '
            'impostazioni Bluetooth del telefono (PIN di solito 0000 o '
            '1234), poi tocca "Cerca stampanti".',
        'unreachable' || 'timeout' => 'Non riesco a collegarmi: accendi '
            'la stampante e avvicinala al telefono (se è collegata a un '
            'altro dispositivo, scollegala).',
        'busy' => 'Stampante occupata o già collegata: scollegala '
            'dall\'altro dispositivo e riprova.',
        'lost' => 'Connessione Bluetooth caduta durante l\'invio: '
            'riprova la stampa.',
        _ => 'Collegamento Bluetooth non riuscito: riprova.',
      };

  @override
  Future<void> connect() async {
    if (!Platform.isAndroid) {
      throw StateError(
        'Bluetooth classico disponibile solo su Android: usa Wi-Fi o '
        'Bluetooth LE.',
      );
    }
    await close();
    try {
      await _channel.invokeMethod<bool>(
        'connect',
        {'address': address},
      );
      _connected = true;
      _sentBytes = 0;
    } on PlatformException catch (e) {
      final code = e.code;
      // Un nuovo tentativo dopo 1,5 s per gli errori transitori
      // (spenta ma che si sveglia, porta occupata dal lavoro prima).
      if (code == 'unreachable' || code == 'timeout' || code == 'busy') {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        try {
          await _channel.invokeMethod<bool>(
            'connect',
            {'address': address},
          );
          _connected = true;
          _sentBytes = 0;
          return;
        } on PlatformException catch (second) {
          // Nessun MAC completo nei log (criterio Prompt 17): solo il
          // codice e l'ultimo carattere dell'errore.
          debugPrint('SPP: secondo tentativo fallito (${second.code}).');
          throw StateError(messageForCode(second.code));
        }
      }
      debugPrint('SPP: connessione fallita ($code).');
      throw StateError(messageForCode(code));
    } on MissingPluginException {
      throw StateError(
        'Bluetooth classico non disponibile in questa build: usa Wi-Fi '
        'o Bluetooth LE.',
      );
    }
  }

  @override
  Future<void> writeChunk(List<int> bytes) async {
    if (!_connected) {
      throw StateError('Bluetooth non connesso');
    }
    try {
      await _channel.invokeMethod<bool>(
        'write',
        {'bytes': Uint8List.fromList(bytes)},
      );
      _sentBytes += bytes.length;
    } on PlatformException catch (e) {
      _connected = false;
      throw StateError(messageForCode(e.code));
    }
  }

  @override
  Future<void> close() async {
    if (!_connected) return;
    _connected = false;
    try {
      // Il lato nativo fa flush + attesa 500 ms + close.
      await _channel.invokeMethod<bool>('disconnect');
    } catch (_) {
      // GiÃƒÂ  chiusa dall'altro lato.
    }
  }

  /// Elenco dei dispositivi GIÃƒâ‚¬ ASSOCIATI (nome + MAC): i candidati
  /// stampante prima, ma tutti selezionabili (Prompt 17, Ã‚Â§2).
  static Future<List<Map<String, String>>> listPaired() async {
    final list = await _channel.invokeListMethod<Map<dynamic, dynamic>>(
      'listPaired',
    );
    return [
      for (final entry in list ?? const [])
        {
          'name': (entry['name'] ?? '') as String,
          'address': (entry['address'] ?? '') as String,
        },
    ];
  }

  /// true se il nome sembra quello di una stampante (ordinamento).
  static bool looksLikePrinter(String name) {
    final n = name.toLowerCase();
    return [
      'printer',
      'pos',
      'bt-',
      'mtp',
      'rpp',
      'pt-',
      'xp',
      'mht',
      'printer-',
      'tm-',
      'gb',
      'zc',
    ].any((k) => n.contains(k));
  }

  /// Elenco tipizzato dei dispositivi associati (nome + MAC).
  static Future<List<({String name, String address})>>
      listPairedRecords() async {
    final raw = await listPaired();
    return [
      for (final d in raw) (name: d['name'] ?? '', address: d['address'] ?? ''),
    ];
  }

  /// Apre le impostazioni Bluetooth di Android ("Associa nuova
  /// stampante", Prompt 17, Ã‚Â§2).
  static Future<void> openBluetoothSettings() async {
    try {
      await _channel.invokeMethod<bool>('openBluetoothSettings');
    } catch (_) {
      // Non Android o canale assente: silenzio.
    }
  }
}

class FakeByteTransport extends ByteTransport {
  FakeByteTransport({this.failAtBytes, int? mtu})
      : suggestedChunkSize =
            mtu == null || mtu <= 0 ? 512 : (mtu - 3).clamp(20, 512);

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
/// riprova una volta (Prompt 11, Ã‚Â§3 bis). Restituisce false se anche il
/// secondo tentativo fallisce. La dimensione dei blocchi ÃƒÂ¨ quella
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

/// Dispositivo Bluetooth classico associato (Prompt 17).
typedef SppPairedDevice = ({String name, String address});
