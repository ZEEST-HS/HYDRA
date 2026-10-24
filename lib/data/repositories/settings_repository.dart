import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/business_type.dart';
import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../models/models.dart';

class SettingsRepository {
  SettingsRepository(this.appDb);
  final AppDatabase appDb;

  final Map<String, String> _cache = {};
  bool _loaded = false;

  Future<void> load() async {
    final rows = await appDb.db.query('settings');
    _cache
      ..clear()
      ..addEntries(
        rows.map((r) => MapEntry(r['key'] as String, r['value'] as String)),
      );
    _loaded = true;
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  String getString(String key, {String fallback = ''}) =>
      _cache[key] ?? fallback;

  bool getBool(String key, {bool fallback = false}) =>
      (_cache[key] ?? (fallback ? '1' : '0')) == '1';

  int getInt(String key, {int fallback = 0}) =>
      int.tryParse(_cache[key] ?? '') ?? fallback;

  Future<void> set(String key, String value) async {
    await appDb.db.insert('settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _cache[key] = value;
  }

  Future<void> setBool(String key, bool value) => set(key, value ? '1' : '0');

  Future<String> language() async {
    await ensureLoaded();
    final value = getString('language', fallback: 'ar');
    return value == 'fr' ? 'fr' : 'ar';
  }

  Future<void> setLanguage(String value) =>
      set('language', value == 'ar' ? 'ar' : 'fr');

  Future<bool> onboardingDone() async {
    await ensureLoaded();
    return getBool('onboarding_done');
  }

  Future<void> setOnboardingDone(bool value) =>
      setBool('onboarding_done', value);

  Future<ThemeMode> themeMode() async {
    await ensureLoaded();
    switch (getString('theme_mode', fallback: 'system')) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) => set('theme_mode', switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  });

  Future<BusinessType> businessType() async {
    await ensureLoaded();
    return BusinessType.fromCode(getString('business_type', fallback: 'small'));
  }

  Future<void> setBusinessType(BusinessType type) =>
      set('business_type', type.code);

  Future<String> stockPolicy() async {
    await ensureLoaded();
    final value = getString('stock_policy', fallback: 'block');
    return ['block', 'confirm', 'allow'].contains(value) ? value : 'block';
  }

  Future<void> setStockPolicy(String value) => set('stock_policy', value);

  Future<bool> autoPrint() async {
    await ensureLoaded();
    return getBool('auto_print');
  }

  Future<int> paperWidth() async {
    await ensureLoaded();
    final value = getInt('paper_width', fallback: 58);
    return value == 80 ? 80 : 58;
  }

  Future<bool> catalogEnabled() async {
    await ensureLoaded();
    return getBool('catalog_enabled', fallback: true);
  }

  Future<int> expiryAlertDays() async {
    await ensureLoaded();
    return getInt('expiry_alert_days', fallback: 30);
  }

  Future<void> setExpiryAlertDays(int days) =>
      set('expiry_alert_days', days.clamp(1, 365).toString());

  Future<String> printerMac() async {
    await ensureLoaded();
    return getString('printer_mac');
  }

  Future<String> printerName() async {
    await ensureLoaded();
    return getString('printer_name');
  }

  Future<void> savePrinter({required String mac, required String name}) async {
    await set('printer_mac', mac);
    await set('printer_name', name);
  }

  Future<Shop> shop() async {
    final rows = await appDb.db.query('shop', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      return const Shop(id: 1, name: 'Ma boutique');
    }
    return Shop.fromMap(rows.first);
  }

  Future<void> saveShop(Shop shop) async {
    await appDb.db.update('shop', {
      'name': shop.name.trim(),
      'name_ar': shop.nameAr?.trim(),
      'address': shop.address?.trim(),
      'phone': shop.phone?.trim(),
      'email': shop.email?.trim(),
      'tax_id': shop.taxId?.trim(),
      'footer': shop.footer?.trim(),
      'logo_path': shop.logoPath,
      'updated_at': Dates.nowMillis(),
    }, where: 'id = 1');
  }
}
