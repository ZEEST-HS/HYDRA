import 'dart:math';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../domain/purchases/purchase_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../../ui/widgets/expiry_picker.dart';
import '../common/product_picker_sheet.dart';
import '../common/scanner_sheet.dart';
import '../parties/supplier_picker.dart';

/// Purchase entry. Scanning the same barcode repeatedly increases the quantity
/// of the existing line; the multiplier applies to the scanned quantity (for
/// example `10` + one scan adds ten units).
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key});

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  final _discount = TextEditingController();
  final _paid = TextEditingController(text: '0');
  final _note = TextEditingController();
  final _multiplier = TextEditingController(text: '1');

  final List<_PurchaseLineDraft> _lines = [];
  Supplier? _supplier;
  String _method = 'cash';
  bool _paidTouched = false;
  bool _saving = false;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _discount.addListener(_onTotalsChanged);
  }

  @override
  void dispose() {
    _discount.dispose();
    _paid.dispose();
    _note.dispose();
    _multiplier.dispose();
    super.dispose();
  }

  void _onTotalsChanged() {
    if (mounted) setState(() {});
  }

  int get _subtotal => _lines.fold(0, (sum, line) => sum + line.totalCentimes);
  int get _discountCentimes =>
      (Money.tryParseToCentimes(_discount.text) ?? 0).clamp(0, _subtotal);
  int get _total => max(0, _subtotal - _discountCentimes);
  int get _paidCentimes => Money.tryParseToCentimes(_paid.text) ?? 0;
  int get _due => max(0, _total - _paidCentimes);

  int get _multiplierMilli {
    final value = Qty.tryParse(_multiplier.text) ?? Qty.milliPerUnit;
    return value <= 0 ? Qty.milliPerUnit : value;
  }

  void _syncPaidToTotal() {
    if (_paidTouched) return;
    _paid.text = Money.format(_total).replaceAll('\u00A0', '');
  }

  Future<void> _chooseSupplier() async {
    final supplier = await pickSupplier(context, selectedId: _supplier?.id);
    if (supplier == null || !mounted) return;
    setState(() => _supplier = supplier);
  }

  Future<void> _pickProduct() async {
    final product = await pickProduct(context);
    if (product == null || !mounted) return;
    _addProduct(product);
  }

  Future<void> _scan() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      final code = await scanBarcode(context);
      if (code == null || !mounted) return;
      final product = await AppScope.of(context).products.findByBarcode(code);
      if (!mounted) return;
      if (product == null) {
        showError(context, AppScope.of(context).l10n.t('Produit introuvable'));
        return;
      }
      _addProduct(product);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  ProductUnit? _defaultUnit(Product product) {
    for (final unit in product.units) {
      if (unit.isDefaultPurchase) return unit;
    }
    return null;
  }

  int _costForUnit(Product product, ProductUnit? unit) {
    if (unit == null) return product.costCentimes;
    if (unit.costCentimes != null) return unit.costCentimes!;
    return (product.costCentimes * unit.factorMilli + Qty.milliPerUnit ~/ 2) ~/
        Qty.milliPerUnit;
  }

  void _addProduct(Product product) {
    final unit = _defaultUnit(product);
    final qty = _multiplierMilli;
    final existing = _lines.indexWhere(
      (line) =>
          line.product.id == product.id &&
          line.unit?.id == unit?.id &&
          line.unit?.factorMilli == unit?.factorMilli &&
          line.unit?.name == unit?.name &&
          line.expiryDate == null,
    );
    setState(() {
      if (existing >= 0) {
        final line = _lines[existing];
        _lines[existing] = line.copyWith(qtyMilli: line.qtyMilli + qty);
      } else {
        _lines.add(
          _PurchaseLineDraft(
            product: product,
            unit: unit,
            qtyMilli: qty,
            unitCostCentimes: _costForUnit(product, unit),
          ),
        );
      }
      _syncPaidToTotal();
    });
    showInfo(context, AppScope.of(context).l10n.t('Article ajouté'));
  }

  Future<void> _editLine(int index) async {
    final line = _lines[index];
    final result = await showDialog<_LineEditResult>(
      context: context,
      builder: (_) => _PurchaseLineDialog(
        product: line.product,
        initialUnit: line.unit,
        initialQtyMilli: line.qtyMilli,
        initialCostCentimes: line.unitCostCentimes,
        initialExpiry: line.expiryDate,
        initialBatchNo: line.batchNo,
        defaultCost: _costForUnit,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lines[index] = _PurchaseLineDraft(
        product: line.product,
        unit: result.unit,
        qtyMilli: result.qtyMilli,
        unitCostCentimes: result.unitCostCentimes,
        expiryDate: result.expiryDate,
        batchNo: result.batchNo,
      );
      _syncPaidToTotal();
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index);
      if (_lines.isEmpty) {
        _paid.text = '0';
      } else {
        _syncPaidToTotal();
      }
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    final l = AppScope.of(context).l10n;
    if (_lines.isEmpty) {
      showError(context, l.t('Sélectionnez au moins un article'));
      return;
    }
    final discount = Money.tryParseToCentimes(_discount.text) ?? 0;
    if (discount < 0) {
      showError(context, l.t('Montant invalide.'));
      return;
    }
    if (discount > _subtotal) {
      showError(context, l.t('La remise dépasse le sous-total.'));
      return;
    }
    final paid = _paidCentimes;
    if (paid < 0) {
      showError(context, l.t('Montant invalide.'));
      return;
    }
    if (paid > _total) {
      showError(context, l.t('Montant trop élevé'));
      return;
    }
    if (_due > 0 && _supplier == null) {
      showError(context, l.t('Sélectionnez un fournisseur pour le crédit.'));
      return;
    }
    setState(() => _saving = true);
    try {
      await AppScope.of(context).purchases.completePurchase(
        PurchaseDraft(
          supplierId: _supplier?.id,
          lines: [
            for (final line in _lines)
              PurchaseDraftLine(
                product: line.product,
                unit: line.unit,
                qtyMilli: line.baseQtyMilli,
                unitCostCentimes: line.baseUnitCostCentimes,
                expiryDate: line.expiryDate,
                batchNo: line.batchNo,
                lineTotalOverrideCentimes: line.totalCentimes,
              ),
          ],
          discountCentimes: discount,
          paidCentimes: paid,
          paymentMethod: _method,
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        ),
      );
      if (!mounted) return;
      showInfo(context, l.t('Achat enregistré'));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Nouvel achat')),
        actions: [
          IconButton(
            tooltip: l.t('Enregistrer'),
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.check),
          ),
        ],
        bottom: _saving
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: PageBody(
        maxWidth: 920,
        child: ListView(
          children: [
            _supplierCard(l),
            const SizedBox(height: 12),
            _addCard(l),
            const SizedBox(height: 12),
            if (_lines.isEmpty)
              Card(
                child: EmptyState(
                  message: l.t('Sélectionnez au moins un article'),
                  icon: Icons.shopping_basket_outlined,
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < _lines.length; i++) _lineTile(i, l),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            _totalsCard(l),
            const SizedBox(height: 12),
            _noteCard(l),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(l.t('Enregistrer l\'achat')),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _supplierCard(L10n l) {
    final supplier = _supplier;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.store_outlined, color: AppTheme.primary),
        ),
        title: Text(supplier?.name ?? l.t('Aucun fournisseur')),
        subtitle: supplier == null
            ? Text(l.t('Obligatoire pour un achat à crédit'))
            : Text(
                '${l.t('Solde')} : ${money(supplier.balanceCentimes, context)}',
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (supplier != null)
              IconButton(
                tooltip: l.t('Supprimer'),
                onPressed: () => setState(() => _supplier = null),
                icon: const Icon(Icons.close),
              ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: _chooseSupplier,
      ),
    );
  }

  Widget _addCard(L10n l) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _scanning ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(l.t('Scanner')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickProduct,
                    icon: const Icon(Icons.search),
                    label: Text(l.t('Sélectionner un produit')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _multiplier,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.t('Multiplicateur'),
                      suffixText: '×',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.t('La quantité scannée est multipliée.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineTile(int index, L10n l) {
    final line = _lines[index];
    final unitName = line.unitName(l);
    final subtitle = StringBuffer(
      '${Qty.format(line.qtyMilli)} $unitName × '
      '${money(line.unitCostCentimes, context)}',
    );
    if (line.unit != null) {
      subtitle.write(
        ' · ${Qty.format(line.baseQtyMilli)} '
        '${unitLabel(line.product.baseUnit, l)}',
      );
    }
    if (line.expiryDate != null) {
      subtitle.write(' · ${l.t('Péremption')} ${line.expiryDate}');
    }
    if (line.batchNo != null && line.batchNo!.trim().isNotEmpty) {
      subtitle.write(' · ${l.t('Lot')} ${line.batchNo}');
    }
    return ListTile(
      title: Text(line.product.displayName(l.isArabic)),
      subtitle: Text(subtitle.toString()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            money(line.totalCentimes, context),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                _editLine(index);
              } else if (value == 'delete') {
                _removeLine(index);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(l.t('Modifier'))),
              PopupMenuItem(value: 'delete', child: Text(l.t('Supprimer'))),
            ],
          ),
        ],
      ),
      onTap: () => _editLine(index),
    );
  }

  Widget _totalsCard(L10n l) {
    final totalLabel = money(_total, context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _discount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: l.t('Remise'),
                      suffixText: 'DH',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _paid,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) {
                      _paidTouched = true;
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: l.t('Payé'),
                      suffixText: 'DH',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '${l.t('Total')} : $totalLabel',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                OutlinedButton(
                  onPressed: () {
                    _paidTouched = false;
                    setState(() => _syncPaidToTotal());
                  },
                  child: Text(l.t('Tout payer')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in const [
                  'cash',
                  'card',
                  'cheque',
                  'transfer',
                ])
                  ChoiceChip(
                    label: Text(paymentLabel(method, l)),
                    selected: _method == method,
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const Divider(height: 24),
            _amountRow(l.t('Sous-total'), money(_subtotal, context)),
            if (_discountCentimes > 0)
              _amountRow(
                l.t('Remise'),
                '-${money(_discountCentimes, context)}',
              ),
            _amountRow(
              l.t('Total'),
              totalLabel,
              bold: true,
              color: AppTheme.primary,
            ),
            _amountRow(l.t('Payé'), money(_paidCentimes, context)),
            _amountRow(
              l.t('Reste à payer'),
              money(_due, context),
              bold: _due > 0,
              color: _due > 0 ? AppTheme.danger : AppTheme.success,
            ),
          ],
        ),
      ),
    );
  }

  Widget _noteCard(L10n l) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: TextField(
          controller: _note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l.t('Note'),
            hintText: l.t('Facultatif'),
          ),
        ),
      ),
    );
  }

  Widget _amountRow(
    String label,
    String value, {
    bool bold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseLineDraft {
  const _PurchaseLineDraft({
    required this.product,
    required this.unit,
    required this.qtyMilli,
    required this.unitCostCentimes,
    this.expiryDate,
    this.batchNo,
  });

  final Product product;
  final ProductUnit? unit;

  /// Quantity expressed in the selected unit, not in base units.
  final int qtyMilli;
  final int unitCostCentimes;
  final String? expiryDate;
  final String? batchNo;

  int get factorMilli => unit?.factorMilli ?? Qty.milliPerUnit;
  int get baseQtyMilli => Qty.multiply(qtyMilli, factorMilli);
  int get totalCentimes =>
      Money.lineTotal(qtyMilli: qtyMilli, unitPriceCentimes: unitCostCentimes);
  int get baseUnitCostCentimes => baseQtyMilli <= 0
      ? unitCostCentimes
      : (totalCentimes * Qty.milliPerUnit + baseQtyMilli ~/ 2) ~/ baseQtyMilli;

  String unitName(L10n l) => unit == null
      ? unitLabel(product.baseUnit, l)
      : unit!.displayName(l.isArabic);

  _PurchaseLineDraft copyWith({int? qtyMilli, int? unitCostCentimes}) {
    return _PurchaseLineDraft(
      product: product,
      unit: unit,
      qtyMilli: qtyMilli ?? this.qtyMilli,
      unitCostCentimes: unitCostCentimes ?? this.unitCostCentimes,
      expiryDate: expiryDate,
      batchNo: batchNo,
    );
  }
}

class _LineEditResult {
  const _LineEditResult({
    required this.unit,
    required this.qtyMilli,
    required this.unitCostCentimes,
    this.expiryDate,
    this.batchNo,
  });

  final ProductUnit? unit;
  final int qtyMilli;
  final int unitCostCentimes;
  final String? expiryDate;
  final String? batchNo;
}

class _UnitChoice {
  const _UnitChoice({required this.label, required this.unit});
  final String label;
  final ProductUnit? unit;
  int get factorMilli => unit?.factorMilli ?? Qty.milliPerUnit;
}

class _PurchaseLineDialog extends StatefulWidget {
  const _PurchaseLineDialog({
    required this.product,
    required this.initialUnit,
    required this.initialQtyMilli,
    required this.initialCostCentimes,
    required this.initialExpiry,
    this.initialBatchNo,
    required this.defaultCost,
  });

  final Product product;
  final ProductUnit? initialUnit;
  final int initialQtyMilli;
  final int initialCostCentimes;
  final String? initialExpiry;
  final String? initialBatchNo;
  final int Function(Product, ProductUnit?) defaultCost;

  @override
  State<_PurchaseLineDialog> createState() => _PurchaseLineDialogState();
}

class _PurchaseLineDialogState extends State<_PurchaseLineDialog> {
  late final List<_UnitChoice> _choices;
  late _UnitChoice _choice;
  late final TextEditingController _qty;
  late final TextEditingController _cost;
  late final TextEditingController _batch;
  String? _expiry;
  String? _error;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _expiry = widget.initialExpiry;
    _batch = TextEditingController(text: widget.initialBatchNo ?? '');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final l = L10n.of(context);
    _choices = [
      _UnitChoice(
        label:
            '${unitLabel(widget.product.baseUnit, l)} (${l.t('unité de base')})',
        unit: null,
      ),
      for (final unit in widget.product.units)
        if (unit.factorMilli > 0 && unit.factorMilli != Qty.milliPerUnit)
          _UnitChoice(label: unit.displayName(l.isArabic), unit: unit),
    ];
    _choice = _choices.firstWhere(
      (choice) =>
          choice.unit?.id == widget.initialUnit?.id &&
          choice.unit?.name == widget.initialUnit?.name &&
          choice.factorMilli ==
              (widget.initialUnit?.factorMilli ?? Qty.milliPerUnit),
      orElse: () => _choices.first,
    );
    _qty = TextEditingController(text: Qty.format(widget.initialQtyMilli));
    _cost = TextEditingController(
      text: Money.format(widget.initialCostCentimes).replaceAll('\u00A0', ''),
    );
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _batch.dispose();
    super.dispose();
  }

  int? get _parsedQty => Qty.tryParse(_qty.text);
  int? get _parsedCost => Money.tryParseToCentimes(_cost.text);

  int get _lineTotal {
    final qty = _parsedQty;
    final cost = _parsedCost;
    if (qty == null || cost == null || qty <= 0 || cost < 0) return 0;
    return Money.lineTotal(qtyMilli: qty, unitPriceCentimes: cost);
  }

  int get _baseQty => Qty.multiply(_parsedQty ?? 0, _choice.factorMilli);

  Future<void> _pickExpiry() async {
    final value = await pickIsoDate(
      context,
      initial: _expiry,
      firstDate: DateTime(DateTime.now().year - 5),
    );
    if (value != null && mounted) setState(() => _expiry = value);
  }

  void _submit() {
    final l = L10n.of(context);
    final qty = _parsedQty;
    final cost = _parsedCost;
    if (qty == null || qty <= 0) {
      setState(() => _error = l.t('Quantité invalide.'));
      return;
    }
    if (cost == null || cost < 0) {
      setState(() => _error = l.t('Coût invalide.'));
      return;
    }
    Navigator.of(context).pop(
      _LineEditResult(
        unit: _choice.unit,
        qtyMilli: qty,
        unitCostCentimes: cost,
        expiryDate: _expiry,
        batchNo: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      ),
    );
  }

  void _onUnitChanged(_UnitChoice? choice) {
    if (choice == null) return;
    final previous = _choice;
    final qty = _parsedQty ?? Qty.milliPerUnit;
    final baseQty = Qty.multiply(qty, previous.factorMilli);
    final cost = widget.defaultCost(widget.product, choice.unit);
    setState(() {
      _choice = choice;
      _qty.text = Qty.format(
        (baseQty * Qty.milliPerUnit + choice.factorMilli ~/ 2) ~/
            choice.factorMilli,
      );
      _cost.text = Money.format(cost).replaceAll('\u00A0', '');
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(widget.product.displayName(l.isArabic)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<_UnitChoice>(
              initialValue: _choice,
              isExpanded: true,
              decoration: InputDecoration(labelText: l.t('Unité')),
              items: [
                for (final choice in _choices)
                  DropdownMenuItem(
                    value: choice,
                    child: Text(choice.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _onUnitChanged,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: l.t('Quantité'),
                      suffixText: _choice.unit == null
                          ? unitLabel(widget.product.baseUnit, l)
                          : _choice.unit!.name,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cost,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    decoration: InputDecoration(
                      labelText: l.t('Prix d\'achat'),
                      suffixText: 'DH',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _batch,
              decoration: InputDecoration(
                labelText: l.t('Numéro de lot (facultatif)'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickExpiry,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _expiry ?? l.t('Date de péremption (facultatif)'),
                    ),
                  ),
                ),
                if (_expiry != null)
                  IconButton(
                    tooltip: l.t('Supprimer'),
                    onPressed: () => setState(() => _expiry = null),
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${l.t('Total')} : ${money(_lineTotal, context)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (_choice.unit != null)
                    Text(
                      '${Qty.format(_baseQty)} '
                      '${unitLabel(widget.product.baseUnit, l)}'
                      ' · ${l.t('Stock actuel')} '
                      '${Qty.format(widget.product.stockMilli)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
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
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(onPressed: _submit, child: Text(l.t('Valider'))),
      ],
    );
  }
}
