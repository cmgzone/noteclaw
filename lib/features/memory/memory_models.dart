import 'dart:convert';

class MemoryNotebook {
  const MemoryNotebook({
    required this.id,
    required this.title,
    required this.description,
    required this.sourceCount,
    required this.createdAt,
    required this.updatedAt,
    required this.session,
    required this.isAgentNotebook,
  });

  final String id;
  final String title;
  final String description;
  final int sourceCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final MemoryAgentSession session;
  final bool isAgentNotebook;

  factory MemoryNotebook.fromJson(Map<String, dynamic> json) {
    return MemoryNotebook(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Untitled memory',
      description: json['description']?.toString() ?? '',
      sourceCount: _asInt(json['sourceCount'] ?? json['source_count']),
      createdAt: _asDate(json['createdAt'] ?? json['created_at']),
      updatedAt: _asDate(json['updatedAt'] ?? json['updated_at']),
      session: MemoryAgentSession.fromJson(_asMap(json['session'])),
      isAgentNotebook: _asBool(
        json['isAgentNotebook'] ?? json['is_agent_notebook'],
        defaultValue: false,
      ),
    );
  }
}

class MemoryAgentSession {
  const MemoryAgentSession({
    required this.id,
    required this.agentName,
    required this.mcpClientName,
    required this.agentIdentifier,
    required this.status,
    required this.websocketConnected,
    required this.websocketConnectionCount,
    required this.connectedClients,
    this.lastActivity,
  });

  final String id;
  final String agentName;
  final String mcpClientName;
  final String agentIdentifier;
  final String status;
  final bool websocketConnected;
  final int websocketConnectionCount;
  final List<String> connectedClients;
  final DateTime? lastActivity;

  String get displayAgentName {
    if (connectedClients.isNotEmpty) return connectedClients.join(', ');
    if (mcpClientName.isNotEmpty) return mcpClientName;
    return agentName;
  }

  factory MemoryAgentSession.fromJson(Map<String, dynamic> json) {
    return MemoryAgentSession(
      id: json['id']?.toString() ?? '',
      agentName:
          (json['agentName'] ?? json['agent_name'])?.toString() ?? 'Agent',
      mcpClientName:
          (json['mcpClientName'] ?? json['mcp_client_name'])?.toString() ?? '',
      agentIdentifier:
          (json['agentIdentifier'] ?? json['agent_identifier'])?.toString() ??
              '',
      status: json['status']?.toString() ?? 'active',
      websocketConnected: json['websocketConnected'] as bool? ??
          json['websocket_connected'] as bool? ??
          false,
      websocketConnectionCount: _asInt(
        json['websocketConnectionCount'] ??
            json['websocket_connection_count'] ??
            (json['websocketConnected'] == true ? 1 : 0),
      ),
      connectedClients: json['connectedClients'] is List
          ? (json['connectedClients'] as List)
              .map((value) => value.toString())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
          : const [],
      lastActivity: _asDate(json['lastActivity'] ?? json['last_activity']),
    );
  }
}

class MemorySource {
  const MemorySource({
    required this.id,
    required this.title,
    required this.namespace,
    required this.memory,
    required this.content,
    required this.summary,
    required this.version,
    required this.updatedAt,
    required this.memoryStats,
    required this.sourceType,
    required this.isMemorySource,
  });

  final String id;
  final String title;
  final String namespace;
  final Map<String, dynamic> memory;
  final String content;
  final String summary;
  final int version;
  final DateTime? updatedAt;
  final Map<String, dynamic> memoryStats;
  final String sourceType;
  final bool isMemorySource;

  factory MemorySource.fromJson(Map<String, dynamic> json) {
    final memory = _asMap(json['memory']);
    return MemorySource(
      id: json['id']?.toString() ?? 'memory:${json['namespace']}',
      title: json['title']?.toString() ?? 'Memory source',
      namespace: json['namespace']?.toString() ?? 'default',
      memory: memory,
      content: json['content']?.toString() ??
          const JsonEncoder.withIndent('  ').convert(memory),
      summary: json['summary']?.toString() ?? '',
      version: _asInt(json['version']),
      updatedAt: _asDate(json['updatedAt'] ?? json['updated_at']),
      memoryStats: _asMap(json['memoryStats'] ?? json['memory_stats']),
      sourceType: json['type']?.toString() ?? 'memory',
      isMemorySource: json['isMemorySource'] as bool? ??
          json['is_memory_source'] as bool? ??
          json['type'] == 'memory',
    );
  }

  int get populatedFields =>
      _asInt(memoryStats['nonEmptyFieldCount'] ?? memoryStats['fieldCount']);
}

class MemoryNotebookDetail {
  const MemoryNotebookDetail({
    required this.notebook,
    required this.sources,
  });

  final MemoryNotebook notebook;
  final List<MemorySource> sources;

  List<MemorySource> get visibleSources => sources
      .where((source) => source.sourceType != 'agent_chat')
      .toList(growable: false);

  factory MemoryNotebookDetail.fromJson(Map<String, dynamic> json) {
    final notebook = MemoryNotebook.fromJson(_asMap(json['notebook']));
    final sourceRows = json['sources'] is List
        ? (json['sources'] as List).whereType<Map>()
        : const Iterable<Map>.empty();
    return MemoryNotebookDetail(
      notebook: notebook,
      sources: sourceRows
          .map((row) => MemorySource.fromJson(Map<String, dynamic>.from(row)))
          .toList(growable: false),
    );
  }
}

class MemoryChatMessage {
  const MemoryChatMessage({
    required this.role,
    required this.content,
  });

  final String role;
  final String content;

  bool get isUser => role == 'user';

  Map<String, String> toJson() => {
        'role': role,
        'content': content,
      };
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _asDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

bool _asBool(dynamic value, {bool defaultValue = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return defaultValue;
}
