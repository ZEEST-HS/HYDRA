import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'party_detail_screen.dart';
import 'party_form_dialog.dart';

enum PartyKind { customer, supplier }

/// Customers and suppliers share the same screen. Balances are maintained by
/// sale/purchase/payment services, never edited directly.
class PartiesScreen extends StatefulWidget {
  const PartiesScreen({super.key, required this.kind});
  final PartyKind kind;

  @override
  State<PartiesScreen> createState() => _PartiesScreenState();
}

class _PartiesScreenState extends State<PartiesScreen> {
  final _search = TextEditingController();
  Future<_PartiesData>? _future;

  bool get _customers => widget.kind == PartyKind.customer;

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

  Future<_PartiesData> _load() async {
    final c = AppScope.read(context);
    final query = _search.text.trim();
    if (_customers) {
      final list = await c.parties.customers(query: query);
      return _PartiesData.customers(list);
    }
    final list = await c.parties.suppliers(query: query);
    return _PartiesData.suppliers(list);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _add() async {
    final created = await showPartyForm(
      context,
      customer: null,
      supplier: null,
    );
    if (created == true) _reload();
  }

  Future<void> _openCustomer(Customer customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PartyDetailScreen(kind: PartyKind.customer, partyId: customer.id),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _openSupplier(Supplier supplier) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PartyDetailScreen(kind: PartyKind.supplier, partyId: supplier.id),
      ),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_customers ? l.t('Clients') : l.t('Fournisseurs')),
        actions: [
          IconButton(
            tooltip: l.t('Ajouter'),
            onPressed: _add,
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 980,
        child: Column(
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => _reload(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l.t('Rechercher'),
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _search.clear();
                          _reload();
                        },
                        icon: const Icon(Icons.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<_PartiesData>(
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
                  final data = snapshot.data!;
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      children: [
                        _SummaryCard(
                          label: _customers
                              ? l.t('Dettes clients')
                              : l.t('Dettes fournisseurs'),
                          total: data.total,
                          count: data.count,
                          isCustomer: _customers,
                          onAdd: _add,
                        ),
                        const SizedBox(height: 12),
                        if (data.isEmpty)
                          EmptyState(
                            message: _customers
                                ? l.t('Aucun client')
                                : l.t('Aucun fournisseur'),
                            icon: Icons.people_outline,
                            action: FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: Text(
                                _customers
                                    ? l.t('Ajouter un client')
                                    : l.t('Ajouter un fournisseur'),
                              ),
                            ),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (final row in data.rows)
                                  _PartyTile(
                                    name: row.name,
                                    phone: row.phone,
                                    balance: row.balance,
                                    isCustomer: _customers,
                                    onTap: () => _customers
                                        ? _openCustomer(row.customer!)
                                        : _openSupplier(row.supplier!),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartiesData {
  _PartiesData._(this.customers, this.suppliers);
  factory _PartiesData.customers(List<Customer> list) =>
      _PartiesData._(list, const []);
  factory _PartiesData.suppliers(List<Supplier> list) =>
      _PartiesData._(const [], list);

  final List<Customer> customers;
  final List<Supplier> suppliers;

  bool get isEmpty => customers.isEmpty && suppliers.isEmpty;
  int get count => customers.length + suppliers.length;

  int get total {
    var value = 0;
    for (final c in customers) {
      if (c.balanceCentimes > 0) value += c.balanceCentimes;
    }
    for (final s in suppliers) {
      if (s.balanceCentimes > 0) value += s.balanceCentimes;
    }
    return value;
  }

  List<_PartyRow> get rows => [
    for (final c in customers)
      _PartyRow(
        name: c.name,
        phone: c.phone,
        balance: c.balanceCentimes,
        customer: c,
      ),
    for (final s in suppliers)
      _PartyRow(
        name: s.name,
        phone: s.phone,
        balance: s.balanceCentimes,
        supplier: s,
      ),
  ];
}

class _PartyRow {
  const _PartyRow({
    required this.name,
    required this.balance,
    this.phone,
    this.customer,
    this.supplier,
  });
  final String name;
  final String? phone;
  final int balance;
  final Customer? customer;
  final Supplier? supplier;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.total,
    required this.count,
    required this.isCustomer,
    required this.onAdd,
  });

  final String label;
  final int total;
  final int count;
  final bool isCustomer;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCustomer ? Icons.people_outline : Icons.store_outlined,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  Text(
                    money(total, context),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$count ${isCustomer ? l.t('clients') : l.t('fournisseurs')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l.t('Ajouter')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartyTile extends StatelessWidget {
  const _PartyTile({
    required this.name,
    required this.balance,
    required this.isCustomer,
    required this.onTap,
    this.phone,
  });

  final String name;
  final String? phone;
  final int balance;
  final bool isCustomer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: balance > 0
            ? AppTheme.danger.withValues(alpha: 0.12)
            : AppTheme.success.withValues(alpha: 0.12),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: balance > 0 ? AppTheme.danger : AppTheme.success,
          ),
        ),
      ),
      title: Text(name),
      subtitle: phone == null || phone!.isEmpty
          ? Text(l.t('Aucun mouvement'))
          : Text(phone!),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(balance, context),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: balance > 0 ? AppTheme.danger : AppTheme.success,
            ),
          ),
          Text(
            balance > 0 ? l.t('Reste à payer') : l.t('Solde'),
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
