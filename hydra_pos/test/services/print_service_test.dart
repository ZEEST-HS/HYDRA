import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/services/print_service.dart';

void main() {
  group('EscPosBuilder.ascii', () {
    test('removes French accents and ligatures', () {
      expect(EscPosBuilder.ascii('Épicerie française'), 'Epicerie francaise');
      expect(EscPosBuilder.ascii('Cœur à l\'hôtel'), 'Coeur a l\'hotel');
      expect(EscPosBuilder.ascii('Æther œuvre'), 'AEther oeuvre');
      expect(EscPosBuilder.ascii('25 °C'), '25 oC');
    });

    test('replaces Arabic and unsupported characters with ?', () {
      final result = EscPosBuilder.ascii('حليب 1L');
      expect(result.codeUnits.every((c) => c >= 32 && c <= 126), isTrue);
      expect(result, contains('?'));
      expect(result, endsWith('1L'));
    });

    test('keeps printable ASCII intact', () {
      expect(EscPosBuilder.ascii('Lait 1L - 8.50 DH'), 'Lait 1L - 8.50 DH');
    });
  });

  group('EscPosBuilder.sale', () {
    const shop = Shop(
      name: 'Boutique Al Amal',
      phone: '0522000000',
      address: 'Rue 12, Casablanca',
      footer: 'Merci de votre visite',
    );

    final sale = Sale(
      id: 1,
      invoiceNo: 'V-2026-00001',
      customerName: 'Ahmed',
      subtotalCentimes: 2100,
      discountCentimes: 100,
      totalCentimes: 2000,
      paidCentimes: 1500,
      dueCentimes: 500,
      paymentMethod: 'cash',
      businessDate: '2026-10-23',
      createdAt: DateTime(2026, 10, 23, 14, 30).millisecondsSinceEpoch,
      lines: const [
        SaleLine(
          productName: 'Lait Centrale 1L',
          unitName: 'Carton',
          factorMilli: 12000,
          qtyMilli: 24000,
          unitPriceCentimes: 950,
          unitCostCentimes: 800,
          lineTotalCentimes: 1900,
        ),
        SaleLine(
          productName: 'Pain',
          qtyMilli: 1000,
          unitPriceCentimes: 200,
          unitCostCentimes: 100,
          lineTotalCentimes: 200,
        ),
      ],
    );

    test('emits init, content, totals and cut commands', () {
      final bytes = EscPosBuilder(width: 32).sale(sale, shop);
      final text = latin1.decode(bytes.where((b) => b <= 126).toList());

      expect(bytes.sublist(0, 2), [0x1B, 0x40], reason: 'ESC @ init');
      expect(bytes.sublist(bytes.length - 4), [0x1D, 0x56, 0x42, 0x00]);
      expect(text, contains('Boutique Al Amal'));
      expect(text, contains('V-2026-00001'));
      expect(text, contains('Ahmed'));
      expect(text, contains('Lait Centrale 1L'));
      expect(text, contains('Carton'));
      expect(text, contains('TOTAL'));
      expect(text, contains('2,00'));
      expect(text, contains('Reste'));
      expect(text, contains('Merci de votre visite'));
      expect(text, contains('Hydra POS'));
    });

    test('never writes bytes outside the printer-safe ASCII range', () {
      final bytes = EscPosBuilder(width: 32).sale(sale, shop);

      expect(bytes, isNotEmpty);
      expect(bytes.every((b) => b >= 0 && b <= 126), isTrue);
    });

    test('respects 80 mm paper width', () {
      final narrow = EscPosBuilder(width: 32).test();
      final wide = EscPosBuilder(width: 48).test();

      expect(narrow, isNotEmpty);
      expect(wide, isNotEmpty);
      expect(wide.sublist(0, 2), [0x1B, 0x40]);
      expect(latin1.decode(wide), contains('HYDRA POS'));
    });

    test('prints a readable placeholder for Arabic-only names', () {
      final arabicSale = Sale(
        id: 2,
        invoiceNo: 'V-1',
        subtotalCentimes: 500,
        discountCentimes: 0,
        totalCentimes: 500,
        paidCentimes: 500,
        dueCentimes: 0,
        paymentMethod: 'cash',
        businessDate: '2026-10-23',
        createdAt: DateTime(2026, 10, 23).millisecondsSinceEpoch,
        lines: const [
          SaleLine(
            productName: 'خبز',
            qtyMilli: 1000,
            unitPriceCentimes: 500,
            unitCostCentimes: 0,
            lineTotalCentimes: 500,
          ),
        ],
      );

      final bytes = EscPosBuilder(width: 32).sale(arabicSale, shop);
      final text = latin1.decode(bytes.where((b) => b <= 126).toList());
      expect(text, contains('?'));
      expect(bytes.every((b) => b <= 126), isTrue);
    });
  });

  group('EscPosBuilder command helpers', () {
    test('expose standard ESC/POS control sequences', () {
      expect(EscPosBuilder.init(), [0x1B, 0x40]);
      expect(EscPosBuilder.align(1), [0x1B, 0x61, 1]);
      expect(EscPosBuilder.cut(), [0x1D, 0x56, 0x42, 0x00]);
      expect(EscPosBuilder.feed(3), [0x1B, 0x64, 3]);
      expect(EscPosBuilder.doubleSize(), [0x1D, 0x21, 0x11]);
      expect(EscPosBuilder.normalSize(), [0x1D, 0x21, 0x00]);
    });
  });
}
