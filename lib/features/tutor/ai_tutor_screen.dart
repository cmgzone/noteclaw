import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'tutor_session.dart';
import 'tutor_provider.dart';
import '../sources/source_provider.dart';
import '../notebook/notebook_provider.dart';
import '../subscription/services/credit_manager.dart';

class AITutorScreen extends ConsumerStatefulWidget {
  final String notebookId;
  final String? sessionId;

  const AITutorScreen({
    super.key,
    required this.notebookId,
    this.sessionId,
  });

  @override
  ConsumerState<AITutorScreen> createState() => _AITutorScreenState();
}

class _AITutorScreenState extends ConsumerState<AITutorScreen> {
  final _responseController = TextEditingController();
  final _scrollController = ScrollController();
  TutorSession? _session;
  bool _isLoading = false;
  bool _isStarting = true;
  String? _currentExchangeId;

  // Session setup
  String _topic = '';
  TutorDifficulty _difficulty = TutorDifficulty.adaptive;
  TutorStyle _style = TutorStyle.socratic;
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    if (widget.sessionId != null) {
      _loadExistingSession();
    }
  }

  void _loadExistingSession() {
    final session =
        ref.read(tutorProvider.notifier).getSession(widget.sessionId!);
    if (session != null) {
      setState(() {
        _session = session;
        _isStarting = false;
        _topic = session.topic;
        _difficulty = session.difficulty;
        _style = session.style;
        _selectedSourceId = session.sourceId;
      });
    }
  }

  @override
  void dispose() {
    _responseController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startSession() async {
    if (_topic.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a topic to study')),
      );
      return;
    }

    // Check and consume credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.tutorSession,
      feature: 'tutor_session',
    );
    if (!hasCredits) return;

    setState(() => _isLoading = true);

    try {
      final session = await ref.read(tutorProvider.notifier).startSession(
            notebookId: widget.notebookId,
            topic: _topic.trim(),
            sourceId: _selectedSourceId,
            difficulty: _difficulty,
            style: _style,
          );

      setState(() {
        _session = session;
        _isStarting = false;
      });

      // Generate first question
      await _generateNextExchange();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting session: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateNextExchange() async {
    if (_session == null) return;

    setState(() => _isLoading = true);

    try {
      final exchange = await ref
          .read(tutorProvider.notifier)
          .generateNextExchange(_session!.id);

      setState(() {
        _session = ref.read(tutorProvider.notifier).getSession(_session!.id);
        _currentExchangeId = exchange.id;
      });

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitResponse() async {
    final response = _responseController.text.trim();
    if (response.isEmpty || _session == null || _currentExchangeId == null) {
      return;
    }

    setState(() => _isLoading = true);
    _responseController.clear();

    try {
      await ref.read(tutorProvider.notifier).processResponse(
            _session!.id,
            _currentExchangeId!,
            response,
          );

      setState(() {
        _session = ref.read(tutorProvider.notifier).getSession(_session!.id);
      });

      _scrollToBottom();

      // Auto-generate next question after a delay
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted && !_session!.isComplete) {
        await _generateNextExchange();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestHint() async {
    if (_session == null) return;

    setState(() => _isLoading = true);

    try {
      // Add a hint request to the session
      await _generateNextExchange();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _endSession() async {
    if (_session == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Session?'),
        content: const Text(
          'This will generate a summary of your learning session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Continue Learning'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('End Session'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(tutorProvider.notifier).endSession(_session!.id);
      setState(() {
        _session = ref.read(tutorProvider.notifier).getSession(_session!.id);
      });
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Watch notebooks for reactivity
    ref.watch(notebookProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBackToTutorSessions,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Tutor'),
            if (!_isStarting && _session != null)
              Text(
                _session!.topic,
                style: text.bodySmall?.copyWith(
                  color: scheme.onPrimary.withValues(alpha: 0.7),
                ),
              ),
          ],
        ),
        actions: [
          if (!_isStarting && _session != null && !_session!.isComplete)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'End Session',
              onPressed: _endSession,
            ),
        ],
      ),
      body: _isStarting
          ? _buildSetupView(scheme, text)
          : _buildSessionView(scheme, text),
    );
  }

  Widget _buildSetupView(ColorScheme scheme, TextTheme text) {
    final sources = ref.watch(sourceProvider);
    final notebookSources =
        sources.where((s) => s.notebookId == widget.notebookId).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.school,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Tutor Mode',
                        style: text.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Learn through guided questioning',
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ).animate().fadeIn().slideY(begin: -0.2),

          const SizedBox(height: 32),

          // Topic input
          Text('What would you like to learn?', style: text.titleMedium),
          const SizedBox(height: 12),
          TextField(
            onChanged: (v) => setState(() => _topic = v),
            decoration: InputDecoration(
              hintText: 'e.g., Photosynthesis, World War II, Calculus...',
              prefixIcon: const Icon(Icons.lightbulb_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ).animate().fadeIn(delay: 100.ms),

          const SizedBox(height: 24),

          // Source selection
          Text('Focus on specific source (optional)', style: text.titleMedium),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _selectedSourceId,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.source),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            style: TextStyle(color: scheme.onSurface),
            dropdownColor: scheme.surface,
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(
                  'All sources in notebook',
                  style: TextStyle(color: scheme.onSurface),
                ),
              ),
              ...notebookSources.map((s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(
                      s.title,
                      style: TextStyle(color: scheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                  )),
            ],
            onChanged: (v) => setState(() => _selectedSourceId = v),
            selectedItemBuilder: (context) {
              return [
                Text(
                  'All sources in notebook',
                  style: TextStyle(color: scheme.onSurface),
                ),
                ...notebookSources.map((s) => Text(
                      s.title,
                      style: TextStyle(color: scheme.onSurface),
                      overflow: TextOverflow.ellipsis,
                    )),
              ];
            },
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 24),

          // Difficulty selection
          Text('Difficulty Level', style: text.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TutorDifficulty.values.map((d) {
              final selected = _difficulty == d;
              return ChoiceChip(
                label: Text(d.displayName),
                selected: selected,
                onSelected: (_) => setState(() => _difficulty = d),
                avatar: selected ? const Icon(Icons.check, size: 18) : null,
              );
            }).toList(),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 24),

          // Teaching style
          Text('Teaching Style', style: text.titleMedium),
          const SizedBox(height: 12),
          ...TutorStyle.values
              .map((s) {
                final selected = _style == s;
                return Card(
                  color: selected ? scheme.primaryContainer : null,
                  child: ListTile(
                    leading: Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? scheme.primary : scheme.outline,
                    ),
                    title: Text(s.displayName),
                    subtitle: Text(s.description),
                    onTap: () => setState(() => _style = s),
                  ),
                );
              })
              .toList()
              .animate(interval: 50.ms)
              .fadeIn()
              .slideX(begin: 0.1),

          const SizedBox(height: 32),

          // Start button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _startSession,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label:
                  Text(_isLoading ? 'Starting...' : 'Start Tutoring Session'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 500.ms)
              .scale(begin: const Offset(0.95, 0.95)),
        ],
      ),
    );
  }

  Widget _buildSessionView(ColorScheme scheme, TextTheme text) {
    if (_session == null) return const SizedBox();

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatChip(
                icon: Icons.help_outline,
                label: 'Questions',
                value: '${_session!.questionsAsked}',
              ),
              _StatChip(
                icon: Icons.check_circle_outline,
                label: 'Correct',
                value: '${_session!.correctAnswers}',
                color: Colors.green,
              ),
              _StatChip(
                icon: Icons.percent,
                label: 'Accuracy',
                value: '${(_session!.accuracy * 100).toStringAsFixed(0)}%',
                color: _session!.accuracy >= 0.7 ? Colors.green : Colors.orange,
              ),
            ],
          ),
        ),

        // Exchanges list
        Expanded(
          child: _session!.exchanges.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Preparing your first question...',
                          style: text.bodyMedium),
                    ],
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _session!.exchanges.length,
                  itemBuilder: (context, index) {
                    final exchange = _session!.exchanges[index];
                    return _ExchangeCard(
                      exchange: exchange,
                      isLatest: index == _session!.exchanges.length - 1,
                    ).animate().fadeIn(
                          delay: Duration(milliseconds: index * 100),
                        );
                  },
                ),
        ),

        // Loading indicator
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text('Thinking...', style: text.bodySmall),
              ],
            ),
          ),

        // Input area (only if session not complete)
        if (!_session!.isComplete)
          _buildInputArea(scheme, text)
        else
          Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Session complete',
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your summary is saved in this session. You can return to the tutor session list or start a fresh one.',
                    textAlign: TextAlign.center,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _goBackToTutorSessions,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Back to Tutor Sessions'),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputArea(ColorScheme scheme, TextTheme text) {
    final lastExchange = _session?.exchanges.lastOrNull;
    final needsResponse = lastExchange != null &&
        lastExchange.type == ExchangeType.question &&
        lastExchange.userResponse == null;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (needsResponse) ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _responseController,
                    decoration: InputDecoration(
                      hintText: 'Type your answer...',
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitResponse(),
                    enabled: !_isLoading,
                  ),
                ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  onPressed: _isLoading ? null : _submitResponse,
                  mini: true,
                  child: const Icon(Icons.send),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _isLoading ? null : _requestHint,
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: const Text('Get a hint'),
                ),
                const SizedBox(width: 16),
                TextButton.icon(
                  onPressed: _isLoading ? null : _generateNextExchange,
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Skip'),
                ),
              ],
            ),
          ] else ...[
            FilledButton.icon(
              onPressed: _isLoading ? null : _generateNextExchange,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Next Question'),
            ),
          ],
        ],
      ),
    );
  }

  void _goBackToTutorSessions() {
    if (!mounted) return;
    context.go('/notebook/${widget.notebookId}/tutor-sessions');
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.primary;

    return Column(
      children: [
        Icon(icon, color: effectiveColor, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: effectiveColor,
          ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ExchangeCard extends StatelessWidget {
  final TutorExchange exchange;
  final bool isLatest;

  const _ExchangeCard({
    required this.exchange,
    this.isLatest = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      color: _getCardColor(scheme),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getBadgeColor(scheme),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_getIcon(), size: 14, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        _getTypeLabel(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (exchange.wasCorrect != null)
                  Icon(
                    exchange.wasCorrect! ? Icons.check_circle : Icons.cancel,
                    color: exchange.wasCorrect! ? Colors.green : Colors.orange,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Content
            Text(
              exchange.content,
              style: text.bodyLarge,
            ),

            // User response
            if (exchange.userResponse != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your answer:',
                      style: text.labelSmall?.copyWith(
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(exchange.userResponse!),
                  ],
                ),
              ),
            ],

            // Feedback
            if (exchange.feedback != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: exchange.wasCorrect == true
                      ? Colors.green.withValues(alpha: 0.1)
                      : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: exchange.wasCorrect == true
                        ? Colors.green.withValues(alpha: 0.3)
                        : Colors.orange.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      exchange.wasCorrect == true
                          ? Icons.thumb_up
                          : Icons.info_outline,
                      size: 18,
                      color: exchange.wasCorrect == true
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(exchange.feedback!)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getCardColor(ColorScheme scheme) {
    switch (exchange.type) {
      case ExchangeType.summary:
        return scheme.tertiaryContainer;
      case ExchangeType.encouragement:
        return Colors.green.withValues(alpha: 0.1);
      default:
        return scheme.surface;
    }
  }

  Color _getBadgeColor(ColorScheme scheme) {
    switch (exchange.type) {
      case ExchangeType.question:
        return scheme.primary;
      case ExchangeType.hint:
        return Colors.amber;
      case ExchangeType.explanation:
        return scheme.secondary;
      case ExchangeType.encouragement:
        return Colors.green;
      case ExchangeType.correction:
        return Colors.orange;
      case ExchangeType.summary:
        return scheme.tertiary;
    }
  }

  IconData _getIcon() {
    switch (exchange.type) {
      case ExchangeType.question:
        return Icons.help_outline;
      case ExchangeType.hint:
        return Icons.lightbulb_outline;
      case ExchangeType.explanation:
        return Icons.school;
      case ExchangeType.encouragement:
        return Icons.celebration;
      case ExchangeType.correction:
        return Icons.edit;
      case ExchangeType.summary:
        return Icons.summarize;
    }
  }

  String _getTypeLabel() {
    switch (exchange.type) {
      case ExchangeType.question:
        return 'Question';
      case ExchangeType.hint:
        return 'Hint';
      case ExchangeType.explanation:
        return 'Explanation';
      case ExchangeType.encouragement:
        return 'Great job!';
      case ExchangeType.correction:
        return 'Let\'s review';
      case ExchangeType.summary:
        return 'Session Summary';
    }
  }
}
