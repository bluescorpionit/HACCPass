import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/utils/format.dart';
import '../repositories/haccp_repository.dart';
import '../services/license_service.dart';
import '../services/pdf_service.dart';
import '../widgets/common_widgets.dart';
import 'lots_screen.dart' show PdfPreviewScreen;

enum ReportPeriod { today, last7, thisMonth, lastMonth, last3, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.repository,
    required this.license,
  });

  final HaccpRepository repository;
  final LicenseService license;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportPeriod period = ReportPeriod.last7;
  DateTime customFrom = DateTime.now().subtract(const Duration(days: 7));
  DateTime customTo = DateTime.now();
  var generating = false;
  var includePhotos = true;

  (DateTime, DateTime) get range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (period) {
      ReportPeriod.today => (
          today,
          today.add(const Duration(days: 1)),
        ),
      ReportPeriod.last7 => (
          today.subtract(const Duration(days: 7)),
          today.add(const Duration(days: 1)),
        ),
      ReportPeriod.thisMonth => (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 1),
        ),
      ReportPeriod.lastMonth => (
          DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 1),
        ),
      ReportPeriod.last3 => (
          DateTime(now.year, now.month - 3, 1),
          today.add(const Duration(days: 1)),
        ),
      ReportPeriod.custom => (
          DateTime(customFrom.year, customFrom.month, customFrom.day),
          DateTime(customTo.year, customTo.month, customTo.day)
              .add(const Duration(days: 1)),
        ),
    };
  }

  String get rangeLabel {
    final (from, to) = range;
    final endExclusive = to.subtract(const Duration(days: 1));
    return '${fmtDate(from)} \u2013 ${fmtDate(endExclusive)}';
  }

  Future<void> _generate(
    BuildContext context,
    String title,
    Future<Uint8List> Function() builder,
    String fileName,
  ) async {
    if (!widget.license.ensureLicensed(context)) return;
    setState(() => generating = true);
    try {
      final bytes = await builder();
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            title: title,
            bytes: bytes,
            fileName: fileName,
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generazione non riuscita: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<String> get _companyName async {
    final company = await widget.repository.getCompany();
    return company.name;
  }

  Future<void> _open(
    BuildContext context,
    String title,
    String registerId,
  ) async {
    final (from, to) = range;
    final company = await _companyName;
    if (!context.mounted) return;
    await _generate(
      context,
      title,
      () => PdfService(
        repository: widget.repository,
        license: widget.license,
      ).buildRegister(registerId, from, to),
      'HACCP_${sanitizeFileName(title)}_${sanitizeFileName(company)}_${_stamp()}.pdf',
    );
  }

  String _stamp() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final registers = <(String, String, IconData)>[
      ('temperature', 'Temperature', Icons.thermostat),
      ('thermometer', 'Verifica termometri', Icons.device_thermostat_outlined),
      ('cleaning', 'Pulizie e sanificazione', Icons.cleaning_services_outlined),
      ('receipts', 'Merce in arrivo', Icons.local_shipping_outlined),
      ('lots', 'Lotti e rintracciabilit\u00E0', Icons.inventory_2_outlined),
      ('nc', 'Non conformit\u00E0', Icons.report_outlined),
      ('waste', 'Eliminazione prodotti', Icons.delete_outline),
      ('pest', 'Monitoraggio infestanti', Icons.pest_control_outlined),
      ('structure', 'Monitoraggio strutture', Icons.foundation_outlined),
      ('staff', 'Personale e formazione', Icons.badge_outlined),
      ('suppliers', 'Fornitori', Icons.local_shipping_outlined),
    ];

    return Stack(
      children: [
        ListView(
          padding: screenPadding(context, hasBottomBar: true),
          children: [
            PageHeader(
              title: 'Report',
              subtitle:
                  'Genera i PDF dei registri per il periodo scelto e '
                  'condividili con ASL, email o WhatsApp.',
            ),
            LabeledField(
              label: 'Periodo',
              child: ChoiceRow<ReportPeriod>(
                options: const [
                  (ReportPeriod.today, 'Oggi'),
                  (ReportPeriod.last7, '7 giorni'),
                  (ReportPeriod.thisMonth, 'Mese corrente'),
                  (ReportPeriod.lastMonth, 'Mese scorso'),
                  (ReportPeriod.last3, '3 mesi'),
                  (ReportPeriod.custom, 'Personalizzato'),
                ],
                selected: period,
                onSelected: (v) => setState(() => period = v),
              ),
            ),
            if (period == ReportPeriod.custom)
              Row(
                children: [
                  Expanded(
                    child: DateField(
                      label: 'Dal',
                      value: customFrom,
                      onChanged: (v) => setState(
                          () => customFrom = v ?? customFrom),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DateField(
                      label: 'Al',
                      value: customTo,
                      onChanged: (v) =>
                          setState(() => customTo = v ?? customTo),
                    ),
                  ),
                ],
              ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.date_range_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Periodo selezionato: $rangeLabel',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Includi le foto nel dossier'),
              subtitle: const Text(
                'Appendice fotografica delle non conformit\u00E0 e delle '
                'merci respinte',
              ),
              value: includePhotos,
              onChanged: (v) => setState(() => includePhotos = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: FilledButton.icon(
                onPressed: generating
                    ? null
                    : () async {
                        final (from, to) = range;
                        final company = await _companyName;
                        if (!context.mounted) return;
                        await _generate(
                          context,
                          'Dossier HACCP completo',
                          () => PdfService(
                            repository: widget.repository,
                            license: widget.license,
                          ).buildDossier(from, to, includePhotos: includePhotos),
                          'HACCP_Dossier_${sanitizeFileName(company)}_${_stamp()}.pdf',
                        );
                      },
                icon: const Icon(Icons.picture_as_pdf),
                label: const Text('Dossier completo'),
              ),
            ),
            const SizedBox(height: 8),
            const SectionTitle('Singoli registri'),
            for (final (id, title, icon) in registers)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    leading: Icon(icon, color: theme.colorScheme.primary),
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(rangeLabel),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _open(context, title, id),
                  ),
                ),
              ),
            const SectionTitle('Documenti rapidi'),
            Card(
              child: ListTile(
                leading: Icon(Icons.restaurant_menu_outlined,
                    color: theme.colorScheme.primary),
                title: const Text(
                  'Registro scritto allergeni',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                    'Piatto per piatto, consultabile al banco e stampabile '
                    '(2022/C 355/01)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (!widget.license.ensureLicensed(context)) return;
                  final company = await _companyName;
                  if (!context.mounted) return;
                  await _generate(
                    context,
                    'Registro scritto allergeni',
                    () => PdfService(
                      repository: widget.repository,
                      license: widget.license,
                    ).buildWrittenAllergenRegister(),
                    'HACCP_RegistroAllergeni_${sanitizeFileName(company)}_${_stamp()}.pdf',
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.table_chart_outlined,
                    color: theme.colorScheme.primary),
                title: const Text(
                  'Prospetto riassuntivo moduli',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                    'Moduli, frequenza di compilazione e stato'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final company = await _companyName;
                  if (!context.mounted) return;
                  await _generate(
                    context,
                    'Prospetto riassuntivo',
                    () => PdfService(
                      repository: widget.repository,
                      license: widget.license,
                    ).buildOverviewSheet(),
                    'HACCP_Prospetto_${sanitizeFileName(company)}_${_stamp()}.pdf',
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(Icons.restaurant_menu_outlined,
                    color: theme.colorScheme.primary),
                title: const Text(
                  'Men\u00F9 allergeni per i clienti',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text(
                    'Tabella prodotti x 14 allergeni, formato orizzontale'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final company = await _companyName;
                  if (!context.mounted) return;
                  await _generate(
                    context,
                    'Men\u00F9 allergeni',
                    () => PdfService(
                      repository: widget.repository,
                      license: widget.license,
                    ).buildAllergenMenu(),
                    'HACCP_MenuAllergeni_${sanitizeFileName(company)}_${_stamp()}.pdf',
                  );
                },
              ),
            ),
          ],
        ),
        if (generating)
          Positioned.fill(
            child: ColoredBox(
              color: theme.colorScheme.surface.withValues(alpha: 0.7),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
      ],
    );
  }
}
