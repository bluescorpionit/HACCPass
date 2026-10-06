import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../../core/constants/business_templates.dart';
import '../../../core/constants/haccp_rules.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/format.dart';
import '../../../services/attachment_service.dart';
import '../../../services/onboarding/onboarding_controller.dart';
import '../../../widgets/common_widgets.dart';

// ---------------------------------------------------------------------------
// Passo 0: benvenuto, privacy e termini
// ---------------------------------------------------------------------------

class WelcomeStep extends StatefulWidget {
  const WelcomeStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  void _onController() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Registra temperatura, pulizie, merce e non conformit\u00E0 in pochi '
          'tocchi, genera i PDF per l\u2019ispezione. Tutto resta sul tuo '
          'dispositivo.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: context.haccpColors.infoBg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: context.haccpColors.info),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'L\u2019app aiuta a tenere i registri: la '
                      'responsabilit\u00E0 dell\u2019autocontrollo resta '
                      'dell\u2019operatore (Reg. CE 852/2004).',
                      style: TextStyle(
                        color: context.haccpColors.info,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: controller.termsAccepted,
            onChanged: (v) async {
              if (v == true) {
                await controller.acceptTerms();
              }
            },
              controlAffinity: ListTileControlAffinity.leading,
            title: const Text(
              'Ho letto e accetto i Termini di servizio e l\u2019Informativa '
              'privacy',
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 16,
            children: [
              TextButton.icon(
                onPressed: () =>
                    _openUrl(context, widget.controller.termsUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Termini di servizio'),
              ),
              TextButton.icon(
                onPressed: () =>
                    _openUrl(context, widget.controller.privacyUrl),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Informativa privacy'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Nessun account, nessuna telemetria, nessun dato inviato al '
            'sviluppatore. Il cloud \u00E8 facoltativo e resta il tuo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  void _openUrl(BuildContext context, String url) {
    launchUrlString(url, mode: LaunchMode.externalApplication)
        .catchError((_) => false);
  }
}

// ---------------------------------------------------------------------------
// Passo 1: tipo di attivit\u00E0 (scelta multipla)
// ---------------------------------------------------------------------------

class BusinessTypeStep extends StatefulWidget {
  const BusinessTypeStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<BusinessTypeStep> createState() => _BusinessTypeStepState();
}

class _BusinessTypeStepState extends State<BusinessTypeStep> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Scegli il tipo di attivit\u00E0: servir\u00E0 a proporre '
          'attrezzature, piano di pulizia e prodotti tipici. Potrai '
          'modificare tutto.',
      child: GridView.count(
        crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 3 : 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: [
          for (final template in templates)
            Card(
              color: controller.businessTypes.contains(template.key)
                  ? theme.colorScheme.primaryContainer
                  : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  setState(() {
                    controller.businessTypes.contains(template.key)
                        ? controller.businessTypes.remove(template.key)
                        : controller.businessTypes.add(template.key);
                  });
                  // La selezione pu\u00F2 abilitare il pulsante "Avanti".
                  controller.uiChanged();
                },
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: Text(
                      template.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: controller.businessTypes.contains(template.key)
                            ? theme.colorScheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 2: dati azienda con P.IVA validata e logo
// ---------------------------------------------------------------------------

class CompanyStep extends StatefulWidget {
  const CompanyStep({
    super.key,
    required this.controller,
    required this.attachmentService,
  });

  final OnboardingController controller;
  final AttachmentService attachmentService;

  @override
  State<CompanyStep> createState() => _CompanyStepState();
}

class _CompanyStepState extends State<CompanyStep> {
  late final TextEditingController _vat;

  @override
  void initState() {
    super.initState();
    final company = widget.controller.company;
    _vat = TextEditingController(text: company.vat);
  }

  @override
  void dispose() {
    _vat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final company = widget.controller.company;
    final vatValid = _vat.text.isEmpty || isValidItalianVat(_vat.text);

    return StepBody(
      explanation:
          'Questi dati intestano dossier PDF ed etichette. La P.IVA viene '
          'verificata formalmente.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DraftField(
            label: 'Ragione sociale',
            value: company.name,
            onChanged: (v) => company.name = v,
          ),
          _DraftField(
            label: 'Indirizzo',
            value: company.address,
            onChanged: (v) => company.address = v,
          ),
          _DraftField(
            label: 'Citt\u00E0',
            value: company.city,
            onChanged: (v) => company.city = v,
          ),
          TextField(
            controller: _vat,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'P.IVA (11 cifre)',
              errorText: vatValid
                  ? null
                  : 'Partita IVA non valida: controlla le cifre.',
              suffixIcon: _vat.text.length == 11 && vatValid
                  ? Icon(Icons.check_circle_outline,
                      color: context.haccpColors.success)
                  : null,
            ),
            onChanged: (v) {
              company.vat = v.trim();
              setState(() {});
            },
          ),
          const SizedBox(height: 12),
          _DraftField(
            label: 'Codice ATECO',
            value: company.ateco,
            onChanged: (v) => company.ateco = v,
          ),
          _DraftField(
            label: 'Telefono',
            value: company.phone,
            onChanged: (v) => company.phone = v,
          ),
          _DraftField(
            label: 'Email',
            value: company.email,
            onChanged: (v) => company.email = v,
          ),
          _DraftField(
            label: 'PEC',
            value: company.pec,
            onChanged: (v) => company.pec = v,
          ),
          _DraftField(
            label: 'Numero notifica sanitaria',
            value: company.healthNotification,
            onChanged: (v) => company.healthNotification = v,
          ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: () async {
              final picker = ImagePicker();
              final photo = await picker.pickImage(
                source: ImageSource.gallery,
                maxWidth: 600,
                maxHeight: 600,
              );
              if (photo == null) return;
              await widget.attachmentService.setCompanyLogo(
                sourcePath: photo.path,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Logo salvato.')),
                );
              }
            },
            icon: const Icon(Icons.badge_outlined),
            label: const Text('Logo (compare su PDF ed etichette)'),
          ),
          Text(
            'Il logo si sceglie ora o pi\u00F9 tardi da Anagrafica azienda.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 3: responsabili e personale
// ---------------------------------------------------------------------------

class PeopleStep extends StatefulWidget {
  const PeopleStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<PeopleStep> createState() => _PeopleStepState();
}

class _PeopleStepState extends State<PeopleStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final company = controller.company;
    return StepBody(
      explanation:
          'Il responsabile HACCP firma i registri. Aggiungi i collaboratori '
          'con la data dell\u2019attestato alimentarista.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DraftField(
            label: 'Titolare / responsabile HACCP',
            value: company.haccpManager,
            onChanged: (v) => company.haccpManager = v,
          ),
          _DraftField(
            label: 'Sostituto responsabile',
            value: company.haccpSubstitute,
            onChanged: (v) => company.haccpSubstitute = v,
          ),
          _DraftField(
            label: 'Operatore predefinito (firmato nelle registrazioni)',
            value: widget.controller.people.defaultOperator,
            onChanged: (v) => widget.controller.people.defaultOperator = v,
          ),
          const SectionTitle('Collaboratori'),
          for (final member in controller.staff)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      decoration:
                          const InputDecoration(labelText: 'Nome'),
                      onChanged: (v) => member.name = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration:
                          const InputDecoration(labelText: 'Mansione'),
                      onChanged: (v) => member.job = v,
                    ),
                    const SizedBox(height: 8),
                    DateField(
                      label: 'Attestato alimentarista del',
                      value: member.certificateAt,
                      onChanged: (v) =>
                          setState(() => member.certificateAt = v),
                      allowClear: true,
                    ),
                    Text(
                      member.certificateAt == null
                          ? 'Senza data: risulter\u00E0 mancante in dashboard.'
                          : 'Scadenza calcolata: ${fmtDate(member.certificateAt!
                              .add(const Duration(days: 365 * 3)))}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => setState(
              () => controller.staff.add(StaffDraft()),
            ),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Aggiungi collaboratore'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 4: locali e attrezzature (contatore +/-)
// ---------------------------------------------------------------------------

class EquipmentStep extends StatefulWidget {
  const EquipmentStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<EquipmentStep> createState() => _EquipmentStepState();
}

class _EquipmentStepState extends State<EquipmentStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final suggestions = controller.equipmentSuggestions;

    return StepBody(
      explanation:
          'Cosa hai nella tua attivit\u00E0? I limiti di temperatura sono '
          'precompilati dai preset (valori di riferimento modificabili).',
      child: Column(
        children: [
          for (final suggestion in suggestions)
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            suggestion.label,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            '${suggestion.type} \u2022 '
                            '${suggestion.minTemp.toStringAsFixed(0)}/'
                            '${suggestion.maxTemp.toStringAsFixed(0)} \u00B0C'
                            '${suggestion.location.isEmpty ? '' : ' \u2022 ${suggestion.location}'}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        final current =
                            controller.equipmentCounts[suggestion.key] ?? 0;
                        if (current > 0) {
                          controller.equipmentCounts[suggestion.key] =
                              current - 1;
                        }
                      }),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text(
                      '${controller.equipmentCounts[suggestion.key] ?? 0}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        final current =
                            controller.equipmentCounts[suggestion.key] ?? 0;
                        controller.equipmentCounts[suggestion.key] =
                            current + 1;
                      }),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
              ),
            ),
          if (suggestions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'Scegli prima il tipo di attivit\u00E0 (passo 1) per avere '
                  'suggerimenti, oppure aggiungi le attrezzature dopo da '
                  '\u201CAltro > Attrezzature\u201D.',
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Sorgente temperatura delle attrezzature (Prompt 7): il
          // collegamento vero del sensore avviene in Temperature.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sorgente temperatura delle nuove attrezzature',
                    style:
                        const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manuale (consigliato): l\u2019operatore inserisce il '
                    'valore. Sensore: puoi collegare un Govee H5179 dopo, '
                    'dalla sezione Temperature.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ChoiceRow<bool>(
                    options: const [
                      (false, 'Manuale'),
                      (true, 'Sensore (collego dopo)'),
                    ],
                    selected: controller.equipmentUseSensor,
                    onSelected: (v) => setState(() {
                      controller.equipmentUseSensor = v;
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nomi e posizioni si affinano al volo: dopo la creazione '
            'comparir\u00E0 l\u2019elenco, modificabile da \u201CAltro > '
            'Attrezzature\u201D. Da l\u00EC puoi anche generare etichette QR '
            'da appendere sulle attrezzature.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 5: piano di pulizia proposto
// ---------------------------------------------------------------------------

class CleaningStep extends StatefulWidget {
  const CleaningStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<CleaningStep> createState() => _CleaningStepState();
}

class _CleaningStepState extends State<CleaningStep> {
  /// Le 3 frequenze più comuni restano come chip rapidi; le altre si
  /// scelgono dal menu (bottom sheet) per non riempire la card.
  static const _quickFrequencies = [
    CleaningFrequency.afterUse,
    CleaningFrequency.daily,
    CleaningFrequency.weekly,
  ];

  Future<void> _pickFrequency(CleaningSuggestion suggestion) async {
    final chosen = await showModalBottomSheet<CleaningFrequency>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
          children: [
            Text(
              'Frequenza di \u201C${suggestion.title}\u201D',
              style: Theme.of(sheetContext)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            for (final freq in CleaningFrequency.values)
              ListTile(
                title: Text(freq.label),
                trailing: (widget.controller.cleaningFreq[suggestion.key] ??
                        suggestion.frequency) ==
                    freq
                    ? const Icon(Icons.check_circle_outline)
                    : null,
                onTap: () => Navigator.pop(sheetContext, freq),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      setState(() {
        widget.controller.cleaningFreq[suggestion.key] = chosen;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final suggestions = controller.cleaningSuggestions;

    return StepBody(
      explanation:
          'Proposta basata sulla tua attivit\u00E0: conferma le voci e '
          'regola le frequenze. Potrai modificare tutto dal piano di pulizia.',
      child: Column(
        children: [
          for (final suggestion in suggestions)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        suggestion.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(suggestion.area),
                      value:
                          controller.cleaningEnabled.contains(suggestion.key),
                      onChanged: (v) => setState(() {
                        v
                            ? controller.cleaningEnabled.add(suggestion.key)
                            : controller.cleaningEnabled.remove(suggestion.key);
                      }),
                    ),
                    if (controller.cleaningEnabled.contains(suggestion.key))
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final freq in _quickFrequencies)
                              ChoiceChipX(
                                label: freq.label,
                                selected:
                                    (controller.cleaningFreq[suggestion.key] ??
                                            suggestion.frequency) ==
                                        freq,
                                onSelected: (v) => setState(() {
                                  if (v) {
                                    controller.cleaningFreq[suggestion.key] =
                                        freq;
                                  }
                                }),
                              ),
                            TextButton.icon(
                              onPressed: () => _pickFrequency(suggestion),
                              icon: const Icon(Icons.expand_more),
                              label: Text(
                                'Frequenza: '
                                '${(controller.cleaningFreq[suggestion.key] ?? suggestion.frequency).label}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (suggestions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                    'Nessuna proposta: scegli il tipo di attivit\u00E0 al passo 1.'),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 6: disinfestazione e strutture
// ---------------------------------------------------------------------------

class PestStep extends StatefulWidget {
  const PestStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<PestStep> createState() => _PestStepState();
}

class _PestStepState extends State<PestStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Postazioni di monitoraggio e ditta di disinfestazione. Il '
          'controllo strutture ha cadenza semestrale consigliata.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: const InputDecoration(
              labelText: 'Ditta di disinfestazione (facoltativo)',
            ),
            onChanged: (v) => controller.pestCompanyName = v,
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Telefono ditta',
            ),
            keyboardType: TextInputType.phone,
            onChanged: (v) => controller.pestCompanyPhone = v,
          ),
          const SizedBox(height: 12),
          const Text('Postazioni di monitoraggio'),
          const SizedBox(height: 8),
          for (final pest in controller.pestSuggestions)
            Card(
              child: CheckboxListTile(
                value: controller.pestEnabled.contains(pest.key),
                onChanged: (v) => setState(() {
                  v!
                      ? controller.pestEnabled.add(pest.key)
                      : controller.pestEnabled.remove(pest.key);
                }),
                title: Text(pest.location),
                subtitle: Text(pest.type),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 7: fornitori (manuale o dai contatti)
// ---------------------------------------------------------------------------

class SuppliersStep extends StatefulWidget {
  const SuppliersStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<SuppliersStep> createState() => _SuppliersStepState();
}

class _SuppliersStepState extends State<SuppliersStep> {
  var _importing = false;

  Future<void> _importFromContacts() async {
    setState(() => _importing = true);
    try {
      // Il permesso contatti viene chiesto qui, al primo uso.
      final status = await FlutterContacts.permissions
          .request(PermissionType.read);
      if (status != PermissionStatus.granted &&
          status != PermissionStatus.limited) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Permesso contatti negato: aggiungi i fornitori a mano.'),
          ),
        );
        return;
      }
      final contacts = await FlutterContacts.getAll();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) {
          final withPhone = contacts
              .map((c) => (
                    c.displayName ?? '',
                    c.phones.isEmpty ? '' : c.phones.first.number,
                  ))
              .where((c) => c.$1.isNotEmpty && c.$2.isNotEmpty)
              .take(50)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            children: [
              Text(
                'Scegli i contatti da aggiungere come fornitori',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final (name, phone) in withPhone)
                ListTile(
                  title: Text(name),
                  subtitle: Text(phone),
                  onTap: () {
                    widget.controller.suppliers.add(SupplierDraft(
                      name: name,
                      phone: phone,
                    ));
                    Navigator.pop(sheetContext);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          );
        },
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation:
          'I fornitori si possono aggiungere anche pi\u00F9 tardi, al primo '
          'ricevimento merce.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: _importing ? null : _importFromContacts,
            icon: const Icon(Icons.import_contacts_outlined),
            label: const Text('Importa dai contatti del telefono'),
          ),
          const SizedBox(height: 8),
          for (final supplier in controller.suppliers)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      decoration:
                          const InputDecoration(labelText: 'Nome fornitore'),
                      controller: TextEditingController(text: supplier.name),
                      onChanged: (v) => supplier.name = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: const InputDecoration(labelText: 'Telefono'),
                      controller: TextEditingController(text: supplier.phone),
                      onChanged: (v) => supplier.phone = v,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration:
                          const InputDecoration(labelText: 'Prodotti forniti'),
                      controller:
                          TextEditingController(text: supplier.products),
                      onChanged: (v) => supplier.products = v,
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => setState(
              () => controller.suppliers.add(SupplierDraft()),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Aggiungi fornitore'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 8: prodotti e allergeni
// ---------------------------------------------------------------------------

class ProductsStep extends StatefulWidget {
  const ProductsStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<ProductsStep> createState() => _ProductsStepState();
}

class _ProductsStepState extends State<ProductsStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation: '',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: context.haccpColors.warningBg,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Gli allergeni proposti sono indicativi: verifica sempre '
                'ricette ed etichette dei fornitori (Reg. UE 1169/2011).',
                style: TextStyle(
                  color: context.haccpColors.warning,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (controller.productSuggestions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                    'Nessun prodotto tipico per questa attivit\u00E0: aggiungili '
                    'pi\u00F9 tardi da \u201CAltro > Prodotti e allergeni\u201D.'),
              ),
            )
          else
            for (final product in controller.productSuggestions)
              Card(
                child: CheckboxListTile(
                  value:
                      controller.productsEnabled.contains(product.key),
                  onChanged: (v) => setState(() {
                    v!
                        ? controller.productsEnabled.add(product.key)
                        : controller.productsEnabled.remove(product.key);
                  }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: product.allergens.isEmpty
                      ? const Text('Nessun allergene indicato')
                      : Text(
                          'Allergeni: ${product.allergens.map((a) => allergenByCode(a).label).join(', ')}',
                        ),
                ),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 9: documenti e backup
// ---------------------------------------------------------------------------

class CloudStep extends StatefulWidget {
  const CloudStep({super.key, required this.controller});

  final OnboardingController controller;

  @override
  State<CloudStep> createState() => _CloudStepState();
}

class _CloudStepState extends State<CloudStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onIOS = !kIsWeb && Platform.isIOS;

    return StepBody(
      explanation:
          'Dove salvare backup, PDF e foto? Puoi cambiare o rimandare in '
          'qualsiasi momento da \u201CAltro\u201D.',
      child: RadioGroup<String>(
        groupValue: controller.cloudProvider,
        onChanged: (v) =>
            setState(() => controller.cloudProvider = v ?? 'local'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final choice in <(String, String, IconData, String)>[
              (
                'local',
                'Solo su questo dispositivo',
                Icons.phone_android_outlined,
                'Salvataggio con il foglio di condivisione: funziona con ogni '
                    'cloud installato'
              ),
              (
                'gdrive',
                'Google Drive',
                Icons.cloud_outlined,
                'Cartella \u201CHACCPass\u201D nel tuo Drive: backup '
                    'automatici e copia di PDF e foto'
              ),
              if (onIOS)
                (
                  'icloud',
                  'File e iCloud Drive',
                  Icons.folder_outlined,
                  'Salvataggio tramite l\u2019app File'
                ),
            ])
              Card(
                child: RadioListTile<String>(
                  value: choice.$1,
                  title: Text(
                    choice.$2,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(choice.$4),
                  secondary: Icon(choice.$3),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Cifra i backup con una password'),
              subtitle: const Text(
                'AES-256: senza password non si recupera nulla. Consigliato '
                'perch\u00E9 i backup contengono dati del personale.',
              ),
              value: controller.backupEncrypted,
              onChanged: (v) => setState(
                () => controller.backupEncrypted = v,
              ),
            ),
            if (controller.backupEncrypted)
              TextField(
                decoration: const InputDecoration(
                  labelText:
                      'Password dei backup (non salvata nell\u2019app)',
                ),
                obscureText: true,
                onChanged: (v) => controller.backupPassword = v,
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 10: promemoria
// ---------------------------------------------------------------------------

class RemindersStep extends StatefulWidget {
  const RemindersStep({
    super.key,
    required this.controller,
    required this.onRequestPermission,
    required this.onTestNotification,
  });

  final OnboardingController controller;
  final Future<bool> Function() onRequestPermission;
  final Future<void> Function() onTestNotification;

  @override
  State<RemindersStep> createState() => _RemindersStepState();
}

class _RemindersStepState extends State<RemindersStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Notifiche locali, nessun server. Il permesso viene chiesto ora '
          'e serve solo per i promemoria.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TimeTile(
            label: 'Controllo temperature (mattina)',
            value: controller.reminderMorning,
            onChanged: (v) =>
                setState(() => controller.reminderMorning = v),
          ),
          _TimeTile(
            label: 'Controllo temperature (pomeriggio)',
            value: controller.reminderAfternoon,
            onChanged: (v) =>
                setState(() => controller.reminderAfternoon = v),
          ),
          _TimeTile(
            label: 'Chiusura pulizie',
            value: controller.reminderCleaning,
            onChanged: (v) => setState(() => controller.reminderCleaning = v),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verifiche periodiche (formazione, termometri, '
                    'infestanti, strutture)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChipX(
                        label: 'Disattivato',
                        selected: controller.reminderPeriodic.isEmpty,
                        onSelected: (_) => setState(
                          () => controller.reminderPeriodic = '',
                        ),
                      ),
                      ChoiceChipX(
                        label: 'Settimanale, luned\u00EC 8:00',
                        selected:
                            controller.reminderPeriodic == 'weekly',
                        onSelected: (_) => setState(
                          () => controller.reminderPeriodic = 'weekly',
                        ),
                      ),
                      ChoiceChipX(
                        label: 'Mensile, giorno 1',
                        selected:
                            controller.reminderPeriodic == 'monthly',
                        onSelected: (_) => setState(
                          () => controller.reminderPeriodic = 'monthly',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (controller.notificationsGranted)
            OutlinedButton.icon(
              onPressed: () => widget.onTestNotification(),
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Invia una notifica di prova'),
            )
          else
            FilledButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final granted = await widget.onRequestPermission();
                if (!mounted) return;
                setState(
                  () => controller.notificationsGranted = granted,
                );
                if (!granted) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Permesso negato: puoi riattivarlo dalle '
                          'impostazioni di sistema delle notifiche.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('Attiva i promemoria'),
            ),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final parts = value.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? (int.tryParse(parts.last) ?? 0) : 0;
    final time = TimeOfDay(hour: hour, minute: minute);
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: TextButton(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) {
              onChanged(
                '${picked.hour.toString().padLeft(2, '0')}:'
                '${picked.minute.toString().padLeft(2, '0')}',
              );
            }
          },
          child: Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 11: stampa ed etichette
// ---------------------------------------------------------------------------

class PrintingStep extends StatefulWidget {
  const PrintingStep({
    super.key,
    required this.controller,
    required this.onTestPrint,
  });

  final OnboardingController controller;
  final Future<void> Function() onTestPrint;

  @override
  State<PrintingStep> createState() => _PrintingStepState();
}

class _PrintingStepState extends State<PrintingStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Le etichette dei lotti usano questo formato. La stampante si '
          'sceglie dal sistema: AirPrint su iPhone, servizio di stampa su '
          'Android.',
      child: RadioGroup<String>(
        groupValue: controller.labelFormat,
        onChanged: (v) =>
            setState(() => controller.labelFormat = v ?? '62x40'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final format in const [
              ('62x40', '62 \u00D7 40 mm (predefinito)'),
              ('50x30', '50 \u00D7 30 mm'),
              ('40x30', '40 \u00D7 30 mm'),
            ])
              Card(
                child: RadioListTile<String>(
                  value: format.$1,
                  title: Text(format.$2),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onTestPrint(),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Stampa una prova'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Passo 12: riepilogo
// ---------------------------------------------------------------------------

class SummaryStep extends StatefulWidget {
  const SummaryStep({
    super.key,
    required this.controller,
    required this.onGeneratePlan,
  });

  final OnboardingController controller;
  final Future<void> Function() onGeneratePlan;

  @override
  State<SummaryStep> createState() => _SummaryStepState();
}

class _SummaryStepState extends State<SummaryStep> {
  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return StepBody(
      explanation:
          'Ecco cosa \u00E8 pronto. Puoi rifare la configurazione quando '
          'vuoi da \u201CAltro > Configurazione guidata\u201D.',
      child: FutureBuilder<OnboardingSummary>(
        future: controller.finishPreview,
        builder: (context, snapshot) {
          final data = snapshot.data;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data != null) ...[
                _SummaryTile(
                  icon: Icons.kitchen_outlined,
                  label: '${data.equipmentCount} attrezzature create',
                ),
                _SummaryTile(
                  icon: Icons.cleaning_services_outlined,
                  label: '${data.cleaningCount} attivit\u00E0 di pulizia pianificate',
                ),
                _SummaryTile(
                  icon: Icons.restaurant_menu_outlined,
                  label: '${data.productCount} prodotti con allergeni',
                ),
                _SummaryTile(
                  icon: Icons.badge_outlined,
                  label: '${data.staffCount} persone in organico',
                ),
                _SummaryTile(
                  icon: Icons.local_shipping_outlined,
                  label: '${data.supplierCount} fornitori',
                ),
              ],
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => widget.onGeneratePlan(),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label:
                    const Text('Genera il Piano di autocontrollo (PDF)'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget comuni dei passi
// ---------------------------------------------------------------------------

class StepBody extends StatelessWidget {
  const StepBody({super.key, required this.explanation, required this.child});

  final String explanation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (explanation.isNotEmpty) ...[
          Text(
            explanation,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        child,
      ],
    );
  }
}

class _DraftField extends StatefulWidget {
  const _DraftField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_DraftField> createState() => _DraftFieldState();
}

class _DraftFieldState extends State<_DraftField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        decoration: InputDecoration(labelText: widget.label),
        onChanged: widget.onChanged,
      ),
    );
  }
}
