import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../services/file_share_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'purchase_detail_screen.dart';
import 'purchase_form_screen.dart';

enum PurchasePeriod { today, week, month, all, custom }

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  final _search = TextEditingController();
  PurchasePeriod _period = PurchasePeriod.month;
  DateTimeRange? _customRange;
  Future<_PurchasesData>? _future;

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

  DateTimeRange? _range() {
    final now = DateTime.now();
    switch (_period) {
      case PurchasePeriod.today:
        return DateTimeRange(start: now, end: now);
      case PurchasePeriod.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
      case PurchasePeriod.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case PurchasePeriod.custom:
        return _customRange;
      case PurchasePeriod.all:
        return null;
    }
  }

  Future<_PurchasesData> _load() async {
    final c = AppScope.read(context);
    final range = _range();
    final purchases = await c.purchases.list(
      from: range?.start,
      to: range?.end,
      query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      limit: 300,
    );
    var total = 0;
    var paid = 0;
    var due = 0;
    for (final purchase in purchases) {
      if (purchase.isVoided) continue;
      total += purchase.totalCentimes;
      paid += purchase.paidCentimes;
      due += purchase.dueCentimes;
    }
    return _PurchasesData(purchases, total, paid, due);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
    );
    if (range == null) return;
    setState(() {
      _customRange = range;
      _period = PurchasePeriod.custom;
      _future = _load();
    });
  }

  Future<void> _add() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const PurchaseFormScreen()));
    if (created == true) _reload();
  }

  Future<void> _open(Purchase purchase) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PurchaseDetailScreen(purchaseId: purchase.id),
      ),
    );
    if (mounted) _reload();
  }

  Future<void> _export() async {
    final c = AppScope.of(context);
    final l = c.l10n;
    try {
      final range = _range();
      final csv = await c.io.exportPurchasesCsv(
        from: range?.start,
        to: range?.end,
      );
      await const FileShareService().shareCsv(
        fileName: 'achats_${Dates.businessDate()}.csv',
        csv: csv,
        subject: l.t('Achats'),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Achats')),
        actions: [
          IconButton(
            tooltip: l.t('Exporter'),
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: l.t('Nouvel achat'),
            onPressed: _add,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l.t('Nouvel achat')),
      ),
      body: PageBody(
        maxWidth: 1080,
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
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final period in PurchasePeriod.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(_periodLabel(period, l)),
                        selected: _period == period,
                        onSelected: (_) {
                          if (period == PurchasePeriod.custom) {
                            _pickCustomRange();
                            return;
                          }
                          setState(() {
                            _period = period;
                            _future = _load();
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<_PurchasesData>(
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
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        _PurchasesSummary(data: data),
                        const SizedBox(height: 12),
                        if (data.purchases.isEmpty)
                          EmptyState(
                            message: l.t('Aucun achat'),
                            icon: Icons.local_shipping_outlined,
                            action: FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: Text(l.t('Nouvel achat')),
                            ),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (final purchase in data.purchases)
                                  _PurchaseTile(
                                    purchase: purchase,
                                    onTap: () => _open(purchase),
                                  ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 32),
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

  String _periodLabel(PurchasePeriod period, L10n l) {
    switch (period) {
      case PurchasePeriod.today:
        return l.t('Aujourd\'hui');
      case PurchasePeriod.week:
        return l.t('7 derniers jours');
      case PurchasePeriod.month:
        return l.t('Ce mois');
      case PurchasePeriod.all:
        return l.t('Tous');
      case PurchasePeriod.custom:
        return _customRange == null
            ? l.t('Personnalisé')
            : '${Dates.formatDate(_customRange!.start)} – '
                  '${Dates.formatDate(_customRange!.end)}';
    }
  }
}

class _PurchasesData {
  const _PurchasesData(this.purchases, this.total, this.paid, this.due);
  final List<Purchase> purchases;
  final int total;
  final int paid;
  final int due;
}

class _PurchasesSummary extends StatelessWidget {
  const _PurchasesSummary({required this.data});
  final _PurchasesData data;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 3 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        final cards = [
          StatCard(
            label: l.t('Total des achats'),
            value: money(data.total, context),
            icon: Icons.local_shipping_outlined,
            footnote: '${data.purchases.length} ${l.t('achat(s)')}',
          ),
          StatCard(
            label: l.t('Payé'),
            value: money(data.paid, context),
            icon: Icons.payments_outlined,
            color: AppTheme.success,
          ),
          StatCard(
            label: l.t('Reste à payer'),
            value: money(data.due, context),
            icon: Icons.schedule,
            color: data.due > 0 ? AppTheme.danger : AppTheme.success,
          ),
        ];
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _PurchaseTile extends StatelessWidget {
  const _PurchaseTile({required this.purchase, required this.onTap});
  final Purchase purchase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final color = purchase.isVoided
        ? AppTheme.danger
        : purchase.dueCentimes == 0
        ? AppTheme.success
        : AppTheme.accent;
    final label = purchase.isVoided
        ? l.t('Annulée')
        : purchase.dueCentimes == 0
        ? l.t('Payée')
        : l.t('Payé partiellement');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.local_shipping, color: color, size: 20),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              purchase.refNo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: label, color: color),
        ],
      ),
      subtitle: Text(
        '${dateLabel(purchase.businessDate, l)}'
        '${purchase.supplierName == null ? '' : ' · ${purchase.supplierName}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(purchase.totalCentimes, context),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            paymentLabel(purchase.paymentMethod, l),
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
