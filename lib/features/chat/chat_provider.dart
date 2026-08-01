import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_service.dart';
import '../../core/ai/web_browsing_service.dart';
import '../../core/ai/deep_research_service.dart';
import '../subscription/providers/subscription_provider.dart';
import 'message.dart';
import 'stream_provider.dart';
import '../subscription/services/credit_manager.dart';

import 'services/suggestion_service.dart';

class ChatNotifier extends StateNotifier<List<Message>> {
  ChatNotifier(this.ref) : super([]) {
    unawaited(_initialize());
  }

  final Ref ref;

  // Web browsing state
  bool _isWebBrowsing = false;
  WebBrowsingUpdate? _currentBrowsingUpdate;

  bool get isWebBrowsing => _isWebBrowsing;
  WebBrowsingUpdate? get currentBrowsingUpdate => _currentBrowsingUpdate;

  Future<void> _initialize() async {
    await _loadHistory();
    await _resumeDeepResearch();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;

    try {
      final history = await ref.read(apiServiceProvider).getChatHistory();

      final messages = <Message>[];

      for (final data in history) {
        try {
          // Validate required fields
          if (!data.containsKey('content') || !data.containsKey('role')) {
            debugPrint('Skipping invalid message data: $data');
            continue;
          }

          final content = data['content'];
          final role = data['role'];

          // Ensure content is a string
          if (content == null) {
            debugPrint('Skipping message with null content');
            continue;
          }

          final contentStr = content.toString();
          if (contentStr.isEmpty) {
            debugPrint('Skipping message with empty content');
            continue;
          }

          // Parse timestamp safely
          DateTime timestamp = DateTime.now();
          if (data.containsKey('created_at') && data['created_at'] != null) {
            final parsedTime = DateTime.tryParse(data['created_at'].toString());
            if (parsedTime != null) {
              timestamp = parsedTime;
            }
          }

          final metadata = _parseMessageMetadata(data['metadata']);
          final isDeepResearch = metadata['isDeepResearch'] == true;

          messages.add(Message(
            id: data['id']?.toString() ??
                DateTime.now().millisecondsSinceEpoch.toString(),
            text: contentStr,
            isUser: role.toString() == 'user',
            timestamp: timestamp,
            isDeepSearch: isDeepResearch,
            isWebBrowsing: isDeepResearch || metadata['isWebBrowsing'] == true,
            webBrowsingStatus: metadata['researchStatus']?.toString(),
            webBrowsingSources: _stringList(metadata['sources']),
            webBrowsingScreenshots: _stringList(metadata['images']),
          ));
        } catch (e) {
          debugPrint('Error parsing message: $e, data: $data');
          // Continue processing other messages
        }
      }

      if (mounted) {
        state = messages;
      }
    } catch (e, stackTrace) {
      // Log error for debugging but don't crash - chat can work without history
      debugPrint('Error loading chat history: $e');
      debugPrint('Stack trace: $stackTrace');

      // Initialize with empty state if loading fails
      if (mounted) {
        state = [];
      }
    }
  }

  Map<String, dynamic> _parseMessageMetadata(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Older rows may contain non-JSON metadata. Treat them as untagged.
      }
    }
    return const <String, dynamic>{};
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  void addAIMessage(String text) {
    // Also save this if used?
    final aiMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: false,
      timestamp: DateTime.now(),
    );
    state = [...state, aiMsg];
  }

  /// Send message with optional web browsing mode
  Future<void> send(String text,
      {bool useDeepSearch = false,
      bool useWebBrowsing = false,
      String? imagePath,
      Uint8List? imageBytes}) async {
    final userMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      imageUrl: imagePath,
    );

    // 1. Add message to UI IMMEDIATELY (no await)
    state = [...state, userMsg];

    // 2. Save user message to backend in background (non-blocking)
    unawaited(
      ref
          .read(apiServiceProvider)
          .saveChatMessage(
            notebookId: null,
            role: 'user',
            content: text,
          )
          .catchError((_) => <String, dynamic>{}),
    );

    // Use web browsing mode if enabled
    if (useWebBrowsing) {
      await _handleWebBrowsing(text);
      return;
    }

    if (useDeepSearch) {
      await _handleDeepResearch(text);
      return;
    }

    // Pass chat history to stream provider for context
    final chatHistory = state.where((m) => m.id != userMsg.id).toList();

    try {
      final stream = ref.read(streamProvider.notifier).ask(
            text,
            chatHistory: chatHistory,
            useDeepSearch: useDeepSearch,
            imageBytes: imageBytes,
          );

      StringBuffer buffer = StringBuffer();
      List<Citation> citations = [];

      // Add initial placeholder AI message
      final placeholderMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '',
        isUser: false,
        timestamp: DateTime.now(),
        isDeepSearch: useDeepSearch,
      );
      state = [...state, placeholderMsg];

      await for (final tokens in stream) {
        for (final t in tokens) {
          t.when(
            text: (txt) {
              buffer.write(txt);
            },
            citation: (id, snippet) {
              final parts = id.split('::');
              final chunkId = parts.isNotEmpty ? parts.first : id;
              final sourceId = parts.length > 1 ? parts[1] : 's1';
              citations.add(Citation(
                  id: chunkId,
                  sourceId: sourceId,
                  snippet: snippet,
                  start: 0,
                  end: 10));
            },
            done: () {},
          );
        }

        final aiMsg = Message(
          id: placeholderMsg.id,
          text: buffer.toString(),
          isUser: false,
          timestamp: DateTime.now(),
          citations: citations,
          isDeepSearch: useDeepSearch,
        );
        state = [...state.sublist(0, state.length - 1), aiMsg];
      }

      // Save AI response to backend in background (non-blocking)
      unawaited(
        ref
            .read(apiServiceProvider)
            .saveChatMessage(
              notebookId: null,
              role: 'model',
              content: buffer.toString(),
            )
            .catchError((_) => <String, dynamic>{}),
      );

      // Generate Smart Suggestions
      _generateSuggestions();
    } on InsufficientCreditsException catch (e) {
      // Handle insufficient credits error
      final errorMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '⚠️ **Insufficient Credits**\n\n'
            'You need ${e.required} credits but only have ${e.available} credits available.\n\n'
            'Please purchase more credits or upgrade your plan to continue.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = [...state.sublist(0, state.length - 1), errorMsg];

      // Invalidate subscription to refresh balance
      ref.invalidate(userSubscriptionProvider);
    } catch (e) {
      debugPrint('Error in AI stream: $e');
      // Update with an error message
      final errorMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: '⚠️ **Error**\n\n${e.toString()}',
        isUser: false,
        timestamp: DateTime.now(),
      );
      state = [...state.sublist(0, state.length - 1), errorMsg];
    }
  }

  /// Handle web browsing mode with real-time updates
  Future<void> _handleWebBrowsing(String query) async {
    // Check credits first
    final creditManager = ref.read(creditManagerProvider);
    if (creditManager.currentBalance < 0) {
      final errorMsg = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text:
            '⚠️ **Insufficient Credits**\n\nYou do not have enough credits to send this message.',
        isUser: false,
        timestamp: DateTime.now(),
      );
      if (mounted) state = [...state, errorMsg];
      return;
    }

    _isWebBrowsing = true;
    _currentBrowsingUpdate = null;

    // Add placeholder AI message
    final placeholderMsg = Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      text: '🌐 Browsing the web...',
      isUser: false,
      timestamp: DateTime.now(),
      isWebBrowsing: true,
    );
    if (mounted) state = [...state, placeholderMsg];

    final webService = ref.read(webBrowsingServiceProvider);
    final screenshots = <String>[];

    await for (final update in webService.browse(query: query)) {
      _currentBrowsingUpdate = update;

      // Collect screenshots
      if (update.screenshotUrl != null &&
          !screenshots.contains(update.screenshotUrl)) {
        screenshots.add(update.screenshotUrl!);
      }

      // Update the message with current status
      final statusMsg = Message(
        id: placeholderMsg.id,
        text: update.isComplete
            ? update.finalResponse ?? 'No response generated'
            : '🌐 ${update.status}',
        isUser: false,
        timestamp: DateTime.now(),
        isWebBrowsing: true,
        webBrowsingStatus: update.status,
        webBrowsingScreenshots: screenshots,
        webBrowsingSources: update.sources,
      );

      if (mounted) {
        state = [...state.sublist(0, state.length - 1), statusMsg];
      }
    }

    _isWebBrowsing = false;
    _currentBrowsingUpdate = null;

    // Save AI response
    if (state.isNotEmpty && !state.last.isUser) {
      try {
        await ref.read(apiServiceProvider).saveChatMessage(
              notebookId: 'global',
              role: 'model',
              content: state.last.text,
            );
      } catch (_) {}
    }

    // Generate Smart Suggestions
    _generateSuggestions();
  }

  Future<void> _handleDeepResearch(String query) async {
    final placeholder = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: 'Starting deep research…',
      isUser: false,
      timestamp: DateTime.now(),
      isDeepSearch: true,
      isWebBrowsing: true,
      webBrowsingStatus: 'Starting deep research',
    );
    if (mounted) state = [...state, placeholder];

    try {
      await for (final update in ref.read(deepResearchServiceProvider).research(
            query: query,
            notebookId: '',
            depth: ResearchDepth.standard,
            template: ResearchTemplate.general,
            owner: 'global-chat',
          )) {
        if (!mounted) return;
        final sourceUrls = update.sources
                ?.map((source) => source.url)
                .where((url) => url.isNotEmpty)
                .toList() ??
            const <String>[];
        final text = update.error != null
            ? '⚠️ **Deep Research Error**\n\n${update.error}'
            : update.isComplete
                ? (update.result ?? 'Research completed without a report.')
                : '🔎 ${update.status}';
        state = [
          ...state.sublist(0, state.length - 1),
          Message(
            id: placeholder.id,
            text: text,
            isUser: false,
            timestamp: DateTime.now(),
            isDeepSearch: true,
            isWebBrowsing: true,
            webBrowsingStatus: update.error != null
                ? 'Research failed'
                : update.isComplete
                    ? 'Research complete'
                    : update.status,
            webBrowsingSources: sourceUrls,
            webBrowsingScreenshots: update.images ?? const <String>[],
          ),
        ];

        if (update.isComplete) {
          if (update.error == null && update.result != null) {
            unawaited(ref.read(apiServiceProvider).saveChatMessage(
              notebookId: null,
              role: 'model',
              content: update.result!,
              metadata: {
                'isDeepResearch': true,
                'isWebBrowsing': true,
                'researchStatus': 'Research complete',
                'sources': sourceUrls,
                'images': update.images ?? const <String>[],
              },
            ).catchError((_) => <String, dynamic>{}));
          }
          ref.invalidate(userSubscriptionProvider);
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      state = [
        ...state.sublist(0, state.length - 1),
        Message(
          id: placeholder.id,
          text: '⚠️ **Deep Research Error**\n\n$error',
          isUser: false,
          timestamp: DateTime.now(),
          isDeepSearch: true,
          isWebBrowsing: true,
          webBrowsingStatus: 'Research failed',
        ),
      ];
    }
  }

  Future<void> _resumeDeepResearch() async {
    try {
      final service = ref.read(deepResearchServiceProvider);
      final job = await service.getActiveJob('global-chat');
      if (job == null || !mounted) return;

      final placeholder = Message(
        id: 'deep-research-${job.jobId}',
        text: 'Reconnecting to background research...',
        isUser: false,
        timestamp: DateTime.now(),
        isDeepSearch: true,
        isWebBrowsing: true,
        webBrowsingStatus: 'Reconnecting to background research',
      );
      state = [...state, placeholder];

      await for (final update in service.resume(job)) {
        if (!mounted) return;
        final sourceUrls = update.sources
                ?.map((source) => source.url)
                .where((url) => url.isNotEmpty)
                .toList() ??
            const <String>[];
        final text = update.error != null
            ? '⚠️ **Deep Research Error**\n\n${update.error}'
            : update.isComplete
                ? (update.result ?? 'Research completed without a report.')
                : '🔎 ${update.status}';
        final replacement = Message(
          id: placeholder.id,
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
          isDeepSearch: true,
          isWebBrowsing: true,
          webBrowsingStatus: update.error != null
              ? 'Research failed'
              : update.isComplete
                  ? 'Research complete'
                  : update.status,
          webBrowsingSources: sourceUrls,
          webBrowsingScreenshots: update.images ?? const <String>[],
        );
        final index =
            state.indexWhere((message) => message.id == placeholder.id);
        if (index >= 0) {
          final updated = [...state];
          updated[index] = replacement;
          state = updated;
        } else {
          state = [...state, replacement];
        }

        if (update.isComplete) {
          if (update.error == null && update.result != null) {
            unawaited(ref.read(apiServiceProvider).saveChatMessage(
              notebookId: null,
              role: 'model',
              content: update.result!,
              metadata: {
                'isDeepResearch': true,
                'isWebBrowsing': true,
                'researchStatus': 'Research complete',
                'sources': sourceUrls,
                'images': update.images ?? const <String>[],
              },
            ).catchError((_) => <String, dynamic>{}));
          }
          ref.invalidate(userSubscriptionProvider);
          return;
        }
      }
    } catch (error) {
      debugPrint('Could not resume deep research: $error');
    }
  }

  Future<void> _generateSuggestions() async {
    // Only generate if the last message is from AI
    if (state.isEmpty || state.last.isUser) return;

    final suggestionService = ref.read(suggestionServiceProvider);
    final suggestions =
        await suggestionService.generateSuggestions(history: state);

    if (suggestions.questions.isNotEmpty || suggestions.sources.isNotEmpty) {
      final lastMsg = state.last;

      if (!lastMsg.isUser) {
        final updatedMsg = lastMsg.copyWith(
          suggestedQuestions: suggestions.questions,
          relatedSources: suggestions.sources,
        );
        if (mounted) {
          state = [...state.sublist(0, state.length - 1), updatedMsg];
        }
      }
    }
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, List<Message>>(
    (ref) => ChatNotifier(ref));
