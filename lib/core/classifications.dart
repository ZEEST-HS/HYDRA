/// The two top-level product divisions required by the shop classification.
///
/// Categories (subcategories) always belong to one of these divisions. The
/// division is stored as a short stable code in SQLite.
enum ProductDivision {
  food('food'),
  nonFood('non_food');

  const ProductDivision(this.code);

  final String code;

  bool get isFood => this == ProductDivision.food;

  static ProductDivision? fromCode(String? code) {
    switch (code) {
      case 'food':
        return ProductDivision.food;
      case 'non_food':
        return ProductDivision.nonFood;
      default:
        return null;
    }
  }
}

/// A predefined subcategory. [nameFr] is used for CSV/PDF compatibility while
/// [nameAr] is the primary label in the Arabic interface.
class SubcategorySeed {
  const SubcategorySeed({
    required this.nameFr,
    required this.nameAr,
    this.examples = const [],
  });

  final String nameFr;
  final String nameAr;
  final List<String> examples;
}

/// Predefined food subcategories, in display order.
const foodSubcategories = <SubcategorySeed>[
  SubcategorySeed(
    nameFr: 'Huiles et matières grasses',
    nameAr: 'الزيوت والدهون',
  ),
  SubcategorySeed(nameFr: 'Boissons', nameAr: 'المشروبات'),
  SubcategorySeed(nameFr: 'Pain et dérivés', nameAr: 'الخبز ومشتقاته'),
  SubcategorySeed(nameFr: 'Lait et dérivés', nameAr: 'الحليب ومشتقاته'),
  SubcategorySeed(
    nameFr: 'Produits alimentaires de base',
    nameAr: 'المواد الغذائية الأساسية',
  ),
  SubcategorySeed(nameFr: 'Conserves', nameAr: 'المعلبات والمصبرات'),
  SubcategorySeed(
    nameFr: 'Confiserie et snacks',
    nameAr: 'الحلويات والوجبات الخفيفة',
  ),
  SubcategorySeed(
    nameFr: 'Œufs et produits frais',
    nameAr: 'البيض والمنتجات الطازجة',
  ),
  SubcategorySeed(
    nameFr: 'Autres produits alimentaires',
    nameAr: 'مواد غذائية أخرى',
  ),
];

/// Predefined non-food subcategories, in display order.
const nonFoodSubcategories = <SubcategorySeed>[
  SubcategorySeed(nameFr: 'Produits de nettoyage', nameAr: 'مواد التنظيف'),
  SubcategorySeed(
    nameFr: 'Hygiène et soins personnels',
    nameAr: 'النظافة والعناية الشخصية',
  ),
  SubcategorySeed(nameFr: 'Papier', nameAr: 'الورقيات'),
  SubcategorySeed(
    nameFr: 'Articles maison et cuisine',
    nameAr: 'لوازم المنزل والمطبخ',
  ),
  SubcategorySeed(nameFr: 'Produits pour bébés', nameAr: 'منتجات الأطفال'),
  SubcategorySeed(nameFr: 'Outils et divers', nameAr: 'أدوات ومنتجات متنوعة'),
  SubcategorySeed(
    nameFr: 'Autres produits non alimentaires',
    nameAr: 'منتجات أخرى غير غذائية',
  ),
];

List<SubcategorySeed> subcategoriesFor(ProductDivision division) =>
    division == ProductDivision.food ? foodSubcategories : nonFoodSubcategories;

/// Display label for a division, independent of the active locale.
String divisionName(ProductDivision division, {required bool arabic}) => arabic
    ? (division == ProductDivision.food ? 'الأكل' : 'غير الأكل')
    : (division == ProductDivision.food ? 'Alimentation' : 'Non alimentaire');
