/// Interfaccia unica per i motori di stampa etichette (Prompt 11, §1).
///
/// Quattro motori per il cliente — Brother QL, Niimbot, stampante
/// generica (ESC/POS o TSPL), stampa di sistema — più un motore demo
/// visibile solo nelle build di debug. I layout delle etichette restano
/// quelli di `PdfService`: i motori ricevono i **byte PDF** già pronti
/// e li rasterizzano (o li passano al SDK) senza riscrivere nulla.
///
/// Per aggiungere in futuro un altro motore basta implementare
/// [LabelPrinter] (vedi `docs/stampanti.md`).
library;

import 'dart:typed_data';

/// Trasporto con cui si raggiunge la stampante.
enum PrintTransport { wifi, ble, bluetooth, usb, system, demo }

String printTransportLabel(PrintTransport t) => switch (t) {
      PrintTransport.wifi => 'Wi-Fi',
      PrintTransport.ble => 'Bluetooth LE',
      PrintTransport.bluetooth => 'Bluetooth',
      PrintTransport.usb => 'USB',
      PrintTransport.system => 'Sistema',
      PrintTransport.demo => 'Demo',
    };

/// Stampante trovata dalla ricerca.
class PrinterDevice {
  const PrinterDevice({
    required this.name,
    required this.id,
    required this.transport,
    this.detail,
  });

  final String name;

  /// Identificativo stabile per ricollegarsi dopo un riavvio
  /// (indirizzo IP, MAC, remoteId BLE, "system"...).
  final String id;
  final PrintTransport transport;

  /// Dettaglio opzionale (modello, indirizzo...).
  final String? detail;
}

/// Specifica dell'etichetta da stampare: la dimensione deriva dal
/// formato scelto nel wizard/Impostazioni (`62x40`, `50x30`, `40x30`).
class LabelSpec {
  const LabelSpec({
    required this.format,
    this.density = 3,
    this.autoCut = true,
  });

  static const List<String> formats = ['62x40', '50x30', '40x30'];

  final String format;

  /// Densità di stampa 1–5 (dove il motore la supporta; default 3).
  final int density;

  /// Taglio automatico a fine etichetta (dove supportato).
  final bool autoCut;

  int get widthMm => switch (format) {
        '50x30' => 50,
        '40x30' => 40,
        _ => 62,
      };

  int get heightMm => switch (format) {
        '50x30' => 30,
        '40x30' => 30,
        _ => 40,
      };
}

/// Esito tipizzato di una stampa: mai stack trace all'utente, sempre un
/// messaggio in italiano ([PrintResult.italianMessage]).
enum PrintOutcome {
  ok,
  notConnected,
  paperError,
  coverOpen,
  labelSizeNotSupported,
  cancelled,
  busy,
  failed,
}

class PrintResult {
  const PrintResult(this.outcome, [this.message]);

  final PrintOutcome outcome;

  /// Dettaglio opzionale del motore (già in italiano).
  final String? message;

  bool get isOk => outcome == PrintOutcome.ok;

  String get italianMessage => switch (outcome) {
        PrintOutcome.ok => 'Stampa completata.',
        PrintOutcome.notConnected =>
          message ?? 'Stampante non collegata: selezionala e riprova.',
        PrintOutcome.paperError => message ??
            'Carta assente: inserisci il rotolo di etichette e chiudi il coperchio.',
        PrintOutcome.coverOpen =>
          message ?? 'Coperchio aperto: chiudilo e riprova.',
        PrintOutcome.labelSizeNotSupported =>
          message ?? 'Formato etichetta non adatto a questa stampante.',
        PrintOutcome.cancelled => 'Stampa annullata.',
        PrintOutcome.busy => message ??
            'Stampante occupata: attendi la fine della stampa precedente o riavvia la stampante.',
        PrintOutcome.failed =>
          message ?? 'Stampa non riuscita: riprova.',
      };
}

/// Stato della stampante al momento della richiesta.
class PrinterStatus {
  const PrinterStatus({
    required this.connected,
    this.ok = true,
    this.paperOut = false,
    this.coverOpen = false,
    this.batteryLevel,
    this.detail,
  });

  /// true se la stampante risponde (per i motori generici: raggiungibile).
  final bool connected;

  /// Nessun errore hardware noto.
  final bool ok;
  final bool paperOut;
  final bool coverOpen;

  /// Percentuale batteria 0–100 se disponibile.
  final int? batteryLevel;

  final String? detail;
}

/// Contratto dei motori di stampa etichette.
abstract class LabelPrinter {
  /// `'brother'`, `'niimbot'`, `'generic'`, `'system'`, `'demo'`.
  String get id;

  String get displayName;

  /// Cerca le stampanti disponibili (i permessi Bluetooth vengono chiesti
  /// qui, al momento della ricerca, mai all'avvio).
  Future<List<PrinterDevice>> discover();

  /// Collega una stampante trovata da [discover] o ricostruita dalle
  /// impostazioni salvate (id stabile).
  Future<void> connect(PrinterDevice device);

  Future<void> disconnect();

  bool get isConnected;

  /// Stampa le etichette: [pdfPages] sono i byte PDF di `PdfService`
  /// (layout invariati), ripetuti [copies] volte.
  Future<PrintResult> printLabels(
    List<Uint8List> pdfPages,
    LabelSpec spec, {
    int copies = 1,
  });

  /// Stato attuale (carta, coperchio, batteria se disponibile; i motori
  /// generici riportano solo connessa / non raggiungibile).
  Future<PrinterStatus> status();
}
