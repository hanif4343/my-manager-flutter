/// একটা আবশ্যিক খরচ — যেমন বাসাভাড়া, কিস্তি, বিদ্যুৎ বিল, টিউশন ফি।
///
/// "ঠিক আছে" চাপলে খাতায় এই পরিমাণ খরচ হিসেবে নিজে লেখা হয় (ক্যাশ কমে)।
/// [monthly] হলে প্রতি মাসে আবার বাকি হয়ে ফিরে আসে; না হলে একবার মেটালেই শেষ।
class CashbookEssential {
  final int? id;
  final String title;
  final double amount;
  final int dueDay; // মাসের কত তারিখের মধ্যে (০ = নির্দিষ্ট নেই)
  final String category; // খাতায় যে ক্যাটাগরিতে খরচ লেখা হবে
  final bool monthly;
  final String? paidMonth; // 'YYYY-MM' — শেষ কোন মাসে মেটানো হয়েছে
  final int? entryId; // মেটানোর সময় খাতায় যে খরচ-এন্ট্রি লেখা হয়েছে
  final int createdAt;

  const CashbookEssential({
    this.id,
    required this.title,
    required this.amount,
    this.dueDay = 0,
    this.category = 'bill',
    this.monthly = true,
    this.paidMonth,
    this.entryId,
    required this.createdAt,
  });

  /// [mk] ('YYYY-MM') মাসে কি এটা মেটানো হয়ে গেছে?
  bool paidIn(String mk) => paidMonth == mk;

  /// [mk] মাসের তালিকায় দেখাবে কি? একবারের খরচ আগের মাসে মেটানো হলে আর দেখায় না।
  bool visibleIn(String mk) => monthly || paidMonth == null || paidMonth == mk;

  /// [mk] মাসে এখনও বাকি?
  bool unpaidIn(String mk) => visibleIn(mk) && paidMonth != mk;

  factory CashbookEssential.fromMap(Map<String, dynamic> m) => CashbookEssential(
        id: m['id'] as int?,
        title: m['title'] as String,
        amount: (m['amount'] as num).toDouble(),
        dueDay: (m['due_day'] as num?)?.toInt() ?? 0,
        category: (m['category'] as String?) ?? 'bill',
        monthly: ((m['monthly'] as num?) ?? 1) == 1,
        paidMonth: m['paid_month'] as String?,
        entryId: (m['entry_id'] as num?)?.toInt(),
        createdAt: (m['created_at'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'amount': amount,
        'due_day': dueDay,
        'category': category,
        'monthly': monthly ? 1 : 0,
        'paid_month': paidMonth,
        'entry_id': entryId,
        'created_at': createdAt,
      };

  CashbookEssential copyWith({
    String? title,
    double? amount,
    int? dueDay,
    String? category,
    bool? monthly,
  }) =>
      CashbookEssential(
        id: id,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        dueDay: dueDay ?? this.dueDay,
        category: category ?? this.category,
        monthly: monthly ?? this.monthly,
        paidMonth: paidMonth,
        entryId: entryId,
        createdAt: createdAt,
      );
}
