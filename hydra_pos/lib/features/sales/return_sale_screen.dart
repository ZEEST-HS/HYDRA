import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../domain/sales/return_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class ReturnSaleScreen extends StatefulWidget {
  const ReturnSaleScreen({super.key, required this.sale});
  final Sale sale;

  @override
  State<ReturnSaleScreen> createState() => _ReturnSaleScreenState();
}

class _ReturnSaleScreenState extends State<ReturnSaleScreen> {
  final _controllers = <int, TextEditingController>{};
  final _note = TextEditingController();
  Map<int, int> _returned = const {};
  late String _method;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _hasCustomer => widget.sale.customerId != null;
  bool get _hasDue => widget.sale.dueCentimes > 0;

  @override
  void initState() {
    super.initState();
    _method = _hasDue || !_hasCustomer ? 'credit' : 'cash';
    _load();
  }

  Future<void> _load() async {
    try {
      final map = await AppScope.read(context).returns
          .returnedQuantities(widget.sale.id);
      if (!mounted) return;
      setState(() {
        _returned = map;
        _loading = false;
      });
      for (final line in widget.sale.lines) {
        _controllers[line.id] = TextEditingController();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _note.dispose();
    super.dispose();
  }

  int _remaining(SaleLine line) {
    final already = _returned[line.id] ?? 0;
    final remaining = line.qtyMilli - already;
    return remaining < 0 ? 0 : remaining;
  }

  int _enteredBase(SaleLine line) {
    final controller = _controllers[line.id];
    final entered = controller == null ? 0 : Qty.tryParse(controller.text) ?? 0;
    if (entered <= 0) return 0;
    return Qty.multiply(
      entered,
      line.factorMilli > 0 ? line.factorMilli : 1000,
    );
  }

  int get _estimatedTotal {
    var total = 0;
    for (final line in widget.sale.lines) {
      final qty = _enteredBase(line);
      if (qty <= 0 || line.qtyMilli <= 0) continue;
      total +=
          (line.lineTotalCentimes * qty + line.qtyMilli ~/ 2) ~/ line.qtyMilli;
    }
    return total;
  }

  Future<void> _submit() async {
    final l = AppScope.of(context).l10n;
    final lines = <ReturnDraftLine>[];
    for (final line in widget.sale.lines) {
      final qty = _enteredBase(line);
      if (qty <= 0) continue;
      final remaining = _remaining(line);
      if (qty > remaining) {
        setState(
          () => _error = '${l.t('Trop de quantité')} : ${line.productName}',
        );
        return;
      }
      lines.add(ReturnDraftLine(saleLineId: line.id, qtyMilli: qty));
    }
    if (lines.isEmpty) {
      setState(() => _error = l.t('Sélectionnez au moins un article'));
      return;
    }
    if (_method == 'credit' && !_hasCustomer) {
      setState(
        () => _error = l.t(
          'Un remboursement en avoir nécessite un client identifié.',
        ),
      );
      return;
    }
    if (_method == 'cash' && _hasDue) {
      setState(
        () => _error = l.t(
          'Cette vente a un reste à payer : remboursez en avoir (crédit).',
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await AppScope.of(context).returns.returnSale(
        saleId: widget.sale.id,
        lines: lines,
        refundMethod: _method,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      showInfo(context, '${l.t('Retour enregistré')} · ${result.returnNo}');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('Retourner'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _controllers.isEmpty
          ? EmptyState(
              message: _error!,
              icon: Icons.error_outline,
              action: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l.t('Retour')),
              ),
            )
          : PageBody(
              maxWidth: 820,
              child: ListView(
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.sale.invoiceNo,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${l.t('Client')}: ${widget.sale.customerName ?? l.t('Client de passage')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          if (_hasDue)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                l.t(
                                  'Cette vente a un reste à payer : remboursez en avoir (crédit).',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final line in widget.sale.lines)
                    _ReturnLineCard(
                      line: line,
                      remaining: _remaining(line),
                      controller: _controllers[line.id],
                      onChanged: () => setState(() {}),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    l.t('Remboursement'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l.t('Remboursement en espèces')),
                        selected: _method == 'cash',
                        onSelected: _hasDue
                            ? null
                            : (_) => setState(() => _method = 'cash'),
                      ),
                      ChoiceChip(
                        label: Text(l.t('Avoir client')),
                        selected: _method == 'credit',
                        onSelected: _hasCustomer
                            ? (_) => setState(() => _method = 'credit')
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _note,
                    maxLines: 2,
                    decoration: InputDecoration(labelText: l.t('Note')),
                  ),
                  const SizedBox(height: 14),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
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
                            money(_estimatedTotal, context),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: AppTheme.danger)),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.keyboard_return),
                    label: Text(l.t('Retourner')),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }
}

class _ReturnLineCard extends StatelessWidget {
  const _ReturnLineCard({
    required this.line,
    required this.remaining,
    required this.controller,
    required this.onChanged,
  });

  final SaleLine line;
  final int remaining;
  final TextEditingController? controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final factor = line.factorMilli > 0 ? line.factorMilli : 1000;
    final available = (remaining * Qty.milliPerUnit) ~/ factor;
    final unit = line.unitName.isEmpty ? l.t('Pièce') : line.unitName;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  money(line.lineTotalCentimes, context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${l.t('Quantité à retourner')} · '
              '${Qty.format(available)} $unit ${l.t('disponible(s)')}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              enabled: remaining > 0,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onChanged: (_) => onChanged(),
              decoration: InputDecoration(
                labelText: '${l.t('Quantité')} ($unit)',
                suffixText: unit,
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
