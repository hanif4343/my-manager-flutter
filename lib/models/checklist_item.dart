class ChecklistItem {
  final int? id;
  final int ideaId;
  final String text;
  final int done; // 0/1
  final int sortOrder;
  final int createdAt;
  final int updatedAt;

  ChecklistItem({
    this.id, required this.ideaId, required this.text,
    this.done = 0, this.sortOrder = 0,
    required this.createdAt, required this.updatedAt,
  });

  bool get isDone => done == 1;

  factory ChecklistItem.fromMap(Map<String, dynamic> m) => ChecklistItem(
    id: m['id'], ideaId: m['idea_id'], text: m['text'],
    done: m['done'] ?? 0, sortOrder: m['sort_order'] ?? 0,
    createdAt: m['created_at'], updatedAt: m['updated_at'],
  );

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'idea_id': ideaId, 'text': text, 'done': done,
    'sort_order': sortOrder,
    'created_at': createdAt, 'updated_at': updatedAt,
  };

  ChecklistItem copyWith({
    int? id, int? ideaId, String? text, int? done,
    int? sortOrder, int? createdAt, int? updatedAt,
  }) => ChecklistItem(
    id: id ?? this.id, ideaId: ideaId ?? this.ideaId,
    text: text ?? this.text, done: done ?? this.done,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
