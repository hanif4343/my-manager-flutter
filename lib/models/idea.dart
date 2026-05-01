class Idea {
  final int? id;
  final int projectId;
  final String title;
  final String? description;
  final String status; // todo, doing, done
  final String priority; // low, medium, high
  final int createdAt;
  final int updatedAt;

  Idea({
    this.id,
    required this.projectId,
    required this.title,
    this.description,
    this.status = 'todo',
    this.priority = 'medium',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Idea.fromMap(Map<String, dynamic> m) => Idea(
        id: m['id'],
        projectId: m['project_id'],
        title: m['title'],
        description: m['description'],
        status: m['status'] ?? 'todo',
        priority: m['priority'] ?? 'medium',
        createdAt: m['created_at'],
        updatedAt: m['updated_at'],
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'project_id': projectId,
        'title': title,
        'description': description,
        'status': status,
        'priority': priority,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Idea copyWith({
    int? id, int? projectId, String? title, String? description,
    String? status, String? priority, int? createdAt, int? updatedAt,
  }) => Idea(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        title: title ?? this.title,
        description: description ?? this.description,
        status: status ?? this.status,
        priority: priority ?? this.priority,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
