/// Monetary values are stored as integer centimes (1 DH = 100 centimes).
/// Never use doubles for money.
class Money {
  Money._();

  static const int centimesPerDirham = 100;

  /// A single number followed by an optional currency suffix. This rejects
  /// stray numbers such as `12 DH 5` instead of silently concatenating them.
  static final RegExp _validRaw = RegExp(
    r'''^\s*[-+]?\s*\d[\d\s\u00A0\u202F.,_'\u066B\u066C]*\s*(?:dh|dhs|mad|dirhams?|d\.?m\.?)?\s*$''',
    caseSensitive: false,
  );

  /// Parses user input such as `12`, `12,5`, `1 234,56`, `12.50 DH`.
  /// Returns null when the input is not a valid non-negative amount.
  static int? tryParseToCentimes(String raw) {
    var s = raw.trim();
    if (s.isEmpty || !_validRaw.hasMatch(s)) return null;
    // Remove currency words/symbols and grouping spaces.
    s = s
        .replaceAll(
          RegExp(r'\b(dh|dhs|mad|dirhams?|d\.?m\.?)\b', caseSensitive: false),
          '',
        )
        .replaceAll('\u00A0', '')
        .replaceAll('\u202F', '')
        .replaceAll(' ', '')
        .replaceAll('_', '')
        .replaceAll("'", '');
    // Arabic decimal separator and thousands separator.
    s = s.replaceAll('\u066C', '').replaceAll('\u066B', '.');
    if (s.isEmpty) return null;
    final negative = s.startsWith('-');
    if (negative || s.startsWith('+')) s = s.substring(1);
    s = s.replaceAll(',', '.');
    if (!RegExp(r'^\d+(\.\d{0,4})?$').hasMatch(s)) return null;
    final parts = s.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    var frac = 0;
    if (parts.length > 1 && parts[1].isNotEmpty) {
      final digits = parts[1].padRight(4, '0').substring(0, 4);
      frac = int.parse(digits);
      // Round half-up from 1/10000 to centimes.
      frac = (frac + 50) ~/ 100;
    }
    final value = whole * centimesPerDirham + frac;
    return negative ? -value : value;
  }

  /// Parses an amount for calculations. Rejects negative values.
  static int? tryParsePositive(String raw) {
    final v = tryParseToCentimes(raw);
    return (v == null || v < 0) ? null : v;
  }

  /// Formats centimes for display using French/Moroccan conventions:
  /// `1 234,50`. The currency symbol is added by the localization layer.
  static String format(
    int centimes, {
    bool withSymbol = false,
    String symbol = 'DH',
  }) {
    final negative = centimes < 0;
    final abs = centimes.abs();
    final whole = abs ~/ 100;
    final frac = abs % 100;
    final groups = <String>[];
    var rest = whole;
    do {
      final chunk = rest % 1000;
      rest ~/= 1000;
      groups.insert(
        0,
        rest > 0 ? chunk.toString().padLeft(3, '0') : chunk.toString(),
      );
    } while (rest > 0);
    final text = '${groups.join('\u00A0')},${frac.toString().padLeft(2, '0')}';
    final signed = negative ? '-$text' : text;
    return withSymbol ? '$signed $symbol' : signed;
  }

  /// Compact display for cards: 12,50 DH.
  static String withCurrency(int centimes, String symbol) =>
      format(centimes, withSymbol: true, symbol: symbol);

  /// Exact multiplication of a base-unit quantity (milli-units) by a
  /// centimes-per-base-unit price. Rounds half-up to the nearest centime.
  static int lineTotal({
    required int qtyMilli,
    required int unitPriceCentimes,
  }) {
    if (qtyMilli <= 0 || unitPriceCentimes == 0) return 0;
    final numerator = qtyMilli * unitPriceCentimes;
    final sign = numerator < 0 ? -1 : 1;
    return sign * ((numerator.abs() + 500) ~/ 1000);
  }
}
