import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../data/repositories/inventory_repository.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/expiry_picker.dart';

/// Inventory workspace: stock adjustments, expiry alerts, a counting session
/// and the stock movement journal.
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final index = initialTab < 0 ? 0 : (initialTab > 3 ? 3 : initialTab);
    return DefaultTabController(
      length: 4,
      initialIndex: index,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l.t('Stock')),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: l.t('Produits')),
              Tab(text: l.t('Péremptions')),
              Tab(text: l.t('Inventaire')),
              Tab(text: l.t('Mouvements')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StockTab(),
            _ExpiryTab(),
            _StocktakeTab(),
            _MovementsTab(),
          ],
        ),
      ),
    );
  }
}

class _StockTab extends StatefulWidget {
  const _StockTab();

  @override
  State<_StockTab> createState() => _StockTabState();
}

class _StockTabState extends State<_StockTab> {
  final _search = TextEditingController();
  bool _lowOnly = false;
  Future<List<Product>>? _future;

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

  Future<List<Product>> _load() =>
      AppScope.read(context).products
          .search(_search.text.trim(), lowStockOnly: _lowOnly, limit: 500);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _adjust(Product product) async {
    final input = await showDialog<_StockCountInput>(
      context: context,
      builder: (_) => _StockCountDialog(
        title: AppScope.of(context).l10n.t('Ajuster le stock'),
        product: product,
        initialCountedMilli: product.stockMilli,
        allowBatch: true,
      ),
    );
    if (input == null || !mounted) return;
    try {
      await AppScope.of(context).inventory.setCountedStock(
        productId: product.id,
        countedMilli: input.countedMilli,
        reason: input.reason,
        expiryDate: input.expiryDate,
        batchNo: input.batchNo,
      );
      if (!mounted) return;
      showInfo(context, AppScope.of(context).l10n.t('Stock ajusté'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
              const SizedBox(height: 8),
              Row(
                children: [
                  FilterChip(
                    label: Text(l.t('Stock faible')),
                    selected: _lowOnly,
                    onSelected: (value) {
                      setState(() {
                        _lowOnly = value;
                      });
                      _reload();
                    },
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l.t('Actualiser'),
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
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
              final products = snapshot.data ?? const <Product>[];
              if (products.isEmpty) {
                return EmptyState(
                  message: l.t('Aucun produit'),
                  icon: Icons.inventory_2_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final color = Color(
                    stockColor(product.stockMilli, product.minStockMilli),
                  );
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.12),
                      child: Icon(
                        product.stockMilli <= 0
                            ? Icons.remove_shopping_cart
                            : Icons.inventory_2_outlined,
                        color: color,
                        size: 20,
                      ),
                    ),
                    title: Text(product.displayName(l.isArabic)),
                    subtitle: Text(
                      '${stockLabel(product.stockMilli, product.baseUnit, l)}'
                      ' · ${l.t('Stock minimum')} '
                      '${stockLabel(product.minStockMilli, product.baseUnit, l)}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money(product.priceCentimes, context),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          product.stockMilli <= 0
                              ? l.t('Rupture de stock')
                              : product.isLowStock
                              ? l.t('Stock faible')
                              : '',
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                      ],
                    ),
                    onTap: () => _adjust(product),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ExpiryTab extends StatefulWidget {
  const _ExpiryTab();

  @override
  State<_ExpiryTab> createState() => _ExpiryTabState();
}

class _ExpiryTabState extends State<_ExpiryTab> {
  Future<List<ExpiringBatch>>? _future;
  int _days = 30;
  int _view = 0;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ExpiringBatch>> _load() async {
    final c = AppScope.read(context);
    _days = await c.settings.expiryAlertDays();
    switch (_view) {
      case 1:
        return c.inventory.expiredBatches();
      case 2:
        return c.inventory.missingExpiryBatches();
      default:
        return c.inventory.expiringBatches(days: _days);
    }
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _disposeBatch(ExpiringBatch batch) async {
    final input = await showDialog<_DisposalInput>(
      context: context,
      builder: (_) => _DisposalDialog(batch: batch),
    );
    if (input == null || !mounted) return;
    try {
      await AppScope.of(context).inventory.disposeBatch(
        batchId: batch.id,
        qtyMilli: input.qtyMilli,
        reason: input.reason,
      );
      if (!mounted) return;
      showInfo(context, AppScope.of(context).l10n.t('Succès'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: 0,
                  label: Text(l.t('Proches')),
                  icon: const Icon(Icons.event_busy_outlined, size: 16),
                ),
                ButtonSegment(
                  value: 1,
                  label: Text(l.t('Périmés')),
                  icon: const Icon(Icons.error_outline, size: 16),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text(l.t('Sans date')),
                  icon: const Icon(Icons.help_outline, size: 16),
                ),
              ],
              selected: {_view},
              onSelectionChanged: (selection) {
                setState(() => _view = selection.first);
                _reload();
              },
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<ExpiringBatch>>(
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
              final batches = snapshot.data ?? const <ExpiringBatch>[];
              if (batches.isEmpty) {
                return EmptyState(
                  message: _view == 0
                      ? l.t('Aucun lot périme bientôt')
                      : _view == 1
                      ? l.t('Aucun lot périmé')
                      : l.t('Tous les lots ont une date de péremption'),
                  icon: _view == 1
                      ? Icons.event_available_outlined
                      : Icons.event_busy_outlined,
                  action: OutlinedButton.icon(
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                    label: Text(l.t('Actualiser')),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Text(
                      _view == 0
                          ? '${l.t('Lots arrivant à expiration dans')} $_days ${l.t('jours')}'
                          : _view == 1
                          ? l.t('Lots périmés')
                          : l.t('Date de péremption manquante'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Column(
                        children: [
                          for (final batch in batches)
                            _batchTile(batch, l, context),
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
    );
  }

  Widget _batchTile(ExpiringBatch batch, L10n l, BuildContext context) {
    final days = Dates.daysUntil(batch.expiryDate);
    final expired = (_view == 1) || (days != null && days < 0);
    final color = expired || (days != null && days <= 7)
        ? AppTheme.danger
        : AppTheme.accent;
    final expiryText = days == null
        ? ' · ${l.t('Date de péremption manquante')}'
        : expired
        ? ' · ${l.t('Expiré')}'
        : ' · ${l.t('dans')} $days ${l.t('jours')}';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          expired ? Icons.error_outline : Icons.event_busy,
          color: color,
          size: 20,
        ),
      ),
      title: Text(batch.productName),
      subtitle: Text(
        '${l.t('Péremption')} : ${batch.expiryDate ?? '—'}$expiryText'
        '${batch.batchNo == null ? '' : ' · ${l.t('Lot')} ${batch.batchNo}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                stockLabel(batch.qtyRemainingMilli, batch.baseUnit, l),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (expired)
                Text(
                  l.t('Expiré'),
                  style: TextStyle(fontSize: 11, color: AppTheme.danger),
                ),
            ],
          ),
          IconButton(
            tooltip: l.t('Jeter'),
            onPressed: () => _disposeBatch(batch),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
    );
  }
}

class _DisposalInput {
  const _DisposalInput(this.qtyMilli, this.reason);
  final int qtyMilli;
  final String reason;
}

class _DisposalDialog extends StatefulWidget {
  const _DisposalDialog({required this.batch});
  final ExpiringBatch batch;

  @override
  State<_DisposalDialog> createState() => _DisposalDialogState();
}

class _DisposalDialogState extends State<_DisposalDialog> {
  late final TextEditingController _qty;
  final _reason = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(
      text: Qty.format(widget.batch.qtyRemainingMilli),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final l = L10n.of(context);
    final qty = Qty.tryParse(_qty.text);
    if (qty == null || qty <= 0 || qty > widget.batch.qtyRemainingMilli) {
      setState(() => _error = l.t('Quantité invalide.'));
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = l.t('Motif obligatoire'));
      return;
    }
    Navigator.pop(context, _DisposalInput(qty, _reason.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l.t('Confirmer la mise au rebut ?')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.batch.productName}\n'
              '${l.t('Péremption')} : ${widget.batch.expiryDate ?? '—'}',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              l.t(
                'Le stock sera retiré et l\'opération enregistrée dans le journal.',
              ),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Quantité à jeter'),
                suffixText: unitLabel(widget.batch.baseUnit, l),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reason,
              decoration: InputDecoration(labelText: l.t('Motif du mouvement')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: scheme.error),
          child: Text(l.t('Jeter')),
        ),
      ],
    );
  }
}

class _StocktakeTab extends StatefulWidget {
  const _StocktakeTab();

  @override
  State<_StocktakeTab> createState() => _StocktakeTabState();
}

class _StocktakeTabState extends State<_StocktakeTab> {
  final _search = TextEditingController();
  final Map<int, int> _counts = {};
  Future<List<Product>>? _future;
  List<Product> _products = const [];
  bool _saving = false;

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

  Future<List<Product>> _load() async {
    final products = await AppScope.read(context).products.all(limit: 2000);
    _products = products;
    return products;
  }

  void _reload() => setState(() {
    _future = _load();
    _counts.clear();
  });

  List<Product> get _filtered {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _products;
    return _products
        .where(
          (p) =>
              p.name.toLowerCase().contains(query) ||
              (p.nameAr ?? '').contains(query) ||
              (p.barcode ?? '').contains(query),
        )
        .toList();
  }

  Future<void> _count(Product product) async {
    final input = await showDialog<_StockCountInput>(
      context: context,
      builder: (_) => _StockCountDialog(
        title: AppScope.of(context).l10n.t('Stock compté'),
        product: product,
        initialCountedMilli: _counts[product.id] ?? product.stockMilli,
        reasonRequired: false,
      ),
    );
    if (input == null || !mounted) return;
    setState(() => _counts[product.id] = input.countedMilli);
  }

  Future<void> _confirm() async {
    if (_counts.isEmpty) {
      showInfo(context, AppScope.of(context).l10n.t('Aucune modification'));
      return;
    }
    final l = AppScope.of(context).l10n;
    final reason = await promptText(
      context,
      title: l.t('Motif du mouvement'),
      hint: l.t('Inventaire'),
    );
    if (reason == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final adjusted = await AppScope.of(context).inventory.confirmStocktake([
        for (final entry in _counts.entries)
          StocktakeEntry(productId: entry.key, countedMilli: entry.value),
      ], reason);
      if (!mounted) return;
      showInfo(context, '$adjusted ${l.t('produit(s) ajusté(s)')}');
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l.t('Rechercher'),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _counts.isEmpty
                  ? null
                  : Chip(label: Text('${_counts.length} ${l.t('compté(s)')}')),
            ),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Product>>(
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
              final products = _filtered;
              if (products.isEmpty) {
                return EmptyState(
                  message: l.t('Aucun produit'),
                  icon: Icons.inventory_2_outlined,
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                itemCount: products.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = products[index];
                  final counted = _counts[product.id];
                  final delta = counted == null
                      ? null
                      : counted - product.stockMilli;
                  return ListTile(
                    title: Text(product.displayName(l.isArabic)),
                    subtitle: Text(
                      '${l.t('Stock actuel')} : '
                      '${stockLabel(product.stockMilli, product.baseUnit, l)}',
                    ),
                    trailing: counted == null
                        ? OutlinedButton(
                            onPressed: () => _count(product),
                            child: Text(l.t('Compter')),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                stockLabel(counted, product.baseUnit, l),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                delta == null || delta == 0
                                    ? l.t('Aucune modification')
                                    : '${delta > 0 ? '+' : ''}'
                                          '${Qty.format(delta)}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: delta == null || delta == 0
                                      ? Theme.of(context).colorScheme.outline
                                      : (delta > 0
                                            ? AppTheme.success
                                            : AppTheme.danger),
                                ),
                              ),
                            ],
                          ),
                    onTap: () => _count(product),
                  );
                },
              );
            },
          ),
        ),
        if (_counts.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _confirm,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: Text(
                    _saving
                        ? l.t('Enregistrement…')
                        : '${l.t('Valider l\'inventaire')} (${_counts.length})',
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MovementsTab extends StatefulWidget {
  const _MovementsTab();

  @override
  State<_MovementsTab> createState() => _MovementsTabState();
}

class _MovementsTabState extends State<_MovementsTab> {
  Future<List<StockMovement>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<StockMovement>> _load() =>
      AppScope.read(context).inventory.recentMovements(limit: 300);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  String _typeLabel(String type, L10n l) {
    switch (type) {
      case 'purchase':
        return l.t('Achat');
      case 'sale':
        return l.t('Vente');
      case 'sale_void':
        return l.t('Annulation vente');
      case 'purchase_void':
        return l.t('Annulation achat');
      case 'return':
        return l.t('Retour client');
      case 'stocktake':
        return l.t('Inventaire');
      case 'initial':
        return l.t('Initial');
      case 'disposal':
        return l.t('Mise au rebut');
      default:
        return l.t('Ajustement manuel');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return FutureBuilder<List<StockMovement>>(
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
        final movements = snapshot.data ?? const <StockMovement>[];
        if (movements.isEmpty) {
          return EmptyState(
            message: l.t('Aucun mouvement'),
            icon: Icons.swap_vert,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: movements.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final movement = movements[index];
              final positive = movement.qtyDeltaMilli >= 0;
              final color = positive ? AppTheme.success : AppTheme.danger;
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(
                    positive ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color,
                    size: 18,
                  ),
                ),
                title: Text(movement.productName ?? l.t('Produit')),
                subtitle: Text(
                  '${_typeLabel(movement.type, l)}'
                  ' · ${Dates.formatDateTime(DateTime.fromMillisecondsSinceEpoch(movement.createdAt))}'
                  '${movement.reason == null ? '' : ' · ${movement.reason}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  '${positive ? '+' : ''}${Qty.format(movement.qtyDeltaMilli)}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _StockCountInput {
  const _StockCountInput(
    this.countedMilli,
    this.reason, {
    this.expiryDate,
    this.batchNo,
  });
  final int countedMilli;
  final String reason;
  final String? expiryDate;
  final String? batchNo;
}

class _StockCountDialog extends StatefulWidget {
  const _StockCountDialog({
    required this.title,
    required this.product,
    required this.initialCountedMilli,
    this.reasonRequired = true,
    this.allowBatch = false,
  });

  final String title;
  final Product product;
  final int initialCountedMilli;
  final bool reasonRequired;
  final bool allowBatch;

  @override
  State<_StockCountDialog> createState() => _StockCountDialogState();
}

class _StockCountDialogState extends State<_StockCountDialog> {
  late final TextEditingController _counted;
  final _reason = TextEditingController();
  final _batchNo = TextEditingController();
  String? _expiry;
  String? _error;

  @override
  void initState() {
    super.initState();
    _counted = TextEditingController(
      text: Qty.format(widget.initialCountedMilli),
    );
  }

  @override
  void dispose() {
    _counted.dispose();
    _reason.dispose();
    _batchNo.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final value = await pickIsoDate(context, initial: _expiry);
    if (value != null && mounted) setState(() => _expiry = value);
  }

  void _submit() {
    final l = L10n.of(context);
    final value = Qty.tryParse(_counted.text);
    if (value == null || value < 0) {
      setState(() => _error = l.t('Quantité invalide.'));
      return;
    }
    if (widget.reasonRequired && _reason.text.trim().isEmpty) {
      setState(() => _error = l.t('Motif obligatoire'));
      return;
    }
    Navigator.pop(
      context,
      _StockCountInput(
        value,
        _reason.text.trim().isEmpty
            ? l.t('Ajustement manuel')
            : _reason.text.trim(),
        expiryDate: _expiry,
        batchNo: _batchNo.text.trim().isEmpty ? null : _batchNo.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${l.t('Stock actuel')} : '
              '${stockLabel(widget.initialCountedMilli, widget.product.baseUnit, l)}',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _counted,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Stock compté'),
                suffixText: unitLabel(widget.product.baseUnit, l),
              ),
            ),
            if (widget.allowBatch) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.event_outlined, size: 18),
                      label: Text(
                        _expiry ?? l.t('Date de péremption (facultatif)'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_expiry != null)
                    IconButton(
                      tooltip: l.t('Supprimer'),
                      onPressed: () => setState(() => _expiry = null),
                      icon: const Icon(Icons.clear, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _batchNo,
                decoration: InputDecoration(
                  labelText: l.t('Numéro de lot (facultatif)'),
                ),
              ),
            ],
            if (widget.reasonRequired) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _reason,
                decoration: InputDecoration(
                  labelText: l.t('Motif du mouvement'),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(onPressed: _submit, child: Text(l.t('Valider'))),
      ],
    );
  }
}
