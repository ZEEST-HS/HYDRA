import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/errors.dart';
import '../../data/models/models.dart';

/// One external product catalog. Adding a provider must not require changes
/// to sales, purchases or stock code.
abstract class CatalogProvider {
  String get id;
  String get displayName;
  String get attribution;
  Uri get website;

  /// Returns null when the provider has no product for this barcode.
  /// Throws on network/unexpected errors.
  Future<CatalogCandidate?> lookup(String barcode);
  void close();
}

class OpenFoodFactsProvider implements CatalogProvider {
  OpenFoodFactsProvider({
    http.Client? client,
    Uri? baseUri,
    this.userAgent = 'HydraPOS/1.0 (Android; barcode lookup)',
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://world.openfoodfacts.org');

  final http.Client _client;
  final Uri _baseUri;
  final String userAgent;

  @override
  String get id => 'open_food_facts';

  @override
  String get displayName => 'Open Food Facts';

  @override
  String get attribution =>
      'Données Open Food Facts (ODbL) — https://world.openfoodfacts.org';

  @override
  Uri get website => Uri.parse('https://world.openfoodfacts.org');

  @override
  Future<CatalogCandidate?> lookup(String barcode) async {
    if (barcode.trim().isEmpty) return null;
    final uri = _baseUri.replace(
      path: '/api/v3/product/$barcode.json',
      queryParameters: {
        'fields':
            'code,product_name,product_name_fr,product_name_ar,'
            'brands,quantity,categories,image_front_url,image_url',
      },
    );
    final response = await _client
        .get(
          uri,
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 9));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppError(
        'catalog_http',
        'Catalogue indisponible (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw AppError('catalog_format', 'Réponse du catalogue invalide.');
    }
    final product = decoded['product'];
    if (product is! Map<String, dynamic>) return null;
    return _mapProduct(product);
  }

  CatalogCandidate? _mapProduct(Map<String, dynamic> product) {
    final name = _firstNonEmpty([
      product['product_name_fr'],
      product['product_name'],
      product['product_name_ar'],
    ]);
    if (name == null) return null;
    final nameAr =
        (product['product_name_ar']?.toString().trim().isNotEmpty ?? false)
        ? product['product_name_ar'].toString().trim()
        : null;
    final categories = product['categories']?.toString() ?? '';
    final category = categories.split(',').first.trim();
    return CatalogCandidate(
      barcode: product['code']?.toString() ?? '',
      name: name,
      nameAr: nameAr,
      brand: _firstNonEmpty([product['brands']]),
      quantityText: _firstNonEmpty([product['quantity']]),
      category: category.isEmpty ? null : category,
      imageUrl: _firstNonEmpty([
        product['image_front_url'],
        product['image_url'],
      ]),
      source: id,
      rawJson: jsonEncode(product),
    );
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final text = v?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  @override
  void close() => _client.close();
}

class OpenProductsFactsProvider implements CatalogProvider {
  OpenProductsFactsProvider({
    http.Client? client,
    Uri? baseUri,
    this.userAgent = 'HydraPOS/1.0 (Android; barcode lookup)',
  }) : _client = client ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse('https://world.openproductsfacts.org');

  final http.Client _client;
  final Uri _baseUri;
  final String userAgent;

  @override
  String get id => 'open_products_facts';

  @override
  String get displayName => 'Open Products Facts';

  @override
  String get attribution =>
      'Données Open Products Facts (ODbL) — https://world.openproductsfacts.org';

  @override
  Uri get website => Uri.parse('https://world.openproductsfacts.org');

  @override
  Future<CatalogCandidate?> lookup(String barcode) async {
    if (barcode.trim().isEmpty) return null;
    final uri = _baseUri.replace(
      path: '/api/v3/product/$barcode.json',
      queryParameters: {
        'fields':
            'code,product_name,product_name_fr,product_name_ar,'
            'brands,quantity,categories,image_front_url,image_url',
      },
    );
    final response = await _client
        .get(
          uri,
          headers: {'User-Agent': userAgent, 'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 9));
    if (response.statusCode == 404) return null;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AppError(
        'catalog_http',
        'Catalogue indisponible (HTTP ${response.statusCode}).',
      );
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw AppError('catalog_format', 'Réponse du catalogue invalide.');
    }
    final product = decoded['product'];
    if (product is! Map<String, dynamic>) return null;
    final name = _firstNonEmpty([
      product['product_name_fr'],
      product['product_name'],
      product['product_name_ar'],
    ]);
    if (name == null) return null;
    final categories = product['categories']?.toString() ?? '';
    final category = categories.split(',').first.trim();
    return CatalogCandidate(
      barcode: product['code']?.toString() ?? barcode,
      name: name,
      nameAr:
          (product['product_name_ar']?.toString().trim().isNotEmpty ?? false)
          ? product['product_name_ar'].toString().trim()
          : null,
      brand: _firstNonEmpty([product['brands']]),
      quantityText: _firstNonEmpty([product['quantity']]),
      category: category.isEmpty ? null : category,
      imageUrl: _firstNonEmpty([
        product['image_front_url'],
        product['image_url'],
      ]),
      source: id,
      rawJson: jsonEncode(product),
    );
  }

  static String? _firstNonEmpty(List<Object?> values) {
    for (final v in values) {
      final text = v?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  @override
  void close() => _client.close();
}
