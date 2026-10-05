import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../widgets/common_widgets.dart';

/// Guida HACCP in-app: regole chiave riformulate, con riferimenti normativi.
/// Nessun testo copiato dai manuali: solo valori e strutture dei registri.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.haccpColors;

    return Scaffold(
      appBar: AppBar(title: const Text('Guida HACCP')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          PageHeader(
            title: 'Come usare l\u2019autocontrollo',
            subtitle:
                'I limiti indicati sono valori di riferimento: adattali alla '
                'tua attivit\u00E0. La responsabilit\u00E0 dell\u2019autocontrollo '
                'resta dell\u2019operatore.',
          ),
          _GuideSection(
            icon: Icons.thermostat,
            color: theme.colorScheme.primary,
            title: 'Temperature (PRP 11)',
            bullets: const [
              'Registra ogni mattina la temperatura delle attrezzature '
                  'refrigeranti: \u00E8 il controllo minimo giornaliero.',
              'Frigo +4 \u00B0C (0/+4), verdure e uova 0/+7, bevande 0/+8, '
                  'congelatore -18 \u00B0C (-30/-18), cotti caldi +60/+90, '
                  'cotti freddi max +10 \u00B0C.',
              'La zona di rischio \u00E8 tra +10 e +60 \u00B0C: oltre 2 ore il '
                  'prodotto va riportato a temperatura o valutato.',
              'Se la lettura \u00E8 fuori limite scegli le azioni correttive '
                  'adottate: l\u2019app apre la non conformit\u00E0 collegata.',
            ],
          ),
          _GuideSection(
            icon: Icons.device_thermostat_outlined,
            color: theme.colorScheme.primary,
            title: 'Verifica termometri (PRP 4)',
            bullets: const [
              'Verifica lo strumento ogni 6 mesi confrontandolo con una '
                  'temperatura di riferimento.',
              'Tolleranza \u00B11 \u00B0C. Oltre \u00B13 \u00B0C il termometro '
                  'va riparato o sostituito: l\u2019app apre una NC.',
            ],
          ),
          _GuideSection(
            icon: Icons.cleaning_services_outlined,
            color: theme.colorScheme.primary,
            title: 'Pulizie e sanificazione (PRP 2)',
            bullets: const [
              'Frequenze tipiche: dopo ogni utilizzo, giornaliera, 2 volte al '
                  'giorno, settimanale, mensile, semestrale (frigoriferi), '
                  'annuale, al bisogno.',
              'Conferma ogni attivit\u00E0 quando eseguita: lo storico alimenta '
                  'il registro PDF.',
              'Se una superficie non \u00E8 idonea (sporco visibile, unto, '
                  'odori) usa "Problema" per aprire la NC.',
            ],
          ),
          _GuideSection(
            icon: Icons.local_shipping_outlined,
            color: theme.colorScheme.primary,
            title: 'Merce in arrivo (PRP 10)',
            bullets: const [
              'Controlla: integrit\u00E0 confezioni, etichetta, scadenza, '
                  'igiene del mezzo e temperatura per categoria.',
              'Limiti al ricevimento: latticini 0/+4, carni -1/+7, pesce '
                  '-1/+2, surgelati max -15, pasta fresca max +4 (+2 di '
                  'tolleranza), dolci con crema max +4, IV gamma max +8, '
                  'cotti caldi min +60, cotti freddi max +10.',
              'Un controllo negativo propone l\u2019esito "Respinta" e apre il '
                  'modulo NC fornitore (Allegato IV).',
              'Fornitori con NC ripetute: valuta la sostituzione.',
            ],
          ),
          _GuideSection(
            icon: Icons.inventory_2_outlined,
            color: theme.colorScheme.primary,
            title: 'Lotti e rintracciabilit\u00E0',
            bullets: const [
              'Ogni produzione ha un codice lotto automatico, scadenza '
                  'precompilata dalla durata del prodotto e allergeni ereditati.',
              'Collega gli ingredienti alle consegne ricevute: dal lotto del '
                  'fornitore trovi subito i lotti da ritirare (Reg. CE 178/2002).',
              'Conservazione della documentazione: freschi 3 mesi; "da '
                  'consumarsi entro" 6 mesi dopo la scadenza; "preferibilmente '
                  'entro" 12 mesi; altri 2 anni. Nessun dato viene cancellato '
                  'automaticamente.',
            ],
          ),
          _GuideSection(
            icon: Icons.pest_control_outlined,
            color: theme.colorScheme.primary,
            title: 'Infestanti (PRP 3)',
            bullets: const [
              'Roditori: 0 accettabile, 1 o pi\u00F9 notevole.',
              'Striscianti (somma): 0-3 accettabile, 4-7 modesto, 8 o pi\u00F9 '
                  'notevole.',
              'Volanti per trappola: fino a 20 accettabile, 21-30 modesto, '
                  '31 o pi\u00F9 notevole.',
              'Livello notevole: sospendi l\u2019attivit\u00E0 nell\u2019area, '
                  'allontana gli alimenti, copri le attrezzature, aerate e '
                  'pulisci, contatta la ditta.',
            ],
          ),
          _GuideSection(
            icon: Icons.report_outlined,
            color: colors.danger,
            title: 'Non conformit\u00E0 e cartelli',
            bullets: const [
              'Ogni NC si chiude solo con un\u2019azione correttiva e il '
                  'destino del prodotto (smaltito, reso, isolato, usato dopo '
                  'cottura).',
              'Il cartello "PRODOTTO NON CONFORME" si stampa e si appende al '
                  'prodotto in attesa di decisione (Allegato III).',
              'Ogni eliminazione di alimento va registrata con motivo e '
                  'quantit\u00E0 (Allegato II).',
            ],
          ),
          _GuideSection(
            icon: Icons.gavel_outlined,
            color: colors.info,
            title: 'Riferimenti normativi',
            bullets: const [
              'Reg. CE 852/2004 e Reg. UE 2021/382: igiene, cultura della '
                  'sicurezza alimentare, gestione allergeni, ridistribuzione '
                  'degli alimenti, contaminazione crociata.',
              'Comunicazione Commissione 2022/C 355/01: orientamenti '
                  'sulla gestione degli allergeni (registro scritto per '
                  'piatto/prodotto, non solo digitale).',
              'Reg. CE 178/2002: rintracciabilit\u00E0 e sicurezza alimentare.',
              'Reg. UE 1169/2011 e D.Lgs. 231/2017: etichettatura e 14 '
                  'allergeni (Allegato II).',
              'Formazione alimentarista: la durata \u00E8 regolata a livello '
                  'regionale (es. L.R. Emilia-Romagna 9/2025, DGR Toscana '
                  '540/2024): configura i mesi di rinnovo in \u201CModuli e '
                  'limiti\u201D.',
              'Manuali di corretta prassi operativa (incluso MGSA-0415 '
                  'Rev.2 09/2020): valori di riferimento adattabili.',
            ],
          ),
          _GuideSection(
            icon: Icons.campaign_outlined,
            color: theme.colorScheme.primary,
            title: 'Cottura, abbattimento, trasporto',
            bullets: const [
              'Cottura: \u2265 75 \u00B0C al cuore; rigenerazione \u2265 65 '
                  '\u00B0C; frittura max 180 \u00B0C senza rabbocchi '
                  '(PR COT 01/02).',
              'Abbattimento: positivo +3 \u00B0C entro 2 ore, negativo -18 '
                  '\u00B0C entro 2 ore (PR ABB, limiti pi\u00F9 ampi '
                  'configurabili).',
              'Mantenimento caldo 60-65 \u00B0C, freddo < 10 \u00B0C, gelati '
                  '-15/-20 \u00B0C; trasporto catering freddi < 10 \u00B0C e '
                  'caldi > 65 \u00B0C (PR TRA / PR SOM).',
              'Pasto campione: \u2265 100 g, 0/+4 \u00B0C per 72 ore '
                  '(PR CAMP 01); acqua e ghiaccio con verifiche periodiche '
                  '(PR APO).',
            ],
          ),
          Card(
            color: colors.infoBg,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contenuti aggiornati a ottobre 2026',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.info,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Contenuti di supporto, non sostituiscono la consulenza '
                    'di un tecnico HACCP o le disposizioni della propria '
                    'ASL/Regione.',
                    style: TextStyle(
                      color: colors.info,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({
    required this.icon,
    required this.color,
    required this.title,
    required this.bullets,
  });

  final IconData icon;
  final Color color;
  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (final bullet in bullets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('\u2022 '),
                      Expanded(child: Text(bullet)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
