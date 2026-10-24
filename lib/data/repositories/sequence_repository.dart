import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';

class SequenceRepository {
  const SequenceRepository();

  /// Transactional, gapless invoice sequence. The UPDATE happens inside the
  /// caller's transaction, so a rollback cannot consume a number.
  Future<String> next(
    DatabaseExecutor txn,
    String name, {
    required String prefix,
    int pad = 5,
    bool includeYear = true,
  }) async {
    final rows = await txn.query(
      'sequences',
      columns: ['next_value'],
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    var next = rows.isEmpty ? 1 : (rows.first['next_value'] as num).toInt();
    if (next < 1) next = 1;
    if (rows.isEmpty) {
      await txn.insert('sequences', {'name': name, 'next_value': next + 1});
    } else {
      await txn.update(
        'sequences',
        {'next_value': next + 1},
        where: 'name = ?',
        whereArgs: [name],
      );
    }
    final year = Dates.businessDate().substring(0, 4);
    final number = next.toString().padLeft(pad, '0');
    return includeYear ? '$prefix-$year-$number' : '$prefix-$number';
  }
}
