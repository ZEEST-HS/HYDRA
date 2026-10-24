import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/business_type.dart';
import '../../core/l10n/l10n.dart';
import '../../ui/theme.dart';
import '../cash/cash_screen.dart';
import '../expenses/expenses_screen.dart';
import '../inventory/inventory_screen.dart';
import '../parties/parties_screen.dart';
import '../purchases/purchases_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final smallShop =
        AppScope.of(context).businessType == BusinessType.smallShop;

    final purchases = _MoreItem(
      l.t('Achats'),
      l.t('Fournisseurs et réception de stock'),
      Icons.local_shipping_outlined,
      AppTheme.primary,
      (c) => const PurchasesScreen(),
    );
    final stock = _MoreItem(
      l.t('Stock'),
      l.t('Inventaire, alertes et péremptions'),
      Icons.inventory_outlined,
      AppTheme.info,
      (c) => const InventoryScreen(),
    );
    final customers = _MoreItem(
      l.t('Clients'),
      l.t('Dettes et historique'),
      Icons.people_outline,
      AppTheme.violet,
      (c) => const PartiesScreen(kind: PartyKind.customer),
    );
    final suppliers = _MoreItem(
      l.t('Fournisseurs'),
      l.t('Soldes et paiements'),
      Icons.store_outlined,
      AppTheme.brown,
      (c) => const PartiesScreen(kind: PartyKind.supplier),
    );
    final reports = _MoreItem(
      l.t('Rapports'),
      l.t('Ventes, marges et dépenses'),
      Icons.insights_outlined,
      AppTheme.primary,
      (c) => const ReportsScreen(),
    );
    final expenses = _MoreItem(
      l.t('Dépenses'),
      l.t('Sorties de caisse'),
      Icons.payments_outlined,
      AppTheme.rose,
      (c) => const ExpensesScreen(),
    );
    final cash = _MoreItem(
      l.t('Caisse du jour'),
      l.t('Ouverture et clôture'),
      Icons.account_balance_wallet_outlined,
      AppTheme.success,
      (c) => const CashScreen(),
    );
    final settings = _MoreItem(
      l.t('Réglages'),
      l.t('Boutique, imprimante, sauvegardes'),
      Icons.settings_outlined,
      AppTheme.slate,
      (c) => const SettingsScreen(),
    );

    // Small shops get everyday tasks first; the full POS tools stay reachable
    // further down without cluttering the main navigation.
    final items = smallShop
        ? [stock, expenses, cash, settings, purchases, suppliers, reports]
        : [
            purchases,
            stock,
            customers,
            suppliers,
            reports,
            expenses,
            cash,
            settings,
          ];

    return Scaffold(
      appBar: AppBar(title: Text(l.t('Plus'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.offline_bolt_outlined,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l.t('Les données restent sur cet appareil.'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final item in items) ...[
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: item.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(item.icon, color: item.color),
                    ),
                    title: Text(
                      item.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(item.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        Navigator.of(context)
                            .push(MaterialPageRoute(builder: item.builder)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(
    this.title,
    this.subtitle,
    this.icon,
    this.color,
    this.builder,
  );
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}
