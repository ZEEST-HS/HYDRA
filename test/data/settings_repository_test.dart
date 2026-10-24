import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/business_type.dart';
import 'package:hydra_pos/data/repositories/settings_repository.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;

  setUp(() async {
    env = await TestEnv.memory();
  });

  tearDown(() async {
    await env.close();
  });

  test(
    'a fresh install starts in Arabic with system theme and simple mode',
    () async {
      expect(await env.settings.language(), 'ar');
      expect(await env.settings.themeMode(), ThemeMode.system);
      expect(await env.settings.businessType(), BusinessType.smallShop);
      expect(await env.settings.onboardingDone(), isFalse);
      expect(await env.settings.expiryAlertDays(), 30);
    },
  );

  test('appearance, business profile and onboarding persist', () async {
    await env.settings.setThemeMode(ThemeMode.dark);
    await env.settings.setBusinessType(BusinessType.supermarket);
    await env.settings.setOnboardingDone(true);
    await env.settings.setLanguage('fr');
    await env.settings.setExpiryAlertDays(45);

    // Reload from the database as the app does on the next launch.
    final reloaded = SettingsRepository(env.db);
    await reloaded.load();
    expect(await reloaded.themeMode(), ThemeMode.dark);
    expect(await reloaded.businessType(), BusinessType.supermarket);
    expect(await reloaded.onboardingDone(), isTrue);
    expect(await reloaded.language(), 'fr');
    expect(await reloaded.expiryAlertDays(), 45);
  });

  test('unknown stored values fall back to safe defaults', () async {
    await env.db.db.update(
      'settings',
      {'value': 'unknown'},
      where: 'key = ?',
      whereArgs: ['theme_mode'],
    );
    await env.db.db.update(
      'settings',
      {'value': 'unknown'},
      where: 'key = ?',
      whereArgs: ['business_type'],
    );
    await env.db.db.update(
      'settings',
      {'value': 'unknown'},
      where: 'key = ?',
      whereArgs: ['language'],
    );
    final reloaded = SettingsRepository(env.db);
    await reloaded.load();
    expect(await reloaded.themeMode(), ThemeMode.system);
    expect(await reloaded.businessType(), BusinessType.smallShop);
    expect(await reloaded.language(), 'ar');
  });
}
