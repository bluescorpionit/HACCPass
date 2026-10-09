import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/constants/app_links.dart';
import '../services/license_service.dart';
import '../widgets/common_widgets.dart' show screenPadding;
import '../widgets/legal_links.dart';

/// Paywall store-only (Prompt 13): prova gratuita dello store,
/// abbonamento annuale, ripristino, gestione dell'abbonamento e codici
/// promozionali. Nessuna chiave di licenza offline.
///
/// Testi e prezzi sono sempre letti dallo store: mai importi o durate
/// scritti a mano. Gli stati mostrati sono solo quelli deducibili dal
/// plugin, mai scadenze inventate.
class LicenseScreen extends StatefulWidget {
  const LicenseScreen({super.key, required this.license});

  final LicenseService license;

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen> {
  LicenseService get service => widget.license;

  /// Pagina di gestione abbonamento dello store (esterna all'app).
  String get _manageSubscriptionUrl {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'https://apps.apple.com/account/subscriptions';
    }
    return 'https://play.google.com/store/account/subscriptions'
        '?sku=${LicenseProductIds.annual}&package=it.bluescorpion.haccpass';
  }

  Future<void> _openManageSubscription() async {
    try {
      await launchUrl(
        Uri.parse(_manageSubscriptionUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Nessun browser disponibile: il pulsante resta mutamente inutile,
      // l'utente può aprire il link dallo store manualmente.
    }
  }

  /// Codici promozionali Apple: foglio di riscatto di StoreKit (solo iOS).
  Future<void> _presentCodeRedemptionSheet() async {
    try {
      final addition = InAppPurchase.instance
          .getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      await addition.presentCodeRedemptionSheet();
    } catch (_) {
      // Il foglio non è disponibile (es. nessuno StoreKit): silenzio,
      // resta il canale della pagina gestione abbonamento.
    }
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
                const SizedBox(height: 10),
                _manageSubscriptionButton(theme),
              ] else ...[
                _iapSection(context, service, theme),
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
              // Avviso di pagamento: non bloccante, con gestione directa
              // dello store (Prompt 13, §2.5).
              if (service.paymentIssue) ...[
                const SizedBox(height: 12),
                _paymentIssueCard(context, service, theme),
              ],
              if (service.lastError?.isNotEmpty == true) ...[
                const SizedBox(height: 16),
                Text(
                  service.lastError!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              // Link legali (Prompt 11-bis, §6): fonti unica AppLinks.
              const SizedBox(height: 20),
              const LegalLinksText(),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => openExternalUrl(AppLinks.privacyUrl),
                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                label: const Text('Informativa sulla privacy'),
              ),
              TextButton.icon(
                onPressed: () => openExternalUrl(AppLinks.termsUrl),
                icon: const Icon(Icons.description_outlined, size: 18),
                label: const Text('Termini e condizioni'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _manageSubscriptionButton(ThemeData theme) => OutlinedButton.icon(
        onPressed: _openManageSubscription,
        icon: const Icon(Icons.open_in_new),
        label: const Text('Gestisci abbonamento'),
      );

  Widget _paymentIssueCard(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pagamento in sospeso',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              'Lo store non \u00E8 riuscito ad addebitare il rinnovo. '
              'Verifica il metodo di pagamento per mantenere l\u2019accesso.',
            ),
            const SizedBox(height: 10),
            _manageSubscriptionButton(theme),
          ],
        ),
      ),
    );
  }

  Widget _statusCard(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    final colors = theme.colorScheme;
    final (icon, title, message) = _statusOf(service);

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

  /// Stato mostrato nella card: solo ciò che si sa dallo store, mai una
  /// scadenza inventata.
  (IconData, String, String) _statusOf(LicenseService service) {
    if (service.canWrite) {
      if (service.kind == LicenseKind.trial) {
        return (
          Icons.verified_outlined,
          'Prova gratuita in corso',
          'Prova completa: ${service.trialDaysLeft} giorni rimanenti.'
        );
      }
      if (service.kind == LicenseKind.debug) {
        return (
          Icons.verified_outlined,
          'Sblocchi di prova (debug)',
          'Tutte le funzioni sono sbloccate (solo build debug).'
        );
      }
      // Abbonamento: "attivo" o "in verifica" se si sta usando la
      // tolleranza offline.
      final title = service.iapVerifiedNow
          ? 'Abbonamento attivo'
          : 'In verifica (offline: ancora ${service.offlineToleranceDaysLeft} giorni)';
      return (
        Icons.verified_outlined,
        title,
        'Tutte le funzioni sono sbloccate.'
      );
    }
    if (service.clockTampered) {
      return (
        Icons.schedule_outlined,
        'Orologio del dispositivo alterato',
        'Verifica data e ora del telefono. I tuoi dati sono al '
            'sicuro: puoi consultarli ma non registrare nuove '
            'operazioni finch\u00E9 la data non \u00E8 corretta.'
      );
    }
    if (service.subscriptionEnded) {
      return (
        Icons.card_membership,
        'Abbonamento scaduto o sospeso',
        'Riattivalo da "Gestisci abbonamento" o effettua un nuovo '
            'acquisto: nel frattempo l\u2019app \u00E8 in sola lettura.'
      );
    }
    return (
      Icons.lock_outline,
      'Prova scaduta',
      'L\u2019app \u00E8 in sola lettura: puoi consultare i dati ma non '
          'registrare né esportare.'
    );
  }

  Widget _iapSection(
    BuildContext context,
    LicenseService service,
    ThemeData theme,
  ) {
    if (!service.iapAvailable) {
      // Desktop (build di sviluppo): nessuno store, niente vendita.
      if (service.isDesktop) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'La licenza si acquista dall\u2019app per Android o iPhone',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Su questo computer l\u2019app resta in prova locale e poi '
                  'in sola lettura: \u00E8 una build di sviluppo.',
                ),
              ],
            ),
          ),
        );
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gli acquisti non sono disponibili ora',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Controlla la connessione e che sul telefono sia attivo '
                'Google Play (o App Store), poi riprova.',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => service.retryStoreInit(),
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
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
        if (defaultTargetPlatform == TargetPlatform.iOS) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: _presentCodeRedemptionSheet,
            icon: const Icon(Icons.redeem),
            label: const Text('Hai un codice?'),
          ),
        ] else if (defaultTargetPlatform == TargetPlatform.android) ...[
          const SizedBox(height: 6),
          Text(
            'Hai un codice promozionale? Si riscatta dal Play Store.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
}
