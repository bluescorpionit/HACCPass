import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'sensor_model.dart';
import 'sensor_registry.dart';
import 'sensor_source.dart';

/// Stato di un sensore rispetto alla soglia di "dato vecchio".
enum SensorStatus { live, stale, offline }

/// Contratto dello scanner BLE (iniettabile: nei test si passa un fake).
abstract class SensorScanner {
  /// Avvia la scansione: i permessi Bluetooth si chiedono QUI, al primo
  /// uso, mai all'avvio dell'app.
  Future<void> start({Duration timeout});

  Future<void> stop();

  /// Flusso cumulativo dei dispositivi visti.
  Stream<List<BleAdvertisement>> get advertisements;
}

/// Scanner reale su flutter_blue_plus, stessa configurazione della
/// diagnostica: scansione ATTIVA a bassa latenza (l'H5179 pubblica il
/// payload nella scan response).
class FlutterBluePlusScanner implements SensorScanner {
  FlutterBluePlusScanner() {
    _sub = FlutterBluePlus.scanResults.listen(
      (results) {
        if (_controller.isClosed) return;
        _controller.add([
          for (final r in results)
            BleAdvertisement(
              name: r.advertisementData.advName.isNotEmpty
                  ? r.advertisementData.advName
                  : r.device.platformName,
              systemId: r.device.remoteId.str,
              rssi: r.rssi,
              manufacturerData: r.advertisementData.manufacturerData,
              serviceData: {
                for (final e in r.advertisementData.serviceData.entries)
                  e.key.str: e.value,
              },
              seenAt: DateTime.now(),
            ),
        ]);
      },
      onError: (Object error) => _controller.addError(error),
    );
  }

  final _controller = StreamController<List<BleAdvertisement>>.broadcast();
  StreamSubscription<List<ScanResult>>? _sub;

  @override
  Stream<List<BleAdvertisement>> get advertisements => _controller.stream;

  @override
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) async {
    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  @override
  Future<void> stop() => FlutterBluePlus.stopScan();

  @visibleForTesting
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_controller.close());
  }
}

/// Servizio condiviso dei sensori (singleton) — implementa [SensorSource]
/// BLE: avvia/ferma la scansione, tiene in memoria l'ultima lettura per
/// sensore, espone `Stream` e `latestFor(key)` e calcola lo stato
/// live/stale/offline. La scansione parte SOLO dalle schermate che la
/// richiedono (Temperature, Collega sensore) e si ferma all'uscita: nessuna
/// scansione in background in questa fase.
class SensorService implements SensorSource {
  SensorService._(this._scanner, this._now);

  static SensorService? _instance;

  /// Istanza dell'app (scanner BLE reale). Lazy: nessuna risorsa
  /// Bluetooth finché la prima schermata sensori non la usa.
  static SensorService get instance =>
      _instance ??= SensorService._(FlutterBluePlusScanner(), DateTime.now);

  /// Sostituisce l'istanza (solo test).
  @visibleForTesting
  static set instanceForTest(SensorService? service) => _instance = service;

  /// Costruttore per i test: scanner finto + orologio finto.
  @visibleForTesting
  factory SensorService.forTest(
    SensorScanner scanner, {
    DateTime Function()? now,
  }) {
    return SensorService._(scanner, now ?? DateTime.now);
  }

  final SensorScanner _scanner;
  final DateTime Function() _now;

  /// Soglia "dato vecchio" (configurabile, default 10 min).
  Duration staleAfter = const Duration(minutes: 10);

  StreamSubscription<List<BleAdvertisement>>? _subscription;
  final Map<String, SensorSample> _latest = {};
  final _samplesController = StreamController<SensorSample>.broadcast();

  void Function(SensorSample sample)? _readingSink;

  /// Collega il sink di persistenza (il repository applica throttling e
  /// retention). Chiamato all'avvio dell'app, non dal costruttore.
  void attachSink(void Function(SensorSample sample)? sink) {
    _readingSink = sink;
  }

  /// Ultime letture per chiave sensore: notifica le UI.
  final ValueNotifier<Map<String, SensorSample>> latest =
      ValueNotifier<Map<String, SensorSample>>(const {});

  /// Advertisement visti dall'ultima scansione (per "Collega sensore").
  final ValueNotifier<List<BleAdvertisement>> discovered =
      ValueNotifier(const []);

  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  String get id => 'ble';

  @override
  Stream<SensorSample> get samples => _samplesController.stream;

  /// Avvia la scansione condivisa. Se i permessi sono negati o il Bluetooth
  /// è spento rilancia l'errore al chiamante, che mostra il messaggio e il
  /// ripiego Manuale: l'app resta pienamente utilizzabile.
  @override
  Future<void> start({Duration timeout = const Duration(seconds: 30)}) async {
    if (_running) return;
    _running = true;
    _subscription ??= _scanner.advertisements.listen(
      (advertisements) {
        if (!_running) return;
        discovered.value = advertisements;
        var changed = false;
        for (final a in advertisements) {
          for (final model in sensorRegistry) {
            if (!model.matches(a)) continue;
            final sample = model.decode(a);
            if (sample == null) continue;
            _latest[sample.sensorId] = sample;
            changed = true;
            _samplesController.add(sample);
            _readingSink?.call(sample);
          }
        }
        if (changed) latest.value = Map.unmodifiable(_latest);
      },
      onError: (_) {
        // Errori di scansione: nessun dato inventato.
      },
    );
    try {
      await _scanner.start(timeout: timeout);
    } catch (_) {
      _running = false;
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    try {
      await _scanner.stop();
    } catch (_) {
      // Fermare due volte o senza permessi non è un errore per l'utente.
    }
  }

  /// Ultima lettura per chiave sensore (null se mai vista in sessione).
  SensorSample? latestFor(String key) => _latest[key];

  /// Stato del sensore: live (< staleAfter), stale (≥ soglia), offline
  /// (mai visto in questa sessione).
  SensorStatus statusFor(String key) {
    final sample = _latest[key];
    if (sample == null) return SensorStatus.offline;
    final age = _now().difference(sample.timestamp);
    return age < staleAfter ? SensorStatus.live : SensorStatus.stale;
  }

  /// Inietta una lettura (solo test).
  @visibleForTesting
  void debugInjectReading(SensorSample sample) {
    _latest[sample.sensorId] = sample;
    latest.value = Map.unmodifiable(_latest);
  }
}
