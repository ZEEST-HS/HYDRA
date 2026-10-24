import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/sales/sale_service.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;

  setUp(() async {
    env = await TestEnv.memory();
  });

  tearDown(() async {
    await env.close();
  });

  Future<Product> seedProduct({
    String name = 'Lait Centrale 1L',
    String barcode = '6111245100059',
    int price = 800,
    int cost = 500,
    int stock = 5000,
  }) async {
    final created = await env.products.create(
      Product(
        name: name,
        barcode: barcode,
        priceCentimes: price,
        costCentimes: cost,
        stockMilli: stock,
        minStockMilli: 1000,
        baseUnit: 'piece',
      ),
    );
    return (await env.products.findById(created.id))!;
  }

  SaleDraft cashDraft(
    Product product, {
    int qty = 2000,
    int paid = 1600,
    String key = 'sale-key-1',
    int? customerId,
  }) {
    return SaleDraft(
      lines: [
        SaleDraftLine(
          product: product,
          qtyMilli: qty,
          unitPriceCentimes: product.priceCentimes,
        ),
      ],
      customerId: customerId,
      paidCentimes: paid,
      paymentMethod: 'cash',
      idempotencyKey: key,
    );
  }

  test('completes a cash sale, updates stock and writes audit trail', () async {
    final product = await seedProduct();

    final sale = await env.sales.completeSale(cashDraft(product));

    expect(sale.id, greaterThan(0));
    expect(sale.invoiceNo, startsWith('V-'));
    expect(sale.subtotalCentimes, 1600);
    expect(sale.totalCentimes, 1600);
    expect(sale.paidCentimes, 1600);
    expect(sale.dueCentimes, 0);
    expect(sale.status, 'completed');
    expect(sale.lines, hasLength(1));
    expect(sale.lines.single.qtyMilli, 2000);
    expect(sale.lines.single.unitCostCentimes, 500);
    expect(sale.lines.single.lineTotalCentimes, 1600);

    expect(await productStockMilli(env, product.id), 3000);

    final movements = await env.inventory.movements(product.id);
    final saleMovement = movements.firstWhere((m) => m.type == 'sale');
    expect(saleMovement.qtyDeltaMilli, -2000);
    expect(saleMovement.refType, 'sale');
    expect(saleMovement.refId, sale.id);

    final audit = await env.db.db.query(
      'audit_log',
      where: "action = 'sale' AND entity_id = ?",
      whereArgs: [sale.id],
    );
    expect(audit, hasLength(1));
  });

  test('idempotency key returns the original sale exactly once', () async {
    final product = await seedProduct();

    final first = await env.sales.completeSale(cashDraft(product));
    final second = await env.sales.completeSale(
      cashDraft(product, qty: 1000, paid: 800, key: 'sale-key-1'),
    );

    expect(second.id, first.id);
    expect(second.invoiceNo, first.invoiceNo);
    expect(await env.db.count('sales'), 1);
    expect(await productStockMilli(env, product.id), 3000);
    // Only the first confirmation may consume an invoice number.
    final sequences = await env.db.db.query(
      'sequences',
      where: 'name = ?',
      whereArgs: ['sale'],
    );
    expect(sequences.single['next_value'], 2);
  });

  test('blocks insufficient stock under the default policy', () async {
    final product = await seedProduct(stock: 1000);

    await expectLater(
      env.sales.completeSale(cashDraft(product, qty: 2000, paid: 1600)),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('sales'), 0);
    expect(await productStockMilli(env, product.id), 1000);
  });

  test('allow policy lets stock go negative', () async {
    final product = await seedProduct(stock: 1000);
    await env.settings.setStockPolicy('allow');

    final sale = await env.sales.completeSale(
      cashDraft(product, qty: 2000, paid: 1600),
    );

    expect(sale.totalCentimes, 1600);
    expect(await productStockMilli(env, product.id), -1000);
  });

  test('aggregates duplicate product lines before checking stock', () async {
    final product = await seedProduct(stock: 1500);

    final draft = SaleDraft(
      lines: [
        SaleDraftLine(product: product, qtyMilli: 1000, unitPriceCentimes: 800),
        SaleDraftLine(product: product, qtyMilli: 1000, unitPriceCentimes: 800),
      ],
      paidCentimes: 1600,
      paymentMethod: 'cash',
      idempotencyKey: 'duplicate-lines',
    );

    await expectLater(
      env.sales.completeSale(draft),
      throwsA(isA<ValidationError>()),
    );
    expect(await productStockMilli(env, product.id), 1500);
  });

  test('requires a customer when a balance remains due', () async {
    final product = await seedProduct();

    await expectLater(
      env.sales.completeSale(cashDraft(product, paid: 1000)),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('sales'), 0);
  });

  test(
    'credit sale updates customer debt, ledger and accepts payments',
    () async {
      final product = await seedProduct();
      final customerId = await env.parties.createCustomer(
        const Customer(name: 'Ahmed', phone: '0612345678'),
      );

      final sale = await env.sales.completeSale(
        cashDraft(product, paid: 300, customerId: customerId),
      );

      expect(sale.totalCentimes, 1600);
      expect(sale.dueCentimes, 1300);
      expect(sale.customerName, 'Ahmed');
      expect(await partyBalance(env, 'customers', customerId), 1300);

      final ledger = await env.parties.ledger('customer', customerId);
      expect(ledger.single.entryType, 'sale_due');
      expect(ledger.single.amountCentimes, 1300);

      await env.sales.addPayment(
        saleId: sale.id,
        amountCentimes: 800,
        method: 'cash',
      );

      final updated = (await env.sales.findById(sale.id))!;
      expect(updated.paidCentimes, 1100);
      expect(updated.dueCentimes, 500);
      expect(await partyBalance(env, 'customers', customerId), 500);

      await expectLater(
        env.sales.addPayment(
          saleId: sale.id,
          amountCentimes: 600,
          method: 'cash',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(await partyBalance(env, 'customers', customerId), 500);
    },
  );

  test('rejects overpayment, empty carts and invalid quantities', () async {
    final product = await seedProduct();

    await expectLater(
      env.sales.completeSale(cashDraft(product, paid: 1700)),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.sales.completeSale(
        const SaleDraft(
          lines: [],
          paidCentimes: 0,
          paymentMethod: 'cash',
          idempotencyKey: 'empty',
        ),
      ),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.sales.completeSale(
        SaleDraft(
          lines: [
            SaleDraftLine(
              product: product,
              qtyMilli: 0,
              unitPriceCentimes: 800,
            ),
          ],
          paidCentimes: 0,
          paymentMethod: 'cash',
          idempotencyKey: 'zero-qty',
        ),
      ),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('sales'), 0);
  });

  test('voiding a cash sale restores stock and records cash out', () async {
    final product = await seedProduct();
    final sale = await env.sales.completeSale(cashDraft(product));

    await env.sales.voidSale(sale.id, 'Erreur de caisse');

    final voided = (await env.sales.findById(sale.id))!;
    expect(voided.status, 'voided');
    expect(voided.voidReason, 'Erreur de caisse');
    expect(await productStockMilli(env, product.id), 5000);

    final payments = await env.parties.payments(partyType: 'cash');
    expect(payments, hasLength(1));
    expect(payments.single.direction, 'out');
    expect(payments.single.amountCentimes, 1600);

    await expectLater(
      env.sales.voidSale(sale.id, 'Deuxième fois'),
      throwsA(isA<ConflictError>()),
    );
  });

  test('voiding a credit sale clears the customer balance', () async {
    final product = await seedProduct();
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Salma'),
    );
    final sale = await env.sales.completeSale(
      cashDraft(product, paid: 0, customerId: customerId),
    );

    expect(await partyBalance(env, 'customers', customerId), 1600);

    await env.sales.voidSale(sale.id, 'Client a annulé');

    expect(await partyBalance(env, 'customers', customerId), 0);
    final ledger = await env.parties.ledger('customer', customerId);
    expect(
      ledger.map((e) => e.entryType),
      containsAll(['sale_due', 'sale_void']),
    );
  });

  test('invoice numbers are sequential and unique', () async {
    final product = await seedProduct();
    final first = await env.sales.completeSale(cashDraft(product));
    final second = await env.sales.completeSale(
      cashDraft(product, key: 'sale-key-2'),
    );

    expect(first.invoiceNo, isNot(second.invoiceNo));
    expect(second.invoiceNo, endsWith('00002'));
    expect(await env.db.count('sales'), 2);
  });

  test('package sale stores base quantity and exact package total', () async {
    final product = await seedProduct(stock: 24000);
    const carton = ProductUnit(
      name: 'Carton',
      factorMilli: 12000,
      priceCentimes: 8900,
      isDefaultSale: true,
    );

    final sale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            unit: carton,
            qtyMilli: 12000,
            unitPriceCentimes: 8900,
            lineTotalOverrideCentimes: 8900,
          ),
        ],
        paidCentimes: 8900,
        paymentMethod: 'cash',
        idempotencyKey: 'carton-1',
      ),
    );

    expect(sale.totalCentimes, 8900);
    expect(sale.lines.single.factorMilli, 12000);
    expect(sale.lines.single.unitName, 'Carton');
    expect(sale.lines.single.displayQtyMilli, 1000);
    expect(sale.lines.single.displayUnitPriceCentimes, 8900);
    expect(await productStockMilli(env, product.id), 12000);
  });
}
