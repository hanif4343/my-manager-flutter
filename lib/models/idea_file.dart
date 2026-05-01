class IdeaFile {
  final int? id;
  final int ideaId;
  final int projectId;
  final String name;
  final String type; // text, image
  final String? content;
  final int version;
  final int createdAt;
  final int updatedAt;

  IdeaFile({
    this.id,
    required this.ideaId,
    required this.projectId,
    required this.name,
    required this.type,
    this.content,
    this.version = 1,
    required this.createdAt,
    required this.updatedAt,
  });

  String get ext {
    final parts = name.split('.');
    return parts.length > 1 ? parts.last.toLowerCase() : '';
  }

  String get baseName {
    final parts = name.split('.');
    if (parts.length > 1) {
      return parts.sublist(0, parts.length - 1).join('.');
    }
    return name;
  }

  bool get isImage => ['png', 'jpg', 'jpeg', 'gif', 'webp', 'svg'].contains(ext);
  bool get isText => !isImage;

  int get lineCount => content?.split('\n').length ?? 0;

  factory IdeaFile.fromMap(Map<String, dynamic> m) => IdeaFile(
        id: m['id'],
        ideaId: m['idea_id'],
        projectId: m['project_id'],
        name: m['name'],
        type: m['type'],
        content: m['content'],
        version: m['version'] ?? 1,
        createdAt: m['created_at'],
        updatedAt: m['updated_at'],
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'idea_id': ideaId,
        'project_id': projectId,
        'name': name,
        'type': type,
        'content': content,
        'version': version,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  IdeaFile copyWith({
    int? id, int? ideaId, int? projectId, String? name,
    String? type, String? content, int? version,
    int? createdAt, int? updatedAt,
  }) => IdeaFile(
        id: id ?? this.id,
        ideaId: ideaId ?? this.ideaId,
        projectId: projectId ?? this.projectId,
        name: name ?? this.name,
        type: type ?? this.type,
        content: content ?? this.content,
        version: version ?? this.version,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
