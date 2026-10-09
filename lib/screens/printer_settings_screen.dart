import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/printing/label_printer.dart';
import '../core/printing/label_rasterizer.dart';
import '../repositories/haccp_repository.dart';
import '../services/pdf_service.dart';
import '../services/printing/bluetooth_permissions.dart';
import '../services/printing/byte_transport.dart'
    show BluetoothSppByteTransport, phoneIpv4;
import '../services/printing/generic_label_printer.dart';
import '../services/printing/niimbot_label_printer.dart';
import '../services/printing/print_coordinator.dart';
import '../services/printing/print_label_flow.dart'
    show GenericFitChoice, showFitChoiceDialog;
import '../widgets/common_widgets.dart' show screenPadding;

/// Impostazioni ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ Stampante (Prompt 11, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§4): scelta del motore tra
/// Brother QL, Niimbot, stampante generica e stampa di sistema; ricerca,
/// collegamento, formato, densitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â , etichetta di prova, stato e profili.
///
/// I motori sono iniettabili: i widget test usano motori finti, nessuna
/// dipendenza da hardware.
class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({
    super.key,
    required this.repository,
    this.engines,
  });

  final HaccpRepository repository;
  final List<LabelPrinter>? engines;

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> {
  List<LabelPrinter> _engines = [];
  String _engineId = '';
  List<PrinterDevice> _devices = [];
  bool _searching = false;
  bool _printingTest = false;
  String? _note;

  PrintSettings _settings = const PrintSettings();

  final _addressCtrl = TextEditingController();
  final _characteristicCtrl = TextEditingController();
  final _printableDotsCtrl = TextEditingController();
  final _bandRowsCtrl = TextEditingController();
  final _portCtrl = TextEditingController();
  final _feedMmCtrl = TextEditingController();
  String _genericTransport = 'wifi';
  GenericLanguage _genericLanguage = GenericLanguage.escpos;
  int _genericDpi = 203;
  int _genericPaperWidth = 58;
  bool _genericInvert = false;
  bool _genericCutter = false;
  bool _genericFormFeed = false;
  bool _genericAntiAdvance = false;
  String _genericSpeed = 'normal';
  String _genericFitMode = 'ask';

  /// SPP disponibile solo su Android (Prompt 17, Ã‚Â§2).
  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Riepilogo dell'ultimo invio/diagnostica (Prompt 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§7.4).
  String? _lastSendSummary;
  var _diagnosing = false;

  @override
  void initState() {
    super.initState();
    _engines = widget.engines ?? PrintCoordinator.availableEngines();
    _load();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _characteristicCtrl.dispose();
    _printableDotsCtrl.dispose();
    _bandRowsCtrl.dispose();
    _portCtrl.dispose();
    _feedMmCtrl.dispose();
    super.dispose();
  }

  LabelPrinter? get _engine {
    for (final engine in _engines) {
      if (engine.id == _engineId) return engine;
    }
    return null;
  }

  Future<void> _load() async {
    final settings = await PrintSettings.load(widget.repository.getSetting);
    // "Stampanti salvate" disattivate: con BT classico Android l'elenco dei
    // dispositivi associati può includere device non stampanti e creare
    // selezioni fuorvianti. Manteniamo una sola stampante attiva nei setting.
    final legacyProfiles =
        await widget.repository.getSetting('printer_profiles');
    if (legacyProfiles.isNotEmpty) {
      await widget.repository.setSetting('printer_profiles', '');
    }
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _engineId = settings.engine;
      _genericTransport = settings.generic.transport;
      _genericLanguage = settings.generic.language;
      _genericDpi = settings.generic.dpi;
      _genericPaperWidth = settings.generic.paperWidthMm;
      _addressCtrl.text = settings.generic.address;
      _characteristicCtrl.text = settings.generic.characteristicId ?? '';
      _printableDotsCtrl.text =
          settings.generic.printableWidthDots?.toString() ?? '';
      _bandRowsCtrl.text = settings.generic.bandRows.toString();
      _portCtrl.text = settings.generic.port.toString();
      _feedMmCtrl.text = settings.generic.feedMm.toStringAsFixed(0);
      _genericInvert = settings.generic.invertTspl;
      _genericCutter = settings.generic.cutter;
      _genericFormFeed = settings.generic.formFeed;
      _genericAntiAdvance = settings.generic.antiAdvance;
      _genericSpeed = settings.generic.speed;
      _genericFitMode = settings.generic.fitMode;
    });
  }

  Future<void> _save({
    String? engine,
    String? deviceId,
    String? deviceName,
    String? format,
    int? density,
    GenericPrinterConfig? generic,
  }) async {
    final next = PrintSettings(
      engine: engine ?? _engineId,
      deviceId: deviceId ?? _settings.deviceId,
      deviceName: deviceName ?? _settings.deviceName,
      format: format ?? _settings.format,
      density: density ?? _settings.density,
      generic: generic ?? _settings.generic,
    );
    await next.save(widget.repository);
    setState(() => _settings = next);
  }

  Future<void> _selectEngine(String id) async {
    setState(() {
      _engineId = id;
      _devices = [];
      _note = null;
    });
    await _save(engine: id, deviceId: '', deviceName: '');
  }

  // ------------------------------------------------------------------
  // Ricerca e collegamento
  // ------------------------------------------------------------------

  /// Messaggio d'errore in italiano, senza prefissi tecnici.
  String _errorText(Object e) {
    if (e is StateError) return e.message;
    return e.toString();
  }

  Future<void> _search() async {
    final engine = _engine;
    if (engine == null) return;
    final needsBle = engine.id == 'niimbot' ||
        (engine.id == 'generic' && _genericTransport == 'ble');
    if (needsBle) {
      final granted = await requestBluetoothForPrinters();
      if (!granted) {
        setState(() => _note =
            'Permesso Bluetooth negato: abilitalo nelle impostazioni del '
                'telefono e riprova.');
        return;
      }
    }
    setState(() {
      _searching = true;
      _note = null;
    });
    try {
      if (engine is GenericLabelPrinter) {
        // La generica legge il trasporto dalla propria configurazione:
        // la si aggiorna PRIMA della ricerca.
        engine.config = _genericConfig();
      }
      final devices = await engine.discover();
      setState(() => _devices = devices);
      if (devices.isEmpty) {
        setState(() => _note = engine.id == 'generic' &&
                _genericTransport == 'wifi'
            ? 'Nessuna ricerca automatica in Wi-Fi: inserisci l\u2019indirizzo '
                'IP della stampante e usa "Salva e collega".'
            : engine.id == 'generic' && _genericTransport == 'ble'
                ? 'Nessuna stampante Bluetooth LE trovata. Se la stampante '
                    'compare nelle impostazioni Bluetooth del telefono ma '
                    'non qui, \u00E8 una stampante classica: scegli '
                    'Bluetooth classico (SPP).'
                : engine.id == 'generic' && _genericTransport == 'bluetooth'
                    ? 'Nessun dispositivo associato: tocca "Associa nuova '
                        'stampante" e associala dalle impostazioni Bluetooth '
                        'del telefono.'
                    : 'Nessuna stampante trovata: accendila, avvicinala e '
                        'riprova.');
      }
    } catch (e) {
      setState(() => _note = _errorText(e));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _connect(PrinterDevice device) async {
    final engine = _engine;
    if (engine == null) return;
    setState(() => _note = null);
    try {
      await engine.connect(device);
    } catch (e) {
      setState(() => _note = _errorText(e));
      return;
    }
    var address = device.id;
    var savedDeviceId = device.id;
    GenericPrinterConfig? generic;
    if (engine is GenericLabelPrinter) {
      address = engine.config.address;
      savedDeviceId = switch (device.transport) {
        PrintTransport.bluetooth => 'bt:$address',
        _ => address,
      };
      generic = engine.config;
      _addressCtrl.text = address;
    }
    await _save(
      deviceId: savedDeviceId,
      deviceName: device.name,
      generic: generic,
    );
    if (mounted) {
      setState(
          () => _note = 'Collegata: ${device.name}. Stampa l\u2019etichetta '
              'di prova per verificare formato e orientamento.');
    }
  }

  Future<void> _disconnect() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.disconnect();
    await _save(deviceId: '', deviceName: '');
    if (mounted) setState(() => _note = 'Stampante scollegata.');
  }

  // ------------------------------------------------------------------
  // Prova, anteprima e stato
  // ------------------------------------------------------------------

  Future<void> _testPrint() async {
    if (_printingTest) return;
    setState(() {
      _printingTest = true;
      _note = null;
    });
    try {
      final pdf = PdfService(repository: widget.repository);
      final bytes = await pdf.buildTestLabel(_settings.format);
      final coordinator = await PrintCoordinator.load(widget.repository);

      // Prompt 17, Â§3: scelta esplicita se l'etichetta non entra nella
      // carta della stampante generica.
      final engine = coordinator.engine;
      if (engine is GenericLabelPrinter &&
          engine.config.language == GenericLanguage.escpos) {
        final spec = coordinator.settings.spec;
        if (!engine.checkFit(spec).fits) {
          if (!mounted) return;
          if (engine.config.fitMode == 'ask') {
            final choice = await showFitChoiceDialog(
              context,
              engine: engine,
              repository: widget.repository,
              spec: spec,
            );
            if (choice == GenericFitChoice.shrink) {
              engine.config = engine.config.copyWith(fitMode: 'shrink');
            } else {
              if (mounted) {
                setState(() => _note = choice == GenericFitChoice.smallerFormat
                    ? 'Cambia formato in 40\u00D730 e riprova la prova.'
                    : 'Prova annullata: etichetta piÃ¹ larga della carta.');
              }
              return;
            }
          } else if (engine.config.fitMode == 'reject') {
            if (mounted) {
              setState(() => _note =
                  'Etichetta piÃ¹ larga della carta: riduci (Avanzate \u2192 '
                      '"Se l\u2019etichetta \u00E8 pi\u00F9 larga della carta") o '
                      'cambia formato.');
            }
            return;
          }
          if (engine.readabilityWarningNeeded(spec) && mounted) {
            setState(() => _note =
                'L\u2019etichetta ridotta pu\u00F2 risultare poco leggibile: '
                    'prova la stampa di prova e verifica il QR con il telefono.');
          }
        }
      }

      final result = await coordinator.printPdf([bytes]);
      if (!mounted) return;
      setState(() => _note = result.italianMessage);
    } catch (e) {
      if (mounted) setState(() => _note = 'Prova non riuscita: $e');
    } finally {
      if (mounted) setState(() => _printingTest = false);
    }
  }

  /// Anteprima dell'immagine monocromatica che sarÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  inviata alla
  /// stampante (aiuta a vedere testi troppo piccoli e l'orientamento).
  Future<void> _preview() async {
    try {
      final pdf = PdfService(repository: widget.repository);
      final bytes = await pdf.buildTestLabel(_settings.format);
      final dpi = _engineId == 'niimbot' ? 203 : _genericDpi;
      final mono = await LabelRasterizer().rasterPdfPage(
        bytes,
        dpi: dpi,
        widthMm: LabelSpec(format: _settings.format).widthMm.toDouble(),
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Anteprima (bianco/nero)'),
          content: Image.memory(monoToPng(mono)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Chiudi'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _note = 'Anteprima non riuscita: $e');
    }
  }

  Future<void> _showStatus() async {
    final engine = _engine;
    if (engine == null) return;
    final status = await engine.status();
    if (!mounted) return;
    final message = !status.connected
        ? 'Non collegata / non raggiungibile.'
        : status.paperOut
            ? 'Carta assente: inserisci il rotolo e chiudi il coperchio.'
            : status.coverOpen
                ? 'Coperchio aperto.'
                : 'Collegata${status.detail == null ? '' : ' \u2022 ${status.detail}'}.';
    setState(() => _note = message);
  }

  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isGeneric = _engineId == 'generic';
    final isNiimbot = _engineId == 'niimbot';
    final showsDeviceList = !const ['system', 'demo'].contains(_engineId);

    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni \u2192 Stampante')),
      // Prompt 14: screenPadding per non finire sotto la barra di
      // navigazione (3 tasti e gesti); contenuto centrato con larghezza
      // massima 640 su tablet; pulsanti d'azione uniformi (primari a
      // larghezza piena, secondari in coppia uguale).
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: screenPadding(context, horizontal: 16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'La stampante \u00E8 facoltativa: senza stampante l\u2019app '
                    '\u00E8 pienamente utilizzabile e le etichette si possono '
                    'condividere come PDF.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final engine in _engines)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: _engineId == engine.id
                      ? theme.colorScheme.primaryContainer
                      : null,
                  child: ListTile(
                    title: Text(engine.displayName),
                    subtitle: Text(_engineSubtitle(engine.id)),
                    trailing: _engineId == engine.id
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () => _selectEngine(engine.id),
                  ),
                ),
              if (showsDeviceList) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: FilledButton.tonal(
                          onPressed: _searching ? null : _search,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searching)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                const Icon(Icons.search),
                              const SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _engineId == 'generic' &&
                                            _genericTransport == 'wifi'
                                        ? 'Cerca (solo Bluetooth LE)'
                                        : 'Cerca stampanti',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 52,
                      height: 52,
                      child: IconButton.outlined(
                        tooltip: 'Stato stampante',
                        onPressed: _showStatus,
                        icon: const Icon(Icons.info_outline),
                      ),
                    ),
                  ],
                ),
                if (_devices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final device in _devices)
                    ListTile(
                      dense: true,
                      title: Text(device.name),
                      subtitle: Text('${printTransportLabel(device.transport)}'
                          '${device.detail == null ? '' : ' \u2022 ${device.detail}'}'),
                      trailing: TextButton(
                        onPressed: () => _connect(device),
                        child: const Text('Collega'),
                      ),
                    ),
                ],
              ],
              if (isGeneric) ..._genericSection(theme),
              if (isNiimbot) ...[
                const SizedBox(height: 8),
                _warningCard(theme, NiimbotLabelPrinter.permanentWarning),
              ],
              if (isGeneric)
                _warningCard(theme, GenericLabelPrinter.permanentWarning),
              const SizedBox(height: 16),
              Text('Formato etichetta',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              RadioGroup<String>(
                groupValue: _settings.format,
                onChanged: (v) => _save(format: v),
                child: Column(
                  children: [
                    for (final format in const ['62x40', '50x30', '40x30'])
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: RadioListTile<String>(
                          value: format,
                          title: Text(format == '62x40'
                              ? '62 \u00D7 40 mm (predefinito)'
                              : format == '50x30'
                                  ? '50 \u00D7 30 mm'
                                  : '40 \u00D7 30 mm'),
                        ),
                      ),
                  ],
                ),
              ),
              if (isNiimbot || isGeneric) ...[
                const SizedBox(height: 8),
                Text('Densit\u00E0 di stampa: ${_settings.density} su 5',
                    style: theme.textTheme.titleSmall),
                Slider(
                  value: _settings.density.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '${_settings.density}',
                  onChanged: (v) => _save(density: v.round()),
                ),
              ],
              const SizedBox(height: 8),
              // Prompt 14, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§2: azione primaria a larghezza piena,
              // secondarie in coppia uguale, stessa altezza (52).
              SizedBox(
                height: 52,
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _printingTest ? null : _testPrint,
                  icon: _printingTest
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.receipt_long),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Stampa etichetta di prova'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _preview,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Anteprima'),
                        ),
                      ),
                    ),
                  ),
                  if (_settings.deviceId.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _disconnect,
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Scollega'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              // Prompt 11-bis, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§2: guida alla prova accanto al pulsante.
              if (isGeneric) ...[
                const SizedBox(height: 6),
                Text(
                  'Se l\u2019etichetta esce in negativo (sfondo nero) attiva '
                  '"Inverti immagine" in Avanzate; se esce vuota o tagliata '
                  'prova l\u2019altro linguaggio (ESC/POS/TSPL).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (_note != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_note!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _engineSubtitle(String id) => switch (id) {
        'brother' =>
          'QL-820NWB verificata \u2022 Wi-Fi/USB (Bluetooth solo Android)',
        'niimbot' => 'B21, B1, D11/D110 \u2022 Bluetooth LE',
        'generic' =>
          'Termiche ESC/POS o TSPL \u2022 Wi-Fi, BLE o BT classico (Android)',
        'system' => 'AirPrint / stampa di Android o del computer',
        'demo' => 'Simulazione della stampa (solo build debug)',
        _ => '',
      };

  List<Widget> _genericSection(ThemeData theme) {
    Widget sectionTitle(String text) => Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(
            text,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        );

    Widget segmented<T>({
      required String title,
      required List<(T, String)> segments,
      required T selected,
      required ValueChanged<T> onSelected,
    }) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            sectionTitle(title),
            SizedBox(
              height: 48,
              child: SegmentedButton<T>(
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                ),
                segments: [
                  for (final (value, label) in segments)
                    ButtonSegment(
                      value: value,
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label),
                      ),
                    ),
                ],
                selected: {selected},
                onSelectionChanged: (values) => onSelected(values.first),
              ),
            ),
          ],
        );

    return [
      const SizedBox(height: 8),
      Text('Connessione della stampante generica',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      // Prompt 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§6: voci brevi + selectedItemBuilder con ellissi
      // (l'overflow nasceva dalle voci disabilitate lunghe, che il
      // dropdown misura TUTTE per calcolare la larghezza interna).
      // Prompt 17, Ãƒâ€šÃ‚Â§2: SPP selezionabile su Android, disattivato su
      // iPhone (Bluetooth classico = programma MFi di Apple).
      DropdownButtonFormField<String>(
        initialValue: _genericTransport,
        isExpanded: true,
        selectedItemBuilder: (context) => [
          for (final label in const [
            'Wi-Fi / LAN (porta 9100)',
            'Bluetooth LE',
            'Bluetooth classico (SPP)',
            'USB',
          ])
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
        items: [
          const DropdownMenuItem(
              value: 'wifi', child: Text('Wi-Fi / LAN (porta 9100)')),
          const DropdownMenuItem(value: 'ble', child: Text('Bluetooth LE')),
          DropdownMenuItem<String>(
            value: 'bluetooth',
            enabled: _isAndroid,
            child: Text(
              _isAndroid
                  ? 'Bluetooth classico (SPP)'
                  : 'Bluetooth classico \u2014 non disponibile su iPhone '
                      '(usa Wi-Fi o Bluetooth LE)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const DropdownMenuItem(
            value: '_usb',
            enabled: false,
            child: Text('USB \u2014 non disponibile'),
          ),
        ],
        decoration: const InputDecoration(
          labelText: 'Trasporto',
          helperText: 'Bluetooth LE: non verificato su ogni modello. \n'
              'SPP: non verificato, solo Android.',
        ),
        onChanged: (v) {
          if (v == null || v.startsWith('_')) return;
          setState(() {
            _genericTransport = v;
            if (v == 'bluetooth' && _genericSpeed == 'normal') {
              _genericSpeed = 'slow';
            }
          });
          _save(generic: _genericConfig());
        },
      ),
      const SizedBox(height: 12),
      if (_genericTransport == 'wifi')
        TextField(
          controller: _addressCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Indirizzo IP (es. 192.168.1.50)',
          ),
          onSubmitted: (_) => _saveGenericNow(),
        )
      else if (_genericTransport == 'bluetooth') ...[
        TextField(
          controller: _addressCtrl,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Dispositivo Bluetooth associato',
            helperText: 'Sceglierlo con "Cerca stampanti" qui sotto.',
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 52,
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await BluetoothSppByteTransport.openBluetoothSettings();
              if (mounted) {
                setState(() => _note =
                    'Torna all\u2019app quando hai associato la stampante e '
                        'tocca di nuovo "Cerca stampanti".');
              }
            },
            icon: const Icon(Icons.settings_bluetooth_outlined),
            label: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Associa nuova stampante'),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Accendi la stampante, associala dalle impostazioni Bluetooth '
          'del telefono (PIN di solito 0000 o 1234), poi tocca "Cerca '
          'stampanti" e scegli il suo nome.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ] else
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Dispositivo Bluetooth',
            helperText: 'Premi "Cerca stampanti" oppure incolla '
                'l\u2019identificativo.',
          ),
          onSubmitted: (_) => _saveGenericNow(),
        ),
      segmented(
        title: 'Linguaggio',
        segments: const [
          (GenericLanguage.escpos, 'ESC/POS'),
          (GenericLanguage.tspl, 'TSPL'),
        ],
        selected: _genericLanguage,
        onSelected: (v) {
          setState(() => _genericLanguage = v);
          _saveGenericNow();
        },
      ),
      segmented(
        title: 'Risoluzione',
        segments: const [(203, '203 dpi'), (300, '300 dpi')],
        selected: _genericDpi,
        onSelected: (v) {
          setState(() => _genericDpi = v);
          _saveGenericNow();
        },
      ),
      if (_genericLanguage == GenericLanguage.escpos)
        segmented(
          title: 'Larghezza carta',
          segments: const [(58, '58 mm'), (80, '80 mm')],
          selected: _genericPaperWidth,
          onSelected: (v) {
            setState(() => _genericPaperWidth = v);
            _saveGenericNow();
          },
        ),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('Avanzate'),
        children: [
          TextField(
            controller: _characteristicCtrl,
            decoration: const InputDecoration(
              labelText: 'UUID caratteristica di scrittura BLE (opzionale)',
            ),
            onSubmitted: (_) => _saveGenericNow(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _printableDotsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Punti stampabili in larghezza (opzionale)',
              helperText: 'Default dalla carta: 58 mm \u2192 384 punti, '
                  '80 mm \u2192 576 (a 203 dpi). Cambialo solo se la tua '
                  'stampante ha una testina diversa.',
            ),
            onSubmitted: (_) => _saveGenericNow(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bandRowsCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Righe per banda immagine',
              helperText: '128 default; 24 per stampanti molto vecchie '
                  '(blocchi alti ignorati da alcuni modelli).',
            ),
            onSubmitted: (_) => _saveGenericNow(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _portCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Porta TCP',
              helperText: '9100 nella quasi totalit\u00E0 dei casi.',
            ),
            onSubmitted: (_) => _saveGenericNow(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _feedMmCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Avanzamento dopo l\u2019immagine (mm)',
              helperText:
                  'Default 4 mm. Con "Modalit\u00E0 anti-avanzamento" il '
                  'valore viene limitato a massimo 1 mm.',
            ),
            onSubmitted: (_) => _saveGenericNow(),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _genericInvert,
            onChanged: (v) {
              setState(() => _genericInvert = v);
              _saveGenericNow();
            },
            title: const Text('Inverti immagine'),
            subtitle: const Text(
              'Solo TSPL: attivalo se l\u2019etichetta esce in negativo '
              '(sfondo nero).',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _genericCutter,
            onChanged: (v) {
              setState(() => _genericCutter = v);
              _saveGenericNow();
            },
            title: const Text('Taglierina'),
            subtitle: const Text(
              'Solo se la stampante ha il taglio automatico: il comando '
              'pu\u00F2 bloccare alcune stampanti di etichette.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _genericAntiAdvance,
            onChanged: (v) {
              setState(() => _genericAntiAdvance = v);
              _saveGenericNow();
            },
            title: const Text('Modalit\u00E0 anti-avanzamento carta'),
            subtitle: const Text(
              'Riduce il feed a massimo 1 mm e disattiva il comando FF '
              '(consigliata se la stampante non aggancia bene il gap).',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _genericFormFeed,
            onChanged: (v) {
              setState(() => _genericFormFeed = v);
              _saveGenericNow();
            },
            title: const Text('Avanza all\u2019etichetta successiva'),
            subtitle: const Text(
              'Invia il comando FF dopo ogni etichetta (carta a gap).',
            ),
          ),
          // Prompt 17, Ã‚Â§1/Ã‚Â§3: profilo di invio e adattamento alla carta.
          segmented<String>(
            title: 'Velocit\u00E0 di invio',
            segments: const [
              ('normal', 'Normale'),
              ('slow', 'Lenta'),
              ('fast', 'Veloce'),
            ],
            selected: _genericSpeed,
            onSelected: (v) {
              setState(() => _genericSpeed = v);
              _saveGenericNow();
            },
          ),
          segmented<String>(
            title: 'Se l\u2019etichetta \u00E8 pi\u00F9 larga della carta',
            segments: const [
              ('ask', 'Chiedi'),
              ('shrink', 'Riduci'),
              ('reject', 'Rifiuta'),
            ],
            selected: _genericFitMode,
            onSelected: (v) {
              setState(() => _genericFitMode = v);
              _saveGenericNow();
            },
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Prompt 14, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§2 + 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§6: azioni a larghezza piena, altezza 52.
      SizedBox(
        height: 52,
        width: double.infinity,
        child: FilledButton.tonal(
          onPressed: _saveGenericNow,
          child: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Salva e collega'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _diagnosing ? null : _probeConnection,
          icon: _diagnosing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.wifi_find_outlined),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Verifica connessione'),
          ),
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _diagnosing ? null : _plainTextTest,
          icon: const Icon(Icons.notes_outlined),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Prova solo testo'),
          ),
        ),
      ),
      if (_lastSendSummary != null) ...[
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _lastSendSummary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
      _troubleshootingGuide(theme),
    ];
  }

  /// Guida "La stampante non stampa?" (Prompt 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§7.5).
  Widget _troubleshootingGuide(ThemeData theme) => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: const Text('La stampante non stampa?'),
        subtitle: const Text('Sei controlli da fare, in ordine.'),
        children: [
          Text(
            '1. Stampa dalla stampante la pagina di autotest (di solito '
            'tenendo premuto il tasto Feed all\u2019accensione) e controlla '
            'IP, porta (9100) e linguaggio (ESC/POS / TSPL / ZPL).\n'
            '2. Telefono e stampante sulla STESSA rete Wi-Fi (non la rete '
            'ospiti, n\u00E9 "isolamento client" del router).\n'
            '3. Da un PC sulla stessa rete: '
            'Test-NetConnection <IP> -Port 9100 (Windows) o '
            'nc -vz <IP> 9100.\n'
            '4. Le stampanti di etichette con carta a gap usano spesso '
            'TSPL, non ESC/POS: prova l\u2019altro linguaggio.\n'
            '5. Larghezza carta e formato: 58 mm \u2248 48 mm stampabili, '
            '80 mm \u2248 72 mm.\n'
            '6. Imposta un IP fisso/prenotato per la stampante sul router.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );

  /// Configurazione generica costruita dallo stato a schermo: il
  /// trasporto Ã¨ SEMPRE [_genericTransport] (Prompt 17, fix "Cerca
  /// stampanti": prima il default 'wifi' di `partial.transport`
  /// sovrascriveva BLE/SPP e la ricerca restituiva sempre lista vuota).
  GenericPrinterConfig _genericConfig() => GenericPrinterConfig(
        transport: _genericTransport,
        address: _addressCtrl.text.trim(),
        characteristicId: _characteristicCtrl.text.trim().isEmpty
            ? null
            : _characteristicCtrl.text.trim(),
        language: _genericLanguage,
        dpi: _genericDpi,
        paperWidthMm: _genericPaperWidth,
        printableWidthDots: int.tryParse(_printableDotsCtrl.text.trim()),
        invertTspl: _genericInvert,
        bandRows: int.tryParse(_bandRowsCtrl.text.trim()) ?? 128,
        cutter: _genericCutter,
        formFeed: _genericFormFeed,
        antiAdvance: _genericAntiAdvance,
        feedMm: double.tryParse(
              _feedMmCtrl.text.trim().replaceAll(',', '.'),
            ) ??
            4,
        port: int.tryParse(_portCtrl.text.trim()) ?? 9100,
        speed: _genericTransport == 'bluetooth' && _genericSpeed == 'normal'
            ? 'slow'
            : _genericSpeed,
        fitMode: _genericFitMode,
      );

  /// Diagnostica 1 (Prompt 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§7.4): raggiungibilitÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â  TCP + IP telefono.
  Future<void> _probeConnection() async {
    final engine = _engine;
    if (engine is! GenericLabelPrinter) return;
    setState(() => _diagnosing = true);
    try {
      engine.config = _genericConfig();
      final probe = await engine.probeConnection();
      final phoneIp = await phoneIpv4();
      if (!mounted) return;
      setState(() => _note =
          '${probe.message}${phoneIp == null ? '' : ' (telefono: $phoneIp)'}');
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  /// Diagnostica 2 (Prompt 16, ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â§7.4): "prova solo testo".
  Future<void> _plainTextTest() async {
    final engine = _engine;
    if (engine is! GenericLabelPrinter) return;
    setState(() => _diagnosing = true);
    try {
      engine.config = _genericConfig();
      final result = await engine.printPlainTextTest();
      if (!mounted) return;
      setState(() {
        _note = result.italianMessage;
        _lastSendSummary = engine.lastJobSummary ?? _lastSendSummary;
      });
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  Future<void> _saveGenericNow() async {
    final config = _genericConfig();
    final autoName = switch (config.transport) {
      'wifi' => 'Rete ${config.address}',
      'bluetooth' => 'BT ${config.address}',
      _ => 'BLE ${config.address}',
    };
    final savedDeviceId = config.transport == 'bluetooth'
        ? 'bt:${config.address}'
        : config.address;
    await _save(
      deviceId: savedDeviceId,
      deviceName: autoName,
      generic: config,
    );
    if (mounted) {
      setState(() => _note =
          'Configurazione stampante generica salvata: stampa l\u2019etichetta '
              'di prova per verificare.');
    }
  }

  Widget _warningCard(ThemeData theme, String message) => Card(
        color: theme.colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
}

/// Converte la bitmap monocromatica in PNG per l'anteprima in app.
Uint8List monoToPng(MonoBitmap mono) {
  final image = img.Image(width: mono.width, height: mono.height);
  img.fill(image, color: img.ColorRgb8(255, 255, 255));
  for (var y = 0; y < mono.height; y++) {
    for (var x = 0; x < mono.width; x++) {
      final byte = mono.packed[y * mono.bytesPerRow + (x >> 3)];
      final black = (byte >> (7 - (x & 7))) & 1 == 1;
      if (black) {
        image.setPixel(x, y, img.ColorRgb8(0, 0, 0));
      }
    }
  }
  return Uint8List.fromList(img.encodePng(image));
}
