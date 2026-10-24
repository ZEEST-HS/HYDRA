import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/ui/theme.dart';

/// WCAG 2.1 relative luminance for an opaque colour channel.
double _luminance(Color color) {
  double channel(double value) {
    return value <= 0.03928
        ? value / 12.92
        : ((value + 0.055) / 1.055) * ((value + 0.055) / 1.055);
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color foreground, Color background) {
  final a = _luminance(foreground);
  final b = _luminance(background);
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  tearDown(() => AppTheme.syncBrightness(Brightness.light));

  test('every dark semantic colour reaches AA text contrast', () {
    AppTheme.syncBrightness(Brightness.dark);
    const surface = Color(0xFF101615);
    final colors = <String, Color>{
      'primary': AppTheme.primary,
      'accent': AppTheme.accent,
      'success': AppTheme.success,
      'danger': AppTheme.danger,
      'info': AppTheme.info,
      'violet': AppTheme.violet,
      'brown': AppTheme.brown,
      'rose': AppTheme.rose,
      'slate': AppTheme.slate,
    };
    for (final entry in colors.entries) {
      expect(
        _contrast(entry.value, surface),
        greaterThanOrEqualTo(4.5),
        reason: '${entry.key} on the dark scaffold',
      );
    }
  });

  test('light semantic colours stay readable on white cards', () {
    AppTheme.syncBrightness(Brightness.light);
    for (final color in [AppTheme.primary, AppTheme.success, AppTheme.danger]) {
      expect(
        _contrast(color, const Color(0xFFFFFFFF)),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('switching brightness changes the active palette', () {
    AppTheme.syncBrightness(Brightness.light);
    final lightDanger = AppTheme.danger;
    AppTheme.syncBrightness(Brightness.dark);
    expect(AppTheme.danger, isNot(lightDanger));
    expect(AppTheme.danger, const Color(0xFFF87171));
  });
}
