import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/money.dart';

void main() {
  group('Money.tryParseToCentimes', () {
    test('accepts plain, decimal, grouped and currency input', () {
      expect(Money.tryParseToCentimes('12'), 1200);
      expect(Money.tryParseToCentimes('12,5'), 1250);
      expect(Money.tryParseToCentimes('12.50'), 1250);
      expect(Money.tryParseToCentimes('1 234,56'), 123456);
      expect(Money.tryParseToCentimes('12,50 DH'), 1250);
      expect(Money.tryParseToCentimes('8 DHS'), 800);
      expect(Money.tryParseToCentimes('9 mad'), 900);
      expect(Money.tryParseToCentimes('1\u00A0234,56'), 123456);
    });

    test('handles Arabic separators', () {
      expect(Money.tryParseToCentimes('12\u066B50'), 1250);
      expect(Money.tryParseToCentimes('1\u066C234'), 123400);
    });

    test('rounds sub-centime fractions half-up', () {
      expect(Money.tryParseToCentimes('0.004'), 0);
      expect(Money.tryParseToCentimes('0.005'), 1);
      expect(Money.tryParseToCentimes('0.0099'), 1);
    });

    test('rejects invalid input', () {
      expect(Money.tryParseToCentimes(''), isNull);
      expect(Money.tryParseToCentimes('abc'), isNull);
      expect(Money.tryParseToCentimes('12,3,4'), isNull);
      expect(Money.tryParseToCentimes('12 DH 5'), isNull);
      expect(Money.tryParseToCentimes('1e3'), isNull);
    });

    test('tryParsePositive rejects negatives', () {
      expect(Money.tryParsePositive('-2'), isNull);
      expect(Money.tryParsePositive('0'), 0);
      expect(Money.tryParsePositive('2.25'), 225);
    });
  });

  group('Money.format', () {
    test('uses non-breaking grouping and a comma decimal', () {
      expect(Money.format(0), '0,00');
      expect(Money.format(5), '0,05');
      expect(Money.format(1250), '12,50');
      expect(Money.format(123456), '1\u00A0234,56');
      expect(Money.format(100000000), '1\u00A0000\u00A0000,00');
    });

    test('formats negative amounts', () {
      expect(Money.format(-1250), '-12,50');
    });

    test('appends the currency symbol when requested', () {
      expect(Money.withCurrency(1250, 'DH'), '12,50 DH');
    });
  });

  group('Money.lineTotal', () {
    test('is exact for whole and fractional quantities', () {
      expect(Money.lineTotal(qtyMilli: 1000, unitPriceCentimes: 800), 800);
      expect(Money.lineTotal(qtyMilli: 500, unitPriceCentimes: 1250), 625);
      expect(Money.lineTotal(qtyMilli: 1500, unitPriceCentimes: 333), 500);
    });

    test('rounds half-up without floating point drift', () {
      // 1 milli-unit at 500 centimes = 0.5 centime -> 1 centime.
      expect(Money.lineTotal(qtyMilli: 1, unitPriceCentimes: 500), 1);
      // 1 milli-unit at 499 centimes = 0.499 centime -> 0 centime.
      expect(Money.lineTotal(qtyMilli: 1, unitPriceCentimes: 499), 0);
    });

    test('returns zero for empty or zero quantities', () {
      expect(Money.lineTotal(qtyMilli: 0, unitPriceCentimes: 800), 0);
      expect(Money.lineTotal(qtyMilli: -1000, unitPriceCentimes: 800), 0);
      expect(Money.lineTotal(qtyMilli: 1000, unitPriceCentimes: 0), 0);
    });

    test('keeps the sign for negative unit prices', () {
      expect(Money.lineTotal(qtyMilli: 1000, unitPriceCentimes: -800), -800);
    });
  });
}
