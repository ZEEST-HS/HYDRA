import 'dart:io';

import 'package:hydra_pos/core/db/app_database.dart';
import 'package:hydra_pos/data/repositories/inventory_repository.dart';
import 'package:hydra_pos/data/repositories/party_repository.dart';
import 'package:hydra_pos/data/repositories/product_repository.dart';
import 'package:hydra_pos/data/repositories/settings_repository.dart';
import 'package:hydra_pos/domain/purchases/purchase_service.dart';
import 'package:hydra_pos/domain/sales/return_service.dart';
import 'package:hydra_pos/domain/sales/sale_service.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Shared in-memory database and services for domain tests.
class TestEnv {
  TestEnv._({
    required this.db,
    required this.settings,
    required this.products,
    required this.inventory,
    required this.parties,
    required this.sales,
    required this.purchases,
    required this.returns,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final ProductRepository products;
  final InventoryRepository inventory;
  final PartyRepository parties;
  final SaleService sales;
  final PurchaseService purchases;
  final ReturnService returns;

  static bool _ffiReady = false;

  static void initFfi() {
    if (_ffiReady) return;
    sqfliteFfiInit();
    _ffiReady = true;
  }

  /// Opens a fresh in-memory database. Closing it discards all data.
  static Future<TestEnv> memory() async {
    initFfi();
    final db = AppDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      singleInstance: false,
    );
    await db.open();
    return _build(db);
  }

  /// Opens a database backed by [path] so close/reopen keeps its data.
  static Future<TestEnv> file(String path) async {
    initFfi();
    final db = AppDatabase(
      factory: databaseFactoryFfi,
      path: path,
      singleInstance: false,
    );
    await db.open();
    return _build(db);
  }

  static Future<TestEnv> _build(AppDatabase db) async {
    final settings = SettingsRepository(db);
    await settings.load();
    final products = ProductRepository(db);
    final inventory = InventoryRepository(db);
    final parties = PartyRepository(db);
    final sales = SaleService(db, settings, inventory);
    final purchases = PurchaseService(db, inventory);
    final returns = ReturnService(db, inventory);
    return TestEnv._(
      db: db,
      settings: settings,
      products: products,
      inventory: inventory,
      parties: parties,
      sales: sales,
      purchases: purchases,
      returns: returns,
    );
  }

  Future<void> close() => db.close();
}

/// Creates a unique temporary directory and returns it.
Future<Directory> tempDir([String prefix = 'hydra_pos_test_']) =>
    Directory.systemTemp.createTemp(prefix);

/// Path to a database file inside [dir].
String dbPathIn(Directory dir) => p.join(dir.path, 'hydra_pos.db');

/// Reads an integer setting straight from the database.
Future<int> productStockMilli(TestEnv env, int productId) async {
  final rows = await env.db.db.query(
    'products',
    columns: ['stock_milli'],
    where: 'id = ?',
    whereArgs: [productId],
  );
  return (rows.first['stock_milli'] as num).toInt();
}

/// Reads a product's weighted average cost straight from the database.
Future<int> productCostCentimes(TestEnv env, int productId) async {
  final rows = await env.db.db.query(
    'products',
    columns: ['cost_centimes'],
    where: 'id = ?',
    whereArgs: [productId],
  );
  return (rows.first['cost_centimes'] as num).toInt();
}

/// Reads a customer or supplier balance.
Future<int> partyBalance(TestEnv env, String table, int id) async {
  final rows = await env.db.db.query(
    table,
    columns: ['balance_centimes'],
    where: 'id = ?',
    whereArgs: [id],
  );
  return (rows.first['balance_centimes'] as num).toInt();
}

/// Deletes a temporary directory without failing the test.
Future<void> cleanDir(Directory dir) async {
  try {
    if (await dir.exists()) await dir.delete(recursive: true);
  } catch (_) {}
}
