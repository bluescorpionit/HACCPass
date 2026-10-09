import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../core/printing/label_printer.dart';
import '../../repositories/haccp_repository.dart';
import '../../screens/printer_settings_screen.dart';
import 'print_coordinator.dart';

/// Flusso di stampa etichetta per l'utente (Prompt 11, §4):
/// - nessuna stampante configurata → propone di configurarla oppure di
///   condividere l'etichetta come PDF (l'app resta pienamente usabile);
/// - stampante configurata → scelta copie, stampa a coda con
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

  var copies = 1;
  var printing = false;
  var progressDone = 0;
  var progressTotal = 1;
  var resultMessage = '';
  final cancel = PrintCancel();

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
                value: progressTotal == 0
                    ? null
                    : progressDone / progressTotal,
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
