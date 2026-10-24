import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/quantity.dart';

void main() {
  group('Qty.tryParse', () {
    test('parses integers, decimals and spaces', () {
      expect(Qty.tryParse('1'), 1000);
      expect(Qty.tryParse('0,5'), 500);
      expect(Qty.tryParse('1.25'), 1250);
      expect(Qty.tryParse('1\u00A0234'), 1234000);
      expect(Qty.tryParse('0,001'), 1);
    });

    test('rounds to the nearest milli-unit', () {
      expect(Qty.tryParse('0,0004'), 0);
      expect(Qty.tryParse('0,0005'), 1);
      expect(Qty.tryParse('0,0009'), 1);
    });

    test('rejects invalid quantities', () {
      expect(Qty.tryParse(''), isNull);
      expect(Qty.tryParse('-1'), isNull);
      expect(Qty.tryParse('un'), isNull);
      expect(Qty.tryParse('1,2,3'), isNull);
    });
  });

  group('Qty.format', () {
    test('drops trailing zeros and trims decimals', () {
      expect(Qty.format(0), '0');
      expect(Qty.format(1000), '1');
      expect(Qty.format(1500), '1,5');
      expect(Qty.format(1250), '1,25');
      expect(Qty.format(1), '0,001');
      expect(Qty.format(-1500), '-1,5');
      expect(Qty.format(1999, maxDecimals: 2), '1,99');
    });

    test('formats with a unit label', () {
      expect(Qty.formatWithUnit(1500, 'kg'), '1,5 kg');
    });
  });

  group('packaging conversions', () {
    test('packagesToBaseMilli multiplies by the package factor', () {
      expect(Qty.packagesToBaseMilli(3, 12000), 36000);
    });

    test('baseToPackages floors incomplete packages', () {
      expect(Qty.baseToPackages(36000, 12000), 3);
      expect(Qty.baseToPackages(35000, 12000), 2);
      expect(Qty.baseToPackages(1000, 0), 0);
    });

    test('multiply rounds decimal package counts', () {
      expect(Qty.multiply(1000, 12000), 12000);
      expect(Qty.multiply(500, 12000), 6000);
    });
  });
}
