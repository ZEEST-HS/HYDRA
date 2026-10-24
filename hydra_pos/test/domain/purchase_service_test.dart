import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/cash/cash_service.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';

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
    String name = 'Huile Lesieur 5L',
    String barcode = '6111245100066',
    int price = 9500,
    int cost = 0,
    int stock = 0,
  }) async {
    final created = await env.products.create(
      Product(
        name: name,
        barcode: barcode,
        priceCentimes: price,
        costCentimes: cost,
        stockMilli: stock,
        baseUnit: 'piece',
      ),
    );
    return (await env.products.findById(created.id))!;
  }

  Future<int> seedSupplier([String name = 'Grossiste Atlas']) =>
      env.parties.createSupplier(Supplier(name: name, phone: '0522000000'));

  PurchaseDraft purchase({
    required Product product,
    int? supplierId,
    int qty = 10000,
    int unitCost = 600,
    int paid = 2000,
    int? lineTotal,
    String? expiry,
  }) {
    return PurchaseDraft(
      supplierId: supplierId,
      lines: [
        PurchaseDraftLine(
          product: product,
          qtyMilli: qty,
          unitCostCentimes: unitCost,
          lineTotalOverrideCentimes: lineTotal,
          expiryDate: expiry,
        ),
      ],
      paidCentimes: paid,
      paymentMethod: 'cash',
    );
  }

  test('completes a purchase, updates stock, cost and supplier debt', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();

    final result = await env.purchases.completePurchase(
      purchase(product: product, supplierId: supplierId),
    );

    expect(result.refNo, startsWith('A-'));
    expect(result.subtotalCentimes, 6000);
    expect(result.totalCentimes, 6000);
    expect(result.paidCentimes, 2000);
    expect(result.dueCentimes, 4000);
    expect(result.supplierName, 'Grossiste Atlas');
    expect(result.lines.single.qtyMilli, 10000);
    expect(result.lines.single.unitCostCentimes, 600);

    expect(await productStockMilli(env, product.id), 10000);
    expect(await productCostCentimes(env, product.id), 600);
    expect(await partyBalance(env, 'suppliers', supplierId), 4000);

    final payments = await env.purchases.paymentsForPurchase(result.id);
    expect(payments, hasLength(1));
    expect(payments.single.direction, 'out');
    expect(payments.single.amountCentimes, 2000);

    final batches = await env.db.db.query('batches');
    expect(batches, hasLength(1));
    expect(batches.single['qty_remaining_milli'], 10000);
  });

  test('keeps a weighted average cost across purchases', () async {
    final product = await seedProduct(cost: 600, stock: 10000);
    final supplierId = await seedSupplier();

    final result = await env.purchases.completePurchase(
      purchase(
        product: product,
        supplierId: supplierId,
        qty: 10000,
        unitCost: 900,
        paid: 9000,
      ),
    );

    expect(result.totalCentimes, 9000);
    expect(await productStockMilli(env, product.id), 20000);
    // (10 000 x 0.60 + 90.00 DH) / 20 000 base units = 0.75 DH.
    expect(await productCostCentimes(env, product.id), 750);
  });

  test(
    'partial payments reduce the supplier balance and purchase due',
    () async {
      final product = await seedProduct();
      final supplierId = await seedSupplier();
      final result = await env.purchases.completePurchase(
        purchase(product: product, supplierId: supplierId),
      );

      await env.purchases.addPayment(
        purchaseId: result.id,
        amountCentimes: 1500,
        method: 'cash',
        note: 'Versement',
      );

      final updated = (await env.purchases.findById(result.id))!;
      expect(updated.paidCentimes, 3500);
      expect(updated.dueCentimes, 2500);
      expect(await partyBalance(env, 'suppliers', supplierId), 2500);
      expect(await env.purchases.paymentsForPurchase(result.id), hasLength(2));

      await expectLater(
        env.purchases.addPayment(
          purchaseId: result.id,
          amountCentimes: 2600,
          method: 'cash',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(await partyBalance(env, 'suppliers', supplierId), 2500);
    },
  );

  test('voiding restores stock and supplier debt', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();
    final result = await env.purchases.completePurchase(
      purchase(product: product, supplierId: supplierId),
    );

    await env.purchases.voidPurchase(result.id, 'Produits non conformes');

    final voided = (await env.purchases.findById(result.id))!;
    expect(voided.status, 'voided');
    expect(await productStockMilli(env, product.id), 0);
    expect(await partyBalance(env, 'suppliers', supplierId), 0);

    await expectLater(
      env.purchases.voidPurchase(result.id, 'Encore'),
      throwsA(isA<ConflictError>()),
    );
  });

  test('cash refund from a voided purchase enters the cash drawer', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();
    final cash = CashService(env.db);

    await cash.open(openingCashCentimes: 10000);
    final result = await env.purchases.completePurchase(
      purchase(
        product: product,
        supplierId: supplierId,
        qty: 2000,
        unitCost: 500,
        paid: 1000,
      ),
    );
    var session = (await cash.openSession())!;
    var breakdown = await cash.breakdown(session);
    expect(breakdown.supplierPayments, 1000);
    expect(breakdown.expectedCash, 9000);

    await env.purchases.voidPurchase(result.id, 'Erreur de commande');

    session = (await cash.openSession())!;
    breakdown = await cash.breakdown(session);
    expect(breakdown.supplierRefunds, 1000);
    expect(breakdown.expectedCash, 10000);
  });

  test('package purchase uses the exact package total for cost', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();
    const carton = ProductUnit(
      name: 'Carton de 12',
      factorMilli: 12000,
      costCentimes: 8900,
      isDefaultPurchase: true,
    );

    final result = await env.purchases.completePurchase(
      PurchaseDraft(
        supplierId: supplierId,
        lines: [
          PurchaseDraftLine(
            product: product,
            unit: carton,
            qtyMilli: 12000,
            unitCostCentimes: 8900,
            lineTotalOverrideCentimes: 8900,
          ),
        ],
        paidCentimes: 8900,
        paymentMethod: 'cash',
      ),
    );

    expect(result.totalCentimes, 8900);
    expect(result.lines.single.factorMilli, 12000);
    expect(result.lines.single.unitName, 'Carton de 12');
    expect(await productStockMilli(env, product.id), 12000);
    // 89.00 DH / 12 base units = 741.67 -> 742 centimes.
    expect(await productCostCentimes(env, product.id), 742);
  });

  test('purchase with expiry creates a batch for FEFO sales', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();

    await env.purchases.completePurchase(
      purchase(
        product: product,
        supplierId: supplierId,
        qty: 5000,
        unitCost: 700,
        paid: 3500,
        expiry: '2026-12-31',
      ),
    );

    final batches = await env.db.db.query('batches');
    expect(batches.single['expiry_date'], '2026-12-31');

    final expiring = await env.inventory.expiringBatches(days: 365);
    expect(expiring, hasLength(1));
    expect(expiring.single.productName, product.name);
  });

  test('requires a supplier when the purchase is unpaid', () async {
    final product = await seedProduct();

    await expectLater(
      env.purchases.completePurchase(purchase(product: product, paid: 0)),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('purchases'), 0);
  });

  test('rejects overpayment and empty purchases', () async {
    final product = await seedProduct();
    final supplierId = await seedSupplier();

    await expectLater(
      env.purchases.completePurchase(
        purchase(product: product, supplierId: supplierId, paid: 7000),
      ),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.purchases.completePurchase(
        const PurchaseDraft(lines: [], paidCentimes: 0, paymentMethod: 'cash'),
      ),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('purchases'), 0);
  });
}
