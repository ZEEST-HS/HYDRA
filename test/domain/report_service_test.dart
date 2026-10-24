import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/dates.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/data/repositories/expense_repository.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';
import 'package:hydra_pos/domain/reports/report_service.dart';
import 'package:hydra_pos/domain/sales/return_service.dart';
import 'package:hydra_pos/domain/sales/sale_service.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late ReportService reports;

  setUp(() async {
    env = await TestEnv.memory();
    reports = ReportService(env.db);
  });

  tearDown(() async {
    await env.close();
  });

  test('summary estimates revenue, cost of goods, expenses and cash', () async {
    final created = await env.products.create(
      const Product(
        name: 'Lait',
        barcode: '6111245100059',
        priceCentimes: 1000,
        costCentimes: 600,
        stockMilli: 10000,
      ),
    );
    final product = (await env.products.findById(created.id))!;
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Ahmed'),
    );

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
        idempotencyKey: 'cash',
      ),
    );

    final creditSale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 2000,
            unitPriceCentimes: 1000,
          ),
        ],
        customerId: customerId,
        paidCentimes: 500,
        paymentMethod: 'cash',
        idempotencyKey: 'credit',
      ),
    );
    await env.sales.addPayment(
      saleId: creditSale.id,
      amountCentimes: 300,
      method: 'cash',
    );

    await env.returns.returnSale(
      saleId: cashSale.id,
      lines: [
        ReturnDraftLine(saleLineId: cashSale.lines.single.id, qtyMilli: 500),
      ],
      refundMethod: 'cash',
    );

    await ExpenseRepository(env.db)
        .create(category: 'Transport', amountCentimes: 200, method: 'cash');

    await env.purchases.completePurchase(
      PurchaseDraft(
        lines: [
          PurchaseDraftLine(
            product: product,
            qtyMilli: 5000,
            unitCostCentimes: 400,
          ),
        ],
        paidCentimes: 2000,
        paymentMethod: 'cash',
      ),
    );

    // An older sale must not leak into today's report.
    await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 500,
            unitPriceCentimes: 1000,
          ),
        ],
        paidCentimes: 500,
        paymentMethod: 'cash',
        idempotencyKey: 'old',
        at: DateTime.now().subtract(const Duration(days: 3)),
      ),
    );

    final today = DateTime.now();
    final summary = await reports.summary(from: today, to: today);

    expect(summary.salesCount, 2);
    expect(summary.salesTotal, 3000);
    expect(summary.returnsTotal, 500);
    expect(summary.revenue, 2500);
    expect(summary.cogs, 1500);
    expect(summary.grossProfit, 1000);
    expect(summary.expensesTotal, 200);
    expect(summary.netProfit, 800);
    expect(summary.cashSales, 1500);
    expect(summary.cashFromCredits, 300);
    expect(summary.cashRefunds, 500);
    expect(summary.cashCollected, 1300);
    expect(summary.creditSales, 1200);
    expect(summary.cardSales, 0);
    expect(summary.purchasesTotal, 2000);
    expect(summary.missingCostLines, 0);
    expect(summary.averageBasket, 1500);
    expect(summary.discounts, 0);

    final top = await reports.topProducts(from: today, to: today);
    expect(top.single.name, 'Lait');
    expect(top.single.qtyMilli, 2500);
    expect(top.single.revenueCentimes, 2500);

    final payments = await reports.paymentBreakdown(from: today, to: today);
    expect(payments['cash'], 1800);

    final expenses = await reports.expenseByCategory(from: today, to: today);
    expect(expenses, {'Transport': 200});
  });

  test('daily series fills empty days and subtracts returns', () async {
    final created = await env.products.create(
      const Product(name: 'Pain', priceCentimes: 200, stockMilli: 5000),
    );
    final product = (await env.products.findById(created.id))!;
    final sale = await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 1000,
            unitPriceCentimes: 200,
          ),
        ],
        paidCentimes: 200,
        paymentMethod: 'cash',
        idempotencyKey: 'series',
      ),
    );
    await env.returns.returnSale(
      saleId: sale.id,
      lines: [ReturnDraftLine(saleLineId: sale.lines.single.id, qtyMilli: 500)],
      refundMethod: 'cash',
    );

    final today = Dates.startOfDay(DateTime.now());
    final series = await reports.dailySeries(
      today.subtract(const Duration(days: 3)),
      today,
    );

    expect(series, hasLength(4));
    expect(series.last.date, today);
    expect(series.last.sales, 200);
    expect(series.last.revenue, 100);
    expect(series.take(3).every((p) => p.sales == 0), isTrue);
  });

  test('dashboard aggregates today, stock, debt and top products', () async {
    final created = await env.products.create(
      const Product(
        name: 'Eau',
        barcode: '6111245100103',
        priceCentimes: 500,
        costCentimes: 300,
        stockMilli: 10000,
        minStockMilli: 20000,
      ),
    );
    final product = (await env.products.findById(created.id))!;
    await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 2000,
            unitPriceCentimes: 500,
          ),
        ],
        paidCentimes: 1000,
        paymentMethod: 'cash',
        idempotencyKey: 'dash',
      ),
    );

    final dashboard = await reports.dashboard();

    expect(dashboard.today.salesCount, 1);
    expect(dashboard.today.revenue, 1000);
    expect(dashboard.last7Days, hasLength(7));
    expect(dashboard.lowStockCount, 1);
    expect(dashboard.productCount, 1);
    expect(dashboard.topProducts.single.name, 'Eau');
    expect(dashboard.customerDebt, 0);
    expect(dashboard.supplierDebt, 0);
  });
}
