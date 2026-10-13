import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/theme/app_theme.dart';

/// Schermata di lettura QR con la fotocamera (mobile_scanner). Ritorna il
/// testo del primo QR letto via `Navigator.pop(context, valore)`; Annulla
/// ritorna null. Usata per cercare un lotto dal QR dell'etichetta.
///
/// Il permesso fotocamera si chiede QUI, al primo uso, mai all'avvio
/// (stessa regola degli altri permessi dell'app).
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key, this.hint});

  /// Istruzione mostrata sopra l'inquadratura (es. "Inquadra il QR del
  /// lotto sull'etichetta").
  final String? hint;

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _returned = false;
  bool _torchOn = false;

  @override
  void dispose() {
    // Il controller spegne la fotocamera: sempre dispose, anche dopo il
    // pop, per non lasciare la torcia o il sensore attivi.
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_returned) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      _returned = true;
      Navigator.of(context).pop(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Leggi QR'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: _torchOn ? 'Spegni torcia' : 'Accendi torcia',
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _torchOn = !_torchOn);
            },
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _CameraError(error: error),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                widget.hint ?? 'Inquadra un codice QR',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Errore fotocamera (permesso negato, sensore occupato): messaggio chiaro
/// e azione per aprire le impostazioni, senza crash.
class _CameraError extends StatelessWidget {
  const _CameraError({required this.error});

  final MobileScannerException error;

  @override
  Widget build(BuildContext context) {
    final colors = context.haccpColors;
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.photo_camera_outlined,
                color: Colors.white, size: 40),
            const SizedBox(height: 12),
            Text(
              denied
                  ? 'Permesso fotocamera negato'
                  : 'Fotocamera non disponibile',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              denied
                  ? 'Serve la fotocamera per leggere il QR del lotto. '
                      'Attivala nelle impostazioni e riprova.'
                  : 'Chiudi le altre app che usano la fotocamera e riprova.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.warningBg),
            ),
            if (denied) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Apri impostazioni'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Apre [QrScannerScreen] e restituisce il testo letto (null se annullato).
Future<String?> showQrScanner(
  BuildContext context, {
  String? hint,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => QrScannerScreen(hint: hint),
      fullscreenDialog: true,
    ),
  );
}
