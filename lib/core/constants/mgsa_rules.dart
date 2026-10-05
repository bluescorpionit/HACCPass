/// Parametri e valori di riferimento dai manuali di corretta prassi
/// (MGSA-0415 Rev.2 09/2020, schede PR COT/ABB/TRA/SOM/CAMP/APO/ALL/RIN).
///
/// Sono **default configurabili**: l'operatore pu\u00F2 adattarli alla propria
/// attivit\u00E0 da "Altro > Moduli e limiti". La responsabilit\u00E0
/// dell'autocontrollo resta dell'operatore.
library;

/// Categorie della tabella PR COT 01: temperatura al cuore e tempo minimo.
class CookingRule {
  const CookingRule(this.category, this.coreTemp, this.holdSeconds,
      {this.note = ''});

  final String category;

  /// Temperatura minima al cuore in \u00B0C.
  final double coreTemp;

  /// Tempo di mantenimento in secondi.
  final int holdSeconds;
  final String note;
}

const List<CookingRule> cookingRulesPRCOT01 = [
  CookingRule('Carni bovine e suine (pezzo intero)', 72, 120),
  CookingRule('Roast-beef', 63, 180),
  CookingRule('Uova fresche in guscio', 63, 15),
  CookingRule(
      'Preparati a base di pesce, carne, selvaggina allevata', 68, 15),
  CookingRule('Pollame, carne, pesce, pasta ripiena', 74, 15),
  CookingRule(
      'Muscolo intero: bistecche, scaloppine, costate', 63, 15,
      note: 'sulla superficie'),
  CookingRule('Altri alimenti di origine animale', 63, 15),
];

/// Limiti di cottura e rigenerazione (PR COT).
const double defaultCookingCoreMin = 75.0;
const double defaultRegenerationCoreMin = 65.0;
const double defaultFryerMaxTemp = 180.0;

/// Abbattimento (PR ABB): default; la PR COT 01 ammette limiti pi\u00F9
/// ampi (< 10 \u00B0C in 2 h positivo, < -20 \u00B0C in 4 h negativo),
/// configurabili.
const double defaultBlastChillPosTemp = 3.0;
const int defaultBlastChillPosHours = 2;
const double defaultBlastChillNegTemp = -18.0;
const int defaultBlastChillNegHours = 2;
const double wideBlastChillPosTemp = 10.0;
const int wideBlastChillPosHours = 2;
const double wideBlastChillNegTemp = -20.0;
const int wideBlastChillNegHours = 4;

/// Mantenimento e trasporto (PR TRA / PR SOM).
const double defaultHoldHotMin = 60.0;
const double defaultHoldHotMax = 65.0;
const double defaultHoldColdMax = 10.0;
const double defaultIceMin = -20.0;
const double defaultIceMax = -15.0;
const double defaultTransportColdMax = 10.0;
const double defaultTransportHotMin = 65.0;

/// Pasto campione (PR CAMP 01).
const double defaultSampleGrams = 100.0;
const int defaultSampleRetentionHours = 72;
const double defaultSampleStorageMin = 0.0;
const double defaultSampleStorageMax = 4.0;

/// Acqua potabile e ghiaccio (PR APO).
const int waterAnalysisIntervalDays = 365;
const int iceMachineSanitizeIntervalDays = 30;

/// Azioni correttive suggerite per cottura non conforme.
const List<String> cookingCorrectiveActions = [
  'Prodotto ricottura fino a temperatura raggiunta',
  'Prodotto eliminato',
  'Verificato il funzionamento dell\u2019attrezzatura',
  'Contattata l\u2019assistenza tecnica',
];

/// Chiavi settings dei limiti configurabili e dei moduli attivi.
class MgsaSettings {
  static const cookingCoreMin = 'limit_cooking_core_min';
  static const regenerationCoreMin = 'limit_regen_core_min';
  static const fryerMaxTemp = 'limit_fryer_max';
  static const blastChillPosTemp = 'limit_abb_pos_temp';
  static const blastChillPosHours = 'limit_abb_pos_hours';
  static const blastChillNegTemp = 'limit_abb_neg_temp';
  static const blastChillNegHours = 'limit_abb_neg_hours';
  static const holdColdMax = 'limit_hold_cold_max';
  static const transportColdMax = 'limit_transport_cold_max';
  static const transportHotMin = 'limit_transport_hot_min';
  static const sampleGrams = 'limit_sample_grams';
  static const sampleRetentionHours = 'limit_sample_hours';
  static const trainingRenewalMonths = 'training_renewal_months';

  /// Moduli attivabili/disattivabili.
  static const moduleCooking = 'module_cooking';
  static const moduleBlastChill = 'module_blast_chill';
  static const moduleTransport = 'module_transport';
  static const moduleSamples = 'module_samples';
  static const moduleWater = 'module_water';
  static const moduleRecall = 'module_recall';
  static const moduleCulture = 'module_culture';
  static const moduleDonations = 'module_donations';
}
