import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import '../purchases/purchase_detail_screen.dart';
import '../sales/sale_detail_screen.dart';
import 'parties_screen.dart';
import 'party_form_dialog.dart';

class PartyDetailScreen extends StatefulWidget {
  const PartyDetailScreen({
    super.key,
    required this.kind,
    required this.partyId,
  });

  final PartyKind kind;
  final int partyId;

  @override
  State<PartyDetailScreen> createState() => _PartyDetailScreenState();
}

class _PartyDetailScreenState extends State<PartyDetailScreen> {
  Future<_PartyDetailData>? _future;

  bool get _isCustomer => widget.kind == PartyKind.customer;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PartyDetailData> _load() async {
    final c = AppScope.read(context);
    if (_isCustomer) {
      final customer = await c.parties.customer(widget.partyId);
      if (customer == null) {
        throw Exception(c.l10n.t('Client introuvable'));
      }
      return _PartyDetailData(
        customer: customer,
        ledger: await c.parties.ledger('customer', widget.partyId),
        payments: await c.parties.payments(
          partyType: 'customer',
          partyId: widget.partyId,
          limit: 100,
        ),
        sales: await c.sales.salesForCustomer(widget.partyId, limit: 50),
      );
    }
    final supplier = await c.parties.supplier(widget.partyId);
    if (supplier == null) {
      throw Exception(c.l10n.t('Fournisseur introuvable'));
    }
    return _PartyDetailData(
      supplier: supplier,
      ledger: await c.parties.ledger('supplier', widget.partyId),
      payments: await c.parties.payments(
        partyType: 'supplier',
        partyId: widget.partyId,
        limit: 100,
      ),
      purchases: await c.purchases.purchasesForSupplier(
        widget.partyId,
        limit: 50,
      ),
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _edit(_PartyDetailData data) async {
    final changed = await showPartyForm(
      context,
      customer: data.customer,
      supplier: data.supplier,
    );
    if (changed == true) _reload();
  }

  Future<void> _delete(_PartyDetailData data) async {
    final l = AppScope.of(context).l10n;
    final name = data.customer?.name ?? data.supplier?.name ?? '';
    final ok = await confirm(
      context,
      title: l.t('Supprimer'),
      message: '${l.t('Supprimer')} $name ?',
      destructive: true,
      confirmLabel: l.t('Supprimer'),
    );
    if (!ok || !mounted) return;
    try {
      final c = AppScope.of(context);
      if (_isCustomer) {
        await c.parties.deleteCustomer(widget.partyId);
      } else {
        await c.parties.deleteSupplier(widget.partyId);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _settle(_PartyDetailData data) async {
    final balance =
        data.customer?.balanceCentimes ?? data.supplier?.balanceCentimes ?? 0;
    final input = await showDialog<_PaymentInput>(
      context: context,
      builder: (_) => _PaymentDialog(isCustomer: _isCustomer, balance: balance),
    );
    if (input == null || !mounted) return;
    final c = AppScope.of(context);
    final l = c.l10n;
    try {
      if (_isCustomer) {
        await c.parties.receiveCustomerPayment(
          customerId: widget.partyId,
          amountCentimes: input.amountCentimes,
          method: input.method,
          note: input.note,
        );
      } else {
        await c.parties.paySupplier(
          supplierId: widget.partyId,
          amountCentimes: input.amountCentimes,
          method: input.method,
          note: input.note,
        );
      }
      if (!mounted) return;
      showInfo(context, l.t('Paiement enregistré'));
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
        title: Text(
          _isCustomer ? l.t('Détail du client') : l.t('Détail du fournisseur'),
        ),
        actions: [
          FutureBuilder<_PartyDetailData>(
            future: _future,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') _edit(data);
                  if (value == 'delete') _delete(data);
                },
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(l.t('Modifier'))),
                  PopupMenuItem(value: 'delete', child: Text(l.t('Supprimer'))),
                ],
              );
            },
          ),
        ],
      ),
      body: PageBody(
        maxWidth: 980,
        child: FutureBuilder<_PartyDetailData>(
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
      ),
    );
  }

  Widget _content(_PartyDetailData data) {
    final l = L10n.of(context);
    final party = data.customer;
    final supplier = data.supplier;
    final name = party?.name ?? supplier?.name ?? '';
    final phone = party?.phone ?? supplier?.phone;
    final address = party?.address ?? supplier?.address;
    final note = party?.note ?? supplier?.note;
    final balance = party?.balanceCentimes ?? supplier?.balanceCentimes ?? 0;
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppTheme.primary.withValues(
                          alpha: 0.12,
                        ),
                        child: Text(
                          name.trim().isEmpty
                              ? '?'
                              : name.trim()[0].toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (phone != null)
                              Text(
                                phone,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (address != null) ...[
                    const SizedBox(height: 10),
                    Text(address, style: const TextStyle(fontSize: 12)),
                  ],
                  if (note != null && note.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: balance > 0
                          ? AppTheme.danger.withValues(alpha: 0.08)
                          : AppTheme.success.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isCustomer
                                    ? l.t('Dette du client')
                                    : l.t('Solde dû au fournisseur'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                money(balance, context),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: balance > 0
                                      ? AppTheme.danger
                                      : AppTheme.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: balance > 0 ? () => _settle(data) : null,
                          icon: const Icon(Icons.payments_outlined),
                          label: Text(l.t('Régler')),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SectionTitle(l.t('Historique des paiements')),
          if (data.payments.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: EmptyState(
                  message: l.t('Aucun mouvement'),
                  icon: Icons.payments_outlined,
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final payment in data.payments)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        payment.direction == 'in'
                            ? Icons.south_west
                            : Icons.north_east,
                        color: payment.direction == 'in'
                            ? AppTheme.success
                            : AppTheme.danger,
                      ),
                      title: Text(paymentLabel(payment.method, l)),
                      subtitle: Text(dateLabel(payment.businessDate, l)),
                      trailing: Text(
                        money(payment.amountCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          SectionTitle(l.t('Historique')),
          if (data.ledger.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: EmptyState(
                  message: l.t('Aucun mouvement'),
                  icon: Icons.history,
                ),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final entry in data.ledger)
                    ListTile(
                      dense: true,
                      leading: _ledgerIcon(entry.entryType),
                      title: Text(_ledgerLabel(entry.entryType, l)),
                      subtitle: Text(
                        dateLabel(DatesIso.date(entry.createdAt), l),
                      ),
                      trailing: Text(
                        money(entry.amountCentimes, context),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: entry.amountCentimes >= 0
                              ? AppTheme.danger
                              : AppTheme.success,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          if (_isCustomer && data.sales.isNotEmpty) ...[
            SectionTitle(l.t('Ventes du client')),
            Card(
              child: Column(
                children: [
                  for (final sale in data.sales)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(sale.invoiceNo),
                      subtitle: Text(dateLabel(sale.businessDate, l)),
                      trailing: Text(
                        money(sale.totalCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SaleDetailScreen(saleId: sale.id),
                          ),
                        );
                        if (mounted) _reload();
                      },
                    ),
                ],
              ),
            ),
          ],
          if (!_isCustomer && data.purchases.isNotEmpty) ...[
            SectionTitle(l.t('Achats du fournisseur')),
            Card(
              child: Column(
                children: [
                  for (final purchase in data.purchases)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.local_shipping_outlined),
                      title: Text(purchase.refNo),
                      subtitle: Text(dateLabel(purchase.businessDate, l)),
                      trailing: Text(
                        money(purchase.totalCentimes, context),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      onTap: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PurchaseDetailScreen(purchaseId: purchase.id),
                          ),
                        );
                        if (mounted) _reload();
                      },
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

  Icon _ledgerIcon(String type) {
    switch (type) {
      case 'payment':
        return const Icon(Icons.payments_outlined, size: 20);
      case 'sale_due':
        return const Icon(Icons.receipt_long_outlined, size: 20);
      case 'purchase_due':
        return const Icon(Icons.local_shipping_outlined, size: 20);
      case 'return_credit':
        return const Icon(Icons.keyboard_return, size: 20);
      default:
        return const Icon(Icons.swap_horiz, size: 20);
    }
  }

  String _ledgerLabel(String type, L10n l) {
    switch (type) {
      case 'payment':
        return l.t('Paiement');
      case 'sale_due':
        return l.t('Vente à crédit');
      case 'purchase_due':
        return l.t('Achat à crédit');
      case 'return_credit':
        return l.t('Avoir client');
      case 'sale_void':
        return l.t('Annulation vente');
      case 'purchase_void':
        return l.t('Annulation achat');
      default:
        return type;
    }
  }
}

class _PartyDetailData {
  _PartyDetailData({
    this.customer,
    this.supplier,
    this.ledger = const [],
    this.payments = const [],
    this.sales = const [],
    this.purchases = const [],
  });

  final Customer? customer;
  final Supplier? supplier;
  final List<LedgerEntry> ledger;
  final List<Payment> payments;
  final List<Sale> sales;
  final List<Purchase> purchases;
}

/// Tiny helper so ledger dates use the same local-date format as everywhere
/// else without importing date utilities in every widget.
class DatesIso {
  DatesIso._();
  static String date(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
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
  const _PaymentDialog({required this.isCustomer, required this.balance});
  final bool isCustomer;
  final int balance;

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
      text: Money.format(widget.balance).replaceAll('\u00A0', ''),
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
    final amount = Money.tryParseToCentimes(_amount.text);
    if (amount == null || amount <= 0) {
      setState(() => _error = l.t('Montant invalide.'));
      return;
    }
    if (amount > widget.balance) {
      setState(() => _error = l.t('Montant trop élevé'));
      return;
    }
    Navigator.pop(
      context,
      _PaymentInput(
        amountCentimes: amount,
        method: _method,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(
        widget.isCustomer
            ? l.t('Encaisser un paiement')
            : l.t('Payer le fournisseur'),
      ),
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
