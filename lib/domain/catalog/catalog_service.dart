import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../core/dates.dart';
import '../../core/db/app_database.dart';
import '../../data/models/models.dart';
import '../../integrations/catalog/catalog_providers.dart';

class CatalogLookupResult {
  const CatalogLookupResult({
    this.candidate,
    this.fromCache = false,
    this.offline = false,
    this.message,
    this.providerName,
  });

  final CatalogCandidate? candidate;
  final bool fromCache;
  final bool offline;
  final String? message;
  final String? providerName;

  bool get found => candidate != null;
}

/// Coordinates providers, rate limiting, negative caching and offline
/// fallback. It never writes to products, prices or stock.
class CatalogService {
  CatalogService(
    this.appDb, {
    List<CatalogProvider>? providers,
    this.userAgentContact = '',
  }) : providers =
           providers ?? [OpenFoodFactsProvider(), OpenProductsFactsProvider()];

  final AppDatabase appDb;
  final List<CatalogProvider> providers;
  final String userAgentContact;

  static const _foundTtl = Duration(days: 30);
  static const _missingTtl = Duration(days: 7);
  DateTime? _lastNetworkCall;

  Future<CatalogLookupResult> lookup(
    String rawBarcode, {
    bool forceRefresh = false,
  }) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty) {
      return const CatalogLookupResult(message: 'Code-barres vide.');
    }
    if (!forceRefresh) {
      final cached = await _readCache(barcode);
      if (cached != null && _isFresh(cached)) {
        if ((cached['found'] as num).toInt() == 1) {
          final payload = cached['payload_json'] as String?;
          if (payload != null) {
            final json = jsonDecode(payload);
            if (json is Map<String, dynamic>) {
              return CatalogLookupResult(
                candidate: CatalogCandidate.fromJsonMap(json),
                fromCache: true,
                providerName: cached['source'] as String?,
              );
            }
          }
        } else {
          return const CatalogLookupResult(fromCache: true);
        }
      }
    }

    await _throttle();
    var networkError = false;
    String? lastError;
    for (final provider in providers) {
      try {
        final candidate = await provider.lookup(barcode);
        _lastNetworkCall = DateTime.now();
        if (candidate != null && candidate.hasUsefulData) {
          await _writeCache(barcode, provider.id, candidate);
          return CatalogLookupResult(
            candidate: candidate,
            providerName: provider.displayName,
          );
        }
      } on TimeoutException {
        networkError = true;
        lastError = 'Délai dépassé.';
      } on SocketException {
        networkError = true;
        lastError = 'Pas de connexion Internet.';
      } on HttpException {
        networkError = true;
        lastError = 'Connexion interrompue.';
      } catch (e) {
        networkError = true;
        lastError = e.toString();
      }
    }
    _lastNetworkCall = DateTime.now();

    if (networkError) {
      // Offline fallback: an expired cached hit is still better than nothing.
      final stale = await _readCache(barcode);
      if (stale != null && (stale['found'] as num).toInt() == 1) {
        final payload = stale['payload_json'] as String?;
        if (payload != null) {
          final json = jsonDecode(payload);
          if (json is Map<String, dynamic>) {
            return CatalogLookupResult(
              candidate: CatalogCandidate.fromJsonMap(json),
              fromCache: true,
              offline: true,
              message: lastError ?? 'Hors ligne',
              providerName: stale['source'] as String?,
            );
          }
        }
      }
      return CatalogLookupResult(
        offline: true,
        message: lastError ?? 'Pas de connexion Internet.',
      );
    }

    await _writeCache(barcode, providers.first.id, null);
    return const CatalogLookupResult();
  }

  Future<void> _throttle() async {
    final last = _lastNetworkCall;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      if (elapsed < const Duration(milliseconds: 900)) {
        await Future<void>.delayed(const Duration(milliseconds: 900) - elapsed);
      }
    }
  }

  Future<Map<String, Object?>?> _readCache(String barcode) async {
    final rows = await appDb.db.query(
      'catalog_cache',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  bool _isFresh(Map<String, Object?> row) {
    final found = (row['found'] as num).toInt() == 1;
    final fetched = (row['fetched_at'] as num).toInt();
    final age = DateTime.now().millisecondsSinceEpoch - fetched;
    return age <= (found ? _foundTtl : _missingTtl).inMilliseconds;
  }

  Future<void> _writeCache(
    String barcode,
    String source,
    CatalogCandidate? candidate,
  ) async {
    await appDb.db.insert('catalog_cache', {
      'barcode': barcode,
      'source': source,
      'found': candidate == null ? 0 : 1,
      'payload_json': candidate == null
          ? null
          : jsonEncode(candidate.toJsonMap()),
      'fetched_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearCache() async {
    await appDb.db.delete('catalog_cache');
  }

  Future<int> cacheCount() async {
    final rows = await appDb.db.rawQuery(
      'SELECT COUNT(*) AS c FROM catalog_cache',
    );
    return (rows.first['c'] as num).toInt();
  }

  String providerName(String? id) {
    if (id == null) return '';
    return providers
        .firstWhere((p) => p.id == id, orElse: () => _LabelProvider(id))
        .displayName;
  }

  void dispose() {
    for (final provider in providers) {
      provider.close();
    }
  }
}

class _LabelProvider implements CatalogProvider {
  _LabelProvider(this.id);
  @override
  final String id;
  @override
  String get displayName => id;
  @override
  String get attribution => '';
  @override
  Uri get website => Uri.parse('https://world.openfoodfacts.org');
  @override
  Future<CatalogCandidate?> lookup(String barcode) async => null;
  @override
  void close() {}
}

/// Attribution text shown in Settings/About.
String catalogAttributions() => [
  'Open Food Facts — données ouvertes sous ODbL. '
      'https://world.openfoodfacts.org',
  'Open Products Facts — données ouvertes sous ODbL. '
      'https://world.openproductsfacts.org',
].join('\n');

/// Small helper kept public for tests: cache expiry timestamps.
int catalogFetchedAtNow() => Dates.nowMillis();
