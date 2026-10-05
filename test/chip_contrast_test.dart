import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:blue_haccp/core/theme/app_theme.dart';
import 'package:blue_haccp/widgets/common_widgets.dart';

import 'theme_contrast_test.dart' show contrastRatio;

void main() {
  Color effectiveTextColor(WidgetTester tester, String text) {
    final painter =
        tester.renderObject<RenderParagraph>(find.text(text)).text;
    return painter.style?.color ?? Colors.black;
  }

  /// Sfondo effettivo del chip: risolto come fa RawChip, dal ChipTheme
  /// inherited alla posizione del chip e dal suo stato di selezione
  /// (selectedColor / backgroundColor del tema chip).
  Color chipBackgroundColor(WidgetTester tester, String text) {
    final element = find.text(text).evaluate().first;
    final chipTheme = ChipTheme.of(element);
    ChoiceChip? choiceChip;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget is ChoiceChip) {
        choiceChip = ancestor.widget as ChoiceChip;
        return false;
      }
      return true;
    });
    final selected = choiceChip?.selected ?? false;
    return selected
        ? chipTheme.selectedColor ?? chipTheme.backgroundColor!
        : chipTheme.backgroundColor!;
  }

  Widget harness(ThemeData theme, Widget child) => MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('ChoiceChipX: contrasto testo/sfondo nei 4 stati (light)',
      (tester) async {
    await tester.pumpWidget(
      harness(
        AppTheme.light(),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChoiceChipX(label: 'normale', selected: false, onSelected: (_) {}),
            ChoiceChipX(label: 'selezionato', selected: true, onSelected: (_) {}),
            const ChoiceChipX(label: 'disabilitato', selected: false),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = AppTheme.light().colorScheme;

    // Non selezionato: testo onSurface su superficie del chip.
    var fg = effectiveTextColor(tester, 'normale');
    var bg = chipBackgroundColor(tester, 'normale');
    expect(
      contrastRatio(fg, bg),
      greaterThanOrEqualTo(4.5),
      reason: 'normale: ${contrastRatio(fg, bg).toStringAsFixed(2)}',
    );
    expect(fg.toARGB32(), scheme.onSurface.toARGB32());

    // Selezionato: testo onSecondaryContainer su secondaryContainer.
    fg = effectiveTextColor(tester, 'selezionato');
    bg = chipBackgroundColor(tester, 'selezionato');
    expect(
      contrastRatio(fg, bg),
      greaterThanOrEqualTo(4.5),
      reason: 'selezionato: ${contrastRatio(fg, bg).toStringAsFixed(2)}',
    );
    expect(bg.toARGB32(), scheme.secondaryContainer.toARGB32());
    expect(fg.toARGB32(), scheme.onSecondaryContainer.toARGB32());
  });

  testWidgets('ChoiceChipX: contrasto nei 3 stati (dark)', (tester) async {
    await tester.pumpWidget(
      harness(
        AppTheme.dark(),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ChoiceChipX(label: 'normale', selected: false, onSelected: (_) {}),
            ChoiceChipX(label: 'selezionato', selected: true, onSelected: (_) {}),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scheme = AppTheme.dark().colorScheme;

    var fg = effectiveTextColor(tester, 'normale');
    var bg = chipBackgroundColor(tester, 'normale');
    expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));

    fg = effectiveTextColor(tester, 'selezionato');
    bg = chipBackgroundColor(tester, 'selezionato');
    expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
    expect(bg.toARGB32(), scheme.secondaryContainer.toARGB32());
    expect(fg.toARGB32(), scheme.onSecondaryContainer.toARGB32());
  });

  testWidgets('chip semantici S\u00EC/No: coppie con contrasto AA',
      (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        harness(
          theme,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChoiceChipX(
                label: 'siOk',
                selected: true,
                onSelected: (_) {},
                semantic: ChipSemantic.success,
              ),
              ChoiceChipX(
                label: 'noKo',
                selected: true,
                onSelected: (_) {},
                semantic: ChipSemantic.danger,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      final colors =
          theme.extension<HaccpColors>()!;

      var fg = effectiveTextColor(tester, 'siOk');
      var bg = chipBackgroundColor(tester, 'siOk');
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5),
          reason: 'success dark=${theme.brightness}');
      expect(bg.toARGB32(), colors.successBg.toARGB32());
      expect(fg.toARGB32(), colors.success.toARGB32());

      fg = effectiveTextColor(tester, 'noKo');
      bg = chipBackgroundColor(tester, 'noKo');
      expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5),
          reason: 'danger dark=${theme.brightness}');
      expect(bg.toARGB32(), colors.dangerBg.toARGB32());
      expect(fg.toARGB32(), colors.danger.toARGB32());
    }
  });

  testWidgets('chip disabilitato: testo ancora leggibile (>= 4.5:1)',
      (tester) async {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      await tester.pumpWidget(
        harness(
          theme,
          const ChoiceChipX(label: 'off', selected: false),
        ),
      );
      await tester.pumpAndSettle();

      final fg = effectiveTextColor(tester, 'off');
      final bg = chipBackgroundColor(tester, 'off');
      expect(
        contrastRatio(fg, bg),
        greaterThanOrEqualTo(4.5),
        reason:
            'disabilitato (${theme.brightness}): ${contrastRatio(fg, bg).toStringAsFixed(2)}',
      );
    }
  });
}
