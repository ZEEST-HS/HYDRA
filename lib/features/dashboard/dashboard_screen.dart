import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../domain/cash/cash_service.dart';
import '../../domain/reports/report_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../cash/cash_screen.dart';
import '../inventory/inventory_screen.dart';
import '../parties/parties_screen.dart';
import '../reports/reports_screen.dart';
import '../sales/sale_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardData {
  const _DashboardData({
    required this.snapshot,
    required this.stockValue,
    required this.recentSales,
    this.session,
    this.breakdown,
  });

  final DashboardSnapshot snapshot;
  final int stockValue;
  final List<Sale> recentSales;
  final CashSession? session;
  final CashBreakdown? breakdown;
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final c = AppScope.read(context);
    final expiryDays = await c.settings.expiryAlertDays();
    final snapshot = await c.reports.dashboard(expiryDays: expiryDays);
    final session = await c.cash.openSession();
    final sales = await c.sales.list(limit: 5);
    final stockValue = await c.products.stockValueTotal();
    CashBreakdown? breakdown;
    if (session != null) {
      breakdown = await c.cash.breakdown(session);
    }
    return _DashboardData(
      snapshot: snapshot,
      stockValue: stockValue,
      recentSales: sales,
      session: session,
      breakdown: breakdown,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              c.shop.displayName(c.isArabic),
              style: const TextStyle(fontSize: 18),
            ),
            Text(
              Dates.formatDateLong(DateTime.now(), arabic: c.isArabic),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l.t('Rapports'),
            onPressed: () => _open(const ReportsScreen()),
            icon: const Icon(Icons.insights_outlined),
          ),
          IconButton(
            tooltip: l.t('Caisse du jour'),
            onPressed: () => _open(const CashScreen()),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_DashboardData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  EmptyState(
                    message: snapshot.error.toString(),
                    icon: Icons.error_outline,
                    action: FilledButton(
                      onPressed: _refresh,
                      child: Text(l.t('Réessayer')),
                    ),
                  ),
                ],
              );
            }
            final data = snapshot.data!;
            return _content(context, data);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _DashboardData data) {
    final l = L10n.of(context);
    final s = data.snapshot;
    return PageBody(
      child: ListView(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1000
                  ? 4
                  : constraints.maxWidth > 620
                  ? 2
                  : 2;
              final width =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              final cards = [
                StatCard(
                  label: l.t('Ventes du jour'),
                  value: money(s.today.salesTotal, context),
                  icon: Icons.payments_outlined,
                  footnote: '${s.today.salesCount} ${l.t('vente(s)')}',
                  onTap: () => _open(const ReportsScreen()),
                ),
                StatCard(
                  label: l.t('Bénéfice net estimé'),
                  value: money(s.today.netProfit, context),
                  icon: Icons.trending_up,
                  color: s.today.netProfit >= 0
                      ? AppTheme.success
                      : AppTheme.danger,
                  footnote: l.t('Marge estimée (coût moyen pondéré)'),
                  onTap: () => _open(const ReportsScreen()),
                ),
                StatCard(
                  label: l.t('Dettes clients'),
                  value: money(s.customerDebt, context),
                  icon: Icons.people_outline,
                  color: AppTheme.violet,
                  onTap: () =>
                      _open(const PartiesScreen(kind: PartyKind.customer)),
                ),
                StatCard(
                  label: l.t('Valeur du stock'),
                  value: money(data.stockValue, context),
                  icon: Icons.inventory_2_outlined,
                  color: AppTheme.info,
                  footnote: '${s.productCount} ${l.t('produits')}',
                  onTap: () => _open(const InventoryScreen()),
                ),
              ];
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          _CashBanner(
            session: data.session,
            breakdown: data.breakdown,
            onTap: () => _open(const CashScreen()),
          ),
          if (s.lowStockCount > 0 || s.expiringCount > 0 || s.supplierDebt > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (s.lowStockCount > 0)
                    ActionChip(
                      avatar: Icon(
                        Icons.warning_amber,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                      label: Text('${s.lowStockCount} ${l.t('Stock faible')}'),
                      onPressed: () =>
                          _open(const InventoryScreen(initialTab: 0)),
                    ),
                  if (s.expiringCount > 0)
                    ActionChip(
                      avatar: Icon(
                        Icons.event_busy,
                        size: 18,
                        color: AppTheme.danger,
                      ),
                      label: Text(
                        '${s.expiringCount} ${l.t('Péremptions proches')}',
                      ),
                      onPressed: () =>
                          _open(const InventoryScreen(initialTab: 1)),
                    ),
                  if (s.supplierDebt > 0)
                    ActionChip(
                      avatar: Icon(
                        Icons.store_outlined,
                        size: 18,
                        color: AppTheme.brown,
                      ),
                      label: Text(
                        '${l.t('Dettes fournisseurs')} : ${money(s.supplierDebt, context)}',
                      ),
                      onPressed: () =>
                          _open(const PartiesScreen(kind: PartyKind.supplier)),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SectionTitle(l.t('7 derniers jours')),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              child: _WeekChart(points: s.last7Days),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: SectionTitle(l.t('Dernières ventes'))),
              TextButton(
                onPressed: () => _open(const ReportsScreen()),
                child: Text(l.t('Voir tout')),
              ),
            ],
          ),
          Card(
            child: data.recentSales.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(26),
                    child: EmptyState(
                      message: l.t('Aucune vente pour le moment'),
                    ),
                  )
                : Column(
                    children: [
                      for (final sale in data.recentSales)
                        ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .primaryContainer,
                            child: const Icon(Icons.receipt_long, size: 20),
                          ),
                          title: Text(sale.invoiceNo),
                          subtitle: Text(
                            '${dateLabel(sale.businessDate, l)}'
                            '${sale.customerName == null ? '' : ' · ${sale.customerName}'}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                money(sale.totalCentimes, context),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (sale.isVoided)
                                Text(
                                  l.t('Annulée'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.danger,
                                  ),
                                ),
                            ],
                          ),
                          onTap: () => _open(SaleDetailScreen(saleId: sale.id)),
                        ),
                    ],
                  ),
          ),
          if (s.topProducts.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionTitle(l.t('Produits les plus vendus')),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < s.topProducts.length; i++)
                    ListTile(
                      leading: CircleAvatar(
                        radius: 14,
                        child: Text(
                          '${i + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      title: Text(s.topProducts[i].name),
                      subtitle: Text(
                        '${qty(s.topProducts[i].qtyMilli, context)} ${l.t('vendus')}',
                      ),
                      trailing: Text(
                        money(s.topProducts[i].revenueCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _CashBanner extends StatelessWidget {
  const _CashBanner({
    required this.session,
    required this.breakdown,
    required this.onTap,
  });

  final CashSession? session;
  final CashBreakdown? breakdown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final open = session != null;
    final color = open
        ? AppTheme.success
        : Theme.of(context).colorScheme.outline;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(
            open ? Icons.lock_open : Icons.lock_outline,
            color: color,
          ),
        ),
        title: Text(
          open ? l.t('Session ouverte') : l.t('Aucune session ouverte'),
        ),
        subtitle: Text(
          open
              ? '${l.t('Espèces attendues')} : '
                    '${money(breakdown?.expectedCash ?? 0, context)}'
              : l.t('Ouvrir la caisse'),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.points});
  final List<DailyPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox(height: 120);
    var maxValue = 0;
    for (final point in points) {
      if (point.revenue > maxValue) maxValue = point.revenue;
    }
    if (maxValue == 0) maxValue = 1;
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final point in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      point.revenue == 0 ? '' : money(point.revenue, context),
                      style: const TextStyle(fontSize: 9),
                      overflow: TextOverflow.visible,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 8 + 100 * (point.revenue / maxValue),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      Dates.formatDateShort(point.date),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
