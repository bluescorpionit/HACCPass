import 'package:flutter/material.dart';

import '../../repositories/haccp_repository.dart';
import '../../services/attachment_service.dart';
import '../../services/license_service.dart';
import '../../services/pdf_service.dart';
import '../../services/reminder_service.dart';
import '../../services/onboarding/onboarding_controller.dart';
import '../../services/sync_service.dart';
import '../lots_screen.dart' show PdfPreviewScreen;
import 'onboarding_steps.dart';

/// Wizard di prima configurazione: 13 passi (0-12), saltabile, riprendibile
/// e rieseguibile. Su schermi larghi: indice dei passi a sinistra.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.repository,
    required this.license,
    required this.attachments,
    required this.reminders,
    required this.sync,
    required this.onFinished,
  });

  final HaccpRepository repository;
  final LicenseService license;
  final AttachmentService attachments;
  final ReminderService reminders;
  final SyncService sync;
  final VoidCallback onFinished;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingController controller;
  final pageController = PageController();
  var _applying = false;

  @override
  void initState() {
    super.initState();
    controller = OnboardingController(
      repository: widget.repository,
      attachments: widget.attachments,
    );
    controller.load().then((_) {
      if (mounted) {
        pageController.jumpToPage(controller.step);
      }
    });
  }

  @override
  void dispose() {
    pageController.dispose();
    controller.dispose();
    super.dispose();
  }

  bool get _canProceed => switch (controller.step) {
        0 => controller.termsAccepted,
        1 => controller.businessTypes.isNotEmpty,
        _ => true,
      };

  Future<void> _applyCurrentStep() async {
    setState(() => _applying = true);
    try {
      switch (controller.step) {
        case 1:
          await controller.saveBusinessTypes();
        case 2:
          await controller.saveCompany();
        case 3:
          await controller.savePeople();
        case 4:
          await controller.applyEquipment();
        case 5:
          await controller.applyCleaning();
        case 6:
          await controller.applyPests();
        case 7:
          await controller.applySuppliers();
        case 8:
          await controller.applyProducts();
        case 9:
          await controller.saveCloudChoice();
        case 10:
          await controller.saveReminders();
          await widget.reminders.rescheduleAll();
        case 11:
          await controller.saveLabelFormat();
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  Future<void> _next() async {
    await _applyCurrentStep();
    await controller.next();
    pageController.animateToPage(
      controller.step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _back() async {
    await controller.back();
    pageController.animateToPage(
      controller.step,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _skip() => _next();

  Future<void> _finish() async {
    await _applyCurrentStep();
    await controller.finish();
    widget.onFinished();
  }

  Future<void> _generatePlan() async {
    final pdf = PdfService(
      repository: widget.repository,
      license: widget.license,
    );
    final bytes = await pdf.buildSelfControlPlan();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          title: 'Piano di autocontrollo',
          bytes: bytes,
          fileName: 'HACCP_PianoAutocontrollo_${_stamp()}.pdf',
        ),
      ),
    );
  }

  Future<void> _testPrint() async {
    final pdf = PdfService(
      repository: widget.repository,
      license: widget.license,
    );
    final bytes = await pdf.buildTestLabel(controller.labelFormat);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          title: 'Etichetta di prova',
          bytes: bytes,
          fileName: 'HACCP_EtichettaProva_${_stamp()}.pdf',
        ),
      ),
    );
  }

  String _stamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;

    // L'intera schermata (titolo, pagine e barra dei pulsanti) si ricostruisce
    // a ogni cambiamento del controller: il bottone "Avanti" dipende da
    // _canProceed, che cambia con la spunta dei termini e le scelte dei passi.
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final content = _buildPages();

        return Scaffold(
          appBar: AppBar(
            toolbarHeight: 72,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  controller.stepTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18),
                ),
                const SizedBox(height: 2),
                Text(
                  'Passo ${controller.step} di ${OnboardingController.lastStep}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: widget.onFinished,
                child: const Text('Esci'),
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 300,
                  child: _StepIndex(controller: controller),
                ),
                VerticalDivider(
                    width: 1,
                    color: theme.colorScheme.outlineVariant),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(
                value:
                    (controller.step + 1) / (OnboardingController.lastStep + 1),
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 12),
              _buildNavBar(context),
            ],
          ),
        ),
      ),
        );
      },
    );
  }

  /// Barra dei pulsanti del wizard, due livelli: riga 1 = Indietro +
  /// Avanti/Inizia; riga 2 (solo se saltabile) = "Salta questo passo" su
  /// una riga propria a larghezza piena. Nell'ultimo passo non c'e' mai
  /// "Avanti". Con altezza scarsa (landscape, < 600 dp) tutto su una riga
  /// con testi brevi.
  Widget _buildNavBar(BuildContext context) {
    final lastStep = OnboardingController.lastStep;
    final step = controller.step;
    final skippable = step != 0 && step != lastStep;
    final isLast = step == lastStep;
    final compact = MediaQuery.sizeOf(context).height < 600;

    final back = OutlinedButton(
      onPressed: _applying ? null : _back,
      child: const Text('Indietro'),
    );

    final Widget primary;
    if (isLast) {
      primary = FilledButton.icon(
        onPressed: _applying ? null : _finish,
        icon: const Icon(Icons.rocket_launch_outlined),
        label: const Text('Inizia'),
      );
    } else {
      primary = FilledButton(
        onPressed: _applying || !_canProceed ? null : _next,
        child: _applying
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : const Text('Avanti'),
      );
    }

    final skip = TextButton(
      onPressed: _applying ? null : _skip,
      child: Text(compact ? 'Salta' : 'Salta questo passo'),
    );

    if (compact) {
      return Row(
        children: [
          if (step > 0) ...[back, const SizedBox(width: 10)],
          if (skippable)
            Expanded(
              child: Center(
                child: Tooltip(
                  message: 'Salta questo passo',
                  child: skip,
                ),
              ),
            )
          else
            const Spacer(),
          primary,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            if (step > 0) ...[back, const SizedBox(width: 10)],
            Expanded(child: primary),
          ],
        ),
        if (skippable)
          SizedBox(
            height: 44,
            width: double.infinity,
            child: skip,
          ),
      ],
    );
  }

  Widget _buildPages() {
    return PageView.builder(
      controller: pageController,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: OnboardingController.lastStep + 1,
      itemBuilder: (context, index) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final page = switch (index) {
              0 => WelcomeStep(controller: controller),
              1 => BusinessTypeStep(controller: controller),
              2 => CompanyStep(
                  controller: controller,
                  attachmentService: widget.attachments,
                ),
              3 => PeopleStep(controller: controller),
              4 => EquipmentStep(controller: controller),
              5 => CleaningStep(controller: controller),
              6 => PestStep(controller: controller),
              7 => SuppliersStep(controller: controller),
              8 => ProductsStep(controller: controller),
              9 => CloudStep(controller: controller, sync: widget.sync),
              10 => RemindersStep(
                  controller: controller,
                  onRequestPermission:
                      widget.reminders.requestPermission,
                  onTestNotification:
                      widget.reminders.showTestNotification,
                ),
              11 => PrintingStep(
                  controller: controller,
                  onTestPrint: _testPrint,
                ),
              _ => SummaryStep(
                  controller: controller,
                  onGeneratePlan: _generatePlan,
                ),
            };

            if (index == OnboardingController.lastStep) {
              // "Inizia" sta fisso nella barra inferiore (_buildNavBar):
              // il corpo resta scorrevole.
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  page,
                ],
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: page,
            );
          },
        );
      },
    );
  }
}

class _StepIndex extends StatelessWidget {
  const _StepIndex({required this.controller});

  final OnboardingController controller;

  static const _titles = [
    'Benvenuto e privacy',
    'Tipo di attivit\u00E0',
    'Dati dell\u2019azienda',
    'Responsabili e personale',
    'Locali e attrezzature',
    'Piano di pulizia',
    'Disinfestazione e strutture',
    'Fornitori',
    'Prodotti e allergeni',
    'Documenti e backup',
    'Promemoria',
    'Stampa ed etichette',
    'Riepilogo',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      itemCount: _titles.length,
      itemBuilder: (context, index) {
        final current = index == controller.step;
        final done = index < controller.step;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(
                done
                    ? Icons.check_circle
                    : current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                color: current || done
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _titles[index],
                  style: TextStyle(
                    fontWeight:
                        current ? FontWeight.w700 : FontWeight.w500,
                    color: current || done
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
