import 'package:flutter/material.dart';

/// Central palette and theme factory.
///
/// Brand colours are exposed as brightness-aware getters instead of fixed
/// constants so that every existing `AppTheme.danger` / `success` / `primary`
/// usage keeps enough contrast when the dark theme is active. The active
/// brightness is synchronised by the `MaterialApp.builder` in `app.dart`
/// before any screen builds.
class AppTheme {
  AppTheme._();

  // Light palette.
  static const Color _primaryLight = Color(0xFF115E59);
  static const Color _accentLight = Color(0xFFD97706);
  static const Color _successLight = Color(0xFF166534);
  static const Color _dangerLight = Color(0xFFB91C1C);
  static const Color background = Color(0xFFF5F7F8);

  // Dark palette: lighter tones that stay readable on the near-black surface.
  static const Color _primaryDark = Color(0xFF5EEAD4);
  static const Color _accentDark = Color(0xFFFBBF24);
  static const Color _successDark = Color(0xFF4ADE80);
  static const Color _dangerDark = Color(0xFFF87171);

  static Brightness _brightness = Brightness.light;

  /// Called from the app builders whenever the applied theme changes.
  static void syncBrightness(Brightness brightness) {
    _brightness = brightness;
  }

  static bool get _isDark => _brightness == Brightness.dark;

  static Color get primary => _isDark ? _primaryDark : _primaryLight;
  static Color get accent => _isDark ? _accentDark : _accentLight;
  static Color get success => _isDark ? _successDark : _successLight;
  static Color get danger => _isDark ? _dangerDark : _dangerLight;

  // Extra accents used by dashboards, charts and shortcut tiles.
  static Color get info =>
      _isDark ? const Color(0xFF60A5FA) : const Color(0xFF0369A1);
  static Color get violet =>
      _isDark ? const Color(0xFFC4B5FD) : const Color(0xFF7C3AED);
  static Color get brown =>
      _isDark ? const Color(0xFFFCD34D) : const Color(0xFFB45309);
  static Color get rose =>
      _isDark ? const Color(0xFFFB7185) : const Color(0xFFBE123C);
  static Color get slate =>
      _isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _primaryLight,
          brightness: Brightness.light,
        ).copyWith(
          secondary: _accentLight,
          error: _dangerLight,
          surface: Colors.white,
        );
    return _base(scheme, background);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: _primaryLight,
      brightness: Brightness.dark,
    ).copyWith(secondary: _accentDark, error: _dangerDark);
    return _base(scheme, const Color(0xFF101615));
  }

  static ThemeData _base(ColorScheme scheme, Color scaffold) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outlineVariant),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scaffold,
      fontFamily: 'NotoSans',
      fontFamilyFallback: const ['NotoSansArabic'],
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        isDense: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 44)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
      ),
    );
  }

  static const TextStyle numberStyle = TextStyle(
    fontFeatures: [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w600,
  );
}
