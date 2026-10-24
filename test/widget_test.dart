import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/app/app.dart';
import 'package:hydra_pos/app/app_controller.dart';
import 'package:hydra_pos/core/business_type.dart';
import 'package:hydra_pos/core/db/app_database.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/ui/theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/test_env.dart';

/// Opens the database and controller outside the fake-async widget zone.
///
/// SQLite (through `sqflite_common_ffi`) talks over real receive ports. Awaiting
/// it directly inside `testWidgets` deadlocks because the fake clock never
/// completes those futures, so every call site goes through `tester.runAsync`.
Future<AppController> _bootstrap({
  String language = 'fr',
  BusinessType businessType = BusinessType.supermarket,
  bool onboardingDone = true,
}) async {
  TestEnv.initFfi();
  final db = AppDatabase(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    singleInstance: false,
  );
  await db.open();

  Future<void> setSetting(String key, String value) async {
    final rows = await db.db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (rows.isEmpty) {
      await db.db.insert('settings', {'key': key, 'value': value});
    } else {
      await db.db.update(
        'settings',
        {'value': value},
        where: 'key = ?',
        whereArgs: [key],
      );
    }
  }

  await setSetting('language', language);
  await setSetting('business_type', businessType.code);
  await setSetting('onboarding_done', onboardingDone ? '1' : '0');
  return AppController.bootstrap(database: db);
}

/// Lets pending SQLite futures complete, then renders their results.
///
/// `pumpAndSettle` cannot be used while a screen shows a progress indicator:
/// the indicator animates forever if database I/O has not completed yet.
Future<void> _pumpWithIo(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home shell renders French navigation and dashboard', (
    tester,
  ) async {
    final controller = await tester.runAsync(_bootstrap);
    addTearDown(controller!.dispose);

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Tableau de bord'), findsWidgets);
    expect(find.text('Caisse'), findsWidgets);
    expect(find.text('Produits'), findsWidgets);
    expect(find.text('Ventes'), findsWidgets);
    expect(find.text('Plus'), findsWidgets);
    // Default shop name from the seeded settings.
    expect(find.text('Ma boutique'), findsOneWidget);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('POS tab opens with its scan/search field', (tester) async {
    final controller = await tester.runAsync(_bootstrap);
    addTearDown(controller!.dispose);
    await tester.runAsync(
      () => controller.products.create(
        const Product(
          name: 'Lait Centrale 1L',
          barcode: '6111245100059',
          priceCentimes: 850,
          costCentimes: 720,
          stockMilli: 12000,
        ),
      ),
    );

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    await tester.tap(find.byIcon(Icons.point_of_sale_outlined));
    await _pumpWithIo(tester);

    expect(find.text('Saisir ou scanner un code-barres'), findsOneWidget);
    expect(find.text('Lait Centrale 1L'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Arabic locale switches navigation and text direction', (
    tester,
  ) async {
    final controller = await tester.runAsync(() => _bootstrap(language: 'ar'));
    addTearDown(controller!.dispose);

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    expect(controller.isArabic, isTrue);
    expect(find.text('البيع'), findsWidgets);
    expect(find.text('المنتجات'), findsWidgets);
    final directionality = tester.widget<Directionality>(
      find.byType(Directionality).first,
    );
    expect(directionality.textDirection, TextDirection.rtl);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('first launch shows onboarding and saves the chosen profile', (
    tester,
  ) async {
    final controller = await tester.runAsync(
      () => _bootstrap(
        language: 'ar',
        businessType: BusinessType.smallShop,
        onboardingDone: false,
      ),
    );
    addTearDown(controller!.dispose);

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    expect(controller.onboardingDone, isFalse);
    expect(find.text('مرحباً بك في Hydra POS'), findsOneWidget);
    expect(find.text('ابدأ الآن'), findsOneWidget);

    await tester.tap(find.text('ابدأ الآن'));
    await _pumpWithIo(tester);
    expect(find.text('اختر نوع محلك'), findsOneWidget);

    await tester.tap(find.text('سوبر ماركت'));
    await _pumpWithIo(tester);
    await tester.tap(find.text('تأكيد'));
    await _pumpWithIo(tester);

    expect(controller.onboardingDone, isTrue);
    expect(controller.businessType, BusinessType.supermarket);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('لوحة التحكم'), findsWidgets);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('small shop navigation stays simple', (tester) async {
    final controller = await tester.runAsync(
      () => _bootstrap(businessType: BusinessType.smallShop),
    );
    addTearDown(controller!.dispose);

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Caisse'), findsWidgets);
    expect(find.text('Produits'), findsWidgets);
    expect(find.text('Dettes'), findsWidgets);
    expect(find.text('Plus'), findsWidgets);
    // The dashboard and sales tabs are not part of the simple profile.
    expect(find.text('Tableau de bord'), findsNothing);
    expect(find.text('Ventes'), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Arabic dark layout fits a narrow phone without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await tester.runAsync(
      () => _bootstrap(language: 'ar', businessType: BusinessType.smallShop),
    );
    addTearDown(controller!.dispose);
    await tester.runAsync(() => controller.setThemeMode(ThemeMode.dark));

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    // The active palette must switch to the high-contrast dark variants.
    expect(AppTheme.danger, const Color(0xFFF87171));
    expect(tester.takeException(), isNull);

    for (final icon in [
      Icons.inventory_2_outlined,
      Icons.handshake_outlined,
      Icons.grid_view_outlined,
    ]) {
      await tester.tap(find.byIcon(icon).first);
      await _pumpWithIo(tester);
      expect(tester.takeException(), isNull, reason: '$icon');
    }

    // Open the settings screen with its dropdown rows on the same narrow width.
    await tester.tap(find.byIcon(Icons.inventory_outlined).first);
    await _pumpWithIo(tester);
    expect(tester.takeException(), isNull, reason: 'inventory');
    Navigator.of(tester.element(find.byType(BackButton))).pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull, reason: 'back');

    await tester.tap(find.byIcon(Icons.settings_outlined).first);
    await _pumpWithIo(tester);
    expect(find.byType(AppBar), findsWidgets);
    expect(tester.takeException(), isNull, reason: 'settings');
  }, timeout: const Timeout(Duration(seconds: 60)));

  testWidgets('Arabic onboarding fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await tester.runAsync(
      () => _bootstrap(
        language: 'ar',
        businessType: BusinessType.smallShop,
        onboardingDone: false,
      ),
    );
    addTearDown(controller!.dispose);

    await tester.pumpWidget(HydraApp(controller: controller));
    await _pumpWithIo(tester);

    expect(find.text('مرحباً بك في Hydra POS'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ابدأ الآن'));
    await _pumpWithIo(tester);
    expect(find.text('اختر نوع محلك'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 60)));
}
