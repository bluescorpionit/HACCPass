import 'haccp_rules.dart';

/// Suggerimenti per tipo di attività: attrezzature, piano di pulizia,
/// prodotti tipici con allergeni indicativi, postazioni infestanti.
///
/// I dati sono **suggerimenti** da adattare: l'app lo dichiara sempre
/// all'operatore. Limiti e frequenze seguono i valori di riferimento dei
/// manuali di corretta prassi (vedi `haccp_rules.dart`).

class EquipmentSuggestion {
  const EquipmentSuggestion({
    required this.key,
    required this.label,
    required this.type,
    required this.minTemp,
    required this.maxTemp,
    this.defaultCount = 1,
    this.location = '',
  });

  final String key;
  final String label;
  final String type;
  final double minTemp;
  final double maxTemp;
  final int defaultCount;
  final String location;
}

class CleaningSuggestion {
  const CleaningSuggestion({
    required this.key,
    required this.area,
    required this.title,
    required this.freqCode,
    this.productName = '',
    this.method = '',
  });

  final String key;
  final String area;
  final String title;
  final String freqCode;
  final String productName;
  final String method;

  CleaningFrequency get frequency =>
      CleaningFrequency.fromCode(freqCode);
}

class ProductSuggestion {
  const ProductSuggestion({
    required this.key,
    required this.name,
    required this.allergens,
    this.category = '',
    this.shelfLifeDays = 0,
  });

  final String key;
  final String name;
  final List<String> allergens;
  final String category;
  final int shelfLifeDays;
}

class PestSuggestion {
  const PestSuggestion({
    required this.key,
    required this.type,
    required this.location,
  });

  final String key;
  final String type;
  final String location;
}

class BusinessTemplate {
  const BusinessTemplate({
    required this.key,
    required this.label,
    required this.ateco,
    required this.equipment,
    required this.cleaning,
    required this.products,
    this.pests = const [
      PestSuggestion(key: 'rodenti_esterno', type: 'Roditori', location: 'Esterno - lato cortile'),
      PestSuggestion(key: 'rodenti_magazzino', type: 'Roditori', location: 'Magazzino - porta carico'),
      PestSuggestion(key: 'striscianti_cucina', type: 'Striscianti', location: 'Cucina - sotto lavello'),
      PestSuggestion(key: 'volanti_sala', type: 'Volanti', location: 'Sala - ingresso'),
    ],
    this.goodsCategories = const ['ambient', 'dairy'],
  });

  final String key;
  final String label;
  final String ateco;
  final List<EquipmentSuggestion> equipment;
  final List<CleaningSuggestion> cleaning;
  final List<ProductSuggestion> products;
  final List<PestSuggestion> pests;

  /// Categorie di merce in arrivo più frequenti (codici di `goodsCategories`).
  final List<String> goodsCategories;

  static BusinessTemplate byKey(String key) => templates
      .firstWhere((t) => t.key == key, orElse: () => templates.last);
}

const _frigoFarciture = EquipmentSuggestion(
  key: 'frigo_farciture',
  label: 'Frigo latticini e farciture',
  type: 'Frigorifero',
  minTemp: 0,
  maxTemp: 4,
  location: 'Banco',
);

const _congelatore = EquipmentSuggestion(
  key: 'congelatore',
  label: 'Congelatore',
  type: 'Congelatore',
  minTemp: -30,
  maxTemp: -18,
  location: 'Magazzino',
);

const _pavimenti2x = CleaningSuggestion(
  key: 'pavimenti',
  area: 'Locale',
  title: 'Pavimenti',
  freqCode: 'twice_daily',
  productName: 'Detergente pavimenti',
  method: 'Aspirare, detergere con mop dedicato e lasciare asciugare.',
);

const _servizi = CleaningSuggestion(
  key: 'servizi_igienici',
  area: 'Servizi igienici',
  title: 'Sanitari e pavimenti',
  freqCode: 'daily',
  productName: 'Detergente sanitari',
  method: 'Detergere sanitari, specchi e pavimenti con prodotti dedicati.',
);

const _pianiLavoro = CleaningSuggestion(
  key: 'piani_lavoro',
  area: 'Cucina',
  title: 'Piani di lavoro e utensili',
  freqCode: 'after_use',
  productName: 'Sanificante superfici',
  method: 'Rimuovere i residui, detergere, risciacquare, sanificare e asciugare.',
);

const List<BusinessTemplate> templates = [
  BusinessTemplate(
    key: 'bar',
    label: 'Bar / Caffetteria',
    ateco: '56.10.11',
    equipment: [
      EquipmentSuggestion(
        key: 'frigo_bevande',
        label: 'Frigo bevande',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 8,
        location: 'Sala',
      ),
      _frigoFarciture,
      _congelatore,
      EquipmentSuggestion(
        key: 'vetrina_brioche',
        label: 'Vetrina brioche',
        type: 'Banco frigo',
        minTemp: 0,
        maxTemp: 8,
        location: 'Bancone',
      ),
    ],
    cleaning: [
      CleaningSuggestion(
        key: 'macchina_caffe',
        area: 'Bancone',
        title: 'Macchina caff\u00E8 e macinadosatore',
        freqCode: 'daily',
        productName: 'Detergente gruppi erogatori',
        method: 'Erogare il detergente nei gruppi, spazzolare i portafiltri, risciacquare.',
      ),
      CleaningSuggestion(
        key: 'superfici_banco',
        area: 'Bancone',
        title: 'Superfici del banco',
        freqCode: 'after_use',
        productName: 'Sanificante superfici',
      ),
      _servizi,
      _pavimenti2x,
    ],
    products: [
      ProductSuggestion(key: 'cappuccino', name: 'Cappuccino', allergens: ['milk']),
      ProductSuggestion(key: 'brioche', name: 'Brioche', allergens: ['gluten', 'eggs', 'milk']),
      ProductSuggestion(key: 'panino', name: 'Panino farcito', allergens: ['gluten', 'milk']),
      ProductSuggestion(key: 'spremuta', name: 'Spremuta d\u2019arancia', allergens: []),
      ProductSuggestion(key: 'tiramisu', name: 'Tiramis\u00F9', allergens: ['gluten', 'eggs', 'milk']),
    ],
    goodsCategories: ['ambient', 'dairy', 'cream_sweets'],
  ),
  BusinessTemplate(
    key: 'ristorante',
    label: 'Ristorante / Trattoria',
    ateco: '56.10.12',
    equipment: [
      EquipmentSuggestion(
        key: 'cella_carne',
        label: 'Cella/frigo carni',
        type: 'Cella refrigerata',
        minTemp: -1,
        maxTemp: 7,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'frigo_pesce',
        label: 'Cella/frigo pesce',
        type: 'Cella refrigerata',
        minTemp: -1,
        maxTemp: 2,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'frigo_verdure',
        label: 'Frigo verdure',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 7,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'abbattitore',
        label: 'Abbattitore',
        type: 'Abbatitore',
        minTemp: 0,
        maxTemp: 4,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'caldo',
        label: 'Mantenimento a caldo (bagnomaria)',
        type: 'Mantenimento a caldo',
        minTemp: 60,
        maxTemp: 90,
        location: 'Sala',
      ),
      _congelatore,
      EquipmentSuggestion(
        key: 'lavastoviglie',
        label: 'Lavastoviglie ad alta temperatura',
        type: 'Attrezzatura',
        minTemp: 0,
        maxTemp: 99,
        location: 'Cucina',
      ),
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'affettatrice',
        area: 'Cucina',
        title: 'Affettatrice',
        freqCode: 'daily',
        productName: 'Detergente + disinfettante',
        method: 'Smontare le parti, lavare, sanificare, risciacquare e asciugare.',
      ),
      _pavimenti2x,
      _servizi,
      CleaningSuggestion(
        key: 'cappe_filtri',
        area: 'Cucina',
        title: 'Filtri cappe',
        freqCode: 'weekly',
        productName: 'sgrassante',
        method: 'Sgrassare i filtri in lavaggio, risciacquare e asciugare.',
      ),
    ],
    products: [
      ProductSuggestion(key: 'pizza_margherita', name: 'Pizza margherita', allergens: ['gluten', 'milk']),
      ProductSuggestion(key: 'pasta_carbonara', name: 'Pasta alla carbonara', allergens: ['gluten', 'eggs']),
      ProductSuggestion(key: 'secondo_carne', name: 'Secondo di carne', allergens: []),
      ProductSuggestion(key: 'dolce_casa', name: 'Dolce della casa', allergens: ['milk', 'eggs']),
    ],
    goodsCategories: ['meat', 'fish', 'fvg', 'frozen'],
  ),
  BusinessTemplate(
    key: 'pizzeria',
    label: 'Pizzeria',
    ateco: '56.10.12',
    equipment: [
      EquipmentSuggestion(
        key: 'frigo_impasti',
        label: 'Frigo impasti e ingredienti',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
        location: 'Laboratorio',
      ),
      _congelatore,
      EquipmentSuggestion(
        key: 'frigo_bibite',
        label: 'Frigo bibite',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 8,
        location: 'Sala',
      ),
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'impastatrice',
        area: 'Laboratorio',
        title: 'Impastatrice',
        freqCode: 'after_use',
        productName: 'Detergente + disinfettante',
      ),
      CleaningSuggestion(
        key: 'forno_piani',
        area: 'Cucina',
        title: 'Forno e piani di lavoro',
        freqCode: 'daily',
        productName: 'Sgrassatore',
      ),
      _pavimenti2x,
      _servizi,
    ],
    products: [
      ProductSuggestion(key: 'pizza_margherita', name: 'Pizza margherita', allergens: ['gluten', 'milk']),
      ProductSuggestion(key: 'pizza_salame', name: 'Pizza con salame', allergens: ['gluten', 'milk']),
      ProductSuggestion(key: 'fritti', name: 'Fritti', allergens: ['gluten']),
      ProductSuggestion(key: 'bibite', name: 'Bibite', allergens: []),
    ],
    goodsCategories: ['ambient', 'dairy', 'frozen', 'meat'],
  ),
  BusinessTemplate(
    key: 'pub',
    label: 'Pub / Paninoteca',
    ateco: '56.30.00',
    equipment: [
      EquipmentSuggestion(
        key: 'frigo_birre',
        label: 'Frigo birre e bibite',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 8,
        location: 'Sala',
      ),
      _frigoFarciture,
      _congelatore,
    ],
    cleaning: [
      CleaningSuggestion(
        key: 'spina_birre',
        area: 'Bancone',
        title: 'Spina birre e contatore',
        freqCode: 'daily',
        productName: 'Detergente linee birra',
      ),
      _pianiLavoro,
      _pavimenti2x,
      _servizi,
    ],
    products: [
      ProductSuggestion(key: 'panino', name: 'Panino farcito', allergens: ['gluten']),
      ProductSuggestion(key: 'patatine', name: 'Patatine fritte', allergens: []),
      ProductSuggestion(key: 'birra', name: 'Birra alla spina', allergens: ['gluten']),
    ],
    goodsCategories: ['ambient', 'meat', 'frozen'],
  ),
  BusinessTemplate(
    key: 'gastronomia',
    label: 'Gastronomia / Rosticceria',
    ateco: '47.11.10',
    equipment: [
      _frigoFarciture,
      EquipmentSuggestion(
        key: 'banco_vetrina',
        label: 'Banco frigo / vetrina gastronomia',
        type: 'Banco frigo',
        minTemp: 0,
        maxTemp: 4,
        location: 'Sala vendita',
      ),
      EquipmentSuggestion(
        key: 'caldo_rosticceria',
        label: 'Mantenimento a caldo',
        type: 'Mantenimento a caldo',
        minTemp: 60,
        maxTemp: 90,
        location: 'Sala vendita',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'affettatrice_gastro',
        area: 'Laboratorio',
        title: 'Affettatrice',
        freqCode: 'after_use',
        productName: 'Detergente + disinfettante',
      ),
      _pavimenti2x,
      _servizi,
      CleaningSuggestion(
        key: 'scaffali_vendita',
        area: 'Sala vendita',
        title: 'Scaffali e banchi vendita',
        freqCode: 'weekly',
        productName: 'Detergente superfici',
      ),
    ],
    products: [
      ProductSuggestion(key: 'affettati', name: 'Affettati misti', allergens: []),
      ProductSuggestion(key: 'formaggi', name: 'Formaggi', allergens: ['milk']),
      ProductSuggestion(key: 'polli_arrosto', name: 'Polli arrosto', allergens: []),
      ProductSuggestion(key: 'insalate', name: 'Insalate pronte', allergens: ['sulphites']),
    ],
    goodsCategories: ['meat', 'dairy', 'frozen', 'hot_cooked'],
  ),
  BusinessTemplate(
    key: 'pasticceria',
    label: 'Pasticceria / Panificio',
    ateco: '10.71.10',
    equipment: [
      EquipmentSuggestion(
        key: 'cella_pasta',
        label: 'Cella pasta lievitata',
        type: 'Cella refrigerata',
        minTemp: 2,
        maxTemp: 6,
        location: 'Laboratorio',
      ),
      EquipmentSuggestion(
        key: 'frigo_creme',
        label: 'Frigo creme e farciture',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
        location: 'Laboratorio',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'sac_a_faire',
        area: 'Laboratorio',
        title: 'Sac \u00E0 faire, becchi e teglie',
        freqCode: 'after_use',
        productName: 'Detergente alimentare',
      ),
      _pavimenti2x,
      _servizi,
      CleaningSuggestion(
        key: 'forno_pasticceria',
        area: 'Laboratorio',
        title: 'Forno e piastre',
        freqCode: 'weekly',
        productName: 'Sgrassatore forni',
      ),
    ],
    products: [
      ProductSuggestion(key: 'torta_crema', name: 'Torta alla crema', allergens: ['gluten', 'eggs', 'milk']),
      ProductSuggestion(key: 'brioche_panificio', name: 'Brioche', allergens: ['gluten', 'eggs', 'milk']),
      ProductSuggestion(key: 'biscotti', name: 'Biscotti', allergens: ['gluten', 'milk']),
      ProductSuggestion(key: 'pane', name: 'Pane', allergens: ['gluten']),
    ],
    goodsCategories: ['ambient', 'dairy', 'cream_sweets', 'frozen'],
  ),
  BusinessTemplate(
    key: 'macelleria',
    label: 'Macelleria / Salumeria',
    ateco: '47.22.10',
    equipment: [
      EquipmentSuggestion(
        key: 'cella_macelleria',
        label: 'Cella frigorifera carni',
        type: 'Cella refrigerata',
        minTemp: -1,
        maxTemp: 7,
        location: 'Laboratorio',
      ),
      EquipmentSuggestion(
        key: 'banco_macelleria',
        label: 'Banco frigo vendita',
        type: 'Banco frigo',
        minTemp: -1,
        maxTemp: 4,
        location: 'Sala vendita',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'macinacarne',
        area: 'Laboratorio',
        title: 'Macinacarne e tritacarne',
        freqCode: 'after_use',
        productName: 'Detergente + disinfettante',
      ),
      _pavimenti2x,
      _servizi,
    ],
    products: [
      ProductSuggestion(key: 'carne_bovina', name: 'Carne bovina', allergens: []),
      ProductSuggestion(key: 'carne_suina', name: 'Carne suina', allergens: []),
      ProductSuggestion(key: 'salumi', name: 'Salumi', allergens: ['sulphites']),
      ProductSuggestion(key: 'polpette', name: 'Polpette', allergens: ['gluten', 'eggs']),
    ],
    goodsCategories: ['meat', 'frozen_meat'],
  ),
  BusinessTemplate(
    key: 'pescheria',
    label: 'Pescheria',
    ateco: '47.23.10',
    equipment: [
      EquipmentSuggestion(
        key: 'banco_ghiaccio',
        label: 'Banco con ghiaccio',
        type: 'Banco frigo',
        minTemp: -1,
        maxTemp: 2,
        location: 'Sala vendita',
      ),
      EquipmentSuggestion(
        key: 'cella_pesce',
        label: 'Cella frigorifera pesce',
        type: 'Cella refrigerata',
        minTemp: -1,
        maxTemp: 2,
        location: 'Laboratorio',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'banco_pesce',
        area: 'Sala vendita',
        title: 'Banco pesce e griglie',
        freqCode: 'daily',
        productName: 'Detergente + disinfettante',
      ),
      _pavimenti2x,
      _servizi,
    ],
    products: [
      ProductSuggestion(key: 'pesce_fresco', name: 'Pesce fresco', allergens: ['fish']),
      ProductSuggestion(key: 'frutti_mare', name: 'Frutti di mare', allergens: ['molluscs', 'crustaceans']),
      ProductSuggestion(key: 'sushi', name: 'Preparati di pesce', allergens: ['fish', 'soy']),
    ],
    goodsCategories: ['fish', 'frozen'],
  ),
  BusinessTemplate(
    key: 'caseificio',
    label: 'Caseificio / Laboratorio',
    ateco: '10.51.10',
    equipment: [
      EquipmentSuggestion(
        key: 'cella_stagionatura',
        label: 'Cella di stagionatura',
        type: 'Cella refrigerata',
        minTemp: 2,
        maxTemp: 8,
        location: 'Laboratorio',
      ),
      EquipmentSuggestion(
        key: 'frigo_latte',
        label: 'Frigo latte e latticini',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
        location: 'Laboratorio',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'vasche_latte',
        area: 'Laboratorio',
        title: 'Vasche e attrezzature a contatto col latte',
        freqCode: 'after_use',
        productName: 'Detergente + disinfettante alimentare',
      ),
      _pavimenti2x,
      _servizi,
      CleaningSuggestion(
        key: 'pulizia_completa_celle',
        area: 'Laboratorio',
        title: 'Pulizia completa celle e frigoriferi',
        freqCode: 'semiannual',
        productName: 'Detergente + disinfettante',
      ),
    ],
    products: [
      ProductSuggestion(key: 'latte_crudo', name: 'Latte', allergens: ['milk']),
      ProductSuggestion(key: 'formaggio_fresco', name: 'Formaggio fresco', allergens: ['milk']),
      ProductSuggestion(key: 'yogurt', name: 'Yogurt', allergens: ['milk']),
    ],
    goodsCategories: ['dairy'],
  ),
  BusinessTemplate(
    key: 'mensa',
    label: 'Mensa / Catering',
    ateco: '56.20.11',
    equipment: [
      EquipmentSuggestion(
        key: 'cella_mensa',
        label: 'Cella frigorifera',
        type: 'Cella refrigerata',
        minTemp: 0,
        maxTemp: 4,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'abbattitore_mensa',
        label: 'Abbattitore',
        type: 'Abbatitore',
        minTemp: 0,
        maxTemp: 4,
        location: 'Cucina',
      ),
      EquipmentSuggestion(
        key: 'caldo_mensa',
        label: 'Mantenimento a caldo',
        type: 'Mantenimento a caldo',
        minTemp: 60,
        maxTemp: 90,
        location: 'Distribuzione',
      ),
      EquipmentSuggestion(
        key: 'frigo_cotti',
        label: 'Frigo cotti da consumare freddi',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 10,
        location: 'Cucina',
      ),
      _congelatore,
    ],
    cleaning: [
      _pianiLavoro,
      CleaningSuggestion(
        key: 'linee_distribuzione',
        area: 'Distribuzione',
        title: 'Linee di distribuzione',
        freqCode: 'daily',
        productName: 'Detergente + disinfettante',
      ),
      _pavimenti2x,
      _servizi,
      CleaningSuggestion(
        key: 'lavastoviglie_mensa',
        area: 'Cucina',
        title: 'Lavastoviglie (verifica temperatura lavaggio)',
        freqCode: 'daily',
        productName: 'Detersivo industriale',
      ),
    ],
    products: [
      ProductSuggestion(key: 'primo_piatto', name: 'Primo piatto', allergens: ['gluten']),
      ProductSuggestion(key: 'secondo_mensa', name: 'Secondo piatto', allergens: []),
      ProductSuggestion(key: 'contorno', name: 'Contorno', allergens: []),
      ProductSuggestion(key: 'frutta', name: 'Frutta', allergens: []),
    ],
    goodsCategories: ['meat', 'fish', 'fvg', 'frozen', 'hot_cooked'],
  ),
  BusinessTemplate(
    key: 'altro',
    label: 'Altro',
    ateco: '56.10.90',
    equipment: [
      EquipmentSuggestion(
        key: 'frigo_generico',
        label: 'Frigorifero',
        type: 'Frigorifero',
        minTemp: 0,
        maxTemp: 4,
      ),
      _congelatore,
    ],
    cleaning: [_pianiLavoro, _pavimenti2x, _servizi],
    products: [],
    goodsCategories: ['ambient', 'dairy'],
  ),
];

/// Unisce i suggerimenti di pi\u00F9 tipi di attivit\u00E0 senza duplicati.
List<EquipmentSuggestion> mergeEquipment(List<BusinessTemplate> list) {
  final map = <String, EquipmentSuggestion>{};
  for (final t in list) {
    for (final e in t.equipment) {
      map.putIfAbsent(e.key, () => e);
    }
  }
  return map.values.toList();
}

List<CleaningSuggestion> mergeCleaning(List<BusinessTemplate> list) {
  final map = <String, CleaningSuggestion>{};
  for (final t in list) {
    for (final c in t.cleaning) {
      map.putIfAbsent(c.key, () => c);
    }
  }
  return map.values.toList();
}

List<ProductSuggestion> mergeProducts(List<BusinessTemplate> list) {
  final map = <String, ProductSuggestion>{};
  for (final t in list) {
    for (final p in t.products) {
      map.putIfAbsent(p.key, () => p);
    }
  }
  return map.values.toList();
}

List<PestSuggestion> mergePests(List<BusinessTemplate> list) {
  final map = <String, PestSuggestion>{};
  for (final t in list) {
    for (final p in t.pests) {
      map.putIfAbsent(p.key, () => p);
    }
  }
  return map.values.toList();
}
