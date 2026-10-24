import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../../data/models/models.dart';
import '../../data/repositories/audit_service.dart';

class CashBreakdown {
  const CashBreakdown({
    required this.openingCash,
    required this.cashSales,
    required this.customerPayments,
    required this.otherCashIn,
    required this.supplierPayments,
    this.supplierRefunds = 0,
    required this.cashExpenses,
    required this.refundsAndVoids,
  });

  final int openingCash;
  final int cashSales;
  final int customerPayments;
  final int otherCashIn;
  final int supplierPayments;

  /// Cash returned by a supplier, e.g. when a paid purchase is voided.
  final int supplierRefunds;
  final int cashExpenses;
  final int refundsAndVoids;

  int get expectedCash =>
      openingCash +
      cashSales +
      customerPayments +
      otherCashIn +
      supplierRefunds -
      supplierPayments -
      cashExpenses -
      refundsAndVoids;
}

class CashService {
  CashService(this.appDb);
  final AppDatabase appDb;
  Database get _db => appDb.db;

  Future<CashSession?> openSession() async {
    final rows = await _db.query(
      'cash_sessions',
      where: "status = 'open'",
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : CashSession.fromMap(rows.first);
  }

  Future<int> open({required int openingCashCentimes, String? note}) async {
    if (openingCashCentimes < 0) {
      throw ValidationError('Le fond de caisse ne peut pas être négatif.');
    }
    return appDb.transaction((txn) async {
      final existing = await txn.query(
        'cash_sessions',
        where: "status = 'open'",
        limit: 1,
      );
      if (existing.isNotEmpty) {
        throw ConflictError('Une session de caisse est déjà ouverte.');
      }
      final now = Dates.nowMillis();
      final id = await txn.insert('cash_sessions', {
        'opened_at': now,
        'opening_cash_centimes': openingCashCentimes,
        'note': note?.trim(),
        'status': 'open',
      });
      await AuditService(txn).log(
        action: 'open',
        entity: 'cash_session',
        entityId: id,
        details: {'opening_cash': openingCashCentimes},
        reason: note,
      );
      return id;
    });
  }

  Future<CashBreakdown> breakdown(CashSession session, {int? until}) async {
    final end = until ?? Dates.nowMillis();
    final start = session.openedAt;
    Future<int> scalar(String sql, List<Object?> args) async {
      final rows = await _db.rawQuery(sql, args);
      return (rows.first.values.first as num?)?.toInt() ?? 0;
    }

    final cashSales = await scalar(
      '''
      SELECT COALESCE(SUM(
        paid_centimes - COALESCE((
          SELECT SUM(p.amount_centimes) FROM payments p
          WHERE p.sale_id = sales.id AND p.direction = 'in'
        ), 0)
      ), 0) FROM sales
      WHERE payment_method = 'cash'
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final customerPayments = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
      WHERE direction = 'in' AND method = 'cash'
        AND party_type = 'customer'
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final otherCashIn = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
      WHERE direction = 'in' AND method = 'cash'
        AND party_type NOT IN ('customer', 'supplier')
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final supplierPayments = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
      WHERE direction = 'out' AND method = 'cash'
        AND party_type = 'supplier'
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final supplierRefunds = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
      WHERE direction = 'in' AND method = 'cash'
        AND party_type = 'supplier'
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final refundsAndVoids = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
      WHERE direction = 'out' AND method = 'cash'
        AND party_type = 'cash'
        AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );
    final expenses = await scalar(
      '''
      SELECT COALESCE(SUM(amount_centimes), 0) FROM expenses
      WHERE method = 'cash' AND created_at >= ? AND created_at <= ?
    ''',
      [start, end],
    );

    return CashBreakdown(
      openingCash: session.openingCashCentimes,
      cashSales: cashSales,
      customerPayments: customerPayments,
      otherCashIn: otherCashIn,
      supplierPayments: supplierPayments,
      supplierRefunds: supplierRefunds,
      cashExpenses: expenses,
      refundsAndVoids: refundsAndVoids,
    );
  }

  Future<CashSession> close({
    required int countedCashCentimes,
    String? note,
  }) async {
    if (countedCashCentimes < 0) {
      throw ValidationError('Le montant compté est invalide.');
    }
    return appDb.transaction((txn) async {
      final rows = await txn.query(
        'cash_sessions',
        where: "status = 'open'",
        orderBy: 'id DESC',
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Aucune session ouverte.');
      final session = CashSession.fromMap(rows.first);
      final end = Dates.nowMillis();
      // Compute using the transaction executor for consistency.
      Future<int> scalar(String sql, List<Object?> args) async {
        final r = await txn.rawQuery(sql, args);
        return (r.first.values.first as num?)?.toInt() ?? 0;
      }

      final start = session.openedAt;
      final cashSales = await scalar(
        '''
        SELECT COALESCE(SUM(
          paid_centimes - COALESCE((
            SELECT SUM(p.amount_centimes) FROM payments p
            WHERE p.sale_id = sales.id AND p.direction = 'in'
          ), 0)
        ), 0) FROM sales
        WHERE payment_method = 'cash'
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final customerPayments = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
        WHERE direction = 'in' AND method = 'cash'
          AND party_type = 'customer'
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final otherCashIn = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
        WHERE direction = 'in' AND method = 'cash'
          AND party_type NOT IN ('customer', 'supplier')
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final supplierPayments = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
        WHERE direction = 'out' AND method = 'cash'
          AND party_type = 'supplier'
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final supplierRefunds = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
        WHERE direction = 'in' AND method = 'cash'
          AND party_type = 'supplier'
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final refunds = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM payments
        WHERE direction = 'out' AND method = 'cash'
          AND party_type = 'cash'
          AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final expenses = await scalar(
        '''
        SELECT COALESCE(SUM(amount_centimes), 0) FROM expenses
        WHERE method = 'cash' AND created_at >= ? AND created_at <= ?
      ''',
        [start, end],
      );
      final expected =
          session.openingCashCentimes +
          cashSales +
          customerPayments +
          otherCashIn +
          supplierRefunds -
          supplierPayments -
          expenses -
          refunds;
      final difference = countedCashCentimes - expected;
      await txn.update(
        'cash_sessions',
        {
          'closed_at': end,
          'expected_cash_centimes': expected,
          'counted_cash_centimes': countedCashCentimes,
          'difference_centimes': difference,
          'note': note ?? session.note,
          'status': 'closed',
        },
        where: 'id = ?',
        whereArgs: [session.id],
      );
      await AuditService(txn).log(
        action: 'close',
        entity: 'cash_session',
        entityId: session.id,
        details: {
          'opening': session.openingCashCentimes,
          'expected': expected,
          'counted': countedCashCentimes,
          'difference': difference,
          'cash_sales': cashSales,
          'cash_expenses': expenses,
          'supplier_payments': supplierPayments,
          'supplier_refunds': supplierRefunds,
          'refunds': refunds,
        },
        reason: note,
      );
      final updated = await txn.query(
        'cash_sessions',
        where: 'id = ?',
        whereArgs: [session.id],
        limit: 1,
      );
      return CashSession.fromMap(updated.first);
    });
  }

  Future<List<CashSession>> history({int limit = 60}) async {
    final rows = await _db.query(
      'cash_sessions',
      orderBy: 'opened_at DESC',
      limit: limit,
    );
    return rows.map(CashSession.fromMap).toList();
  }
}
