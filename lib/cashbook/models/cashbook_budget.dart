/// A monthly spending limit for one category, checked against that
/// category's actual খরচ for the current month. Budgets are global
/// (not per-account) — overspending is overspending regardless of which
/// wallet it came out of.
class CashbookBudget {
  final int? id;
  final String category;
  final double monthlyLimit;

  CashbookBudget({this.id, required this.category, required this.monthlyLimit});

  factory CashbookBudget.fromMap(Map<String, dynamic> m) => CashbookBudget(
        id: m['id'] as int?,
        category: m['category'] as String,
        monthlyLimit: (m['monthly_limit'] as num).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'category': category,
        'monthly_limit': monthlyLimit,
      };
}
