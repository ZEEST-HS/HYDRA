/// Business profile chosen during onboarding.
///
/// Both profiles share the same database, services and records. The profile
/// only changes navigation and which shortcuts are shown first.
enum BusinessType {
  smallShop('small'),
  supermarket('supermarket');

  const BusinessType(this.code);

  final String code;

  bool get isSmallShop => this == BusinessType.smallShop;

  static BusinessType fromCode(String? code) {
    return code == 'supermarket'
        ? BusinessType.supermarket
        : BusinessType.smallShop;
  }
}
