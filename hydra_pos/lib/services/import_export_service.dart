import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../core/dates.dart';
import '../core/errors.dart';
import '../core/money.dart';
import '../core/quantity.dart';
import '../data/models/models.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/party_repository.dart';
import '../data/repositories/product_repository.dart';
import '../domain/purchases/purchase_service.dart';
import '../domain/sales/sale_service.dart';

/// One rejected row. [row] is the 1-based line in the original file.
class ImportRowError {
  const ImportRowError(this.row, this.message);
  final int row;
  final String message;

  Map<String, Object?> toMap() => {'row': row, 'message': message};
}

class ImportResult {
  ImportResult({
    this.created = 0,
    this.updated = 0,
    this.skipped = 0,
    List<ImportRowError>? errors,
  }) : errors = errors ?? [];

  int created;
  int updated;
  int skipped;
  final List<ImportRowError> errors;

  int get total => created + updated + skipped;
}

/// CSV/XLSX product import and CSV exports.
///
/// Import is deliberately explicit: prices and catalog fields may be updated,
/// but stock is only touched when [updateStock] is true. Import never deletes
/// products and never changes sales, purchases or debts.
class ImportExportService {
  ImportExportService({
    required this.productRepository,
    required this.inventoryRepository,
    required this.salesService,
    required this.purchasesService,
    required this.partiesRepository,
  });

  final ProductRepository productRepository;
  final InventoryRepository inventoryRepository;
  final SaleService salesService;
  final PurchaseService purchasesService;
  final PartyRepository partiesRepository;

  static const List<String> templateHeaders = [
    'nom',
    'nom_ar',
    'code_barres',
    'prix',
    'cout',
    'stock',
    'stock_min',
    'unite',
    'categorie',
    'marque',
    'conditionnement',
  ];

  static const Map<String, List<String>> _aliases = {
    'name': ['nom', 'name', 'produit', 'product', 'designation', 'libelle'],
    'name_ar': ['nom_ar', 'nom arabe', 'name_ar', 'arabic', 'الاسم'],
    'barcode': [
      'code_barres',
      'code-barres',
      'code barres',
      'barcode',
      'ean',
      'code',
    ],
    'price': ['prix', 'prix_vente', 'prix de vente', 'price', 'sale_price'],
    'cost': ['cout', 'coût', 'prix_achat', 'prix achat', 'cost', 'buy_price'],
    'stock': ['stock', 'quantite', 'quantité', 'qty', 'quantity'],
    'min_stock': ['stock_min', 'stock min', 'stock minimum', 'min_stock'],
    'unit': ['unite', 'unité', 'unit', 'unite_base'],
    'category': ['categorie', 'catégorie', 'category', 'rayon'],
    'brand': ['marque', 'brand'],
    'package': ['conditionnement', 'packaging', 'package_size', 'format'],
  };

  static const Map<String, String> _unitAliases = {
    'piece': 'piece',
    'pièce': 'piece',
    'piéce': 'piece',
    'pcs': 'piece',
    'unite': 'piece',
    'unité': 'piece',
    'kg': 'kg',
    'kilo': 'kg',
    'kilogramme': 'kg',
    'g': 'g',
    'gramme': 'g',
    'l': 'l',
    'litre': 'l',
    'ml': 'ml',
  };

  /// Reads [path] as CSV (`.csv`/`.txt`) or XLSX (`.xlsx`).
  Future<ImportResult> importProductsFile(
    String path, {
    bool updateStock = false,
    bool updateExisting = true,
  }) async {
    final lower = path.toLowerCase();
    final List<List<String>> rows;
    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      rows = await _readCsv(path);
    } else if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      rows = await _readXlsx(path);
    } else {
      throw ValidationError(
        'Format non pris en charge. Utilisez un fichier CSV ou Excel (.xlsx).',
      );
    }
    if (rows.isEmpty) {
      throw ValidationError('Le fichier est vide.');
    }
    final headerIndex = _findHeaderRow(rows);
    if (headerIndex == null) {
      throw ValidationError(
        'Colonne « nom » introuvable. Téléchargez le modèle CSV.',
      );
    }
    final header = rows[headerIndex]
        .map(_normalizeHeader)
        .toList(growable: false);
    final columnFor = <String, int>{};
    for (final entry in _aliases.entries) {
      final index = header.indexWhere(entry.value.contains);
      if (index >= 0) columnFor[entry.key] = index;
    }
    if (!columnFor.containsKey('name')) {
      throw ValidationError(
        'Colonne « nom » introuvable. Téléchargez le modèle CSV.',
      );
    }

    final result = ImportResult();
    final categories = <String, int>{
      for (final c in await productRepository.categories())
        c.nameFr.toLowerCase(): c.id,
    };

    for (var i = headerIndex + 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final lineNumber = i + 1;
      try {
        String cell(String key) {
          final index = columnFor[key];
          if (index == null || index >= row.length) return '';
          return row[index].trim();
        }

        final name = cell('name');
        if (name.isEmpty) {
          throw ValidationError('Le nom est obligatoire.');
        }
        final price = _parseMoney(cell('price'), 'prix');
        final cost = _parseMoney(cell('cost'), 'coût');
        final stock = _parseQty(cell('stock'), 'stock');
        final minStock = _parseQty(cell('min_stock'), 'stock minimum');
        final barcode = normalizeBarcode(cell('barcode'));
        final unitText = cell('unit').toLowerCase();
        final unit = _unitAliases[unitText] ?? 'piece';
        final categoryName = cell('category');
        int? categoryId;
        if (categoryName.isNotEmpty) {
          categoryId = categories[categoryName.toLowerCase()];
          if (categoryId == null) {
            categoryId = await productRepository.addCategory(
              categoryName,
              null,
            );
            categories[categoryName.toLowerCase()] = categoryId;
          }
        }

        final existing = barcode.isEmpty
            ? null
            : await productRepository.findByBarcode(barcode);
        if (existing != null) {
          if (!updateExisting) {
            result.skipped++;
            continue;
          }
          await productRepository.update(
            existing.copyWith(
              name: name,
              nameAr: cell('name_ar').isEmpty
                  ? existing.nameAr
                  : cell('name_ar'),
              brand: cell('brand').isEmpty ? existing.brand : cell('brand'),
              packageSize: cell('package').isEmpty
                  ? existing.packageSize
                  : cell('package'),
              baseUnit: unitText.isEmpty ? existing.baseUnit : unit,
              categoryId: categoryId ?? existing.categoryId,
              priceCentimes: price ?? existing.priceCentimes,
              costCentimes: cost ?? existing.costCentimes,
              minStockMilli: minStock ?? existing.minStockMilli,
              notes: existing.notes,
            ),
            reason: 'Import CSV',
          );
          if (updateStock && stock != null) {
            await inventoryRepository.setCountedStock(
              productId: existing.id,
              countedMilli: stock,
              reason: 'Import CSV',
            );
          }
          result.updated++;
        } else {
          final product = Product(
            barcode: barcode.isEmpty ? null : barcode,
            name: name,
            nameAr: cell('name_ar').isEmpty ? null : cell('name_ar'),
            brand: cell('brand').isEmpty ? null : cell('brand'),
            packageSize: cell('package').isEmpty ? null : cell('package'),
            baseUnit: unit,
            categoryId: categoryId,
            priceCentimes: price ?? 0,
            costCentimes: cost ?? 0,
            minStockMilli: minStock ?? 0,
            stockMilli: updateStock ? (stock ?? 0) : 0,
            isActive: true,
          );
          await productRepository.create(product, reason: 'Import CSV');
          result.created++;
        }
      } catch (e) {
        result.errors.add(ImportRowError(lineNumber, _message(e)));
      }
    }
    if (result.created == 0 &&
        result.updated == 0 &&
        result.errors.isNotEmpty) {
      throw ValidationError(
        'Aucune ligne importée. ${result.errors.length} erreur(s) : '
        '${result.errors.first.message}',
      );
    }
    return result;
  }

  /// CSV with a header row and one example line, saved/shared by the UI.
  String productTemplateCsv() {
    final rows = <List<String>>[
      templateHeaders,
      [
        'Lait Centrale 1L',
        'حليب سنترال 1 لتر',
        '6111245100059',
        '8.50',
        '7.20',
        '24',
        '6',
        'piece',
        'Produits laitiers',
        'Centrale',
        '1 L',
      ],
    ];
    return _encodeCsv(rows);
  }

  /// Products with local prices, cost and stock (stock is informational).
  String exportProductsCsv(List<Product> products) {
    final rows = <List<String>>[
      templateHeaders,
      for (final p in products)
        [
          p.name,
          p.nameAr ?? '',
          p.barcode ?? '',
          Money.format(p.priceCentimes).replaceAll('\u00A0', ''),
          Money.format(p.costCentimes).replaceAll('\u00A0', ''),
          Qty.format(p.stockMilli),
          Qty.format(p.minStockMilli),
          p.baseUnit,
          p.categoryName ?? '',
          p.brand ?? '',
          p.packageSize ?? '',
        ],
    ];
    return _encodeCsv(rows);
  }

  Future<String> exportSalesCsv({
    DateTime? from,
    DateTime? to,
    int limit = 10000,
  }) async {
    final sales = await salesService.list(from: from, to: to, limit: limit);
    final rows = <List<String>>[
      [
        'facture',
        'date',
        'heure',
        'client',
        'sous_total',
        'remise',
        'total',
        'paye',
        'reste',
        'paiement',
        'statut',
        'retours',
      ],
      for (final s in sales)
        [
          s.invoiceNo,
          s.businessDate,
          Dates.formatTime(DateTime.fromMillisecondsSinceEpoch(s.createdAt)),
          s.customerName ?? '',
          _plainMoney(s.subtotalCentimes),
          _plainMoney(s.discountCentimes),
          _plainMoney(s.totalCentimes),
          _plainMoney(s.paidCentimes),
          _plainMoney(s.dueCentimes),
          s.paymentMethod,
          s.status,
          _plainMoney(s.returnedCentimes),
        ],
    ];
    return _encodeCsv(rows);
  }

  Future<String> exportPurchasesCsv({
    DateTime? from,
    DateTime? to,
    int limit = 10000,
  }) async {
    final purchases = await purchasesService.list(
      from: from,
      to: to,
      limit: limit,
    );
    final rows = <List<String>>[
      [
        'reference',
        'date',
        'fournisseur',
        'sous_total',
        'remise',
        'total',
        'paye',
        'reste',
        'paiement',
        'statut',
      ],
      for (final p in purchases)
        [
          p.refNo,
          p.businessDate,
          p.supplierName ?? '',
          _plainMoney(p.subtotalCentimes),
          _plainMoney(p.discountCentimes),
          _plainMoney(p.totalCentimes),
          _plainMoney(p.paidCentimes),
          _plainMoney(p.dueCentimes),
          p.paymentMethod,
          p.status,
        ],
    ];
    return _encodeCsv(rows);
  }

  Future<String> exportCustomerDebtsCsv() async {
    final customers = await partiesRepository.customers();
    final rows = <List<String>>[
      ['client', 'telephone', 'solde', 'limite_credit'],
      for (final c in customers)
        [
          c.name,
          c.phone ?? '',
          _plainMoney(c.balanceCentimes),
          _plainMoney(c.creditLimitCentimes),
        ],
    ];
    return _encodeCsv(rows);
  }

  Future<String> exportSupplierDebtsCsv() async {
    final suppliers = await partiesRepository.suppliers();
    final rows = <List<String>>[
      ['fournisseur', 'telephone', 'solde'],
      for (final s in suppliers)
        [s.name, s.phone ?? '', _plainMoney(s.balanceCentimes)],
    ];
    return _encodeCsv(rows);
  }

  /// Excel export of products (first sheet only).
  List<int> exportProductsXlsx(List<Product> products) {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Produits';
    final sheet = excel[sheetName];
    sheet.appendRow(
      templateHeaders.map<CellValue>((e) => TextCellValue(e)).toList(),
    );
    for (final p in products) {
      sheet.appendRow([
        TextCellValue(p.name),
        TextCellValue(p.nameAr ?? ''),
        TextCellValue(p.barcode ?? ''),
        TextCellValue(_plainMoney(p.priceCentimes)),
        TextCellValue(_plainMoney(p.costCentimes)),
        TextCellValue(Qty.format(p.stockMilli)),
        TextCellValue(Qty.format(p.minStockMilli)),
        TextCellValue(p.baseUnit),
        TextCellValue(p.categoryName ?? ''),
        TextCellValue(p.brand ?? ''),
        TextCellValue(p.packageSize ?? ''),
      ]);
    }
    final bytes = excel.save();
    if (bytes == null) throw AppError('export', 'Export Excel impossible.');
    return bytes;
  }

  Future<List<List<String>>> _readCsv(String path) async {
    final raw = await File(path).readAsBytes();
    var text = utf8.decode(raw, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final firstLine = text.split(RegExp(r'\r?\n')).first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    final tabs = '\t'.allMatches(firstLine).length;
    final delimiter = tabs > semicolons && tabs > commas
        ? '\t'
        : (semicolons >= commas ? ';' : ',');
    final parsed = Csv(
      fieldDelimiter: delimiter,
      autoDetect: false,
      skipEmptyLines: true,
    ).decode(text.replaceAll('\r\n', '\n'));
    return [
      for (final row in parsed)
        [for (final cell in row) cell?.toString().trim() ?? ''],
    ];
  }

  Future<List<List<String>>> _readXlsx(String path) async {
    final bytes = await File(path).readAsBytes();
    final Excel excel;
    try {
      excel = Excel.decodeBytes(bytes);
    } catch (e) {
      throw ValidationError('Fichier Excel illisible : ${_message(e)}');
    }
    final sheet = excel.sheets.values.isEmpty
        ? null
        : excel.sheets.values.first;
    if (sheet == null) return const [];
    final result = <List<String>>[];
    for (final row in sheet.rows) {
      result.add([for (final cell in row) _cellText(cell?.value)]);
    }
    return result;
  }

  String _cellText(CellValue? value) {
    switch (value) {
      case null:
        return '';
      case final TextCellValue text:
        return text.value.toString().trim();
      case final IntCellValue number:
        return number.value.toString();
      case final DoubleCellValue number:
        return number.value.toString();
      case final BoolCellValue flag:
        return flag.value ? '1' : '0';
      case final DateCellValue date:
        return '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      case final DateTimeCellValue date:
        return '${date.year.toString().padLeft(4, '0')}-'
            '${date.month.toString().padLeft(2, '0')}-'
            '${date.day.toString().padLeft(2, '0')}';
      case final FormulaCellValue formula:
        return formula.formula;
      case final TimeCellValue time:
        return '${time.hour}:${time.minute}';
    }
  }

  int? _findHeaderRow(List<List<String>> rows) {
    final limit = rows.length < 15 ? rows.length : 15;
    for (var i = 0; i < limit; i++) {
      final normalized = rows[i].map(_normalizeHeader).toList();
      if (normalized.any(_aliases['name']!.contains)) return i;
    }
    return null;
  }

  String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('à', 'a')
      .replaceAll('ç', 'c')
      .replaceAll('ô', 'o')
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[^a-z0-9_\u0600-\u06FF ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  int? _parseMoney(String raw, String field) {
    if (raw.trim().isEmpty) return null;
    final value = Money.tryParseToCentimes(raw);
    if (value == null || value < 0) {
      throw ValidationError('$field invalide : « $raw ».');
    }
    return value;
  }

  int? _parseQty(String raw, String field) {
    if (raw.trim().isEmpty) return null;
    final value = Qty.tryParse(raw);
    if (value == null || value < 0) {
      throw ValidationError('$field invalide : « $raw ».');
    }
    return value;
  }

  String _plainMoney(int centimes) =>
      Money.format(centimes).replaceAll('\u00A0', '').replaceAll(',', '.');

  String _encodeCsv(List<List<String>> rows) {
    final buffer = StringBuffer('\uFEFF');
    buffer.write(
      const CsvEncoder(fieldDelimiter: ';', addBom: false).convert(rows),
    );
    return buffer.toString();
  }

  String _message(Object error) =>
      error is AppError ? error.message : error.toString();
}
