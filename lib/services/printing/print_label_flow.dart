import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/printing/label_printer.dart';
import '../../repositories/haccp_repository.dart';
import '../../screens/printer_settings_screen.dart';
import 'generic_label_printer.dart';
import 'print_coordinator.dart';

/// Esito della scelta di adattamento alla carta (Prompt 17, Â§3).
enum GenericFitChoice { shrink, smallerFormat, cancelled }

/// Dialog di adattamento quando l'etichetta Ã¨ piÃ¹ larga della carta
/// (Prompt 17, Â§3): MAI riduzioni nascoste. Opzioni: ridurre per
/// adattare (consigliato), scegliere un formato piÃ¹ piccolo, annullare;
/// la scelta puÃ² essere ricordata (`printer_generic_fit_mode`).
Future<GenericFitChoice> showFitChoiceDialog(
  BuildContext context, {
  required GenericLabelPrinter engine,
  required HaccpRepository repository,
  required LabelSpec spec,
}) async {
  final fit = engine.checkFit(spec);
  var remember = false;
  var choice = GenericFitChoice.cancelled;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) => AlertDialog(
        title: const Text('L\u2019etichetta \u00E8 pi\u00F9 larga della carta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'L\u2019etichetta \u00E8 larga ${fit.labelMm} mm ma la stampante '
              'ne stampa al massimo ${fit.printableMm.toStringAsFixed(0)} mm '
              '(carta dichiarata da ${engine.config.paperWidthMm} mm).',
            ),
            const SizedBox(height: 8),
            Text(
              'Con la riduzione testi e QR diventano piÃ¹ piccoli: verifica '
              'il QR con il telefono dopo la stampa.',
              style: Theme.of(dialogContext).textTheme.bodySmall,
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: remember,
              onChanged: (v) => setDialogState(() => remember = v ?? false),
              title: const Text('Ricorda questa scelta'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                choice = GenericFitChoice.smallerFormat;
                Navigator.pop(dialogContext);
              },
              child: const Text('Formato pi\u00F9 piccolo'),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                choice = GenericFitChoice.shrink;
                Navigator.pop(dialogContext);
              },
              child: const Text('Riduci per adattare'),
            ),
          ),
        ],
      ),
    ),
  );
  if (remember && choice != GenericFitChoice.cancelled) {
    final mode = choice == GenericFitChoice.shrink ? 'shrink' : 'reject';
    engine.config = engine.config.copyWith(fitMode: mode);
    await repository.setSetting('printer_generic_fit_mode', mode);
  }
  return choice;
}

/// Flusso di stampa etichetta per l'utente (Prompt 11, Â§4):
/// - nessuna stampante configurata â†’ propone di configurarla oppure di
///   condividere l'etichetta come PDF (l'app resta pienamente usabile);
/// - stampante configurata â†’ scelta copie, stampa a coda con
///   avanzamento e annulla, messaggi d'errore in italiano.
Future<void> showPrintLabelDialog(
  BuildContext context, {
  required HaccpRepository repository,
  required Uint8List pdfBytes,
  required String title,
  String? pdfFileName,
}) async {
  final coordinator = await PrintCoordinator.load(repository);
  if (!context.mounted) return;

  if (!coordinator.isConfigured) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: const Text(
          'Nessuna stampante configurata: l\u2019app \u00E8 gi\u00E0 '
          'utilizzabile, le etichette si possono stampare in qualsiasi '
          'momento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          OutlinedButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (pdfFileName != null && context.mounted) {
                await Printing.sharePdf(bytes: pdfBytes, filename: pdfFileName);
              }
            },
            icon: const Icon(Icons.share_outlined),
            label: const Text('Condividi PDF'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PrinterSettingsScreen(repository: repository),
                ),
              );
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Configura stampante'),
          ),
        ],
      ),
    );
    return;
  }

  // Prompt 17, §3: l'etichetta più larga della carta non si taglia in
  // silenzio: scelta esplicita (riduci / formato più piccolo / annulla)
  // prima di aprire il dialogo delle copie.
  final engine = coordinator.engine;
  if (engine is GenericLabelPrinter &&
      engine.config.language == GenericLanguage.escpos) {
    final spec = coordinator.settings.spec;
    final fit = engine.checkFit(spec);
    if (!fit.fits) {
      var proceed = engine.config.fitMode == 'shrink';
      if (!proceed && engine.config.fitMode == 'ask') {
        // ignore: use_build_context_synchronously
        final choice = await showFitChoiceDialog(
          context,
          engine: engine,
          repository: repository,
          spec: spec,
        );
        if (choice == GenericFitChoice.shrink) {
          engine.config = engine.config.copyWith(fitMode: 'shrink');
          proceed = true;
        } else if (choice == GenericFitChoice.smallerFormat) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cambia formato in 40\u00D730 da Impostazioni \u2192 '
                  'Stampante e riprova.',
                ),
              ),
            );
          }
          return;
        } else {
          return;
        }
      }
      if (!proceed) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(engine.checkFit(spec).fits
                    ? ''
                    : 'Etichetta più larga della carta: riduci, cambia formato '
                        'o carta più larga (Impostazioni \u2192 Stampante).')),
          );
        }
        return;
      }
    }
  }

  var copies = 1;
  var printing = false;
  var progressDone = 0;
  var progressTotal = 1;
  var resultMessage = '';
  final cancel = PrintCancel();

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: !printing,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${coordinator.engine!.displayName}'
              '${coordinator.settings.deviceName.isNotEmpty ? ' \u2022 ${coordinator.settings.deviceName}' : ''}'
              ' \u2022 ${coordinator.settings.format} mm',
            ),
            if (!printing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Copie:'),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: copies,
                    items: [
                      for (var n = 1; n <= 10; n++)
                        DropdownMenuItem(value: n, child: Text('$n')),
                    ],
                    onChanged: (v) => setState(() => copies = v ?? 1),
                  ),
                ],
              ),
            ],
            if (printing) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: progressTotal == 0 ? null : progressDone / progressTotal,
              ),
              const SizedBox(height: 6),
              Text('Etichetta $progressDone di $progressTotal\u2026'),
            ],
            if (resultMessage.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                resultMessage,
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (printing)
            TextButton(
              onPressed: () => cancel.cancel(),
              child: const Text('Annulla stampa'),
            )
          else ...[
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Chiudi'),
            ),
            FilledButton.icon(
              onPressed: () async {
                setState(() {
                  printing = true;
                  progressTotal = copies;
                  resultMessage = '';
                });
                final result = await coordinator.printPdf(
                  [pdfBytes],
                  copies: copies,
                  onProgress: (done, total) {
                    if (dialogContext.mounted) {
                      setState(() {
                        progressDone = done;
                        progressTotal = total;
                      });
                    }
                  },
                  cancel: cancel,
                );
                if (!dialogContext.mounted) return;
                setState(() {
                  printing = false;
                  if (result.isOk) {
                    resultMessage = 'Fatto: $progressTotal etichette '
                        'inviate alla stampante.';
                  } else if (result.outcome == PrintOutcome.notConnected) {
                    resultMessage = result.italianMessage;
                  } else {
                    resultMessage = result.italianMessage;
                  }
                });
              },
              icon: const Icon(Icons.print),
              label: const Text('Stampa'),
            ),
          ],
        ],
      ),
    ),
  );
}
