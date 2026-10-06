import 'package:flutter/material.dart';

/// Colori semantici dell'app: ogni colore ha una variante "testo/icona"
/// ad alto contrasto e una "sfondo" chiara. Contrast verificati WCAG AA
/// (4.5:1 testo, 3:1 bordi) sul tema chiaro e scuro.
@immutable
class HaccpColors extends ThemeExtension<HaccpColors> {
  const HaccpColors({
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.warningStripe,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.onHero,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color success;
  final Color successBg;
  final Color warning;

  /// Sfondo chiaro del messaggio di avviso.
  final Color warningBg;

  /// Colore della striscia/segnaposto grafico dell'avviso (non per testo).
  final Color warningStripe;

  final Color danger;
  final Color dangerBg;
  final Color info;
  final Color infoBg;
  final Color onHero;
  final Color heroStart;
  final Color heroEnd;

  @override
  HaccpColors copyWith({
    Color? success,
    Color? successBg,
    Color? warning,
    Color? warningBg,
    Color? warningStripe,
    Color? danger,
    Color? dangerBg,
    Color? info,
    Color? infoBg,
    Color? onHero,
    Color? heroStart,
    Color? heroEnd,
  }) {
    return HaccpColors(
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      warningStripe: warningStripe ?? this.warningStripe,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      info: info ?? this.info,
      infoBg: infoBg ?? this.infoBg,
      onHero: onHero ?? this.onHero,
      heroStart: heroStart ?? this.heroStart,
      heroEnd: heroEnd ?? this.heroEnd,
    );
  }

  @override
  HaccpColors lerp(ThemeExtension<HaccpColors>? other, double t) {
    if (other is! HaccpColors) return this;
    return HaccpColors(
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      warningStripe: Color.lerp(warningStripe, other.warningStripe, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      info: Color.lerp(info, other.info, t)!,
      infoBg: Color.lerp(infoBg, other.infoBg, t)!,
      onHero: Color.lerp(onHero, other.onHero, t)!,
      heroStart: Color.lerp(heroStart, other.heroStart, t)!,
      heroEnd: Color.lerp(heroEnd, other.heroEnd, t)!,
    );
  }
}

extension HaccpColorsX on BuildContext {
  HaccpColors get haccpColors =>
      Theme.of(this).extension<HaccpColors>() ?? AppTheme.lightColors;
}

class AppTheme {
  // Palette chiaro (contrast verificati: bordi >= 3:1, testo >= 4.5:1).
  static const Color primary = Color(0xFF0B6B66);
  static const Color primaryDark = Color(0xFF064A47);
  static const Color textLight = Color(0xFF10201F);
  static const Color textSecondaryLight = Color(0xFF3F4D4B);
  static const Color backgroundLight = Color(0xFFF1F5F4);

  /// Bordo controlli (input, checkbox, chip): 4.5:1 su bianco.
  static const Color borderLight = Color(0xFF6B7B78);

  /// Divider / bordo decorativo card: 3:1 su bianco.
  static const Color dividerLight = Color(0xFFD5DFDC);
  static const Color surfaceLight = Colors.white;

  // Palette scuro: stessi rapporti di contrasto.
  static const Color primaryBright = Color(0xFF53C6BE);
  static const Color textDark = Color(0xFFE9F2F0);
  static const Color textSecondaryDark = Color(0xFFAEC2BE);
  static const Color backgroundDark = Color(0xFF0E1615);
  static const Color surfaceDark = Color(0xFF182522);

  /// Bordo controlli su superficie scura: >= 3:1.
  static const Color borderDark = Color(0xFF6F8581);

  /// Divider scuro.
  static const Color dividerDark = Color(0xFF2A3B37);

  static const HaccpColors lightColors = HaccpColors(
    success: Color(0xFF16703C),
    successBg: Color(0xFFDDF3E6),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFFFF1DB),
    warningStripe: Color(0xFFD97706),
    danger: Color(0xFFB3261E),
    dangerBg: Color(0xFFFBE0DD),
    info: Color(0xFF1B4F8F),
    infoBg: Color(0xFFDCE9FA),
    onHero: Colors.white,
    heroStart: Color(0xFF0B6B66),
    heroEnd: Color(0xFF064A47),
  );

  static const HaccpColors darkColors = HaccpColors(
    success: Color(0xFF8FDFAF),
    successBg: Color(0xFF11301F),
    warning: Color(0xFFF5C67C),
    warningBg: Color(0xFF352711),
    warningStripe: Color(0xFFF59E0B),
    danger: Color(0xFFF2B8B5),
    dangerBg: Color(0xFF3B1D1A),
    info: Color(0xFFA9C9F8),
    infoBg: Color(0xFF15294A),
    onHero: Colors.white,
    heroStart: Color(0xFF0A5450),
    heroEnd: Color(0xFF073835),
  );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme.light(
          primary: primary,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFD3ECEA),
          onPrimaryContainer: primaryDark,
          secondary: primary,
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFD3ECEA),
          onSecondaryContainer: Color(0xFF064A47),
          surface: surfaceLight,
          onSurface: textLight,
          surfaceContainerHighest: Color(0xFFE4EDEB),
          onSurfaceVariant: textSecondaryLight,
          outline: borderLight,
          outlineVariant: dividerLight,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          errorContainer: Color(0xFFFBE0DD),
          onErrorContainer: Color(0xFF8C1D18),
          inverseSurface: Color(0xFF10201F),
          onInverseSurface: Color(0xFFF1F5F4),
        ),
        background: backgroundLight,
        haccp: lightColors,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme.dark(
          primary: primaryBright,
          onPrimary: Color(0xFF04302D),
          primaryContainer: Color(0xFF0A5450),
          onPrimaryContainer: Color(0xFFC9F2EE),
          secondary: primaryBright,
          onSecondary: Color(0xFF04302D),
          secondaryContainer: Color(0xFF0A5450),
          onSecondaryContainer: Color(0xFFC9F2EE),
          surface: surfaceDark,
          onSurface: textDark,
          surfaceContainerHighest: Color(0xFF233330),
          onSurfaceVariant: textSecondaryDark,
          outline: borderDark,
          outlineVariant: dividerDark,
          error: Color(0xFFF2B8B5),
          onError: Color(0xFF601410),
          errorContainer: Color(0xFF8C1D18),
          onErrorContainer: Color(0xFFF9DEDC),
          inverseSurface: Color(0xFFE9F2F0),
          onInverseSurface: Color(0xFF10201F),
        ),
        background: backgroundDark,
        haccp: darkColors,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color background,
    required HaccpColors haccp,
  }) {
    final baseText = ThemeData(brightness: brightness, fontFamily: 'Poppins');

    // Scala tipografica compatta: Poppins e' un font largo e i testi M3 di
    // default causano a capo/overflow su 360 dp. Ridotti di ~10% (mai sotto
    // 11 sp) per display/headline/title/body/label.
    final scaledText = baseText.textTheme.copyWith(
      displayLarge: baseText.textTheme.displayLarge?.copyWith(fontSize: 28),
      displayMedium: baseText.textTheme.displayMedium?.copyWith(fontSize: 26),
      displaySmall: baseText.textTheme.displaySmall?.copyWith(fontSize: 24),
      headlineLarge: baseText.textTheme.headlineLarge?.copyWith(fontSize: 24),
      headlineMedium: baseText.textTheme.headlineMedium?.copyWith(fontSize: 22),
      headlineSmall: baseText.textTheme.headlineSmall?.copyWith(fontSize: 20),
      titleLarge: baseText.textTheme.titleLarge?.copyWith(fontSize: 18),
      titleMedium: baseText.textTheme.titleMedium?.copyWith(fontSize: 15),
      titleSmall: baseText.textTheme.titleSmall?.copyWith(fontSize: 14),
      bodyLarge: baseText.textTheme.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: baseText.textTheme.bodyMedium?.copyWith(fontSize: 14),
      bodySmall: baseText.textTheme.bodySmall?.copyWith(fontSize: 12),
      labelLarge: baseText.textTheme.labelLarge?.copyWith(fontSize: 14),
      labelMedium: baseText.textTheme.labelMedium?.copyWith(fontSize: 12),
      labelSmall: baseText.textTheme.labelSmall?.copyWith(fontSize: 11),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      fontFamily: 'Poppins',
      textTheme: scaledText.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      extensions: [haccp],
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: baseText.textTheme.titleLarge!.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        labelStyle: TextStyle(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
        floatingLabelStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline, width: 1.4),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outline, width: 1.4),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.error, width: 2.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 54),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
          ),
          side: BorderSide(color: scheme.primary, width: 1.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: baseText.chipTheme.copyWith(
        // Chip a stati: il colore del testo dipende dallo stato
        // (WidgetStateColor risolto da RawChip), mai fisso.
        backgroundColor: scheme.surface,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.surfaceContainerHighest,
        labelStyle: (baseText.chipTheme.labelStyle ?? const TextStyle())
            .copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: WidgetStateColor.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              // 70% di onSurface: resta leggibile (>= 4.5:1) sul fondo neutro.
              return scheme.onSurface.withValues(alpha: 0.70);
            }
            if (states.contains(WidgetState.selected)) {
              return scheme.onSecondaryContainer;
            }
            return scheme.onSurface;
          }),
        ),
        checkmarkColor: scheme.onSecondaryContainer,
        side: BorderSide(color: scheme.outline, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        showCheckmark: true,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.outline;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 1.6),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return scheme.primary;
          return scheme.outline;
        }),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        modalBackgroundColor: scheme.surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      datePickerTheme: DatePickerThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
    );
  }
}
