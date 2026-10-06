/// Astrazione delle sorgenti di lettura dei sensori di temperatura
/// (Fase 3 del piano Govee H5179).
///
/// Il registro HACCP e la UI dipendono solo da questa interfaccia, così le
/// sorgenti si aggiungono senza toccare il registro:
/// - BLE (`flutter_blue_plus`, Fase 1, offline);
/// - Cloud (Govee OpenAPI, Fase 2B, opzione di ripiego);
/// - Manuale (già esistente: registrazione a tocco);
/// - in futuro Gateway (mini-PC/ESP32/tablet stazione, non implementato).
library;

import 'dart:async';

/// Origine della lettura, registrata insieme al dato (mai implicita).
enum SensorSourceKind { ble, cloud, manual, gateway }

/// Singola lettura di un sensore associato a un'attrezzatura.
class SensorSample {
  const SensorSample({
    required this.sensorId,
    required this.tempC,
    required this.source,
    required this.timestamp,
    this.humidity,
    this.batteryPercent,
    this.rssi,
  });

  /// ID del sensore (MAC/ble_id del sensore associato).
  final String sensorId;

  /// Temperatura in °C così come letta: NESSUN offset di calibrazione è
  /// applicato qui. L'eventuale offset è configurazione del sensore, va
  /// mostrata all'utente e registrata insieme al dato.
  final double tempC;

  final SensorSourceKind source;
  final DateTime timestamp;
  final double? humidity;
  final int? batteryPercent;
  final int? rssi;
}

/// Contratto comune a ogni sorgente di letture.
abstract interface class SensorSource {
  /// Identificativo stabile della sorgente (es. 'ble', 'cloud-govee').
  String get id;

  /// Flusso delle letture; nessun dato sintetico quando la sorgente è
  /// offline: il flusso resta semplicemente muto.
  Stream<SensorSample> get samples;

  /// Avvia l'acquisizione. I permessi (Bluetooth, posizione) si chiedono
  /// qui, al primo uso, mai all'avvio dell'app.
  Future<void> start();

  /// Interrompe l'acquisizione e rilascia le risorse.
  Future<void> stop();

  /// true se la sorgente è attiva e funzionante.
  bool get isRunning;
}
