import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';

class ReportSummary {
  const ReportSummary({
    this.salesCount = 0,
    this.salesTotal = 0,
    this.returnsTotal = 0,
    this.revenue = 0,
    this.discounts = 0,
    this.cogs = 0,
    this.grossProfit = 0,
    this.expensesTotal = 0,
    this.netProfit = 0,
    this.cashSales = 0,
    this.cashFromCredits = 0,
    this.cashRefunds = 0,
    this.cashCollected = 0,
    this.creditSales = 0,
    this.cardSales = 0,
    this.purchasesTotal = 0,
    this.missingCostLines = 0,
    this.averageBasket = 0,
  });

  final int salesCount;
  final int salesTotal;
  final int returnsTotal;
  final int revenue;
  final int discounts;
  final int cogs;
  final int grossProfit;
  final int expensesTotal;
  final int netProfit;
  final int cashSales;
  final int cashFromCredits;
  final int cashRefunds;
  final int cashCollected;
  final int creditSales;
  final int cardSales;
  final int purchasesTotal;
  final int missingCostLines;
  final int averageBasket;
}

class DailyPoint {
  const DailyPoint({
    required this.date,
    this.sales = 0,
    this.revenue = 0,
    this.purchases = 0,
    this.expenses = 0,
  });
  final DateTime date;
  final int sales;
  final int revenue;
  final int purchases;
  final int expenses;
}

class TopProduct {
  const TopProduct({
    this.productId,
    required this.name,
    required this.qtyMilli,
    required this.revenueCentimes,
  });
  final int? productId;
  final String name;
  final int qtyMilli;
  final int revenueCentimes;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.today,
    required this.last7Days,
    required this.lowStockCount,
    required this.expiringCount,
    required this.customerDebt,
    required this.supplierDebt,
    required this.productCount,
    required this.topProducts,
    this.openCashSession,
  });

  final ReportSummary today;
  final List<DailyPoint> last7Days;
  final int lowStockCount;
  final int expiringCount;
  final int customerDebt;
  final int supplierDebt;
  final int productCount;
  final List<TopProduct> topProducts;
  final dynamic openCashSession;
}

class ReportService {
  ReportService(this.appDb);
  final AppDatabase appDb;
  Database get _db => appDb.db;

  Future<ReportSummary> summary({DateTime? from, DateTime? to}) async {
    final start = Dates.businessDate(from ?? DateTime.now());
    final end = Dates.businessDate(to ?? from ?? DateTime.now());

    final salesRows = await _db.rawQuery(
      '''
      SELECT
        COUNT(*) AS cnt,
        COALESCE(SUM(subtotal_centimes), 0) AS subtotal,
        COALESCE(SUM(discount_centimes), 0) AS discount,
        COALESCE(SUM(total_centimes), 0) AS total,
        COALESCE(SUM(due_centimes), 0) AS due,
        COALESCE(SUM(CASE WHEN payment_method = 'cash' THEN
          paid_centimes - COALESCE((
            SELECT SUM(p.amount_centimes) FROM payments p
            WHERE p.sale_id = sales.id AND p.direction = 'in'
          ), 0) ELSE 0 END), 0) AS cash_sales,
        COALESCE(SUM(CASE WHEN payment_method = 'card' THEN
          paid_centimes - COALESCE((
            SELECT SUM(p.amount_centimes) FROM payments p
            WHERE p.sale_id = sales.id AND p.direction = 'in'
          ), 0) ELSE 0 END), 0) AS card_sales
      FROM sales
      WHERE status = 'completed' AND business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final s = salesRows.first;
    final salesTotal = (s['total'] as num).toInt();
    final salesCount = (s['cnt'] as num).toInt();
    final cashSales = (s['cash_sales'] as num).toInt();
    final cardSales = (s['card_sales'] as num).toInt();
    final creditSales = (s['due'] as num).toInt();

    final returnsRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_centimes), 0) AS t FROM sale_returns
      WHERE business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final returnsTotal = (returnsRows.first['t'] as num).toInt();

    final cogsRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM((sl.qty_milli * sl.unit_cost_centimes) / 1000), 0) AS cogs,
             COALESCE(SUM(CASE WHEN sl.unit_cost_centimes = 0 THEN 1 ELSE 0 END), 0) AS missing
      FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id
      WHERE s.status = 'completed' AND s.business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final salesCogs = (cogsRows.first['cogs'] as num).toInt();
    final missing = (cogsRows.first['missing'] as num).toInt();

    final returnCogsRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM((rl.qty_milli * rl.unit_cost_centimes) / 1000), 0) AS cogs
      FROM return_lines rl JOIN sale_returns r ON r.id = rl.return_id
      WHERE r.business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final returnCogs = (returnCogsRows.first['cogs'] as num).toInt();

    final lineDiscountRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(sl.line_discount_centimes), 0) AS d
      FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id
      WHERE s.status = 'completed' AND s.business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );

    final expenseRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) AS t FROM expenses
      WHERE business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final expenses = (expenseRows.first['t'] as num).toInt();

    final purchaseRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(total_centimes), 0) AS t FROM purchases
      WHERE status = 'completed' AND business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final purchases = (purchaseRows.first['t'] as num).toInt();

    final cashCreditRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) AS t FROM payments
      WHERE party_type = 'customer' AND direction = 'in' AND method = 'cash'
        AND business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final refundRows = await _db.rawQuery(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) AS t FROM payments
      WHERE party_type = 'cash' AND direction = 'out' AND method = 'cash'
        AND business_date BETWEEN ? AND ?
    ''',
      [start, end],
    );
    final cashFromCredits = (cashCreditRows.first['t'] as num).toInt();
    final cashRefunds = (refundRows.first['t'] as num).toInt();

    final revenue = salesTotal - returnsTotal;
    final cogs = salesCogs - returnCogs;
    final gross = revenue - cogs;
    final net = gross - expenses;
    final discounts =
        (s['discount'] as num).toInt() +
        (lineDiscountRows.first['d'] as num).toInt();

    return ReportSummary(
      salesCount: salesCount,
      salesTotal: salesTotal,
      returnsTotal: returnsTotal,
      revenue: revenue,
      discounts: discounts,
      cogs: cogs,
      grossProfit: gross,
      expensesTotal: expenses,
      netProfit: net,
      cashSales: cashSales,
      cashFromCredits: cashFromCredits,
      cashRefunds: cashRefunds,
      cashCollected: cashSales + cashFromCredits - cashRefunds,
      creditSales: creditSales,
      cardSales: cardSales,
      purchasesTotal: purchases,
      missingCostLines: missing,
      averageBasket: salesCount == 0 ? 0 : salesTotal ~/ salesCount,
    );
  }

  Future<DashboardSnapshot> dashboard({int expiryDays = 30}) async {
    final now = DateTime.now();
    final today = Dates.startOfDay(now);
    final weekStart = today.subtract(const Duration(days: 6));
    final results = await Future.wait<Object>([
      summary(from: today, to: today),
      dailySeries(weekStart, today),
      _lowStockCount(),
      expiringBatches(days: expiryDays),
      _customerDebt(),
      _supplierDebt(),
      _productCount(),
      topProducts(from: weekStart, to: today, limit: 5),
    ]);
    return DashboardSnapshot(
      today: results[0] as ReportSummary,
      last7Days: results[1] as List<DailyPoint>,
      lowStockCount: results[2] as int,
      expiringCount: (results[3] as List).length,
      customerDebt: results[4] as int,
      supplierDebt: results[5] as int,
      productCount: results[6] as int,
      topProducts: results[7] as List<TopProduct>,
    );
  }

  Future<int> _lowStockCount() async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS c FROM products
      WHERE deleted_at IS NULL AND is_active = 1
        AND min_stock_milli > 0 AND stock_milli <= min_stock_milli
    ''');
    return (rows.first['c'] as num).toInt();
  }

  Future<List<Map<String, Object?>>> expiringBatches({int days = 30}) async {
    final today = Dates.businessDate();
    final limit = Dates.businessDate(DateTime.now().add(Duration(days: days)));
    return _db.rawQuery(
      '''
      SELECT b.id, b.expiry_date, b.qty_remaining_milli, p.name
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.qty_remaining_milli > 0 AND b.expiry_date IS NOT NULL
        AND b.expiry_date >= ? AND b.expiry_date <= ?
        AND p.deleted_at IS NULL
      ORDER BY b.expiry_date ASC LIMIT 500
    ''',
      [today, limit],
    );
  }

  Future<int> _customerDebt() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(balance_centimes), 0) AS v FROM customers '
      'WHERE deleted_at IS NULL AND balance_centimes > 0',
    );
    return (rows.first['v'] as num).toInt();
  }

  Future<int> _supplierDebt() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(balance_centimes), 0) AS v FROM suppliers '
      'WHERE deleted_at IS NULL AND balance_centimes > 0',
    );
    return (rows.first['v'] as num).toInt();
  }

  Future<int> _productCount() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM products WHERE deleted_at IS NULL AND is_active = 1',
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<List<DailyPoint>> dailySeries(DateTime from, DateTime to) async {
    final start = Dates.businessDate(from);
    final end = Dates.businessDate(to);
    final sales = await _db.rawQuery(
      '''
      SELECT business_date AS d,
             COALESCE(SUM(total_centimes), 0) AS s
      FROM sales WHERE status = 'completed' AND business_date BETWEEN ? AND ?
      GROUP BY business_date
    ''',
      [start, end],
    );
    final returns = await _db.rawQuery(
      '''
      SELECT business_date AS d, COALESCE(SUM(total_centimes), 0) AS r
      FROM sale_returns WHERE business_date BETWEEN ? AND ? GROUP BY business_date
    ''',
      [start, end],
    );
    final purchases = await _db.rawQuery(
      '''
      SELECT business_date AS d, COALESCE(SUM(total_centimes), 0) AS p
      FROM purchases WHERE status = 'completed' AND business_date BETWEEN ? AND ?
      GROUP BY business_date
    ''',
      [start, end],
    );
    final expenses = await _db.rawQuery(
      '''
      SELECT business_date AS d, COALESCE(SUM(amount_centimes), 0) AS e
      FROM expenses WHERE business_date BETWEEN ? AND ? GROUP BY business_date
    ''',
      [start, end],
    );

    final salesMap = {
      for (final r in sales) r['d'] as String: (r['s'] as num).toInt(),
    };
    final returnsMap = {
      for (final r in returns) r['d'] as String: (r['r'] as num).toInt(),
    };
    final purchaseMap = {
      for (final r in purchases) r['d'] as String: (r['p'] as num).toInt(),
    };
    final expenseMap = {
      for (final r in expenses) r['d'] as String: (r['e'] as num).toInt(),
    };

    final points = <DailyPoint>[];
    var day = Dates.startOfDay(from);
    final last = Dates.startOfDay(to);
    while (!day.isAfter(last)) {
      final key = Dates.businessDate(day);
      final salesValue = salesMap[key] ?? 0;
      final returnsValue = returnsMap[key] ?? 0;
      points.add(
        DailyPoint(
          date: day,
          sales: salesValue,
          revenue: salesValue - returnsValue,
          purchases: purchaseMap[key] ?? 0,
          expenses: expenseMap[key] ?? 0,
        ),
      );
      day = day.add(const Duration(days: 1));
    }
    return points;
  }

  Future<List<TopProduct>> topProducts({
    DateTime? from,
    DateTime? to,
    int limit = 10,
  }) async {
    final start = Dates.businessDate(from ?? DateTime.now());
    final end = Dates.businessDate(to ?? from ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT product_id, product_name,
             SUM(qty) AS qty, SUM(total) AS revenue
      FROM (
        SELECT sl.product_id AS product_id, sl.product_name AS product_name,
               sl.qty_milli AS qty, sl.line_total_centimes AS total
        FROM sale_lines sl JOIN sales s ON s.id = sl.sale_id
        WHERE s.status = 'completed' AND s.business_date BETWEEN ? AND ?
        UNION ALL
        SELECT rl.product_id, rl.product_name,
               -rl.qty_milli, -rl.line_total_centimes
        FROM return_lines rl JOIN sale_returns r ON r.id = rl.return_id
        WHERE r.business_date BETWEEN ? AND ?
      )
      GROUP BY product_id, product_name
      HAVING SUM(total) <> 0 OR SUM(qty) <> 0
      ORDER BY revenue DESC
      LIMIT ?
    ''',
      [start, end, start, end, limit],
    );
    return rows
        .map(
          (r) => TopProduct(
            productId: r['product_id'] == null
                ? null
                : (r['product_id'] as num).toInt(),
            name: r['product_name'] as String? ?? '',
            qtyMilli: (r['qty'] as num?)?.toInt() ?? 0,
            revenueCentimes: (r['revenue'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  Future<Map<String, int>> paymentBreakdown({
    DateTime? from,
    DateTime? to,
  }) async {
    final start = Dates.businessDate(from ?? DateTime.now());
    final end = Dates.businessDate(to ?? from ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT payment_method, COALESCE(SUM(paid_centimes), 0) AS amount
      FROM sales WHERE status = 'completed' AND business_date BETWEEN ? AND ?
      GROUP BY payment_method
    ''',
      [start, end],
    );
    return {
      for (final row in rows)
        row['payment_method'] as String? ?? 'other': (row['amount'] as num)
            .toInt(),
    };
  }

  Future<Map<String, int>> expenseByCategory({
    DateTime? from,
    DateTime? to,
  }) async {
    final start = Dates.businessDate(from ?? DateTime.now());
    final end = Dates.businessDate(to ?? from ?? DateTime.now());
    final rows = await _db.rawQuery(
      '''
      SELECT category, COALESCE(SUM(amount_centimes), 0) AS amount
      FROM expenses WHERE business_date BETWEEN ? AND ? GROUP BY category
      ORDER BY amount DESC
    ''',
      [start, end],
    );
    return {
      for (final row in rows)
        (row['category'] as String? ?? ''): (row['amount'] as num).toInt(),
    };
  }
}
