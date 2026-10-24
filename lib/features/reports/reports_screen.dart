import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../domain/reports/report_service.dart';
import '../../services/file_share_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

enum _ReportPeriod { today, week, month, all, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _ReportPeriod _period = _ReportPeriod.month;
  DateTimeRange? _customRange;
  Future<_ReportData>? _future;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  DateTimeRange _summaryRange() {
    final now = DateTime.now();
    switch (_period) {
      case _ReportPeriod.today:
        return DateTimeRange(start: now, end: now);
      case _ReportPeriod.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
      case _ReportPeriod.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _ReportPeriod.all:
        return DateTimeRange(start: DateTime(2000, 1, 1), end: now);
      case _ReportPeriod.custom:
        return _customRange ??
            DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  Future<_ReportData> _load() async {
    final c = AppScope.read(context);
    final range = _summaryRange();
    final now = DateTime.now();
    var chartStart = range.start;
    var chartEnd = range.end;
    // Keep the chart readable on a phone even for a very long custom period.
    if (chartEnd.difference(chartStart).inDays > 120) {
      chartStart = chartEnd.subtract(const Duration(days: 59));
    }
    final results = await Future.wait<Object>([
      c.reports.summary(from: range.start, to: range.end),
      c.reports.dailySeries(chartStart, chartEnd),
      c.reports.topProducts(from: range.start, to: range.end, limit: 10),
      c.reports.paymentBreakdown(from: range.start, to: range.end),
      c.reports.expenseByCategory(from: range.start, to: range.end),
    ]);
    return _ReportData(
      summary: results[0] as ReportSummary,
      points: results[1] as List<DailyPoint>,
      topProducts: results[2] as List<TopProduct>,
      payments: results[3] as Map<String, int>,
      expenses: results[4] as Map<String, int>,
      chartClipped: chartStart != range.start,
      generatedAt: now,
    );
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
    if (range == null || !mounted) return;
    setState(() {
      _customRange = range;
      _period = _ReportPeriod.custom;
      _future = _load();
    });
  }

  Future<void> _export(String kind) async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final range = _summaryRange();
    setState(() => _exporting = true);
    try {
      final share = const FileShareService();
      switch (kind) {
        case 'sales':
          final csv = await c.io.exportSalesCsv(
            from: range.start,
            to: range.end,
          );
          await share.shareCsv(
            fileName: 'ventes_${Dates.businessDate()}.csv',
            csv: csv,
            subject: l.t('Ventes'),
          );
        case 'products':
          final products = await c.products.all(limit: 5000);
          await share.shareBytes(
            fileName: 'produits_${Dates.businessDate()}.xlsx',
            bytes: c.io.exportProductsXlsx(products),
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            subject: l.t('Produits'),
          );
        case 'customers':
          final csv = await c.io.exportCustomerDebtsCsv();
          await share.shareCsv(
            fileName: 'dettes_clients_${Dates.businessDate()}.csv',
            csv: csv,
            subject: l.t('Dettes clients'),
          );
        case 'suppliers':
          final csv = await c.io.exportSupplierDebtsCsv();
          await share.shareCsv(
            fileName: 'dettes_fournisseurs_${Dates.businessDate()}.csv',
            csv: csv,
            subject: l.t('Dettes fournisseurs'),
          );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Rapports')),
        bottom: _exporting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          PopupMenuButton<String>(
            tooltip: l.t('Exporter'),
            onSelected: _export,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'sales',
                child: Text(l.t('Exporter les ventes')),
              ),
              PopupMenuItem(
                value: 'products',
                child: Text(l.t('Export Excel')),
              ),
              PopupMenuItem(
                value: 'customers',
                child: Text(l.t('Dettes clients')),
              ),
              PopupMenuItem(
                value: 'suppliers',
                child: Text(l.t('Dettes fournisseurs')),
              ),
            ],
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 1100,
        child: Column(
          children: [
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final period in _ReportPeriod.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(_periodLabel(period, l)),
                        selected: _period == period,
                        onSelected: (_) {
                          if (period == _ReportPeriod.custom) {
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
              child: FutureBuilder<_ReportData>(
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
                  return _content(snapshot.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(_ReportData data) {
    final l = L10n.of(context);
    final s = data.summary;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _summaryGrid(data),
          const SizedBox(height: 16),
          SectionTitle(l.t('Évolution des ventes')),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (data.chartClipped)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l.t(
                          'Le graphique affiche les 60 derniers jours de la période.',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  SizedBox(
                    height: 200,
                    child: _RevenueChart(points: data.points),
                  ),
                ],
              ),
            ),
          ),
          if (s.missingCostLines > 0) ...[
            const SizedBox(height: 12),
            Card(
              color: AppTheme.accent.withValues(alpha: 0.08),
              child: ListTile(
                leading: Icon(Icons.info_outline, color: AppTheme.accent),
                title: Text(l.t('Coût manquant sur certaines lignes')),
                subtitle: Text(
                  '${s.missingCostLines} ${l.t('ligne(s) avec un coût à zéro. Les marges sont surestimées.')}',
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          _breakdownCard(
            l.t('Répartition des paiements'),
            {
              for (final entry in data.payments.entries)
                paymentLabel(entry.key, l): entry.value,
            },
            [AppTheme.primary, AppTheme.info, AppTheme.accent, AppTheme.violet],
            empty: l.t('Aucune vente'),
          ),
          const SizedBox(height: 16),
          _breakdownCard(l.t('Dépenses par catégorie'), data.expenses, [
            AppTheme.danger,
            AppTheme.rose,
            AppTheme.brown,
            AppTheme.accent,
          ], empty: l.t('Aucune dépense')),
          const SizedBox(height: 16),
          SectionTitle(l.t('Produits les plus vendus')),
          if (data.topProducts.isEmpty)
            Card(
              child: EmptyState(
                message: l.t('Aucune vente'),
                icon: Icons.insights_outlined,
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < data.topProducts.length; i++)
                    _topProductTile(i, data.topProducts[i]),
                ],
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '${l.t('Bénéfice estimé (coût moyen pondéré) — hors taxes et charges non saisies.')}'
            ' · ${Dates.formatDateTime(data.generatedAt)}',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryGrid(_ReportData data) {
    final l = L10n.of(context);
    final s = data.summary;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 900
            ? 4
            : constraints.maxWidth > 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        final cards = [
          StatCard(
            label: l.t('Chiffre d\'affaires'),
            value: money(s.revenue, context),
            icon: Icons.payments_outlined,
            footnote: '${s.salesCount} ${l.t('vente(s)')}',
          ),
          StatCard(
            label: l.t('Marge brute'),
            value: money(s.grossProfit, context),
            icon: Icons.trending_up,
            color: s.grossProfit >= 0 ? AppTheme.success : AppTheme.danger,
            footnote:
                '${l.t('Coût des marchandises vendues')} '
                '${money(s.cogs, context)}',
          ),
          StatCard(
            label: l.t('Bénéfice net estimé'),
            value: money(s.netProfit, context),
            icon: Icons.account_balance_wallet_outlined,
            color: s.netProfit >= 0 ? AppTheme.success : AppTheme.danger,
            footnote: '${l.t('Dépenses')} ${money(s.expensesTotal, context)}',
          ),
          StatCard(
            label: l.t('Panier moyen'),
            value: money(s.averageBasket, context),
            icon: Icons.shopping_basket_outlined,
            color: AppTheme.info,
            footnote:
                '${l.t('Total des ventes')} ${money(s.salesTotal, context)}',
          ),
          StatCard(
            label: l.t('Retours de la période'),
            value: money(s.returnsTotal, context),
            icon: Icons.keyboard_return,
            color: AppTheme.accent,
            footnote: '${l.t('Remise')} ${money(s.discounts, context)}',
          ),
          StatCard(
            label: l.t('Total des achats'),
            value: money(s.purchasesTotal, context),
            icon: Icons.local_shipping_outlined,
            color: AppTheme.brown,
          ),
          StatCard(
            label: l.t('Trésorerie'),
            value: money(s.cashCollected, context),
            icon: Icons.account_balance_outlined,
            color: AppTheme.success,
            footnote: '${l.t('Crédit')} ${money(s.creditSales, context)}',
          ),
          StatCard(
            label: l.t('Impayés'),
            value: money(s.creditSales, context),
            icon: Icons.schedule,
            color: s.creditSales > 0 ? AppTheme.danger : AppTheme.success,
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

  Widget _breakdownCard(
    String title,
    Map<String, int> values,
    List<Color> colors, {
    required String empty,
  }) {
    var total = 0;
    for (final value in values.values) {
      total += value;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        Card(
          child: values.isEmpty || total == 0
              ? Padding(
                  padding: const EdgeInsets.all(20),
                  child: Center(child: Text(empty)),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      for (var i = 0; i < values.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _breakdownRow(
                            values.keys.elementAt(i),
                            values.values.elementAt(i),
                            total,
                            colors[i % colors.length],
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _breakdownRow(String label, int value, int total, Color color) {
    final ratio = total == 0 ? 0.0 : value / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(
              '${money(value, context)} · ${(ratio * 100).toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio.clamp(0, 1),
            minHeight: 7,
            backgroundColor: color.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }

  Widget _topProductTile(int index, TopProduct product) {
    final l = L10n.of(context);
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          '${index + 1}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      title: Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${qty(product.qtyMilli, context)} ${l.t('vendus')}'),
      trailing: Text(
        money(product.revenueCentimes, context),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  String _periodLabel(_ReportPeriod period, L10n l) {
    switch (period) {
      case _ReportPeriod.today:
        return l.t('Aujourd\'hui');
      case _ReportPeriod.week:
        return l.t('7 derniers jours');
      case _ReportPeriod.month:
        return l.t('Ce mois');
      case _ReportPeriod.all:
        return l.t('Tous');
      case _ReportPeriod.custom:
        return _customRange == null
            ? l.t('Personnalisé')
            : '${Dates.formatDate(_customRange!.start)} – '
                  '${Dates.formatDate(_customRange!.end)}';
    }
  }
}

class _ReportData {
  const _ReportData({
    required this.summary,
    required this.points,
    required this.topProducts,
    required this.payments,
    required this.expenses,
    required this.chartClipped,
    required this.generatedAt,
  });

  final ReportSummary summary;
  final List<DailyPoint> points;
  final List<TopProduct> topProducts;
  final Map<String, int> payments;
  final Map<String, int> expenses;
  final bool chartClipped;
  final DateTime generatedAt;
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points});
  final List<DailyPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const Center(child: Text('—'));
    }
    var maxDirs = 0;
    for (final point in points) {
      maxDirs = max(maxDirs, point.revenue);
    }
    final maxY = max(100.0, (maxDirs / 100) * 1.2);
    final primary = Theme.of(context).colorScheme.primary;
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(enabled: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(
            color: Theme.of(context).colorScheme.outlineVariant
                .withValues(alpha: 0.5),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  '${value.toStringAsFixed(0)} DH',
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                final step = max(1, (points.length / 6).ceil());
                if (index % step != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    Dates.formatDateShort(points[index].date),
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: points[i].revenue / 100,
                  width: points.length > 40 ? 4 : 10,
                  color: primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
