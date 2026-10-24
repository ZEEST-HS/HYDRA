import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/data/repositories/inventory_repository.dart';
import 'package:hydra_pos/data/repositories/product_repository.dart';
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

  test('normalizes scanned barcodes before lookup and storage', () async {
    final created = await env.products.create(
      const Product(name: 'Lait', barcode: '6111 2451 00059'),
    );
    expect(created.barcode, '6111245100059');

    final byBarcode = await env.products.findByBarcode(' 6111245100059\u200B ');
    expect(byBarcode, isNotNull);
    expect(byBarcode!.id, created.id);

    expect(normalizeBarcode(' 61\u200B1124\t5100059 '), '6111245100059');
    expect(await env.products.findByBarcode('\u200B '), isNull);
  });

  test('rejects duplicate barcodes but allows a reusable one', () async {
    final created = await env.products.create(
      const Product(name: 'Lait', barcode: '6111245100059'),
    );

    await expectLater(
      env.products.create(
        const Product(name: 'Autre lait', barcode: '6111 2451 00059'),
      ),
      throwsA(isA<ConflictError>()),
    );

    await env.products.delete(created.id, reason: 'Produit arrêté');

    final replacement = await env.products.create(
      const Product(name: 'Nouveau lait', barcode: '6111245100059'),
    );
    expect(replacement.id, isNot(created.id));
    expect(await env.products.findByBarcode('6111245100059'), isNotNull);
  });

  test('packaging units are stored and returned with the product', () async {
    final created = await env.products.create(
      const Product(
        name: 'Eau',
        barcode: '6111245100110',
        units: [
          ProductUnit(
            name: 'Pack de 6',
            nameAr: 'علبة 6',
            factorMilli: 6000,
            priceCentimes: 2700,
            isDefaultSale: true,
          ),
          ProductUnit(
            name: 'Carton de 24',
            factorMilli: 24000,
            costCentimes: 9000,
            isDefaultPurchase: true,
          ),
        ],
      ),
    );

    final product = (await env.products.findById(created.id))!;
    expect(product.units, hasLength(2));
    expect(product.hasPackaging, isTrue);
    expect(product.units.first.name, 'Pack de 6');
    expect(product.units.first.factorMilli, 6000);
    expect(product.units.first.nameAr, 'علبة 6');
    expect(product.units.last.isDefaultPurchase, isTrue);
    // Unit factors are converted through the same rule as base quantities.
    expect(ProductRepository.packageQtyToBase('2', 6000), 12000);
    expect(
      () => ProductRepository.packageQtyToBase('abc', 6000),
      throwsA(isA<ValidationError>()),
    );
  });

  test(
    'stock adjustments require a reason and respect the negative guard',
    () async {
      final product = await env.products.create(
        const Product(name: 'Riz', stockMilli: 5000, costCentimes: 400),
      );

      await expectLater(
        env.inventory.adjustStock(
          productId: product.id,
          deltaMilli: -1000,
          reason: '   ',
        ),
        throwsA(isA<ValidationError>()),
      );
      await expectLater(
        env.inventory.adjustStock(
          productId: product.id,
          deltaMilli: -6000,
          reason: 'Perte',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(await productStockMilli(env, product.id), 5000);

      await env.inventory.adjustStock(
        productId: product.id,
        deltaMilli: -6000,
        reason: 'Perte exceptionnelle',
        allowNegative: true,
      );
      expect(await productStockMilli(env, product.id), -1000);

      final movements = await env.inventory.movements(product.id);
      expect(movements.first.type, 'adjustment');
      expect(movements.first.qtyDeltaMilli, -6000);
      expect(movements.first.reason, 'Perte exceptionnelle');
    },
  );

  test('stocktake session applies counted quantities atomically', () async {
    final a = await env.products.create(
      const Product(name: 'A', barcode: 'A1', stockMilli: 5000),
    );
    final b = await env.products.create(
      const Product(name: 'B', barcode: 'B1', stockMilli: 3000),
    );

    final adjusted = await env.inventory.confirmStocktake([
      StocktakeEntry(productId: a.id, countedMilli: 4500),
      StocktakeEntry(productId: b.id, countedMilli: 3000),
    ], 'Inventaire mensuel');

    expect(adjusted, 1);
    expect(await productStockMilli(env, a.id), 4500);
    expect(await productStockMilli(env, b.id), 3000);

    final audit = await env.db.db.query(
      'audit_log',
      where: "action = 'stocktake'",
      orderBy: 'id ASC',
    );
    expect(audit, hasLength(2), reason: 'unchanged counts are logged too');
    expect(audit.first['reason'], 'Inventaire mensuel');

    // Setting the same value writes an audit row but no stock movement.
    await env.inventory.setCountedStock(
      productId: b.id,
      countedMilli: 3000,
      reason: 'Comptage sans écart',
    );
    final movements = await env.db.db.query(
      'stock_movements',
      where: "type = 'stocktake'",
    );
    expect(movements, hasLength(1));
  });

  test('soft deletion keeps historical invoice rows immutable', () async {
    final product = await env.products.create(
      const Product(
        name: 'Beurre',
        barcode: '6111245100127',
        priceCentimes: 1200,
        costCentimes: 800,
        stockMilli: 4000,
      ),
    );
    final sale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 1000,
            unitPriceCentimes: 1200,
          ),
        ],
        paidCentimes: 1200,
        paymentMethod: 'cash',
        idempotencyKey: 'history',
      ),
    );

    await env.products.delete(product.id, reason: 'Fin de gamme');

    expect(await env.products.findById(product.id), isNull);
    expect(await env.products.findByBarcode('6111245100127'), isNull);
    final search = await env.products.search('Beurre');
    expect(search, isEmpty);

    final history = (await env.sales.findById(sale.id))!;
    expect(history.lines.single.productName, 'Beurre');
    expect(history.lines.single.lineTotalCentimes, 1200);
    expect(history.totalCentimes, 1200);
  });

  test('initial stock and stock value are computed from base units', () async {
    await env.products.create(
      const Product(
        name: 'Huile',
        stockMilli: 3500,
        costCentimes: 900,
        minStockMilli: 1000,
      ),
    );

    expect(await env.products.stockValueTotal(), 3150);

    final movements = await env.db.db.query('stock_movements');
    expect(movements.single['type'], 'initial');
    expect(movements.single['qty_delta_milli'], 3500);
  });

  test('low stock query reflects the minimum threshold', () async {
    await env.products.create(
      const Product(name: 'Bas', stockMilli: 500, minStockMilli: 1000),
    );
    await env.products.create(
      const Product(name: 'Haut', stockMilli: 5000, minStockMilli: 1000),
    );
    await env.products.create(
      const Product(name: 'Sans seuil', stockMilli: 0, minStockMilli: 0),
    );

    expect(await env.inventory.lowStockCount(), 1);
    final low = await env.products.search('', lowStockOnly: true);
    expect(low.single.name, 'Bas');
  });
}
