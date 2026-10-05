import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/theme/app_theme.dart';
import 'package:haccpass/widgets/common_widgets.dart';

/// Rapporto di contrasto WCAG tra due colori.
double contrastRatio(Color a, Color b) {
  double luminance(Color color) {
    final argb = color.toARGB32();
    double channel(int v8) {
      final v = v8 / 255.0;
      return v <= 0.03928
          ? v / 12.92
          : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((argb >> 16) & 0xFF) +
        0.7152 * channel((argb >> 8) & 0xFF) +
        0.0722 * channel(argb & 0xFF);
  }

  final l1 = luminance(a);
  final l2 = luminance(b);
  final lighter = l1 > l2 ? l1 : l2;
  final darker = l1 > l2 ? l2 : l1;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Contrasto palette (WCAG)', () {
    final light = AppTheme.light();
    final dark = AppTheme.dark();
    final lightColors = light.extension<HaccpColors>()!;
    final darkColors = dark.extension<HaccpColors>()!;

    Map<String, (Color, Color)> textPairs(ThemeData t, HaccpColors c) => {
          'onSurface/surface': (t.colorScheme.onSurface, t.colorScheme.surface),
          'onSurface/scaffold': (
            t.colorScheme.onSurface,
            t.scaffoldBackgroundColor
          ),
          'onSurfaceVariant/surface': (
            t.colorScheme.onSurfaceVariant,
            t.colorScheme.surface
          ),
          'primary/onPrimary (light)': (
            t.colorScheme.onPrimary,
            t.colorScheme.primary
          ),
          'success/bg': (c.success, c.successBg),
          'warning/bg': (c.warning, c.warningBg),
          'danger/bg': (c.danger, c.dangerBg),
          'info/bg': (c.info, c.infoBg),
        };

    test('testo: tutte le coppie light >= 4.5:1', () {
      for (final entry in textPairs(light, lightColors).entries) {
        final ratio = contrastRatio(entry.value.$1, entry.value.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} = ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('testo: tutte le coppie dark >= 4.5:1', () {
      for (final entry in textPairs(dark, darkColors).entries) {
        final ratio = contrastRatio(entry.value.$1, entry.value.$2);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key} = ${ratio.toStringAsFixed(2)}:1',
        );
      }
    });

    test('bordi controlli: outline >= 3:1 su superficie (light e dark)', () {
      expect(
        contrastRatio(light.colorScheme.outline, light.colorScheme.surface),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrastRatio(dark.colorScheme.outline, dark.colorScheme.surface),
        greaterThanOrEqualTo(3.0),
      );
    });

    test('warning non usato come testo su fondo chiaro debole', () {
      // Il warning light (B45309) deve reggere come testo su sfondo chiaro.
      expect(
        contrastRatio(lightColors.warning, lightColors.warningBg),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(lightColors.warning, Colors.white),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('snackbar: onInverseSurface su inverseSurface >= 4.5:1', () {
      for (final theme in [light, dark]) {
        final snack = theme.snackBarTheme;
        final bg = snack.backgroundColor!;
        final fg = snack.contentTextStyle!.color!;
        expect(contrastRatio(fg, bg), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('HaccpColors.lerp', () {
    test('lerp(a, b, 1) == b per ogni campo', () {
      const a = AppTheme.lightColors;
      const b = AppTheme.darkColors;
      final result = a.lerp(b, 1.0);

      expect(result.warning.toARGB32(), b.warning.toARGB32(),
          reason: 'campo warning (bug storico del lerp)');
      expect(result.warningBg.toARGB32(), b.warningBg.toARGB32());
      expect(result.warningStripe.toARGB32(), b.warningStripe.toARGB32());
      expect(result.success.toARGB32(), b.success.toARGB32());
      expect(result.successBg.toARGB32(), b.successBg.toARGB32());
      expect(result.danger.toARGB32(), b.danger.toARGB32());
      expect(result.dangerBg.toARGB32(), b.dangerBg.toARGB32());
      expect(result.info.toARGB32(), b.info.toARGB32());
      expect(result.infoBg.toARGB32(), b.infoBg.toARGB32());
      expect(result.onHero.toARGB32(), b.onHero.toARGB32());
      expect(result.heroStart.toARGB32(), b.heroStart.toARGB32());
      expect(result.heroEnd.toARGB32(), b.heroEnd.toARGB32());
    });

    test('lerp(a, b, 0) == a', () {
      const a = AppTheme.lightColors;
      const b = AppTheme.darkColors;
      final result = a.lerp(b, 0.0);
      expect(result.warning.toARGB32(), a.warning.toARGB32());
      expect(result.danger.toARGB32(), a.danger.toARGB32());
    });

    test('copyWith modifica solo il campo richiesto', () {
      const a = AppTheme.lightColors;
      final changed = a.copyWith(warning: const Color(0xFF123456));
      expect(changed.warning.toARGB32(), 0xFF123456);
      expect(changed.warningBg.toARGB32(), a.warningBg.toARGB32());
      expect(changed.danger.toARGB32(), a.danger.toARGB32());
    });
  });

  group('FeatureScaffold', () {
    testWidgets('ha AppBar con titolo e sfondo opaco del tema', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const FeatureScaffold(
            title: 'Temperature',
            body: Text('Contenuto'),
          ),
        ),
      );

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(
        scaffold.backgroundColor,
        AppTheme.light().scaffoldBackgroundColor,
        reason: 'lo sfondo deve venire dal tema, mai trasparente',
      );
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Temperature'), findsOneWidget);
      // Freccia indietro automatica: nessuna route sottostante => assente,
      // ma il back button appears quando spinta. Verifichiamo con push.
    });

    testWidgets('mostra la freccia indietro quando spinta', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FeatureScaffold(
                    title: 'Pulizie',
                    body: SizedBox(),
                  ),
                ),
              ),
              child: const Text('apri'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();

      expect(find.byType(BackButton), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
    });
  });
}
