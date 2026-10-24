import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../classifications.dart';
import '../dates.dart';

/// Owns the SQLite connection, schema and migrations.
///
/// The database is the only source of truth for stock, money and balances.
/// All mutations that affect more than one table run in [transaction].
class AppDatabase {
  AppDatabase({
    DatabaseFactory? factory,
    String? path,
    this.singleInstance = true,
  }) : _factory = factory ?? databaseFactory,
       _explicitPath = path;
  static const int schemaVersion = 3;
  static const String fileName = 'hydra_pos.db';

  final DatabaseFactory _factory;
  final String? _explicitPath;
  final bool singleInstance;

  Database? _db;
  String? _path;
  bool _opening = false;

  Database get db {
    final value = _db;
    if (value == null || !value.isOpen) {
      throw StateError('Database is not open. Call open() first.');
    }
    return value;
  }

  bool get isOpen => _db?.isOpen ?? false;
  String? get path => _path;

  Future<String> resolvePath() async {
    final explicit = _explicitPath;
    if (explicit != null) {
      _path = explicit;
      return explicit;
    }
    if (_path != null) return _path!;
    final base = await getDatabasesPath();
    _path = p.join(base, fileName);
    return _path!;
  }

  Future<Database> open({bool readOnly = false}) async {
    if (isOpen) return _db!;
    if (_opening) {
      // Wait for an in-flight open.
      while (_opening) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      if (isOpen) return _db!;
    }
    _opening = true;
    try {
      final dbPath = await resolvePath();
      if (!readOnly && dbPath != inMemoryDatabasePath) {
        await Directory(p.dirname(dbPath)).create(recursive: true);
      }
      _db = await _factory.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          readOnly: readOnly,
          singleInstance: singleInstance && dbPath != inMemoryDatabasePath,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
          onCreate: (db, version) async {
            await createBaseSchema(db);
            await migrateV1ToV2(db);
            await migrateV2ToV3(db, onboardExistingData: false);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            for (var v = oldVersion; v < newVersion; v++) {
              await migrate(db, v, v + 1);
            }
          },
          onOpen: (db) async {
            // WAL is unsupported for in-memory databases. Ignore failures on
            // platforms that do not support it.
            try {
              await db.rawQuery('PRAGMA journal_mode = WAL');
            } catch (_) {}
            try {
              await db.execute('PRAGMA synchronous = NORMAL');
            } catch (_) {}
          },
        ),
      );
      if (!readOnly) await _seedDefaults(_db!);
      return _db!;
    } finally {
      _opening = false;
    }
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null && db.isOpen) {
      await db.close();
    }
  }

  /// Closes and reopens the database, used after backup restore and in tests.
  Future<void> reopen() async {
    await close();
    await open();
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) {
    return db.transaction<T>(action);
  }

  Future<void> checkpoint() async {
    if (!isOpen) return;
    try {
      await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
    } catch (_) {}
  }

  Future<int> count(String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return (rows.first['c'] as num).toInt();
  }

  /// Runs one migration step. Exposed for migration tests.
  static Future<void> migrate(DatabaseExecutor db, int from, int to) async {
    if (from == 1 && to == 2) {
      await migrateV1ToV2(db);
      return;
    }
    if (from == 2 && to == 3) {
      await migrateV2ToV3(db);
      return;
    }
    throw StateError('No migration from schema $from to $to');
  }

  static Future<void> createBaseSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE shop (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        name TEXT NOT NULL,
        name_ar TEXT,
        address TEXT,
        phone TEXT,
        email TEXT,
        tax_id TEXT,
        footer TEXT,
        logo_path TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name_fr TEXT NOT NULL,
        name_ar TEXT,
        division TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_system INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        note TEXT,
        balance_centimes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        note TEXT,
        balance_centimes INTEGER NOT NULL DEFAULT 0,
        credit_limit_centimes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        name TEXT NOT NULL,
        name_ar TEXT,
        brand TEXT,
        category_id INTEGER REFERENCES categories(id) ON DELETE SET NULL,
        package_size TEXT,
        base_unit TEXT NOT NULL DEFAULT 'piece',
        cost_centimes INTEGER NOT NULL DEFAULT 0,
        price_centimes INTEGER NOT NULL DEFAULT 0,
        stock_milli INTEGER NOT NULL DEFAULT 0,
        min_stock_milli INTEGER NOT NULL DEFAULT 0,
        supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
        image_url TEXT,
        image_path TEXT,
        catalog_source TEXT,
        catalog_updated_at INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        deleted_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE product_units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        name_ar TEXT,
        factor_milli INTEGER NOT NULL,
        price_centimes INTEGER,
        cost_centimes INTEGER,
        is_default_sale INTEGER NOT NULL DEFAULT 0,
        is_default_purchase INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        purchase_id INTEGER,
        batch_no TEXT,
        expiry_date TEXT,
        qty_received_milli INTEGER NOT NULL,
        qty_remaining_milli INTEGER NOT NULL,
        unit_cost_centimes INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_no TEXT NOT NULL UNIQUE,
        customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
        customer_name TEXT,
        subtotal_centimes INTEGER NOT NULL,
        discount_centimes INTEGER NOT NULL,
        total_centimes INTEGER NOT NULL,
        paid_centimes INTEGER NOT NULL,
        due_centimes INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        business_date TEXT NOT NULL,
        idempotency_key TEXT UNIQUE,
        created_at INTEGER NOT NULL,
        voided_at INTEGER,
        void_reason TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE CASCADE,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        barcode TEXT,
        unit_name TEXT NOT NULL DEFAULT '',
        factor_milli INTEGER NOT NULL DEFAULT 1000,
        qty_milli INTEGER NOT NULL,
        unit_price_centimes INTEGER NOT NULL,
        unit_cost_centimes INTEGER NOT NULL DEFAULT 0,
        line_discount_centimes INTEGER NOT NULL DEFAULT 0,
        line_total_centimes INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Which stock batches were consumed by each sale line. Used to restore the
    // same expiry batches on returns and cancellations (FEFO traceability).
    await db.execute('''
      CREATE TABLE sale_line_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_line_id INTEGER NOT NULL REFERENCES sale_lines(id) ON DELETE CASCADE,
        batch_id INTEGER NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
        qty_milli INTEGER NOT NULL,
        returned_milli INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE purchases (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ref_no TEXT NOT NULL UNIQUE,
        supplier_id INTEGER REFERENCES suppliers(id) ON DELETE SET NULL,
        supplier_name TEXT,
        subtotal_centimes INTEGER NOT NULL,
        discount_centimes INTEGER NOT NULL,
        total_centimes INTEGER NOT NULL,
        paid_centimes INTEGER NOT NULL,
        due_centimes INTEGER NOT NULL,
        payment_method TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'completed',
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        voided_at INTEGER,
        void_reason TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        purchase_id INTEGER NOT NULL REFERENCES purchases(id) ON DELETE CASCADE,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        unit_name TEXT NOT NULL DEFAULT '',
        factor_milli INTEGER NOT NULL DEFAULT 1000,
        qty_milli INTEGER NOT NULL,
        unit_cost_centimes INTEGER NOT NULL,
        line_total_centimes INTEGER NOT NULL,
        expiry_date TEXT,
        batch_no TEXT,
        batch_id INTEGER REFERENCES batches(id) ON DELETE SET NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_returns (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_no TEXT NOT NULL UNIQUE,
        sale_id INTEGER NOT NULL REFERENCES sales(id) ON DELETE RESTRICT,
        customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
        total_centimes INTEGER NOT NULL,
        refund_method TEXT NOT NULL,
        note TEXT,
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE return_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        return_id INTEGER NOT NULL REFERENCES sale_returns(id) ON DELETE CASCADE,
        sale_line_id INTEGER,
        product_id INTEGER,
        product_name TEXT NOT NULL,
        qty_milli INTEGER NOT NULL,
        unit_price_centimes INTEGER NOT NULL,
        unit_cost_centimes INTEGER NOT NULL DEFAULT 0,
        line_total_centimes INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_type TEXT NOT NULL,
        party_id INTEGER NOT NULL,
        direction TEXT NOT NULL,
        amount_centimes INTEGER NOT NULL,
        method TEXT NOT NULL,
        reference TEXT,
        note TEXT,
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        sale_id INTEGER,
        purchase_id INTEGER,
        return_id INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT NOT NULL,
        amount_centimes INTEGER NOT NULL,
        method TEXT NOT NULL,
        note TEXT,
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE cash_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        opening_cash_centimes INTEGER NOT NULL DEFAULT 0,
        expected_cash_centimes INTEGER,
        counted_cash_centimes INTEGER,
        difference_centimes INTEGER,
        note TEXT,
        status TEXT NOT NULL DEFAULT 'open'
      )
    ''');

    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        qty_delta_milli INTEGER NOT NULL,
        unit_cost_centimes INTEGER NOT NULL DEFAULT 0,
        ref_type TEXT,
        ref_id INTEGER,
        reason TEXT,
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE ledger_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        party_type TEXT NOT NULL,
        party_id INTEGER NOT NULL,
        entry_type TEXT NOT NULL,
        amount_centimes INTEGER NOT NULL,
        ref_type TEXT,
        ref_id INTEGER,
        note TEXT,
        business_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        action TEXT NOT NULL,
        entity TEXT NOT NULL,
        entity_id INTEGER,
        details_json TEXT,
        reason TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sequences (
        name TEXT PRIMARY KEY,
        next_value INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE catalog_cache (
        barcode TEXT PRIMARY KEY,
        source TEXT NOT NULL,
        found INTEGER NOT NULL,
        payload_json TEXT,
        fetched_at INTEGER NOT NULL
      )
    ''');

    // Indexes. Unique barcode only among active, non-deleted rows so a
    // returned product can be registered again later.
    await db.execute(
      'CREATE UNIQUE INDEX idx_products_barcode ON products(barcode) '
      'WHERE barcode IS NOT NULL AND barcode <> \'\' AND deleted_at IS NULL',
    );
    await db.execute('CREATE INDEX idx_products_name ON products(name)');
    await db.execute('CREATE INDEX idx_products_active ON products(is_active)');
    await db.execute(
      'CREATE INDEX idx_products_stock ON products(stock_milli)',
    );
    await db.execute(
      'CREATE INDEX idx_products_supplier ON products(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX idx_units_product ON product_units(product_id)',
    );
    await db.execute('CREATE INDEX idx_batches_product ON batches(product_id)');
    await db.execute('CREATE INDEX idx_batches_expiry ON batches(expiry_date)');
    await db.execute(
      'CREATE INDEX idx_sale_line_batches_line ON sale_line_batches(sale_line_id)',
    );
    await db.execute(
      'CREATE INDEX idx_sale_line_batches_batch ON sale_line_batches(batch_id)',
    );
    await db.execute('CREATE INDEX idx_sales_date ON sales(business_date)');
    await db.execute('CREATE INDEX idx_sales_customer ON sales(customer_id)');
    await db.execute('CREATE INDEX idx_sales_status ON sales(status)');
    await db.execute('CREATE INDEX idx_sale_lines_sale ON sale_lines(sale_id)');
    await db.execute(
      'CREATE INDEX idx_sale_lines_product ON sale_lines(product_id)',
    );
    await db.execute(
      'CREATE INDEX idx_purchases_date ON purchases(business_date)',
    );
    await db.execute(
      'CREATE INDEX idx_purchases_supplier ON purchases(supplier_id)',
    );
    await db.execute(
      'CREATE INDEX idx_purchase_lines_purchase ON purchase_lines(purchase_id)',
    );
    await db.execute(
      'CREATE INDEX idx_payments_party ON payments(party_type, party_id)',
    );
    await db.execute(
      'CREATE INDEX idx_payments_date ON payments(business_date)',
    );
    await db.execute(
      'CREATE INDEX idx_expenses_date ON expenses(business_date)',
    );
    await db.execute(
      'CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)',
    );
    await db.execute(
      'CREATE INDEX idx_stock_movements_date ON stock_movements(business_date)',
    );
    await db.execute(
      'CREATE INDEX idx_ledger_party ON ledger_entries(party_type, party_id)',
    );
    await db.execute('CREATE INDEX idx_returns_sale ON sale_returns(sale_id)');
    await db.execute('CREATE INDEX idx_audit_created ON audit_log(created_at)');
  }

  /// Schema v2 adds free-form notes to products, sales and purchases.
  static Future<void> migrateV1ToV2(DatabaseExecutor db) async {
    await _addColumnIfMissing(db, 'products', 'notes', 'TEXT');
    await _addColumnIfMissing(db, 'sales', 'note', 'TEXT');
    await _addColumnIfMissing(db, 'purchases', 'note', 'TEXT');
  }

  /// Schema v3 introduces the two product divisions, editable subcategories,
  /// batch/lot metadata on purchase lines and the sale-line batch allocations
  /// needed to restore the original expiry batches on returns.
  ///
  /// Existing categories, products and history are preserved. Legacy
  /// categories are mapped to a division when the mapping is unambiguous and
  /// are otherwise left unclassified for the user to review.
  static Future<void> migrateV2ToV3(
    DatabaseExecutor db, {
    bool onboardExistingData = true,
  }) async {
    await _addColumnIfMissing(db, 'categories', 'division', 'TEXT');
    await _addColumnIfMissing(
      db,
      'categories',
      'sort_order',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'categories',
      'is_system',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(db, 'purchase_lines', 'batch_no', 'TEXT');
    await _addColumnIfMissing(db, 'purchase_lines', 'batch_id', 'INTEGER');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_line_batches (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sale_line_id INTEGER NOT NULL REFERENCES sale_lines(id) ON DELETE CASCADE,
        batch_id INTEGER NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
        qty_milli INTEGER NOT NULL,
        returned_milli INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_line_batches_line '
      'ON sale_line_batches(sale_line_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sale_line_batches_batch '
      'ON sale_line_batches(batch_id)',
    );

    await _classifyLegacyCategories(db);
    await seedPredefinedCategories(db);

    // Existing shops already know the app: never show onboarding after an
    // update, unless the user deliberately resets it.
    if (onboardExistingData) {
      final dataCount =
          Sqflite.firstIntValue(
            await db.rawQuery('''
              SELECT
                (SELECT COUNT(*) FROM products) +
                (SELECT COUNT(*) FROM sales) +
                (SELECT COUNT(*) FROM purchases)
            '''),
          ) ??
          0;
      if (dataCount > 0) {
        final updated = await db.update(
          'settings',
          {'value': '1'},
          where: 'key = ? AND value = ?',
          whereArgs: ['onboarding_done', '0'],
        );
        if (updated == 0) {
          await db.insert('settings', {
            'key': 'onboarding_done',
            'value': '1',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    }
  }

  /// Maps the flat v2 categories onto the two divisions when the legacy name is
  /// known. Unknown names stay `NULL` so the user classifies them explicitly.
  static Future<void> _classifyLegacyCategories(DatabaseExecutor db) async {
    const food = {
      'alimentation',
      'boissons',
      'fruits et légumes',
      'fruits et legumes',
      'produits laitiers',
    };
    const nonFood = {'hygiène', 'hygiene', 'entretien'};
    final rows = await db.query(
      'categories',
      columns: ['id', 'name_fr', 'division'],
    );
    for (final row in rows) {
      if (row['division'] != null) continue;
      final name = (row['name_fr'] as String? ?? '').trim().toLowerCase();
      final division = food.contains(name)
          ? ProductDivision.food.code
          : nonFood.contains(name)
          ? ProductDivision.nonFood.code
          : null;
      if (division == null) continue;
      await db.update(
        'categories',
        {'division': division},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  /// Inserts every predefined subcategory that does not exist yet and marks
  /// matching legacy rows as system categories. Safe to run on every open.
  static Future<void> seedPredefinedCategories(DatabaseExecutor db) async {
    final now = Dates.nowMillis();
    final rows = await db.query(
      'categories',
      columns: ['id', 'name_fr', 'name_ar', 'division', 'is_system'],
    );
    final byName = <String, Map<String, Object?>>{};
    for (final row in rows) {
      final name = (row['name_fr'] as String? ?? '').trim().toLowerCase();
      if (name.isEmpty) continue;
      byName.putIfAbsent(name, () => row);
    }
    var order = 0;
    for (final division in ProductDivision.values) {
      for (final seed in subcategoriesFor(division)) {
        order += 1;
        final existing = byName[seed.nameFr.toLowerCase()];
        if (existing == null) {
          await db.insert('categories', {
            'name_fr': seed.nameFr,
            'name_ar': seed.nameAr,
            'division': division.code,
            'sort_order': order,
            'is_system': 1,
            'created_at': now,
          });
          continue;
        }
        final updates = <String, Object?>{
          'division': division.code,
          'sort_order': order,
          'is_system': 1,
        };
        if ((existing['name_ar'] as String? ?? '').trim().isEmpty) {
          updates['name_ar'] = seed.nameAr;
        }
        await db.update(
          'categories',
          updates,
          where: 'id = ?',
          whereArgs: [existing['id']],
        );
      }
    }
  }

  static Future<void> _addColumnIfMissing(
    DatabaseExecutor db,
    String table,
    String column,
    String type,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((row) => row['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
    }
  }

  Future<void> _seedDefaults(Database db) async {
    final now = Dates.nowMillis();

    final shopCount =
        Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM shop')) ??
        0;
    if (shopCount == 0) {
      await db.insert('shop', {
        'id': 1,
        'name': 'Ma boutique',
        'name_ar': 'متجري',
        'address': null,
        'phone': null,
        'email': null,
        'tax_id': null,
        'footer': 'Merci de votre visite',
        'logo_path': null,
        'updated_at': now,
      });
    }

    final defaults = <String, String>{
      'language': 'ar',
      'stock_policy': 'block',
      'auto_print': '0',
      'paper_width': '58',
      'catalog_enabled': '1',
      'expiry_alert_days': '30',
      'printer_mac': '',
      'printer_name': '',
      'default_payment_method': 'cash',
      'onboarding_done': '0',
      'theme_mode': 'system',
      'business_type': 'small',
    };
    for (final entry in defaults.entries) {
      await db.insert('settings', {
        'key': entry.key,
        'value': entry.value,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    for (final name in ['sale', 'purchase', 'return']) {
      await db.insert('sequences', {
        'name': name,
        'next_value': 1,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    // Idempotent: creates the 16 predefined subcategories on a fresh install
    // and preserves every existing category on upgraded databases.
    await seedPredefinedCategories(db);
  }
}
