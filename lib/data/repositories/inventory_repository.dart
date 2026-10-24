import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../models/models.dart';
import 'audit_service.dart';

class StocktakeEntry {
  const StocktakeEntry({
    required this.productId,
    required this.countedMilli,
    this.note,
  });
  final int productId;
  final int countedMilli;
  final String? note;
}

/// A quantity taken from one stock batch, used to trace FEFO sales.
class BatchConsumption {
  const BatchConsumption({required this.batchId, required this.qtyMilli});
  final int batchId;
  final int qtyMilli;
}

class InventoryRepository {
  InventoryRepository(this.appDb);
  final AppDatabase appDb;

  Database get _db => appDb.db;

  Future<void> adjustStock({
    required int productId,
    required int deltaMilli,
    required String reason,
    String type = 'adjustment',
    int? unitCostCentimes,
    String? refType,
    int? refId,
    bool allowNegative = false,
    String? expiryDate,
    String? batchNo,
    bool createBatch = true,
  }) async {
    if (deltaMilli == 0) return;
    if (reason.trim().isEmpty) {
      throw ValidationError('Le motif du mouvement de stock est obligatoire.');
    }
    await appDb.transaction((txn) async {
      await applyDelta(
        txn,
        productId: productId,
        deltaMilli: deltaMilli,
        type: type,
        reason: reason.trim(),
        unitCostCentimes: unitCostCentimes,
        refType: refType,
        refId: refId,
        allowNegative: allowNegative,
      );
      // Receiving stock (positive adjustment) creates a traceable batch so its
      // expiry date is never lost, even outside the purchase workflow.
      if (createBatch && deltaMilli > 0 && type != 'sale_return') {
        final costRows = await txn.query(
          'products',
          columns: ['cost_centimes'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        await addBatch(
          txn,
          productId: productId,
          purchaseId: null,
          batchNo: batchNo,
          expiryDate: expiryDate,
          qtyMilli: deltaMilli,
          unitCostCentimes:
              unitCostCentimes ??
              (costRows.isEmpty
                  ? 0
                  : (costRows.first['cost_centimes'] as num).toInt()),
        );
      }
    });
  }

  /// Applies a stock delta and writes its movement/audit row inside [txn].
  Future<void> applyDelta(
    DatabaseExecutor txn, {
    required int productId,
    required int deltaMilli,
    required String type,
    required String reason,
    int? unitCostCentimes,
    String? refType,
    int? refId,
    bool allowNegative = false,
    bool audit = true,
    String? businessDate,
  }) async {
    final rows = await txn.query(
      'products',
      columns: ['id', 'name', 'stock_milli', 'cost_centimes'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Produit introuvable.');
    final current = (rows.first['stock_milli'] as num).toInt();
    final updated = current + deltaMilli;
    if (updated < 0 && !allowNegative) {
      throw ValidationError(
        'Stock insuffisant pour « ${rows.first['name']} » '
        '(disponible: ${current / 1000}).',
      );
    }
    final now = Dates.nowMillis();
    await txn.update(
      'products',
      {'stock_milli': updated, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [productId],
    );
    await txn.insert('stock_movements', {
      'product_id': productId,
      'type': type,
      'qty_delta_milli': deltaMilli,
      'unit_cost_centimes': unitCostCentimes ?? rows.first['cost_centimes'],
      'ref_type': refType,
      'ref_id': refId,
      'reason': reason,
      'business_date': businessDate ?? Dates.businessDate(),
      'created_at': now,
    });
    if (audit) {
      await AuditService(txn).log(
        action: type,
        entity: 'product',
        entityId: productId,
        details: {
          'name': rows.first['name'],
          'before': current,
          'delta': deltaMilli,
          'after': updated,
          'ref_type': refType,
          'ref_id': refId,
        },
        reason: reason,
      );
    }
  }

  Future<void> setCountedStock({
    required int productId,
    required int countedMilli,
    required String reason,
    String? expiryDate,
    String? batchNo,
  }) async {
    if (countedMilli < 0) {
      throw ValidationError('Le stock compté est invalide.');
    }
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'products',
        columns: ['stock_milli', 'name', 'cost_centimes'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Produit introuvable.');
      final current = (rows.first['stock_milli'] as num).toInt();
      final delta = countedMilli - current;
      if (delta == 0) {
        await AuditService(txn).log(
          action: 'stocktake',
          entity: 'product',
          entityId: productId,
          details: {'before': current, 'after': countedMilli, 'delta': 0},
          reason: reason,
        );
        return;
      }
      await applyDelta(
        txn,
        productId: productId,
        deltaMilli: delta,
        type: 'stocktake',
        reason: reason,
        audit: false,
      );
      // A positive count is stock entering the shop: keep the declared expiry
      // date and lot number on a dedicated batch.
      if (delta > 0) {
        await addBatch(
          txn,
          productId: productId,
          batchNo: batchNo,
          expiryDate: expiryDate,
          qtyMilli: delta,
          unitCostCentimes: (rows.first['cost_centimes'] as num).toInt(),
        );
      }
      await AuditService(txn).log(
        action: 'stocktake',
        entity: 'product',
        entityId: productId,
        details: {
          'before': current,
          'after': countedMilli,
          'delta': delta,
          'batch_no': batchNo,
          'expiry_date': expiryDate,
        },
        reason: reason,
      );
    });
  }

  /// Confirms a whole counting session atomically.
  Future<int> confirmStocktake(
    List<StocktakeEntry> entries,
    String reason,
  ) async {
    if (entries.isEmpty) return 0;
    if (reason.trim().isEmpty) {
      throw ValidationError('Le motif de l\'inventaire est obligatoire.');
    }
    return appDb.transaction((txn) async {
      var adjusted = 0;
      for (final entry in entries) {
        final rows = await txn.query(
          'products',
          columns: ['stock_milli', 'name'],
          where: 'id = ?',
          whereArgs: [entry.productId],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final current = (rows.first['stock_milli'] as num).toInt();
        final delta = entry.countedMilli - current;
        final entryReason = entry.note?.trim().isNotEmpty == true
            ? entry.note!.trim()
            : reason;
        if (delta == 0) {
          await AuditService(txn).log(
            action: 'stocktake',
            entity: 'product',
            entityId: entry.productId,
            details: {
              'before': current,
              'after': entry.countedMilli,
              'delta': 0,
            },
            reason: entryReason,
          );
          continue;
        }
        await applyDelta(
          txn,
          productId: entry.productId,
          deltaMilli: delta,
          type: 'stocktake',
          reason: entryReason,
          audit: false,
        );
        await AuditService(txn).log(
          action: 'stocktake',
          entity: 'product',
          entityId: entry.productId,
          details: {
            'before': current,
            'counted': entry.countedMilli,
            'delta': delta,
          },
          reason: entryReason,
        );
        adjusted++;
      }
      return adjusted;
    });
  }

  Future<List<StockMovement>> movements(
    int productId, {
    int limit = 100,
  }) async {
    final rows = await _db.rawQuery(
      '''
      SELECT m.*, p.name AS product_name
      FROM stock_movements m LEFT JOIN products p ON p.id = m.product_id
      WHERE m.product_id = ?
      ORDER BY m.created_at DESC LIMIT ?
    ''',
      [productId, limit],
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<List<StockMovement>> recentMovements({int limit = 200}) async {
    final rows = await _db.rawQuery(
      '''
      SELECT m.*, p.name AS product_name
      FROM stock_movements m LEFT JOIN products p ON p.id = m.product_id
      ORDER BY m.created_at DESC LIMIT ?
    ''',
      [limit],
    );
    return rows.map(StockMovement.fromMap).toList();
  }

  Future<List<ExpiringBatch>> expiringBatches({int days = 30}) async {
    final today = Dates.businessDate();
    final limitDate = Dates.businessDate(
      DateTime.now().add(Duration(days: days)),
    );
    final rows = await _db.rawQuery(
      '''
      SELECT b.id, b.product_id, b.batch_no, b.expiry_date,
             b.qty_remaining_milli, p.name AS product_name, p.base_unit
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.qty_remaining_milli > 0
        AND b.expiry_date IS NOT NULL
        AND b.expiry_date <= ?
        AND b.expiry_date >= ?
        AND p.deleted_at IS NULL
      ORDER BY b.expiry_date ASC
      LIMIT 500
    ''',
      [limitDate, today],
    );
    return rows.map(ExpiringBatch.fromMap).toList();
  }

  /// Batches already past their expiry date that still hold stock.
  Future<List<ExpiringBatch>> expiredBatches() async {
    final rows = await _db.rawQuery(
      '''
      SELECT b.id, b.product_id, b.batch_no, b.expiry_date,
             b.qty_remaining_milli, p.name AS product_name, p.base_unit
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.qty_remaining_milli > 0
        AND b.expiry_date IS NOT NULL
        AND b.expiry_date < ?
        AND p.deleted_at IS NULL
      ORDER BY b.expiry_date ASC
      LIMIT 500
    ''',
      [Dates.businessDate()],
    );
    return rows.map(ExpiringBatch.fromMap).toList();
  }

  /// Batches without an expiry date, so the user can complete them.
  Future<List<ExpiringBatch>> missingExpiryBatches() async {
    final rows = await _db.rawQuery('''
      SELECT b.id, b.product_id, b.batch_no, b.expiry_date,
             b.qty_remaining_milli, p.name AS product_name, p.base_unit
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.qty_remaining_milli > 0
        AND b.expiry_date IS NULL
        AND p.deleted_at IS NULL
      ORDER BY p.name ASC
      LIMIT 500
    ''');
    return rows.map(ExpiringBatch.fromMap).toList();
  }

  Future<List<ExpiringBatch>> batchesForProduct(int productId) async {
    final rows = await _db.rawQuery(
      '''
      SELECT b.id, b.product_id, b.batch_no, b.expiry_date,
             b.qty_remaining_milli, p.name AS product_name, p.base_unit
      FROM batches b JOIN products p ON p.id = b.product_id
      WHERE b.product_id = ? AND b.qty_remaining_milli > 0
      ORDER BY CASE WHEN b.expiry_date IS NULL THEN 1 ELSE 0 END,
               b.expiry_date ASC, b.id ASC
    ''',
      [productId],
    );
    return rows.map(ExpiringBatch.fromMap).toList();
  }

  Future<int> lowStockCount() async {
    final rows = await _db.rawQuery('''
      SELECT COUNT(*) AS c FROM products
      WHERE deleted_at IS NULL AND is_active = 1
        AND min_stock_milli > 0 AND stock_milli <= min_stock_milli
    ''');
    return (rows.first['c'] as num).toInt();
  }

  /// Decrements remaining quantities on the earliest-expiring batches.
  /// Batches never block a sale; the product stock is authoritative.
  ///
  /// When [saleLineId] is provided, the returned allocations are persisted in
  /// `sale_line_batches` so returns and cancellations can restore the exact
  /// expiry batches that were sold.
  Future<List<BatchConsumption>> consumeBatchesFefo(
    DatabaseExecutor txn,
    int productId,
    int qtyMilli, {
    int? saleLineId,
  }) async {
    var remaining = qtyMilli;
    final used = <BatchConsumption>[];
    if (remaining <= 0) return used;
    final rows = await txn.query(
      'batches',
      columns: ['id', 'qty_remaining_milli'],
      where: 'product_id = ? AND qty_remaining_milli > 0',
      whereArgs: [productId],
      orderBy: 'CASE WHEN expiry_date IS NULL THEN 1 ELSE 0 END, expiry_date ASC, id ASC',
    );
    for (final row in rows) {
      if (remaining <= 0) break;
      final available = (row['qty_remaining_milli'] as num).toInt();
      final usedQty = available < remaining ? available : remaining;
      await txn.update(
        'batches',
        {'qty_remaining_milli': available - usedQty},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
      final batchId = (row['id'] as num).toInt();
      used.add(BatchConsumption(batchId: batchId, qtyMilli: usedQty));
      if (saleLineId != null) {
        await txn.insert('sale_line_batches', {
          'sale_line_id': saleLineId,
          'batch_id': batchId,
          'qty_milli': usedQty,
          'returned_milli': 0,
          'created_at': Dates.nowMillis(),
        });
      }
      remaining -= usedQty;
    }
    return used;
  }

  /// Restores stock to the batches that were consumed by [saleLineId].
  ///
  /// Falls back to a new untracked batch for legacy sale lines that predate
  /// batch allocations, so stock quantities always stay accurate.
  Future<void> restoreSaleLineBatches(
    DatabaseExecutor txn, {
    required int saleLineId,
    required int productId,
    required int qtyMilli,
    required int unitCostCentimes,
  }) async {
    var remaining = qtyMilli;
    if (remaining <= 0) return;
    final allocations = await txn.query(
      'sale_line_batches',
      columns: ['id', 'batch_id', 'qty_milli', 'returned_milli'],
      where: 'sale_line_id = ?',
      whereArgs: [saleLineId],
      orderBy: 'id ASC',
    );
    for (final row in allocations) {
      if (remaining <= 0) break;
      final allocated = (row['qty_milli'] as num).toInt();
      final returned = (row['returned_milli'] as num).toInt();
      final available = allocated - returned;
      if (available <= 0) continue;
      final restore = available < remaining ? available : remaining;
      await txn.rawUpdate(
        'UPDATE batches SET qty_remaining_milli = qty_remaining_milli + ? '
        'WHERE id = ?',
        [restore, row['batch_id']],
      );
      await txn.rawUpdate(
        'UPDATE sale_line_batches SET returned_milli = returned_milli + ? '
        'WHERE id = ?',
        [restore, row['id']],
      );
      remaining -= restore;
    }
    if (remaining > 0) {
      await addBatch(
        txn,
        productId: productId,
        qtyMilli: remaining,
        unitCostCentimes: unitCostCentimes,
      );
    }
  }

  /// Records expired or damaged stock disposal for one batch. The quantity is
  /// removed from both the batch and the product stock, with a movement and an
  /// audit entry so the loss is traceable.
  Future<void> disposeBatch({
    required int batchId,
    required int qtyMilli,
    required String reason,
    String type = 'disposal',
  }) async {
    if (qtyMilli <= 0) {
      throw ValidationError('La quantité à jeter est invalide.');
    }
    if (reason.trim().isEmpty) {
      throw ValidationError('Le motif de la mise au rebut est obligatoire.');
    }
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'batches',
        columns: [
          'id',
          'product_id',
          'batch_no',
          'expiry_date',
          'qty_remaining_milli',
          'unit_cost_centimes',
        ],
        where: 'id = ?',
        whereArgs: [batchId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Lot introuvable.');
      final batch = rows.first;
      final available = (batch['qty_remaining_milli'] as num).toInt();
      if (qtyMilli > available) {
        throw ValidationError(
          'La quantité dépasse le reste du lot ($available).',
        );
      }
      final productId = (batch['product_id'] as num).toInt();
      final cost = (batch['unit_cost_centimes'] as num).toInt();
      await txn.update(
        'batches',
        {'qty_remaining_milli': available - qtyMilli},
        where: 'id = ?',
        whereArgs: [batchId],
      );
      final productRows = await txn.query(
        'products',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      final productName = productRows.isEmpty
          ? ''
          : (productRows.first['name'] as String? ?? '');
      await applyDelta(
        txn,
        productId: productId,
        deltaMilli: -qtyMilli,
        type: type,
        reason: reason.trim(),
        unitCostCentimes: cost,
        refType: 'batch',
        refId: batchId,
        allowNegative: true,
        audit: false,
      );
      await AuditService(txn).log(
        action: type,
        entity: 'batch',
        entityId: batchId,
        details: {
          'product_id': productId,
          'product_name': productName,
          'batch_no': batch['batch_no'],
          'expiry_date': batch['expiry_date'],
          'qty_milli': qtyMilli,
          'unit_cost_centimes': cost,
        },
        reason: reason.trim(),
      );
    });
  }

  Future<int> addBatch(
    DatabaseExecutor txn, {
    required int productId,
    int? purchaseId,
    String? batchNo,
    String? expiryDate,
    required int qtyMilli,
    required int unitCostCentimes,
  }) async {
    if (qtyMilli <= 0) return 0;
    return txn.insert('batches', {
      'product_id': productId,
      'purchase_id': purchaseId,
      'batch_no': (batchNo?.trim().isEmpty ?? true) ? null : batchNo!.trim(),
      'expiry_date': (expiryDate?.trim().isEmpty ?? true)
          ? null
          : expiryDate!.trim(),
      'qty_received_milli': qtyMilli,
      'qty_remaining_milli': qtyMilli,
      'unit_cost_centimes': unitCostCentimes,
      'created_at': Dates.nowMillis(),
    });
  }
}
