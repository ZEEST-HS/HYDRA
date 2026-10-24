import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../data/repositories/audit_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});

  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final _search = TextEditingController();
  Future<List<AuditEntry>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<List<AuditEntry>> _load() async {
    final c = AppScope.read(context);
    final rows = await AuditService(c.db.db).recent(limit: 500);
    return rows.map(AuditEntry.fromMap).toList();
  }

  void _reload() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Journal d\'audit')),
        actions: [
          IconButton(
            tooltip: l.t('Actualiser'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 900,
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l.t('Rechercher'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<AuditEntry>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return EmptyState(
                      message: snapshot.error.toString(),
                      icon: Icons.error_outline,
                      action: FilledButton(
                        onPressed: _reload,
                        child: Text(l.t('Réessayer')),
                      ),
                    );
                  }
                  final entries = snapshot.data ?? const <AuditEntry>[];
                  final query = _search.text.trim().toLowerCase();
                  final filtered = query.isEmpty
                      ? entries
                      : entries
                            .where(
                              (entry) =>
                                  entry.action.toLowerCase().contains(query) ||
                                  entry.entity.toLowerCase().contains(query) ||
                                  (entry.reason ?? '').toLowerCase().contains(
                                    query,
                                  ) ||
                                  (entry.detailsJson ?? '')
                                      .toLowerCase()
                                      .contains(query),
                            )
                            .toList();
                  if (filtered.isEmpty) {
                    return EmptyState(
                      message: entries.isEmpty
                          ? l.t('Aucune entrée')
                          : l.t('Aucun résultat'),
                      icon: Icons.history,
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) =>
                        _auditTile(filtered[index], l),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _auditTile(AuditEntry entry, L10n l) {
    final color = _colorFor(entry.action);
    final date = DateTime.fromMillisecondsSinceEpoch(entry.createdAt);
    return ExpansionTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(_iconFor(entry.action), color: color, size: 19),
      ),
      title: Text(
        '${entry.action} · ${entry.entity}'
        '${entry.entityId == null ? '' : ' #${entry.entityId}'}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        Dates.formatDateTime(date) +
            (entry.reason == null ? '' : ' · ${entry.reason}'),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (entry.detailsJson == null)
          Text(l.t('Aucune description'))
        else
          SelectableText(
            _pretty(entry.detailsJson!),
            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          ),
      ],
    );
  }

  String _pretty(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }

  Color _colorFor(String action) {
    if (action.contains('delete') || action.contains('void')) {
      return AppTheme.danger;
    }
    if (action.contains('payment') || action.contains('sale')) {
      return AppTheme.success;
    }
    if (action.contains('update') || action.contains('adjust')) {
      return AppTheme.accent;
    }
    return AppTheme.primary;
  }

  IconData _iconFor(String action) {
    if (action.contains('delete') || action.contains('void')) {
      return Icons.delete_outline;
    }
    if (action.contains('payment')) return Icons.payments_outlined;
    if (action.contains('stock')) return Icons.inventory_2_outlined;
    if (action.contains('update')) return Icons.edit_outlined;
    return Icons.add_circle_outline;
  }
}
