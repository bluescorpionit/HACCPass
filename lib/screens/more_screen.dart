import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../repositories/haccp_repository.dart';
import '../services/attachment_service.dart';
import '../services/backup_service.dart';
import '../services/license_service.dart';
import '../services/sync_service.dart';
import '../widgets/common_widgets.dart';
import 'cloud_backup_screen.dart';
import 'company_screen.dart';
import 'goods/products_screen.dart';
import 'goods/suppliers_screen.dart';
import 'guide_screen.dart';
import 'license_screen.dart';
import 'modules/extra_screens.dart';
import 'onboarding/onboarding_screen.dart';
import 'sensors/sensor_diagnostics_screen.dart';
import 'storage/attachment_storage_screen.dart';
import 'staff/staff_screen.dart';
import 'temperature/equipment_editor.dart';

/// Hub "Altro": anagrafiche, piano, guida, backup e licenza.
class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.repository,
    required this.license,
    required this.sync,
    required this.backup,
    required this.attachments,
    required this.reminders,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final SyncService sync;
  final BackupService backup;
  final dynamic attachments;
  final dynamic reminders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final entries = <(String, String, IconData, VoidCallback)>[
      (
        'Configurazione guidata',
        'Ripeti o completa la configurazione iniziale',
        Icons.tune,
        () => _push(
          context,
          OnboardingScreen(
            repository: repository,
            license: license,
            attachments: attachments,
            reminders: reminders,
            onFinished: () {},
          ),
        ),
      ),
      (
        'Anagrafica azienda',
        'Ragione sociale, responsabile, P.IVA, notifica sanitaria',
        Icons.store_outlined,
        () => _push(
            context, CompanyScreen(repository: repository, license: license)),
      ),
      (
        'Attrezzature',
        'Frighi, freezer, abbattitori con limiti e preset',
        Icons.kitchen_outlined,
        () => _push(context, EquipmentEditor(repository: repository)),
      ),
      (
        'Fornitori',
        'Registro fornitori e qualifica',
        Icons.local_shipping_outlined,
        () => _push(context,
            SuppliersScreen(repository: repository, license: license)),
      ),
      (
        'Prodotti e allergeni',
        'Schede prodotto con i 14 allergeni',
        Icons.restaurant_menu_outlined,
        () => _push(
            context, ProductsScreen(repository: repository, license: license)),
      ),
      (
        'Personale',
        'Formazione e attestati alimentarista',
        Icons.badge_outlined,
        () => _push(
            context, StaffScreen(repository: repository, license: license)),
      ),
      (
        'Moduli e limiti',
        'Limiti PR COT/ABB/TRA/CAMP configurabili e moduli attivi',
        Icons.tune,
        () => _push(context, LimitsScreen(repository: repository)),
      ),
      (
        'Cultura della sicurezza alimentare',
        'Politica, comunicazioni, verifica annuale (Reg. UE 2021/382)',
        Icons.history_edu_outlined,
        () => _push(
            context,
            CultureScreen(repository: repository, license: license)),
      ),
      (
        'Ridistribuzione alimenti',
        'Registro donazioni (facoltativo, Reg. UE 2021/382)',
        Icons.volunteer_activism_outlined,
        () => _push(
            context,
            DonationsScreen(repository: repository, license: license)),
      ),
      (
        'Guida HACCP',
        'Piano, limiti di riferimento e riferimenti normativi',
        Icons.menu_book_outlined,
        () => _push(context, const GuideScreen()),
      ),
      (
        'Documenti e backup',
        'Cloud, backup cifrato, ripristino e coda di caricamento',
        Icons.cloud_outlined,
        () => _push(
          context,
          CloudBackupScreen(repository: repository, backup: backup, sync: sync),
        ),
      ),
      (
        'Licenza',
        'Stato prova, acquisti e chiave offline',
        Icons.key_outlined,
        () => _push(context, LicenseScreen(license: license)),
      ),
      // Prompt 8: spazio e sicurezza degli allegati.
      (
        'Spazio e allegati',
        'Foto, PDF, spazio usato e "Libera spazio"',
        Icons.photo_library_outlined,
        () => _push(
          context,
          AttachmentStorageScreen(
            repository: repository,
            attachments: AttachmentService(repository: repository),
            cloud: null,
          ),
        ),
      ),
      // FASE 0 sensori Govee: voce visibile SOLO nelle build di debug.
      if (kDebugMode)
        (
          'Diagnostica sensori (debug)',
          'Scansione BLE e byte grezzi Govee H5179',
          Icons.sensors,
          () => _push(context, const SensorDiagnosticsScreen()),
        ),
      // Prompt 10: azzeramento prova/licenza, visibile SOLO nelle build
      // di debug (in release la voce non esiste e il metodo non fa nulla).
      if (kDebugMode)
        (
          'Azzera prova e licenza (debug)',
          'Cancella prova, ancora e stato acquisti, poi riavvia lo stato',
          Icons.restart_alt,
          () => _confirmDebugReset(context),
        ),
    ];

    return ListView(
      padding: screenPadding(context, hasBottomBar: true),
      children: [
        PageHeader(
          title: 'Altro',
          subtitle:
              'Anagrafiche, piano di autocontrollo, backup e licenza. Tutto '
              'offline, nessun account cloud.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.verified_user_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'HACCPass',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Autocontrollo alimentare per piccoli esercizi. I limiti '
                  'dell\u2019app sono valori di riferimento: la '
                  'responsabilit\u00E0 dell\u2019autocontrollo resta '
                  'dell\u2019operatore (Reg. CE 852/2004).',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        for (final (title, subtitle, icon, action) in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ListTile(
                leading: Icon(icon, color: theme.colorScheme.primary),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(subtitle),
                isThreeLine: false,
                trailing: const Icon(Icons.chevron_right),
                onTap: action,
              ),
            ),
          ),
      ],
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Conferma l'azzeramento di prova e licenza (solo build debug).
  Future<void> _confirmDebugReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Azzerare prova e licenza?'),
        content: const Text(
          'Cancella la data della prova, l\u2019ancora (Keychain/file), le '
          'impostazioni license_* e iap_*, poi riavvia lo stato del '
          'servizio. Disponibile solo nelle build di debug.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Azzera'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await license.debugReset();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prova e licenza azzerate (solo build debug).'),
        ),
      );
    }
  }
}
