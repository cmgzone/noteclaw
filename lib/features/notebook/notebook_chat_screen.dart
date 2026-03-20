import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../../ui/widgets/app_network_image.dart';
import 'dart:ui';
import 'dart:async';
import '../sources/source_provider.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/ai/web_browsing_service.dart';
import '../../core/ai/deep_research_service.dart';
import 'notebook_provider.dart';
import '../../core/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../chat/context_usage_widget.dart';
import '../subscription/services/credit_manager.dart';
import '../chat/github_action_detector.dart';
import '../github/github_issue_dialog.dart';
import '../../core/audio/voice_service.dart';
import 'notebook_chat_context_builder.dart';

class NotebookChatScreen extends ConsumerStatefulWidget {
  final String notebookId;

  const NotebookChatScreen({
    super.key,
    required this.notebookId,
  });

  @override
  ConsumerState<NotebookChatScreen> createState() => _NotebookChatScreenState();
}

class _NotebookChatScreenState extends ConsumerState<NotebookChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isVoiceListening = false;
  double _voiceSoundLevel = 0.0;
  ChatStyle _selectedStyle = ChatStyle.standard;
  bool _isWebBrowsingEnabled = false;
  bool _isDeepResearchEnabled = false;
  String? _webBrowsingStatus;
  List<String> _webBrowsingScreenshots = [];
  List<String> _webBrowsingSources = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      final history = await ref
          .read(apiServiceProvider)
          .getChatHistory(notebookId: widget.notebookId);

      final messages = <ChatMessage>[];

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

          messages.add(ChatMessage(
            text: contentStr,
            isUser: role.toString() == 'user',
            timestamp: timestamp,
          ));
        } catch (e) {
          debugPrint('Error parsing message: $e, data: $data');
          // Continue processing other messages
        }
      }

      if (mounted) {
        setState(() {
          _messages.clear();
          _messages.addAll(messages);
          _isLoading = false;
        });

        // Scroll to bottom after a delay to ensure UI is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
          }
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading chat history: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _isLoading = false);

        // Show user-friendly error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to load chat history. Starting fresh.'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: _loadHistory,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    if (_isVoiceListening) {
      ref.read(voiceServiceProvider).stopListening();
    }
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setMessageText(String text) {
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _startVoiceInput() async {
    if (_isLoading) return;
    setState(() {
      _isVoiceListening = true;
      _voiceSoundLevel = 0.0;
    });

    try {
      await ref.read(voiceServiceProvider).listen(
        onResult: (text) {
          if (!mounted) return;
          _setMessageText(text);
        },
        onDone: (text) {
          if (!mounted) return;
          setState(() => _isVoiceListening = false);
          final finalText = text.trim();
          if (finalText.isEmpty) return;
          _setMessageText(finalText);
          _sendMessage();
        },
        onSoundLevel: (level) {
          if (!mounted) return;
          setState(() => _voiceSoundLevel = level);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice input error: $e')),
      );
    }
  }

  Future<void> _stopVoiceInput() async {
    try {
      final transcript = await ref.read(voiceServiceProvider).stopListening();
      if (!mounted) return;
      setState(() => _isVoiceListening = false);
      final text = transcript.trim();
      if (text.isEmpty) return;
      _setMessageText(text);
      _sendMessage();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isVoiceListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop voice input: $e')),
      );
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isVoiceListening) {
      await _stopVoiceInput();
    } else {
      await _startVoiceInput();
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty || _isLoading) return;

    // Check credits
    int creditCost = CreditCosts.chatMessage;
    String featureName = 'chat_message';
    if (_isDeepResearchEnabled) {
      creditCost = CreditCosts.deepResearch;
      featureName = 'deep_research';
    } else if (_isWebBrowsingEnabled) {
      creditCost = CreditCosts.chatMessage * 3;
      featureName = 'web_browsing_chat';
    }

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: creditCost,
      feature: featureName,
    );
    if (!hasCredits) return;

    // Add user message immediately
    final userMessage = ChatMessage(
      text: message,
      isUser: true,
      timestamp: DateTime.now(),
    );

    if (!mounted) return;

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _webBrowsingStatus = null;
      _webBrowsingScreenshots = [];
      _webBrowsingSources = [];
    });

    _messageController.clear();
    _scrollToBottom();

    try {
      // Save User Message (non-blocking)
      ref
          .read(apiServiceProvider)
          .saveChatMessage(
            role: 'user',
            content: message,
            notebookId: widget.notebookId,
          )
          .catchError((e) {
        debugPrint('Error saving user message: $e');
        return <String, dynamic>{};
      });

      if (_isDeepResearchEnabled) {
        await _handleDeepResearch(message);
      } else if (_isWebBrowsingEnabled) {
        // Use web browsing service
        await _handleWebBrowsing(message);
      } else {
        // Regular chat flow
        await _handleRegularChat(message);
      }
    } catch (e) {
      debugPrint('Error in _sendMessage: $e');

      if (mounted) {
        // Show user-friendly error message
        String errorMessage = 'Failed to send message';
        if (e.toString().contains('network') ||
            e.toString().contains('connection')) {
          errorMessage = 'Network error. Please check your connection.';
        } else if (e.toString().contains('401') ||
            e.toString().contains('Unauthorized')) {
          errorMessage = 'Authentication error. Please log in again.';
        } else if (e.toString().contains('timeout')) {
          errorMessage = 'Request timed out. Please try again.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                _messageController.text = message;
                _sendMessage();
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeepResearch(String message) async {
    if (!mounted) return;

    try {
      final deepResearchService = ref.read(deepResearchServiceProvider);

      await for (final update in deepResearchService.research(
          query: message,
          notebookId: widget.notebookId,
          depth: ResearchDepth.standard,
          template: ResearchTemplate.general,
          useNotebookContext: true)) {
        if (!mounted) return;

        setState(() {
          _webBrowsingStatus = update.status;

          if (update.sources != null) {
            final newSources = update.sources!.map((s) => s.url).toList();
            for (final url in newSources) {
              if (!_webBrowsingSources.contains(url)) {
                _webBrowsingSources.add(url);
              }
            }
          }

          if (update.images != null) {
            for (final url in update.images!) {
              if (!_webBrowsingScreenshots.contains(url)) {
                _webBrowsingScreenshots.add(url);
              }
            }
          }
        });
        _scrollToBottom();

        if (update.isComplete && update.result != null) {
          // Save AI Message (non-blocking)
          ref
              .read(apiServiceProvider)
              .saveChatMessage(
                role: 'model',
                content: update.result!,
                notebookId: widget.notebookId,
              )
              .catchError((e) {
            debugPrint('Error saving AI message: $e');
            return <String, dynamic>{};
          });

          if (mounted) {
            setState(() {
              _messages.add(ChatMessage(
                text: update.result!,
                isUser: false,
                timestamp: DateTime.now(),
                isWebBrowsing: true, // Reuse the nice styling
                webBrowsingScreenshots: List.from(_webBrowsingScreenshots),
                webBrowsingSources: List.from(_webBrowsingSources),
              ));
              _webBrowsingStatus = null;
            });
            _scrollToBottom();
          }
          break;
        }
      }
    } catch (e) {
      debugPrint('Error in deep research: $e');

      if (mounted) {
        setState(() => _webBrowsingStatus = null);

        _messages.add(ChatMessage(
          text:
              '⚠️ **Deep Research Error**\n\nFailed to research. Please try again or use regular chat mode.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  Future<void> _handleWebBrowsing(String message) async {
    if (!mounted) return;

    try {
      final webBrowsingService = ref.read(webBrowsingServiceProvider);

      await for (final update in webBrowsingService.browse(query: message)) {
        if (!mounted) return;

        setState(() {
          _webBrowsingStatus = update.status;
          if (update.screenshotUrl != null &&
              !_webBrowsingScreenshots.contains(update.screenshotUrl)) {
            _webBrowsingScreenshots.add(update.screenshotUrl!);
          }
          _webBrowsingSources = update.sources;
        });
        _scrollToBottom();

        if (update.isComplete && update.finalResponse != null) {
          // Save AI Message (non-blocking)
          ref
              .read(apiServiceProvider)
              .saveChatMessage(
                role: 'model',
                content: update.finalResponse!,
                notebookId: widget.notebookId,
              )
              .catchError((e) {
            debugPrint('Error saving AI message: $e');
            return <String, dynamic>{};
          });

          if (mounted) {
            setState(() {
              _messages.add(ChatMessage(
                text: update.finalResponse!,
                isUser: false,
                timestamp: DateTime.now(),
                isWebBrowsing: true,
                webBrowsingScreenshots: List.from(_webBrowsingScreenshots),
                webBrowsingSources: List.from(_webBrowsingSources),
              ));
              _webBrowsingStatus = null;
            });
            _scrollToBottom();
          }
          break;
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error in web browsing: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        setState(() => _webBrowsingStatus = null);

        // Add error message to chat
        _messages.add(ChatMessage(
          text:
              '⚠️ **Web Browsing Error**\n\nFailed to browse the web. Please try again or use regular chat mode.',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      }
    }
  }

  Future<void> _handleRegularChat(String message) async {
    if (!mounted) return;

    try {
      // Get notebook sources for context
      final allSources = ref.read(sourceProvider);
      final notebookSources =
          allSources.where((s) => s.notebookId == widget.notebookId).toList();
      final contextWindowTokens =
          await AISettingsService.getCurrentModelContextWindow(ref.read);
      final contextList = NotebookChatContextBuilder.build(
        sources: notebookSources,
        query: message,
        maxContextChars: NotebookChatContextBuilder.estimateContextCharBudget(
          contextWindowTokens,
        ),
      );

      // Construct history pairs safely
      final historyPairs = <AIPromptResponse>[];
      try {
        for (int i = 0; i < _messages.length - 1; i++) {
          if (i + 1 < _messages.length &&
              _messages[i].isUser &&
              !_messages[i + 1].isUser) {
            historyPairs.add(AIPromptResponse(
              prompt: _messages[i].text,
              response: _messages[i + 1].text,
              timestamp: _messages[i + 1].timestamp,
            ));
          }
        }
      } catch (e) {
        debugPrint('Error building history pairs: $e');
        // Continue without history if there's an error
      }

      // Generate AI response
      await ref.read(aiProvider.notifier).generateContent(
            message,
            context: contextList,
            style: _selectedStyle,
            externalHistory: historyPairs,
          );

      if (!mounted) return;

      final aiState = ref.read(aiProvider);

      // Check for errors first
      if (aiState.error != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('AI Error: ${aiState.error}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'Settings',
                textColor: Colors.white,
                onPressed: () {
                  // Navigate to AI settings
                  context.push('/settings/ai');
                },
              ),
            ),
          );
        }
        return;
      }

      if (aiState.lastResponse != null && aiState.lastResponse!.isNotEmpty) {
        // Save AI Message (non-blocking)
        ref
            .read(apiServiceProvider)
            .saveChatMessage(
              role: 'model',
              content: aiState.lastResponse!,
              notebookId: widget.notebookId,
            )
            .catchError((e) {
          debugPrint('Error saving AI message: $e');
          return <String, dynamic>{};
        });

        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(
              text: aiState.lastResponse!,
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
          _scrollToBottom();
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Error in regular chat: $e');
      debugPrint('Stack trace: $stackTrace');

      if (mounted) {
        // Add error message to chat
        _messages.add(ChatMessage(
          text:
              '⚠️ **Chat Error**\n\nFailed to generate response. Please try again.',
          isUser: false,
          timestamp: DateTime.now(),
        ));

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to generate AI response'),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _handleRegularChat(message),
            ),
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveConversationAsSource() async {
    if (_messages.isEmpty) return;

    final conversation = _messages
        .map((m) => '${m.isUser ? "User" : "AI"}: ${m.text}')
        .join('\n\n');

    try {
      await ref.read(sourceProvider.notifier).addSource(
            title:
                'Chat Conversation - ${DateTime.now().toString().split('.')[0]}',
            type: 'conversation',
            content: conversation,
            notebookId: widget.notebookId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Conversation saved as source'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving conversation: $e')),
        );
      }
    }
  }

  void _showStyleSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Communication Style',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildStyleTile(ChatStyle.standard, 'Standard',
                'Balanced and helpful', Icons.chat),
            _buildStyleTile(ChatStyle.tutor, 'Socratic Tutor',
                'Asks guiding questions', Icons.school),
            _buildStyleTile(ChatStyle.deepDive, 'Deep Dive',
                'Detailed and analytical', Icons.analytics),
            _buildStyleTile(ChatStyle.concise, 'Concise', 'Short and direct',
                Icons.short_text),
            _buildStyleTile(ChatStyle.creative, 'Creative',
                'Imaginative and novel', Icons.lightbulb),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleTile(
      ChatStyle style, String title, String subtitle, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    final isSelected = _selectedStyle == style;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: isSelected ? scheme.primary : scheme.onSurface,
        ),
      ),
      title: Text(title,
          style: TextStyle(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(subtitle),
      trailing:
          isSelected ? Icon(Icons.check_circle, color: scheme.primary) : null,
      onTap: () {
        setState(() => _selectedStyle = style);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Switched to $title mode'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: scheme.primaryContainer,
            showCloseIcon: true,
            closeIconColor: scheme.onPrimaryContainer,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final notebooks = ref.watch(notebookProvider);
    if (notebooks.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final notebook = notebooks.firstWhere(
      (n) => n.id == widget.notebookId,
      orElse: () => notebooks.first,
    );
    final allSources = ref.watch(sourceProvider);
    final sourcesCount =
        allSources.where((s) => s.notebookId == widget.notebookId).length;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(notebook.title, style: const TextStyle(color: Colors.white)),
            Text(
              '$sourcesCount sources available',
              style: text.bodySmall?.copyWith(
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Context usage indicator
          GestureDetector(
            onTap: () => showContextUsageDialog(context),
            child: const ContextUsageIndicator(compact: true),
          ),
          const SizedBox(width: 4),
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save as Source',
              onPressed: _saveConversationAsSource,
            ),
          IconButton(
            icon: const Icon(Icons.psychology), // Brain icon for personas
            tooltip: 'Conversation Style',
            onPressed: _showStyleSelector,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: () {
              setState(() => _messages.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Info banner if no sources
          if (sourcesCount == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: scheme.secondaryContainer.withValues(alpha: 0.5),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Add sources to this notebook for better AI responses',
                      style: TextStyle(color: scheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ).animate().slideY(begin: -0.2).fadeIn(),

          // Messages
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            gradient: AppTheme.premiumGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 8),
                              )
                            ],
                          ),
                          child: Icon(
                            Icons.chat_bubble_outline,
                            size: 40,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        )
                            .animate()
                            .scale(duration: 600.ms, curve: Curves.elasticOut),
                        const SizedBox(height: 24),
                        Text(
                          'Start a conversation',
                          style: text.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ).animate().fadeIn(delay: 200.ms),
                        const SizedBox(height: 8),
                        Text(
                          'Ask questions about your sources',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ).animate().fadeIn(delay: 400.ms),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length +
                        (ref.watch(aiProvider).status == AIStatus.loading &&
                                ref
                                        .watch(aiProvider)
                                        .lastResponse
                                        ?.isNotEmpty ==
                                    true &&
                                _webBrowsingStatus == null
                            ? 1
                            : 0),
                    itemBuilder: (context, index) {
                      if (index < _messages.length) {
                        final message = _messages[index];
                        return _MessageBubble(message: message)
                            .animate()
                            .fadeIn();
                      } else {
                        // Streaming message
                        final aiState = ref.watch(aiProvider);
                        return _MessageBubble(
                          message: ChatMessage(
                            text: aiState.lastResponse ?? '',
                            isUser: false,
                            timestamp: DateTime.now(),
                          ),
                        ).animate().fadeIn();
                      }
                    },
                  ),
          ),

          // Web browsing status indicator
          if (_isWebBrowsingEnabled && _webBrowsingStatus != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _webBrowsingStatus!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Screenshots preview
                  if (_webBrowsingScreenshots.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _webBrowsingScreenshots.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AppNetworkImage(
                                imageUrl: _webBrowsingScreenshots[index],
                                width: 80,
                                height: 60,
                                fit: BoxFit.cover,
                                placeholder: (_) => Container(
                                  width: 80,
                                  height: 60,
                                  color: scheme.surfaceContainerHighest,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (_) => Container(
                                  width: 80,
                                  height: 60,
                                  color: scheme.surfaceContainerHighest,
                                  child:
                                      const Icon(Icons.broken_image, size: 20),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ).animate().fadeIn().slideY(begin: 0.2),

          // Loading indicator
          if (_isLoading && _webBrowsingStatus == null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 12),
                  Text('Thinking...', style: text.bodySmall),
                ],
              ),
            ),

          // Input field
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.8),
                  border: Border(
                    top: BorderSide(
                        color: scheme.outline.withValues(alpha: 0.1)),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Web browsing toggle indicator
                    if (_isWebBrowsingEnabled)
                      Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.language,
                                size: 16, color: Colors.orange),
                            SizedBox(width: 6),
                            Text(
                              '🌐 Web Browsing - AI will search & show screenshots',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn().slideY(begin: 0.2),
                    Row(
                      children: [
                        // Web browsing toggle
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _isWebBrowsingEnabled = !_isWebBrowsingEnabled;
                              if (_isWebBrowsingEnabled) {
                                _isDeepResearchEnabled = false;
                              }
                            });
                          },
                          icon: Icon(
                            Icons.language,
                            color: _isWebBrowsingEnabled
                                ? Colors.orange
                                : scheme.onSurface.withValues(alpha: 0.5),
                            size: 22,
                          ),
                          tooltip: _isWebBrowsingEnabled
                              ? 'Web Browsing ON'
                              : 'Enable Web Browsing (with screenshots)',
                        ),
                        // Deep Research toggle
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _isDeepResearchEnabled = !_isDeepResearchEnabled;
                              if (_isDeepResearchEnabled) {
                                _isWebBrowsingEnabled = false;
                              }
                            });
                          },
                          icon: Icon(
                            Icons.auto_awesome,
                            color: _isDeepResearchEnabled
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.5),
                            size: 22,
                          ),
                          tooltip: _isDeepResearchEnabled
                              ? 'Deep Research ON'
                              : 'Enable Deep Research',
                        ),
                        Transform.scale(
                          scale: 1 + (_voiceSoundLevel * 0.18),
                          child: IconButton(
                            onPressed: _isLoading ? null : _toggleVoiceInput,
                            icon: Icon(
                              _isVoiceListening ? Icons.stop : Icons.mic,
                              color: _isVoiceListening
                                  ? scheme.error
                                  : scheme.onSurface.withValues(alpha: 0.6),
                              size: 22,
                            ),
                            tooltip: _isVoiceListening
                                ? 'Stop voice input'
                                : 'Voice input',
                          )
                              .animate(key: ValueKey(_isVoiceListening))
                              .scale(duration: 200.ms),
                        ),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.1),
                              ),
                            ),
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: _isWebBrowsingEnabled
                                    ? 'Search the web...'
                                    : 'Ask anything...',
                                border: InputBorder.none,
                                contentPadding:
                                    const EdgeInsets.symmetric(vertical: 14),
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              enabled: !_isLoading,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            gradient: _isWebBrowsingEnabled
                                ? const LinearGradient(
                                    colors: [Colors.orange, Colors.deepOrange],
                                  )
                                : AppTheme.premiumGradient,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isWebBrowsingEnabled
                                        ? Colors.orange
                                        : scheme.primary)
                                    .withValues(alpha: 0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed: _isLoading ? null : _sendMessage,
                            icon: const Icon(Icons.arrow_upward,
                                color: Colors.white),
                            tooltip: 'Send',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final bool isWebBrowsing;
  final List<String> webBrowsingScreenshots;
  final List<String> webBrowsingSources;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.isWebBrowsing = false,
    this.webBrowsingScreenshots = const [],
    this.webBrowsingSources = const [],
  });
}

class _MessageBubble extends ConsumerWidget {
  final ChatMessage message;

  const _MessageBubble({required this.message});

  String _extractDomain(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return url;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * (isUser ? 0.75 : 0.88),
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Web browsing indicator
            if (!isUser && message.isWebBrowsing)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.language, size: 12, color: Colors.orange),
                    SizedBox(width: 4),
                    Text(
                      '🌐 Web Browsing',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            // Main message bubble
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? scheme.primary : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24).copyWith(
                  bottomRight: isUser ? Radius.zero : const Radius.circular(24),
                  bottomLeft: !isUser ? Radius.zero : const Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: !isUser
                    ? Border.all(color: scheme.outline.withValues(alpha: 0.1))
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Screenshots from web browsing
                  if (!isUser &&
                      message.isWebBrowsing &&
                      message.webBrowsingScreenshots.isNotEmpty) ...[
                    SizedBox(
                      height: 80,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: message.webBrowsingScreenshots.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _showFullScreenshot(context,
                                  message.webBrowsingScreenshots[index]),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AppNetworkImage(
                                      imageUrl:
                                          message.webBrowsingScreenshots[index],
                                      width: 120,
                                      height: 80,
                                      fit: BoxFit.cover,
                                      placeholder: (_) => Container(
                                        width: 120,
                                        height: 80,
                                        color: scheme.surfaceContainerHighest,
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (_) => Container(
                                        width: 120,
                                        height: 80,
                                        color: scheme.surfaceContainerHighest,
                                        child: const Icon(Icons.broken_image,
                                            size: 24),
                                      ),
                                    ),
                                  ),
                                  // Expand icon overlay
                                  Positioned(
                                    right: 4,
                                    bottom: 4,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(
                                        Icons.fullscreen,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Use Markdown for AI messages, plain text for user
                  if (isUser)
                    SelectableText(
                      message.text,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onPrimary,
                        height: 1.5,
                      ),
                    )
                  else
                    MarkdownBody(
                      data: message.text,
                      selectable: true,
                      styleSheet: MarkdownStyleSheet(
                        // Text styles
                        p: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                          height: 1.6,
                        ),
                        h1: text.headlineSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        h2: text.titleLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        h3: text.titleMedium?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.bold,
                        ),
                        h4: text.titleSmall?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        // Bold and emphasis
                        strong: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                        em: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: scheme.onSurface,
                        ),
                        // Lists
                        listBullet: text.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        // Code
                        code: TextStyle(
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: scheme.tertiary,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        codeblockDecoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        codeblockPadding: const EdgeInsets.all(12),
                        // Blockquotes
                        blockquote: text.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.8),
                          fontStyle: FontStyle.italic,
                        ),
                        blockquoteDecoration: BoxDecoration(
                          border: Border(
                            left: BorderSide(
                              color: scheme.primary.withValues(alpha: 0.6),
                              width: 4,
                            ),
                          ),
                        ),
                        blockquotePadding:
                            const EdgeInsets.only(left: 16, top: 4, bottom: 4),
                        // Links
                        a: TextStyle(
                          color: scheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: scheme.primary,
                        ),
                        // Horizontal rule
                        horizontalRuleDecoration: BoxDecoration(
                          border: Border(
                            top: BorderSide(
                              color: scheme.outline.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                        ),
                        // Table styles
                        tableHead: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                        tableBody: text.bodyMedium?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                      onTapLink: (text, href, title) async {
                        if (href != null) {
                          final uri = Uri.parse(href);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                    ),
                  if (!isUser) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            await ref
                                .read(voiceServiceProvider)
                                .speak(message.text, interrupt: true);
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('TTS error: $e')),
                            );
                          }
                        },
                        onLongPress: () async {
                          await ref.read(voiceServiceProvider).stopSpeaking();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: scheme.outline.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Icon(
                            Icons.volume_up,
                            size: 16,
                            color: scheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                  ],
                  // Sources from web browsing
                  if (!isUser &&
                      message.isWebBrowsing &&
                      message.webBrowsingSources.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.webBrowsingSources.map((url) {
                        final domain = _extractDomain(url);
                        return GestureDetector(
                          onTap: () async {
                            final uri = Uri.parse(url);
                            if (await canLaunchUrl(uri)) {
                              await launchUrl(uri,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: AppNetworkImage(
                                    imageUrl:
                                        'https://www.google.com/s2/favicons?domain=$domain&sz=32',
                                    width: 14,
                                    height: 14,
                                    errorWidget: (_) =>
                                        const Icon(Icons.link, size: 14),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  domain.length > 20
                                      ? '${domain.substring(0, 20)}...'
                                      : domain,
                                  style: text.bodySmall?.copyWith(
                                    color: scheme.primary,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Action row with timestamp and copy button
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTime(message.timestamp),
                        style: text.bodySmall?.copyWith(
                          color: isUser
                              ? scheme.onPrimary.withValues(alpha: 0.7)
                              : scheme.onSurface.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                      if (!isUser) ...[
                        const SizedBox(width: 12),
                        InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: message.text));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Copied to clipboard'),
                                behavior: SnackBarBehavior.floating,
                                backgroundColor: scheme.inverseSurface,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 14,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  // GitHub action buttons for AI responses
                  // Requirements: 6.1, 6.2
                  if (!isUser)
                    GitHubActionButtons(
                      messageText: message.text,
                      onCreateIssue: () {
                        // Show issue creation dialog
                        final issueSuggestion =
                            GitHubActionDetector.detectIssueSuggestion(
                                message.text);
                        if (issueSuggestion != null) {
                          showGitHubIssueDialog(
                            context,
                            ref,
                            title: issueSuggestion.title,
                            body: issueSuggestion.body,
                          );
                        }
                      },
                      onCopyCode: (code, language) {
                        // Code is already copied by the button
                        debugPrint('Code copied: $language');
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenshot(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.contain,
                    placeholder: (_) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.black54,
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                    errorWidget: (_) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.black54,
                      child: const Icon(Icons.broken_image,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
