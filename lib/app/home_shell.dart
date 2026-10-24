import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../core/business_type.dart';
import '../core/l10n/l10n.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/more/more_screen.dart';
import '../features/parties/parties_screen.dart';
import '../features/pos/pos_screen.dart';
import '../features/products/products_screen.dart';
import '../features/sales/sales_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final smallShop =
        AppScope.of(context).businessType == BusinessType.smallShop;
    final pages = smallShop
        ? const <Widget>[
            PosScreen(),
            ProductsScreen(),
            PartiesScreen(kind: PartyKind.customer),
            MoreScreen(),
          ]
        : const <Widget>[
            DashboardScreen(),
            PosScreen(),
            ProductsScreen(),
            SalesScreen(),
            MoreScreen(),
          ];
    final destinations = smallShop
        ? [
            (
              icon: Icons.point_of_sale_outlined,
              selected: Icons.point_of_sale,
              label: l.t('Caisse'),
            ),
            (
              icon: Icons.inventory_2_outlined,
              selected: Icons.inventory_2,
              label: l.t('Produits'),
            ),
            (
              icon: Icons.handshake_outlined,
              selected: Icons.handshake,
              label: l.t('Dettes'),
            ),
            (
              icon: Icons.grid_view_outlined,
              selected: Icons.grid_view,
              label: l.t('Plus'),
            ),
          ]
        : [
            (
              icon: Icons.dashboard_outlined,
              selected: Icons.dashboard,
              label: l.t('Tableau de bord'),
            ),
            (
              icon: Icons.point_of_sale_outlined,
              selected: Icons.point_of_sale,
              label: l.t('Caisse'),
            ),
            (
              icon: Icons.inventory_2_outlined,
              selected: Icons.inventory_2,
              label: l.t('Produits'),
            ),
            (
              icon: Icons.receipt_long_outlined,
              selected: Icons.receipt_long,
              label: l.t('Ventes'),
            ),
            (
              icon: Icons.grid_view_outlined,
              selected: Icons.grid_view,
              label: l.t('Plus'),
            ),
          ];
    final index = _index < 0
        ? 0
        : (_index >= pages.length ? pages.length - 1 : _index);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final body = IndexedStack(index: index, children: pages);
        if (wide) {
          return Scaffold(
            key: _scaffoldKey,
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: index,
                  onDestinationSelected: _select,
                  labelType: NavigationRailLabelType.all,
                  minWidth: 82,
                  leading: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.storefront,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Hydra',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  destinations: [
                    for (final d in destinations)
                      NavigationRailDestination(
                        icon: Icon(d.icon),
                        selectedIcon: Icon(d.selected),
                        label: Text(d.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          key: _scaffoldKey,
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: _select,
            destinations: [
              for (final d in destinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selected),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}
