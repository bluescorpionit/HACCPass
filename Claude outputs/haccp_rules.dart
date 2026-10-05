/// Regole e valori di riferimento HACCP usati dall'app.
///
/// Fonti di riferimento (sintesi, non testo copiato):
/// - Reg. CE 852/2004 (igiene), Reg. CE 178/2002 (rintracciabilità),
///   Reg. UE 1169/2011 (allergeni e informazioni al consumatore)
/// - Manuale di corretta prassi operativa per il commercio al dettaglio
///   (FIDA, validato dal Ministero della Salute il 9/12/2020)
/// - Esempio di manuale di autocontrollo per bar (schemi di registro)
///
/// I valori sono default ragionevoli: l'operatore (OSA) resta responsabile
/// di adattarli alla propria attività, ai prodotti e alle indicazioni in etichetta.
library;

class TempLimit {
  const TempLimit({
    required this.id,
    required this.label,
    this.min,
    this.max,
    this.needsTemp = true,
    this.note = '',
  });

  final String id;
  final String label;
  final double? min;
  final double? max;
  final bool needsTemp;
  final String note;

  String get rangeLabel {
    if (!needsTemp) return 'Temperatura ambiente';
    if (min != null && max != null) {
      return '${_f(min!)} / ${_f(max!)} °C';
    }
    if (max != null) return 'max ${_f(max!)} °C';
    if (min != null) return 'min ${_f(min!)} °C';
    return '-';
  }

  bool isCompliant(double t) {
    if (!needsTemp) return true;
    if (min != null && t < min!) return false;
    if (max != null && t > max!) return false;
    return true;
  }

  static String _f(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class EquipmentPreset {
  const EquipmentPreset({
    required this.label,
    required this.type,
    required this.min,
    required this.max,
    required this.hint,
  });

  final String label;
  final String type;
  final double min;
  final double max;
  final String hint;
}

class Allergen {
  const Allergen(this.code, this.name, this.short);
  final String code;
  final String name;
  final String short;
}

class CleaningFrequency {
  const CleaningFrequency(this.code, this.label, this.days, this.perDay);
  final String code;
  final String label;

  /// Intervallo in giorni (0 = al bisogno).
  final int days;

  /// Quante volte al giorno va eseguita (solo frequenze giornaliere).
  final int perDay;
}

class HaccpRules {
  HaccpRules._();

  // ---------------------------------------------------------------------------
  // Tipi di attrezzatura e preset di temperatura
  // ---------------------------------------------------------------------------
  static const equipmentTypes = <String>[
    'Frigorifero',
    'Congelatore',
    'Cella frigorifera',
    'Banco frigo',
    'Abbattitore',
    'Mantenimento a caldo',
  ];

  static const equipmentPresets = <EquipmentPreset>[
    EquipmentPreset(
      label: 'Frigorifero standard (+4 °C)',
      type: 'Frigorifero',
      min: 0,
      max: 4,
      hint: 'Latticini, carni, prodotti con crema/panna',
    ),
    EquipmentPreset(
      label: 'Frigorifero verdure e uova (+7 °C)',
      type: 'Frigorifero',
      min: 0,
      max: 7,
      hint: 'Ortofrutta, uova; IV gamma < +8 °C',
    ),
    EquipmentPreset(
      label: 'Frigorifero bevande (+8 °C)',
      type: 'Frigorifero',
      min: 0,
      max: 8,
      hint: 'Bibite non deperibili',
    ),
    EquipmentPreset(
      label: 'Congelatore / surgelati (-18 °C)',
      type: 'Congelatore',
      min: -30,
      max: -18,
      hint: 'Surgelati: -18 °C, oscillazioni verso l\'alto max 3 °C',
    ),
    EquipmentPreset(
      label: 'Mantenimento a caldo (+60 °C)',
      type: 'Mantenimento a caldo',
      min: 60,
      max: 90,
      hint: 'Cotti da consumare caldi: +60/+65 °C',
    ),
    EquipmentPreset(
      label: 'Cotti da consumare freddi (+10 °C)',
      type: 'Banco frigo',
      min: 0,
      max: 10,
      hint: 'Arrosti, roast-beef: max +10 °C',
    ),
  ];

  // ---------------------------------------------------------------------------
  // Ricevimento merci: limiti di temperatura all'arrivo
  // ---------------------------------------------------------------------------
  static const receivingCategories = <TempLimit>[
    TempLimit(
      id: 'latticini',
      label: 'Latte fresco, yogurt, formaggi freschi',
      min: 0,
      max: 4,
    ),
    TempLimit(
      id: 'carni',
      label: 'Carni fresche e insaccati',
      min: -1,
      max: 7,
      note: 'Conservare poi a +1/+4 °C',
    ),
    TempLimit(
      id: 'pesce',
      label: 'Pesce fresco',
      min: -1,
      max: 2,
      note: 'Temperatura vicina al ghiaccio fondente',
    ),
    TempLimit(
      id: 'surgelati',
      label: 'Surgelati',
      max: -15,
      note: 'Conservazione -18 °C (tolleranza +3 °C in trasporto)',
    ),
    TempLimit(
      id: 'carni_congelate',
      label: 'Carni congelate',
      max: -15,
    ),
    TempLimit(
      id: 'pasta_fresca',
      label: 'Pasta fresca',
      max: 6,
      note: 'Max +4 °C con tolleranza di 2 °C',
    ),
    TempLimit(
      id: 'crema_panna',
      label: 'Dolci con panna o crema, gastronomia in gelatina',
      max: 4,
    ),
    TempLimit(
      id: 'quarta_gamma',
      label: 'Ortofrutta di IV gamma',
      max: 8,
    ),
    TempLimit(
      id: 'cotti_caldi',
      label: 'Cotti da consumare caldi',
      min: 60,
      max: 90,
    ),
    TempLimit(
      id: 'cotti_freddi',
      label: 'Cotti da consumare freddi',
      max: 10,
    ),
    TempLimit(
      id: 'uova',
      label: 'Uova fresche',
      needsTemp: false,
      note: 'Conservare in frigo su ripiano basso',
    ),
    TempLimit(
      id: 'ortofrutta',
      label: 'Frutta e verdura fresca',
      needsTemp: false,
    ),
    TempLimit(
      id: 'secco',
      label: 'Secco, scatolame, bevande, caffè',
      needsTemp: false,
    ),
  ];

  static TempLimit receivingCategory(String id) {
    return receivingCategories.firstWhere(
      (c) => c.id == id,
      orElse: () => receivingCategories.last,
    );
  }

  // ---------------------------------------------------------------------------
  // Allergeni (Allegato II Reg. UE 1169/2011)
  // ---------------------------------------------------------------------------
  static const allergens = <Allergen>[
    Allergen('1', 'Cereali contenenti glutine', 'Glutine'),
    Allergen('2', 'Crostacei', 'Crostacei'),
    Allergen('3', 'Uova', 'Uova'),
    Allergen('4', 'Pesce', 'Pesce'),
    Allergen('5', 'Arachidi', 'Arachidi'),
    Allergen('6', 'Soia', 'Soia'),
    Allergen('7', 'Latte e lattosio', 'Latte'),
    Allergen('8', 'Frutta a guscio', 'Frutta guscio'),
    Allergen('9', 'Sedano', 'Sedano'),
    Allergen('10', 'Senape', 'Senape'),
    Allergen('11', 'Semi di sesamo', 'Sesamo'),
    Allergen('12', 'Anidride solforosa e solfiti', 'Solfiti'),
    Allergen('13', 'Lupini', 'Lupini'),
    Allergen('14', 'Molluschi', 'Molluschi'),
  ];

  static Allergen? allergenByCode(String code) {
    for (final a in allergens) {
      if (a.code == code) return a;
    }
    return null;
  }

  static List<String> parseAllergens(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    return raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String allergenNames(List<String> codes) {
    return codes
        .map((c) => allergenByCode(c)?.name)
        .whereType<String>()
        .join(', ');
  }

  // ---------------------------------------------------------------------------
  // Frequenze di pulizia e sanificazione
  // ---------------------------------------------------------------------------
  static const cleaningFrequencies = <CleaningFrequency>[
    CleaningFrequency('after_use', 'Dopo ogni utilizzo', 1, 1),
    CleaningFrequency('daily', 'Giornaliera', 1, 1),
    CleaningFrequency('twice_daily', '2 volte al giorno', 1, 2),
    CleaningFrequency('weekly', 'Settimanale', 7, 1),
    CleaningFrequency('monthly', 'Mensile', 30, 1),
    CleaningFrequency('semiannual', 'Semestrale', 182, 1),
    CleaningFrequency('annual', 'Annuale', 365, 1),
    CleaningFrequency('as_needed', 'Al bisogno', 0, 1),
  ];

  static CleaningFrequency cleaningFrequency(String code) {
    return cleaningFrequencies.firstWhere(
      (f) => f.code == code,
      orElse: () => cleaningFrequencies[1],
    );
  }

  static const cleaningAreas = <String>[
    'Cucina',
    'Sala / Locale',
    'Banco',
    'Magazzino',
    'Servizi igienici',
    'Attrezzature',
    'Frigoriferi',
    'Esterno',
  ];

  // ---------------------------------------------------------------------------
  // Non conformità
  // ---------------------------------------------------------------------------
  static const ncCategories = <String>[
    'Temperatura',
    'Ricevimento merci',
    'Materia prima',
    'Pulizia',
    'Infestanti',
    'Attrezzatura',
    'Strutture',
    'Scadenza',
    'Etichettatura',
    'Allergeni',
    'Personale',
    'Altro',
  ];

  static const dispositions = <String>[
    'Nessuna',
    'Smaltito',
    'Reso al fornitore',
    'Isolato in attesa',
    'Utilizzato dopo cottura',
  ];

  static const temperatureActions = <String>[
    'Verificata chiusura porta e guarnizioni',
    'Rilevata di nuovo dopo 30 minuti',
    'Prodotti spostati in altra attrezzatura',
    'Valutato il prodotto (aspetto, tempo/temperatura)',
    'Prodotto smaltito',
    'Contattata assistenza tecnica',
  ];

  static const wasteReasons = <String>[
    'Scaduto',
    'Alterato',
    'Contaminato',
    'Confezione danneggiata',
    'Temperatura non conforme',
    'Restituito',
    'Altro',
  ];

  // ---------------------------------------------------------------------------
  // Infestanti: soglie di intervento
  // ---------------------------------------------------------------------------
  static const pestKinds = <String, String>{
    'rodent': 'Roditori',
    'crawling': 'Striscianti',
    'flying': 'Volanti',
  };

  /// Restituisce Accettabile / Modesto / Notevole.
  static String pestLevel(String kind, int count) {
    switch (kind) {
      case 'rodent':
        return count >= 1 ? 'Notevole' : 'Accettabile';
      case 'crawling':
        if (count >= 8) return 'Notevole';
        if (count >= 4) return 'Modesto';
        return 'Accettabile';
      case 'flying':
        if (count >= 31) return 'Notevole';
        if (count >= 21) return 'Modesto';
        return 'Accettabile';
      default:
        return 'Accettabile';
    }
  }

  static const pestThresholdHint = <String, String>{
    'rodent': 'Accettabile: 0 · Notevole: 1 o più',
    'crawling': 'Accettabile: 0-3 · Modesto: 4-7 · Notevole: 8 o più',
    'flying': 'Accettabile: fino a 20 · Modesto: 21-30 · Notevole: 31 o più',
  };

  // ---------------------------------------------------------------------------
  // Monitoraggio strutture e attrezzature
  // ---------------------------------------------------------------------------
  static const structureChecklist = <String, List<String>>{
    'Aree e strutture esterne': ['Integrità pavimentazione'],
    'Locale di lavorazione': [
      'Distacco di intonaco o vernice',
      'Integrità pavimento e piastrelle',
      'Integrità porte, finestre e retine',
      'Rubinetti gocciolanti',
      'Presenza di umidità',
    ],
    'Locale stoccaggio': [
      'Distacco di intonaco o vernice',
      'Integrità pavimento e piastrelle',
      'Integrità porte, finestre e retine',
      'Rubinetti gocciolanti',
      'Presenza di umidità',
    ],
    'Servizi igienici': [
      'Distacco di intonaco o vernice',
      'Integrità pavimento e piastrelle',
      'Integrità porte, finestre e retine',
      'Rubinetti gocciolanti',
      'Presenza di umidità',
    ],
    'Apparecchiature refrigeranti': ['Integrità guarnizioni'],
    'Attrezzature': ['Anomalie meccaniche'],
  };

  // ---------------------------------------------------------------------------
  // Parametri di verifica
  // ---------------------------------------------------------------------------

  /// Verifica termometri: scostamento massimo ammesso (°C).
  static const thermometerTolerance = 1.0;

  /// Oltre questo scostamento il termometro va sostituito o riparato (°C).
  static const thermometerReplaceDelta = 3.0;

  /// Verifica termometri ogni 6 mesi circa.
  static const thermometerIntervalDays = 182;

  static const pestCheckIntervalDays = 30;
  static const structureCheckIntervalDays = 182;
  static const trainingWarningDays = 30;

  static const units = <String>['kg', 'g', 'pz', 'l', 'conf.'];

  static const staffRoles = <String>[
    'Titolare / Responsabile HACCP',
    'Addetto alla preparazione',
    'Cuoco',
    'Banconista',
    'Cameriere',
    'Addetto alle pulizie',
    'Altro',
  ];

  /// Tempi di conservazione della documentazione di rintracciabilità.
  static const retentionHint =
      'Freschi: 3 mesi · "Da consumarsi entro": 6 mesi dopo la scadenza · '
      '"Preferibilmente entro": 12 mesi · Altri prodotti: 2 anni.';
}
