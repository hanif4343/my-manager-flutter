/// A single "হিসাব" (wallet) inside the Cashbook — নগদ, ব্যাংক, বিকাশ, or
/// any custom wallet the user adds. Every entry belongs to exactly one
/// account; balances and the account switcher chips are built from this.
class CashbookAccount {
  final int? id;
  final String name;
  final String icon; // emoji
  final int sortOrder;
  final int createdAt;

  CashbookAccount({
    this.id,
    required this.name,
    required this.icon,
    this.sortOrder = 0,
    required this.createdAt,
  });

  factory CashbookAccount.fromMap(Map<String, dynamic> m) => CashbookAccount(
        id: m['id'] as int?,
        name: m['name'] as String,
        icon: m['icon'] as String? ?? '👛',
        sortOrder: m['sort_order'] as int? ?? 0,
        createdAt: m['created_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'icon': icon,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };
}
