import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/classifications.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/expiry_picker.dart';
import '../common/scanner_sheet.dart';
import '../pos/catalog_lookup_sheet.dart';

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({
    super.key,
    this.product,
    this.initialBarcode,
    this.candidate,
    this.initialCategoryId,
  });

  final Product? product;
  final String? initialBarcode;
  final CatalogCandidate? candidate;
  final int? initialCategoryId;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _nameAr;
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _packageSize;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  late final TextEditingController _stock;
  late final TextEditingController _minStock;
  late final TextEditingController _notes;

  late Product? _product;
  List<Category> _allCategories = const [];
  List<Category> _categories = const [];
  List<ProductUnit> _units = [];
  String _baseUnit = 'piece';
  ProductDivision _division = ProductDivision.food;
  int? _categoryId;
  String? _imageUrl;
  String? _catalogSource;
  bool _saving = false;
  String? _initialExpiry;
  final _batchNo = TextEditingController();

  bool get _creating => _product == null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    final c = widget.candidate;
    _product = p;
    _name = TextEditingController(text: p?.name ?? c?.name ?? '');
    _nameAr = TextEditingController(text: p?.nameAr ?? c?.nameAr ?? '');
    _barcode = TextEditingController(
      text: p?.barcode ?? widget.initialBarcode ?? c?.barcode ?? '',
    );
    _brand = TextEditingController(text: p?.brand ?? c?.brand ?? '');
    _packageSize = TextEditingController(
      text: p?.packageSize ?? c?.quantityText ?? '',
    );
    _price = TextEditingController(
      text: p == null ? '' : _amount(p.priceCentimes),
    );
    _cost = TextEditingController(
      text: p == null ? '' : _amount(p.costCentimes),
    );
    _stock = TextEditingController(
      text: p == null ? '0' : Qty.format(p.stockMilli),
    );
    _minStock = TextEditingController(
      text: p == null ? '' : Qty.format(p.minStockMilli),
    );
    _notes = TextEditingController(text: p?.notes ?? '');
    _baseUnit = p?.baseUnit ?? 'piece';
    _categoryId = p?.categoryId ?? widget.initialCategoryId;
    _imageUrl = p?.imageUrl ?? c?.imageUrl;
    _catalogSource = p?.catalogSource ?? c?.source;
    _units = [...?p?.units];
    _loadCategories();
  }

  String _amount(int centimes) =>
      Money.format(centimes).replaceAll('\u00A0', '');

  Future<void> _loadCategories() async {
    final c = AppScope.read(context);
    final categories = await c.products.categories();
    if (!mounted) return;
    setState(() {
      _allCategories = categories;
      final matches = categories
          .where((category) => category.id == _categoryId)
          .toList();
      if (matches.isNotEmpty) {
        _division =
            ProductDivision.fromCode(matches.first.division) ?? _division;
      }
      _categories = categories
          .where((category) => category.division == _division.code)
          .toList();
      // Keep a legacy/unclassified category selectable so the bound value is
      // always present in the dropdown.
      if (_categoryId != null &&
          !_categories.any((category) => category.id == _categoryId)) {
        final legacy = categories.where((c) => c.id == _categoryId).toList();
        _categories = [..._categories, ...legacy];
      }
    });
  }

  void _selectDivision(ProductDivision division) {
    setState(() {
      _division = division;
      _categories = _allCategories
          .where((category) => category.division == division.code)
          .toList();
      if (!_categories.any((category) => category.id == _categoryId)) {
        _categoryId = null;
      }
    });
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _nameAr,
      _barcode,
      _brand,
      _packageSize,
      _price,
      _cost,
      _stock,
      _minStock,
      _notes,
      _batchNo,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    final code = await scanBarcode(context);
    if (code != null) setState(() => _barcode.text = code);
  }

  Future<void> _lookupCatalog() async {
    final code = _barcode.text.trim();
    if (code.isEmpty) {
      showInfo(
        context,
        AppScope.of(context).l10n.t('Saisir le code manuellement'),
      );
      return;
    }
    final result = await showModalBottomSheet<CatalogSheetResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CatalogLookupSheet(barcode: code),
    );
    final candidate = result?.candidate;
    if (candidate == null || !mounted) return;
    setState(() {
      _name.text = candidate.name;
      if (candidate.nameAr != null) _nameAr.text = candidate.nameAr!;
      if (candidate.brand != null) _brand.text = candidate.brand!;
      if (candidate.quantityText != null) {
        _packageSize.text = candidate.quantityText!;
      }
      if (candidate.imageUrl != null) _imageUrl = candidate.imageUrl;
      _catalogSource = candidate.source;
    });
    if (mounted) {
      showInfo(
        context,
        AppScope.of(context).l10n.t('Prix et stock locaux conservés'),
      );
    }
  }

  Future<void> _addCategory() async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final result = await showDialog<(String, String?)>(
      context: context,
      builder: (context) => _CategoryDialog(),
    );
    if (result == null) return;
    try {
      final id = await c.products.addCategory(
        result.$1,
        result.$2,
        division: _division.code,
      );
      await _loadCategories();
      if (!mounted) return;
      setState(() => _categoryId = id);
      if (mounted) showInfo(context, l.t('Catégorie ajoutée'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _editUnit([ProductUnit? unit]) async {
    final result = await showDialog<ProductUnit>(
      context: context,
      builder: (context) => _UnitDialog(initial: unit),
    );
    if (result == null) return;
    setState(() {
      if (unit == null) {
        _units.add(result);
      } else {
        final index = _units.indexOf(unit);
        if (index >= 0) _units[index] = result;
      }
    });
  }

  Future<void> _pickInitialExpiry() async {
    final value = await pickIsoDate(context, initial: _initialExpiry);
    if (value == null || !mounted) return;
    setState(() => _initialExpiry = value);
  }

  Future<void> _adjustStock() async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final product = _product;
    if (product == null) return;
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (context) => _StockDialog(
        currentMilli: product.stockMilli,
        unit: product.baseUnit,
      ),
    );
    if (result == null) return;
    try {
      await c.inventory.setCountedStock(
        productId: product.id,
        countedMilli: result.$1,
        reason: result.$2,
      );
      final refreshed = await c.products.findById(product.id);
      if (!mounted) return;
      setState(() {
        _product = refreshed;
        if (refreshed != null) {
          _stock.text = Qty.format(refreshed.stockMilli);
        }
      });
      showInfo(context, l.t('Stock mis à jour'));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final c = AppScope.of(context);
    final l = c.l10n;
    final price = _price.text.trim().isEmpty
        ? 0
        : Money.tryParseToCentimes(_price.text);
    final cost = _cost.text.trim().isEmpty
        ? 0
        : Money.tryParseToCentimes(_cost.text);
    final stock = _stock.text.trim().isEmpty ? 0 : Qty.tryParse(_stock.text);
    final minStock = _minStock.text.trim().isEmpty
        ? 0
        : Qty.tryParse(_minStock.text);
    if (price == null || price < 0) {
      showInfo(context, l.t('Prix invalide.'));
      return;
    }
    if (cost == null || cost < 0) {
      showInfo(context, l.t('Coût invalide.'));
      return;
    }
    if (stock == null || stock < 0) {
      showInfo(context, l.t('Quantité invalide.'));
      return;
    }
    if (minStock == null || minStock < 0) {
      showInfo(context, l.t('Quantité invalide.'));
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = _product;
      final product = Product(
        id: existing?.id ?? 0,
        barcode: _barcode.text.trim().isEmpty ? null : _barcode.text.trim(),
        name: _name.text.trim(),
        nameAr: _nameAr.text.trim().isEmpty ? null : _nameAr.text.trim(),
        brand: _brand.text.trim().isEmpty ? null : _brand.text.trim(),
        categoryId: _categoryId,
        packageSize: _packageSize.text.trim().isEmpty
            ? null
            : _packageSize.text.trim(),
        baseUnit: _baseUnit,
        costCentimes: cost,
        priceCentimes: price,
        stockMilli: existing?.stockMilli ?? stock,
        minStockMilli: minStock,
        supplierId: existing?.supplierId,
        imageUrl: _imageUrl,
        imagePath: existing?.imagePath,
        catalogSource: _catalogSource,
        catalogUpdatedAt: existing?.catalogUpdatedAt,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        isActive: true,
        createdAt: existing?.createdAt ?? 0,
        updatedAt: existing?.updatedAt ?? 0,
        units: _units,
      );
      if (existing == null) {
        await c.products.create(
          product,
          initialExpiryDate: _initialExpiry,
          initialBatchNo: _batchNo.text.trim().isEmpty
              ? null
              : _batchNo.text.trim(),
        );
      } else {
        await c.products.update(product);
      }
      if (!mounted) return;
      showInfo(
        context,
        l.t(existing == null ? 'Produit créé' : 'Produit mis à jour'),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final c = AppScope.of(context);
    final l = c.l10n;
    final product = _product;
    if (product == null) return;
    final ok = await confirm(
      context,
      title: l.t('Supprimer le produit'),
      message: product.name,
      destructive: true,
      confirmLabel: l.t('Supprimer'),
    );
    if (!ok) return;
    try {
      await c.products.delete(product.id, reason: 'Suppression produit');
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _creating ? l.t('Ajouter un produit') : l.t('Modifier le produit'),
        ),
        actions: [
          if (!_creating)
            IconButton(
              tooltip: l.t('Supprimer'),
              onPressed: _delete,
              icon: Icon(Icons.delete_outline, color: AppTheme.danger),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
              children: [
                if (_imageUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            _imageUrl!,
                            width: 70,
                            height: 70,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox(
                              width: 70,
                              height: 70,
                              child: Icon(Icons.image_not_supported),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _catalogSource == null
                                ? l.t('Image')
                                : '${l.t('Source externe')} : $_catalogSource',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                SectionTitle(l.t('Produit')),
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(labelText: l.t('Nom du produit')),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l.t('Champ requis')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameAr,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(labelText: l.t('Nom arabe')),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _barcode,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l.t('Code-barres'),
                    suffixIcon: IconButton(
                      onPressed: _scan,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _lookupCatalog,
                  icon: const Icon(Icons.travel_explore, size: 18),
                  label: Text(l.t('Rechercher dans les catalogues')),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _brand,
                        decoration: InputDecoration(labelText: l.t('Marque')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _packageSize,
                        decoration: InputDecoration(
                          labelText: l.t('Conditionnement'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _baseUnit,
                        decoration: InputDecoration(labelText: l.t('Unité')),
                        items: [
                          for (final code in unitCodes)
                            DropdownMenuItem(
                              value: code,
                              child: Text(unitLabel(code, l)),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _baseUnit = value ?? 'piece'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<ProductDivision>(
                        initialValue: _division,
                        decoration: InputDecoration(labelText: l.t('Division')),
                        items: [
                          for (final division in ProductDivision.values)
                            DropdownMenuItem(
                              value: division,
                              child: Text(
                                divisionName(division, arabic: l.isArabic),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) _selectDivision(value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int?>(
                        initialValue: _categoryId,
                        decoration: InputDecoration(
                          labelText: l.t('Sous-catégorie'),
                        ),
                        items: [
                          DropdownMenuItem<int?>(
                            value: null,
                            child: Text(l.t('Sans catégorie')),
                          ),
                          for (final category in _categories)
                            DropdownMenuItem<int?>(
                              value: category.id,
                              child: Text(category.displayName(l.isArabic)),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _categoryId = value),
                      ),
                    ),
                    IconButton(
                      tooltip: l.t('Nouvelle sous-catégorie'),
                      onPressed: _addCategory,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SectionTitle(l.t('Prix et stock')),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cost,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l.t('Prix d\'achat'),
                          suffixText: 'DH',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l.t('Prix de vente'),
                          suffixText: 'DH',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stock,
                        readOnly: !_creating,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _creating
                              ? l.t('Stock initial')
                              : l.t('Stock'),
                          suffixText: unitLabel(_baseUnit, l),
                        ),
                      ),
                    ),
                    if (!_creating) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _adjustStock,
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(l.t('Ajuster')),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _minStock,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: l.t('Stock minimum'),
                          suffixText: unitLabel(_baseUnit, l),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_creating) ...[
                  SectionTitle(l.t('Lot et péremption')),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickInitialExpiry,
                          icon: const Icon(Icons.event_outlined, size: 18),
                          label: Text(
                            _initialExpiry == null
                                ? l.t('Date de péremption (facultatif)')
                                : '${l.t('Date de péremption')} : $_initialExpiry',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (_initialExpiry != null)
                        IconButton(
                          tooltip: l.t('Supprimer'),
                          onPressed: () =>
                              setState(() => _initialExpiry = null),
                          icon: const Icon(Icons.clear, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _batchNo,
                    decoration: InputDecoration(
                      labelText: l.t('Numéro de lot (facultatif)'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l.t(
                      'Priorité FEFO : les lots qui expirent d\'abord sont vendus en premier.',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SectionTitle(
                  l.t('Conditionnement'),
                  action: TextButton.icon(
                    onPressed: () => _editUnit(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l.t('Ajouter un conditionnement')),
                  ),
                ),
                if (_units.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l.t('Exemple : carton de 12 pièces, pack de 6.'),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final unit in _units)
                          ListTile(
                            title: Text(unit.displayName(l.isArabic)),
                            subtitle: Text(
                              '${unit.factorLabel} × ${unitLabel(_baseUnit, l)}'
                              '${unit.isDefaultSale ? ' · ${l.t('Par défaut')}' : ''}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  unit.priceCentimes == null
                                      ? '—'
                                      : money(unit.priceCentimes!, context),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) {
                                    if (value == 'edit') _editUnit(unit);
                                    if (value == 'delete') {
                                      setState(() => _units.remove(unit));
                                    }
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
                      ],
                    ),
                  ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: InputDecoration(labelText: l.t('Note')),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomSheet: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _creating ? l.t('Enregistrer le produit') : l.t('Enregistrer'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryDialog extends StatefulWidget {
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _fr = TextEditingController();
  final _ar = TextEditingController();

  @override
  void dispose() {
    _fr.dispose();
    _ar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l.t('Catégorie')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _fr,
            autofocus: true,
            decoration: InputDecoration(labelText: l.t('Nom')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ar,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(labelText: l.t('Nom arabe')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: () {
            if (_fr.text.trim().isEmpty) return;
            Navigator.pop(context, (
              _fr.text.trim(),
              _ar.text.trim().isEmpty ? null : _ar.text.trim(),
            ));
          },
          child: Text(l.t('Ajouter')),
        ),
      ],
    );
  }
}

class _UnitDialog extends StatefulWidget {
  const _UnitDialog({this.initial});
  final ProductUnit? initial;

  @override
  State<_UnitDialog> createState() => _UnitDialogState();
}

class _UnitDialogState extends State<_UnitDialog> {
  late final TextEditingController _name;
  late final TextEditingController _nameAr;
  late final TextEditingController _factor;
  late final TextEditingController _price;
  late final TextEditingController _cost;
  bool _defaultSale = false;
  bool _defaultPurchase = false;

  @override
  void initState() {
    super.initState();
    final u = widget.initial;
    _name = TextEditingController(text: u?.name ?? '');
    _nameAr = TextEditingController(text: u?.nameAr ?? '');
    _factor = TextEditingController(
      text: u == null ? '' : Qty.format(u.factorMilli),
    );
    _price = TextEditingController(
      text: u?.priceCentimes == null
          ? ''
          : Money.format(u!.priceCentimes!).replaceAll('\u00A0', ''),
    );
    _cost = TextEditingController(
      text: u?.costCentimes == null
          ? ''
          : Money.format(u!.costCentimes!).replaceAll('\u00A0', ''),
    );
    _defaultSale = u?.isDefaultSale ?? false;
    _defaultPurchase = u?.isDefaultPurchase ?? false;
  }

  @override
  void dispose() {
    for (final controller in [_name, _nameAr, _factor, _price, _cost]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? l.t('Ajouter un conditionnement')
            : l.t('Modifier'),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: l.t('Nom')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameAr,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(labelText: l.t('Nom arabe')),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _factor,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Facteur'),
                helperText: l.t('Exemple : 12 pour un carton de 12 pièces'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.t('Prix d\'achat'),
                      suffixText: 'DH',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.t('Prix de vente'),
                      suffixText: 'DH',
                    ),
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _defaultSale,
              onChanged: (value) =>
                  setState(() => _defaultSale = value ?? false),
              title: Text(l.t('Conditionnement par défaut')),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _defaultPurchase,
              onChanged: (value) =>
                  setState(() => _defaultPurchase = value ?? false),
              title: Text(l.t('Par défaut à l\'achat')),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: () {
            final factor = Qty.tryParse(_factor.text);
            if (_name.text.trim().isEmpty || factor == null || factor <= 0) {
              return;
            }
            final price = _price.text.trim().isEmpty
                ? null
                : Money.tryParseToCentimes(_price.text);
            final cost = _cost.text.trim().isEmpty
                ? null
                : Money.tryParseToCentimes(_cost.text);
            if ((_price.text.trim().isNotEmpty &&
                    (price == null || price < 0)) ||
                (_cost.text.trim().isNotEmpty && (cost == null || cost < 0))) {
              return;
            }
            Navigator.pop(
              context,
              ProductUnit(
                id: widget.initial?.id ?? 0,
                name: _name.text.trim(),
                nameAr: _nameAr.text.trim().isEmpty
                    ? null
                    : _nameAr.text.trim(),
                factorMilli: factor,
                priceCentimes: price,
                costCentimes: cost,
                isDefaultSale: _defaultSale,
                isDefaultPurchase: _defaultPurchase,
              ),
            );
          },
          child: Text(l.t('Valider')),
        ),
      ],
    );
  }
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.currentMilli, required this.unit});
  final int currentMilli;
  final String unit;

  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  late final TextEditingController _count;
  final _reason = TextEditingController(text: 'Ajustement manuel');

  @override
  void initState() {
    super.initState();
    _count = TextEditingController(text: Qty.format(widget.currentMilli));
  }

  @override
  void dispose() {
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final unit = unitLabel(widget.unit, l);
    return AlertDialog(
      title: Text(l.t('Ajuster le stock')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _count,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l.t('Stock compté'),
              suffixText: unit,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            decoration: InputDecoration(labelText: l.t('Motif du mouvement')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: () {
            final qty = Qty.tryParse(_count.text);
            if (qty == null || qty < 0 || _reason.text.trim().isEmpty) return;
            Navigator.pop(context, (qty, _reason.text.trim()));
          },
          child: Text(l.t('Valider')),
        ),
      ],
    );
  }
}
