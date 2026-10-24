import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/sales/sale_service.dart';
import 'package:hydra_pos/services/import_export_service.dart';
import 'package:path/path.dart' as p;

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;
  late Directory dir;
  late ImportExportService io;

  setUp(() async {
    env = await TestEnv.memory();
    io = ImportExportService(
      productRepository: env.products,
      inventoryRepository: env.inventory,
      salesService: env.sales,
      purchasesService: env.purchases,
      partiesRepository: env.parties,
    );
    dir = await tempDir('hydra_csv_');
  });

  tearDown(() async {
    await env.close();
    await cleanDir(dir);
  });

  Future<String> writeCsv(String name, String content) async {
    final file = File(p.join(dir.path, name));
    await file.writeAsString(content, encoding: utf8);
    return file.path;
  }

  const header =
      'nom;nom_ar;code_barres;prix;cout;stock;stock_min;unite;categorie;'
      'marque;conditionnement';

  String csvData() =>
      '$header\n'
      'Lait Centrale 1L;حليب سنترال;6111245100059;8,50;7,20;24;6;piece;'
      'Produits laitiers;Centrale;1 L\n'
      'Pain complet;;6111245100073;2.00;1.20;10;2;piece;Boulangerie;;\n';

  test('imports products without touching stock by default', () async {
    final path = await writeCsv('produits.csv', csvData());

    final result = await io.importProductsFile(path);

    expect(result.created, 2);
    expect(result.updated, 0);
    expect(result.errors, isEmpty);

    final lait = await env.products.findByBarcode('6111245100059');
    expect(lait, isNotNull);
    expect(lait!.name, 'Lait Centrale 1L');
    expect(lait.nameAr, 'حليب سنترال');
    expect(lait.priceCentimes, 850);
    expect(lait.costCentimes, 720);
    expect(lait.stockMilli, 0, reason: 'stock must be opt-in');
    expect(lait.minStockMilli, 6000);
    expect(lait.categoryName, 'Produits laitiers');

    final categories = await env.products.categories();
    expect(
      categories.map((c) => c.nameFr),
      containsAll(['Produits laitiers', 'Boulangerie']),
    );
  });

  test('updates existing products and stock when explicitly enabled', () async {
    final path = await writeCsv('produits.csv', csvData());
    await io.importProductsFile(path);

    final result = await io.importProductsFile(
      path,
      updateStock: true,
      updateExisting: true,
    );

    expect(result.updated, 2);
    expect(result.created, 0);

    final lait = (await env.products.findByBarcode('6111245100059'))!;
    expect(lait.stockMilli, 24000);
    expect(await productStockMilli(env, lait.id), 24000);

    final pain = (await env.products.findByBarcode('6111245100073'))!;
    expect(pain.stockMilli, 10000);

    final movements = await env.db.db.query(
      'stock_movements',
      where: "type = 'stocktake'",
    );
    expect(movements, hasLength(2));
  });

  test('can skip existing products', () async {
    final path = await writeCsv('produits.csv', csvData());
    await io.importProductsFile(path);

    final result = await io.importProductsFile(
      path,
      updateExisting: false,
      updateStock: true,
    );

    expect(result.created, 0);
    expect(result.updated, 0);
    expect(result.skipped, 2);
  });

  test('reports invalid rows and fails when nothing was imported', () async {
    final path = await writeCsv(
      'bad.csv',
      '$header\n'
          'Produit cassé;;6111999999999;abc;1;10;0;piece;;;\n',
    );

    await expectLater(
      io.importProductsFile(path),
      throwsA(isA<ValidationError>()),
    );
    expect(await env.db.count('products'), 0);
  });

  test('rejects unsupported files and missing name column', () async {
    final json = await writeCsv('data.json', '{"name": "x"}');
    await expectLater(
      io.importProductsFile(json),
      throwsA(isA<ValidationError>()),
    );

    final noName = await writeCsv('noname.csv', 'prix;stock\n8,50;10\n');
    await expectLater(
      io.importProductsFile(noName),
      throwsA(isA<ValidationError>()),
    );

    final empty = await writeCsv('empty.csv', '');
    await expectLater(
      io.importProductsFile(empty),
      throwsA(isA<ValidationError>()),
    );
  });

  test('template CSV contains headers and one example line', () async {
    final csv = io.productTemplateCsv();
    expect(csv, startsWith('\uFEFF'));
    final rows = Csv(fieldDelimiter: ';').decode(csv.substring(1));
    expect(rows.first, ImportExportService.templateHeaders);
    expect(rows, hasLength(2));
    expect(rows[1][0], 'Lait Centrale 1L');
    expect(rows[1][2], '6111245100059');
  });

  test('product CSV export preserves local prices, cost and stock', () async {
    final categories = await env.products.categories();
    final boissons = categories.firstWhere((c) => c.nameFr == 'Boissons');
    final created = await env.products.create(
      Product(
        name: 'Thé Sultan',
        barcode: '6111245100097',
        priceCentimes: 1250,
        costCentimes: 900,
        stockMilli: 3500,
        minStockMilli: 1000,
        baseUnit: 'piece',
        brand: 'Sultan',
        packageSize: '200 g',
        categoryId: boissons.id,
      ),
    );
    final product = (await env.products.findById(created.id))!;
    final csv = io.exportProductsCsv([product]);
    final rows = Csv(fieldDelimiter: ';').decode(csv.substring(1));

    expect(rows.first, ImportExportService.templateHeaders);
    expect(rows[1][0], 'Thé Sultan');
    expect(rows[1][2], '6111245100097');
    expect(rows[1][3], '12,50');
    expect(rows[1][4], '9,00');
    expect(rows[1][5], '3,5');
    expect(rows[1][8], 'Boissons');
    expect(rows[1][9], 'Sultan');
    expect(rows[1][10], '200 g');
  });

  test('XLSX export produces a valid workbook', () async {
    final created = await env.products.create(
      const Product(name: 'Riz', priceCentimes: 1500, costCentimes: 1100),
    );
    final product = (await env.products.findById(created.id))!;

    final bytes = io.exportProductsXlsx([product]);

    expect(bytes.length, greaterThan(1000));
    // XLSX files are ZIP archives.
    expect(bytes.take(2).toList(), [0x50, 0x4B]);
  });

  test('sales, purchases and debt CSV exports include local data', () async {
    final customerId = await env.parties.createCustomer(
      const Customer(name: 'Karim', phone: '0600000000'),
    );
    final created = await env.products.create(
      const Product(
        name: 'Eau Sidi Ali',
        barcode: '6111245100103',
        priceCentimes: 500,
        costCentimes: 300,
        stockMilli: 20000,
      ),
    );
    final product = (await env.products.findById(created.id))!;
    await env.sales.completeSale(
      SaleDraft(
        lines: [
          SaleDraftLine(
            product: product,
            qtyMilli: 2000,
            unitPriceCentimes: 500,
          ),
        ],
        customerId: customerId,
        paidCentimes: 400,
        paymentMethod: 'cash',
        idempotencyKey: 'export-sale',
      ),
    );

    final salesCsv = await io.exportSalesCsv();
    expect(salesCsv, contains('V-'));
    expect(salesCsv, contains('Karim'));
    expect(salesCsv, contains('cash'));
    expect(salesCsv, contains('6.00'));

    final debtsCsv = await io.exportCustomerDebtsCsv();
    expect(debtsCsv, contains('Karim'));
    expect(debtsCsv, contains('6.00'));

    final purchasesCsv = await io.exportPurchasesCsv();
    expect(purchasesCsv, contains('reference'));

    final supplierCsv = await io.exportSupplierDebtsCsv();
    expect(supplierCsv, contains('fournisseur'));
  });
}
