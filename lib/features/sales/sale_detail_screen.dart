import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../core/quantity.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'return_sale_screen.dart';

class SaleDetailScreen extends StatefulWidget {
  const SaleDetailScreen({super.key, required this.saleId});
  final int saleId;

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  Future<_SaleDetailData>? _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SaleDetailData> _load() async {
    final c = AppScope.read(context);
    final sale = await c.sales.findById(widget.saleId);
    if (sale == null) throw Exception(c.l10n.t('Vente introuvable'));
    final returns = await c.returns.returnsForSale(widget.saleId);
    return _SaleDetailData(sale, returns);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _print(Sale sale) async {
    final c = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await c.printer.printSale(sale, c.shop);
      if (mounted) showInfo(context, c.l10n.t('Reçu'));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sharePdf(Sale sale, {bool receipt = false}) async {
    final c = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final paper = await c.settings.paperWidth();
      final bytes = await c.pdf.saleDocument(
        sale: sale,
        shop: c.shop,
        arabic: c.isArabic,
        receipt: receipt,
        paperWidthMm: paper.toDouble(),
      );
      await Printing.sharePdf(bytes: bytes, filename: '${sale.invoiceNo}.pdf');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _return(Sale sale) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReturnSaleScreen(sale: sale)),
    );
    if (changed == true) _reload();
  }

  Future<void> _void(Sale sale) async {
    final l = AppScope.of(context).l10n;
    final reason = await promptText(
      context,
      title: l.t('Motif de l\'annulation'),
      maxLines: 2,
    );
    if (reason == null || !mounted) return;
    final ok = await confirm(
      context,
      title: l.t('Annuler cette vente ?'),
      message: l.t('Le stock sera remis et la caisse ajustée.'),
      confirmLabel: l.t('Annulation'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await AppScope.of(context).sales.voidSale(sale.id, reason);
      if (!mounted) return;
      showInfo(context, l.t('Vente annulée'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _pay(Sale sale) async {
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(due: sale.dueCentimes),
    );
    if (input == null || !mounted) return;
    try {
      await AppScope.of(context).sales.addPayment(
        saleId: sale.id,
        amountCentimes: input.amountCentimes,
        method: input.method,
        note: input.note,
      );
      if (!mounted) return;
      showInfo(context, AppScope.of(context).l10n.t('Paiement enregistré'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Détail de la vente')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          FutureBuilder<_SaleDetailData>(
            future: _future,
            builder: (context, snapshot) {
              final sale = snapshot.data?.sale;
              if (sale == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'receipt':
                      _sharePdf(sale, receipt: true);
                    case 'invoice':
                      _sharePdf(sale);
                    case 'print':
                      _print(sale);
                    case 'return':
                      if (!sale.isVoided) _return(sale);
                    case 'void':
                      if (!sale.isVoided) _void(sale);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'print',
                    child: Text(l.t('Imprimer le reçu')),
                  ),
                  PopupMenuItem(
                    value: 'receipt',
                    child: Text(l.t('Partager le reçu')),
                  ),
                  PopupMenuItem(
                    value: 'invoice',
                    child: Text(l.t('Imprimer la facture')),
                  ),
                  if (!sale.isVoided) ...[
                    PopupMenuItem(value: 'return', child: Text(l.t('Retours'))),
                    PopupMenuItem(
                      value: 'void',
                      child: Text(l.t('Annuler la vente')),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<_SaleDetailData>(
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
    );
  }

  Widget _content(_SaleDetailData data) {
    final l = L10n.of(context);
    final sale = data.sale;
    final color = sale.isVoided
        ? AppTheme.danger
        : sale.dueCentimes == 0
        ? AppTheme.success
        : AppTheme.accent;
    return PageBody(
      maxWidth: 900,
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sale.invoiceNo,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      StatusChip(
                        label: sale.isVoided
                            ? l.t('Annulée')
                            : sale.dueCentimes == 0
                            ? l.t('Payée')
                            : l.t('Payé partiellement'),
                        color: color,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${dateLabel(sale.businessDate, l)} · '
                    '${Dates.formatTime(DateTime.fromMillisecondsSinceEpoch(sale.createdAt))}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _row(
                    l.t('Client'),
                    sale.customerName ?? l.t('Client de passage'),
                  ),
                  _row(
                    l.t('Moyen de paiement'),
                    paymentLabel(sale.paymentMethod, l),
                  ),
                  _row(
                    l.t('Total'),
                    money(sale.totalCentimes, context),
                    bold: true,
                    color: AppTheme.primary,
                  ),
                  _row(l.t('Payé'), money(sale.paidCentimes, context)),
                  if (sale.dueCentimes > 0)
                    _row(
                      l.t('Reste à payer'),
                      money(sale.dueCentimes, context),
                      color: AppTheme.danger,
                      bold: true,
                    ),
                  if (sale.returnedCentimes > 0)
                    _row(
                      l.t('Retours'),
                      '-${money(sale.returnedCentimes, context)}',
                      color: AppTheme.accent,
                    ),
                  if (sale.isVoided) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l.t('Motif')}: ${sale.voidReason ?? ''}',
                      style: TextStyle(fontSize: 12, color: AppTheme.danger),
                    ),
                  ],
                  if (sale.note != null && sale.note!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${l.t('Note')}: ${sale.note}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if (sale.dueCentimes > 0 && !sale.isVoided) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => _pay(sale),
                        icon: const Icon(Icons.payments_outlined),
                        label: Text(l.t('Encaisser un paiement')),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(l.t('Articles vendus')),
          Card(
            child: Column(
              children: [
                for (final line in sale.lines) _lineTile(line),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _row(
                        l.t('Sous-total'),
                        money(sale.subtotalCentimes, context),
                      ),
                      if (sale.discountCentimes > 0)
                        _row(
                          l.t('Remise'),
                          '-${money(sale.discountCentimes, context)}',
                        ),
                      _row(
                        l.t('Total'),
                        money(sale.totalCentimes, context),
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (data.returns.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionTitle(l.t('Retours')),
            Card(
              child: Column(
                children: [
                  for (final ret in data.returns)
                    ExpansionTile(
                      title: Text(ret.returnNo),
                      subtitle: Text(
                        '${dateLabel(ret.businessDate, l)} · '
                        '${ret.refundMethod == 'cash' ? l.t('Remboursement en espèces') : l.t('Avoir client')}',
                      ),
                      trailing: Text(
                        money(ret.totalCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      children: [
                        for (final line in ret.lines)
                          ListTile(
                            dense: true,
                            leading: const Icon(
                              Icons.keyboard_return,
                              size: 18,
                            ),
                            title: Text(line.productName),
                            subtitle: Text(
                              '${Qty.format(line.qtyMilli)} × '
                              '${money(line.unitPriceCentimes, context)}',
                            ),
                            trailing: Text(
                              money(line.lineTotalCentimes, context),
                            ),
                          ),
                      ],
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

  Widget _lineTile(SaleLine line) {
    final context = this.context;
    return ListTile(
      title: Text(line.productName),
      subtitle: Text(
        '${Qty.format(line.displayQtyMilli)}'
        '${line.unitName.isEmpty ? '' : ' ${line.unitName}'}'
        ' × ${money(line.displayUnitPriceCentimes, context)}',
      ),
      trailing: Text(
        money(line.lineTotalCentimes, context),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

class _SaleDetailData {
  const _SaleDetailData(this.sale, this.returns);
  final Sale sale;
  final List<SaleReturn> returns;
}

class _PaymentInput {
  const _PaymentInput({
    required this.amountCentimes,
    required this.method,
    this.note,
  });
  final int amountCentimes;
  final String method;
  final String? note;
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.due});
  final int due;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final TextEditingController _amount;
  final _note = TextEditingController();
  String _method = 'cash';
  String? _error;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: Money.format(widget.due).replaceAll('\u00A0', ''),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _submit() {
    final l = L10n.of(context);
    final value = Money.tryParseToCentimes(_amount.text);
    if (value == null || value <= 0) {
      setState(() => _error = l.t('Montant invalide.'));
      return;
    }
    if (value > widget.due) {
      setState(() => _error = l.t('Montant trop élevé'));
      return;
    }
    Navigator.pop(
      context,
      _PaymentInput(
        amountCentimes: value,
        method: _method,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l.t('Encaisser un paiement')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Montant'),
                suffixText: 'DH',
              ),
            ),
            const SizedBox(height: 10),
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
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.t('Note')),
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
        FilledButton(onPressed: _submit, child: Text(l.t('Valider'))),
      ],
    );
  }
}
