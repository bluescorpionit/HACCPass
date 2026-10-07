import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/license_service.dart';
import '../widgets/common_widgets.dart' show screenPadding;

/// Paywall: prova gratuita dello store, abbonamento annuale e chiave di
/// licenza offline (vendita diretta, nascosta su iOS).
///
/// Testi e prezzi sono sempre letti dallo store: mai importi o durate
/// scritti a mano.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, required this.license});

  final LicenseService license;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  final keyController = TextEditingController();

  LicenseService get service => widget.license;

  @override
  void dispose() {
    keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(title: const Text('Licenza HACCPass')),
      body: ListView(
        padding: screenPadding(context, horizontal: 24),
        children: [
          // Logo dell'app: in tema scuro resta in contenitore chiaro.
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? Colors.white
                    : null,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset(
                'assets/images/logo.png',
                width: 96,
                height: 96,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'HACCPass',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 16),
          _statusCard(context, service, theme),
              const SizedBox(height: 20),
              Text(
                'Con la licenza ottieni',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final benefit in const [
                'Registrazioni illimitate di tutti i controlli',
                'Dossier HACCP completo in PDF, pronto per l\u2019ispezione',
                'Etichette con QR e men\u00F9 allergeni',
                'Backup e ripristino dei dati',
                'Tutto offline: nessun account, nessun server',
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline,
                          color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(child: Text(benefit)),
                    ],
                  ),
                ),
              const SizedBox(height: 24),
              if (service.canWrite &&
                  !service.trialActive &&
                  service.kind != LicenseKind.debug) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Licenza gi\u00E0 attiva. Grazie!',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ] else ...[
                _iapSection(context, service, theme),
                const SizedBox(height: 16),
                // Le chiavi offline restano nascoste su iOS: lo sblocco con
                // codici immessi nell'app pu\u00F2 violare la guideline 3.1.1
                // di Apple. Abilitate solo su Android e desktop.
                if (!Platform.isIOS) ...[
                  _offlineKeySection(context, service, theme),
                  const SizedBox(height: 16),
                ],
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await service.debugUnlock();
                      if (ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'Sblocchi di prova attivato (solo build debug).'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.developer_mode_outlined),
                    label: const Text('Sblocco di prova (solo debug)'),
                  ),
                ],
              ],
              if (service.lastError?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text(
                  service.lastError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusCard(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    final colors = theme.colorScheme;
    final (icon, title, message) = service.canWrite
        ? (
            Icons.verified_outlined,
            service.isLifetime ? 'Licenza a vita attiva' : 'Licenza attiva',
            service.kind == LicenseKind.trial
                ? 'Prova gratuita completa: ${service.trialDaysLeft} giorni rimanenti.'
                : 'Tutte le funzioni sono sbloccate.'
          )
        : service.clockTampered
            ? (
                Icons.schedule_outlined,
                'Orologio del dispositivo alterato',
                'Verifica data e ora del telefono. I tuoi dati sono al '
                    'sicuro: puoi consultarli ma non registrare nuove '
                    'operazioni finch\u00E9 la data non \u00E8 corretta.'
              )
            : (
                Icons.lock_outline,
                'Prova scaduta',
                'L\u2019app \u00E8 in sola lettura: puoi consultare i dati ma non '
                    'registrare né esportare.'
              );

    return Card(
      color: service.canWrite ? null : colors.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 34, color: colors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
          ],
        ),
      ),
    );
  }

  Widget _iapSection(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    if (!service.iapAvailable) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Acquisti in-app non disponibili su questo dispositivo',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Puoi sbloccare l\u2019app con una chiave di licenza fornita '
                'dal fornitore (qui sotto).',
              ),
            ],
          ),
        ),
      );
    }

    final trialCta =
        !service.canWrite && service.freeTrialAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (trialCta) ...[
          // Prova gratuita gestita dallo store: reinstallare non la
          // rigenera. Testo e prezzo letti dallo store.
          SizedBox(
            height: 56,
            child: FilledButton.icon(
              onPressed: () => _buyAnnual(service),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Inizia prova gratuita'),
            ),
          ),
          if (service.annualOfferText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                service.annualOfferText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 10),
        ],
        if (service.annualPrice.isNotEmpty)
          SizedBox(
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => _buyAnnual(service),
              icon: const Icon(Icons.calendar_month),
              label: Text(
                'Abbonamento annuale \u2022 ${service.annualPrice}',
              ),
            ),
          ),
        const SizedBox(height: 10),
        // Richiesto da Apple: sempre visibile su iOS.
        TextButton.icon(
          onPressed: () => service.restorePurchases(),
          icon: const Icon(Icons.restore),
          label: const Text('Ripristina acquisti'),
        ),
      ],
    );
  }

  Future<void> _buyAnnual(LicenseService service) async {
    try {
      // Sceglie l'offerta con fase gratuita se presente (Android) o il
      // prodotto annuale (iOS: l'offerta introduttiva è applicata da
      // StoreKit).
      final product = service.productToBuy();
      if (product != null) {
        await service.buyOrRestore(product);
      }
    } catch (_) {
      // Lo stato arriva dalla purchaseStream / lastError.
    }
  }

  Widget _offlineKeySection(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Hai una chiave di licenza?',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Formato: BH1-CODICE-AAAAMMGG-FIRMA',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Chiave di licenza',
                hintText: 'BH1-XXXXX-20991231-ABC12',
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final ok = await service.unlockWithKey(keyController.text);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Licenza attivata. Grazie!'
                          : 'Chiave non valida o scaduta.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.key),
              label: const Text('Attiva chiave'),
            ),
          ],
        ),
      ),
    );
  }
}
