import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Conferma di uscita con il tasto/gesto Indietro (Prompt 14, §3).
///
/// Da usare SOLE sulle schermate radice (shell, primo avvio, wizard al
/// primo passo): se sopra c'è un'altra route (schermata pushata, foglio
/// modale, dialog) questo `PopScope` non scatta e Indietro chiude prima
/// quella. Non tocca i `PopScope` dedicati (restore wizard, recupero
/// foto, scansione): hanno priorità sulla loro route.
///
/// [onBeforeConfirm] permette di gestire l'evento senza dialog (es.
/// AppShell: se la scheda attiva non è "Oggi" torna a "Oggi"): ritorna
/// true se l'evento è già gestito. [onConfirmExit] è iniettabile per i
/// test (default: `SystemNavigator.pop()`).
///
/// Desktop di sviluppo e iOS: nessun dialog (non esiste il tasto
/// Indietro di sistema; su iOS l'uscita è un gesto home/swipe).
class ExitConfirmScope extends StatelessWidget {
  const ExitConfirmScope({
    super.key,
    required this.child,
    this.onBeforeConfirm,
    this.onConfirmExit,
  });

  final Widget child;

  /// Ritorna true se il back è già gestito (nessun dialog).
  final bool Function()? onBeforeConfirm;

  /// Azione di uscita dopo la conferma (default `SystemNavigator.pop`).
  final Future<void> Function()? onConfirmExit;

  Future<void> _confirmExit(BuildContext context) async {
    final exit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Uscire da HACCPass?'),
        content: const Text(
          'I tuoi dati sono al sicuro e salvati sul telefono.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Resta'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (exit == true) {
      await (onConfirmExit ?? SystemNavigator.pop)();
    }
  }

  @override
  Widget build(BuildContext context) {
    final desktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);
    if (desktop) return child;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (onBeforeConfirm?.call() == true) return;
        _confirmExit(context);
      },
      child: child,
    );
  }
}
