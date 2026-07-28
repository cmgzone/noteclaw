import 'package:freezed_annotation/freezed_annotation.dart';

part 'notebook.freezed.dart';
part 'notebook.g.dart';

@freezed
class Notebook with _$Notebook {
  const factory Notebook({
    required String id,
    required String userId,
    required String title,
    @Default('') String description,
    String? coverImage, // Base64 encoded image or URL
    required int sourceCount,
    required DateTime createdAt,
    required DateTime updatedAt,
    // Agent notebook fields (Requirements 1.4, 4.1)
    @Default(false) bool isAgentNotebook,
    String? agentSessionId,
    String? agentName,
    String? agentIdentifier,
    @Default('active')
    String agentStatus, // 'active', 'expired', 'disconnected'
    @Default('General') String category,
    // Social sharing fields
    @Default(false) bool isPublic,
    @Default(false) bool isLocked,
    @Default(0) int viewCount,
    @Default(0) int shareCount,
  }) = _Notebook;

  factory Notebook.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(json);

    normalized['userId'] = json['userId'] ?? json['user_id'] ?? '';
    normalized['coverImage'] = json['coverImage'] ?? json['cover_image'];
    normalized['sourceCount'] = _asInt(json['sourceCount'] ?? json['source_count']);
    normalized['createdAt'] = (json['createdAt'] ?? json['created_at'])?.toString() ?? DateTime.now().toIso8601String();
    normalized['updatedAt'] = (json['updatedAt'] ?? json['updated_at'])?.toString() ?? DateTime.now().toIso8601String();
    normalized['isAgentNotebook'] = json['isAgentNotebook'] as bool? ??
        json['is_agent_notebook'] as bool? ??
        (json['is_agent_notebook'] == 1);
    normalized['agentSessionId'] = json['agentSessionId'] ?? json['agent_session_id'];
    normalized['agentName'] = json['agentName'] ?? json['agent_name'];
    normalized['agentIdentifier'] = json['agentIdentifier'] ?? json['agent_identifier'];
    normalized['agentStatus'] = json['agentStatus'] ?? json['agent_status'] ?? 'active';
    normalized['category'] = json['category'] ?? 'General';
    normalized['isPublic'] = json['isPublic'] as bool? ?? json['is_public'] as bool? ?? false;
    normalized['isLocked'] = json['isLocked'] as bool? ?? json['is_locked'] as bool? ?? false;
    normalized['viewCount'] = _asInt(json['viewCount'] ?? json['view_count']);
    normalized['shareCount'] = _asInt(json['shareCount'] ?? json['share_count']);

    return _$NotebookFromJson(normalized);
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
