import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/ai/ai_models_provider.dart';
import '../../core/api/api_service.dart';
import '../../ui/digital_librarian.dart';
import '../memory/memory_models.dart';
import '../sources/source_conversation_provider.dart';

enum _MemoryChatMode { assistant, deepResearch, codingAgent }

class MemoryChatPanel extends ConsumerStatefulWidget {
  const MemoryChatPanel({
    super.key,
    required this.notebook,
    required this.sources,
  });

  final MemoryNotebook notebook;
  final List<MemorySource> sources;

  @override
  ConsumerState<MemoryChatPanel> createState() => _MemoryChatPanelState();
}

class _MemoryChatPanelState extends ConsumerState<MemoryChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<MemoryChatMessage> _aiMessages = [];

  _MemoryChatMode _mode = _MemoryChatMode.assistant;
  String? _selectedModelId;
  String? _liveSourceId;
  String? _researchStatus;
  String? _error;
  bool _isSending = false;
  bool _isOpeningAgent = false;
  int _lastLiveMessageCount = 0;

  @override
  void didUpdateWidget(covariant MemoryChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.notebook.id == widget.notebook.id) return;
    _aiMessages.clear();
    _mode = _MemoryChatMode.assistant;
    _liveSourceId = null;
    _researchStatus = null;
    _error = null;
    _isSending = false;
    _isOpeningAgent = false;
    _lastLiveMessageCount = 0;
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<AIModelOption> _allModels(
    Map<String, List<AIModelOption>> grouped,
  ) {
    return [
      ...grouped['gemini'] ?? const <AIModelOption>[],
      ...grouped['openrouter'] ?? const <AIModelOption>[],
    ];
  }

  AIModelOption? _effectiveModel(
    Map<String, List<AIModelOption>> grouped,
    String? savedModelId,
  ) {
    final models = _allModels(grouped);
    if (models.isEmpty) return null;
    final wantedId = _selectedModelId ?? savedModelId;
    for (final model in models) {
      if (model.id == wantedId && model.canAccess) return model;
    }
    for (final model in models) {
      if (model.canAccess) return model;
    }
    return models.first;
  }

  String _providerFor(AIModelOption? model) {
    final provider = model?.provider.toLowerCase() ?? 'gemini';
    if (provider == 'openrouter' ||
        provider == 'openai' ||
        provider == 'anthropic') {
      return 'openrouter';
    }
    return 'gemini';
  }

  Future<void> _switchMode(_MemoryChatMode mode) async {
    if (_isSending || _isOpeningAgent) return;
    setState(() {
      _mode = mode;
      _error = null;
      _researchStatus = null;
    });
    if (mode == _MemoryChatMode.codingAgent) {
      await _openLiveAgentChat();
    }
    _scrollToEnd();
  }

  Future<String?> _openLiveAgentChat() async {
    if (_liveSourceId != null) return _liveSourceId;
    if (widget.notebook.session.id.isEmpty) {
      setState(() {
        _error = 'This notebook is not connected to a coding agent.';
      });
      return null;
    }

    setState(() {
      _isOpeningAgent = true;
      _error = null;
    });
    try {
      Map<String, dynamic> response;
      try {
        response = await ref
            .read(apiServiceProvider)
            .getOrCreateNotebookLiveAgentChat(widget.notebook.id);
      } catch (error) {
        final message = error.toString().toLowerCase();
        if (!message.contains('route not found')) rethrow;

        final existingSource = widget.sources.cast<MemorySource?>().firstWhere(
              (source) =>
                  source != null &&
                  !source.isMemorySource &&
                  (source.sourceType == 'agent_chat' ||
                      source.title == 'Live agent conversation'),
              orElse: () => null,
            );
        if (existingSource != null) {
          response = {
            'source': {'id': existingSource.id},
          };
        } else {
          response = await ref
              .read(apiServiceProvider)
              .createCompatibleNotebookAgentChat(
                notebookId: widget.notebook.id,
                agentSessionId: widget.notebook.session.id,
                agentName: widget.notebook.session.displayAgentName,
              );
        }
      }
      final source = response['source'];
      final sourceId =
          source is Map ? source['id']?.toString().trim() ?? '' : '';
      if (sourceId.isEmpty) {
        throw Exception('The realtime coding-agent channel could not open.');
      }
      if (!mounted) return null;
      setState(() => _liveSourceId = sourceId);
      ref.read(sourceConversationProvider(sourceId));
      return sourceId;
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
      return null;
    } finally {
      if (mounted) setState(() => _isOpeningAgent = false);
    }
  }

  Future<void> _send([String? suggestedPrompt]) async {
    final message = (suggestedPrompt ?? _controller.text).trim();
    if (message.isEmpty || _isSending || _isOpeningAgent) return;

    if (_mode == _MemoryChatMode.codingAgent) {
      final sourceId = await _openLiveAgentChat();
      if (sourceId == null || !mounted) return;
      _controller.clear();
      final sent = await ref
          .read(sourceConversationProvider(sourceId).notifier)
          .sendMessage(message);
      if (!mounted) return;
      if (!sent) {
        final state = ref.read(sourceConversationProvider(sourceId));
        setState(() {
          _error =
              state.error ?? 'The coding agent could not receive this message.';
        });
      }
      _scrollToEnd();
      return;
    }

    final history = _aiMessages.map((item) => item.toJson()).toList();
    setState(() {
      _aiMessages.add(MemoryChatMessage(role: 'user', content: message));
      _controller.clear();
      _isSending = true;
      _error = null;
    });
    _scrollToEnd();

    try {
      final grouped = ref.read(availableModelsProvider).valueOrNull ??
          const <String, List<AIModelOption>>{};
      final savedModelId = ref.read(currentAIModelIdProvider).valueOrNull;
      final model = _effectiveModel(grouped, savedModelId);
      final provider = _providerFor(model);
      var answer = '';

      if (_mode == _MemoryChatMode.deepResearch) {
        await for (final event
            in ref.read(apiServiceProvider).performDeepResearchStream(
                  query: message,
                  notebookId: widget.notebook.id,
                  depth: 'standard',
                  template: 'general',
                  includeImages: true,
                  useNotebookContext: true,
                  provider: provider,
                  model: model?.id,
                )) {
          final eventError = event['error']?.toString().trim();
          if (eventError?.isNotEmpty == true) {
            throw Exception(eventError);
          }
          final status = event['status']?.toString().trim();
          final result = event['result']?.toString().trim();
          if (result?.isNotEmpty == true) answer = result!;
          if (mounted && status?.isNotEmpty == true) {
            setState(() => _researchStatus = status);
          }
        }
        if (answer.isEmpty) {
          answer = 'The research finished without a written report.';
        }
      } else {
        final response =
            await ref.read(apiServiceProvider).chatWithMemoryNotebook(
                  notebookId: widget.notebook.id,
                  message: message,
                  history: history,
                  provider: provider,
                  model: model?.id,
                );
        answer = response['answer']?.toString().trim() ?? '';
      }

      if (!mounted) return;
      setState(() {
        _aiMessages.add(
          MemoryChatMessage(
            role: 'assistant',
            content: answer.isNotEmpty
                ? answer
                : 'The memory assistant returned an empty response.',
          ),
        );
      });
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _researchStatus = null;
        });
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groupedModels = ref.watch(availableModelsProvider).valueOrNull ??
        const <String, List<AIModelOption>>{};
    final savedModelId = ref.watch(currentAIModelIdProvider).valueOrNull;
    final selectedModel = _effectiveModel(groupedModels, savedModelId);
    final liveConversation = _liveSourceId == null
        ? null
        : ref.watch(sourceConversationProvider(_liveSourceId!));
    final liveMessages = liveConversation?.messages
            .map(
              (message) => MemoryChatMessage(
                role: message.isUser ? 'user' : 'assistant',
                content: message.content,
              ),
            )
            .toList(growable: false) ??
        const <MemoryChatMessage>[];
    if (liveMessages.length != _lastLiveMessageCount) {
      _lastLiveMessageCount = liveMessages.length;
      _scrollToEnd();
    }

    final displayedMessages =
        _mode == _MemoryChatMode.codingAgent ? liveMessages : _aiMessages;
    final isBusy =
        _isSending || _isOpeningAgent || (liveConversation?.isSending ?? false);
    final isLive = _mode == _MemoryChatMode.codingAgent &&
        (liveConversation?.isConnected ??
            widget.notebook.session.websocketConnected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: displayedMessages.isEmpty &&
                  !(liveConversation?.isLoading ?? false)
              ? _ChatEmpty(
                  onPrompt: _send,
                  mode: _mode,
                  agentName: widget.notebook.session.displayAgentName,
                )
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayedMessages.length + (isBusy ? 1 : 0),
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: scheme.outlineVariant.withValues(alpha: 0.55),
                  ),
                  itemBuilder: (context, index) {
                    if (index == displayedMessages.length) {
                      return _ThinkingBubble(
                        label: _isOpeningAgent
                            ? 'Opening realtime channel…'
                            : _researchStatus,
                      );
                    }
                    return _MessageEntry(message: displayedMessages[index]);
                  },
                ),
        ),
        if (_error != null || liveConversation?.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.alertCircle, size: 15, color: scheme.error),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    _error ?? liveConversation!.error!,
                    style: TextStyle(color: scheme.error, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        Divider(height: 1, color: scheme.outlineVariant),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _ChatModeModelDropdown(
                    mode: _mode,
                    model: selectedModel,
                    models: _allModels(groupedModels),
                    agentName: widget.notebook.session.displayAgentName,
                    agentAvailable: widget.notebook.session.id.isNotEmpty,
                    agentLive: isLive,
                    onModeSelected: _switchMode,
                    onModelSelected: (model) {
                      setState(() {
                        _selectedModelId = model.id;
                        _error = null;
                      });
                    },
                  ),
                  const Spacer(),
                  if (_mode == _MemoryChatMode.codingAgent)
                    LiveStatus(
                      label: isLive ? 'LIVE' : 'OFFLINE',
                      active: isLive,
                      compact: true,
                    )
                  else if (selectedModel != null)
                    Flexible(
                      child: Text(
                        selectedModel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontSize: 9,
                            ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !isBusy,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: switch (_mode) {
                          _MemoryChatMode.assistant =>
                            'Ask about this project memory…',
                          _MemoryChatMode.deepResearch =>
                            'Research with this notebook…',
                          _MemoryChatMode.codingAgent =>
                            'Message the coding agent…',
                        },
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: isBusy ? null : _send,
                    tooltip: 'Send',
                    icon: const Icon(LucideIcons.arrowUp, size: 18),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatModeModelDropdown extends StatelessWidget {
  const _ChatModeModelDropdown({
    required this.mode,
    required this.model,
    required this.models,
    required this.agentName,
    required this.agentAvailable,
    required this.agentLive,
    required this.onModeSelected,
    required this.onModelSelected,
  });

  final _MemoryChatMode mode;
  final AIModelOption? model;
  final List<AIModelOption> models;
  final String agentName;
  final bool agentAvailable;
  final bool agentLive;
  final ValueChanged<_MemoryChatMode> onModeSelected;
  final ValueChanged<AIModelOption> onModelSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = switch (mode) {
      _MemoryChatMode.assistant => 'Memory AI',
      _MemoryChatMode.deepResearch => 'Research',
      _MemoryChatMode.codingAgent => 'Coding agent',
    };

    return PopupMenuButton<String>(
      tooltip: 'Chat mode and AI model',
      position: PopupMenuPosition.under,
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      onSelected: (value) {
        if (value.startsWith('mode:')) {
          final modeName = value.substring(5);
          for (final item in _MemoryChatMode.values) {
            if (item.name == modeName) onModeSelected(item);
          }
          return;
        }
        if (!value.startsWith('model:')) return;
        final id = value.substring(6);
        for (final item in models) {
          if (item.id == id) {
            onModelSelected(item);
            return;
          }
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: _MenuHeading('CHAT MODE'),
        ),
        _modeItem(
          context,
          mode: _MemoryChatMode.assistant,
          icon: LucideIcons.messageSquare,
          title: 'Memory AI',
          subtitle: 'Answers from notebook memory',
        ),
        _modeItem(
          context,
          mode: _MemoryChatMode.deepResearch,
          icon: LucideIcons.search,
          title: 'Deep research',
          subtitle: 'Web research with memory context',
        ),
        _modeItem(
          context,
          mode: _MemoryChatMode.codingAgent,
          icon: LucideIcons.terminal,
          title: agentName,
          subtitle: agentLive ? 'Realtime · WebSocket' : 'Agent offline',
          enabled: agentAvailable,
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          enabled: false,
          height: 28,
          child: _MenuHeading('MODELS'),
        ),
        if (models.isEmpty)
          const PopupMenuItem<String>(
            enabled: false,
            child: Text('No active models configured'),
          )
        else
          ...models.map(
            (item) => PopupMenuItem<String>(
              value: 'model:${item.id}',
              enabled: item.canAccess,
              child: Row(
                children: [
                  Icon(
                    item.canAccess ? LucideIcons.sparkles : LucideIcons.lock,
                    size: 16,
                    color: item.canAccess
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.id == model?.id)
                    Icon(LucideIcons.check, size: 16, color: scheme.primary),
                ],
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              mode == _MemoryChatMode.codingAgent
                  ? LucideIcons.terminal
                  : mode == _MemoryChatMode.deepResearch
                      ? LucideIcons.search
                      : LucideIcons.sparkles,
              size: 13,
              color: scheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.chevronDown, size: 12),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _modeItem(
    BuildContext context, {
    required _MemoryChatMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
    bool enabled = true,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: 'mode:${mode.name}',
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 17, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          if (this.mode == mode)
            Icon(LucideIcons.check, size: 16, color: scheme.primary),
        ],
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontFamily: 'JetBrains Mono',
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty({
    required this.onPrompt,
    required this.mode,
    required this.agentName,
  });

  final ValueChanged<String> onPrompt;
  final _MemoryChatMode mode;
  final String agentName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, description, prompts) = switch (mode) {
      _MemoryChatMode.assistant => (
          'Talk to the notebook',
          'Answers use only the stored agent memories in this notebook.',
          const [
            'What is the current project state?',
            'What decisions have the agents made?',
            'What should happen next?',
          ],
        ),
      _MemoryChatMode.deepResearch => (
          'Research with memory context',
          'Search the web deeply while keeping this notebook in context.',
          const [
            'Research the best solution for our current blocker',
            'Find recent evidence related to this project',
            'Compare approaches and recommend the next step',
          ],
        ),
      _MemoryChatMode.codingAgent => (
          'Talk to $agentName',
          'Messages and replies synchronize in realtime over WebSocket.',
          const [
            'What are you working on now?',
            'Review the latest project decisions',
            'Explain the next coding step',
          ],
        ),
    };

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(LucideIcons.sparkles, size: 25, color: scheme.primary),
          const SizedBox(height: 11),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          ...prompts.map(
            (prompt) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: OutlinedButton(
                onPressed: () => onPrompt(prompt),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
                child: Text(
                  prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageEntry extends StatelessWidget {
  const _MessageEntry({required this.message});

  final MemoryChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            message.isUser ? 'YOU' : 'RESPONSE',
            style: TextStyle(
              color: message.isUser ? scheme.primary : scheme.onSurfaceVariant,
              fontFamily: 'JetBrains Mono',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.85,
            ),
          ),
          const SizedBox(height: 7),
          SelectableText(
            message.content,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          if (label?.isNotEmpty == true) ...[
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                label!,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error.toString().replaceFirst('Exception: ', '').trim();
  if (message.contains('404') || message.toLowerCase().contains('not found')) {
    return 'The live coding-agent channel could not open. Refresh the notebook or reconnect the agent.';
  }
  if (message.contains('401') || message.contains('403')) {
    return 'Your account cannot use this chat mode.';
  }
  if (message.toLowerCase().contains('socket')) {
    return 'The realtime agent connection is unavailable. Reconnect the agent and try again.';
  }
  return message.isEmpty ? 'The message could not be sent.' : message;
}
