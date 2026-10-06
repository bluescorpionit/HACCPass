import 'package:flutter/foundation.dart';

import '../../core/constants/business_templates.dart';
import '../../core/constants/haccp_rules.dart';
import '../../models/haccp_models.dart';
import '../../repositories/haccp_repository.dart';
import '../attachment_service.dart';

/// Stato e applicazione del wizard di prima configurazione.
///
/// Ogni passo salva subito i dati e si pu\u00F2 riprendere; applicare \u00E8
/// idempotente: le righe create dal wizard (`source = 'wizard'`) vengono
/// ricostruite, quelle modificate a mano (`source = 'user'`) restano.
/// Le righe wizard già collegate a registri storici non vengono eliminate:
/// vengono convertite a `source = 'user'` per preservare i riferimenti.
class OnboardingController extends ChangeNotifier {
  OnboardingController({
    required this.repository,
    required this.attachments,
    this.termsUrl = 'https://bluescorpion.example/termini',
    this.privacyUrl = 'https://bluescorpion.example/privacy',
  });

  final HaccpRepository repository;
  final AttachmentService attachments;

  /// URL configurabili di Termini e Privacy (pagine del titolare).
  final String termsUrl;
  final String privacyUrl;

  static const int lastStep = 12;
  bool _disposed = false;

  int step = 0;
  bool loading = false;

  // Passo 0
  bool termsAccepted = false;

  // Passo 1
  final Set<String> businessTypes = {};

  // Passo 2
  final company = _CompanyDraft();

  // Passo 3
  final people = _PeopleDraft();
  final List<StaffDraft> staff = [];

  // Passo 4
  final Map<String, int> equipmentCounts = {};
  final Map<String, EquipmentEdit> equipmentEdits = {};

  /// Sorgente temperatura delle attrezzature create dal wizard: 'sensor'
  /// marca l'attrezzatura come da sensore (collegamento vero da Temperature).
  bool equipmentUseSensor = false;

  // Passo 5
  final Set<String> cleaningEnabled = {};
  final Map<String, CleaningFrequency> cleaningFreq = {};

  // Passo 6
  String pestCompanyName = '';
  String pestCompanyPhone = '';
  final Set<String> pestEnabled = {};

  // Passo 7
  final List<SupplierDraft> suppliers = [];

  // Passo 8
  final Set<String> productsEnabled = {};

  // Passo 9
  String cloudProvider = '';
  String cloudAccount = '';
  bool backupEncrypted = false;
  String backupPassword = '';

  // Passo 10
  String reminderMorning = '09:00';
  String reminderAfternoon = '17:00';
  String reminderCleaning = '22:00';
  String reminderPeriodic = '';
  bool notificationsGranted = false;

  // Passo 11
  String labelFormat = '62x40';

  List<BusinessTemplate> get selectedTemplates =>
      [for (final key in businessTypes) BusinessTemplate.byKey(key)];

  List<EquipmentSuggestion> get equipmentSuggestions =>
      mergeEquipment(selectedTemplates);

  List<CleaningSuggestion> get cleaningSuggestions =>
      mergeCleaning(selectedTemplates);

  List<ProductSuggestion> get productSuggestions =>
      mergeProducts(selectedTemplates);

  List<PestSuggestion> get pestSuggestions => mergePests(selectedTemplates);

  String get stepTitle => switch (step) {
        0 => 'Benvenuto',
        1 => 'Tipo di attivit\u00E0',
        2 => 'Dati dell\u2019azienda',
        3 => 'Responsabili e personale',
        4 => 'Locali e attrezzature',
        5 => 'Piano di pulizia',
        6 => 'Disinfestazione e strutture',
        7 => 'Fornitori',
        8 => 'Prodotti e allergeni',
        9 => 'Documenti e backup',
        10 => 'Promemoria',
        11 => 'Stampa ed etichette',
        _ => 'Riepilogo',
      };

  Future<void> load() async {
    loading = true;
    _notifyListenersIfActive();

    step = await repository.getOnboardingStep();

    final typesRaw = await repository.getSetting('onboarding_business_types');
    businessTypes
      ..clear()
      ..addAll(typesRaw.split(',').where((t) => t.isNotEmpty));

    final companyProfile = await repository.getCompany();
    company.name =
        companyProfile.name == 'La mia attività' ? '' : companyProfile.name;
    company.address = companyProfile.address;
    company.city = companyProfile.city;
    company.vat = companyProfile.vat;
    company.ateco = companyProfile.ateco;
    company.phone = companyProfile.phone;
    company.email = companyProfile.email;
    company.pec = companyProfile.pec;
    company.healthNotification = companyProfile.healthNotification;
    company.haccpManager = companyProfile.haccpManager;
    company.haccpSubstitute = companyProfile.haccpSubstitute;

    cloudProvider = await repository.getSetting('cloud_provider');
    backupEncrypted = await repository.getSetting('backup_encrypted') == '1';

    // Termini gi\u00E0 accettati in una sessione precedente.
    termsAccepted =
        await repository.getSetting('terms_accepted_at') != '' || termsAccepted;

    loading = false;
    _notifyListenersIfActive();
  }

  Future<void> goTo(int value) async {
    step = value.clamp(0, lastStep);
    await repository.setOnboardingStep(step);
    _notifyListenersIfActive();
  }

  /// Notifica una modifica fatta dall'interfaccia (es. selezione del tipo di
  /// attivit\u00E0) che pu\u00F2 abilitare/disabilitare il pulsante "Avanti".
  void uiChanged() => _notifyListenersIfActive();

  Future<void> next() => goTo(step + 1);

  Future<void> back() => goTo(step - 1);

  // ---------------------------------------------------------------------------
  // Applicazione dei passi (idempotente)
  // ---------------------------------------------------------------------------

  /// Passo 0: accettazione termini (versione e data salvate).
  Future<void> acceptTerms() async {
    final now = DateTime.now();
    await repository.setSetting('terms_accepted_at', now.toIso8601String());
    await repository.setSetting('terms_version', '1.0');
    termsAccepted = true;
    _notifyListenersIfActive();
  }

  /// Passo 1: tipi di attivit\u00E0 + preimpostazioni derivate.
  Future<void> saveBusinessTypes() async {
    await repository.setSetting(
      'onboarding_business_types',
      businessTypes.join(','),
    );

    // Preimposta contatori e selezioni suggerite.
    equipmentCounts.clear();
    cleaningEnabled.clear();
    productsEnabled.clear();
    pestEnabled.clear();
    for (final e in equipmentSuggestions) {
      equipmentCounts[e.key] = e.defaultCount;
    }
    for (final c in cleaningSuggestions) {
      cleaningEnabled.add(c.key);
      cleaningFreq[c.key] = c.frequency;
    }
    for (final p in productSuggestions) {
      productsEnabled.add(p.key);
    }
    for (final p in pestSuggestions) {
      pestEnabled.add(p.key);
    }

    // ATECO suggerito dal primo tipo scelto.
    if (businessTypes.isNotEmpty && company.ateco.isEmpty) {
      company.ateco = BusinessTemplate.byKey(businessTypes.first).ateco;
    }
    _notifyListenersIfActive();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notifyListenersIfActive() {
    if (_disposed) return;
    notifyListeners();
  }

  /// Passo 2: anagrafica azienda.
  Future<void> saveCompany() async {
    final current = await repository.getCompany();
    await repository.saveCompany(
      CompanyProfile(
        name: company.name.trim().isEmpty ? current.name : company.name.trim(),
        address: company.address.trim(),
        city: company.city.trim(),
        vat: company.vat.trim(),
        haccpManager: company.haccpManager.trim(),
        haccpSubstitute: company.haccpSubstitute.trim(),
        phone: company.phone.trim(),
        email: company.email.trim(),
        pec: company.pec.trim(),
        healthNotification: company.healthNotification.trim(),
        ateco: company.ateco.trim(),
        activity: selectedTemplates.map((t) => t.label).join(', '),
        defaultOperator: current.defaultOperator,
      ),
    );
  }

  /// Passo 3: responsabili e personale.
  Future<void> savePeople() async {
    final current = await repository.getCompany();
    await repository.saveCompany(
      CompanyProfile(
        name: current.name,
        address: current.address,
        city: current.city,
        vat: current.vat,
        haccpManager: company.haccpManager.trim(),
        haccpSubstitute: company.haccpSubstitute.trim(),
        phone: current.phone,
        email: current.email,
        pec: current.pec,
        healthNotification: current.healthNotification,
        ateco: current.ateco,
        activity: current.activity,
        defaultOperator: people.defaultOperator.trim().isEmpty
            ? (company.haccpManager.trim().isEmpty
                ? current.defaultOperator
                : company.haccpManager.trim())
            : people.defaultOperator.trim(),
      ),
    );

    final existing = await repository.getStaff();
    final existingNames = existing.map((s) => s.name.toLowerCase()).toSet();
    for (final member in staff) {
      if (member.name.trim().isEmpty) continue;
      if (existingNames.contains(member.name.trim().toLowerCase())) continue;
      await repository.saveStaffMember(
        StaffMember(
          id: 0,
          name: member.name.trim(),
          role: member.role,
          job: member.job.trim(),
          certificateAt: member.certificateAt,
        ),
      );
    }
  }

  /// Passo 4: attrezzature (righe wizard ricostruite).
  Future<void> applyEquipment() async {
    final rows = <({
      String key,
      String name,
      String type,
      double minTemp,
      double maxTemp,
      String location,
      String tempSource
    })>[];
    final counters = <String, int>{};
    for (final suggestion in equipmentSuggestions) {
      final count = equipmentCounts[suggestion.key] ?? 0;
      for (var i = 1; i <= count; i++) {
        final edit = equipmentEdits['${suggestion.key}_$i'];
        final baseName =
            count > 1 ? '${suggestion.label} $i' : suggestion.label;
        counters[suggestion.label] = (counters[suggestion.label] ?? 0) + 1;
        rows.add((
          key: suggestion.key,
          name: edit?.name ?? baseName,
          type: suggestion.type,
          minTemp: suggestion.minTemp,
          maxTemp: suggestion.maxTemp,
          location: edit?.location ?? suggestion.location,
          tempSource: equipmentUseSensor ? 'sensor' : 'manual',
        ));
      }
    }
    await repository.applyWizardEquipment(rows);
  }

  /// Passo 5: piano di pulizia.
  Future<void> applyCleaning() async {
    final rows = <({
      String key,
      String area,
      String title,
      String freqCode,
      String? productName,
      String? method
    })>[];
    for (final suggestion in cleaningSuggestions) {
      if (!cleaningEnabled.contains(suggestion.key)) continue;
      rows.add((
        key: suggestion.key,
        area: suggestion.area,
        title: suggestion.title,
        freqCode: (cleaningFreq[suggestion.key] ?? suggestion.frequency).code,
        productName: suggestion.productName,
        method: suggestion.method,
      ));
    }
    await repository.applyWizardCleaning(rows);
  }

  /// Passo 6: postazioni infestanti + ditta.
  Future<void> applyPests() async {
    await repository.setSetting('pest_company_name', pestCompanyName.trim());
    await repository.setSetting('pest_company_phone', pestCompanyPhone.trim());
    await repository.setSetting(
      'pest_cadence',
      'mensile',
    );
    await repository.setSetting(
      'structure_check_cadence_days',
      '$structureCheckIntervalDays',
    );

    final rows = <({String key, String type, String location})>[];
    for (final suggestion in pestSuggestions) {
      if (!pestEnabled.contains(suggestion.key)) continue;
      rows.add((
        key: suggestion.key,
        type: suggestion.type,
        location: suggestion.location,
      ));
    }
    await repository.applyWizardPestStations(rows);
  }

  /// Passo 7: fornitori.
  Future<void> applySuppliers() async {
    final existing = await repository.getSuppliers();
    final existingNames = existing.map((s) => s.name.toLowerCase()).toSet();
    for (final draft in suppliers) {
      if (draft.name.trim().isEmpty) continue;
      if (existingNames.contains(draft.name.trim().toLowerCase())) continue;
      await repository.saveSupplier(
        Supplier(
          id: 0,
          name: draft.name.trim(),
          phone: draft.phone.trim(),
          products: draft.products.trim(),
        ),
      );
    }
  }

  /// Passo 8: prodotti e allergeni.
  Future<void> applyProducts() async {
    final rows = <({
      String key,
      String name,
      List<String> allergens,
      String category,
      int shelfLifeDays
    })>[];
    for (final suggestion in productSuggestions) {
      if (!productsEnabled.contains(suggestion.key)) continue;
      rows.add((
        key: suggestion.key,
        name: suggestion.name,
        allergens: suggestion.allergens,
        category: suggestion.category,
        shelfLifeDays: suggestion.shelfLifeDays,
      ));
    }
    await repository.applyWizardProducts(rows);
  }

  /// Passo 9: cloud e cifratura.
  Future<void> saveCloudChoice() async {
    await repository.setSetting('cloud_provider', cloudProvider);
    await repository.setSetting('cloud_account', cloudAccount);
    await repository.setSetting(
      'backup_encrypted',
      backupEncrypted ? '1' : '0',
    );
  }

  /// Passo 10: promemoria (la riprogrammazione reale avviene nel servizio).
  Future<void> saveReminders() async {
    await repository.setSetting(
        'reminder_temperature_morning', reminderMorning);
    await repository.setSetting(
      'reminder_temperature_afternoon',
      reminderAfternoon,
    );
    await repository.setSetting('reminder_cleaning', reminderCleaning);
    await repository.setSetting('reminder_periodic', reminderPeriodic);
  }

  /// Passo 11: formato etichetta.
  Future<void> saveLabelFormat() {
    return repository.setSetting('label_format', labelFormat);
  }

  /// Conteggi per il riepilogo finale senza chiudere il wizard.
  Future<OnboardingSummary> get finishPreview async {
    final equipment = await repository.getEquipment();
    final cleaning = await repository.getCleaningTasks();
    final products = await repository.getProducts();
    final staffCount = (await repository.getStaff()).length;
    final suppliersCount = (await repository.getSuppliers()).length;
    return OnboardingSummary(
      equipmentCount: equipment.length,
      cleaningCount: cleaning.length,
      productCount: products.length,
      staffCount: staffCount,
      supplierCount: suppliersCount,
    );
  }

  /// Passo 12: chiusura, audit e riepilogo dati creati.
  Future<OnboardingSummary> finish() async {
    await repository.setOnboardingDone();
    await repository.setSetting(
      'onboarding_templates_version',
      templatesVersion,
    );

    final equipment = await repository.getEquipment();
    final cleaning = await repository.getCleaningTasks();
    final products = await repository.getProducts();
    final staffCount = (await repository.getStaff()).length;
    final suppliersCount = (await repository.getSuppliers()).length;

    return OnboardingSummary(
      equipmentCount: equipment.length,
      cleaningCount: cleaning.length,
      productCount: products.length,
      staffCount: staffCount,
      supplierCount: suppliersCount,
    );
  }

  static const String templatesVersion = '2026-10';
}

class OnboardingSummary {
  const OnboardingSummary({
    required this.equipmentCount,
    required this.cleaningCount,
    required this.productCount,
    required this.staffCount,
    required this.supplierCount,
  });

  final int equipmentCount;
  final int cleaningCount;
  final int productCount;
  final int staffCount;
  final int supplierCount;
}

class _CompanyDraft {
  String name = '';
  String address = '';
  String city = '';
  String vat = '';
  String ateco = '';
  String phone = '';
  String email = '';
  String pec = '';
  String healthNotification = '';
  String haccpManager = '';
  String haccpSubstitute = '';
}

class _PeopleDraft {
  String defaultOperator = '';
}

class StaffDraft {
  StaffDraft({
    this.name = '',
    this.job = '',
    this.role = 'Alimentarista',
    this.certificateAt,
  });

  String name;
  String job;
  String role;
  DateTime? certificateAt;
}

class SupplierDraft {
  SupplierDraft({this.name = '', this.phone = '', this.products = ''});

  String name;
  String phone;
  String products;
}

class EquipmentEdit {
  EquipmentEdit({required this.name, required this.location});

  String name;
  String location;
}

/// Validazione formale della Partita IVA italiana (11 cifre, checksum).
bool isValidItalianVat(String vat) {
  if (!RegExp(r'^\d{11}$').hasMatch(vat)) return false;
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    final d = vat.codeUnitAt(i) - 48;
    if (i.isEven) {
      sum += d;
    } else {
      final doubled = d * 2;
      sum += doubled > 9 ? doubled - 9 : doubled;
    }
  }
  final check = (10 - (sum % 10)) % 10;
  return check == vat.codeUnitAt(10) - 48;
}
