import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../services/file_share_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'sale_detail_screen.dart';

enum SalesPeriod { today, week, month, all, custom }

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  final _search = TextEditingController();
  SalesPeriod _period = SalesPeriod.week;
  DateTimeRange? _customRange;
  Future<_SalesData>? _future;

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
      case SalesPeriod.today:
        return DateTimeRange(start: now, end: now);
      case SalesPeriod.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
      case SalesPeriod.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case SalesPeriod.custom:
        return _customRange;
      case SalesPeriod.all:
        return null;
    }
  }

  Future<_SalesData> _load() async {
    final c = AppScope.read(context);
    final range = _range();
    final sales = await c.sales.list(
      from: range?.start,
      to: range?.end,
      query: _search.text.trim().isEmpty ? null : _search.text.trim(),
      limit: 300,
    );
    var total = 0;
    var paid = 0;
    var due = 0;
    var returned = 0;
    for (final sale in sales) {
      if (sale.isVoided) continue;
      total += sale.totalCentimes;
      paid += sale.paidCentimes;
      due += sale.dueCentimes;
      returned += sale.returnedCentimes;
    }
    return _SalesData(sales, total, paid, due, returned);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

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
      _period = SalesPeriod.custom;
      _future = _load();
    });
  }

  Future<void> _export(_SalesData data) async {
    final c = AppScope.of(context);
    final l = c.l10n;
    try {
      final range = _range();
      final csv = await c.io.exportSalesCsv(from: range?.start, to: range?.end);
      await const FileShareService().shareCsv(
        fileName: 'ventes_${Dates.businessDate()}.csv',
        csv: csv,
        subject: l.t('Ventes'),
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
        title: Text(l.t('Ventes')),
        actions: [
          IconButton(
            tooltip: l.t('Exporter les ventes'),
            onPressed: _future == null
                ? null
                : () async {
                    final data = await _future!;
                    if (mounted) await _export(data);
                  },
            icon: const Icon(Icons.ios_share),
          ),
        ],
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
                  for (final period in SalesPeriod.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(_periodLabel(period, l)),
                        selected: _period == period,
                        onSelected: (_) {
                          if (period == SalesPeriod.custom) {
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
              child: FutureBuilder<_SalesData>(
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
                        _SalesSummary(data: data),
                        const SizedBox(height: 12),
                        if (data.sales.isEmpty)
                          EmptyState(
                            message: l.t('Aucune vente'),
                            icon: Icons.receipt_long_outlined,
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (final sale in data.sales)
                                  _SaleTile(
                                    sale: sale,
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              SaleDetailScreen(saleId: sale.id),
                                        ),
                                      );
                                      if (mounted) _reload();
                                    },
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

  String _periodLabel(SalesPeriod period, L10n l) {
    switch (period) {
      case SalesPeriod.today:
        return l.t('Aujourd\'hui');
      case SalesPeriod.week:
        return l.t('7 derniers jours');
      case SalesPeriod.month:
        return l.t('Ce mois');
      case SalesPeriod.all:
        return l.t('Tous');
      case SalesPeriod.custom:
        return _customRange == null
            ? l.t('Personnalisé')
            : '${Dates.formatDate(_customRange!.start)} – '
                  '${Dates.formatDate(_customRange!.end)}';
    }
  }
}

class _SalesData {
  const _SalesData(this.sales, this.total, this.paid, this.due, this.returned);
  final List<Sale> sales;
  final int total;
  final int paid;
  final int due;
  final int returned;
}

class _SalesSummary extends StatelessWidget {
  const _SalesSummary({required this.data});
  final _SalesData data;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 700 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        final cards = [
          StatCard(
            label: l.t('Total des ventes'),
            value: money(data.total, context),
            icon: Icons.receipt_long_outlined,
            footnote: '${data.sales.length} ${l.t('vente(s)')}',
          ),
          StatCard(
            label: l.t('Payé'),
            value: money(data.paid, context),
            icon: Icons.payments_outlined,
            color: AppTheme.success,
          ),
          StatCard(
            label: l.t('Impayés'),
            value: money(data.due, context),
            icon: Icons.schedule,
            color: data.due > 0 ? AppTheme.danger : AppTheme.success,
          ),
          StatCard(
            label: l.t('Retours'),
            value: money(data.returned, context),
            icon: Icons.keyboard_return,
            color: AppTheme.accent,
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

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.sale, required this.onTap});
  final Sale sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final (label, color) = _status(context, l);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(Icons.receipt_long, color: color, size: 20),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              sale.invoiceNo,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          StatusChip(label: label, color: color),
        ],
      ),
      subtitle: Text(
        '${dateLabel(sale.businessDate, l)}'
        '${sale.customerName == null ? '' : ' · ${sale.customerName}'}'
        '${sale.returnedCentimes > 0 ? ' · ${l.t('Retours')}: ${money(sale.returnedCentimes, context)}' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            money(sale.totalCentimes, context),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          Text(
            paymentLabel(sale.paymentMethod, l),
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

  (String, Color) _status(BuildContext context, L10n l) {
    if (sale.isVoided) return (l.t('Annulée'), AppTheme.danger);
    if (sale.returnedCentimes >= sale.totalCentimes && sale.totalCentimes > 0) {
      return (l.t('Retours'), AppTheme.accent);
    }
    if (sale.dueCentimes == 0) return (l.t('Payée'), AppTheme.success);
    if (sale.paidCentimes == 0) return (l.t('Impayé'), AppTheme.danger);
    return (l.t('Payé partiellement'), AppTheme.accent);
  }
}
