import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../core/business_type.dart';
import '../../core/l10n/l10n.dart';
import '../../data/models/models.dart';
import '../../ui/widgets/common.dart';
import '../onboarding/onboarding_screen.dart';
import '../products/category_management_screen.dart';
import 'about_screen.dart';
import 'audit_screen.dart';
import 'backup_screen.dart';
import 'import_export_screen.dart';
import 'printer_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<_SettingsData>? _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_SettingsData> _load() async {
    final c = AppScope.read(context);
    await c.settings.ensureLoaded();
    return _SettingsData(
      shop: await c.settings.shop(),
      stockPolicy: await c.settings.stockPolicy(),
      expiryDays: await c.settings.expiryAlertDays(),
      paperWidth: await c.settings.paperWidth(),
      printerName: await c.settings.printerName(),
      autoPrint: await c.settings.autoPrint(),
    );
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _setLanguage(String code) async {
    await AppScope.of(context).setLanguage(code);
    _reload();
  }

  Future<void> _setTheme(ThemeMode mode) async {
    await AppScope.of(context).setThemeMode(mode);
    _reload();
  }

  Future<void> _setBusinessType(BusinessType type) async {
    await AppScope.of(context).setBusinessType(type);
    _reload();
  }

  Future<void> _replayOnboarding() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const OnboardingScreen(replay: true)),
    );
    if (mounted) _reload();
  }

  Future<void> _setStockPolicy(String value) async {
    await AppScope.of(context).settings.setStockPolicy(value);
    _reload();
  }

  /// Compact chooser used instead of a trailing dropdown so the rows keep
  /// working on narrow phones (and in RTL, where the label can be longer).
  Future<T?> _chooseOption<T>({
    required String title,
    required T current,
    required Map<T, String> options,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final entry in options.entries)
                ListTile(
                  leading: Icon(
                    entry.key == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: entry.key == current
                        ? theme.colorScheme.primary
                        : null,
                  ),
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(sheetContext, entry.key),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  String _themeLabel(ThemeMode mode, L10n l) {
    switch (mode) {
      case ThemeMode.light:
        return l.t('Clair');
      case ThemeMode.dark:
        return l.t('Sombre');
      case ThemeMode.system:
        return l.t('Système');
    }
  }

  Future<void> _editExpiryDays(int current) async {
    final l = AppScope.of(context).l10n;
    final input = await promptText(
      context,
      title: l.t('Péremptions proches'),
      initial: '$current',
      hint: l.t('Nombre de jours'),
    );
    if (input == null || !mounted) return;
    final days = int.tryParse(input);
    if (days == null || days <= 0) {
      showError(context, l.t('Valeur invalide.'));
      return;
    }
    await AppScope.of(context).settings.setExpiryAlertDays(days);
    _reload();
  }

  Future<void> _editShop(Shop shop) async {
    final updated = await showDialog<Shop>(
      context: context,
      builder: (_) => _ShopDialog(shop: shop),
    );
    if (updated == null || !mounted) return;
    try {
      final c = AppScope.of(context);
      await c.settings.saveShop(updated);
      await c.reloadShop();
      if (!mounted) return;
      showInfo(context, c.l10n.t('Boutique enregistrée'));
      _reload();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.t('Réglages'))),
      body: FutureBuilder<_SettingsData>(
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
    );
  }

  Widget _content(_SettingsData data) {
    final c = AppScope.of(context);
    final l = L10n.of(context);
    return PageBody(
      maxWidth: 820,
      child: ListView(
        children: [
          SectionTitle(l.t('Général')),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(l.t('Langue')),
                  subtitle: Text(
                    c.locale.languageCode == 'ar'
                        ? l.t('Arabe')
                        : l.t('Français'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await _chooseOption<String>(
                      title: l.t('Langue'),
                      current: c.locale.languageCode == 'ar' ? 'ar' : 'fr',
                      options: {'fr': l.t('Français'), 'ar': l.t('Arabe')},
                    );
                    if (value != null) await _setLanguage(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.inventory_outlined),
                  title: Text(l.t('Politique de stock')),
                  subtitle: Text(_stockPolicyLabel(data.stockPolicy, l)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await _chooseOption<String>(
                      title: l.t('Politique de stock'),
                      current: data.stockPolicy,
                      options: {
                        'block': l.t('Bloquer la vente'),
                        'confirm': l.t('Demander confirmation'),
                        'allow': l.t('Autoriser'),
                      },
                    );
                    if (value != null) await _setStockPolicy(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.event_busy_outlined),
                  title: Text(l.t('Péremptions proches')),
                  subtitle: Text(
                    '${data.expiryDays} ${l.t('jours avant alerte')}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editExpiryDays(data.expiryDays),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    c.themeMode == ThemeMode.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                  title: Text(l.t('Thème')),
                  subtitle: Text(_themeLabel(c.themeMode, l)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await _chooseOption<ThemeMode>(
                      title: l.t('Thème'),
                      current: c.themeMode,
                      options: {
                        ThemeMode.light: l.t('Clair'),
                        ThemeMode.dark: l.t('Sombre'),
                        ThemeMode.system: l.t('Système'),
                      },
                    );
                    if (value != null) await _setTheme(value);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    c.businessType == BusinessType.smallShop
                        ? Icons.storefront_outlined
                        : Icons.local_grocery_store_outlined,
                  ),
                  title: Text(l.t('Type de commerce')),
                  subtitle: Text(
                    c.businessType == BusinessType.smallShop
                        ? l.t('Petit commerce de quartier')
                        : l.t('Supermarché'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await _chooseOption<BusinessType>(
                      title: l.t('Type de commerce'),
                      current: c.businessType,
                      options: {
                        BusinessType.smallShop: l.t('Petit commerce'),
                        BusinessType.supermarket: l.t('Supermarché'),
                      },
                    );
                    if (value != null) await _setBusinessType(value);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(l.t('Produits')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(l.t('Gérer les catégories')),
              subtitle: Text(l.t('Sous-catégories')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const CategoryManagementScreen()),
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(l.t('Boutique')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(data.shop.displayName(c.isArabic)),
              subtitle: Text(
                [
                  if (data.shop.address?.trim().isNotEmpty == true)
                    data.shop.address!,
                  if (data.shop.phone?.trim().isNotEmpty == true)
                    data.shop.phone!,
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _editShop(data.shop),
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(l.t('Imprimante')),
          Card(
            child: ListTile(
              leading: const Icon(Icons.print_outlined),
              title: Text(l.t('Imprimante Bluetooth')),
              subtitle: Text(
                '${data.printerName.isEmpty ? l.t('Imprimante non connectée') : data.printerName}'
                ' · ${l.t('Format du papier')} ${data.paperWidth} mm'
                '${data.autoPrint ? ' · ${l.t('Impression automatique')}' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _open(const PrinterScreen()),
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(l.t('Données')),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: Text(l.t('Sauvegarde')),
                  subtitle: Text(l.t('Sauvegardes locales')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(const BackupScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.import_export),
                  title: Text(l.t('Importer / Exporter')),
                  subtitle: Text(l.t('Importer un fichier CSV ou Excel')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(const ImportExportScreen()),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(l.t('Journal d\'audit')),
                  subtitle: Text(
                    l.t('Les modifications de prix et de stock sont tracées.'),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(const AuditScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionTitle(l.t('Aide')),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.waving_hand_outlined),
                  title: Text(l.t('Revoir l\'accueil')),
                  subtitle: Text(
                    l.t(
                      'Revoir la présentation et le choix du type de commerce.',
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _replayOnboarding,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l.t('À propos')),
                  subtitle: Text('${l.t('Version')} 1.0.0'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(const AboutScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _stockPolicyLabel(String value, L10n l) {
    switch (value) {
      case 'allow':
        return l.t('Autoriser');
      case 'confirm':
        return l.t('Demander confirmation');
      default:
        return l.t('Bloquer la vente');
    }
  }
}

class _SettingsData {
  const _SettingsData({
    required this.shop,
    required this.stockPolicy,
    required this.expiryDays,
    required this.paperWidth,
    required this.printerName,
    required this.autoPrint,
  });

  final Shop shop;
  final String stockPolicy;
  final int expiryDays;
  final int paperWidth;
  final String printerName;
  final bool autoPrint;
}

class _ShopDialog extends StatefulWidget {
  const _ShopDialog({required this.shop});
  final Shop shop;

  @override
  State<_ShopDialog> createState() => _ShopDialogState();
}

class _ShopDialogState extends State<_ShopDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _nameAr;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _taxId;
  late final TextEditingController _footer;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.shop.name);
    _nameAr = TextEditingController(text: widget.shop.nameAr);
    _address = TextEditingController(text: widget.shop.address);
    _phone = TextEditingController(text: widget.shop.phone);
    _email = TextEditingController(text: widget.shop.email);
    _taxId = TextEditingController(text: widget.shop.taxId);
    _footer = TextEditingController(text: widget.shop.footer);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _nameAr,
      _address,
      _phone,
      _email,
      _taxId,
      _footer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    Navigator.pop(
      context,
      widget.shop.copyWith(
        name: _name.text.trim(),
        nameAr: _optional(_nameAr),
        address: _optional(_address),
        phone: _optional(_phone),
        email: _optional(_email),
        taxId: _optional(_taxId),
        footer: _optional(_footer),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = L10n.of(context);
    return AlertDialog(
      title: Text(l.t('Paramètres du magasin')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: InputDecoration(labelText: l.t('Nom du magasin')),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? l.t('Champ requis')
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _nameAr,
                  textDirection: TextDirection.rtl,
                  decoration: InputDecoration(labelText: l.t('Nom en arabe')),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: l.t('Adresse du magasin'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(labelText: l.t('Téléphone')),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(labelText: l.t('E-mail')),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _taxId,
                  decoration: InputDecoration(
                    labelText: l.t('Identifiant fiscal'),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _footer,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: l.t('Pied de facture'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.t('Annuler')),
        ),
        FilledButton(onPressed: _submit, child: Text(l.t('Enregistrer'))),
      ],
    );
  }
}
