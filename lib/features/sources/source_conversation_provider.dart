import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api/api_service.dart';

/// Message model for source conversations
/// Requirements: 3.5, 4.2, 4.4
class SourceMessage {
  final String id;
  final String sourceId;
  final String role; // 'user' or 'agent'
  final String content;
  final DateTime timestamp;
  final Map<String, dynamic>? metadata;
  final bool isRead;

  const SourceMessage({
    required this.id,
    required this.sourceId,
    required this.role,
    required this.content,
    required this.timestamp,
    this.metadata,
    this.isRead = false,
  });

  factory SourceMessage.fromJson(Map<String, dynamic> json) {
    DateTime parseTimestamp(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      return DateTime.now();
    }

    Map<String, dynamic>? parseMetadata(dynamic value) {
      if (value == null) return null;
      if (value is Map<String, dynamic>) return value;
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    return SourceMessage(
      id: json['id'] as String,
      sourceId:
          json['source_id'] as String? ?? json['sourceId'] as String? ?? '',
      role: json['role'] as String,
      content: json['content'] as String,
      timestamp: parseTimestamp(
        json['created_at'] ?? json['createdAt'] ?? json['timestamp'],
      ),
      metadata: parseMetadata(json['metadata']),
      isRead: (json['is_read'] as bool?) ?? (json['isRead'] as bool?) ?? false,
    );
  }

  bool get isUser => role == 'user';
  bool get isAgent => role == 'agent';

  /// Check if this message contains a code update
  bool get hasCodeUpdate => metadata != null && metadata!['codeUpdate'] != null;

  /// Get the code update if present
  Map<String, dynamic>? get codeUpdate =>
      metadata?['codeUpdate'] as Map<String, dynamic>?;

  /// Check if this message contains a code diff (Requirements: 4.4)
  bool get hasCodeDiff => metadata != null && metadata!['codeDiff'] != null;

  /// Get the code diff if present (Requirements: 4.4)
  CodeDiff? get codeDiff {
    final diffData = metadata?['codeDiff'] as Map<String, dynamic>?;
    if (diffData == null) return null;
    return CodeDiff.fromJson(diffData);
  }

  /// Check if this message contains an issue suggestion (Requirements: 4.5)
  bool get hasIssueSuggestion =>
      metadata != null && metadata!['issueSuggestion'] != null;

  /// Get the issue suggestion if present (Requirements: 4.5)
  Map<String, dynamic>? get issueSuggestion =>
      metadata?['issueSuggestion'] as Map<String, dynamic>?;

  List<Map<String, dynamic>> get imageAttachments {
    final raw = metadata?['imageAttachments'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }
}

/// Represents a code diff for displaying changes (Requirements: 4.4)
class CodeDiff {
  final String original;
  final String modified;
  final String? language;
  final String? description;
  final int? startLine;
  final int? endLine;

  const CodeDiff({
    required this.original,
    required this.modified,
    this.language,
    this.description,
    this.startLine,
    this.endLine,
  });

  factory CodeDiff.fromJson(Map<String, dynamic> json) {
    return CodeDiff(
      original: json['original'] as String? ?? '',
      modified: json['modified'] as String? ?? '',
      language: json['language'] as String?,
      description: json['description'] as String?,
      startLine: json['startLine'] as int?,
      endLine: json['endLine'] as int?,
    );
  }
}

/// State for a source conversation
class SourceConversationState {
  final String sourceId;
  final List<SourceMessage> messages;
  final bool isLoading;
  final bool isSending;
  final bool isConnected;
  final String? error;
  final String? agentSessionId;
  final DateTime? lastMessageAt;

  const SourceConversationState({
    required this.sourceId,
    this.messages = const [],
    this.isLoading = false,
    this.isSending = false,
    this.isConnected = false,
    this.error,
    this.agentSessionId,
    this.lastMessageAt,
  });

  SourceConversationState copyWith({
    String? sourceId,
    List<SourceMessage>? messages,
    bool? isLoading,
    bool? isSending,
    bool? isConnected,
    String? error,
    String? agentSessionId,
    DateTime? lastMessageAt,
  }) {
    return SourceConversationState(
      sourceId: sourceId ?? this.sourceId,
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      isConnected: isConnected ?? this.isConnected,
      error: error,
      agentSessionId: agentSessionId ?? this.agentSessionId,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }

  bool get hasMessages => messages.isNotEmpty;
  int get messageCount => messages.length;
  int get unreadCount => messages.where((m) => !m.isRead && m.isAgent).length;
}

/// Provider for managing source conversation state
/// Requirements: 3.5
class SourceConversationNotifier
    extends StateNotifier<SourceConversationState> {
  final Ref ref;
  final String sourceId;
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  static const Duration _reconnectDelay = Duration(seconds: 5);

  SourceConversationNotifier(this.ref, this.sourceId)
      : super(SourceConversationState(sourceId: sourceId)) {
    _init();
  }

  ApiService get _apiService => ref.read(apiServiceProvider);

  Future<void> _init() async {
    await loadConversation();
  }

  /// Load conversation history from the API
  Future<void> loadConversation() async {
    if (_disposed) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.getSourceConversation(sourceId);
      final conversation = response['conversation'];
      final messagesData = response['messages'] as List<dynamic>? ?? [];
      final resolvedAgentSessionId =
          (conversation?['agentSessionId'] as String?) ??
          (conversation?['agent_session_id'] as String?) ??
          (response['resolvedAgentSessionId'] as String?) ??
          (response['resolved_agent_session_id'] as String?);

      final messages = messagesData
          .whereType<Map>()
          .map(
            (message) => SourceMessage.fromJson(
              Map<String, dynamic>.from(message),
            ),
          )
          .toList();
      final mergedMessages = _mergeMessages(messages);

      state = state.copyWith(
        messages: mergedMessages,
        isLoading: false,
        agentSessionId: resolvedAgentSessionId,
        lastMessageAt:
            mergedMessages.isNotEmpty ? mergedMessages.last.timestamp : null,
        error: null,
      );

      await _ensureWebSocketConnected();

      developer.log(
        '[SOURCE_CONVERSATION] Loaded ${mergedMessages.length} messages for $sourceId (${kIsWeb ? 'web' : 'app'})',
        name: 'SourceConversationProvider',
      );
    } catch (e, stack) {
      developer.log(
        '[SOURCE_CONVERSATION] Failed to load conversation for $sourceId: $e',
        name: 'SourceConversationProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Send a follow-up message to the agent
  /// Requirements: 3.2, 4.2
  ///
  /// For GitHub sources, includes file content in the webhook payload
  Future<bool> sendMessage(
    String message, {
    Map<String, dynamic>? githubContext,
    List<Map<String, dynamic>>? imageAttachments,
  }) async {
    if (message.trim().isEmpty) return false;

    state = state.copyWith(isSending: true, error: null);

    try {
      await _ensureWebSocketConnected();

      final response = await _apiService.sendFollowupMessage(
        sourceId,
        message,
        githubContext: githubContext,
        imageAttachments: imageAttachments,
      );

      final now = DateTime.now();
      final serverUserMessage = response['message'];
      final userMessage =
          serverUserMessage is Map
              ? SourceMessage.fromJson(
                  Map<String, dynamic>.from(serverUserMessage),
                )
              : SourceMessage(
                  id: now.millisecondsSinceEpoch.toString(),
                  sourceId: sourceId,
                  role: 'user',
                  content: message,
                  timestamp: now,
                  metadata:
                      (imageAttachments != null && imageAttachments.isNotEmpty)
                          ? {'imageAttachments': imageAttachments}
                          : null,
                  isRead: true,
                );

      var updatedMessages = _mergeMessages([...state.messages, userMessage]);

      final serverAgentMessage = response['agentMessage'];
      if (serverAgentMessage is Map) {
        updatedMessages = _mergeMessages([
          ...updatedMessages,
          SourceMessage.fromJson(Map<String, dynamic>.from(serverAgentMessage)),
        ]);
      } else if (response['agentResponse'] != null) {
        Map<String, dynamic>? messageMetadata;
        if (response['codeUpdated'] == true) {
          messageMetadata = {'codeUpdate': true};
        }
        if (response['codeDiff'] != null) {
          messageMetadata ??= {};
          messageMetadata['codeDiff'] = response['codeDiff'];
        }
        if (response['issueSuggestion'] != null) {
          messageMetadata ??= {};
          messageMetadata['issueSuggestion'] = response['issueSuggestion'];
        }

        updatedMessages = _mergeMessages([
          ...updatedMessages,
          SourceMessage(
            id: '${now.millisecondsSinceEpoch}_agent',
            sourceId: sourceId,
            role: 'agent',
            content: response['agentResponse'] as String,
            timestamp: now.add(const Duration(milliseconds: 100)),
            metadata: messageMetadata,
            isRead: false,
          ),
        ]);
      }

      state = state.copyWith(
        messages: updatedMessages,
        isSending: false,
        lastMessageAt:
            updatedMessages.isNotEmpty ? updatedMessages.last.timestamp : now,
        agentSessionId: state.agentSessionId ??
            (response['agentSessionId'] as String?) ??
            (response['agent_session_id'] as String?) ??
            (response['resolvedAgentSessionId'] as String?) ??
            (response['resolved_agent_session_id'] as String?),
        error: null,
      );

      await _ensureWebSocketConnected();

      developer.log(
        '[SOURCE_CONVERSATION] Sent follow-up for $sourceId',
        name: 'SourceConversationProvider',
      );
      return true;
    } catch (e, stack) {
      developer.log(
        '[SOURCE_CONVERSATION] Failed to send follow-up for $sourceId: $e',
        name: 'SourceConversationProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(
        isSending: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Add a message locally (for optimistic updates)
  void addLocalMessage(SourceMessage message) {
    final mergedMessages = _mergeMessages([...state.messages, message]);
    state = state.copyWith(
      messages: mergedMessages,
      lastMessageAt:
          mergedMessages.isNotEmpty ? mergedMessages.last.timestamp : null,
    );
  }

  /// Refresh the conversation
  Future<void> refresh() async {
    await loadConversation();
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }

  Future<void> _ensureWebSocketConnected() async {
    if (_disposed) return;

    if (_wsChannel != null && state.isConnected) {
      _subscribeToSource();
      return;
    }

    await _connectWebSocket();
  }

  Future<void> _connectWebSocket() async {
    if (_disposed) return;

    try {
      final token = await _apiService.getToken();
      if (token == null || token.trim().isEmpty) {
        developer.log(
          '[SOURCE_CONVERSATION] No token available for websocket',
          name: 'SourceConversationProvider',
        );
        state = state.copyWith(isConnected: false);
        return;
      }

      await _disconnectWebSocket();

      final apiUri = Uri.parse(_apiService.baseUrl);
      final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
      final host = apiUri.host;
      final port = apiUri.hasPort ? ':${apiUri.port}' : '';
      final wsUrl =
          '$scheme://$host$port/ws/source-conversations?token=$token';

      developer.log(
        '[SOURCE_CONVERSATION] Connecting websocket for $sourceId',
        name: 'SourceConversationProvider',
      );

      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsSubscription = _wsChannel!.stream.listen(
        _handleWebSocketMessage,
        onError: (error, stackTrace) {
          developer.log(
            '[SOURCE_CONVERSATION] Websocket error for $sourceId: $error',
            name: 'SourceConversationProvider',
            error: error,
            stackTrace: stackTrace is StackTrace ? stackTrace : null,
          );
          state = state.copyWith(isConnected: false);
          _scheduleReconnect();
        },
        onDone: () {
          developer.log(
            '[SOURCE_CONVERSATION] Websocket closed for $sourceId',
            name: 'SourceConversationProvider',
          );
          state = state.copyWith(isConnected: false);
          _scheduleReconnect();
        },
      );

      state = state.copyWith(isConnected: true, error: null);
      _subscribeToSource();
    } catch (e, stack) {
      developer.log(
        '[SOURCE_CONVERSATION] Failed to connect websocket for $sourceId: $e',
        name: 'SourceConversationProvider',
        error: e,
        stackTrace: stack,
      );
      state = state.copyWith(isConnected: false);
      _scheduleReconnect();
    }
  }

  Future<void> _disconnectWebSocket() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    final subscription = _wsSubscription;
    _wsSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }

    final channel = _wsChannel;
    _wsChannel = null;
    if (channel != null) {
      await channel.sink.close();
    }

    if (!_disposed) {
      state = state.copyWith(isConnected: false);
    }
  }

  void _subscribeToSource() {
    _sendWebSocketMessage({
      'type': 'subscribe',
      'payload': {'sourceId': sourceId},
    });
  }

  void _unsubscribeFromSource() {
    _sendWebSocketMessage({
      'type': 'unsubscribe',
      'payload': {'sourceId': sourceId},
    });
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectTimer = Timer(_reconnectDelay, () {
      _reconnectTimer = null;
      if (_disposed) return;
      _connectWebSocket();
    });
  }

  void _handleWebSocketMessage(dynamic rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage.toString());
      if (decoded is! Map) {
        return;
      }

      final message = Map<String, dynamic>.from(decoded);
      final type = message['type'] as String?;
      final payload = message['payload'];

      switch (type) {
        case 'ping':
          _sendWebSocketMessage({'type': 'pong'});
          break;
        case 'pong':
        case 'subscribed':
          if (!state.isConnected) {
            state = state.copyWith(isConnected: true, error: null);
          }
          break;
        case 'conversation_message':
          if (payload is Map) {
            _handleConversationMessage(Map<String, dynamic>.from(payload));
          }
          break;
        case 'error':
          final errorPayload =
              payload is Map<String, dynamic>
                  ? payload
                  : payload is Map
                  ? Map<String, dynamic>.from(payload)
                  : const <String, dynamic>{};
          final errorMessage =
              errorPayload['message'] as String? ??
              'Source conversation websocket error';
          developer.log(
            '[SOURCE_CONVERSATION] Websocket rejected message for $sourceId: $errorMessage',
            name: 'SourceConversationProvider',
          );
          state = state.copyWith(error: errorMessage);
          break;
        case 'unsubscribed':
        case null:
          break;
        default:
          developer.log(
            '[SOURCE_CONVERSATION] Ignoring websocket message type "$type" for $sourceId',
            name: 'SourceConversationProvider',
          );
      }
    } catch (e, stack) {
      developer.log(
        '[SOURCE_CONVERSATION] Failed to parse websocket message for $sourceId: $e',
        name: 'SourceConversationProvider',
        error: e,
        stackTrace: stack,
      );
    }
  }

  void _handleConversationMessage(Map<String, dynamic> payload) {
    final rawMessage = payload['message'];
    if (rawMessage is! Map) {
      return;
    }

    final message =
        SourceMessage.fromJson(Map<String, dynamic>.from(rawMessage));
    final mergedMessages = _mergeMessages([...state.messages, message]);

    state = state.copyWith(
      messages: mergedMessages,
      lastMessageAt:
          mergedMessages.isNotEmpty ? mergedMessages.last.timestamp : null,
      error: null,
    );
  }

  List<SourceMessage> _mergeMessages(List<SourceMessage> messages) {
    final messagesById = <String, SourceMessage>{};
    for (final message in messages) {
      messagesById[message.id] = message;
    }

    final mergedMessages = messagesById.values.toList()
      ..sort((a, b) {
        final timestampCompare = a.timestamp.compareTo(b.timestamp);
        if (timestampCompare != 0) {
          return timestampCompare;
        }
        return a.id.compareTo(b.id);
      });

    return mergedMessages;
  }

  void _sendWebSocketMessage(Map<String, dynamic> message) {
    final channel = _wsChannel;
    if (channel == null) {
      return;
    }

    try {
      channel.sink.add(jsonEncode(message));
    } catch (e, stack) {
      developer.log(
        '[SOURCE_CONVERSATION] Failed to send websocket message for $sourceId: $e',
        name: 'SourceConversationProvider',
        error: e,
        stackTrace: stack,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _unsubscribeFromSource();

    final subscription = _wsSubscription;
    _wsSubscription = null;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }

    final channel = _wsChannel;
    _wsChannel = null;
    if (channel != null) {
      unawaited(channel.sink.close());
    }

    super.dispose();
  }
}

/// Family provider for source conversations
/// Each source has its own conversation state
final sourceConversationProvider = StateNotifierProvider.family<
    SourceConversationNotifier, SourceConversationState, String>(
  (ref, sourceId) => SourceConversationNotifier(ref, sourceId),
);

/// Provider to check if a source has an agent session
final sourceHasAgentProvider = FutureProvider.family<bool, String>(
  (ref, sourceId) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final response = await apiService.getSourceConversation(sourceId);
      final conversation = response['conversation'];
      final sessionId = conversation?['agentSessionId'] ??
          conversation?['agent_session_id'] ??
          response['resolvedAgentSessionId'] ??
          response['resolved_agent_session_id'];
      return sessionId != null &&
          sessionId is String &&
          sessionId.trim().isNotEmpty;
    } catch (e) {
      return false;
    }
  },
);
