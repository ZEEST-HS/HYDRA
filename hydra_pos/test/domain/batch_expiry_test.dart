import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';
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

  Future<Product> seedProduct() async {
    final created = await env.products.create(
      const Product(
        name: 'Yaourt Jaouda',
        barcode: '6111245100073',
        priceCentimes: 1000,
        costCentimes: 500,
        baseUnit: 'piece',
      ),
    );
    return (await env.products.findById(created.id))!;
  }

  Future<void> purchase(
    Product product, {
    required int qty,
    required String expiry,
    required String batchNo,
  }) async {
    final lineTotal = qty * 500 ~/ 1000;
    await env.purchases.completePurchase(
      PurchaseDraft(
        lines: [
          PurchaseDraftLine(
            product: product,
            qtyMilli: qty,
            unitCostCentimes: 500,
            expiryDate: expiry,
            batchNo: batchNo,
          ),
        ],
        paidCentimes: lineTotal,
        paymentMethod: 'cash',
      ),
    );
  }

  Future<Sale> sell(Product product, int qty) {
    return env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: qty,
            unitPriceCentimes: product.priceCentimes,
          ),
        ],
        paidCentimes: qty * product.priceCentimes ~/ 1000,
        paymentMethod: 'cash',
        idempotencyKey: 'fefo-sale-$qty',
      ),
    );
  }

  test('FEFO sells the earliest batch first and tracks allocations', () async {
    final product = await seedProduct();
    await purchase(product, qty: 3000, expiry: '2026-11-01', batchNo: 'LOT-A');
    await purchase(product, qty: 5000, expiry: '2026-12-01', batchNo: 'LOT-B');

    final sale = await sell(product, 4000);

    final batches = await env.db.db.query('batches', orderBy: 'id ASC');
    expect(batches, hasLength(2));
    expect(batches[0]['batch_no'], 'LOT-A');
    expect(batches[0]['qty_remaining_milli'], 0);
    expect(batches[1]['batch_no'], 'LOT-B');
    expect(batches[1]['qty_remaining_milli'], 4000);

    final allocations = await env.db.db.query(
      'sale_line_batches',
      orderBy: 'id ASC',
    );
    expect(allocations, hasLength(2));
    expect(allocations[0]['batch_id'], batches[0]['id']);
    expect(allocations[0]['qty_milli'], 3000);
    expect(allocations[1]['batch_id'], batches[1]['id']);
    expect(allocations[1]['qty_milli'], 1000);

    await env.returns.returnSale(
      saleId: sale.id,
      lines: [ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 500)],
      refundMethod: 'cash',
    );

    final restored = await env.db.db.query('batches', orderBy: 'id ASC');
    // The returned quantity goes back into the first (earliest) batch.
    expect(restored[0]['qty_remaining_milli'], 500);
    expect(restored[1]['qty_remaining_milli'], 4000);
    expect(await productStockMilli(env, product.id), 4500);
  });

  test('disposal removes stock from the batch and logs the loss', () async {
    final product = await seedProduct();
    await purchase(product, qty: 5000, expiry: '2020-01-01', batchNo: 'OLD');
    final batch = (await env.db.db.query('batches')).single;

    final before = await env.db.db.query('stock_movements');
    await env.inventory.disposeBatch(
      batchId: batch['id'] as int,
      qtyMilli: 2000,
      reason: 'Produit périmé',
    );

    expect(await productStockMilli(env, product.id), 3000);
    final batches = await env.db.db.query('batches');
    expect(batches.single['qty_remaining_milli'], 3000);

    final movements = await env.db.db.query(
      'stock_movements',
      orderBy: 'id ASC',
    );
    expect(movements.length, before.length + 1);
    expect(movements.last['type'], 'disposal');
    expect(movements.last['qty_delta_milli'], -2000);

    final audit = await env.db.db.query(
      'audit_log',
      where: 'action = ?',
      whereArgs: ['disposal'],
    );
    expect(audit, hasLength(1));
    expect(audit.single['entity'], 'batch');
    expect(audit.single['reason'], 'Produit périmé');
  });

  test('disposal refuses more than the batch holds', () async {
    final product = await seedProduct();
    await purchase(product, qty: 1000, expiry: '2020-01-01', batchNo: 'OLD');
    final batch = (await env.db.db.query('batches')).single;

    await expectLater(
      env.inventory.disposeBatch(
        batchId: batch['id'] as int,
        qtyMilli: 2000,
        reason: 'Erreur',
      ),
      throwsA(isA<ValidationError>()),
    );
    expect(await productStockMilli(env, product.id), 1000);
  });

  test('expiry views split expired, upcoming and missing dates', () async {
    final product = await seedProduct();
    await purchase(product, qty: 1000, expiry: '2020-01-01', batchNo: 'OLD');
    await purchase(product, qty: 1000, expiry: '2099-01-01', batchNo: 'FUT');
    // No expiry, created directly through a stock adjustment.
    await env.inventory.adjustStock(
      productId: product.id,
      deltaMilli: 1000,
      reason: 'Stock initial',
    );

    final expired = await env.inventory.expiredBatches();
    expect(expired, hasLength(1));
    expect(expired.single.batchNo, 'OLD');

    final missing = await env.inventory.missingExpiryBatches();
    expect(missing, hasLength(1));
    expect(missing.single.batchNo, isNull);

    final upcoming = await env.inventory.expiringBatches(days: 30);
    expect(upcoming, isEmpty);

    final productBatches = await env.inventory.batchesForProduct(product.id);
    // Dated batches come first in expiry order, missing dates last.
    expect(productBatches.map((b) => b.batchNo).toList(), ['OLD', 'FUT', null]);
  });
}
