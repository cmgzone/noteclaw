import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:uuid/uuid.dart';

part 'mind_map_node.freezed.dart';
part 'mind_map_node.g.dart';

/// Represents a node in a mind map graph
@freezed
class MindMapNode with _$MindMapNode {
  const factory MindMapNode({
    required String id,
    required String label,
    @Default([]) List<MindMapNode> children,
    @Default(0) int level, // Hierarchy depth (0 = root)
    int? colorValue, // Custom color as int
    double? x, // Position for layout
    double? y,
  }) = _MindMapNode;

  const MindMapNode._();

  factory MindMapNode.fromBackendJson(dynamic json) {
    final nodeJson = _normalizeNodeJson(json);
    if (nodeJson == null) {
      return MindMapNode(
        id: const Uuid().v4(),
        label: json?.toString() ?? 'New Node',
        level: 0,
        children: [],
      );
    }
    return MindMapNode(
      id: nodeJson['id']?.toString() ?? const Uuid().v4(),
      label: nodeJson['label']?.toString() ?? 'New Node',
      children: (nodeJson['children'] as List? ?? [])
          .map((c) => MindMapNode.fromBackendJson(c))
          .toList(),
      level: _asInt(nodeJson['level']) ?? 0,
      colorValue: _asInt(nodeJson['colorValue'] ?? nodeJson['color_value']),
      x: _asDouble(nodeJson['x']),
      y: _asDouble(nodeJson['y']),
    );
  }

  Map<String, dynamic> toBackendJson() => {
        'id': id,
        'label': label,
        'children': children.map((c) => c.toBackendJson()).toList(),
        'level': level,
        'colorValue': colorValue,
        'x': x,
        'y': y,
      };

  factory MindMapNode.fromJson(Map<String, dynamic> json) =>
      _$MindMapNodeFromJson(json);
}

/// Represents a complete mind map with metadata
@freezed
class MindMap with _$MindMap {
  const factory MindMap({
    required String id,
    required String title,
    required String notebookId,
    String? sourceId,
    required MindMapNode rootNode,
    String? textContent, // Original markdown text version
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _MindMap;

  const MindMap._();

  factory MindMap.fromBackendJson(Map<String, dynamic> json) {
    final payload = json['mindMap'] is Map
        ? Map<String, dynamic>.from(json['mindMap'] as Map)
        : json;

    return MindMap(
      id: payload['id']?.toString() ?? const Uuid().v4(),
      title: payload['title']?.toString() ?? 'Untitled Mind Map',
      notebookId: payload['notebook_id']?.toString() ??
          payload['notebookId']?.toString() ??
          '',
      sourceId:
          payload['source_id']?.toString() ?? payload['sourceId']?.toString(),
      rootNode: MindMapNode.fromBackendJson(
        payload['root_node'] ?? payload['rootNode'] ?? {},
      ),
      textContent: payload['text_content']?.toString() ??
          payload['textContent']?.toString(),
      createdAt: _parseBackendDate(payload['created_at'] ?? payload['createdAt']),
      updatedAt: _parseBackendDate(payload['updated_at'] ?? payload['updatedAt']),
    );
  }

  Map<String, dynamic> toBackendJson() => {
        'id': id,
        'title': title,
        'notebook_id': notebookId,
        'source_id': sourceId,
        'root_node': rootNode.toBackendJson(),
        'text_content': textContent,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory MindMap.fromJson(Map<String, dynamic> json) =>
      _$MindMapFromJson(json);
}

Map<String, dynamic>? _normalizeNodeJson(dynamic json) {
  if (json is Map<String, dynamic>) return json;
  if (json is Map) return Map<String, dynamic>.from(json);
  if (json is String && json.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
  }
  return null;
}

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime _parseBackendDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value) ?? DateTime.now();
  }
  return DateTime.now();
}
