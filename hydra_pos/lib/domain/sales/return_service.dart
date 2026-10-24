import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../../data/models/models.dart';
import '../../data/repositories/audit_service.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/sequence_repository.dart';

class ReturnDraftLine {
  const ReturnDraftLine({required this.saleLineId, required this.qtyMilli});
  final int saleLineId;
  final int qtyMilli;
}

class ReturnService {
  ReturnService(this.appDb, this.inventory, {SequenceRepository? sequences})
    : _sequences = sequences ?? const SequenceRepository();

  final AppDatabase appDb;
  final InventoryRepository inventory;
  final SequenceRepository _sequences;

  Database get _db => appDb.db;

  Future<SaleReturn> returnSale({
    required int saleId,
    required List<ReturnDraftLine> lines,
    required String refundMethod,
    String? note,
  }) async {
    if (lines.isEmpty) throw ValidationError('Aucun article à retourner.');
    if (refundMethod != 'cash' && refundMethod != 'credit') {
      throw ValidationError('Mode de remboursement invalide.');
    }
    final now = DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;

    return appDb.transaction((txn) async {
      final saleRows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (saleRows.isEmpty) throw NotFoundError('Vente introuvable.');
      final sale = Sale.fromMap(saleRows.first);
      if (sale.status != 'completed') {
        throw ValidationError('Impossible de retourner une vente annulée.');
      }
      final saleLineRows = await txn.query(
        'sale_lines',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      final saleLines = {
        for (final row in saleLineRows)
          (row['id'] as num).toInt(): SaleLine.fromMap(row),
      };

      // Already returned quantities, per original line.
      final returnedRows = await txn.rawQuery(
        '''
        SELECT rl.sale_line_id, COALESCE(SUM(rl.qty_milli), 0) AS qty
        FROM return_lines rl
        JOIN sale_returns r ON r.id = rl.return_id
        WHERE r.sale_id = ?
        GROUP BY rl.sale_line_id
      ''',
        [saleId],
      );
      final alreadyReturned = <int, int>{
        for (final row in returnedRows)
          (row['sale_line_id'] as num).toInt(): (row['qty'] as num).toInt(),
      };

      final returnNo = await _sequences.next(txn, 'return', prefix: 'R');
      var total = 0;
      final prepared = <Map<String, Object?>>[];
      for (final draft in lines) {
        final sold = saleLines[draft.saleLineId];
        if (sold == null) throw ValidationError('Ligne de vente invalide.');
        if (draft.qtyMilli <= 0) continue;
        final already = alreadyReturned[draft.saleLineId] ?? 0;
        if (draft.qtyMilli > sold.qtyMilli - already) {
          throw ValidationError(
            'La quantité retournée dépasse la quantité vendue pour '
            '« ${sold.productName} ».',
          );
        }
        final amount =
            ((sold.lineTotalCentimes * draft.qtyMilli) + sold.qtyMilli ~/ 2) ~/
            sold.qtyMilli;
        total += amount;
        prepared.add({
          'sale_line_id': sold.id,
          'product_id': sold.productId,
          'product_name': sold.productName,
          'qty_milli': draft.qtyMilli,
          'unit_price_centimes': sold.unitPriceCentimes,
          'unit_cost_centimes': sold.unitCostCentimes,
          'line_total_centimes': amount,
        });
        alreadyReturned[draft.saleLineId] = already + draft.qtyMilli;
      }
      if (prepared.isEmpty) throw ValidationError('Aucun article à retourner.');
      if (total > sale.totalCentimes) total = sale.totalCentimes;

      if (refundMethod == 'credit' && sale.customerId == null) {
        throw ValidationError(
          'Un remboursement en avoir nécessite un client identifié.',
        );
      }
      if (refundMethod == 'cash' && sale.dueCentimes > 0) {
        throw ValidationError(
          'Cette vente a un reste à payer : remboursez en avoir (crédit).',
        );
      }

      final returnId = await txn.insert('sale_returns', {
        'return_no': returnNo,
        'sale_id': saleId,
        'customer_id': sale.customerId,
        'total_centimes': total,
        'refund_method': refundMethod,
        'note': note,
        'business_date': Dates.businessDate(now),
        'created_at': nowMillis,
      });

      for (final line in prepared) {
        await txn.insert('return_lines', {...line, 'return_id': returnId});
        final productId = line['product_id'] as int?;
        if (productId == null) continue;
        final qty = line['qty_milli'] as int;
        final cost = line['unit_cost_centimes'] as int;
        await inventory.applyDelta(
          txn,
          productId: productId,
          deltaMilli: qty,
          type: 'sale_return',
          reason: 'Retour $returnNo',
          unitCostCentimes: cost,
          refType: 'sale_return',
          refId: returnId,
          audit: false,
          businessDate: Dates.businessDate(now),
        );
        await inventory.restoreSaleLineBatches(
          txn,
          saleLineId: line['sale_line_id'] as int,
          productId: productId,
          qtyMilli: qty,
          unitCostCentimes: cost,
        );
      }

      if (refundMethod == 'cash') {
        await txn.insert('payments', {
          'party_type': 'cash',
          'party_id': 0,
          'direction': 'out',
          'amount_centimes': total,
          'method': 'cash',
          'reference': returnNo,
          'note': note,
          'business_date': Dates.businessDate(now),
          'created_at': nowMillis,
          'return_id': returnId,
        });
      } else {
        final customerId = sale.customerId!;
        await txn.rawUpdate(
          'UPDATE customers SET balance_centimes = balance_centimes - ?, '
          'updated_at = ? WHERE id = ?',
          [total, nowMillis, customerId],
        );
        await txn.insert('ledger_entries', {
          'party_type': 'customer',
          'party_id': customerId,
          'entry_type': 'return_credit',
          'amount_centimes': -total,
          'ref_type': 'sale_return',
          'ref_id': returnId,
          'note': returnNo,
          'business_date': Dates.businessDate(now),
          'created_at': nowMillis,
        });
      }

      await AuditService(txn).log(
        action: 'return',
        entity: 'sale',
        entityId: saleId,
        details: {
          'return_no': returnNo,
          'total': total,
          'method': refundMethod,
          'lines': prepared.length,
        },
        reason: note,
      );

      final header = await txn.query(
        'sale_returns',
        where: 'id = ?',
        whereArgs: [returnId],
        limit: 1,
      );
      final lineRows = await txn.query(
        'return_lines',
        where: 'return_id = ?',
        whereArgs: [returnId],
      );
      return SaleReturn.fromMap(header.first)
          .copyWithLines(lineRows.map(ReturnLine.fromMap).toList());
    });
  }

  /// Quantity already returned, keyed by sale line id.
  Future<Map<int, int>> returnedQuantities(int saleId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT rl.sale_line_id AS line_id, COALESCE(SUM(rl.qty_milli), 0) AS qty
      FROM return_lines rl JOIN sale_returns r ON r.id = rl.return_id
      WHERE r.sale_id = ? GROUP BY rl.sale_line_id
    ''',
      [saleId],
    );
    return {
      for (final row in rows)
        (row['line_id'] as num).toInt(): (row['qty'] as num).toInt(),
    };
  }

  Future<List<SaleReturn>> returnsForSale(int saleId) async {
    final rows = await _db.query(
      'sale_returns',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'created_at DESC',
    );
    final result = <SaleReturn>[];
    for (final row in rows) {
      final r = SaleReturn.fromMap(row);
      final lines = await _db.query(
        'return_lines',
        where: 'return_id = ?',
        whereArgs: [r.id],
      );
      result.add(r.copyWithLines(lines.map(ReturnLine.fromMap).toList()));
    }
    return result;
  }

  Future<List<SaleReturn>> list({
    DateTime? from,
    DateTime? to,
    int limit = 100,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('business_date >= ?');
      args.add(Dates.businessDate(from));
    }
    if (to != null) {
      where.add('business_date <= ?');
      args.add(Dates.businessDate(to));
    }
    final rows = await _db.query(
      'sale_returns',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(SaleReturn.fromMap).toList();
  }

  Future<int> sumReturns({DateTime? from, DateTime? to}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('business_date >= ?');
      args.add(Dates.businessDate(from));
    }
    if (to != null) {
      where.add('business_date <= ?');
      args.add(Dates.businessDate(to));
    }
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(total_centimes), 0) AS total FROM sale_returns
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
    ''', args);
    return (rows.first['total'] as num).toInt();
  }
}

extension SaleReturnLines on SaleReturn {
  SaleReturn copyWithLines(List<ReturnLine> lines) => SaleReturn(
    id: id,
    returnNo: returnNo,
    saleId: saleId,
    customerId: customerId,
    totalCentimes: totalCentimes,
    refundMethod: refundMethod,
    note: note,
    businessDate: businessDate,
    createdAt: createdAt,
    lines: lines,
  );
}
