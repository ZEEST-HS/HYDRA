import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/classifications.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

/// Manage the subcategories of the two fixed divisions. System subcategories
/// are locked; custom ones can be renamed, moved between divisions, merged or
/// deleted with a safe reassignment of their products.
class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryData {
  const _CategoryData({
    required this.categories,
    required this.counts,
    required this.unclassifiedProducts,
  });

  final List<Category> categories;
  final Map<int, int> counts;
  final int unclassifiedProducts;
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> {
  Future<_CategoryData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_CategoryData> _load() async {
    final c = AppScope.read(context);
    return _CategoryData(
      categories: await c.products.categories(),
      counts: await c.products.categoryCounts(),
      unclassifiedProducts: await c.products.countUnclassified(),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _add(ProductDivision division) async {
    final c = AppScope.read(context);
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (_) => _CategoryFormDialog(division: division),
    );
    if (result == null) return;
    try {
      await c.products.addCategory(
        result.nameFr,
        result.nameAr,
        division: division.code,
      );
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _rename(Category category) async {
    final c = AppScope.read(context);
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (_) => _CategoryFormDialog(
        division: ProductDivision.fromCode(category.division),
        initial: category,
      ),
    );
    if (result == null) return;
    try {
      await c.products.renameCategory(
        category.id,
        nameFr: result.nameFr,
        nameAr: result.nameAr,
      );
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _move(Category category) async {
    final c = AppScope.read(context);
    final division = await showDialog<ProductDivision>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(L10n.of(context).t('Choisir une division')),
        children: [
          for (final value in ProductDivision.values)
            ListTile(
              leading: Icon(
                value == ProductDivision.food
                    ? Icons.restaurant_outlined
                    : Icons.cleaning_services_outlined,
              ),
              title: Text(
                divisionName(value, arabic: L10n.of(context).isArabic),
              ),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (division == null) return;
    try {
      await c.products.setCategoryDivision(category.id, division.code);
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Category category, List<Category> all) async {
    final c = AppScope.read(context);
    final l = L10n.of(context);
    final targets = all
        .where((c) => c.id != category.id && c.division != null)
        .toList();
    final choice = await showDialog<_ReassignChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.t('Supprimer')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${category.displayName(l.isArabic)}\n\n'
                '${l.t('Le produit sera conservé et déplacé.')}',
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.inbox_outlined),
                        title: Text(l.t('Laisser sans catégorie')),
                        onTap: () =>
                            Navigator.pop(context, const _ReassignChoice(null)),
                      ),
                      for (final target in targets)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.subdirectory_arrow_right),
                          title: Text(target.displayName(l.isArabic)),
                          onTap: () => Navigator.pop(
                            context,
                            _ReassignChoice(target.id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.t('Annuler')),
          ),
        ],
      ),
    );
    if (choice == null) return;
    try {
      await c.products.deleteCategory(
        category.id,
        targetCategoryId: choice.targetId,
      );
      _reload();
      if (mounted) showInfo(context, l.t('Succès'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Gérer les catégories')),
        actions: [
          PopupMenuButton<ProductDivision>(
            tooltip: l.t('Nouvelle sous-catégorie'),
            icon: const Icon(Icons.add),
            onSelected: _add,
            itemBuilder: (context) => [
              for (final division in ProductDivision.values)
                PopupMenuItem(
                  value: division,
                  child: Text(
                    '${l.t('Ajouter')} · '
                    '${divisionName(division, arabic: l.isArabic)}',
                  ),
                ),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_CategoryData>(
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
          final unclassified = data.categories
              .where((c) => c.division == null)
              .toList();
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (data.unclassifiedProducts > 0)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer
                          .withValues(alpha: 0.5),
                      child: ListTile(
                        leading: const Icon(Icons.report_problem_outlined),
                        title: Text(l.t('Produits non classés')),
                        subtitle: Text(
                          l.fill(
                            'Cette catégorie contient {count} produit(s)',
                            {'count': data.unclassifiedProducts},
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (final division in ProductDivision.values) ...[
                    _DivisionHeader(
                      division: division,
                      count: data.categories
                          .where((c) => c.division == division.code)
                          .length,
                    ),
                    Card(
                      child: Column(
                        children: [
                          for (final category in data.categories.where(
                            (c) => c.division == division.code,
                          ))
                            _CategoryTile(
                              category: category,
                              count: data.counts[category.id] ?? 0,
                              onRename: () => _rename(category),
                              onMove: () => _move(category),
                              onDelete: data.categories.length > 1
                                  ? () => _delete(category, data.categories)
                                  : null,
                            ),
                          ListTile(
                            leading: const Icon(Icons.add_circle_outline),
                            title: Text(l.t('Nouvelle sous-catégorie')),
                            onTap: () => _add(division),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (unclassified.isNotEmpty) ...[
                    _DivisionHeader(division: null, count: unclassified.length),
                    Card(
                      child: Column(
                        children: [
                          for (final category in unclassified)
                            _CategoryTile(
                              category: category,
                              count: data.counts[category.id] ?? 0,
                              onRename: () => _rename(category),
                              onMove: () => _move(category),
                              onDelete: () =>
                                  _delete(category, data.categories),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DivisionHeader extends StatelessWidget {
  const _DivisionHeader({required this.division, required this.count});
  final ProductDivision? division;
  final int count;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final color = division == null
        ? scheme.outline
        : division == ProductDivision.food
        ? scheme.primary
        : scheme.tertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Icon(
            division == null
                ? Icons.inbox_outlined
                : division == ProductDivision.food
                ? Icons.restaurant_outlined
                : Icons.cleaning_services_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            division == null
                ? l.t('Produits non classés')
                : divisionName(division!, arabic: l.isArabic),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onRename,
    required this.onMove,
    required this.onDelete,
  });

  final Category category;
  final int count;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return ListTile(
      leading: Icon(
        category.isSystem ? Icons.lock_outline : Icons.folder_outlined,
        size: 20,
      ),
      title: Text(category.displayName(l.isArabic)),
      subtitle: Text(
        '${category.nameFr} · '
        '${l.fill('Cette catégorie contient {count} produit(s)', {'count': count})}',
      ),
      trailing: category.isSystem
          ? Tooltip(
              message: l.t('Catégories prédéfinies'),
              child: Icon(
                Icons.verified_outlined,
                color: Theme.of(context).colorScheme.outline,
                size: 20,
              ),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'rename') onRename();
                if (value == 'move') onMove();
                if (value == 'delete') onDelete?.call();
              },
              itemBuilder: (context) => [
                PopupMenuItem(value: 'rename', child: Text(l.t('Renommer'))),
                PopupMenuItem(
                  value: 'move',
                  child: Text(l.t('Choisir une division')),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    l.t('Supprimer'),
                    style: TextStyle(color: AppTheme.danger),
                  ),
                ),
              ],
            ),
    );
  }
}

class _ReassignChoice {
  const _ReassignChoice(this.targetId);
  final int? targetId;
}

class _CategoryFormResult {
  const _CategoryFormResult(this.nameFr, this.nameAr);
  final String nameFr;
  final String? nameAr;
}

class _CategoryFormDialog extends StatefulWidget {
  const _CategoryFormDialog({required this.division, this.initial});
  final ProductDivision? division;
  final Category? initial;

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  late final TextEditingController _fr;
  late final TextEditingController _ar;

  @override
  void initState() {
    super.initState();
    _fr = TextEditingController(text: widget.initial?.nameFr ?? '');
    _ar = TextEditingController(text: widget.initial?.nameAr ?? '');
  }

  @override
  void dispose() {
    _fr.dispose();
    _ar.dispose();
    super.dispose();
  }

  void _save() {
    if (_fr.text.trim().isEmpty) return;
    Navigator.pop(
      context,
      _CategoryFormResult(
        _fr.text.trim(),
        _ar.text.trim().isEmpty ? null : _ar.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l.t('Nouvelle sous-catégorie')
            : l.t('Renommer'),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.division != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(
                      widget.division == ProductDivision.food
                          ? Icons.restaurant_outlined
                          : Icons.cleaning_services_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      divisionName(widget.division!, arabic: l.isArabic),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _fr,
              autofocus: true,
              decoration: InputDecoration(labelText: l.t('Nom')),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ar,
              decoration: const InputDecoration(labelText: 'الاسم بالعربية'),
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(onPressed: _save, child: Text(l.t('Enregistrer'))),
      ],
    );
  }
}
