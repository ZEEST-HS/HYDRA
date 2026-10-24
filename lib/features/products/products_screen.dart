import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/classifications.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'category_management_screen.dart';
import 'product_form_screen.dart';

/// Products browser organised as: division → subcategory → products.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _search = TextEditingController();
  List<Product> _products = const [];
  List<Category> _categories = const [];
  Map<String, int> _divisionCounts = const {};
  ProductDivision? _division;
  int? _categoryId;
  bool _unclassified = false;
  int _unclassifiedCount = 0;
  bool _loading = true;
  bool _lowOnly = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    final query = _search.text.trim();
    final useFilters = query.isEmpty;
    try {
      final products = await c.products.search(
        query,
        lowStockOnly: _lowOnly,
        division: useFilters && !_unclassified ? _division?.code : null,
        categoryId: useFilters && !_unclassified ? _categoryId : null,
        unclassifiedOnly: useFilters && _unclassified,
      );
      final categories = _division == null
          ? const <Category>[]
          : await c.products.categoriesForDivision(_division!.code);
      final counts = await c.products.divisionCounts();
      final unclassified = await c.products.countUnclassified();
      if (!mounted) return;
      setState(() {
        _products = products;
        _categories = categories;
        _divisionCounts = counts;
        _unclassifiedCount = unclassified;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openForm([Product? product]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProductFormScreen(product: product, initialCategoryId: _categoryId),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openCategories() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const CategoryManagementScreen()),
    );
    await _load();
  }

  void _selectDivision(ProductDivision? division) {
    setState(() {
      _division = _division == division ? null : division;
      _categoryId = null;
      _unclassified = false;
    });
    _load();
  }

  void _selectAll() {
    setState(() {
      _division = null;
      _categoryId = null;
      _unclassified = false;
    });
    _load();
  }

  void _selectCategory(int? id) {
    setState(() {
      _categoryId = _categoryId == id ? null : id;
      _unclassified = false;
    });
    _load();
  }

  Future<void> _delete(Product product) async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final ok = await confirm(
      context,
      title: l.t('Supprimer le produit'),
      message:
          '${product.name}\n${l.t('L\'historique des ventes est conservé.')}',
      destructive: true,
      confirmLabel: l.t('Supprimer'),
    );
    if (!ok) return;
    try {
      await c.products.delete(product.id, reason: 'Suppression produit');
      await _load();
      if (mounted) showInfo(context, l.t('Produit supprimé'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Produits')),
        actions: [
          IconButton(
            tooltip: l.t('Gérer les catégories'),
            onPressed: _openCategories,
            icon: const Icon(Icons.category_outlined),
          ),
          IconButton(
            tooltip: l.t('Ajouter un produit'),
            onPressed: _openForm,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: Text(l.t('Produit')),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        textInputAction: TextInputAction.search,
                        onChanged: (_) => _load(),
                        decoration: InputDecoration(
                          hintText: l.t('Rechercher par nom, code ou marque'),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _search.text.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _search.clear();
                                    _load();
                                  },
                                  icon: const Icon(Icons.clear),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l.t('Stock faible')),
                      selected: _lowOnly,
                      onSelected: (value) {
                        setState(() => _lowOnly = value);
                        _load();
                      },
                    ),
                  ],
                ),
              ),
              _filters(l),
              Expanded(child: _body(l)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(L10n l) {
    final searching = _search.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: _DivisionCard(
                    division: ProductDivision.food,
                    count: _divisionCounts[ProductDivision.food.code] ?? 0,
                    selected: _division == ProductDivision.food,
                    onTap: () => _selectDivision(ProductDivision.food),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DivisionCard(
                    division: ProductDivision.nonFood,
                    count: _divisionCounts[ProductDivision.nonFood.code] ?? 0,
                    selected: _division == ProductDivision.nonFood,
                    onTap: () => _selectDivision(ProductDivision.nonFood),
                  ),
                ),
              ],
            ),
          ),
        if (!searching && _division != null)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: FilterChip(
                    label: Text(l.t('Toutes les catégories')),
                    selected: _categoryId == null && !_unclassified,
                    onSelected: (_) => _selectCategory(null),
                  ),
                ),
                for (final category in _categories)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: FilterChip(
                      label: Text(category.displayName(l.isArabic)),
                      selected: _categoryId == category.id,
                      onSelected: (_) => _selectCategory(category.id),
                    ),
                  ),
              ],
            ),
          ),
        if (!searching && _division == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.all_inbox_outlined, size: 18),
                        label: Text(
                          _unclassified
                              ? l.t('Toutes les catégories')
                              : '${l.t('Produits non classés')} ($_unclassifiedCount)',
                        ),
                        onPressed: () {
                          setState(() {
                            _unclassified = !_unclassified;
                            _categoryId = null;
                          });
                          _load();
                        },
                      ),
                    ],
                  ),
                ),
                if (_unclassified || _division != null)
                  TextButton(onPressed: _selectAll, child: Text(l.t('Tous'))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _body(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EmptyState(
        message: _error!,
        icon: Icons.error_outline,
        action: FilledButton(onPressed: _load, child: Text(l.t('Réessayer'))),
      );
    }
    if (_products.isEmpty) {
      return EmptyState(
        message: l.t('Aucun produit'),
        icon: Icons.inventory_2_outlined,
        action: FilledButton.icon(
          onPressed: _openForm,
          icon: const Icon(Icons.add),
          label: Text(l.t('Créer le produit')),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 100),
        itemCount: _products.length,
        separatorBuilder: (context, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final product = _products[index];
          final category = l.isArabic
              ? (product.categoryNameAr ?? product.categoryName)
              : product.categoryName;
          return Card(
            child: ListTile(
              onTap: () => _openForm(product),
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                child: Text(
                  product.name.trim().isEmpty
                      ? '?'
                      : product.name.trim()[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      product.displayName(l.isArabic),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (product.hasPackaging)
                    Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Icon(
                        Icons.layers_outlined,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                    ),
                ],
              ),
              subtitle: Text(
                [
                  if (product.barcode != null) product.barcode!,
                  ?category,
                  '${Qty.format(product.stockMilli)} ${unitLabel(product.baseUnit, l)}',
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        money(product.priceCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        product.isOutOfStock
                            ? l.t('Rupture de stock')
                            : product.isLowStock
                            ? l.t('Stock faible')
                            : l.t('En stock'),
                        style: TextStyle(
                          fontSize: 10,
                          color: Color(
                            stockColor(
                              product.stockMilli,
                              product.minStockMilli,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') _openForm(product);
                      if (value == 'delete') _delete(product);
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(l.t('Modifier')),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(l.t('Supprimer')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DivisionCard extends StatelessWidget {
  const _DivisionCard({
    required this.division,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final ProductDivision division;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final food = division == ProductDivision.food;
    final color = food ? scheme.primary : scheme.tertiary;
    return Material(
      color: selected
          ? color.withValues(alpha: 0.16)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? color : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                food
                    ? Icons.restaurant_outlined
                    : Icons.cleaning_services_outlined,
                color: color,
                size: 26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      divisionName(division, arabic: l.isArabic),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '$count ${l.t('Articles')}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
