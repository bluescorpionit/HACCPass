import 'package:flutter/material.dart';

import '../models/haccp_models.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../widgets/common_widgets.dart';

/// Anagrafica azienda (serve per intestare i PDF).
class CompanyScreen extends StatefulWidget {
  const CompanyScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  State<CompanyScreen> createState() => _CompanyScreenState();
}

class _CompanyScreenState extends State<CompanyScreen> {
  final controllers = <String, TextEditingController>{};
  var loaded = false;

  static const _fields = <(String, String, String)>[
    ('company_name', 'Ragione sociale / nome attivit\u00E0', 'Rossi Srl'),
    ('company_address', 'Indirizzo', 'Via Roma 1'),
    ('company_city', 'Citt\u00E0', 'Milano'),
    ('company_vat', 'P.IVA', '01234567890'),
    ('company_haccp_manager', 'Responsabile HACCP', 'Mario Rossi'),
    ('company_haccp_substitute', 'Sostituto responsabile', 'Anna Bianchi'),
    ('company_phone', 'Telefono', '02 1234567'),
    ('company_email', 'Email', 'info@azienda.it'),
    ('company_pec', 'PEC', 'azienda@pec.it'),
    (
      'company_health_notification',
      'Numero notifica sanitaria',
      'XX000000000'
    ),
    ('company_ateco', 'Codice ATECO', '56.10.11'),
    ('company_activity', 'Descrizione attivit\u00E0', 'Bar con cucina'),
    ('default_operator', 'Operatore predefinito', 'Operatore'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final (key, _, _) in _fields) {
      controllers[key] = TextEditingController();
    }
    final company = await widget.repository.getCompany();
    final values = company.settingsMap;
    for (final entry in values.entries) {
      controllers[entry.key]?.text = entry.value;
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _save() async {
    if (!widget.license.ensureLicensed(context)) return;
    await widget.repository.saveCompany(
      CompanyProfile(
        name: controllers['company_name']!.text.trim(),
        address: controllers['company_address']!.text.trim(),
        city: controllers['company_city']!.text.trim(),
        vat: controllers['company_vat']!.text.trim(),
        haccpManager: controllers['company_haccp_manager']!.text.trim(),
        haccpSubstitute: controllers['company_haccp_substitute']!.text.trim(),
        phone: controllers['company_phone']!.text.trim(),
        email: controllers['company_email']!.text.trim(),
        pec: controllers['company_pec']!.text.trim(),
        healthNotification:
            controllers['company_health_notification']!.text.trim(),
        ateco: controllers['company_ateco']!.text.trim(),
        activity: controllers['company_activity']!.text.trim(),
        defaultOperator: controllers['default_operator']!.text.trim(),
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Anagrafica salvata.')),
      );
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Anagrafica azienda')),
      body: ListView(
        padding: screenPadding(context, top: 8),
        children: [
          PageHeader(
            title: 'Dati dell\u2019attivit\u00E0',
            subtitle:
                'Servono per intestare dossier e registri. Ragione sociale e '
                'responsabile HACCP sono obbligatori per i PDF.',
          ),
          for (final (key, label, hint) in _fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: TextField(
                controller: controllers[key],
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                ),
              ),
            ),
          SizedBox(
            height: 54,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Salva anagrafica'),
            ),
          ),
        ],
      ),
    );
  }
}
