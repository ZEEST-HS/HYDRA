import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../ui/widgets/common.dart';
import 'scanner_sheet.dart';

/// Searchable product picker. Prices and stock shown here are local only.
Future<Product?> pickProduct(
  BuildContext context, {
  String title = 'Sélectionner un produit',
  bool includeInactive = false,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        ProductPickerSheet(title: title, includeInactive: includeInactive),
  );
}

class ProductPickerSheet extends StatefulWidget {
  const ProductPickerSheet({
    super.key,
    this.title = 'Sélectionner un produit',
    this.includeInactive = false,
  });

  final String title;
  final bool includeInactive;

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  final _search = TextEditingController();
  List<Product> _products = const [];
  bool _loading = true;
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await AppScope.read(context).products.search(
        _search.text.trim(),
        includeInactive: widget.includeInactive,
        limit: 500,
      );
      if (!mounted) return;
      setState(() {
        _products = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code == null || !mounted) return;
    final product = await AppScope.of(context).products.findByBarcode(code);
    if (!mounted) return;
    if (product == null) {
      showError(context, AppScope.of(context).l10n.t('Produit introuvable'));
      return;
    }
    Navigator.of(context).pop(product);
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l.t(widget.title),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.t('Scanner'),
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _search,
                autofocus: false,
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
              const SizedBox(height: 10),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? EmptyState(
                        message: _error!,
                        icon: Icons.error_outline,
                        action: FilledButton(
                          onPressed: _load,
                          child: Text(l.t('Réessayer')),
                        ),
                      )
                    : _products.isEmpty
                    ? EmptyState(
                        message: l.t('Aucun produit'),
                        icon: Icons.inventory_2_outlined,
                      )
                    : ListView.separated(
                        itemCount: _products.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final product = _products[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primaryContainer,
                              child: Text(
                                product.name.trim().isEmpty
                                    ? '?'
                                    : product.name.trim()[0].toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              product.displayName(l.isArabic),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${Qty.format(product.stockMilli)} '
                              '${unitLabel(product.baseUnit, l)}'
                              '${product.barcode == null ? '' : ' · ${product.barcode}'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              money(product.costCentimes, context),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            onTap: () => Navigator.of(context).pop(product),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
