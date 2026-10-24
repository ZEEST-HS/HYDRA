import 'package:sqflite/sqflite.dart';

import '../../core/classifications.dart';
import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../core/errors.dart';
import '../../core/quantity.dart';
import '../models/models.dart';
import 'audit_service.dart';

String normalizeBarcode(String raw) {
  var value = raw.trim();
  // Remove zero-width characters and whitespace that keyboard scanners may add.
  value = value.replaceAll(RegExp(r'[\s\u200B-\u200D\uFEFF]'), '');
  return value;
}

class ProductRepository {
  ProductRepository(this.appDb);
  final AppDatabase appDb;

  Database get _db => appDb.db;

  Future<List<Product>> search(
    String query, {
    bool includeInactive = false,
    bool lowStockOnly = false,
    String? division,
    int? categoryId,
    bool unclassifiedOnly = false,
    int limit = 300,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    where.add('p.deleted_at IS NULL');
    if (!includeInactive) where.add('p.is_active = 1');
    final q = query.trim();
    if (q.isNotEmpty) {
      where.add(
        '(p.name LIKE ? OR IFNULL(p.name_ar, \'\') LIKE ? '
        'OR IFNULL(p.barcode, \'\') LIKE ? OR IFNULL(p.brand, \'\') LIKE ?)',
      );
      final pattern = '%$q%';
      args.addAll([pattern, pattern, pattern, pattern]);
    }
    if (lowStockOnly) {
      where.add('p.min_stock_milli > 0 AND p.stock_milli <= p.min_stock_milli');
    }
    if (categoryId != null) {
      where.add('p.category_id = ?');
      args.add(categoryId);
    } else if (unclassifiedOnly) {
      where.add('p.category_id IS NULL');
    } else if (division != null) {
      where.add('c.division = ?');
      args.add(division);
    }
    final joined = await _db.rawQuery(
      '''
      SELECT p.*, c.name_fr AS category_name, c.name_ar AS category_name_ar
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE ${where.join(' AND ')}
      ORDER BY ${q.isEmpty ? 'p.name COLLATE NOCASE ASC' : 'CASE WHEN p.barcode = ? THEN 0 ELSE 1 END, p.name COLLATE NOCASE ASC'}
      LIMIT ?
    ''',
      [...args, if (q.isNotEmpty) q, limit],
    );
    if (joined.isEmpty) return const [];
    return _attachUnits(joined.map(Product.fromMap).toList());
  }

  Future<List<Product>> all({bool includeInactive = false, int limit = 1000}) =>
      search('', includeInactive: includeInactive, limit: limit);

  Future<int> countInCategory(int categoryId) async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE category_id = ? AND deleted_at IS NULL',
      [categoryId],
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<Map<int, int>> categoryCounts() async {
    final rows = await _db.rawQuery('''
      SELECT category_id, COUNT(*) AS c FROM products
      WHERE category_id IS NOT NULL AND deleted_at IS NULL
      GROUP BY category_id
    ''');
    return {
      for (final row in rows)
        (row['category_id'] as num).toInt(): (row['c'] as num).toInt(),
    };
  }

  Future<int> countUnclassified() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE category_id IS NULL AND deleted_at IS NULL',
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<Map<String, int>> divisionCounts() async {
    final rows = await _db.rawQuery('''
      SELECT c.division AS division, COUNT(*) AS c
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.deleted_at IS NULL AND p.is_active = 1
      GROUP BY c.division
    ''');
    return {
      for (final row in rows)
        (row['division'] as String? ?? ''): (row['c'] as num).toInt(),
    };
  }

  Future<Product?> findById(int id) async {
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, c.name_fr AS category_name, c.name_ar AS category_name_ar
      FROM products p LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.id = ? AND p.deleted_at IS NULL LIMIT 1
    ''',
      [id],
    );
    if (rows.isEmpty) return null;
    final product = Product.fromMap(rows.first);
    final units = await getUnits(id);
    return product.copyWith(units: units);
  }

  Future<Product?> findByBarcode(String rawBarcode) async {
    final barcode = normalizeBarcode(rawBarcode);
    if (barcode.isEmpty) return null;
    final rows = await _db.rawQuery(
      '''
      SELECT p.*, c.name_fr AS category_name, c.name_ar AS category_name_ar
      FROM products p LEFT JOIN categories c ON c.id = p.category_id
      WHERE p.barcode = ? AND p.deleted_at IS NULL LIMIT 1
    ''',
      [barcode],
    );
    if (rows.isEmpty) return null;
    final product = Product.fromMap(rows.first);
    return product.copyWith(units: await getUnits(product.id));
  }

  Future<List<ProductUnit>> getUnits(int productId) async {
    final rows = await _db.query(
      'product_units',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'factor_milli ASC',
    );
    return rows.map(ProductUnit.fromMap).toList();
  }

  Future<List<Product>> _attachUnits(List<Product> products) async {
    if (products.isEmpty) return products;
    final ids = products.map((p) => p.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final rows = await _db.query(
      'product_units',
      where: 'product_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'factor_milli ASC',
    );
    final byProduct = <int, List<ProductUnit>>{};
    for (final row in rows) {
      final unit = ProductUnit.fromMap(row);
      byProduct.putIfAbsent(unit.productId, () => []).add(unit);
    }
    return [
      for (final p in products) p.copyWith(units: byProduct[p.id] ?? const []),
    ];
  }

  Future<List<Category>> categories({String? division}) async {
    final rows = await _db.query(
      'categories',
      where: division == null ? null : 'division = ?',
      whereArgs: division == null ? null : [division],
      orderBy:
          'CASE WHEN division IS NULL THEN 1 ELSE 0 END, division, '
          'sort_order ASC, name_fr COLLATE NOCASE',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<List<Category>> categoriesForDivision(String division) =>
      categories(division: division);

  /// Categories that still have no division (legacy data) so the user can
  /// classify them explicitly.
  Future<List<Category>> unclassifiedCategories() async {
    final rows = await _db.query(
      'categories',
      where: 'division IS NULL',
      orderBy: 'name_fr COLLATE NOCASE',
    );
    return rows.map(Category.fromMap).toList();
  }

  Future<int> addCategory(
    String nameFr,
    String? nameAr, {
    String? division,
  }) async {
    if (nameFr.trim().isEmpty) {
      throw ValidationError('Le nom de la catégorie est obligatoire.');
    }
    final name = nameFr.trim();
    final duplicate = await _db.query(
      'categories',
      columns: ['id'],
      where: 'LOWER(name_fr) = ? AND IFNULL(division, \'\') = ?',
      whereArgs: [name.toLowerCase(), division ?? ''],
      limit: 1,
    );
    if (duplicate.isNotEmpty) {
      throw ConflictError('Cette catégorie existe déjà.');
    }
    final rows = await _db.rawQuery(
      'SELECT COALESCE(MAX(sort_order), 0) AS m FROM categories '
      'WHERE IFNULL(division, \'\') = ?',
      [division ?? ''],
    );
    final order = ((rows.first['m'] as num).toInt()) + 1;
    return _db.insert('categories', {
      'name_fr': name,
      'name_ar': (nameAr?.trim().isEmpty ?? true) ? null : nameAr!.trim(),
      'division': division,
      'sort_order': order,
      'is_system': 0,
      'created_at': Dates.nowMillis(),
    });
  }

  Future<void> renameCategory(
    int id, {
    required String nameFr,
    String? nameAr,
  }) async {
    if (nameFr.trim().isEmpty) {
      throw ValidationError('Le nom de la catégorie est obligatoire.');
    }
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Catégorie introuvable.');
    final category = Category.fromMap(rows.first);
    if (category.isSystem) {
      throw ValidationError(
        'Les catégories prédéfinies ne peuvent pas être renommées.',
      );
    }
    await _db.update(
      'categories',
      {
        'name_fr': nameFr.trim(),
        'name_ar': (nameAr?.trim().isEmpty ?? true) ? null : nameAr!.trim(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Moves every product to [targetCategoryId] (or unclassified when null)
  /// before deleting the category. Products, stock and history are preserved.
  Future<void> deleteCategory(int id, {int? targetCategoryId}) async {
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Catégorie introuvable.');
      final category = Category.fromMap(rows.first);
      if (category.isSystem) {
        throw ValidationError(
          'Les catégories prédéfinies ne peuvent pas être supprimées.',
        );
      }
      if (targetCategoryId != null && targetCategoryId == id) {
        throw ValidationError('Choisissez une autre catégorie de destination.');
      }
      if (targetCategoryId != null) {
        final target = await txn.query(
          'categories',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [targetCategoryId],
          limit: 1,
        );
        if (target.isEmpty) throw NotFoundError('Catégorie cible introuvable.');
      }
      final moved = await txn.update(
        'products',
        {'category_id': targetCategoryId},
        where: 'category_id = ?',
        whereArgs: [id],
      );
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
      await AuditService(txn).log(
        action: 'delete',
        entity: 'category',
        entityId: id,
        details: {
          'name': category.nameFr,
          'products_moved': moved,
          'target_category_id': targetCategoryId,
        },
      );
    });
  }

  Future<void> mergeCategory(int sourceId, int targetId) async {
    if (sourceId == targetId) {
      throw ValidationError('Choisissez deux catégories différentes.');
    }
    await deleteCategory(sourceId, targetCategoryId: targetId);
  }

  /// Assigns (or moves) a custom category into one of the two divisions.
  Future<void> setCategoryDivision(int id, String division) async {
    if (division != ProductDivision.food.code &&
        division != ProductDivision.nonFood.code) {
      throw ValidationError('Division invalide.');
    }
    final rows = await _db.query(
      'categories',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) throw NotFoundError('Catégorie introuvable.');
    if (Category.fromMap(rows.first).isSystem) {
      throw ValidationError(
        'Les catégories prédéfinies ne peuvent pas être déplacées.',
      );
    }
    await _db.update(
      'categories',
      {'division': division},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> _ensureBarcodeFree(
    DatabaseExecutor db,
    String? barcode, {
    int? exceptId,
  }) async {
    final value = normalizeBarcode(barcode ?? '');
    if (value.isEmpty) return;
    final rows = await db.query(
      'products',
      columns: ['id'],
      where: 'barcode = ? AND deleted_at IS NULL AND id <> ?',
      whereArgs: [value, exceptId ?? -1],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      throw ConflictError(
        'Ce code-barres est déjà utilisé par un autre produit.',
      );
    }
  }

  Future<Product> create(
    Product product, {
    String? initialExpiryDate,
    String? initialBatchNo,
    String? reason,
  }) async {
    if (product.name.trim().isEmpty) {
      throw ValidationError('Le nom du produit est obligatoire.');
    }
    if (product.priceCentimes < 0 || product.costCentimes < 0) {
      throw ValidationError('Les prix ne peuvent pas être négatifs.');
    }
    final now = Dates.nowMillis();
    return appDb.transaction((txn) async {
      final barcode = normalizeBarcode(product.barcode ?? '');
      await _ensureBarcodeFree(txn, barcode.isEmpty ? null : barcode);
      final map = product.toMap()
        ..remove('id')
        ..['barcode'] = barcode.isEmpty ? null : barcode
        ..['name'] = product.name.trim()
        ..['created_at'] = now
        ..['updated_at'] = now;
      final id = await txn.insert('products', map);
      for (final unit in product.units) {
        if (unit.factorMilli <= 0) continue;
        await txn.insert('product_units', {
          'product_id': id,
          'name': unit.name.trim(),
          'name_ar': unit.nameAr?.trim(),
          'factor_milli': unit.factorMilli,
          'price_centimes': unit.priceCentimes,
          'cost_centimes': unit.costCentimes,
          'is_default_sale': unit.isDefaultSale ? 1 : 0,
          'is_default_purchase': unit.isDefaultPurchase ? 1 : 0,
          'created_at': now,
        });
      }
      if (product.stockMilli != 0) {
        await txn.insert('stock_movements', {
          'product_id': id,
          'type': 'initial',
          'qty_delta_milli': product.stockMilli,
          'unit_cost_centimes': product.costCentimes,
          'ref_type': 'product',
          'ref_id': id,
          'reason': reason ?? 'Stock initial',
          'business_date': Dates.businessDate(),
          'created_at': now,
        });
        if (product.stockMilli > 0) {
          // Always keep an initial batch, even without expiry, so the stock is
          // traceable and can receive an expiry date later.
          await txn.insert('batches', {
            'product_id': id,
            'purchase_id': null,
            'batch_no': (initialBatchNo?.trim().isEmpty ?? true)
                ? null
                : initialBatchNo!.trim(),
            'expiry_date': (initialExpiryDate?.trim().isEmpty ?? true)
                ? null
                : initialExpiryDate!.trim(),
            'qty_received_milli': product.stockMilli,
            'qty_remaining_milli': product.stockMilli,
            'unit_cost_centimes': product.costCentimes,
            'created_at': now,
          });
        }
      }
      await AuditService(txn).log(
        action: 'create',
        entity: 'product',
        entityId: id,
        details: {
          'name': product.name,
          'barcode': barcode,
          'price': product.priceCentimes,
          'cost': product.costCentimes,
          'stock': product.stockMilli,
        },
        reason: reason,
      );
      return product.copyWith(
        id: id,
        barcode: barcode.isEmpty ? null : barcode,
        name: product.name.trim(),
        createdAt: now,
        updatedAt: now,
      );
    });
  }

  /// Updates catalog fields, prices and packaging. Stock is intentionally not
  /// written here: it changes only through stock movements.
  Future<void> update(
    Product product, {
    String? reason,
    bool replaceUnits = true,
  }) async {
    if (product.id <= 0) throw ValidationError('Produit invalide.');
    if (product.name.trim().isEmpty) {
      throw ValidationError('Le nom du produit est obligatoire.');
    }
    final now = Dates.nowMillis();
    await appDb.transaction((txn) async {
      final oldRows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [product.id],
        limit: 1,
      );
      if (oldRows.isEmpty) throw NotFoundError('Produit introuvable.');
      final old = Product.fromMap(oldRows.first);
      final barcode = normalizeBarcode(product.barcode ?? '');
      await _ensureBarcodeFree(
        txn,
        barcode.isEmpty ? null : barcode,
        exceptId: product.id,
      );
      final map = product.toMap()
        ..remove('id')
        ..remove('stock_milli')
        ..['barcode'] = barcode.isEmpty ? null : barcode
        ..['name'] = product.name.trim()
        ..['updated_at'] = now;
      await txn.update(
        'products',
        map,
        where: 'id = ?',
        whereArgs: [product.id],
      );
      if (replaceUnits) {
        await txn.delete(
          'product_units',
          where: 'product_id = ?',
          whereArgs: [product.id],
        );
        for (final unit in product.units) {
          if (unit.factorMilli <= 0) continue;
          await txn.insert('product_units', {
            'product_id': product.id,
            'name': unit.name.trim(),
            'name_ar': unit.nameAr?.trim(),
            'factor_milli': unit.factorMilli,
            'price_centimes': unit.priceCentimes,
            'cost_centimes': unit.costCentimes,
            'is_default_sale': unit.isDefaultSale ? 1 : 0,
            'is_default_purchase': unit.isDefaultPurchase ? 1 : 0,
            'created_at': now,
          });
        }
      }
      final changes = <String, Object?>{};
      if (old.priceCentimes != product.priceCentimes) {
        changes['price_before'] = old.priceCentimes;
        changes['price_after'] = product.priceCentimes;
      }
      if (old.costCentimes != product.costCentimes) {
        changes['cost_before'] = old.costCentimes;
        changes['cost_after'] = product.costCentimes;
      }
      if (old.name != product.name) {
        changes['name_before'] = old.name;
        changes['name_after'] = product.name;
      }
      await AuditService(txn).log(
        action: 'update',
        entity: 'product',
        entityId: product.id,
        details: changes.isEmpty ? {'updated': true} : changes,
        reason: reason,
      );
    });
  }

  /// Soft-deletes a product. Historical invoice lines keep their snapshots.
  Future<void> delete(int id, {String? reason}) async {
    final now = Dates.nowMillis();
    await appDb.transaction((txn) async {
      final rows = await txn.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) throw NotFoundError('Produit introuvable.');
      await txn.update(
        'products',
        {'is_active': 0, 'deleted_at': now, 'updated_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
      await AuditService(txn).log(
        action: 'delete',
        entity: 'product',
        entityId: id,
        details: {'name': rows.first['name']},
        reason: reason,
      );
    });
  }

  Future<int> countActive() async {
    final rows = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM products WHERE deleted_at IS NULL AND is_active = 1',
    );
    return (rows.first['c'] as num).toInt();
  }

  Future<int> stockValueTotal() async {
    final rows = await _db.rawQuery(
      'SELECT COALESCE(SUM((stock_milli * cost_centimes) / 1000), 0) AS v '
      'FROM products WHERE deleted_at IS NULL AND is_active = 1',
    );
    return (rows.first['v'] as num).round();
  }

  /// Conversion helper used by forms: stock in base units for a quantity
  /// entered in a package. Kept here so UI and services share one rule.
  static int packageQtyToBase(String input, int factorMilli) {
    final qty = Qty.tryParse(input);
    if (qty == null) throw ValidationError('Quantité invalide.');
    return (qty * factorMilli + 500) ~/ 1000;
  }
}
