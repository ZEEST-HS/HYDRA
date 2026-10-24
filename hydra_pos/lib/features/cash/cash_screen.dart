import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/dates.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money.dart';
import '../../data/models/models.dart';
import '../../domain/cash/cash_service.dart';
import '../../ui/theme.dart';
import '../../ui/widgets/common.dart';

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _opening = TextEditingController();
  final _counted = TextEditingController();
  final _note = TextEditingController();
  Future<_CashData>? _future;
  bool _busy = false;
  bool _countedTouched = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void dispose() {
    _opening.dispose();
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<_CashData> _load() async {
    final c = AppScope.read(context);
    final session = await c.cash.openSession();
    final breakdown = session == null ? null : await c.cash.breakdown(session);
    final history = await c.cash.history();
    if (breakdown != null && !_countedTouched) {
      _counted.text = Money.format(breakdown.expectedCash)
          .replaceAll('\u00A0', '');
    }
    return _CashData(session, breakdown, history);
  }

  Future<void> _reload() async {
    _countedTouched = false;
    setState(() {
      _future = _load();
    });
    await _future;
  }

  Future<void> _open() async {
    final l = AppScope.of(context).l10n;
    final opening = Money.tryParseToCentimes(_opening.text);
    if (opening == null || opening < 0) {
      showError(context, l.t('Montant invalide.'));
      return;
    }
    setState(() => _busy = true);
    try {
      await AppScope.of(context).cash.open(
        openingCashCentimes: opening,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      _opening.clear();
      _note.clear();
      showInfo(context, l.t('Session ouverte'));
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _close(CashBreakdown breakdown) async {
    final l = AppScope.of(context).l10n;
    final counted = Money.tryParseToCentimes(_counted.text);
    if (counted == null || counted < 0) {
      showError(context, l.t('Montant invalide.'));
      return;
    }
    final ok = await confirm(
      context,
      title: l.t('Fermer la session ?'),
      message:
          '${l.t('Espèces attendues')} : ${money(breakdown.expectedCash, context)}',
      confirmLabel: l.t('Fermer la caisse'),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await AppScope.of(context).cash.close(
        countedCashCentimes: counted,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (!mounted) return;
      _note.clear();
      showInfo(context, l.t('Session clôturée'));
      await _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('Caisse du jour')),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: FutureBuilder<_CashData>(
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
          final data = snapshot.data!;
          return PageBody(
            maxWidth: 820,
            child: ListView(
              children: [
                if (data.session == null)
                  _openCard(l)
                else
                  _sessionCard(data, l),
                const SizedBox(height: 18),
                SectionTitle(l.t('Historique')),
                if (data.history.isEmpty)
                  Card(
                    child: EmptyState(
                      message: l.t('Aucune session'),
                      icon: Icons.history,
                    ),
                  )
                else
                  Card(
                    child: Column(
                      children: [
                        for (final session in data.history)
                          _historyTile(session, l),
                      ],
                    ),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _openCard(L10n l) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, color: AppTheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.t('Ouvrir une session de caisse'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _opening,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l.t('Fond de caisse'),
                suffixText: 'DH',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: l.t('Note')),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _open,
              icon: const Icon(Icons.lock_open),
              label: Text(l.t('Ouvrir la caisse')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sessionCard(_CashData data, L10n l) {
    final session = data.session!;
    final breakdown = data.breakdown!;
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.success.withValues(alpha: 0.1),
                      child: Icon(Icons.lock_open, color: AppTheme.success),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l.t('Session ouverte'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            Dates.formatDateTime(
                              DateTime.fromMillisecondsSinceEpoch(
                                session.openedAt,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(breakdown.expectedCash, context),
                      style: AppTheme.numberStyle.copyWith(
                        fontSize: 20,
                        color: AppTheme.success,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _row(
                  l.t('Fond de caisse'),
                  money(breakdown.openingCash, context),
                ),
                _row(
                  l.t('Ventes en espèces'),
                  money(breakdown.cashSales, context),
                ),
                _row(
                  l.t('Paiements clients'),
                  money(breakdown.customerPayments, context),
                ),
                if (breakdown.otherCashIn != 0)
                  _row(
                    l.t('Autres entrées'),
                    money(breakdown.otherCashIn, context),
                  ),
                if (breakdown.supplierPayments != 0)
                  _row(
                    l.t('Paiements fournisseurs'),
                    '-${money(breakdown.supplierPayments, context)}',
                  ),
                if (breakdown.supplierRefunds != 0)
                  _row(
                    l.t('Remboursements fournisseurs'),
                    money(breakdown.supplierRefunds, context),
                  ),
                if (breakdown.cashExpenses != 0)
                  _row(
                    l.t('Dépenses en espèces'),
                    '-${money(breakdown.cashExpenses, context)}',
                  ),
                if (breakdown.refundsAndVoids != 0)
                  _row(
                    l.t('Remboursements'),
                    '-${money(breakdown.refundsAndVoids, context)}',
                  ),
                const Divider(height: 20),
                _row(
                  l.t('Espèces attendues'),
                  money(breakdown.expectedCash, context),
                  bold: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l.t('Fermer la caisse'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _counted,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => _countedTouched = true,
                  decoration: InputDecoration(
                    labelText: l.t('Espèces comptées'),
                    suffixText: 'DH',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  decoration: InputDecoration(labelText: l.t('Note')),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _close(breakdown),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(l.t('Fermer la caisse')),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _historyTile(CashSession session, L10n l) {
    final open = session.status == 'open';
    final difference = session.differenceCentimes;
    final color = open
        ? AppTheme.success
        : (difference == null || difference == 0
              ? AppTheme.primary
              : (difference > 0 ? AppTheme.accent : AppTheme.danger));
    final date = Dates.formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(session.closedAt ?? session.openedAt),
    );
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(
          open ? Icons.lock_open : Icons.lock_outline,
          color: color,
          size: 20,
        ),
      ),
      title: Text(
        '$date · ${open ? l.t('Session ouverte') : l.t('Session clôturée')}',
      ),
      subtitle: Text(
        '${l.t('Fond de caisse')} : '
        '${money(session.openingCashCentimes, context)}'
        '${session.countedCashCentimes == null ? '' : ' · ${l.t('Espèces comptées')} : ${money(session.countedCashCentimes!, context)}'}',
      ),
      trailing: session.expectedCashCentimes == null
          ? null
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(session.expectedCashCentimes!, context),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (difference != null)
                  Text(
                    '${l.t('Écart')} ${money(difference, context)}',
                    style: TextStyle(fontSize: 11, color: color),
                  ),
              ],
            ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
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

class _CashData {
  const _CashData(this.session, this.breakdown, this.history);
  final CashSession? session;
  final CashBreakdown? breakdown;
  final List<CashSession> history;
}
