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
import '../../data/repositories/settings_repository.dart';

class SaleDraftLine {
  const SaleDraftLine({
    required this.product,
    this.unit,
    required this.qtyMilli,
    required this.unitPriceCentimes,
    this.lineDiscountCentimes = 0,
    this.lineTotalOverrideCentimes,
  });

  final Product product;
  final ProductUnit? unit;
  final int qtyMilli;
  final int unitPriceCentimes;
  final int lineDiscountCentimes;

  /// Exact line total for package sales, where a package price cannot be
  /// represented as an integer price per base unit without rounding. When
  /// null the total is derived from quantity and unit price.
  final int? lineTotalOverrideCentimes;

  String get unitName => unit?.name ?? '';
  int get factorMilli => unit?.factorMilli ?? 1000;

  int get grossCentimes =>
      Money.lineTotal(qtyMilli: qtyMilli, unitPriceCentimes: unitPriceCentimes);

  int get netCentimes =>
      lineTotalOverrideCentimes ?? max(0, grossCentimes - lineDiscountCentimes);
}

class SaleDraft {
  const SaleDraft({
    required this.lines,
    this.customerId,
    this.discountCentimes = 0,
    required this.paidCentimes,
    required this.paymentMethod,
    this.note,
    required this.idempotencyKey,
    this.allowNegativeStock = false,
    this.at,
  });

  final List<SaleDraftLine> lines;
  final int? customerId;
  final int discountCentimes;
  final int paidCentimes;
  final String paymentMethod;
  final String? note;
  final String idempotencyKey;
  final bool allowNegativeStock;
  final DateTime? at;

  int get subtotalCentimes =>
      lines.fold(0, (sum, line) => sum + line.netCentimes);
  int get totalCentimes => max(0, subtotalCentimes - discountCentimes);
}

class SaleService {
  SaleService(
    this.appDb,
    this.settings,
    this.inventory, {
    SequenceRepository? sequences,
  }) : _sequences = sequences ?? const SequenceRepository();

  final AppDatabase appDb;
  final SettingsRepository settings;
  final InventoryRepository inventory;
  final SequenceRepository _sequences;

  Database get _db => appDb.db;

  Future<Sale> completeSale(SaleDraft draft) async {
    if (draft.lines.isEmpty) {
      throw ValidationError('Le panier est vide.');
    }
    if (draft.idempotencyKey.trim().isEmpty) {
      throw ValidationError('Clé de vente manquante.');
    }
    if (draft.paidCentimes < 0 || draft.discountCentimes < 0) {
      throw ValidationError('Montant invalide.');
    }
    if (draft.discountCentimes > draft.subtotalCentimes) {
      throw ValidationError('La remise dépasse le sous-total.');
    }
    if (draft.paidCentimes > draft.totalCentimes) {
      throw ValidationError('Le montant payé dépasse le total.');
    }
    final due = draft.totalCentimes - draft.paidCentimes;
    if (due > 0 && draft.customerId == null) {
      throw ValidationError(
        'Sélectionnez un client pour enregistrer un reste à payer.',
      );
    }
    for (final line in draft.lines) {
      if (line.qtyMilli <= 0) {
        throw ValidationError(
          'Quantité invalide pour « ${line.product.name} ».',
        );
      }
      if (line.unitPriceCentimes < 0) {
        throw ValidationError('Prix invalide pour « ${line.product.name} ».');
      }
      if (line.lineDiscountCentimes < 0 ||
          line.lineDiscountCentimes > line.grossCentimes) {
        throw ValidationError('Remise de ligne invalide.');
      }
      if (line.lineTotalOverrideCentimes != null &&
          line.lineTotalOverrideCentimes! < 0) {
        throw ValidationError('Total de ligne invalide.');
      }
    }

    final now = draft.at ?? DateTime.now();
    final nowMillis = now.millisecondsSinceEpoch;
    final businessDate = Dates.businessDate(now);
    final idempotencyKey = draft.idempotencyKey.trim();
    final policy = await settings.stockPolicy();

    return appDb.transaction((txn) async {
      // Duplicate confirmation protection: return the original sale.
      final existing = await txn.query(
        'sales',
        where: 'idempotency_key = ?',
        whereArgs: [idempotencyKey],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return _loadSale(txn, (existing.first['id'] as num).toInt());
      }

      final allowNegative = draft.allowNegativeStock || policy == 'allow';

      // Aggregate required quantity across lines so two lines of the same
      // product cannot bypass the stock check.
      final required = <int, int>{};
      for (final line in draft.lines) {
        required.update(
          line.product.id,
          (v) => v + line.qtyMilli,
          ifAbsent: () => line.qtyMilli,
        );
      }
      for (final entry in required.entries) {
        final rows = await txn.query(
          'products',
          columns: ['name', 'stock_milli'],
          where: 'id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (rows.isEmpty) throw NotFoundError('Produit introuvable.');
        final stock = (rows.first['stock_milli'] as num).toInt();
        if (entry.value > stock) {
          final name = rows.first['name'];
          if (policy == 'block' || !allowNegative && policy != 'confirm') {
            throw ValidationError(
              'Stock insuffisant pour « $name » : disponible '
              '${stock / 1000}, demandé ${entry.value / 1000}.',
            );
          }
          if (!allowNegative) {
            throw ValidationError(
              'Stock insuffisant pour « $name ». Confirmez l\'exception.',
            );
          }
        }
      }

      String? customerName;
      if (draft.customerId != null) {
        final cRows = await txn.query(
          'customers',
          columns: ['name'],
          where: 'id = ? AND deleted_at IS NULL',
          whereArgs: [draft.customerId],
          limit: 1,
        );
        if (cRows.isEmpty) throw NotFoundError('Client introuvable.');
        customerName = cRows.first['name'] as String;
      }

      final invoiceNo = await _sequences.next(txn, 'sale', prefix: 'V');
      final saleId = await txn.insert('sales', {
        'invoice_no': invoiceNo,
        'customer_id': draft.customerId,
        'customer_name': customerName,
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
        'idempotency_key': idempotencyKey,
        'created_at': nowMillis,
      });

      for (final line in draft.lines) {
        final saleLineId = await txn.insert('sale_lines', {
          'sale_id': saleId,
          'product_id': line.product.id,
          'product_name': line.product.name,
          'barcode': line.product.barcode,
          'unit_name': line.unitName,
          'factor_milli': line.factorMilli,
          'qty_milli': line.qtyMilli,
          'unit_price_centimes': line.unitPriceCentimes,
          'unit_cost_centimes': line.product.costCentimes,
          'line_discount_centimes': line.lineDiscountCentimes,
          'line_total_centimes': line.netCentimes,
          'created_at': nowMillis,
        });
        await inventory.applyDelta(
          txn,
          productId: line.product.id,
          deltaMilli: -line.qtyMilli,
          type: 'sale',
          reason: 'Vente $invoiceNo',
          unitCostCentimes: line.product.costCentimes,
          refType: 'sale',
          refId: saleId,
          allowNegative: allowNegative,
          audit: false,
          businessDate: businessDate,
        );
        await inventory.consumeBatchesFefo(
          txn,
          line.product.id,
          line.qtyMilli,
          saleLineId: saleLineId,
        );
      }

      if (due > 0 && draft.customerId != null) {
        await txn.rawUpdate(
          'UPDATE customers SET balance_centimes = balance_centimes + ?, '
          'updated_at = ? WHERE id = ?',
          [due, nowMillis, draft.customerId],
        );
        await _ledger(
          txn,
          partyType: 'customer',
          partyId: draft.customerId!,
          entryType: 'sale_due',
          amountCentimes: due,
          refType: 'sale',
          refId: saleId,
          note: invoiceNo,
          businessDate: businessDate,
        );
      }

      await AuditService(txn).log(
        action: 'sale',
        entity: 'sale',
        entityId: saleId,
        details: {
          'invoice_no': invoiceNo,
          'total': draft.totalCentimes,
          'paid': draft.paidCentimes,
          'due': due,
          'line_count': draft.lines.length,
        },
      );

      return _loadSale(txn, saleId);
    });
  }

  Future<Sale> _loadSale(DatabaseExecutor txn, int saleId) async {
    final rows = await txn.query(
      'sales',
      where: 'id = ?',
      whereArgs: [saleId],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Vente introuvable.');
    final sale = Sale.fromMap(rows.first);
    final lines = await txn.query(
      'sale_lines',
      where: 'sale_id = ?',
      whereArgs: [saleId],
      orderBy: 'id ASC',
    );
    final returned = await txn.rawQuery(
      '''
      SELECT COALESCE(SUM(rl.line_total_centimes), 0) AS total
      FROM return_lines rl
      JOIN sale_returns r ON r.id = rl.return_id
      WHERE r.sale_id = ?
    ''',
      [saleId],
    );
    return sale.copyWith(
      lines: lines.map(SaleLine.fromMap).toList(),
      returnedCentimes: (returned.first['total'] as num).toInt(),
    );
  }

  Future<Sale?> findById(int id) async {
    final rows = await _db.query(
      'sales',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _loadSale(_db, id);
  }

  Future<Sale?> findByInvoice(String invoiceNo) async {
    final rows = await _db.query(
      'sales',
      where: 'invoice_no = ?',
      whereArgs: [invoiceNo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _loadSale(_db, (rows.first['id'] as num).toInt());
  }

  Future<List<Sale>> list({
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
      where.add('(invoice_no LIKE ? OR IFNULL(customer_name, \'\') LIKE ?)');
      args.addAll(['%$q%', '%$q%']);
    }
    final rows = await _db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    final sales = <Sale>[];
    for (final row in rows) {
      final sale = Sale.fromMap(row);
      final ret = await _db.rawQuery(
        '''
        SELECT COALESCE(SUM(total_centimes), 0) AS t FROM sale_returns WHERE sale_id = ?
      ''',
        [sale.id],
      );
      sales.add(
        sale.copyWith(returnedCentimes: (ret.first['t'] as num).toInt()),
      );
    }
    return sales;
  }

  Future<List<Sale>> salesForCustomer(int customerId, {int limit = 100}) async {
    final rows = await _db.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<void> voidSale(int saleId, String reason) async {
    if (reason.trim().isEmpty) {
      throw ValidationError('Le motif d\'annulation est obligatoire.');
    }
    final now = Dates.nowMillis();
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Vente introuvable.');
      final sale = Sale.fromMap(rows.first);
      if (sale.status == 'voided') {
        throw ConflictError('Cette vente est déjà annulée.');
      }
      final returns = await txn.query(
        'sale_returns',
        where: 'sale_id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (returns.isNotEmpty) {
        throw ConflictError(
          'Cette vente a des retours. Utilisez le remboursement, pas l\'annulation.',
        );
      }
      final lines = await txn.query(
        'sale_lines',
        where: 'sale_id = ?',
        whereArgs: [saleId],
      );
      for (final row in lines) {
        final line = SaleLine.fromMap(row);
        if (line.productId == null) continue;
        await inventory.applyDelta(
          txn,
          productId: line.productId!,
          deltaMilli: line.qtyMilli,
          type: 'sale_void',
          reason: 'Annulation ${sale.invoiceNo}: $reason',
          unitCostCentimes: line.unitCostCentimes,
          refType: 'sale',
          refId: saleId,
          audit: false,
        );
        await inventory.restoreSaleLineBatches(
          txn,
          saleLineId: line.id,
          productId: line.productId!,
          qtyMilli: line.qtyMilli,
          unitCostCentimes: line.unitCostCentimes,
        );
      }
      if (sale.dueCentimes > 0 && sale.customerId != null) {
        await txn.rawUpdate(
          'UPDATE customers SET balance_centimes = balance_centimes - ?, '
          'updated_at = ? WHERE id = ?',
          [sale.dueCentimes, now, sale.customerId],
        );
        await _ledger(
          txn,
          partyType: 'customer',
          partyId: sale.customerId!,
          entryType: 'sale_void',
          amountCentimes: -sale.dueCentimes,
          refType: 'sale',
          refId: saleId,
          note: sale.invoiceNo,
        );
      }
      // Cash actually collected must leave the drawer when the sale is voided.
      if (sale.paidCentimes > 0 && sale.paymentMethod == 'cash') {
        await txn.insert('payments', {
          'party_type': 'cash',
          'party_id': 0,
          'direction': 'out',
          'amount_centimes': sale.paidCentimes,
          'method': 'cash',
          'reference': sale.invoiceNo,
          'note': 'Annulation de vente: $reason',
          'business_date': Dates.businessDate(),
          'created_at': now,
        });
      }
      await txn.update(
        'sales',
        {'status': 'voided', 'voided_at': now, 'void_reason': reason.trim()},
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await AuditService(txn).log(
        action: 'void',
        entity: 'sale',
        entityId: saleId,
        details: {
          'invoice_no': sale.invoiceNo,
          'total': sale.totalCentimes,
          'paid': sale.paidCentimes,
        },
        reason: reason,
      );
    });
  }

  Future<void> addPayment({
    required int saleId,
    required int amountCentimes,
    required String method,
    String? note,
  }) async {
    if (amountCentimes <= 0) throw ValidationError('Montant invalide.');
    final now = Dates.nowMillis();
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'sales',
        where: 'id = ?',
        whereArgs: [saleId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Vente introuvable.');
      final sale = Sale.fromMap(rows.first);
      if (sale.status != 'completed') {
        throw ValidationError('Cette vente est annulée.');
      }
      if (sale.customerId == null) {
        throw ValidationError('Vente sans client.');
      }
      if (amountCentimes > sale.dueCentimes) {
        throw ValidationError('Le paiement dépasse le reste à payer.');
      }
      await txn.update(
        'sales',
        {
          'paid_centimes': sale.paidCentimes + amountCentimes,
          'due_centimes': sale.dueCentimes - amountCentimes,
        },
        where: 'id = ?',
        whereArgs: [saleId],
      );
      await txn.rawUpdate(
        'UPDATE customers SET balance_centimes = balance_centimes - ?, '
        'updated_at = ? WHERE id = ?',
        [amountCentimes, now, sale.customerId],
      );
      await txn.insert('payments', {
        'party_type': 'customer',
        'party_id': sale.customerId,
        'direction': 'in',
        'amount_centimes': amountCentimes,
        'method': method,
        'reference': sale.invoiceNo,
        'note': note,
        'business_date': Dates.businessDate(),
        'created_at': now,
        'sale_id': saleId,
      });
      await _ledger(
        txn,
        partyType: 'customer',
        partyId: sale.customerId!,
        entryType: 'payment',
        amountCentimes: -amountCentimes,
        refType: 'sale',
        refId: saleId,
        note: sale.invoiceNo,
      );
      await AuditService(txn).log(
        action: 'payment',
        entity: 'sale',
        entityId: saleId,
        details: {'amount': amountCentimes, 'method': method},
        reason: note,
      );
    });
  }

  static Future<void> _ledger(
    DatabaseExecutor txn, {
    required String partyType,
    required int partyId,
    required String entryType,
    required int amountCentimes,
    required String refType,
    required int refId,
    String? note,
    String? businessDate,
  }) async {
    final now = Dates.nowMillis();
    await txn.insert('ledger_entries', {
      'party_type': partyType,
      'party_id': partyId,
      'entry_type': entryType,
      'amount_centimes': amountCentimes,
      'ref_type': refType,
      'ref_id': refId,
      'note': note,
      'business_date': businessDate ?? Dates.businessDate(),
      'created_at': now,
    });
  }
}
