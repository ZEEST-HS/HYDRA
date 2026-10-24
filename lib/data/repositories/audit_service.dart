import 'dart:convert';

import 'package:sqflite/sqflite.dart';

class AuditService {
  AuditService(this.db);
  final DatabaseExecutor db;

  Future<void> log({
    required String action,
    required String entity,
    int? entityId,
    Map<String, Object?>? details,
    String? reason,
    int? at,
  }) async {
    await db.insert('audit_log', {
      'action': action,
      'entity': entity,
      'entity_id': entityId,
      'details_json': details == null ? null : jsonEncode(details),
      'reason': reason,
      'created_at': at ?? DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> recent({int limit = 100}) {
    return db.query('audit_log', orderBy: 'created_at DESC', limit: limit);
  }
}
