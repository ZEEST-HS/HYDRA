import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/data/repositories/expense_repository.dart';
import 'package:hydra_pos/domain/cash/cash_service.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';
import 'package:hydra_pos/domain/sales/return_service.dart';
import 'package:hydra_pos/domain/sales/sale_service.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late CashService cash;

  setUp(() async {
    env = await TestEnv.memory();
    cash = CashService(env.db);
  });

  tearDown(() async {
    await env.close();
  });

  Future<Product> seedProduct() async {
    final created = await env.products.create(
      const Product(
        name: 'Café Dubois',
        barcode: '6111245100080',
        priceCentimes: 1000,
        costCentimes: 500,
        stockMilli: 20000,
        baseUnit: 'piece',
      ),
    );
    return (await env.products.findById(created.id))!;
  }

  test('breakdown only counts real cash movements', () async {
    final product = await seedProduct();
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Hamid'),
    );
    final sessionId = await cash.open(openingCashCentimes: 10000);
    expect(sessionId, greaterThan(0));

    // Cash sale: 10.00 DH collected at the counter.
    final cashSale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 1000,
            unitPriceCentimes: 1000,
          ),
        ],
        paidCentimes: 1000,
        paymentMethod: 'cash',
        idempotencyKey: 'cash-sale',
      ),
    );

    // Credit sale: no cash at confirmation.
    final creditSale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 1000,
            unitPriceCentimes: 1000,
          ),
        ],
        customerId: customerId,
        paidCentimes: 0,
        paymentMethod: 'cash',
        idempotencyKey: 'credit-sale',
      ),
    );
    expect(creditSale.paymentMethod, 'credit');

    // Later cash payment of 4.00 DH against the credit sale.
    await env.sales.addPayment(
      saleId: creditSale.id,
      amountCentimes: 400,
      method: 'cash',
    );

    // Cash and card expenses.
    final expenses = ExpenseRepository(env.db);
    await expenses.create(
      category: 'Transport',
      amountCentimes: 300,
      method: 'cash',
    );
    await expenses.create(
      category: 'Loyer',
      amountCentimes: 50000,
      method: 'card',
    );

    // Fully paid cash purchase: money leaves the drawer.
    final supplierId = await env.parties.createSupplier(
      const Supplier(name: 'Fournisseur Cash'),
    );
    await env.purchases.completePurchase(
      PurchaseDraft(
        supplierId: supplierId,
        lines: [
          PurchaseDraftLine(
            product: product,
            qtyMilli: 1000,
            unitCostCentimes: 600,
          ),
        ],
        paidCentimes: 600,
        paymentMethod: 'cash',
      ),
    );

    // Cash refund of 2.00 DH.
    await env.returns.returnSale(
      saleId: cashSale.id,
      lines: [
        ReturnDraftLine(saleLineId: cashSale.lines.single.id, qtyMilli: 200),
      ],
      refundMethod: 'cash',
    );

    final session = (await cash.openSession())!;
    final breakdown = await cash.breakdown(session);

    expect(breakdown.openingCash, 10000);
    expect(breakdown.cashSales, 1000);
    expect(breakdown.customerPayments, 400);
    expect(breakdown.otherCashIn, 0);
    expect(breakdown.supplierPayments, 600);
    expect(breakdown.supplierRefunds, 0);
    expect(breakdown.cashExpenses, 300);
    expect(breakdown.refundsAndVoids, 200);
    expect(breakdown.expectedCash, 10300);
  });

  test('closing stores expected, counted and difference', () async {
    await cash.open(openingCashCentimes: 5000);
    final closed = await cash.close(
      countedCashCentimes: 4950,
      note: 'Petit écart',
    );

    expect(closed.status, 'closed');
    expect(closed.openingCashCentimes, 5000);
    expect(closed.expectedCashCentimes, 5000);
    expect(closed.countedCashCentimes, 4950);
    expect(closed.differenceCentimes, -50);
    expect(closed.note, 'Petit écart');
    expect(await cash.openSession(), isNull);

    final history = await cash.history();
    expect(history, hasLength(1));
    expect(history.single.id, closed.id);
  });

  test('refuses overlapping sessions and invalid amounts', () async {
    await cash.open(openingCashCentimes: 1000);

    await expectLater(
      cash.open(openingCashCentimes: 2000),
      throwsA(isA<ConflictError>()),
    );
    await expectLater(
      cash.open(openingCashCentimes: -1),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      cash.close(countedCashCentimes: -1),
      throwsA(isA<ValidationError>()),
    );
  });

  test('closing without an open session fails', () async {
    await expectLater(
      cash.close(countedCashCentimes: 0),
      throwsA(isA<NotFoundError>()),
    );
  });

  test('voided cash sale removes its collected cash', () async {
    final product = await seedProduct();
    await cash.open(openingCashCentimes: 2000);

    final sale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 1000,
            unitPriceCentimes: 1000,
          ),
        ],
        paidCentimes: 1000,
        paymentMethod: 'cash',
        idempotencyKey: 'void-cash',
      ),
    );

    var breakdown = await cash.breakdown((await cash.openSession())!);
    expect(breakdown.expectedCash, 3000);

    await env.sales.voidSale(sale.id, 'Client a changé d\'avis');

    breakdown = await cash.breakdown((await cash.openSession())!);
    // The sale's cash-in and the void's cash-out both happened in this
    // session, so they net to zero in the drawer.
    expect(breakdown.cashSales, 1000);
    expect(breakdown.refundsAndVoids, 1000);
    expect(breakdown.expectedCash, 2000);
  });
}
