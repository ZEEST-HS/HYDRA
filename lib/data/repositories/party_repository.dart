import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../models/models.dart';
import 'audit_service.dart';

class PartyRepository {
  PartyRepository(this.appDb);
  final AppDatabase appDb;
  Database get _db => appDb.db;

  Future<List<Customer>> customers({String query = '', int limit = 500}) async {
    final q = query.trim();
    final rows = await _db.query(
      'customers',
      where: q.isEmpty
          ? 'deleted_at IS NULL'
          : "deleted_at IS NULL AND (name LIKE ? OR IFNULL(phone, '') LIKE ?)",
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(Customer.fromMap).toList();
  }

  Future<Customer?> customer(int id) async {
    final rows = await _db.query(
      'customers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Customer.fromMap(rows.first);
  }

  Future<int> createCustomer(Customer customer) async {
    if (customer.name.trim().isEmpty) {
      throw ValidationError('Le nom du client est obligatoire.');
    }
    final now = Dates.nowMillis();
    final id = await _db.insert('customers', {
      'name': customer.name.trim(),
      'phone': customer.phone?.trim(),
      'address': customer.address?.trim(),
      'note': customer.note?.trim(),
      'balance_centimes': customer.balanceCentimes,
      'credit_limit_centimes': customer.creditLimitCentimes,
      'created_at': now,
      'updated_at': now,
    });
    await AuditService(_db).log(
      action: 'create',
      entity: 'customer',
      entityId: id,
      details: {'name': customer.name},
    );
    return id;
  }

  Future<void> updateCustomer(Customer customer) async {
    if (customer.id <= 0) throw ValidationError('Client invalide.');
    if (customer.name.trim().isEmpty) {
      throw ValidationError('Le nom du client est obligatoire.');
    }
    await _db.update(
      'customers',
      {
        'name': customer.name.trim(),
        'phone': customer.phone?.trim(),
        'address': customer.address?.trim(),
        'note': customer.note?.trim(),
        'credit_limit_centimes': customer.creditLimitCentimes,
        'updated_at': Dates.nowMillis(),
      },
      where: 'id = ?',
      whereArgs: [customer.id],
    );
    await AuditService(_db).log(
      action: 'update',
      entity: 'customer',
      entityId: customer.id,
      details: {'name': customer.name},
    );
  }

  Future<void> deleteCustomer(int id) async {
    final now = Dates.nowMillis();
    await _db.update(
      'customers',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService(_db)
        .log(action: 'delete', entity: 'customer', entityId: id);
  }

  Future<List<Supplier>> suppliers({String query = '', int limit = 500}) async {
    final q = query.trim();
    final rows = await _db.query(
      'suppliers',
      where: q.isEmpty
          ? 'deleted_at IS NULL'
          : "deleted_at IS NULL AND (name LIKE ? OR IFNULL(phone, '') LIKE ?)",
      whereArgs: q.isEmpty ? null : ['%$q%', '%$q%'],
      orderBy: 'name COLLATE NOCASE',
      limit: limit,
    );
    return rows.map(Supplier.fromMap).toList();
  }

  Future<Supplier?> supplier(int id) async {
    final rows = await _db.query(
      'suppliers',
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : Supplier.fromMap(rows.first);
  }

  Future<int> createSupplier(Supplier supplier) async {
    if (supplier.name.trim().isEmpty) {
      throw ValidationError('Le nom du fournisseur est obligatoire.');
    }
    final now = Dates.nowMillis();
    final id = await _db.insert('suppliers', {
      'name': supplier.name.trim(),
      'phone': supplier.phone?.trim(),
      'address': supplier.address?.trim(),
      'note': supplier.note?.trim(),
      'balance_centimes': supplier.balanceCentimes,
      'created_at': now,
      'updated_at': now,
    });
    await AuditService(_db).log(
      action: 'create',
      entity: 'supplier',
      entityId: id,
      details: {'name': supplier.name},
    );
    return id;
  }

  Future<void> updateSupplier(Supplier supplier) async {
    if (supplier.id <= 0) throw ValidationError('Fournisseur invalide.');
    if (supplier.name.trim().isEmpty) {
      throw ValidationError('Le nom du fournisseur est obligatoire.');
    }
    await _db.update(
      'suppliers',
      {
        'name': supplier.name.trim(),
        'phone': supplier.phone?.trim(),
        'address': supplier.address?.trim(),
        'note': supplier.note?.trim(),
        'updated_at': Dates.nowMillis(),
      },
      where: 'id = ?',
      whereArgs: [supplier.id],
    );
    await AuditService(_db).log(
      action: 'update',
      entity: 'supplier',
      entityId: supplier.id,
      details: {'name': supplier.name},
    );
  }

  Future<void> deleteSupplier(int id) async {
    final now = Dates.nowMillis();
    await _db.update(
      'suppliers',
      {'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [id],
    );
    await AuditService(_db)
        .log(action: 'delete', entity: 'supplier', entityId: id);
  }

  Future<void> receiveCustomerPayment({
    required int customerId,
    required int amountCentimes,
    required String method,
    String? note,
    DateTime? at,
  }) async {
    if (amountCentimes <= 0) throw ValidationError('Montant invalide.');
    final nowDate = at ?? DateTime.now();
    final now = nowDate.millisecondsSinceEpoch;
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'customers',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [customerId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Client introuvable.');
      final customer = Customer.fromMap(rows.first);
      if (amountCentimes > customer.balanceCentimes) {
        throw ValidationError(
          'Le paiement dépasse la dette du client (${customer.balanceCentimes / 100} DH).',
        );
      }
      await txn.rawUpdate(
        'UPDATE customers SET balance_centimes = balance_centimes - ?, '
        'updated_at = ? WHERE id = ?',
        [amountCentimes, now, customerId],
      );
      await txn.insert('payments', {
        'party_type': 'customer',
        'party_id': customerId,
        'direction': 'in',
        'amount_centimes': amountCentimes,
        'method': method,
        'note': note,
        'business_date': Dates.businessDate(nowDate),
        'created_at': now,
      });
      await txn.insert('ledger_entries', {
        'party_type': 'customer',
        'party_id': customerId,
        'entry_type': 'payment',
        'amount_centimes': -amountCentimes,
        'ref_type': 'payment',
        'ref_id': null,
        'note': note,
        'business_date': Dates.businessDate(nowDate),
        'created_at': now,
      });
      await AuditService(txn).log(
        action: 'payment',
        entity: 'customer',
        entityId: customerId,
        details: {'amount': amountCentimes, 'method': method},
        reason: note,
      );
    });
  }

  Future<void> paySupplier({
    required int supplierId,
    required int amountCentimes,
    required String method,
    String? note,
    DateTime? at,
  }) async {
    if (amountCentimes <= 0) throw ValidationError('Montant invalide.');
    final nowDate = at ?? DateTime.now();
    final now = nowDate.millisecondsSinceEpoch;
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'suppliers',
        where: 'id = ? AND deleted_at IS NULL',
        whereArgs: [supplierId],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Fournisseur introuvable.');
      final supplier = Supplier.fromMap(rows.first);
      if (amountCentimes > supplier.balanceCentimes) {
        throw ValidationError(
          'Le paiement dépasse le solde dû au fournisseur.',
        );
      }
      await txn.rawUpdate(
        'UPDATE suppliers SET balance_centimes = balance_centimes - ?, '
        'updated_at = ? WHERE id = ?',
        [amountCentimes, now, supplierId],
      );
      await txn.insert('payments', {
        'party_type': 'supplier',
        'party_id': supplierId,
        'direction': 'out',
        'amount_centimes': amountCentimes,
        'method': method,
        'note': note,
        'business_date': Dates.businessDate(nowDate),
        'created_at': now,
      });
      await txn.insert('ledger_entries', {
        'party_type': 'supplier',
        'party_id': supplierId,
        'entry_type': 'payment',
        'amount_centimes': -amountCentimes,
        'ref_type': 'payment',
        'ref_id': null,
        'note': note,
        'business_date': Dates.businessDate(nowDate),
        'created_at': now,
      });
      await AuditService(txn).log(
        action: 'payment',
        entity: 'supplier',
        entityId: supplierId,
        details: {'amount': amountCentimes, 'method': method},
        reason: note,
      );
    });
  }

  Future<List<Payment>> payments({
    String? partyType,
    int? partyId,
    DateTime? from,
    DateTime? to,
    int limit = 300,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    if (partyType != null) {
      where.add('party_type = ?');
      args.add(partyType);
    }
    if (partyId != null) {
      where.add('party_id = ?');
      args.add(partyId);
    }
    if (from != null) {
      where.add('business_date >= ?');
      args.add(Dates.businessDate(from));
    }
    if (to != null) {
      where.add('business_date <= ?');
      args.add(Dates.businessDate(to));
    }
    final rows = await _db.query(
      'payments',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Payment.fromMap).toList();
  }

  Future<List<LedgerEntry>> ledger(
    String partyType,
    int partyId, {
    int limit = 200,
  }) async {
    final rows = await _db.query(
      'ledger_entries',
      where: 'party_type = ? AND party_id = ?',
      whereArgs: [partyType, partyId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(LedgerEntry.fromMap).toList();
  }

  Future<int> totalCustomerDebt() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(balance_centimes), 0) AS v FROM customers '
      'WHERE deleted_at IS NULL AND balance_centimes > 0',
    );
    return (rows.first['v'] as num).toInt();
  }

  Future<int> totalSupplierDebt() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM(balance_centimes), 0) AS v FROM suppliers '
      'WHERE deleted_at IS NULL AND balance_centimes > 0',
    );
    return (rows.first['v'] as num).toInt();
  }
}
