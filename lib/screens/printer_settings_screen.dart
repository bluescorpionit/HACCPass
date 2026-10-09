import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../core/printing/label_printer.dart';
import '../core/printing/label_rasterizer.dart';
import '../repositories/haccp_repository.dart';
import '../services/pdf_service.dart';
import '../services/printing/bluetooth_permissions.dart';
import '../services/printing/generic_label_printer.dart';
import '../services/printing/niimbot_label_printer.dart';
import '../services/printing/print_coordinator.dart';

/// Impostazioni → Stampante (Prompt 11, §4): scelta del motore tra
/// Brother QL, Niimbot, stampante generica e stampa di sistema; ricerca,
/// collegamento, formato, densità, etichetta di prova, stato e profili.
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
  String _genericTransport = 'wifi';
  GenericLanguage _genericLanguage = GenericLanguage.escpos;
  int _genericDpi = 203;
  int _genericPaperWidth = 58;
  bool _genericInvert = false;

  List<Map<String, dynamic>> _profiles = [];

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
    final profilesRaw = await widget.repository.getSetting('printer_profiles');
    List<Map<String, dynamic>> profiles = [];
    if (profilesRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(profilesRaw);
        if (decoded is List) {
          profiles = [
            for (final entry in decoded)
              if (entry is Map<String, dynamic>) entry,
          ];
        }
      } catch (_) {}
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
      _genericInvert = settings.generic.invertTspl;
      _profiles = profiles;
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
        engine.config = _genericConfig(const GenericPrinterConfig());
      }
      final devices = await engine.discover();
      setState(() => _devices = devices);
      if (devices.isEmpty) {
        setState(() => _note = engine.id == 'generic' && _genericTransport == 'wifi'
            ? 'Nessuna ricerca automatica in Wi-Fi: inserisci l\u2019indirizzo '
                'IP della stampante e usa "Salva e collega".'
            : 'Nessuna stampante trovata: accendila, avvicinala e riprova '
                '(per il Bluetooth classico va prima associata nelle '
                'impostazioni del telefono).');
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
    if (engine is GenericLabelPrinter) {
      address = engine.config.address;
    }
    await _save(deviceId: address, deviceName: device.name);
    await _addProfile(name: device.name, deviceId: address);
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
  // Profili salvati (più stampanti con una predefinita)
  // ------------------------------------------------------------------

  Map<String, dynamic> _currentProfileMap(String name, String deviceId) => {
        'name': name,
        'engine': _engineId,
        'deviceId': deviceId,
        'deviceName': name,
        'format': _settings.format,
        'density': _settings.density,
        'genericTransport': _genericTransport,
        'genericAddress': _addressCtrl.text.trim(),
        'genericCharacteristic': _characteristicCtrl.text.trim(),
        'genericLanguage': _genericLanguage.settingValue,
        'genericDpi': _genericDpi.toString(),
        'genericPaperWidth': _genericPaperWidth.toString(),
        'genericPrintableDots': _printableDotsCtrl.text.trim(),
        'genericInvert': _genericInvert ? '1' : '0',
      };

  Future<void> _addProfile({required String name, required String deviceId}) async {
    final profile = _currentProfileMap(name, deviceId);
    setState(() {
      _profiles = [
        ..._profiles.where((p) => p['deviceId'] != deviceId),
        profile,
      ];
    });
    await _persistProfiles();
  }

  Future<void> _persistProfiles() async {
    await widget.repository.setSetting(
      'printer_profiles',
      jsonEncode(_profiles),
    );
  }

  Future<void> _forgetProfile(Map<String, dynamic> profile) async {
    final wasActive = profile['deviceId'] == _settings.deviceId;
    setState(() => _profiles =
        _profiles.where((p) => p['deviceId'] != profile['deviceId']).toList());
    await _persistProfiles();
    if (wasActive) {
      await _save(deviceId: '', deviceName: '');
      if (mounted) setState(() => _note = 'Stampante dimenticata.');
    }
  }

  Future<void> _useProfile(Map<String, dynamic> profile) async {
    await _save(
      engine: profile['engine'] as String? ?? _engineId,
      deviceId: profile['deviceId'] as String? ?? '',
      deviceName: profile['deviceName'] as String? ?? '',
      format: profile['format'] as String? ?? _settings.format,
      density: int.tryParse(profile['density'] as String? ?? '') ??
          _settings.density,
      generic: GenericPrinterConfig(
        transport: profile['genericTransport'] as String? ?? 'wifi',
        address: profile['genericAddress'] as String? ?? '',
        characteristicId:
            (profile['genericCharacteristic'] as String? ?? '').isEmpty
                ? null
                : profile['genericCharacteristic'] as String,
        language:
            profile['genericLanguage'] == 'tspl' ? GenericLanguage.tspl : GenericLanguage.escpos,
        dpi: int.tryParse(profile['genericDpi'] as String? ?? '') ?? 203,
        paperWidthMm:
            int.tryParse(profile['genericPaperWidth'] as String? ?? '') ?? 58,
        printableWidthDots:
            int.tryParse(profile['genericPrintableDots'] as String? ?? ''),
        invertTspl: profile['genericInvert'] == '1',
      ),
    );
    await _load();
    if (mounted) {
      setState(() => _note =
          'Stampante predefinita: ${profile['deviceName'] ?? profile['name']}.');
    }
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
      final result = await coordinator.printPdf([bytes]);
      if (!mounted) return;
      setState(() => _note = result.italianMessage);
    } catch (e) {
      if (mounted) setState(() => _note = 'Prova non riuscita: $e');
    } finally {
      if (mounted) setState(() => _printingTest = false);
    }
  }

  /// Anteprima dell'immagine monocromatica che sarà inviata alla
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
      body: ListView(
        padding: const EdgeInsets.all(16),
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
                  child: FilledButton.tonalIcon(
                    onPressed: _searching ? null : _search,
                    icon: _searching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.search),
                    label: Text(_engineId == 'generic' && _genericTransport == 'wifi'
                        ? 'Cerca (solo Bluetooth LE)'
                        : 'Cerca stampanti'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Stato stampante',
                  onPressed: _showStatus,
                  icon: const Icon(Icons.info_outline),
                ),
              ],
            ),
            if (_devices.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final device in _devices)
                ListTile(
                  dense: true,
                  title: Text(device.name),
                  subtitle: Text(
                      '${printTransportLabel(device.transport)}'
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
          RadioGroup<String>(
            groupValue: _settings.format,
            onChanged: (v) => _save(format: v),
            child: Column(
              children: [
                for (final format in const ['62x40', '50x30', '40x30'])
                  RadioListTile<String>(
                    value: format,
                    title: Text(format == '62x40'
                        ? '62 \u00D7 40 mm (predefinito)'
                        : format == '50x30'
                            ? '50 \u00D7 30 mm'
                            : '40 \u00D7 30 mm'),
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
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _printingTest ? null : _testPrint,
                icon: _printingTest
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.receipt_long),
                label: const Text('Stampa etichetta di prova'),
              ),
              OutlinedButton.icon(
                onPressed: _preview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Anteprima'),
              ),
              if (_settings.deviceId.isNotEmpty)
                OutlinedButton(
                  onPressed: _disconnect,
                  child: const Text('Scollega'),
                ),
            ],
          ),
          // Prompt 11-bis, §2: guida alla prova accanto al pulsante.
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
          if (_profiles.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Stampanti salvate',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            RadioGroup<String>(
              groupValue: _settings.deviceId,
              onChanged: (deviceId) {
                for (final profile in _profiles) {
                  if (profile['deviceId'] == deviceId) {
                    _useProfile(profile);
                    return;
                  }
                }
              },
              child: Column(
                children: [
                  for (final profile in _profiles)
                    ListTile(
                      dense: true,
                      leading: Radio<String>(
                        value: profile['deviceId'] as String? ?? '',
                      ),
                      title: Text(profile['name']?.toString() ?? 'Stampante'),
                      subtitle: Text(
                          '${profile['engine']} \u2022 ${profile['format'] ?? ''}'),
                      trailing: IconButton(
                        tooltip: 'Dimentica stampante',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _forgetProfile(profile),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _engineSubtitle(String id) => switch (id) {
        'brother' =>
          'QL-820NWB verificata \u2022 Wi-Fi/USB (Bluetooth solo Android)',
        'niimbot' => 'B21, B1, D11/D110 \u2022 Bluetooth LE',
        'generic' => 'Termiche ESC/POS o TSPL \u2022 Wi-Fi o BLE',
        'system' => 'AirPrint / stampa di Android o del computer',
        'demo' => 'Simulazione della stampa (solo build debug)',
        _ => '',
      };

  List<Widget> _genericSection(ThemeData theme) {
    return [
      const SizedBox(height: 8),
      Text('Connessione della stampante generica',
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      DropdownButtonFormField<String>(
        initialValue: _genericTransport,
        decoration: const InputDecoration(labelText: 'Trasporto'),
        items: const [
          DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi / LAN (TCP 9100)')),
          DropdownMenuItem(value: 'ble', child: Text('Bluetooth LE (non verificato)')),
          DropdownMenuItem(
            value: '_spp',
            enabled: false,
            child: Text('Bluetooth classico (SPP) \u2014 non disponibile'),
          ),
          DropdownMenuItem(
            value: '_usb',
            enabled: false,
            child: Text('USB (OTG) \u2014 non disponibile'),
          ),
        ],
        onChanged: (v) {
          if (v == null || v.startsWith('_')) return;
          setState(() => _genericTransport = v);
          _save(generic: _genericConfig(GenericPrinterConfig(transport: v)));
        },
      ),
      if (_genericTransport == 'wifi')
        TextField(
          controller: _addressCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Indirizzo IP della stampante (es. 192.168.1.50)',
          ),
          onSubmitted: (_) => _saveGenericNow(),
        )
      else
        TextField(
          controller: _addressCtrl,
          decoration: const InputDecoration(
            labelText: 'Dispositivo BLE (cerca, oppure remoteId)',
          ),
          onSubmitted: (_) => _saveGenericNow(),
        ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('ESC/POS'),
            selected: _genericLanguage == GenericLanguage.escpos,
            onSelected: (_) {
              setState(() => _genericLanguage = GenericLanguage.escpos);
              _saveGenericNow();
            },
          ),
          ChoiceChip(
            label: const Text('TSPL'),
            selected: _genericLanguage == GenericLanguage.tspl,
            onSelected: (_) {
              setState(() => _genericLanguage = GenericLanguage.tspl);
              _saveGenericNow();
            },
          ),
        ],
      ),
      const SizedBox(height: 4),
      Wrap(
        spacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('203 dpi'),
            selected: _genericDpi == 203,
            onSelected: (_) {
              setState(() => _genericDpi = 203);
              _saveGenericNow();
            },
          ),
          ChoiceChip(
            label: const Text('300 dpi'),
            selected: _genericDpi == 300,
            onSelected: (_) {
              setState(() => _genericDpi = 300);
              _saveGenericNow();
            },
          ),
          if (_genericLanguage == GenericLanguage.escpos) ...[
            ChoiceChip(
              label: const Text('Carta 58 mm'),
              selected: _genericPaperWidth == 58,
              onSelected: (_) {
                setState(() => _genericPaperWidth = 58);
                _saveGenericNow();
              },
            ),
            ChoiceChip(
              label: const Text('Carta 80 mm'),
              selected: _genericPaperWidth == 80,
              onSelected: (_) {
                setState(() => _genericPaperWidth = 80);
                _saveGenericNow();
              },
            ),
          ],
        ],
      ),
      const SizedBox(height: 4),
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
          const SizedBox(height: 8),
          // Prompt 11-bis, §1: alcuni modelli hanno 432 o 640 punti.
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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _genericInvert,
            onChanged: (v) {
              setState(() => _genericInvert = v);
              _saveGenericNow();
            },
            title: const Text('Inverti immagine'),
            subtitle: const Text(
              'Attivalo se l\u2019etichetta TSPL esce in negativo (sfondo '
              'nero).',
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      FilledButton.tonal(
        onPressed: _saveGenericNow,
        child: const Text('Salva e collega'),
      ),
    ];
  }

  GenericPrinterConfig _genericConfig(GenericPrinterConfig partial) =>
      GenericPrinterConfig(
        transport: partial.transport != 'wifi' && partial.transport != 'ble'
            ? _genericTransport
            : partial.transport,
        address: _addressCtrl.text.trim(),
        characteristicId: _characteristicCtrl.text.trim().isEmpty
            ? null
            : _characteristicCtrl.text.trim(),
        language: _genericLanguage,
        dpi: _genericDpi,
        paperWidthMm: _genericPaperWidth,
        printableWidthDots: int.tryParse(_printableDotsCtrl.text.trim()),
        invertTspl: _genericInvert,
      );

  Future<void> _saveGenericNow() async {
    final config = _genericConfig(const GenericPrinterConfig());
    await _save(
      deviceId: config.address,
      deviceName: config.transport == 'wifi'
          ? 'Rete ${config.address}'
          : 'BLE ${config.address}',
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
              Icon(Icons.warning_amber_outlined, color: theme.colorScheme.primary),
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
