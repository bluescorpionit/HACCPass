/// Costanti e regole HACCP di riferimento.
///
/// I valori sono tratti dai manuali di corretta prassi (FIDA 2020 e linee
/// guida per esercizi di somministrazione) e dal Reg. CE 852/2004.
/// Sono valori di riferimento: l'operatore può adattarli alla propria
/// attività. La responsabilità dell'autocontrollo resta dell'operatore.
library;

/// Preset di temperatura per attrezzature (PRP 11).
class EquipmentPreset {
  const EquipmentPreset({
    required this.label,
    required this.type,
    required this.minTemp,
    required this.maxTemp,
  });

  final String label;
  final String type;
  final double minTemp;
  final double maxTemp;

  String get rangeLabel =>
      '${minTemp.toStringAsFixed(0)} / ${maxTemp.toStringAsFixed(0)} °C';
}

const List<String> equipmentTypes = [
  'Frigorifero',
  'Congelatore',
  'Cella refrigerata',
  'Banco frigo',
  'Abbatitore',
  'Mantenimento a caldo',
];

const List<EquipmentPreset> equipmentPresets = [
  EquipmentPreset(label: 'Frigo +4 °C', type: 'Frigorifero', minTemp: 0, maxTemp: 4),
  EquipmentPreset(label: 'Frigo verdure e uova', type: 'Frigorifero', minTemp: 0, maxTemp: 7),
  EquipmentPreset(label: 'Frigo bevande', type: 'Frigorifero', minTemp: 0, maxTemp: 8),
  EquipmentPreset(label: 'Congelatore -18 °C', type: 'Congelatore', minTemp: -30, maxTemp: -18),
  EquipmentPreset(label: 'Mantenimento a caldo', type: 'Mantenimento a caldo', minTemp: 60, maxTemp: 90),
  EquipmentPreset(label: 'Cotti consumati freddi', type: 'Frigorifero', minTemp: 0, maxTemp: 10),
];

/// Azioni correttive suggerite per temperature fuori limite (scelta multipla).
const List<String> temperatureCorrectiveActions = [
  'Verificata chiusura della porta e delle guarnizioni',
  'Nuova misura dopo 30 minuti',
  'Prodotti spostati in altra attrezzatura',
  'Valutato il prodotto per aspetto e tempo/temperatura',
  'Prodotto smaltito',
  'Contattata l\u2019assistenza tecnica',
];

/// Verifica periodica dei termometri (PRP 4): ogni 6 mesi.
const int thermometerCheckIntervalDays = 182;
const double thermometerTolerance = 1.0;
const double thermometerReplaceThreshold = 3.0;

/// Frequenze del piano di pulizia (PRP 2).
enum CleaningFrequency {
  afterUse('after_use', 'Dopo ogni utilizzo'),
  daily('daily', 'Giornaliera'),
  twiceDaily('twice_daily', '2 volte al giorno'),
  weekly('weekly', 'Settimanale'),
  monthly('monthly', 'Mensile'),
  semiannual('semiannual', 'Semestrale'),
  annual('annual', 'Annuale'),
  asNeeded('as_needed', 'Al bisogno');

  const CleaningFrequency(this.code, this.label);
  final String code;
  final String label;

  static CleaningFrequency fromCode(String code) => CleaningFrequency.values
      .firstWhere((f) => f.code == code, orElse: () => CleaningFrequency.daily);

  /// Mappa le frequenze testuali del DB v1 sui nuovi codici.
  static CleaningFrequency fromLegacyLabel(String label) {
    final l = label.toLowerCase();
    if (l.contains('dopo ogni')) return CleaningFrequency.afterUse;
    if (l.contains('2 volte')) return CleaningFrequency.twiceDaily;
    if (l.contains('giornal')) return CleaningFrequency.daily;
    if (l.contains('settiman')) return CleaningFrequency.weekly;
    if (l.contains('mensil')) return CleaningFrequency.monthly;
    if (l.contains('semestr') || l.contains('6 mes')) {
      return CleaningFrequency.semiannual;
    }
    if (l.contains('annual')) return CleaningFrequency.annual;
    return CleaningFrequency.asNeeded;
  }

  static CleaningFrequency? tryFromLabel(String? label) {
    if (label == null) return null;
    for (final f in CleaningFrequency.values) {
      if (f.label == label) return f;
    }
    return null;
  }
}

/// Categorie merce e limiti di temperatura al ricevimento (PRP 10, Allegato V).
class GoodsCategory {
  const GoodsCategory({
    required this.code,
    required this.label,
    this.minTemp,
    this.maxTemp,
  });

  final String code;
  final String label;
  final double? minTemp;
  final double? maxTemp;

  bool get hasTempRange => minTemp != null || maxTemp != null;

  String get rangeLabel {
    if (minTemp != null && maxTemp != null) {
      return '${minTemp!.toStringAsFixed(0)} / ${maxTemp!.toStringAsFixed(0)} °C';
    }
    if (maxTemp != null) return 'max ${maxTemp!.toStringAsFixed(0)} °C';
    if (minTemp != null) return 'min ${minTemp!.toStringAsFixed(0)} °C';
    return 'temperatura ambiente';
  }
}

const List<GoodsCategory> goodsCategories = [
  GoodsCategory(code: 'dairy', label: 'Latticini e formaggi freschi', minTemp: 0, maxTemp: 4),
  GoodsCategory(code: 'meat', label: 'Carni fresche e insaccati', minTemp: -1, maxTemp: 7),
  GoodsCategory(code: 'fish', label: 'Pesce fresco', minTemp: -1, maxTemp: 2),
  GoodsCategory(code: 'frozen', label: 'Surgelati', maxTemp: -15),
  GoodsCategory(code: 'frozen_meat', label: 'Carni congelate', maxTemp: -15),
  GoodsCategory(code: 'fresh_pasta', label: 'Pasta fresca (tolleranza 2 °C)', maxTemp: 4),
  GoodsCategory(code: 'cream_sweets', label: 'Dolci con panna o crema', maxTemp: 4),
  GoodsCategory(code: 'fvg', label: 'Ortofrutta IV gamma', maxTemp: 8),
  GoodsCategory(code: 'hot_cooked', label: 'Cotti caldi', minTemp: 60),
  GoodsCategory(code: 'cold_cooked', label: 'Cotti da consumare freddi', maxTemp: 10),
  GoodsCategory(code: 'ambient', label: 'Uova, ortofrutta, secco, bevande'),
];

GoodsCategory goodsCategoryByCode(String code) => goodsCategories
    .firstWhere((c) => c.code == code, orElse: () => goodsCategories.last);

/// I 14 allergeni del Reg. UE 1169/2011, Allegato II.
class AllergenInfo {
  const AllergenInfo(this.code, this.label, this.number);
  final String code;
  final String label;
  final int number;
}

const List<AllergenInfo> allergens = [
  AllergenInfo('gluten', 'Glutine', 1),
  AllergenInfo('crustaceans', 'Crostacei', 2),
  AllergenInfo('eggs', 'Uova', 3),
  AllergenInfo('fish', 'Pesce', 4),
  AllergenInfo('peanuts', 'Arachidi', 5),
  AllergenInfo('soy', 'Soia', 6),
  AllergenInfo('milk', 'Latte', 7),
  AllergenInfo('nuts', 'Frutta a guscio', 8),
  AllergenInfo('celery', 'Sedano', 9),
  AllergenInfo('mustard', 'Senape', 10),
  AllergenInfo('sesame', 'Sesamo', 11),
  AllergenInfo('sulphites', 'Solfiti', 12),
  AllergenInfo('lupins', 'Lupini', 13),
  AllergenInfo('molluscs', 'Molluschi', 14),
];

AllergenInfo allergenByCode(String code) =>
    allergens.firstWhere((a) => a.code == code, orElse: () => allergens.first);

List<String> parseAllergenCodes(String? csv) {
  if (csv == null || csv.trim().isEmpty) return const [];
  return csv.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

String allergenCodesToCsv(List<String> codes) => codes.join(',');

/// Destino del prodotto in chiusura NC.
enum NcDisposition {
  none('none', 'Nessuna azione sul prodotto'),
  disposed('disposed', 'Prodotto smaltito'),
  returned('returned', 'Reso al fornitore'),
  isolated('isolated', 'Isolato in attesa di decisione'),
  cooked('cooked', 'Utilizzato dopo cottura');

  const NcDisposition(this.code, this.label);
  final String code;
  final String label;

  static NcDisposition fromCode(String? code) => NcDisposition.values
      .firstWhere((d) => d.code == code, orElse: () => NcDisposition.none);
}

/// Categorie di non conformità (Allegato I).
const List<String> ncCategories = [
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

/// Motivi di eliminazione prodotto (Allegato II).
const List<String> wasteReasons = [
  'Scaduto',
  'Alterato',
  'Contaminato',
  'Confezione danneggiata',
  'Temperatura non conforme',
  'Restituito al fornitore',
  'Altro',
];

/// Livelli di infestazione (PRP 3).
enum PestLevel { acceptable, moderate, severe }

const String pestLevelAcceptable = 'Accettabile';
const String pestLevelModerate = 'Modesto';
const String pestLevelSevere = 'Notevole';

PestLevel pestLevelForRodents(int count) =>
    count <= 0 ? PestLevel.acceptable : PestLevel.severe;

PestLevel pestLevelForCrawlers(int count) {
  if (count <= 3) return PestLevel.acceptable;
  if (count <= 7) return PestLevel.moderate;
  return PestLevel.severe;
}

PestLevel pestLevelForFlyers(int count) {
  if (count <= 20) return PestLevel.acceptable;
  if (count <= 30) return PestLevel.moderate;
  return PestLevel.severe;
}

String pestLevelLabel(PestLevel level) => switch (level) {
      PestLevel.acceptable => pestLevelAcceptable,
      PestLevel.moderate => pestLevelModerate,
      PestLevel.severe => pestLevelSevere,
    };

/// Tipi di postazione infestanti.
const List<String> pestStationTypes = ['Roditori', 'Striscianti', 'Volanti'];

/// Azioni consigliate per infestazione notebole.
const List<String> pestSevereActions = [
  'Sospendere l\u2019attività nell\u2019area interessata',
  'Allontanare gli alimenti a rischio',
  'Coprire le attrezzature',
  'Aerare e pulire prima di riprendere l\u2019attività',
  'Contattare la ditta di disinfestazione',
];

/// Monitoraggio strutture (Allegato VII).
const List<String> structureAreas = [
  'Esterno',
  'Locale di lavorazione',
  'Locale di stoccaggio',
  'Servizi igienici',
  'Apparecchiature refrigeranti',
  'Attrezzature',
];

const List<String> structureCheckItems = [
  'Distacchi di intonaco o vernice',
  'Integrità di pavimenti e piastrelle',
  'Integrità di porte, finestre e retine',
  'Rubinetti gocciolanti',
  'Presenza di umidità',
  'Integrità delle guarnizioni',
  'Anomalie meccaniche',
];

const int structureCheckIntervalDays = 182;
const int pestCheckIntervalDays = 30;

/// Zona di rischio: tra +10 e +60 °C. Oltre 2 ore il prodotto va riportato a
/// temperatura o valutato (Reg. CE 852/2004, Allegato II).
const double dangerZoneMin = 10;
const double dangerZoneMax = 60;
const int dangerZoneMaxHours = 2;

/// Tempi di conservazione della documentazione (Reg. CE 178/2002).
const Map<String, String> recordRetentionHints = {
  'freschi': 'Prodotti freschi: conservare le registrazioni 3 mesi.',
  'tte': '"Da consumarsi entro": 6 mesi dopo la scadenza.',
  'tmc': '"Preferibilmente entro": 12 mesi dopo la scadenza.',
  'altri': 'Altri prodotti: 2 anni.',
};

/// Frequenza di verifica termometri in mesi.
const int thermometerCheckMonths = 6;

/// Scadenza formazione alimentarista.
const int staffCertificateExpiryDays = 365 * 3;
const int staffExpiringSoonDays = 30;
