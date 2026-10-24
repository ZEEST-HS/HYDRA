import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/sales/return_service.dart';
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

  Future<Product> seedProduct({int stock = 10000}) async {
    final created = await env.products.create(
      Product(
        name: 'Yaourt Jaouda',
        barcode: '6111245100073',
        priceCentimes: 1000,
        costCentimes: 600,
        stockMilli: stock,
        baseUnit: 'piece',
      ),
    );
    return (await env.products.findById(created.id))!;
  }

  Future<Sale> sell(
    Product product, {
    int qty = 3000,
    int? paid,
    int? customerId,
    String key = 'return-sale',
  }) {
    return env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: qty,
            unitPriceCentimes: product.priceCentimes,
          ),
        ],
        customerId: customerId,
        paidCentimes: paid ?? 3000,
        paymentMethod: 'cash',
        idempotencyKey: key,
      ),
    );
  }

  test('partial cash return restores stock and pays cash out', () async {
    final product = await seedProduct();
    final sale = await sell(product);
    expect(await productStockMilli(env, product.id), 7000);

    final returned = await env.returns.returnSale(
      saleId: sale.id,
      lines: [
        ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1000),
      ],
      refundMethod: 'cash',
      note: 'Article abîmé',
    );

    expect(returned.returnNo, startsWith('R-'));
    expect(returned.totalCentimes, 1000);
    expect(returned.refundMethod, 'cash');
    expect(returned.lines.single.qtyMilli, 1000);
    expect(returned.lines.single.unitCostCentimes, 600);
    expect(await productStockMilli(env, product.id), 8000);

    final payments = await env.parties.payments(partyType: 'cash');
    expect(payments.single.direction, 'out');
    expect(payments.single.amountCentimes, 1000);

    final refreshed = (await env.sales.findById(sale.id))!;
    expect(refreshed.returnedCentimes, 1000);
    expect(await env.returns.returnedQuantities(sale.id), {
      sale.lines.single.id: 1000,
    });

    final batches = await env.db.db.query('batches');
    expect(batches.single['qty_remaining_milli'], 8000);
    // The return is restored into the batch the sale consumed, and the
    // allocation is marked as returned.
    final allocations = await env.db.db.query('sale_line_batches');
    expect(allocations.single['qty_milli'], 3000);
    expect(allocations.single['returned_milli'], 1000);
  });

  test('cannot return more than was sold across several returns', () async {
    final product = await seedProduct();
    final sale = await sell(product);

    await env.returns.returnSale(
      saleId: sale.id,
      lines: [
        ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 2000),
      ],
      refundMethod: 'cash',
    );

    await expectLater(
      env.returns.returnSale(
        saleId: sale.id,
        lines: [
          ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1500),
        ],
        refundMethod: 'cash',
      ),
      throwsA(isA<ValidationError>()),
    );

    expect(await productStockMilli(env, product.id), 9000);
    expect(await env.db.count('sale_returns'), 1);
  });

  test('credit return reduces customer debt instead of paying cash', () async {
    final product = await seedProduct();
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Nadia'),
    );
    final sale = await sell(
      product,
      qty: 2000,
      paid: 1000,
      customerId: customerId,
      key: 'credit-sale',
    );
    expect(await partyBalance(env, 'customers', customerId), 1000);

    final returned = await env.returns.returnSale(
      saleId: sale.id,
      lines: [
        ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1000),
      ],
      refundMethod: 'credit',
    );

    expect(returned.totalCentimes, 1000);
    expect(await partyBalance(env, 'customers', customerId), 0);
    expect(await env.parties.payments(partyType: 'cash'), isEmpty);
  });

  test(
    'cash refund is refused while the sale still has a balance due',
    () async {
      final product = await seedProduct();
      final customerId = await env.parties.createCustomer(
        const Customer(name: 'Youssef'),
      );
      final sale = await sell(
        product,
        qty: 2000,
        paid: 500,
        customerId: customerId,
        key: 'due-sale',
      );

      await expectLater(
        env.returns.returnSale(
          saleId: sale.id,
          lines: [
            ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1000),
          ],
          refundMethod: 'cash',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(await productStockMilli(env, product.id), 8000);
    },
  );

  test('credit return requires an identified customer', () async {
    final product = await seedProduct();
    final sale = await sell(product);

    await expectLater(
      env.returns.returnSale(
        saleId: sale.id,
        lines: [
          ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1000),
        ],
        refundMethod: 'credit',
      ),
      throwsA(isA<ValidationError>()),
    );
  });

  test('rejects invalid lines and empty returns', () async {
    final product = await seedProduct();
    final sale = await sell(product);

    await expectLater(
      env.returns.returnSale(
        saleId: sale.id,
        lines: const [],
        refundMethod: 'cash',
      ),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.returns.returnSale(
        saleId: sale.id,
        lines: const [ReturnDraftLine(saleLineId: 999999, qtyMilli: 1000)],
        refundMethod: 'cash',
      ),
      throwsA(isA<ValidationError>()),
    );
  });

  test('voiding a sale with returns is blocked', () async {
    final product = await seedProduct();
    final sale = await sell(product);
    await env.returns.returnSale(
      saleId: sale.id,
      lines: [ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 500)],
      refundMethod: 'cash',
    );

    await expectLater(
      env.sales.voidSale(sale.id, 'Tentative'),
      throwsA(isA<ConflictError>()),
    );
    final refreshed = (await env.sales.findById(sale.id))!;
    expect(refreshed.status, 'completed');
  });

  test('refund amount is proportional to the original line total', () async {
    final product = await seedProduct();
    // 3 units sold for 10.00 DH each, with a 1.00 DH line discount.
    final sale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 3000,
            unitPriceCentimes: 1000,
            lineDiscountCentimes: 100,
          ),
        ],
        paidCentimes: 2900,
        paymentMethod: 'cash',
        idempotencyKey: 'discounted',
      ),
    );
    expect(sale.totalCentimes, 2900);

    final returned = await env.returns.returnSale(
      saleId: sale.id,
      lines: [
        ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 1000),
      ],
      refundMethod: 'cash',
    );

    // One third of 29.00 DH, rounded to the nearest centime.
    expect(returned.totalCentimes, 967);
  });
}
