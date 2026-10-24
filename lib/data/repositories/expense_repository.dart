import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../models/models.dart';
import 'audit_service.dart';

class ExpenseRepository {
  ExpenseRepository(this.appDb);
  final AppDatabase appDb;
  Database get _db => appDb.db;

  Future<List<Expense>> list({
    DateTime? from,
    DateTime? to,
    int limit = 300,
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
      'expenses',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<int> create({
    required String category,
    required int amountCentimes,
    required String method,
    String? note,
    DateTime? at,
  }) async {
    if (category.trim().isEmpty) {
      throw ValidationError('La catégorie est obligatoire.');
    }
    if (amountCentimes <= 0) throw ValidationError('Montant invalide.');
    final date = at ?? DateTime.now();
    final id = await _db.insert('expenses', {
      'category': category.trim(),
      'amount_centimes': amountCentimes,
      'method': method,
      'note': note?.trim(),
      'business_date': Dates.businessDate(date),
      'created_at': date.millisecondsSinceEpoch,
    });
    await AuditService(_db).log(
      action: 'create',
      entity: 'expense',
      entityId: id,
      details: {
        'category': category,
        'amount': amountCentimes,
        'method': method,
      },
      reason: note,
    );
    return id;
  }

  Future<void> delete(int id, String reason) async {
    final rows = await _db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Dépense introuvable.');
    await _db.delete('expenses', where: 'id = ?', whereArgs: [id]);
    await AuditService(_db).log(
      action: 'delete',
      entity: 'expense',
      entityId: id,
      details: rows.first,
      reason: reason,
    );
  }

  Future<int> total({DateTime? from, DateTime? to, String? method}) async {
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
    if (method != null) {
      where.add('method = ?');
      args.add(method);
    }
    final rows = await _db.rawQuery('''
      SELECT COALESCE(SUM(amount_centimes), 0) AS v FROM expenses
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
    ''', args);
    return (rows.first['v'] as num).toInt();
  }
}
