import 'package:flutter/material.dart';

import '../core/business_type.dart';
import '../core/db/app_database.dart';
import '../core/l10n/l10n.dart';
import '../data/models/models.dart';
import '../data/repositories/expense_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/party_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../domain/backup/backup_service.dart';
import '../domain/cash/cash_service.dart';
import '../domain/catalog/catalog_service.dart';
import '../domain/purchases/purchase_service.dart';
import '../domain/reports/report_service.dart';
import '../domain/sales/return_service.dart';
import '../domain/sales/sale_service.dart';
import '../services/import_export_service.dart';
import '../services/invoice_pdf_service.dart';
import '../services/print_service.dart';

/// Owns the long-lived services and the UI preferences (language, shop).
class AppController extends ChangeNotifier {
  AppController._({
    required this.db,
    required this.settings,
    required this.products,
    required this.inventory,
    required this.parties,
    required this.expenses,
    required this.cash,
    required this.reports,
    required this.sales,
    required this.purchases,
    required this.returns,
    required this.catalog,
    required this.backup,
    required this.pdf,
    required this.printer,
    required this.io,
    required this.locale,
    required this.shop,
    required this.themeMode,
    required this.businessType,
    required this.onboardingDone,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final ProductRepository products;
  final InventoryRepository inventory;
  final PartyRepository parties;
  final ExpenseRepository expenses;
  final CashService cash;
  final ReportService reports;
  final SaleService sales;
  final PurchaseService purchases;
  final ReturnService returns;
  final CatalogService catalog;
  final BackupService backup;
  final InvoicePdfService pdf;
  final PrintService printer;
  final ImportExportService io;

  Locale locale;
  Shop shop;
  ThemeMode themeMode;
  BusinessType businessType;
  bool onboardingDone;

  L10n get l10n => L10n(locale);
  bool get isArabic => locale.languageCode == 'ar';

  static Future<AppController> bootstrap({AppDatabase? database}) async {
    final db = database ?? AppDatabase();
    await db.open();
    final settings = SettingsRepository(db);
    await settings.load();
    final products = ProductRepository(db);
    final inventory = InventoryRepository(db);
    final parties = PartyRepository(db);
    final expenses = ExpenseRepository(db);
    final saleService = SaleService(db, settings, inventory);
    final purchaseService = PurchaseService(db, inventory);
    final control = AppController._(
      db: db,
      settings: settings,
      products: products,
      inventory: inventory,
      parties: parties,
      expenses: expenses,
      cash: CashService(db),
      reports: ReportService(db),
      sales: saleService,
      purchases: purchaseService,
      returns: ReturnService(db, inventory),
      catalog: CatalogService(db),
      backup: BackupService(db),
      pdf: InvoicePdfService(),
      printer: PrintService(settings),
      io: ImportExportService(
        productRepository: products,
        inventoryRepository: inventory,
        salesService: saleService,
        purchasesService: purchaseService,
        partiesRepository: parties,
      ),
      locale: Locale(await settings.language()),
      shop: await settings.shop(),
      themeMode: await settings.themeMode(),
      businessType: await settings.businessType(),
      onboardingDone: await settings.onboardingDone(),
    );
    return control;
  }

  Future<void> reloadShop() async {
    shop = await settings.shop();
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    await settings.setLanguage(code);
    locale = Locale(code == 'ar' ? 'ar' : 'fr');
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await settings.setThemeMode(mode);
    themeMode = mode;
    notifyListeners();
  }

  Future<void> setBusinessType(BusinessType type) async {
    await settings.setBusinessType(type);
    businessType = type;
    notifyListeners();
  }

  Future<void> completeOnboarding({
    BusinessType? type,
    String? language,
  }) async {
    if (type != null) {
      await settings.setBusinessType(type);
      businessType = type;
    }
    if (language != null) {
      await settings.setLanguage(language);
      locale = Locale(language == 'ar' ? 'ar' : 'fr');
    }
    await settings.setOnboardingDone(true);
    onboardingDone = true;
    notifyListeners();
  }

  Future<void> markOnboardingDone() => completeOnboarding();

  Future<void> replayOnboarding() async {
    await settings.setOnboardingDone(false);
    onboardingDone = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    await settings.load();
    shop = await settings.shop();
    locale = Locale(await settings.language());
    themeMode = await settings.themeMode();
    businessType = await settings.businessType();
    onboardingDone = await settings.onboardingDone();
    notifyListeners();
  }

  @override
  void dispose() {
    catalog.dispose();
    db.close();
    super.dispose();
  }
}

/// Small indirection so the import/export service can use the same sale and
/// purchase services without a circular constructor.
class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  /// Returns the controller without registering an inherited dependency.
  ///
  /// Screens start loading data from [State.initState], where Flutter forbids
  /// `dependOnInheritedWidgetOfExactType`. The controller instance is stable for
  /// the whole app lifetime, and [HydraApp] already listens to it, so screens do
  /// not need their own dependency here. Use `AppScope.of` in `build` when a
  /// widget should rebuild on controller notifications.
  static AppController read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing above this widget.');
    return scope!.notifier!;
  }
}
