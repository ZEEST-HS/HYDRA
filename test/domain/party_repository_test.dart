import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';
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

  Future<int> customerWithDebt(int amount) async {
    final product = await env.products.create(
      const Product(
        name: 'Sucre',
        barcode: '6111245100134',
        priceCentimes: 700,
        stockMilli: 20000,
      ),
    );
    final full = (await env.products.findById(product.id))!;
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Fatima', phone: '0611111111'),
    );
    await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: full,
            qtyMilli: amount * 1000 ~/ 700,
            unitPriceCentimes: 700,
          ),
        ],
        customerId: customerId,
        paidCentimes: 0,
        paymentMethod: 'cash',
        idempotencyKey: 'debt-$amount',
      ),
    );
    return customerId;
  }

  test('creates, searches and updates customers and suppliers', () async {
    final id = await env.parties.createCustomer(
      const Customer(
        name: '  Ahmed  ',
        phone: ' 0612345678 ',
        address: 'Casablanca',
        creditLimitCentimes: 50000,
      ),
    );

    var customer = (await env.parties.customer(id))!;
    expect(customer.name, 'Ahmed');
    expect(customer.phone, '0612345678');
    expect(customer.creditLimitCentimes, 50000);
    expect((await env.parties.customers(query: 'Ahmed')), hasLength(1));
    expect((await env.parties.customers(query: '0612')), hasLength(1));
    expect((await env.parties.customers(query: 'Inconnu')), isEmpty);

    await env.parties.updateCustomer(
      Customer(
        id: id,
        name: 'Ahmed B.',
        phone: '0600000000',
        address: customer.address,
        note: customer.note,
        balanceCentimes: customer.balanceCentimes,
        creditLimitCentimes: customer.creditLimitCentimes,
        createdAt: customer.createdAt,
      ),
    );
    customer = (await env.parties.customer(id))!;
    expect(customer.name, 'Ahmed B.');
    expect(customer.phone, '0600000000');

    final supplierId = await env.parties.createSupplier(
      const Supplier(name: 'Atlas', phone: '0522000000'),
    );
    final supplier = (await env.parties.supplier(supplierId))!;
    expect(supplier.name, 'Atlas');
    expect((await env.parties.suppliers(query: 'Atlas')), hasLength(1));

    await expectLater(
      env.parties.createCustomer(const Customer(name: '   ')),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.parties.createSupplier(const Supplier(name: '')),
      throwsA(isA<ValidationError>()),
    );
  });

  test(
    'customer payments reduce debt and are recorded in the ledger',
    () async {
      final customerId = await customerWithDebt(7000);

      expect(await partyBalance(env, 'customers', customerId), 7000);

      await env.parties.receiveCustomerPayment(
        customerId: customerId,
        amountCentimes: 3000,
        method: 'cash',
        note: 'Acompte',
      );

      expect(await partyBalance(env, 'customers', customerId), 4000);
      expect(await env.parties.totalCustomerDebt(), 4000);

      final payments = await env.parties.payments(
        partyType: 'customer',
        partyId: customerId,
      );
      expect(payments, hasLength(1));
      expect(payments.single.direction, 'in');
      expect(payments.single.amountCentimes, 3000);
      expect(payments.single.note, 'Acompte');

      final ledger = await env.parties.ledger('customer', customerId);
      expect(
        ledger.map((e) => e.entryType),
        containsAll(['sale_due', 'payment']),
      );

      await expectLater(
        env.parties.receiveCustomerPayment(
          customerId: customerId,
          amountCentimes: 5000,
          method: 'cash',
        ),
        throwsA(isA<ValidationError>()),
      );
      expect(await partyBalance(env, 'customers', customerId), 4000);

      await expectLater(
        env.parties.receiveCustomerPayment(
          customerId: customerId,
          amountCentimes: 0,
          method: 'cash',
        ),
        throwsA(isA<ValidationError>()),
      );
    },
  );

  test('supplier payments settle purchases and reduce the balance', () async {
    final supplierId = await env.parties.createSupplier(
      const Supplier(name: 'Grossiste'),
    );
    const product = Product(
      name: 'Farine',
      barcode: '6111245100141',
      priceCentimes: 500,
      stockMilli: 0,
    );
    final created = await env.products.create(product);
    final full = (await env.products.findById(created.id))!;

    await env.purchases.completePurchase(
      PurchaseDraft(
        supplierId: supplierId,
        lines: [
          PurchaseDraftLine(
            product: full,
            qtyMilli: 10000,
            unitCostCentimes: 400,
          ),
        ],
        paidCentimes: 1000,
        paymentMethod: 'cash',
      ),
    );
    expect(await partyBalance(env, 'suppliers', supplierId), 3000);
    expect(await env.parties.totalSupplierDebt(), 3000);

    await env.parties.paySupplier(
      supplierId: supplierId,
      amountCentimes: 2000,
      method: 'cash',
      note: 'Règlement',
    );
    expect(await partyBalance(env, 'suppliers', supplierId), 1000);

    await expectLater(
      env.parties.paySupplier(
        supplierId: supplierId,
        amountCentimes: 1500,
        method: 'cash',
      ),
      throwsA(isA<ValidationError>()),
    );
    expect(await partyBalance(env, 'suppliers', supplierId), 1000);
  });

  test(
    'deleted parties disappear from lists but keep payment history',
    () async {
      final customerId = await customerWithDebt(700);
      await env.parties.receiveCustomerPayment(
        customerId: customerId,
        amountCentimes: 700,
        method: 'cash',
      );

      await env.parties.deleteCustomer(customerId);

      expect(await env.parties.customer(customerId), isNull);
      final list = await env.parties.customers();
      expect(list.where((c) => c.id == customerId), isEmpty);
      expect(
        await env.parties.payments(partyType: 'customer', partyId: customerId),
        hasLength(1),
      );
      expect(await env.parties.totalCustomerDebt(), 0);
    },
  );
}
