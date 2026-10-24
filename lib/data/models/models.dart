import '../../core/quantity.dart';

int? asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int asIntOr(Object? v, int fallback) => asInt(v) ?? fallback;

String? asString(Object? v) => v?.toString();

bool asBool(Object? v) => v == 1 || v == true || v == '1' || v == 'true';

const unitCodes = ['piece', 'kg', 'g', 'l', 'ml'];

class Shop {
  const Shop({
    this.id = 1,
    required this.name,
    this.nameAr,
    this.address,
    this.phone,
    this.email,
    this.taxId,
    this.footer,
    this.logoPath,
  });

  final int id;
  final String name;
  final String? nameAr;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxId;
  final String? footer;
  final String? logoPath;

  String displayName(bool arabic) =>
      (arabic && (nameAr?.trim().isNotEmpty ?? false)) ? nameAr!.trim() : name;

  Shop copyWith({
    String? name,
    String? nameAr,
    String? address,
    String? phone,
    String? email,
    String? taxId,
    String? footer,
    String? logoPath,
  }) => Shop(
    id: id,
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    address: address ?? this.address,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    taxId: taxId ?? this.taxId,
    footer: footer ?? this.footer,
    logoPath: logoPath ?? this.logoPath,
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'name_ar': nameAr,
    'address': address,
    'phone': phone,
    'email': email,
    'tax_id': taxId,
    'footer': footer,
    'logo_path': logoPath,
  };

  factory Shop.fromMap(Map<String, Object?> m) => Shop(
    id: asIntOr(m['id'], 1),
    name: asString(m['name']) ?? '',
    nameAr: asString(m['name_ar']),
    address: asString(m['address']),
    phone: asString(m['phone']),
    email: asString(m['email']),
    taxId: asString(m['tax_id']),
    footer: asString(m['footer']),
    logoPath: asString(m['logo_path']),
  );
}

class ProductUnit {
  const ProductUnit({
    this.id = 0,
    this.productId = 0,
    required this.name,
    this.nameAr,
    required this.factorMilli,
    this.priceCentimes,
    this.costCentimes,
    this.isDefaultSale = false,
    this.isDefaultPurchase = false,
  });

  final int id;
  final int productId;
  final String name;
  final String? nameAr;
  final int factorMilli;
  final int? priceCentimes;
  final int? costCentimes;
  final bool isDefaultSale;
  final bool isDefaultPurchase;

  String displayName(bool arabic) =>
      (arabic && (nameAr?.trim().isNotEmpty ?? false)) ? nameAr!.trim() : name;

  /// Factor as a friendly number, e.g. 12 for a carton of 12 pieces.
  String get factorLabel => Qty.format(factorMilli);

  double get factorUnits => factorMilli / Qty.milliPerUnit;

  ProductUnit copyWith({
    int? id,
    int? productId,
    String? name,
    String? nameAr,
    int? factorMilli,
    int? priceCentimes,
    int? costCentimes,
    bool? isDefaultSale,
    bool? isDefaultPurchase,
  }) => ProductUnit(
    id: id ?? this.id,
    productId: productId ?? this.productId,
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    factorMilli: factorMilli ?? this.factorMilli,
    priceCentimes: priceCentimes ?? this.priceCentimes,
    costCentimes: costCentimes ?? this.costCentimes,
    isDefaultSale: isDefaultSale ?? this.isDefaultSale,
    isDefaultPurchase: isDefaultPurchase ?? this.isDefaultPurchase,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'product_id': productId,
    'name': name,
    'name_ar': nameAr,
    'factor_milli': factorMilli,
    'price_centimes': priceCentimes,
    'cost_centimes': costCentimes,
    'is_default_sale': isDefaultSale ? 1 : 0,
    'is_default_purchase': isDefaultPurchase ? 1 : 0,
  };

  factory ProductUnit.fromMap(Map<String, Object?> m) => ProductUnit(
    id: asIntOr(m['id'], 0),
    productId: asIntOr(m['product_id'], 0),
    name: asString(m['name']) ?? '',
    nameAr: asString(m['name_ar']),
    factorMilli: asIntOr(m['factor_milli'], Qty.milliPerUnit),
    priceCentimes: asInt(m['price_centimes']),
    costCentimes: asInt(m['cost_centimes']),
    isDefaultSale: asBool(m['is_default_sale']),
    isDefaultPurchase: asBool(m['is_default_purchase']),
  );
}

class Product {
  const Product({
    this.id = 0,
    this.barcode,
    required this.name,
    this.nameAr,
    this.brand,
    this.categoryId,
    this.packageSize,
    this.baseUnit = 'piece',
    this.costCentimes = 0,
    this.priceCentimes = 0,
    this.stockMilli = 0,
    this.minStockMilli = 0,
    this.supplierId,
    this.imageUrl,
    this.imagePath,
    this.catalogSource,
    this.catalogUpdatedAt,
    this.notes,
    this.isActive = true,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.units = const [],
    this.categoryName,
    this.categoryNameAr,
  });

  final int id;
  final String? barcode;
  final String name;
  final String? nameAr;
  final String? brand;
  final int? categoryId;
  final String? packageSize;
  final String baseUnit;
  final int costCentimes;
  final int priceCentimes;
  final int stockMilli;
  final int minStockMilli;
  final int? supplierId;
  final String? imageUrl;
  final String? imagePath;
  final String? catalogSource;
  final int? catalogUpdatedAt;
  final String? notes;
  final bool isActive;
  final int createdAt;
  final int updatedAt;
  final List<ProductUnit> units;
  final String? categoryName;
  final String? categoryNameAr;

  String displayName(bool arabic) =>
      (arabic && (nameAr?.trim().isNotEmpty ?? false)) ? nameAr!.trim() : name;

  bool get isLowStock => minStockMilli > 0 && stockMilli <= minStockMilli;
  bool get isOutOfStock => stockMilli <= 0;
  int get stockValueCentimes => (stockMilli * costCentimes + 500) ~/ 1000;

  List<ProductUnit> get saleUnits =>
      units.where((u) => u.factorMilli > 0).toList();

  bool get hasPackaging => units.isNotEmpty;

  Product copyWith({
    int? id,
    String? barcode,
    String? name,
    String? nameAr,
    String? brand,
    int? categoryId,
    String? packageSize,
    String? baseUnit,
    int? costCentimes,
    int? priceCentimes,
    int? stockMilli,
    int? minStockMilli,
    int? supplierId,
    String? imageUrl,
    String? imagePath,
    String? catalogSource,
    int? catalogUpdatedAt,
    String? notes,
    bool? isActive,
    int? createdAt,
    int? updatedAt,
    List<ProductUnit>? units,
    String? categoryName,
    String? categoryNameAr,
  }) => Product(
    id: id ?? this.id,
    barcode: barcode ?? this.barcode,
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    brand: brand ?? this.brand,
    categoryId: categoryId ?? this.categoryId,
    packageSize: packageSize ?? this.packageSize,
    baseUnit: baseUnit ?? this.baseUnit,
    costCentimes: costCentimes ?? this.costCentimes,
    priceCentimes: priceCentimes ?? this.priceCentimes,
    stockMilli: stockMilli ?? this.stockMilli,
    minStockMilli: minStockMilli ?? this.minStockMilli,
    supplierId: supplierId ?? this.supplierId,
    imageUrl: imageUrl ?? this.imageUrl,
    imagePath: imagePath ?? this.imagePath,
    catalogSource: catalogSource ?? this.catalogSource,
    catalogUpdatedAt: catalogUpdatedAt ?? this.catalogUpdatedAt,
    notes: notes ?? this.notes,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    units: units ?? this.units,
    categoryName: categoryName ?? this.categoryName,
    categoryNameAr: categoryNameAr ?? this.categoryNameAr,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'barcode': barcode,
    'name': name,
    'name_ar': nameAr,
    'brand': brand,
    'category_id': categoryId,
    'package_size': packageSize,
    'base_unit': baseUnit,
    'cost_centimes': costCentimes,
    'price_centimes': priceCentimes,
    'stock_milli': stockMilli,
    'min_stock_milli': minStockMilli,
    'supplier_id': supplierId,
    'image_url': imageUrl,
    'image_path': imagePath,
    'catalog_source': catalogSource,
    'catalog_updated_at': catalogUpdatedAt,
    'notes': notes,
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  factory Product.fromMap(Map<String, Object?> m) => Product(
    id: asIntOr(m['id'], 0),
    barcode: asString(m['barcode']),
    name: asString(m['name']) ?? '',
    nameAr: asString(m['name_ar']),
    brand: asString(m['brand']),
    categoryId: asInt(m['category_id']),
    packageSize: asString(m['package_size']),
    baseUnit: asString(m['base_unit']) ?? 'piece',
    costCentimes: asIntOr(m['cost_centimes'], 0),
    priceCentimes: asIntOr(m['price_centimes'], 0),
    stockMilli: asIntOr(m['stock_milli'], 0),
    minStockMilli: asIntOr(m['min_stock_milli'], 0),
    supplierId: asInt(m['supplier_id']),
    imageUrl: asString(m['image_url']),
    imagePath: asString(m['image_path']),
    catalogSource: asString(m['catalog_source']),
    catalogUpdatedAt: asInt(m['catalog_updated_at']),
    notes: asString(m['notes']),
    isActive: m['is_active'] == null ? true : asBool(m['is_active']),
    createdAt: asIntOr(m['created_at'], 0),
    updatedAt: asIntOr(m['updated_at'], 0),
    categoryName: asString(m['category_name']),
    categoryNameAr: asString(m['category_name_ar']),
  );
}

class Customer {
  const Customer({
    this.id = 0,
    required this.name,
    this.phone,
    this.address,
    this.note,
    this.balanceCentimes = 0,
    this.creditLimitCentimes = 0,
    this.createdAt = 0,
  });

  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? note;
  final int balanceCentimes;
  final int creditLimitCentimes;
  final int createdAt;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'note': note,
    'balance_centimes': balanceCentimes,
    'credit_limit_centimes': creditLimitCentimes,
    'created_at': createdAt,
  };

  factory Customer.fromMap(Map<String, Object?> m) => Customer(
    id: asIntOr(m['id'], 0),
    name: asString(m['name']) ?? '',
    phone: asString(m['phone']),
    address: asString(m['address']),
    note: asString(m['note']),
    balanceCentimes: asIntOr(m['balance_centimes'], 0),
    creditLimitCentimes: asIntOr(m['credit_limit_centimes'], 0),
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class Supplier {
  const Supplier({
    this.id = 0,
    required this.name,
    this.phone,
    this.address,
    this.note,
    this.balanceCentimes = 0,
    this.createdAt = 0,
  });

  final int id;
  final String name;
  final String? phone;
  final String? address;
  final String? note;
  final int balanceCentimes;
  final int createdAt;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'name': name,
    'phone': phone,
    'address': address,
    'note': note,
    'balance_centimes': balanceCentimes,
    'created_at': createdAt,
  };

  factory Supplier.fromMap(Map<String, Object?> m) => Supplier(
    id: asIntOr(m['id'], 0),
    name: asString(m['name']) ?? '',
    phone: asString(m['phone']),
    address: asString(m['address']),
    note: asString(m['note']),
    balanceCentimes: asIntOr(m['balance_centimes'], 0),
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class Category {
  const Category({
    this.id = 0,
    required this.nameFr,
    this.nameAr,
    this.division,
    this.sortOrder = 0,
    this.isSystem = false,
  });
  final int id;
  final String nameFr;
  final String? nameAr;

  /// `food` or `non_food`; `null` for legacy categories the user must classify.
  final String? division;
  final int sortOrder;

  /// Predefined subcategories cannot be renamed or deleted.
  final bool isSystem;

  String displayName(bool arabic) =>
      (arabic && (nameAr?.trim().isNotEmpty ?? false))
      ? nameAr!.trim()
      : nameFr;

  factory Category.fromMap(Map<String, Object?> m) => Category(
    id: asIntOr(m['id'], 0),
    nameFr: asString(m['name_fr']) ?? '',
    nameAr: asString(m['name_ar']),
    division: asString(m['division']),
    sortOrder: asIntOr(m['sort_order'], 0),
    isSystem: asBool(m['is_system']),
  );
}

class SaleLine {
  const SaleLine({
    this.id = 0,
    this.saleId = 0,
    this.productId,
    required this.productName,
    this.barcode,
    this.unitName = '',
    this.factorMilli = Qty.milliPerUnit,
    required this.qtyMilli,
    required this.unitPriceCentimes,
    required this.unitCostCentimes,
    this.lineDiscountCentimes = 0,
    required this.lineTotalCentimes,
  });

  final int id;
  final int saleId;
  final int? productId;
  final String productName;
  final String? barcode;
  final String unitName;
  final int factorMilli;
  final int qtyMilli;
  final int unitPriceCentimes;
  final int unitCostCentimes;
  final int lineDiscountCentimes;
  final int lineTotalCentimes;

  /// Quantity expressed in the recorded sale unit (a carton counts as 1, not
  /// as its 12 base pieces).
  int get displayQtyMilli =>
      factorMilli > 0 ? (qtyMilli * Qty.milliPerUnit) ~/ factorMilli : qtyMilli;

  /// Effective price for one recorded sale unit, including rounding and any
  /// line discount. Used on receipts and invoices.
  int get displayUnitPriceCentimes => qtyMilli <= 0
      ? unitPriceCentimes
      : (lineTotalCentimes * factorMilli + qtyMilli ~/ 2) ~/ qtyMilli;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'sale_id': saleId,
    'product_id': productId,
    'product_name': productName,
    'barcode': barcode,
    'unit_name': unitName,
    'factor_milli': factorMilli,
    'qty_milli': qtyMilli,
    'unit_price_centimes': unitPriceCentimes,
    'unit_cost_centimes': unitCostCentimes,
    'line_discount_centimes': lineDiscountCentimes,
    'line_total_centimes': lineTotalCentimes,
  };

  factory SaleLine.fromMap(Map<String, Object?> m) => SaleLine(
    id: asIntOr(m['id'], 0),
    saleId: asIntOr(m['sale_id'], 0),
    productId: asInt(m['product_id']),
    productName: asString(m['product_name']) ?? '',
    barcode: asString(m['barcode']),
    unitName: asString(m['unit_name']) ?? '',
    factorMilli: asIntOr(m['factor_milli'], Qty.milliPerUnit),
    qtyMilli: asIntOr(m['qty_milli'], 0),
    unitPriceCentimes: asIntOr(m['unit_price_centimes'], 0),
    unitCostCentimes: asIntOr(m['unit_cost_centimes'], 0),
    lineDiscountCentimes: asIntOr(m['line_discount_centimes'], 0),
    lineTotalCentimes: asIntOr(m['line_total_centimes'], 0),
  );
}

class Sale {
  const Sale({
    this.id = 0,
    required this.invoiceNo,
    this.customerId,
    this.customerName,
    required this.subtotalCentimes,
    required this.discountCentimes,
    required this.totalCentimes,
    required this.paidCentimes,
    required this.dueCentimes,
    required this.paymentMethod,
    this.status = 'completed',
    this.note,
    required this.businessDate,
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
    this.lines = const [],
    this.returnedCentimes = 0,
  });

  final int id;
  final String invoiceNo;
  final int? customerId;
  final String? customerName;
  final int subtotalCentimes;
  final int discountCentimes;
  final int totalCentimes;
  final int paidCentimes;
  final int dueCentimes;
  final String paymentMethod;
  final String status;
  final String? note;
  final String businessDate;
  final int createdAt;
  final int? voidedAt;
  final String? voidReason;
  final List<SaleLine> lines;
  final int returnedCentimes;

  bool get isVoided => status == 'voided';

  Sale copyWith({List<SaleLine>? lines, int? returnedCentimes}) => Sale(
    id: id,
    invoiceNo: invoiceNo,
    customerId: customerId,
    customerName: customerName,
    subtotalCentimes: subtotalCentimes,
    discountCentimes: discountCentimes,
    totalCentimes: totalCentimes,
    paidCentimes: paidCentimes,
    dueCentimes: dueCentimes,
    paymentMethod: paymentMethod,
    status: status,
    note: note,
    businessDate: businessDate,
    createdAt: createdAt,
    voidedAt: voidedAt,
    voidReason: voidReason,
    lines: lines ?? this.lines,
    returnedCentimes: returnedCentimes ?? this.returnedCentimes,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'invoice_no': invoiceNo,
    'customer_id': customerId,
    'customer_name': customerName,
    'subtotal_centimes': subtotalCentimes,
    'discount_centimes': discountCentimes,
    'total_centimes': totalCentimes,
    'paid_centimes': paidCentimes,
    'due_centimes': dueCentimes,
    'payment_method': paymentMethod,
    'status': status,
    'note': note,
    'business_date': businessDate,
    'created_at': createdAt,
    'voided_at': voidedAt,
    'void_reason': voidReason,
  };

  factory Sale.fromMap(Map<String, Object?> m) => Sale(
    id: asIntOr(m['id'], 0),
    invoiceNo: asString(m['invoice_no']) ?? '',
    customerId: asInt(m['customer_id']),
    customerName: asString(m['customer_name']),
    subtotalCentimes: asIntOr(m['subtotal_centimes'], 0),
    discountCentimes: asIntOr(m['discount_centimes'], 0),
    totalCentimes: asIntOr(m['total_centimes'], 0),
    paidCentimes: asIntOr(m['paid_centimes'], 0),
    dueCentimes: asIntOr(m['due_centimes'], 0),
    paymentMethod: asString(m['payment_method']) ?? 'cash',
    status: asString(m['status']) ?? 'completed',
    note: asString(m['note']),
    businessDate: asString(m['business_date']) ?? '',
    createdAt: asIntOr(m['created_at'], 0),
    voidedAt: asInt(m['voided_at']),
    voidReason: asString(m['void_reason']),
    returnedCentimes: asIntOr(m['returned_centimes'], 0),
  );
}

class ReturnLine {
  const ReturnLine({
    this.id = 0,
    this.returnId = 0,
    this.saleLineId,
    this.productId,
    required this.productName,
    required this.qtyMilli,
    required this.unitPriceCentimes,
    required this.unitCostCentimes,
    required this.lineTotalCentimes,
  });

  final int id;
  final int returnId;
  final int? saleLineId;
  final int? productId;
  final String productName;
  final int qtyMilli;
  final int unitPriceCentimes;
  final int unitCostCentimes;
  final int lineTotalCentimes;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'return_id': returnId,
    'sale_line_id': saleLineId,
    'product_id': productId,
    'product_name': productName,
    'qty_milli': qtyMilli,
    'unit_price_centimes': unitPriceCentimes,
    'unit_cost_centimes': unitCostCentimes,
    'line_total_centimes': lineTotalCentimes,
  };

  factory ReturnLine.fromMap(Map<String, Object?> m) => ReturnLine(
    id: asIntOr(m['id'], 0),
    returnId: asIntOr(m['return_id'], 0),
    saleLineId: asInt(m['sale_line_id']),
    productId: asInt(m['product_id']),
    productName: asString(m['product_name']) ?? '',
    qtyMilli: asIntOr(m['qty_milli'], 0),
    unitPriceCentimes: asIntOr(m['unit_price_centimes'], 0),
    unitCostCentimes: asIntOr(m['unit_cost_centimes'], 0),
    lineTotalCentimes: asIntOr(m['line_total_centimes'], 0),
  );
}

class SaleReturn {
  const SaleReturn({
    this.id = 0,
    required this.returnNo,
    required this.saleId,
    this.customerId,
    required this.totalCentimes,
    required this.refundMethod,
    this.note,
    required this.businessDate,
    required this.createdAt,
    this.lines = const [],
  });

  final int id;
  final String returnNo;
  final int saleId;
  final int? customerId;
  final int totalCentimes;
  final String refundMethod;
  final String? note;
  final String businessDate;
  final int createdAt;
  final List<ReturnLine> lines;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'return_no': returnNo,
    'sale_id': saleId,
    'customer_id': customerId,
    'total_centimes': totalCentimes,
    'refund_method': refundMethod,
    'note': note,
    'business_date': businessDate,
    'created_at': createdAt,
  };

  factory SaleReturn.fromMap(Map<String, Object?> m) => SaleReturn(
    id: asIntOr(m['id'], 0),
    returnNo: asString(m['return_no']) ?? '',
    saleId: asIntOr(m['sale_id'], 0),
    customerId: asInt(m['customer_id']),
    totalCentimes: asIntOr(m['total_centimes'], 0),
    refundMethod: asString(m['refund_method']) ?? 'cash',
    note: asString(m['note']),
    businessDate: asString(m['business_date']) ?? '',
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class PurchaseLine {
  const PurchaseLine({
    this.id = 0,
    this.purchaseId = 0,
    this.productId,
    required this.productName,
    this.unitName = '',
    this.factorMilli = Qty.milliPerUnit,
    required this.qtyMilli,
    required this.unitCostCentimes,
    required this.lineTotalCentimes,
    this.expiryDate,
    this.batchNo,
    this.batchId,
  });

  final int id;
  final int purchaseId;
  final int? productId;
  final String productName;
  final String unitName;
  final int factorMilli;
  final int qtyMilli;
  final int unitCostCentimes;
  final int lineTotalCentimes;
  final String? expiryDate;
  final String? batchNo;
  final int? batchId;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'purchase_id': purchaseId,
    'product_id': productId,
    'product_name': productName,
    'unit_name': unitName,
    'factor_milli': factorMilli,
    'qty_milli': qtyMilli,
    'unit_cost_centimes': unitCostCentimes,
    'line_total_centimes': lineTotalCentimes,
    'expiry_date': expiryDate,
    'batch_no': batchNo,
    'batch_id': batchId,
  };

  factory PurchaseLine.fromMap(Map<String, Object?> m) => PurchaseLine(
    id: asIntOr(m['id'], 0),
    purchaseId: asIntOr(m['purchase_id'], 0),
    productId: asInt(m['product_id']),
    productName: asString(m['product_name']) ?? '',
    unitName: asString(m['unit_name']) ?? '',
    factorMilli: asIntOr(m['factor_milli'], Qty.milliPerUnit),
    qtyMilli: asIntOr(m['qty_milli'], 0),
    unitCostCentimes: asIntOr(m['unit_cost_centimes'], 0),
    lineTotalCentimes: asIntOr(m['line_total_centimes'], 0),
    expiryDate: asString(m['expiry_date']),
    batchNo: asString(m['batch_no']),
    batchId: asInt(m['batch_id']),
  );
}

class Purchase {
  const Purchase({
    this.id = 0,
    required this.refNo,
    this.supplierId,
    this.supplierName,
    required this.subtotalCentimes,
    required this.discountCentimes,
    required this.totalCentimes,
    required this.paidCentimes,
    required this.dueCentimes,
    required this.paymentMethod,
    this.status = 'completed',
    this.note,
    required this.businessDate,
    required this.createdAt,
    this.voidedAt,
    this.voidReason,
    this.lines = const [],
  });

  final int id;
  final String refNo;
  final int? supplierId;
  final String? supplierName;
  final int subtotalCentimes;
  final int discountCentimes;
  final int totalCentimes;
  final int paidCentimes;
  final int dueCentimes;
  final String paymentMethod;
  final String status;
  final String? note;
  final String businessDate;
  final int createdAt;
  final int? voidedAt;
  final String? voidReason;
  final List<PurchaseLine> lines;

  bool get isVoided => status == 'voided';

  Purchase copyWith({List<PurchaseLine>? lines}) => Purchase(
    id: id,
    refNo: refNo,
    supplierId: supplierId,
    supplierName: supplierName,
    subtotalCentimes: subtotalCentimes,
    discountCentimes: discountCentimes,
    totalCentimes: totalCentimes,
    paidCentimes: paidCentimes,
    dueCentimes: dueCentimes,
    paymentMethod: paymentMethod,
    status: status,
    note: note,
    businessDate: businessDate,
    createdAt: createdAt,
    voidedAt: voidedAt,
    voidReason: voidReason,
    lines: lines ?? this.lines,
  );

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'ref_no': refNo,
    'supplier_id': supplierId,
    'supplier_name': supplierName,
    'subtotal_centimes': subtotalCentimes,
    'discount_centimes': discountCentimes,
    'total_centimes': totalCentimes,
    'paid_centimes': paidCentimes,
    'due_centimes': dueCentimes,
    'payment_method': paymentMethod,
    'status': status,
    'note': note,
    'business_date': businessDate,
    'created_at': createdAt,
    'voided_at': voidedAt,
    'void_reason': voidReason,
  };

  factory Purchase.fromMap(Map<String, Object?> m) => Purchase(
    id: asIntOr(m['id'], 0),
    refNo: asString(m['ref_no']) ?? '',
    supplierId: asInt(m['supplier_id']),
    supplierName: asString(m['supplier_name']),
    subtotalCentimes: asIntOr(m['subtotal_centimes'], 0),
    discountCentimes: asIntOr(m['discount_centimes'], 0),
    totalCentimes: asIntOr(m['total_centimes'], 0),
    paidCentimes: asIntOr(m['paid_centimes'], 0),
    dueCentimes: asIntOr(m['due_centimes'], 0),
    paymentMethod: asString(m['payment_method']) ?? 'cash',
    status: asString(m['status']) ?? 'completed',
    note: asString(m['note']),
    businessDate: asString(m['business_date']) ?? '',
    createdAt: asIntOr(m['created_at'], 0),
    voidedAt: asInt(m['voided_at']),
    voidReason: asString(m['void_reason']),
  );
}

class Payment {
  const Payment({
    this.id = 0,
    required this.partyType,
    required this.partyId,
    required this.direction,
    required this.amountCentimes,
    required this.method,
    this.reference,
    this.note,
    required this.businessDate,
    required this.createdAt,
    this.saleId,
    this.purchaseId,
    this.returnId,
  });

  final int id;
  final String partyType; // customer | supplier
  final int partyId;
  final String direction; // in | out
  final int amountCentimes;
  final String method;
  final String? reference;
  final String? note;
  final String businessDate;
  final int createdAt;
  final int? saleId;
  final int? purchaseId;
  final int? returnId;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'party_type': partyType,
    'party_id': partyId,
    'direction': direction,
    'amount_centimes': amountCentimes,
    'method': method,
    'reference': reference,
    'note': note,
    'business_date': businessDate,
    'created_at': createdAt,
    'sale_id': saleId,
    'purchase_id': purchaseId,
    'return_id': returnId,
  };

  factory Payment.fromMap(Map<String, Object?> m) => Payment(
    id: asIntOr(m['id'], 0),
    partyType: asString(m['party_type']) ?? 'customer',
    partyId: asIntOr(m['party_id'], 0),
    direction: asString(m['direction']) ?? 'in',
    amountCentimes: asIntOr(m['amount_centimes'], 0),
    method: asString(m['method']) ?? 'cash',
    reference: asString(m['reference']),
    note: asString(m['note']),
    businessDate: asString(m['business_date']) ?? '',
    createdAt: asIntOr(m['created_at'], 0),
    saleId: asInt(m['sale_id']),
    purchaseId: asInt(m['purchase_id']),
    returnId: asInt(m['return_id']),
  );
}

class Expense {
  const Expense({
    this.id = 0,
    required this.category,
    required this.amountCentimes,
    required this.method,
    this.note,
    required this.businessDate,
    required this.createdAt,
  });

  final int id;
  final String category;
  final int amountCentimes;
  final String method;
  final String? note;
  final String businessDate;
  final int createdAt;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'category': category,
    'amount_centimes': amountCentimes,
    'method': method,
    'note': note,
    'business_date': businessDate,
    'created_at': createdAt,
  };

  factory Expense.fromMap(Map<String, Object?> m) => Expense(
    id: asIntOr(m['id'], 0),
    category: asString(m['category']) ?? '',
    amountCentimes: asIntOr(m['amount_centimes'], 0),
    method: asString(m['method']) ?? 'cash',
    note: asString(m['note']),
    businessDate: asString(m['business_date']) ?? '',
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class CashSession {
  const CashSession({
    this.id = 0,
    required this.openedAt,
    this.closedAt,
    required this.openingCashCentimes,
    this.expectedCashCentimes,
    this.countedCashCentimes,
    this.differenceCentimes,
    this.note,
    this.status = 'open',
  });

  final int id;
  final int openedAt;
  final int? closedAt;
  final int openingCashCentimes;
  final int? expectedCashCentimes;
  final int? countedCashCentimes;
  final int? differenceCentimes;
  final String? note;
  final String status;

  Map<String, Object?> toMap() => {
    if (id > 0) 'id': id,
    'opened_at': openedAt,
    'closed_at': closedAt,
    'opening_cash_centimes': openingCashCentimes,
    'expected_cash_centimes': expectedCashCentimes,
    'counted_cash_centimes': countedCashCentimes,
    'difference_centimes': differenceCentimes,
    'note': note,
    'status': status,
  };

  factory CashSession.fromMap(Map<String, Object?> m) => CashSession(
    id: asIntOr(m['id'], 0),
    openedAt: asIntOr(m['opened_at'], 0),
    closedAt: asInt(m['closed_at']),
    openingCashCentimes: asIntOr(m['opening_cash_centimes'], 0),
    expectedCashCentimes: asInt(m['expected_cash_centimes']),
    countedCashCentimes: asInt(m['counted_cash_centimes']),
    differenceCentimes: asInt(m['difference_centimes']),
    note: asString(m['note']),
    status: asString(m['status']) ?? 'open',
  );
}

class StockMovement {
  const StockMovement({
    this.id = 0,
    required this.productId,
    this.productName,
    required this.type,
    required this.qtyDeltaMilli,
    this.unitCostCentimes = 0,
    this.refType,
    this.refId,
    this.reason,
    required this.createdAt,
  });

  final int id;
  final int productId;
  final String? productName;
  final String type;
  final int qtyDeltaMilli;
  final int unitCostCentimes;
  final String? refType;
  final int? refId;
  final String? reason;
  final int createdAt;

  factory StockMovement.fromMap(Map<String, Object?> m) => StockMovement(
    id: asIntOr(m['id'], 0),
    productId: asIntOr(m['product_id'], 0),
    productName: asString(m['product_name']),
    type: asString(m['type']) ?? 'adjustment',
    qtyDeltaMilli: asIntOr(m['qty_delta_milli'], 0),
    unitCostCentimes: asIntOr(m['unit_cost_centimes'], 0),
    refType: asString(m['ref_type']),
    refId: asInt(m['ref_id']),
    reason: asString(m['reason']),
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class ExpiringBatch {
  const ExpiringBatch({
    this.id = 0,
    required this.productId,
    required this.productName,
    this.expiryDate,
    this.qtyRemainingMilli = 0,
    this.baseUnit = 'piece',
    this.batchNo,
  });

  final int id;
  final int productId;
  final String productName;
  final String? expiryDate;
  final int qtyRemainingMilli;
  final String baseUnit;
  final String? batchNo;

  factory ExpiringBatch.fromMap(Map<String, Object?> m) => ExpiringBatch(
    id: asIntOr(m['id'], 0),
    productId: asIntOr(m['product_id'], 0),
    productName: asString(m['product_name']) ?? '',
    expiryDate: asString(m['expiry_date']),
    qtyRemainingMilli: asIntOr(m['qty_remaining_milli'], 0),
    baseUnit: asString(m['base_unit']) ?? 'piece',
    batchNo: asString(m['batch_no']),
  );
}

class LedgerEntry {
  const LedgerEntry({
    this.id = 0,
    required this.partyType,
    required this.partyId,
    required this.entryType,
    required this.amountCentimes,
    this.refType,
    this.refId,
    this.note,
    required this.createdAt,
  });

  final int id;
  final String partyType;
  final int partyId;
  final String entryType;
  final int amountCentimes;
  final String? refType;
  final int? refId;
  final String? note;
  final int createdAt;

  factory LedgerEntry.fromMap(Map<String, Object?> m) => LedgerEntry(
    id: asIntOr(m['id'], 0),
    partyType: asString(m['party_type']) ?? '',
    partyId: asIntOr(m['party_id'], 0),
    entryType: asString(m['entry_type']) ?? '',
    amountCentimes: asIntOr(m['amount_centimes'], 0),
    refType: asString(m['ref_type']),
    refId: asInt(m['ref_id']),
    note: asString(m['note']),
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class AuditEntry {
  const AuditEntry({
    this.id = 0,
    required this.action,
    required this.entity,
    this.entityId,
    this.detailsJson,
    this.reason,
    required this.createdAt,
  });

  final int id;
  final String action;
  final String entity;
  final int? entityId;
  final String? detailsJson;
  final String? reason;
  final int createdAt;

  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
    id: asIntOr(m['id'], 0),
    action: asString(m['action']) ?? '',
    entity: asString(m['entity']) ?? '',
    entityId: asInt(m['entity_id']),
    detailsJson: asString(m['details_json']),
    reason: asString(m['reason']),
    createdAt: asIntOr(m['created_at'], 0),
  );
}

class CatalogCandidate {
  const CatalogCandidate({
    required this.barcode,
    required this.name,
    this.nameAr,
    this.brand,
    this.quantityText,
    this.category,
    this.imageUrl,
    required this.source,
    this.rawJson,
  });

  final String barcode;
  final String name;
  final String? nameAr;
  final String? brand;
  final String? quantityText;
  final String? category;
  final String? imageUrl;
  final String source;
  final String? rawJson;

  bool get hasUsefulData => name.trim().isNotEmpty;

  Map<String, Object?> toJsonMap() => {
    'barcode': barcode,
    'name': name,
    'name_ar': nameAr,
    'brand': brand,
    'quantity': quantityText,
    'category': category,
    'image_url': imageUrl,
    'source': source,
  };

  factory CatalogCandidate.fromJsonMap(Map<String, Object?> m) =>
      CatalogCandidate(
        barcode: asString(m['barcode']) ?? '',
        name: asString(m['name']) ?? '',
        nameAr: asString(m['name_ar']),
        brand: asString(m['brand']),
        quantityText: asString(m['quantity']),
        category: asString(m['category']),
        imageUrl: asString(m['image_url']),
        source: asString(m['source']) ?? 'unknown',
        rawJson: asString(m['raw_json']),
      );
}
