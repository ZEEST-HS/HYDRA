import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/business_type.dart';
import '../../core/l10n/l10n.dart';

/// First-launch welcome flow: a short presentation followed by the business
/// profile choice. Both values are stored in settings so the flow is shown
/// once. It can be reopened in review mode from the settings screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.replay = false});

  final bool replay;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  BusinessType _type = BusinessType.smallShop;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _type = AppScope.read(context).businessType;
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final c = AppScope.read(context);
    final navigator = Navigator.of(context);
    await c.completeOnboarding(type: _type, language: c.isArabic ? 'ar' : 'fr');
    if (!mounted) return;
    if (widget.replay && navigator.canPop()) navigator.pop();
  }

  Future<void> _toggleLanguage() async {
    final c = AppScope.read(context);
    await c.setLanguage(c.isArabic ? 'fr' : 'ar');
  }

  @override
  Widget build(BuildContext context) {
    final l = AppScope.of(context).l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      if (_step == 1 && !widget.replay)
                        IconButton(
                          tooltip: l.t('Retour'),
                          onPressed: () => setState(() => _step = 0),
                          icon: const Icon(Icons.arrow_back),
                        ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _toggleLanguage,
                        icon: const Icon(Icons.translate, size: 18),
                        label: Text(l.isArabic ? 'Français' : 'العربية'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _step == 0
                      ? _WelcomeStep(
                          l: l,
                          onStart: () => setState(() => _step = 1),
                        )
                      : _BusinessTypeStep(
                          l: l,
                          selected: _type,
                          onSelected: (type) => setState(() => _type = type),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : (_step == 0
                                ? () => setState(() => _step = 1)
                                : _finish),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _step == 0
                                  ? Icons.arrow_forward
                                  : Icons.check_circle_outline,
                            ),
                      label: Text(
                        _step == 0
                            ? l.t('Commencer maintenant')
                            : l.t('Confirmer'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.l, required this.onStart});
  final L10n l;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const features = <String>[
      'Organisation des produits et du stock',
      'Enregistrement rapide des ventes',
      'Suivi des dettes clients et fournisseurs',
      'Surveillance des dates de péremption et réduction des pertes',
      'Connaître les ventes, dépenses et bénéfices estimés',
    ];
    const icons = <IconData>[
      Icons.inventory_2_outlined,
      Icons.point_of_sale_outlined,
      Icons.handshake_outlined,
      Icons.event_busy_outlined,
      Icons.insights_outlined,
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                scheme.primary,
                Color.alphaBlend(
                  scheme.secondary.withValues(alpha: 0.55),
                  scheme.primary,
                ),
              ],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: scheme.onPrimary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l.t('Bienvenue dans Hydra POS'),
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l.t(
                  'Gérez votre boutique facilement et sachez où va votre argent.',
                ),
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 24,
                  height: 1.45,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                l.t(
                  'Organisez vos produits et votre stock, enregistrez vos ventes et achats, suivez les dettes des clients et surveillez les dates de péremption. Tout ce qu\'il faut pour gérer votre boutique dans une seule application.',
                ),
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.9),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < features.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icons[i],
                      size: 21,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l.t(features[i]),
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BusinessTypeStep extends StatelessWidget {
  const _BusinessTypeStep({
    required this.l,
    required this.selected,
    required this.onSelected,
  });

  final L10n l;
  final BusinessType selected;
  final ValueChanged<BusinessType> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      children: [
        Text(
          l.t('Choisissez votre type de commerce'),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          l.t('Vous pourrez changer plus tard dans les réglages.'),
          style: TextStyle(
            fontSize: 13.5,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        _BusinessCard(
          title: l.t('Petit commerce de quartier'),
          subtitle: l.t(
            'Interface simple : ventes rapides, produits, dettes et alertes de péremption.',
          ),
          icon: Icons.storefront_outlined,
          selected: selected == BusinessType.smallShop,
          onTap: () => onSelected(BusinessType.smallShop),
        ),
        const SizedBox(height: 12),
        _BusinessCard(
          title: l.t('Supermarché'),
          subtitle: l.t(
            'Toutes les fonctions avancées : stock, achats, rapports et analyses.',
          ),
          icon: Icons.local_grocery_store_outlined,
          selected: selected == BusinessType.supermarket,
          onTap: () => onSelected(BusinessType.supermarket),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Icon(
              Icons.offline_bolt_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l.t('Les données restent sur cet appareil.'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: selected ? scheme.primary : scheme.surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  size: 26,
                  color: selected ? scheme.onPrimary : scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? scheme.primary : scheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
