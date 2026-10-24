import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../data/models/models.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

enum _ExpensePeriod { today, week, month, all }

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  _ExpensePeriod _period = _ExpensePeriod.month;
  Future<List<Expense>>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  DateTimeRange? _range() {
    final now = DateTime.now();
    switch (_period) {
      case _ExpensePeriod.today:
        return DateTimeRange(start: now, end: now);
      case _ExpensePeriod.week:
        return DateTimeRange(
          start: now.subtract(const Duration(days: 6)),
          end: now,
        );
      case _ExpensePeriod.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case _ExpensePeriod.all:
        return null;
    }
  }

  Future<List<Expense>> _load() {
    final range = _range();
    return AppScope.read(context).expenses
        .list(from: range?.start, to: range?.end);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _add() async {
    final input = await showDialog<_ExpenseInput>(
      context: context,
      builder: (_) => const _ExpenseDialog(),
    );
    if (input == null || !mounted) return;
    try {
      await AppScope.of(context).expenses.create(
        category: input.category,
        amountCentimes: input.amountCentimes,
        method: input.method,
        note: input.note,
        at: input.at,
      );
      if (!mounted) return;
      showInfo(context, AppScope.of(context).l10n.t('Dépense enregistrée'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _delete(Expense expense) async {
    final l = AppScope.of(context).l10n;
    final reason = await promptText(
      context,
      title: l.t('Motif de la suppression'),
      initial: l.t('Erreur de saisie'),
    );
    if (reason == null || !mounted) return;
    try {
      await AppScope.of(context).expenses.delete(expense.id, reason);
      if (!mounted) return;
      showInfo(context, l.t('Dépense supprimée'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('Dépenses'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l.t('Nouvelle dépense')),
      ),
      body: PageBody(
        maxWidth: 820,
        child: Column(
          children: [
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final period in _ExpensePeriod.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(_periodLabel(period, l)),
                        selected: _period == period,
                        onSelected: (_) => setState(() {
                          _period = period;
                          _future = _load();
                        }),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<Expense>>(
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
                  final expenses = snapshot.data ?? const <Expense>[];
                  var total = 0;
                  for (final expense in expenses) {
                    total += expense.amountCentimes;
                  }
                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 96),
                      children: [
                        StatCard(
                          label: l.t('Total dépenses'),
                          value: money(total, context),
                          icon: Icons.payments_outlined,
                          color: AppTheme.danger,
                          footnote: '${expenses.length} ${l.t('dépense(s)')}',
                        ),
                        const SizedBox(height: 12),
                        if (expenses.isEmpty)
                          EmptyState(
                            message: l.t('Aucune dépense'),
                            icon: Icons.receipt_long_outlined,
                            action: FilledButton.icon(
                              onPressed: _add,
                              icon: const Icon(Icons.add),
                              label: Text(l.t('Nouvelle dépense')),
                            ),
                          )
                        else
                          Card(
                            child: Column(
                              children: [
                                for (final expense in expenses)
                                  ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: AppTheme.danger
                                          .withValues(alpha: 0.1),
                                      child: Icon(
                                        Icons.receipt_long_outlined,
                                        color: AppTheme.danger,
                                        size: 20,
                                      ),
                                    ),
                                    title: Text(expense.category),
                                    subtitle: Text(
                                      '${dateLabel(expense.businessDate, l)}'
                                      ' · ${paymentLabel(expense.method, l)}'
                                      '${expense.note == null ? '' : ' · ${expense.note}'}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          money(
                                            expense.amountCentimes,
                                            context,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'delete') {
                                              _delete(expense);
                                            }
                                          },
                                          itemBuilder: (context) => [
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
                        const SizedBox(height: 32),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _periodLabel(_ExpensePeriod period, L10n l) {
    switch (period) {
      case _ExpensePeriod.today:
        return l.t('Aujourd\'hui');
      case _ExpensePeriod.week:
        return l.t('7 derniers jours');
      case _ExpensePeriod.month:
        return l.t('Ce mois');
      case _ExpensePeriod.all:
        return l.t('Tous');
    }
  }
}

class _ExpenseInput {
  const _ExpenseInput({
    required this.category,
    required this.amountCentimes,
    required this.method,
    this.note,
    required this.at,
  });
  final String category;
  final int amountCentimes;
  final String method;
  final String? note;
  final DateTime at;
}

class _ExpenseDialog extends StatefulWidget {
  const _ExpenseDialog();

  @override
  State<_ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<_ExpenseDialog> {
  final _category = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  DateTime _date = DateTime.now();
  String? _error;

  static const _suggestions = [
    'Loyer',
    'Salaires',
    'Électricité',
    'Eau',
    'Transport',
    'Emballage',
    'Entretien',
    'Autre',
  ];

  @override
  void dispose() {
    _category.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 5),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDate: _date,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final l = L10n.of(context);
    final amount = Money.tryParseToCentimes(_amount.text);
    if (_category.text.trim().isEmpty) {
      setState(() => _error = l.t('La catégorie est obligatoire.'));
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = l.t('Montant invalide.'));
      return;
    }
    Navigator.pop(
      context,
      _ExpenseInput(
        category: _category.text.trim(),
        amountCentimes: amount,
        method: _method,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        at: _date,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l.t('Nouvelle dépense')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _category,
              autofocus: true,
              decoration: InputDecoration(labelText: l.t('Catégorie')),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final suggestion in _suggestions)
                    ActionChip(
                      label: Text(l.t(suggestion)),
                      onPressed: () =>
                          setState(() => _category.text = l.t(suggestion)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Montant'),
                suffixText: 'DH',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.event_outlined),
              label: Text(Dates.formatDate(_date)),
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
