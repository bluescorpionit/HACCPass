import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:haccpass/core/theme/app_theme.dart';

void main() {
  test('il design system definisce tema chiaro e scuro', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
    expect(AppTheme.light().extension<HaccpColors>(), isNotNull);
    expect(AppTheme.dark().extension<HaccpColors>(), isNotNull);
  });

  testWidgets('sanity check: i colori semantici rispettano le coppie', (
    tester,
  ) async {
    final light = AppTheme.lightColors;
    expect(light.successBg, isNot(light.success));
    expect(light.dangerBg, isNot(light.danger));
  });
}
