import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';
import 'party_form_dialog.dart';

/// Searchable supplier picker used by purchase entry.
Future<Supplier?> pickSupplier(BuildContext context, {int? selectedId}) {
  return showModalBottomSheet<Supplier>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SupplierPickerSheet(selectedId: selectedId),
  );
}

class SupplierPickerSheet extends StatefulWidget {
  const SupplierPickerSheet({super.key, this.selectedId});
  final int? selectedId;

  @override
  State<SupplierPickerSheet> createState() => _SupplierPickerSheetState();
}

class _SupplierPickerSheetState extends State<SupplierPickerSheet> {
  final _search = TextEditingController();
  List<Supplier> _suppliers = const [];
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
          .suppliers(query: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _suppliers = list;
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
                      l.t('Choisir un fournisseur'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.storefront_outlined),
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
                    : _suppliers.isEmpty
                    ? EmptyState(
                        message: l.t('Aucun fournisseur'),
                        icon: Icons.store_outlined,
                        action: FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: Text(l.t('Ajouter un fournisseur')),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _suppliers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final supplier = _suppliers[index];
                          final selected = supplier.id == widget.selectedId;
                          final owed = supplier.balanceCentimes > 0;
                          return ListTile(
                            selected: selected,
                            leading: CircleAvatar(
                              backgroundColor: selected
                                  ? Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                  : null,
                              child: Text(
                                supplier.name.trim().isEmpty
                                    ? '?'
                                    : supplier.name.trim()[0].toUpperCase(),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                            title: Text(supplier.name),
                            subtitle: supplier.phone == null
                                ? null
                                : Text(supplier.phone!),
                            trailing: owed
                                ? Text(
                                    money(supplier.balanceCentimes, context),
                                    style: TextStyle(
                                      color: AppTheme.danger,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(supplier),
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
