import 'package:flutter_test/flutter_test.dart';
import 'package:hydra_pos/core/classifications.dart';
import 'package:hydra_pos/core/errors.dart';
import 'package:hydra_pos/data/models/models.dart';

import '../helpers/test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestEnv env;

  setUp(() async {
    env = await TestEnv.memory();
  });

  tearDown(() async {
    await env.close();
  });

  Future<Product> product(String name, {int? categoryId}) {
    return env.products.create(Product(name: name, categoryId: categoryId));
  }

  test('fresh install seeds the 16 locked subcategories', () async {
    final food = await env.products.categoriesForDivision(
      ProductDivision.food.code,
    );
    final nonFood = await env.products.categoriesForDivision(
      ProductDivision.nonFood.code,
    );
    expect(food, hasLength(foodSubcategories.length));
    expect(nonFood, hasLength(nonFoodSubcategories.length));
    expect(await env.products.categories(), hasLength(16));
    expect(food.every((c) => c.isSystem), isTrue);
    expect(food.first.nameAr, isNotNull);
  });

  test('custom subcategories can be added, renamed and moved', () async {
    final id = await env.products.addCategory(
      'Bio',
      'عضوي',
      division: ProductDivision.food.code,
    );
    var created = (await env.products.categories(division: 'food'))
        .firstWhere((c) => c.id == id);
    expect(created.nameFr, 'Bio');
    expect(created.isSystem, isFalse);

    await env.products.renameCategory(
      id,
      nameFr: 'Bio local',
      nameAr: 'عضوي محلي',
    );
    created = (await env.products.categories(division: 'food'))
        .firstWhere((c) => c.id == id);
    expect(created.nameFr, 'Bio local');
    expect(created.nameAr, 'عضوي محلي');

    await env.products.setCategoryDivision(id, ProductDivision.nonFood.code);
    final moved = await env.products.categoriesForDivision('non_food');
    expect(moved.any((c) => c.id == id), isTrue);
    final food = await env.products.categoriesForDivision('food');
    expect(food.any((c) => c.id == id), isFalse);
  });

  test('predefined subcategories are locked', () async {
    final system = (await env.products.categoriesForDivision('food')).first;
    await expectLater(
      env.products.renameCategory(system.id, nameFr: 'Autre nom'),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.products.deleteCategory(system.id),
      throwsA(isA<ValidationError>()),
    );
    await expectLater(
      env.products.setCategoryDivision(system.id, 'non_food'),
      throwsA(isA<ValidationError>()),
    );
  });

  test('deleting a custom subcategory reassigns its products', () async {
    final source = await env.products.addCategory(
      'Temporaire',
      null,
      division: 'food',
    );
    final target = (await env.products.categoriesForDivision('food')).first;
    final created = await product('Riz', categoryId: source);
    expect(await env.products.countInCategory(source), 1);

    await env.products.deleteCategory(source, targetCategoryId: target.id);

    final remaining = await env.products.findById(created.id);
    expect(remaining, isNotNull);
    expect(remaining!.categoryId, target.id);
    expect(await env.products.countInCategory(source), 0);
    expect(await env.products.countInCategory(target.id), 1);
  });

  test('deleting without a target leaves products unclassified', () async {
    final source = await env.products.addCategory(
      'Divers',
      null,
      division: 'food',
    );
    final created = await product('Éponge', categoryId: source);

    await env.products.deleteCategory(source);

    final remaining = await env.products.findById(created.id);
    expect(remaining, isNotNull);
    expect(remaining!.categoryId, isNull);
    expect(await env.products.countUnclassified(), 1);
    expect(
      (await env.products.search('', unclassifiedOnly: true)).single.id,
      created.id,
    );
  });

  test('merging moves products and removes the source category', () async {
    final source = await env.products.addCategory(
      'Snacks',
      null,
      division: 'food',
    );
    final target = (await env.products.categoriesForDivision('food')).first;
    final created = await product('Chips', categoryId: source);

    await env.products.mergeCategory(source, target.id);

    final remaining = await env.products.findById(created.id);
    expect(remaining!.categoryId, target.id);
    final ids = (await env.products.categories()).map((c) => c.id);
    expect(ids.contains(source), isFalse);
  });

  test('duplicate names inside the same division are rejected', () async {
    await env.products.addCategory('Bio', null, division: 'food');
    await expectLater(
      env.products.addCategory('bio', null, division: 'food'),
      throwsA(isA<ConflictError>()),
    );
    // The same name in the other division is allowed.
    final id = await env.products.addCategory(
      'Bio',
      null,
      division: 'non_food',
    );
    expect(id, greaterThan(0));
  });

  test('products can be filtered by division', () async {
    final food = (await env.products.categoriesForDivision('food')).first;
    final nonFood = (await env.products.categoriesForDivision('non_food'))
        .first;
    await product('Lait', categoryId: food.id);
    await product('Savon', categoryId: nonFood.id);

    final foodProducts = await env.products.search('', division: 'food');
    expect(foodProducts.single.name, 'Lait');
    final nonFoodProducts = await env.products.search('', division: 'non_food');
    expect(nonFoodProducts.single.name, 'Savon');
    final counts = await env.products.divisionCounts();
    expect(counts['food'], 1);
    expect(counts['non_food'], 1);
  });
}
