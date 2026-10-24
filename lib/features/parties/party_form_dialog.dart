import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../data/models/models.dart';
import '../../ui/widgets/common.dart';

/// Creates or edits a customer/supplier. Returns true when the database was
/// changed so the caller can refresh its list.
Future<bool?> showPartyForm(
  BuildContext context, {
  Customer? customer,
  Supplier? supplier,
}) {
  assert(customer == null || supplier == null);
  return showDialog<bool>(
    context: context,
    builder: (_) => _PartyFormDialog(customer: customer, supplier: supplier),
  );
}

class _PartyFormDialog extends StatefulWidget {
  const _PartyFormDialog({this.customer, this.supplier});
  final Customer? customer;
  final Supplier? supplier;

  @override
  State<_PartyFormDialog> createState() => _PartyFormDialogState();
}

class _PartyFormDialogState extends State<_PartyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _note;
  late final TextEditingController _limit;
  bool _saving = false;

  bool get _isCustomer => widget.supplier == null;
  bool get _editing => widget.customer != null || widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    final s = widget.supplier;
    _name = TextEditingController(text: c?.name ?? s?.name ?? '');
    _phone = TextEditingController(text: c?.phone ?? s?.phone ?? '');
    _address = TextEditingController(text: c?.address ?? s?.address ?? '');
    _note = TextEditingController(text: c?.note ?? s?.note ?? '');
    _limit = TextEditingController(
      text: c == null || c.creditLimitCentimes == 0
          ? ''
          : Money.format(c.creditLimitCentimes).replaceAll('\u00A0', ''),
    );
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _note, _limit]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final c = AppScope.of(context);
    final l = c.l10n;
    final limit = _limit.text.trim().isEmpty
        ? 0
        : Money.tryParseToCentimes(_limit.text);
    if (limit == null || limit < 0) {
      showInfo(context, l.t('Montant invalide.'));
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isCustomer) {
        final existing = widget.customer;
        final customer = Customer(
          id: existing?.id ?? 0,
          name: _name.text.trim(),
          phone: _blankToNull(_phone.text),
          address: _blankToNull(_address.text),
          note: _blankToNull(_note.text),
          balanceCentimes: existing?.balanceCentimes ?? 0,
          creditLimitCentimes: limit,
          createdAt: existing?.createdAt ?? 0,
        );
        if (existing == null) {
          await c.parties.createCustomer(customer);
        } else {
          await c.parties.updateCustomer(customer);
        }
      } else {
        final existing = widget.supplier;
        final supplier = Supplier(
          id: existing?.id ?? 0,
          name: _name.text.trim(),
          phone: _blankToNull(_phone.text),
          address: _blankToNull(_address.text),
          note: _blankToNull(_note.text),
          balanceCentimes: existing?.balanceCentimes ?? 0,
          createdAt: existing?.createdAt ?? 0,
        );
        if (existing == null) {
          await c.parties.createSupplier(supplier);
        } else {
          await c.parties.updateSupplier(supplier);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final title = _isCustomer
        ? (_editing ? l.t('Modifier le client') : l.t('Nouveau client'))
        : (_editing
              ? l.t('Modifier le fournisseur')
              : l.t('Nouveau fournisseur'));
    return AlertDialog(
      title: Text(title),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: l.t('Nom')),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? l.t('Champ requis')
                    : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: l.t('Téléphone')),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _address,
                decoration: InputDecoration(labelText: l.t('Adresse')),
              ),
              if (_isCustomer) ...[
                const SizedBox(height: 10),
                TextFormField(
                  controller: _limit,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l.t('Limite de crédit'),
                    suffixText: 'DH',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(labelText: l.t('Note')),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: Text(l.t('Enregistrer')),
        ),
      ],
    );
  }
}
