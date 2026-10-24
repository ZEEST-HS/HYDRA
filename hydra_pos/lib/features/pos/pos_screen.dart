import 'dart:math';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app/app_controller.dart';
import '../../core/errors.dart';
import '../../core/iterables.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../domain/sales/sale_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../common/scanner_sheet.dart';
import '../parties/customer_picker.dart';
import '../products/product_form_screen.dart';
import 'catalog_lookup_sheet.dart';

/// One line in the POS cart. Quantity and price are expressed in the selected
/// sale unit; the base quantity is derived with the package factor.
class CartLine {
  CartLine({
    required this.product,
    required this.unit,
    required this.qtyMilli,
    required this.unitPriceCentimes,
  });

  final Product product;
  final ProductUnit? unit;
  int qtyMilli;
  int unitPriceCentimes;

  int get factorMilli => unit?.factorMilli ?? 1000;
  int get lineId => product.id * 100000 + (unit?.id ?? 0);

  /// Quantity shown to the user, in the selected unit.
  int get displayQtyMilli => factorMilli <= 0
      ? qtyMilli
      : (qtyMilli * Qty.milliPerUnit) ~/ factorMilli;

  int get totalCentimes =>
      (qtyMilli * unitPriceCentimes + factorMilli ~/ 2) ~/ factorMilli;

  int get basePriceCentimes {
    if (factorMilli <= 0) return unitPriceCentimes;
    // Ceiling keeps the derived total at or above the exact package price;
    // the exact total is passed separately to the sale service.
    return (unitPriceCentimes * Qty.milliPerUnit + factorMilli - 1) ~/
        factorMilli;
  }

  SaleDraftLine toDraftLine() => SaleDraftLine(
    product: product,
    unit: unit,
    qtyMilli: qtyMilli,
    unitPriceCentimes: basePriceCentimes,
    lineTotalOverrideCentimes: totalCentimes,
  );

  CartLine copyWith({int? qtyMilli, int? unitPriceCentimes}) => CartLine(
    product: product,
    unit: unit,
    qtyMilli: qtyMilli ?? this.qtyMilli,
    unitPriceCentimes: unitPriceCentimes ?? this.unitPriceCentimes,
  );
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _scrollController = ScrollController();

  List<Product> _products = const [];
  final List<CartLine> _lines = [];
  String _query = '';
  int _multiplier = 1;
  bool _loading = true;
  bool _busy = false;
  bool _lookupInProgress = false;
  String? _loadError;

  String? _lastScanCode;
  DateTime? _lastScanAt;
  Customer? _customer;
  String _idempotencyKey = _newKey();

  static String _newKey() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 30)}';

  int get _subtotal => _lines.fold(0, (sum, line) => sum + line.totalCentimes);
  int get _itemCount => _lines.fold(
    0,
    (sum, line) =>
        sum +
        (line.factorMilli > 0 ? (line.qtyMilli / line.factorMilli).ceil() : 1),
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = AppScope.read(context);
    try {
      final products = await c.products.all();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e.toString();
      });
    }
  }

  List<Product> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products.where((p) {
      return p.name.toLowerCase().contains(q) ||
          (p.nameAr?.contains(q) ?? false) ||
          (p.brand?.toLowerCase().contains(q) ?? false) ||
          (p.barcode?.contains(q) ?? false) ||
          (p.categoryName?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  void _addLine(Product product, ProductUnit? unit, {int count = 1}) {
    final factor = unit?.factorMilli ?? Qty.milliPerUnit;
    final price = _priceForUnit(product, unit);
    final qty = count * factor;
    final index = _lines.indexWhere(
      (line) =>
          line.product.id == product.id &&
          (line.unit?.id ?? 0) == (unit?.id ?? 0),
    );
    setState(() {
      if (index >= 0) {
        _lines[index].qtyMilli += qty;
      } else {
        _lines.add(
          CartLine(
            product: product,
            unit: unit,
            qtyMilli: qty,
            unitPriceCentimes: price,
          ),
        );
      }
      _query = '';
      _searchController.clear();
    });
    _searchFocus.requestFocus();
    final totalQty = _lines
        .where((l) => l.product.id == product.id)
        .fold(0, (s, l) => s + l.qtyMilli);
    if (product.stockMilli < totalQty) {
      showInfo(
        context,
        AppScope.of(context).l10n.t('Le stock deviendra négatif.'),
      );
    }
  }

  int _priceForUnit(Product product, ProductUnit? unit) {
    if (unit == null) return product.priceCentimes;
    return unit.priceCentimes ??
        ((product.priceCentimes * unit.factorMilli + 500) ~/ 1000);
  }

  Future<void> _chooseUnitAndAdd(Product product) async {
    if (product.units.isEmpty) {
      _addLine(product, null, count: _multiplier);
      return;
    }
    final defaultUnit = product.units.where((u) => u.isDefaultSale).firstOrNull;
    if (defaultUnit != null) {
      _addLine(product, defaultUnit, count: _multiplier);
      return;
    }
    final unit = await showModalBottomSheet<ProductUnit?>(
      context: context,
      showDragHandle: true,
      builder: (context) => _UnitPickerSheet(product: product),
    );
    if (unit == null || !mounted) return;
    _addLine(product, unit, count: _multiplier);
  }

  Future<void> _handleCode(String raw, {bool fromCamera = false}) async {
    final code = raw.trim();
    if (code.isEmpty || _lookupInProgress) return;
    final now = DateTime.now();
    if (!fromCamera &&
        code == _lastScanCode &&
        _lastScanAt != null &&
        now.difference(_lastScanAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastScanCode = code;
    _lastScanAt = now;

    setState(() => _lookupInProgress = true);
    try {
      final c = AppScope.of(context);
      final product =
          _products.where((p) => p.barcode == code).firstOrNull ??
          await c.products.findByBarcode(code);
      if (!mounted) return;
      if (product != null) {
        _addLine(
          product,
          product.units.where((u) => u.isDefaultSale).firstOrNull,
          count: _multiplier,
        );
        return;
      }

      final result = await showModalBottomSheet<CatalogSheetResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => CatalogLookupSheet(barcode: code),
      );
      if (!mounted || result == null) return;
      if (result.candidate != null || result.createManually) {
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ProductFormScreen(
              initialBarcode: code,
              candidate: result.candidate,
            ),
          ),
        );
        if (created == true) await _load();
      }
    } finally {
      if (mounted) setState(() => _lookupInProgress = false);
    }
  }

  Future<void> _submitSearch() async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    final exact = _products.where((p) => p.barcode == q).firstOrNull;
    if (exact != null) {
      await _handleCode(q);
      return;
    }
    if (_filtered.length == 1) {
      await _chooseUnitAndAdd(_filtered.first);
      return;
    }
    if (_filtered.isEmpty && RegExp(r'^\d{6,}$').hasMatch(q)) {
      await _handleCode(q);
      return;
    }
    setState(() => _query = q);
  }

  void _changeQty(CartLine line, int steps) {
    final delta = steps * line.factorMilli;
    final next = line.qtyMilli + delta;
    setState(() {
      if (next <= 0) {
        _lines.remove(line);
      } else {
        line.qtyMilli = next;
      }
    });
  }

  Future<void> _editLine(CartLine line) async {
    final updated = await showModalBottomSheet<CartLine?>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LineEditorSheet(line: line),
    );
    if (updated == null || !mounted) return;
    setState(() {
      final index = _lines.indexOf(line);
      if (index >= 0) _lines[index] = updated;
    });
  }

  Future<void> _checkout() async {
    if (_lines.isEmpty || _busy) return;
    final result = await showModalBottomSheet<_CheckoutResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _CheckoutSheet(lines: List.of(_lines), customer: _customer),
    );
    if (result == null || !mounted) return;
    _customer = result.customer;
    await _completeSale(result);
  }

  Future<void> _completeSale(_CheckoutResult result) async {
    final c = AppScope.of(context);
    final l = c.l10n;
    setState(() => _busy = true);
    try {
      final policy = await c.settings.stockPolicy();
      if (!mounted) return;
      final needed = <int, int>{};
      for (final line in _lines) {
        needed.update(
          line.product.id,
          (v) => v + line.qtyMilli,
          ifAbsent: () => line.qtyMilli,
        );
      }
      final shortages = <String>[];
      for (final entry in needed.entries) {
        final product = _products.where((p) => p.id == entry.key).firstOrNull;
        if (product != null && entry.value > product.stockMilli) {
          shortages.add(
            '${product.name} '
            '(${Qty.format(product.stockMilli)} / ${Qty.format(entry.value)})',
          );
        }
      }
      var allowNegative = false;
      if (shortages.isNotEmpty) {
        if (policy == 'block') {
          throw ValidationError(
            '${l.t('Stock insuffisant')} : ${shortages.join(', ')}',
          );
        }
        if (policy == 'confirm') {
          final ok = await confirm(
            context,
            title: l.t('Confirmer la vente en stock négatif ?'),
            message:
                '${l.t('Le stock deviendra négatif.')}\n${shortages.join('\n')}',
            confirmLabel: l.t('Continuer'),
            destructive: true,
          );
          if (!ok) return;
        }
        allowNegative = true;
      }

      final draft = SaleDraft(
        lines: [for (final line in _lines) line.toDraftLine()],
        customerId: result.customer?.id,
        discountCentimes: result.discountCentimes,
        paidCentimes: result.paidCentimes,
        paymentMethod: result.method,
        note: result.note,
        idempotencyKey: _idempotencyKey,
        allowNegativeStock: allowNegative,
      );
      final sale = await c.sales.completeSale(draft);
      if (result.method == 'cash' && await c.settings.autoPrint()) {
        try {
          await c.printer.printSale(sale, c.shop);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _lines.clear();
        _customer = null;
        _multiplier = 1;
        _idempotencyKey = _newKey();
        _query = '';
        _searchController.clear();
      });
      await _load();
      final change = result.tenderedCentimes == null
          ? 0
          : result.tenderedCentimes! - sale.totalCentimes;
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => _SaleSuccessSheet(sale: sale, change: change),
      );
    } catch (e) {
      if (!mounted) return;
      showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openCartSheet() {
    if (_lines.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void refresh(VoidCallback change) {
              change();
              setSheetState(() {});
            }

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              maxChildSize: 0.95,
              builder: (context, scrollController) => _CartPanel(
                lines: _lines,
                subtotal: _subtotal,
                itemCount: _itemCount,
                scrollController: scrollController,
                onClear: () => refresh(() {
                  _lines.clear();
                  Navigator.pop(sheetContext);
                }),
                onIncrement: (line) => refresh(() => _changeQty(line, 1)),
                onDecrement: (line) => refresh(() {
                  _changeQty(line, -1);
                  if (_lines.isEmpty) Navigator.pop(sheetContext);
                }),
                onEdit: (line) async {
                  Navigator.pop(sheetContext);
                  await _editLine(line);
                },
                onCheckout: () {
                  Navigator.pop(sheetContext);
                  _checkout();
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openMultiplier() async {
    final value = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final l = L10n.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.t('Multiplicateur'),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final n in [1, 2, 3, 4, 5, 6, 8, 10, 12, 24])
                      ChoiceChip(
                        label: Text('×$n'),
                        selected: _multiplier == n,
                        onSelected: (_) => Navigator.pop(context, n),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (value != null) setState(() => _multiplier = value);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final l = c.l10n;
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Caisse')),
        actions: [
          if (_lines.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final ok = await confirm(
                  context,
                  title: l.t('Vider le panier'),
                  message: l.t('Le panier sera vidé. Continuer ?'),
                  destructive: true,
                );
                if (ok) {
                  setState(() {
                    _lines.clear();
                    _customer = null;
                  });
                }
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(l.t('Vider')),
            ),
          IconButton(
            tooltip: l.t('Scanner'),
            onPressed: () async {
              final code = await scanBarcode(context);
              if (code != null) await _handleCode(code, fromCamera: true);
            },
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: Column(
        children: [
          _searchBar(l),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _productArea(l)),
                if (wide)
                  SizedBox(
                    width: 380,
                    child: _CartPanel(
                      lines: _lines,
                      subtotal: _subtotal,
                      itemCount: _itemCount,
                      onClear: () => setState(() {
                        _lines.clear();
                        _customer = null;
                      }),
                      onIncrement: (line) => _changeQty(line, 1),
                      onDecrement: (line) => _changeQty(line, -1),
                      onEdit: _editLine,
                      onCheckout: _busy ? null : _checkout,
                    ),
                  ),
              ],
            ),
          ),
          if (!wide && _lines.isNotEmpty) _mobileCartBar(context, l),
        ],
      ),
    );
  }

  Widget _searchBar(L10n l) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  autofocus: false,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) => setState(() => _query = value),
                  onSubmitted: (_) => _submitSearch(),
                  decoration: InputDecoration(
                    hintText: l.t('Saisir ou scanner un code-barres'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _lookupInProgress
                    ? null
                    : () async {
                        final code = await scanBarcode(context);
                        if (code != null) {
                          await _handleCode(code, fromCamera: true);
                        }
                      },
                style: FilledButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  padding: EdgeInsets.zero,
                ),
                child: _lookupInProgress
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.qr_code_scanner),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _openMultiplier,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  backgroundColor: _multiplier > 1
                      ? AppTheme.accent.withValues(alpha: 0.12)
                      : null,
                  foregroundColor: _multiplier > 1 ? AppTheme.accent : null,
                ),
                child: Text(
                  '×$_multiplier',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (_customer != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.person_outline, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    '${l.t('Client')} : ${_customer!.name}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _customer = null),
                    child: Text(l.t('Changer')),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _productArea(L10n l) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return EmptyState(
        message: _loadError!,
        icon: Icons.error_outline,
        action: FilledButton(onPressed: _load, child: Text(l.t('Réessayer'))),
      );
    }
    if (_products.isEmpty) {
      return EmptyState(
        message: l.t('Aucun produit'),
        icon: Icons.inventory_2_outlined,
        action: FilledButton.icon(
          onPressed: () async {
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const ProductFormScreen()),
            );
            if (created == true) await _load();
          },
          icon: const Icon(Icons.add),
          label: Text(l.t('Créer le produit')),
        ),
      );
    }
    final filtered = _filtered;
    if (filtered.isEmpty) {
      return EmptyState(
        message: l.t('Aucun résultat'),
        icon: Icons.search_off,
        action: _query.trim().isEmpty
            ? null
            : OutlinedButton(
                onPressed: () => _submitSearch(),
                child: Text(l.t('Rechercher dans les catalogues')),
              ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 650
            ? 3
            : 2;
        return GridView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(12),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.35,
          ),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final product = filtered[index];
            return _ProductTile(
              product: product,
              arabic: l.isArabic,
              onTap: () => _chooseUnitAndAdd(product),
            );
          },
        );
      },
    );
  }

  Widget _mobileCartBar(BuildContext context, L10n l) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor),
          ),
        ),
        child: Row(
          children: [
            Badge(
              label: Text('$_itemCount'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.t('Panier'), style: const TextStyle(fontSize: 12)),
                  Text(
                    money(_subtotal, context),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _openCartSheet,
              icon: const Icon(Icons.arrow_forward),
              label: Text(l.t('Voir le panier')),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    required this.product,
    required this.arabic,
    required this.onTap,
  });

  final Product product;
  final bool arabic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final low = product.isLowStock || product.isOutOfStock;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      product.displayName(arabic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (product.hasPackaging)
                    Icon(
                      Icons.layers_outlined,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                ],
              ),
              const Spacer(),
              Text(
                money(product.priceCentimes, context),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${Qty.format(product.stockMilli)} ${unitLabel(product.baseUnit, l)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(
                          stockColor(product.stockMilli, product.minStockMilli),
                        ),
                        fontWeight: low ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (product.categoryName != null)
                    Flexible(
                      child: Text(
                        product.categoryName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.lines,
    required this.subtotal,
    required this.itemCount,
    required this.onClear,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEdit,
    required this.onCheckout,
    this.scrollController,
  });

  final List<CartLine> lines;
  final int subtotal;
  final int itemCount;
  final VoidCallback onClear;
  final ValueChanged<CartLine> onIncrement;
  final ValueChanged<CartLine> onDecrement;
  final ValueChanged<CartLine> onEdit;
  final VoidCallback? onCheckout;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: BorderDirectional(start: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${l.t('Panier')} ($itemCount)',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (lines.isNotEmpty)
                  IconButton(
                    tooltip: l.t('Vider le panier'),
                    onPressed: onClear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: lines.isEmpty
                ? EmptyState(
                    message: l.t('Panier vide'),
                    icon: Icons.shopping_cart_outlined,
                  )
                : ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: lines.length,
                    separatorBuilder: (context, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final line = lines[index];
                      return _CartLineTile(
                        line: line,
                        onIncrement: () => onIncrement(line),
                        onDecrement: () => onDecrement(line),
                        onTap: () => onEdit(line),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        l.t('Total'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        money(subtotal, context),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: lines.isEmpty ? null : onCheckout,
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(l.t('Encaisser')),
                    ),
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

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({
    required this.line,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  });

  final CartLine line;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final unit = line.unit?.displayName(l.isArabic) ?? '';
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.product.displayName(l.isArabic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unit.isEmpty
                        ? money(line.unitPriceCentimes, context)
                        : '$unit · ${money(line.unitPriceCentimes, context)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            _QtyStepper(
              value: Qty.format(line.displayQtyMilli),
              onMinus: onDecrement,
              onPlus: onIncrement,
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 74,
              child: Text(
                money(line.totalCentimes, context),
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: onMinus,
            icon: const Icon(Icons.remove, size: 18),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          IconButton(
            onPressed: onPlus,
            icon: const Icon(Icons.add, size: 18),
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

class _UnitPickerSheet extends StatelessWidget {
  const _UnitPickerSheet({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final options = <(ProductUnit?, String, int)>[
      (null, l.t('Pièce'), product.priceCentimes),
      for (final unit in product.units)
        (
          unit,
          unit.displayName(l.isArabic),
          unit.priceCentimes ??
              ((product.priceCentimes * unit.factorMilli + 500) ~/ 1000),
        ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l.t('Changer le conditionnement'),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            for (final option in options)
              ListTile(
                leading: Icon(
                  option.$1 == null
                      ? Icons.category_outlined
                      : Icons.inventory_outlined,
                ),
                title: Text(option.$2),
                subtitle: option.$1 == null
                    ? null
                    : Text('${option.$1!.factorLabel} ${l.t('unités')}'),
                trailing: Text(
                  money(option.$3, context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                onTap: () => Navigator.pop(context, option.$1),
              ),
          ],
        ),
      ),
    );
  }
}

class _LineEditorSheet extends StatefulWidget {
  const _LineEditorSheet({required this.line});
  final CartLine line;

  @override
  State<_LineEditorSheet> createState() => _LineEditorSheetState();
}

class _LineEditorSheetState extends State<_LineEditorSheet> {
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  String? _error;

  @override
  void initState() {
    super.initState();
    final line = widget.line;
    _qtyController = TextEditingController(
      text: Qty.format(line.displayQtyMilli),
    );
    _priceController = TextEditingController(
      text: Money.format(line.unitPriceCentimes).replaceAll('\u00A0', ''),
    );
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  void _save() {
    final l = L10n.of(context);
    final qty = Qty.tryParse(_qtyController.text);
    final price = Money.tryParseToCentimes(_priceController.text);
    if (qty == null || qty <= 0) {
      setState(() => _error = l.t('Quantité invalide.'));
      return;
    }
    if (price == null || price < 0) {
      setState(() => _error = l.t('Prix invalide.'));
      return;
    }
    final line = widget.line;
    final baseQty = Qty.multiply(qty, line.factorMilli);
    Navigator.pop(
      context,
      line.copyWith(qtyMilli: baseQty, unitPriceCentimes: price),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.line.product.displayName(l.isArabic),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText:
                  '${l.t('Quantité')} (${widget.line.unit?.displayName(l.isArabic) ?? l.t('Pièce')})',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.t('Prix unitaire'),
              suffixText: 'DH',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: AppTheme.danger, fontSize: 12),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: Text(l.t('Enregistrer'))),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.delete_outline),
            label: Text(l.t('Supprimer')),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
          ),
        ],
      ),
    );
  }
}

class _CheckoutResult {
  const _CheckoutResult({
    required this.method,
    required this.paidCentimes,
    this.tenderedCentimes,
    this.discountCentimes = 0,
    this.customer,
    this.note,
  });

  final String method;
  final int paidCentimes;
  final int? tenderedCentimes;
  final int discountCentimes;
  final Customer? customer;
  final String? note;
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet({required this.lines, this.customer});
  final List<CartLine> lines;
  final Customer? customer;

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  late final TextEditingController _discountController;
  late final TextEditingController _receivedController;
  late final TextEditingController _noteController;
  String _method = 'cash';
  Customer? _customer;
  String? _error;

  int get _subtotal =>
      widget.lines.fold(0, (sum, line) => sum + line.totalCentimes);

  int get _discount => Money.tryParseToCentimes(_discountController.text) ?? 0;

  int get _total => max(0, _subtotal - _discount);

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _discountController = TextEditingController();
    _receivedController = TextEditingController(
      text: Money.format(_subtotal).replaceAll('\u00A0', ''),
    );
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _receivedController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickCustomer() async {
    final customer = await pickCustomer(context, selectedId: _customer?.id);
    if (customer != null) {
      setState(() => _customer = customer);
    }
  }

  void _confirm() {
    final l = L10n.of(context);
    final discount = _discount;
    if (discount < 0 || discount > _subtotal) {
      setState(() => _error = l.t('Remise invalide.'));
      return;
    }
    final total = _total;
    if (_method == 'credit') {
      if (_customer == null) {
        setState(
          () => _error = l.t(
            'Sélectionnez un client pour enregistrer un reste à payer.',
          ),
        );
        return;
      }
      Navigator.pop(
        context,
        _CheckoutResult(
          method: 'credit',
          paidCentimes: 0,
          discountCentimes: discount,
          customer: _customer,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
      );
      return;
    }
    if (_method == 'cash') {
      final tendered = Money.tryParseToCentimes(_receivedController.text);
      if (tendered == null || tendered < total) {
        setState(() => _error = l.t('Montant insuffisant'));
        return;
      }
      Navigator.pop(
        context,
        _CheckoutResult(
          method: 'cash',
          paidCentimes: total,
          tenderedCentimes: tendered,
          discountCentimes: discount,
          customer: _customer,
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _CheckoutResult(
        method: _method,
        paidCentimes: total,
        discountCentimes: discount,
        customer: _customer,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final received = Money.tryParseToCentimes(_receivedController.text) ?? 0;
    final total = _total;
    final change = received > total ? received - total : 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l.t('Finaliser la vente'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    _row(l.t('Sous-total'), money(_subtotal, context)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _discountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: l.t('Remise globale'),
                        suffixText: 'DH',
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          l.t('Total à payer'),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          money(total, context),
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.t('Moyen de paiement'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in const ['cash', 'card', 'credit'])
                  ChoiceChip(
                    label: Text(paymentLabel(method, l)),
                    selected: _method == method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_customer?.name ?? l.t('Client de passage')),
              subtitle: _customer?.phone == null
                  ? null
                  : Text(_customer!.phone!),
              trailing: TextButton(
                onPressed: _pickCustomer,
                child: Text(l.t('Choisir un client')),
              ),
              onTap: _pickCustomer,
            ),
            if (_method == 'cash') ...[
              const SizedBox(height: 4),
              TextField(
                controller: _receivedController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l.t('Montant reçu'),
                  suffixText: 'DH',
                ),
              ),
              const SizedBox(height: 8),
              _row(
                l.t('Monnaie à rendre'),
                money(change, context),
                bold: true,
                color: AppTheme.success,
              ),
            ],
            if (_method == 'credit')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l.t('Le montant sera ajouté à la dette du client.'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(labelText: l.t('Note')),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: AppTheme.danger, fontSize: 12),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _confirm,
              icon: const Icon(Icons.check_circle_outline),
              label: Text('${l.t('Encaisser')} ${money(total, context)}'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
            color: color,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SaleSuccessSheet extends StatefulWidget {
  const _SaleSuccessSheet({required this.sale, required this.change});
  final Sale sale;
  final int change;

  @override
  State<_SaleSuccessSheet> createState() => _SaleSuccessSheetState();
}

class _SaleSuccessSheetState extends State<_SaleSuccessSheet> {
  bool _printing = false;

  Future<void> _print() async {
    final c = AppScope.of(context);
    setState(() => _printing = true);
    try {
      await c.printer.printSale(widget.sale, c.shop);
      if (mounted) showInfo(context, c.l10n.t('Reçu'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _sharePdf() async {
    final c = AppScope.of(context);
    try {
      final paper = await c.settings.paperWidth();
      final bytes = await c.pdf.saleDocument(
        sale: widget.sale,
        shop: c.shop,
        arabic: c.isArabic,
        receipt: true,
        paperWidthMm: paper.toDouble(),
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: '${widget.sale.invoiceNo}.pdf',
      );
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.check_rounded,
                size: 40,
                color: AppTheme.success,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l.t('Vente enregistrée'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              widget.sale.invoiceNo,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 12),
            Text(
              money(widget.sale.totalCentimes, context),
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            ),
            if (widget.change > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${l.t('Monnaie à rendre')} : ${money(widget.change, context)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.success,
                  ),
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined),
                    label: Text(l.t('Reçu')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _sharePdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(l.t('PDF')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.t('Nouvelle vente')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
