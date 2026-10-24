import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../../core/money.dart';
import '../../data/models/models.dart';
import '../../data/repositories/audit_service.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../data/repositories/sequence_repository.dart';

class PurchaseDraftLine {
  const PurchaseDraftLine({
    required this.product,
    this.unit,
    required this.qtyMilli,
    required this.unitCostCentimes,
    this.expiryDate,
    this.batchNo,
    this.lineTotalOverrideCentimes,
  });

  final Product product;
  final ProductUnit? unit;
  final int qtyMilli;
  final int unitCostCentimes;
  final String? expiryDate;
  final String? batchNo;

  /// Exact total for package purchases (see [SaleDraftLine]).
  final int? lineTotalOverrideCentimes;

  int get lineTotalCentimes =>
      lineTotalOverrideCentimes ??
      Money.lineTotal(qtyMilli: qtyMilli, unitPriceCentimes: unitCostCentimes);
  String get unitName => unit?.name ?? '';
  int get factorMilli => unit?.factorMilli ?? 1000;
}

class PurchaseDraft {
  const PurchaseDraft({
    this.supplierId,
    required this.lines,
    this.discountCentimes = 0,
    required this.paidCentimes,
    required this.paymentMethod,
    this.note,
    this.at,
  });

  final int? supplierId;
  final List<PurchaseDraftLine> lines;
  final int discountCentimes;
  final int paidCentimes;
  final String paymentMethod;
  final String? note;
  final DateTime? at;

  int get subtotalCentimes =>
      lines.fold(0, (sum, line) => sum + line.lineTotalCentimes);
  int get totalCentimes => max(0, subtotalCentimes - discountCentimes);
}

class PurchaseService {
  PurchaseService(this.appDb, this.inventory, {SequenceRepository? sequences})
    : _sequences = sequences ?? const SequenceRepository();

  final AppDatabase appDb;
  final InventoryRepository inventory;
  final SequenceRepository _sequences;

  Database get _db => appDb.db;

  Future<Purchase> completePurchase(PurchaseDraft draft) async {
    if (draft.lines.isEmpty) {
      throw ValidationError('Ajoutez au moins un produit.');
    }
    if (draft.discountCentimes < 0 || draft.paidCentimes < 0) {
      throw ValidationError('Montant invalide.');
    }
    if (draft.discountCentimes > draft.subtotalCentimes) {
      throw ValidationError('La remise dépasse le sous-total.');
    }
    if (draft.paidCentimes > draft.totalCentimes) {
      throw ValidationError('Le montant payé dépasse le total.');
    }
    final due = draft.totalCentimes - draft.paidCentimes;
    if (due > 0 && draft.supplierId == null) {
      throw ValidationError('Sélectionnez un fournisseur pour le crédit.');
    }
    for (final line in draft.lines) {
      if (line.qtyMilli <= 0) {
        throw ValidationError(
          'Quantité invalide pour « ${line.product.name} ».',
        );
      }
      if (line.unitCostCentimes < 0) {
        throw ValidationError('Coût invalide pour « ${line.product.name} ».');
      }
      if (line.lineTotalOverrideCentimes != null &&
          line.lineTotalOverrideCentimes! < 0) {
        throw ValidationError('Total de ligne invalide.');
      }
    }

    final now = draft.at ?? DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;
    final businessDate = Dates.businessDate(now);

    return appDb.transaction((txn) async {
      String? supplierName;
      if (draft.supplierId != null) {
        final rows = await txn.query(
          'suppliers',
          columns: ['name'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [draft.supplierId],
          limit: 1,
        );
        if (rows.isEmpty) throw NotFoundError('Fournisseur introuvable.');
        supplierName = rows.first['name'] as String;
      }

      final refNo = await _sequences.next(txn, 'purchase', prefix: 'A');
      final purchaseId = await txn.insert('purchases', {
        'ref_no': refNo,
        'supplier_id': draft.supplierId,
        'supplier_name': supplierName,
        'subtotal_centimes': draft.subtotalCentimes,
        'discount_centimes': draft.discountCentimes,
        'total_centimes': draft.totalCentimes,
        'paid_centimes': draft.paidCentimes,
        'due_centimes': due,
        'payment_method': draft.paidCentimes == 0 && due > 0
            ? 'credit'
            : draft.paymentMethod,
        'status': 'completed',
        'note': draft.note,
        'business_date': businessDate,
        'created_at': nowMillis,
      });

      for (final line in draft.lines) {
        final rows = await txn.query(
          'products',
          columns: ['stock_milli', 'cost_centimes'],
          where: 'id = ?',
          whereArgs: [line.product.id],
          limit: 1,
        );
        if (rows.isEmpty) throw NotFoundError('Produit introuvable.');
        final stock = (rows.first['stock_milli'] as num).toInt();
        final oldCost = (rows.first['cost_centimes'] as num).toInt();
        // Weighted-average purchase cost per base unit. The exact line total
        // is used so package purchases do not lose centimes to rounding.
        final totalMilli = stock + line.qtyMilli;
        var newCost = oldCost;
        if (totalMilli > 0) {
          final oldValue = (stock * oldCost) ~/ 1000;
          final newValue = oldValue + line.lineTotalCentimes;
          newCost = (newValue * 1000 + totalMilli ~/ 2) ~/ totalMilli;
        }
        await txn.update(
          'products',
          {'cost_centimes': newCost, 'updated_at': nowMillis},
          where: 'id = ?',
          whereArgs: [line.product.id],
        );
        await inventory.applyDelta(
          txn,
          productId: line.product.id,
          deltaMilli: line.qtyMilli,
          type: 'purchase',
          reason: 'Achat $refNo',
          unitCostCentimes: line.unitCostCentimes,
          refType: 'purchase',
          refId: purchaseId,
          audit: false,
          businessDate: businessDate,
        );
        final batchId = await inventory.addBatch(
          txn,
          productId: line.product.id,
          purchaseId: purchaseId,
          batchNo: line.batchNo,
          expiryDate: line.expiryDate,
          qtyMilli: line.qtyMilli,
          unitCostCentimes: line.unitCostCentimes,
        );
        await txn.insert('purchase_lines', {
          'purchase_id': purchaseId,
          'product_id': line.product.id,
          'product_name': line.product.name,
          'unit_name': line.unitName,
          'factor_milli': line.factorMilli,
          'qty_milli': line.qtyMilli,
          'unit_cost_centimes': line.unitCostCentimes,
          'line_total_centimes': line.lineTotalCentimes,
          'expiry_date': line.expiryDate,
          'batch_no': line.batchNo,
          'batch_id': batchId,
          'created_at': nowMillis,
        });
      }

      if (draft.paidCentimes > 0) {
        await txn.insert('payments', {
          'party_type': 'supplier',
          'party_id': draft.supplierId ?? 0,
          'direction': 'out',
          'amount_centimes': draft.paidCentimes,
          'method': draft.paymentMethod,
          'reference': refNo,
          'note': draft.note,
          'business_date': businessDate,
          'created_at': nowMillis,
          'purchase_id': purchaseId,
        });
      }
      if (due > 0 && draft.supplierId != null) {
        await txn.rawUpdate(
          'UPDATE suppliers SET balance_centimes = balance_centimes + ?, '
          'updated_at = ? WHERE id = ?',
          [due, nowMillis, draft.supplierId],
        );
        await txn.insert('ledger_entries', {
          'party_type': 'supplier',
          'party_id': draft.supplierId,
          'entry_type': 'purchase_due',
          'amount_centimes': due,
          'ref_type': 'purchase',
          'ref_id': purchaseId,
          'note': refNo,
          'business_date': businessDate,
          'created_at': nowMillis,
        });
      }

      await AuditService(txn).log(
        action: 'purchase',
        entity: 'purchase',
        entityId: purchaseId,
        details: {
          'ref_no': refNo,
          'total': draft.totalCentimes,
          'paid': draft.paidCentimes,
          'due': due,
        },
      );

      return _load(txn, purchaseId);
    });
  }

  Future<Purchase> _load(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'purchases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Achat introuvable.');
    final lines = await txn.query(
      'purchase_lines',
      where: 'purchase_id = ?',
      whereArgs: [id],
      orderBy: 'id ASC',
    );
    return Purchase.fromMap(rows.first)
        .copyWith(lines: lines.map(PurchaseLine.fromMap).toList());
  }

  Future<Purchase?> findById(int id) async {
    final rows = await _db.query(
      'purchases',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _load(_db, id);
  }

  Future<List<Purchase>> list({
    DateTime? from,
    DateTime? to,
    String? query,
    int limit = 200,
    bool includeVoided = true,
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
    if (!includeVoided) where.add("status = 'completed'");
    final q = query?.trim() ?? '';
    if (q.isNotEmpty) {
      where.add('(ref_no LIKE ? OR IFNULL(supplier_name, \'\') LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    final rows = await _db.query(
      'purchases',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Purchase.fromMap).toList();
  }

  Future<List<Purchase>> purchasesForSupplier(
    int supplierId, {
    int limit = 100,
  }) async {
    final rows = await _db.query(
      'purchases',
      where: 'supplier_id = ?',
      whereArgs: [supplierId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Purchase.fromMap).toList();
  }

  Future<List<Payment>> paymentsForPurchase(
    int purchaseId, {
    int limit = 100,
  }) async {
    final rows = await _db.query(
      'payments',
      where: 'purchase_id = ?',
      whereArgs: [purchaseId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Payment.fromMap).toList();
  }

  /// Records a payment against an existing purchase. The supplier balance and
  /// the purchase's paid/due amounts are updated in the same transaction.
  Future<void> addPayment({
    required int purchaseId,
    required int amountCentimes,
    required String method,
    String? note,
    DateTime? at,
  }) async {
    if (amountCentimes <= 0) throw ValidationError('Montant invalide.');
    final nowDate = at ?? DateTime.now();
    final now = nowDate.millisecondsSinceEpoch;
    final businessDate = Dates.businessDate(nowDate);
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        where: 'id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Achat introuvable.');
      final purchase = Purchase.fromMap(rows.first);
      if (purchase.status != 'completed') {
        throw ValidationError('Cet achat est annulé.');
      }
      if (purchase.supplierId == null) {
        throw ValidationError('Achat sans fournisseur.');
      }
      if (amountCentimes > purchase.dueCentimes) {
        throw ValidationError('Le paiement dépasse le reste à payer.');
      }
      await txn.update(
        'purchases',
        {
          'paid_centimes': purchase.paidCentimes + amountCentimes,
          'due_centimes': purchase.dueCentimes - amountCentimes,
        },
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      await txn.rawUpdate(
        'UPDATE suppliers SET balance_centimes = balance_centimes - ?, '
        'updated_at = ? WHERE id = ?',
        [amountCentimes, now, purchase.supplierId],
      );
      await txn.insert('payments', {
        'party_type': 'supplier',
        'party_id': purchase.supplierId,
        'direction': 'out',
        'amount_centimes': amountCentimes,
        'method': method,
        'reference': purchase.refNo,
        'note': note,
        'business_date': businessDate,
        'created_at': now,
        'purchase_id': purchaseId,
      });
      await txn.insert('ledger_entries', {
        'party_type': 'supplier',
        'party_id': purchase.supplierId,
        'entry_type': 'payment',
        'amount_centimes': -amountCentimes,
        'ref_type': 'purchase',
        'ref_id': purchaseId,
        'note': purchase.refNo,
        'business_date': businessDate,
        'created_at': now,
      });
      await AuditService(txn).log(
        action: 'payment',
        entity: 'purchase',
        entityId: purchaseId,
        details: {
          'ref_no': purchase.refNo,
          'amount': amountCentimes,
          'method': method,
        },
        reason: note,
      );
    });
  }

  Future<void> voidPurchase(int purchaseId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ValidationError('Le motif d\'annulation est obligatoire.');
    }
    final now = Dates.nowMillis();
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'purchases',
        where: 'id = ?',
        whereArgs: [purchaseId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Achat introuvable.');
      final purchase = Purchase.fromMap(rows.first);
      if (purchase.status == 'voided') {
        throw ConflictError('Cet achat est déjà annulé.');
      }
      final lines = await txn.query(
        'purchase_lines',
        where: 'purchase_id = ?',
        whereArgs: [purchaseId],
      );
      for (final row in lines) {
        final line = PurchaseLine.fromMap(row);
        if (line.productId == null) continue;
        await inventory.applyDelta(
          txn,
          productId: line.productId!,
          deltaMilli: -line.qtyMilli,
          type: 'purchase_void',
          reason: 'Annulation achat ${purchase.refNo}: $reason',
          unitCostCentimes: line.unitCostCentimes,
          refType: 'purchase',
          refId: purchaseId,
          audit: false,
        );
      }
      if (purchase.paidCentimes > 0) {
        await txn.insert('payments', {
          'party_type': 'supplier',
          'party_id': purchase.supplierId ?? 0,
          'direction': 'in',
          'amount_centimes': purchase.paidCentimes,
          'method': purchase.paymentMethod == 'credit'
              ? 'cash'
              : purchase.paymentMethod,
          'reference': purchase.refNo,
          'note': 'Annulation achat: $reason',
          'business_date': Dates.businessDate(),
          'created_at': now,
          'purchase_id': purchaseId,
        });
      }
      if (purchase.dueCentimes > 0 && purchase.supplierId != null) {
        await txn.rawUpdate(
          'UPDATE suppliers SET balance_centimes = balance_centimes - ?, '
          'updated_at = ? WHERE id = ?',
          [purchase.dueCentimes, now, purchase.supplierId],
        );
        await txn.insert('ledger_entries', {
          'party_type': 'supplier',
          'party_id': purchase.supplierId,
          'entry_type': 'purchase_void',
          'amount_centimes': -purchase.dueCentimes,
          'ref_type': 'purchase',
          'ref_id': purchaseId,
          'note': purchase.refNo,
          'business_date': Dates.businessDate(),
          'created_at': now,
        });
      }
      await txn.update(
        'purchases',
        {'status': 'voided', 'voided_at': now, 'void_reason': reason.trim()},
        where: 'id = ?',
        whereArgs: [purchaseId],
      );
      await AuditService(txn).log(
        action: 'void',
        entity: 'purchase',
        entityId: purchaseId,
        details: {'ref_no': purchase.refNo, 'total': purchase.totalCentimes},
        reason: reason,
      );
    });
  }
}
