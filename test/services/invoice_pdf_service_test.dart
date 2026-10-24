import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/services/invoice_pdf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shop = Shop(
    name: 'Épicerie Hydra',
    nameAr: 'بقالة هيدرا',
    address: '12 rue Atlas, Casablanca',
    phone: '0522000000',
    footer: 'Merci de votre visite',
  );

  Sale sale() => Sale(
    invoiceNo: 'V-2026-000001',
    customerName: 'Ahmed',
    subtotalCentimes: 1700,
    discountCentimes: 0,
    totalCentimes: 1700,
    paidCentimes: 2000,
    dueCentimes: 0,
    paymentMethod: 'cash',
    businessDate: '2026-10-23',
    createdAt: DateTime(2026, 10, 23, 10, 30).millisecondsSinceEpoch,
    lines: const [
      SaleLine(
        productName: 'حليب سنترال 1 لتر',
        qtyMilli: 2000,
        unitPriceCentimes: 850,
        unitCostCentimes: 720,
        lineTotalCentimes: 1700,
      ),
    ],
  );

  test('generates a valid French A4 invoice PDF', () async {
    final service = InvoicePdfService();
    final bytes = await service.saleDocument(
      sale: sale(),
      shop: shop,
      arabic: false,
    );

    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('generates an Arabic receipt PDF from the bundled font', () async {
    final service = InvoicePdfService();
    final bytes = await service.saleDocument(
      sale: sale(),
      shop: shop,
      arabic: true,
      receipt: true,
      paperWidthMm: 58,
    );

    expect(bytes.length, greaterThan(2000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
