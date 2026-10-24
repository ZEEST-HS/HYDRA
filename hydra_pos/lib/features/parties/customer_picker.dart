import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'party_form_dialog.dart';

/// Opens a searchable customer picker. Returns the chosen customer, or null
/// when the sheet is dismissed.
Future<Customer?> pickCustomer(BuildContext context, {int? selectedId}) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => CustomerPickerSheet(selectedId: selectedId),
  );
}

class CustomerPickerSheet extends StatefulWidget {
  const CustomerPickerSheet({super.key, this.selectedId});
  final int? selectedId;

  @override
  State<CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<CustomerPickerSheet> {
  final _search = TextEditingController();
  List<Customer> _customers = const [];
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
      final list = await AppScope.read(context).parties
          .customers(query: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _customers = list;
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

  Future<void> _add() async {
    final created = await showPartyForm(context);
    if (created == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.78;
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
                      l.t('Choisir un client'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: Text(l.t('Ajouter')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _load(),
                decoration: InputDecoration(
                  hintText: l.t('Rechercher'),
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
                    : _customers.isEmpty
                    ? EmptyState(
                        message: l.t('Aucun client'),
                        icon: Icons.people_outline,
                        action: FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: Text(l.t('Ajouter un client')),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _customers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final customer = _customers[index];
                          final selected = customer.id == widget.selectedId;
                          final owes = customer.balanceCentimes > 0;
                          return ListTile(
                            selected: selected,
                            leading: CircleAvatar(
                              backgroundColor: selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : null,
                              child: Text(
                                customer.name.trim().isEmpty
                                    ? '?'
                                    : customer.name.trim()[0].toUpperCase(),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            title: Text(customer.name),
                            subtitle: customer.phone == null
                                ? null
                                : Text(customer.phone!),
                            trailing: owes
                                ? Text(
                                    money(customer.balanceCentimes, context),
                                    style: TextStyle(
                                      color: AppTheme.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(customer),
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
