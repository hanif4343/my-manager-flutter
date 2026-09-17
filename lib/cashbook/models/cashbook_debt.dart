/// Money owed between the user and someone else — either তারা still owe
/// the user (`lend`) or the user still owes them (`borrow`). Kept
/// separate from the account ledgers since it isn't cash that moved
/// through a wallet yet, just an outstanding promise.
class CashbookDebt {
  final int? id;
  final String name;
  final String type; // 'lend' (আমি পাবো) | 'borrow' (আমি দেনা)
  final double amount;
  final String note;
  final bool cleared;
  final String date; // 'YYYY-MM-DD'
  final int createdAt;

  CashbookDebt({
    this.id,
    required this.name,
    required this.type,
    required this.amount,
    this.note = '',
    this.cleared = false,
    required this.date,
    required this.createdAt,
  });

  factory CashbookDebt.fromMap(Map<String, dynamic> m) => CashbookDebt(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: m['type'] as String,
        amount: (m['amount'] as num).toDouble(),
        note: m['note'] as String? ?? '',
        cleared: (m['cleared'] as int? ?? 0) == 1,
        date: m['date'] as String,
        createdAt: m['created_at'] as int,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type,
        'amount': amount,
        'note': note,
        'cleared': cleared ? 1 : 0,
        'date': date,
        'created_at': createdAt,
      };

  CashbookDebt copyWith({bool? cleared}) => CashbookDebt(
        id: id, name: name, type: type, amount: amount, note: note,
        cleared: cleared ?? this.cleared, date: date, createdAt: createdAt,
      );
}
