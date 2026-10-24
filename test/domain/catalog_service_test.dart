import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/data/models/models.dart';
import 'package:hydra_pos/domain/catalog/catalog_service.dart';
import 'package:hydra_pos/integrations/catalog/catalog_providers.dart';

import '../helpers/test_env.dart';

class FakeProvider implements CatalogProvider {
  FakeProvider({this.candidate, this.error, this.id = 'fake'});

  final CatalogCandidate? candidate;
  final Object? error;
  int calls = 0;
  bool closed = false;

  @override
  final String id;

  @override
  String get displayName => 'Fake catalog';

  @override
  String get attribution => 'Fake data';

  @override
  Uri get website => Uri.parse('https://example.test');

  @override
  Future<CatalogCandidate?> lookup(String barcode) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return candidate;
  }

  @override
  void close() => closed = true;
}

CatalogCandidate candidateFor(String barcode) => CatalogCandidate(
  barcode: barcode,
  name: 'Lait Centrale 1L',
  nameAr: 'حليب سنترال',
  brand: 'Centrale',
  quantityText: '1 L',
  category: 'Produits laitiers',
  imageUrl: 'https://example.test/lait.jpg',
  source: 'fake',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;

  setUp(() async {
    env = await TestEnv.memory();
  });

  tearDown(() async {
    await env.close();
  });

  test(
    'first lookup calls the provider and the second uses the cache',
    () async {
      final provider = FakeProvider(candidate: candidateFor('6111245100059'));
      final catalog = CatalogService(env.db, providers: [provider]);
      addTearDown(catalog.dispose);

      final first = await catalog.lookup('6111245100059');
      expect(first.found, isTrue);
      expect(first.fromCache, isFalse);
      expect(first.offline, isFalse);
      expect(first.candidate!.name, 'Lait Centrale 1L');
      expect(first.candidate!.nameAr, 'حليب سنترال');
      expect(provider.calls, 1);

      final second = await catalog.lookup('6111245100059');
      expect(second.found, isTrue);
      expect(second.fromCache, isTrue);
      expect(second.candidate!.brand, 'Centrale');
      expect(provider.calls, 1, reason: 'cache must avoid a network call');
      expect(await catalog.cacheCount(), 1);
    },
  );

  test('not-found results are cached for the negative TTL', () async {
    final provider = FakeProvider();
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    final first = await catalog.lookup('0000000000000');
    expect(first.found, isFalse);
    expect(first.fromCache, isFalse);
    expect(provider.calls, 1);

    final second = await catalog.lookup('0000000000000');
    expect(second.found, isFalse);
    expect(second.fromCache, isTrue);
    expect(provider.calls, 1);

    final rows = await env.db.db.query('catalog_cache');
    expect(rows.single['found'], 0);
    expect(rows.single['payload_json'], isNull);
  });

  test('forceRefresh bypasses a fresh cache entry', () async {
    final provider = FakeProvider(candidate: candidateFor('6111'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    await catalog.lookup('6111');
    await catalog.lookup('6111', forceRefresh: true);
    expect(provider.calls, 2);
  });

  test('falls back to a stale cached product when offline', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await env.db.db.insert('catalog_cache', {
      'barcode': '6111245100059',
      'source': 'fake',
      'found': 1,
      'payload_json': jsonEncode(candidateFor('6111245100059').toJsonMap()),
      'fetched_at': now - const Duration(days: 31).inMilliseconds,
    });

    final provider = FakeProvider(error: const SocketException('offline'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    final result = await catalog.lookup('6111245100059');
    expect(result.found, isTrue);
    expect(result.fromCache, isTrue);
    expect(result.offline, isTrue);
    expect(result.message, 'Pas de connexion Internet.');
    expect(result.candidate!.name, 'Lait Centrale 1L');
    expect(provider.calls, 1);
  });

  test('reports offline without a cache hit', () async {
    final provider = FakeProvider(error: const SocketException('offline'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    final result = await catalog.lookup('6111111111111');
    expect(result.found, isFalse);
    expect(result.offline, isTrue);
    expect(result.message, 'Pas de connexion Internet.');
  });

  test('tries the next provider when the first one fails', () async {
    final failing = FakeProvider(error: const HttpException('boom'));
    final good = FakeProvider(candidate: candidateFor('6112'), id: 'second');
    final catalog = CatalogService(env.db, providers: [failing, good]);
    addTearDown(catalog.dispose);

    final result = await catalog.lookup('6112');
    expect(result.found, isTrue);
    expect(result.providerName, 'Fake catalog');
    expect(failing.calls, 1);
    expect(good.calls, 1);
  });

  test('ignores a provider candidate without a usable name', () async {
    final provider = FakeProvider(
      candidate: const CatalogCandidate(
        barcode: '6113',
        name: '   ',
        source: 'fake',
      ),
    );
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    final result = await catalog.lookup('6113');
    expect(result.found, isFalse);

    final rows = await env.db.db.query('catalog_cache');
    expect(rows.single['found'], 0);
  });

  test('empty barcodes are rejected without calling providers', () async {
    final provider = FakeProvider(candidate: candidateFor('x'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    final result = await catalog.lookup('   ');
    expect(result.found, isFalse);
    expect(result.message, 'Code-barres vide.');
    expect(provider.calls, 0);
  });

  test('clearCache removes all cached lookups', () async {
    final provider = FakeProvider(candidate: candidateFor('6114'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    await catalog.lookup('6114');
    expect(await catalog.cacheCount(), 1);
    await catalog.clearCache();
    expect(await catalog.cacheCount(), 0);
  });

  test('provider names resolve to friendly labels', () async {
    final provider = FakeProvider(candidate: candidateFor('6115'));
    final catalog = CatalogService(env.db, providers: [provider]);
    addTearDown(catalog.dispose);

    expect(catalog.providerName('fake'), 'Fake catalog');
    expect(catalog.providerName('open_food_facts'), 'open_food_facts');
    expect(catalog.providerName(null), '');
  });
}
