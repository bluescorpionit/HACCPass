import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_links.dart';

/// Apre un indirizzo pubblico in app esterna (browser di sistema).
Future<void> openExternalUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Nessun browser disponibile: silenzio, il link resta leggibile.
  }
}

/// Frase obbligatoria per Apple 3.1.2 sotto il pulsante di acquisto:
/// "Il rinnovo è automatico; gestisci o disdici dallo store. Continuando
/// accetti i [Termini] e l'[Informativa privacy]" con link in linea
/// (sempre da `AppLinks`: nessun URL scritto altrove).
class LegalLinksText extends StatelessWidget {
  const LegalLinksText({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextStyle(
      color: theme.colorScheme.primary,
      decoration: TextDecoration.underline,
    );
    return Text.rich(
      TextSpan(
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        children: [
          const TextSpan(
            text: 'Il rinnovo \u00E8 automatico; gestisci o disdici dallo '
                'store. Continuando accetti i ',
          ),
          TextSpan(
            text: 'Termini',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openExternalUrl(AppLinks.termsUrl),
          ),
          const TextSpan(text: ' e l\u2019'),
          TextSpan(
            text: 'Informativa privacy',
            style: linkStyle,
            recognizer: TapGestureRecognizer()
              ..onTap = () => openExternalUrl(AppLinks.privacyUrl),
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
