import 'dart:ui';
import 'package:flutter/material.dart';

class Project {
  final int? id;
  final String name;
  final String? description;
  final int colorValue;
  final List<String> tags;
  final String status;
  final int createdAt;
  final int updatedAt;

  Project({
    this.id,
    required this.name,
    this.description,
    this.colorValue = 0xFF6366F1,
    this.tags = const [],
    this.status = 'active',
    required this.createdAt,
    required this.updatedAt,
  });

  Color get color => Color(colorValue);

  factory Project.fromMap(Map<String, dynamic> m) => Project(
        id: m['id'],
        name: m['name'],
        description: m['description'],
        colorValue: m['color'] ?? 0xFF6366F1,
        tags: m['tags'] != null && m['tags'].toString().isNotEmpty
            ? m['tags'].toString().split(',')
            : [],
        status: m['status'] ?? 'active',
        createdAt: m['created_at'],
        updatedAt: m['updated_at'],
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'color': colorValue,
        'tags': tags.join(','),
        'status': status,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  Project copyWith({
    int? id, String? name, String? description,
    int? colorValue, List<String>? tags, String? status,
    int? createdAt, int? updatedAt,
  }) => Project(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        colorValue: colorValue ?? this.colorValue,
        tags: tags ?? this.tags,
        status: status ?? this.status,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
