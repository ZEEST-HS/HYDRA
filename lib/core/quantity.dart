/// Quantities are stored as integer thousandths of the product's base unit.
/// 1 piece = 1000; 0,5 kg = 500; 1 carton of 12 = 12000.
class Qty {
  Qty._();

  static const int milliPerUnit = 1000;

  static int? tryParse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(' ', '')
        .replaceAll('\u066B', '.')
        .replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,6})?$').hasMatch(s)) return null;
    final parts = s.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    var milli = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      final digits = parts[1].padRight(6, '0').substring(0, 6);
      milli = int.parse(digits);
      milli = (milli + 500) ~/ 1000;
    }
    return whole * milliPerUnit + milli;
  }

  /// Converts a quantity expressed in packages to base milli-units.
  static int packagesToBaseMilli(int packages, int factorMilli) =>
      packages * factorMilli;

  static int baseToPackages(int baseMilli, int factorMilli) =>
      factorMilli <= 0 ? 0 : baseMilli ~/ factorMilli;

  static String format(int milli, {int maxDecimals = 3}) {
    final negative = milli < 0;
    final abs = milli.abs();
    var whole = abs ~/ milliPerUnit;
    var rest = abs % milliPerUnit;
    var text = whole.toString();
    if (rest > 0 && maxDecimals > 0) {
      var decimals = rest.toString().padLeft(3, '0');
      if (maxDecimals < 3) decimals = decimals.substring(0, maxDecimals);
      while (decimals.endsWith('0')) {
        decimals = decimals.substring(0, decimals.length - 1);
      }
      if (decimals.isNotEmpty) text = '$text,$decimals';
    }
    return negative ? '-$text' : text;
  }

  static String formatWithUnit(int milli, String unitLabel) =>
      '${format(milli)} $unitLabel';

  /// Multiplies a base quantity by a package factor, rounding to the nearest
  /// milli-unit. Used when the user enters a decimal package count.
  static int multiply(int baseMilli, int factorMilli) =>
      ((baseMilli * factorMilli) + 500) ~/ 1000;
}
