class CashbookCategory {
  final String id;
  final String name;
  final String icon;

  const CashbookCategory({required this.id, required this.name, required this.icon});

  factory CashbookCategory.fromJson(Map<String, dynamic> m) =>
      CashbookCategory(id: m['id'], name: m['name'], icon: m['icon'] ?? '🏷️');

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'icon': icon};
}

/// Categories that exist out of the box. Users can add more from the
/// entry form — those are persisted separately (see CashbookService) and
/// appended after this list, so a fresh install still looks sensible.
const defaultCashbookCategories = [
  CashbookCategory(id: 'salary', name: 'বেতন', icon: '💼'),
  CashbookCategory(id: 'market', name: 'বাজার', icon: '🛒'),
  CashbookCategory(id: 'bill', name: 'বিল', icon: '💡'),
  CashbookCategory(id: 'transport', name: 'যাতায়াত', icon: '🚌'),
  CashbookCategory(id: 'food', name: 'খাবার', icon: '🍽️'),
  CashbookCategory(id: 'other', name: 'অন্যান্য', icon: '📦'),
];
