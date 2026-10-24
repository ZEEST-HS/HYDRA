import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/db/app_database.dart';
import '../../core/l10n/l10n.dart';
import '../../ui/widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    final c = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('À propos'))),
      body: PageBody(
        maxWidth: 720,
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.storefront_rounded,
                        size: 42,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Hydra POS',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '${l.t('Version')} 1.0.0 · SQLite v${AppDatabase.schemaVersion}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.t(
                        'Caisse et gestion de boutique au Maroc, hors ligne.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.offline_bolt_outlined),
                    title: Text(l.t('Application hors ligne')),
                    subtitle: Text(
                      l.t(
                        'Toutes les données sont stockées dans SQLite sur cet appareil.',
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(l.t('Confidentialité')),
                    subtitle: Text(l.t('Aucune donnée envoyée sans action.')),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.qr_code_scanner),
                    title: Text(l.t('Catalogue')),
                    subtitle: Text(
                      l.t('Open Food Facts et Open Products Facts'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.t('Attribution des données'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l.t(
                        'Les informations de produits externes proviennent d\'Open Food Facts et d\'Open Products Facts, disponibles sous licence ODbL. Elles ne remplacent jamais les prix, le stock ou l\'historique locaux.',
                      ),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${l.t('Boutique')} : ${c.shop.displayName(c.isArabic)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(l.t('Licences des composants')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Hydra POS',
                      applicationVersion: '1.0.0',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Text(
                l.t(
                  'Bénéfice estimé (coût moyen pondéré) — hors taxes et charges non saisies.',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
