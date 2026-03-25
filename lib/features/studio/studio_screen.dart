// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'audio_overview_provider.dart';
import 'audio_player_sheet.dart';
import 'artifact_provider.dart';
import '../notebook/notebook.dart';
import '../notebook/notebook_provider.dart';
import '../sources/source_provider.dart';
import '../../core/services/background_ai_service.dart';
import '../../core/theme/theme_provider.dart';
import '../subscription/services/credit_manager.dart';
import '../../ui/components/premium_card.dart';
import '../../ui/components/glass_container.dart';
import '../../theme/app_theme.dart';

class StudioScreen extends ConsumerStatefulWidget {
  final String? notebookId; // null = global view, otherwise notebook-specific

  const StudioScreen({super.key, this.notebookId});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  String? _generatingType;
  Timer? _backgroundStatusTimer;
  Map<String, dynamic>? _backgroundTaskStatus;
  String? _lastAnnouncedBackgroundState;

  @override
  void initState() {
    super.initState();
    _refreshBackgroundTaskStatus();
    _backgroundStatusTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshBackgroundTaskStatus(),
    );
  }

  @override
  void dispose() {
    _backgroundStatusTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final allSources = ref.watch(sourceProvider);
    final audioState = ref.watch(audioOverviewProvider);
    final audioOverviews = audioState.overviews;

    // Filter by notebook if notebookId is provided
    final sources = widget.notebookId != null
        ? allSources.where((s) => s.notebookId == widget.notebookId).toList()
        : allSources;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.notebookId != null ? 'Studio' : 'Global Studio'),
        centerTitle: true,
        flexibleSpace: GlassContainer(
          borderRadius: BorderRadius.zero,
          color: scheme.surface.withValues(alpha: 0.7),
          border: Border(
              bottom: BorderSide(color: scheme.outline.withValues(alpha: 0.1))),
          child: Container(),
        ),
        actions: [
          Consumer(builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return IconButton(
              icon: Icon(
                  mode == ThemeMode.dark ? LucideIcons.moon : LucideIcons.sun),
              tooltip: mode == ThemeMode.dark
                  ? 'Switch to Light Mode'
                  : 'Switch to Dark Mode',
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            );
          }),
          if (audioOverviews.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.headphones),
              tooltip: 'Audio History',
              onPressed: () => _showAudioHistory(context, ref, audioOverviews),
            ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
              scheme.surface,
              scheme.surfaceContainer,
            ])),
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                  height:
                      kToolbarHeight + MediaQuery.of(context).padding.top + 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    20, 10, 20, 100), // More bottom padding for scroll
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (sources.isEmpty)
                      _buildEmptyState(context)
                    else ...[
                      if (_shouldShowBackgroundTaskCard) ...[
                        _buildBackgroundTaskCard(context, ref),
                        const SizedBox(height: 32),
                      ],
                      // Audio Section (Podcast)
                      Text('Audio Experience',
                          style: text.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          )),
                      const SizedBox(height: 16),
                      _buildAudioCard(context, ref, audioState),

                      const SizedBox(height: 32),

                      // Visual/Text Artifacts
                      Text('Visual Support',
                          style: text.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          )),
                      const SizedBox(height: 16),
                      GridView(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          mainAxisExtent: 160,
                        ),
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          _TemplateCard(
                            title: 'Study Guide',
                            subtitle: 'Key concepts & summaries',
                            icon: LucideIcons.bookOpen,
                            color: Colors.blue,
                            isLoading: _generatingType == 'study-guide',
                            onTap: () => _showArtifactModeSheet(
                              context,
                              ref,
                              'study-guide',
                            ),
                          ),
                          _TemplateCard(
                            title: 'Executive Brief',
                            subtitle: 'Actionable insights',
                            icon: LucideIcons.fileText,
                            color: Colors.green,
                            isLoading: _generatingType == 'brief',
                            onTap: () => _showArtifactModeSheet(
                              context,
                              ref,
                              'brief',
                            ),
                          ),
                          _TemplateCard(
                            title: 'FAQ',
                            subtitle: 'Common questions',
                            icon: LucideIcons.helpCircle,
                            color: Colors.orange,
                            isLoading: _generatingType == 'faq',
                            onTap: () =>
                                _showArtifactModeSheet(context, ref, 'faq'),
                          ),
                          _TemplateCard(
                            title: 'Timeline',
                            subtitle: 'Chronological events',
                            icon: LucideIcons.calendarClock,
                            color: Colors.purple,
                            isLoading: _generatingType == 'timeline',
                            onTap: () => _showArtifactModeSheet(
                              context,
                              ref,
                              'timeline',
                            ),
                          ),
                          _TemplateCard(
                            title: 'Visual Studio',
                            subtitle: 'Generate Images',
                            icon: LucideIcons.image,
                            color: Colors.pink,
                            onTap: () => _openVisualStudio(),
                          ),
                          _TemplateCard(
                            title: 'Ebook Creator',
                            subtitle: 'AI Agents at work',
                            icon: LucideIcons.book,
                            color: Colors.indigo,
                            onTap: () => _openEbookCreator(),
                          ),
                        ].animate(interval: 50.ms).fadeIn().slideY(begin: 0.2),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const SizedBox(height: 40),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.outline.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(LucideIcons.library,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 16),
          Text(
            'Add sources to start creating',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      ).animate().fadeIn(),
    );
  }

  Widget _buildAudioCard(
      BuildContext context, WidgetRef ref, AudioStudioState state) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (state.isGenerating) {
      return PremiumCard(
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            SizedBox(
              height: 80,
              width: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: state.progressValue > 0
                        ? state.progressValue / 100
                        : null,
                    strokeWidth: 6,
                    strokeCap: StrokeCap.round,
                    color: scheme.primary,
                    backgroundColor: scheme.primary.withValues(alpha: 0.2),
                  ),
                  Icon(LucideIcons.mic, size: 32, color: scheme.primary),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              state.isCancelled ? 'Cancelling...' : 'Producing Podcast...',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              state.progressMessage,
              style: text.bodySmall?.copyWith(color: scheme.secondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            // Cancel button
            if (!state.isCancelled)
              OutlinedButton.icon(
                onPressed: () {
                  ref.read(audioOverviewProvider.notifier).cancelGeneration();
                },
                icon:
                    Icon(Icons.cancel_outlined, size: 18, color: scheme.error),
                label: Text('Cancel', style: TextStyle(color: scheme.error)),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
        ),
      ).animate().fadeIn();
    }

    return PremiumCard(
      isGlass: true, // Use glass effect for the main audio card
      padding: EdgeInsets.zero,
      onTap: () => _showPodcastSettings(context, ref),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.primary.withValues(alpha: 0.1),
              scheme.secondary.withValues(alpha: 0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(LucideIcons.headphones,
                    color: Colors.white, size: 36),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Podcast Studio',
                      style: text.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Build a custom podcast with a guided step-by-step setup.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.5),
                    shape: BoxShape.circle),
                child: Icon(LucideIcons.chevronRight, color: scheme.primary),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn().slideX();
  }

  Future<void> _showPodcastSettings(BuildContext context, WidgetRef ref) async {
    final notebookContext = await _resolveNotebookContext(
      actionLabel: 'create a podcast',
    );
    if (notebookContext == null || !mounted || !context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final initialHosts = [
      (prefs.getString(_podcastPrimaryHostPrefKey) ??
              _defaultPodcastPrimaryHost)
          .trim(),
      (prefs.getString(_podcastSecondaryHostPrefKey) ??
              _defaultPodcastSecondaryHost)
          .trim(),
    ];
    if (!mounted || !context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => _PodcastSettingsDialog(
        notebookTitle: notebookContext.title,
        initialHosts: initialHosts,
        onGenerate: (title, podcastType, topic, hosts) async {
          final normalizedHosts = [
            hosts.isNotEmpty && hosts.first.trim().isNotEmpty
                ? hosts.first.trim()
                : _defaultPodcastPrimaryHost,
            hosts.length > 1 && hosts[1].trim().isNotEmpty
                ? hosts[1].trim()
                : _defaultPodcastSecondaryHost,
          ];

          await prefs.setString(
            _podcastPrimaryHostPrefKey,
            normalizedHosts.first,
          );
          await prefs.setString(
            _podcastSecondaryHostPrefKey,
            normalizedHosts[1],
          );

          await _generateAudioOverview(
            ref,
            notebookId: notebookContext.id,
            notebookTitle: notebookContext.title,
            title: title,
            podcastType: podcastType,
            topic: topic,
            hosts: normalizedHosts,
          );
        },
      ),
    );
  }

  bool get _shouldShowBackgroundTaskCard {
    final status = _backgroundTaskStatus;
    if (status == null) return false;
    final value = (status['status'] as String? ?? 'idle').toLowerCase();
    final isRunning = status['isRunning'] == true;
    return isRunning || value != 'idle' || (status['error'] as String?) != null;
  }

  bool get _hasActiveBackgroundTask {
    final status = _backgroundTaskStatus;
    if (status == null) return false;
    final value = (status['status'] as String? ?? 'idle').toLowerCase();
    return status['isRunning'] == true ||
        value == 'starting' ||
        value == 'running' ||
        value == 'listening';
  }

  Future<void> _refreshBackgroundTaskStatus() async {
    final status = await backgroundAIService.getTaskStatus();

    if (!mounted) return;

    if ((status['status'] as String?) == 'completed') {
      await ref.read(artifactProvider.notifier).checkBackgroundTasks();
      final refreshed = await backgroundAIService.getTaskStatus();
      if (!mounted) return;
      setState(() => _backgroundTaskStatus = refreshed);
      if (_lastAnnouncedBackgroundState != 'completed') {
        _lastAnnouncedBackgroundState = 'completed';
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Background generation finished'),
          ),
        );
      }
      return;
    }

    final nextState = (status['status'] as String? ?? 'idle').toLowerCase();
    if (nextState != 'running' &&
        nextState != 'starting' &&
        nextState != 'completed') {
      _lastAnnouncedBackgroundState = null;
    }

    setState(() => _backgroundTaskStatus = status);
  }

  String _artifactTitle(String type) {
    switch (type) {
      case 'study-guide':
        return 'Study Guide';
      case 'brief':
        return 'Executive Brief';
      case 'faq':
        return 'FAQ';
      case 'timeline':
        return 'Timeline';
      default:
        return 'Artifact';
    }
  }

  String _formatBackgroundStatus(String? status) {
    switch ((status ?? 'idle').toLowerCase()) {
      case 'starting':
        return 'Starting';
      case 'running':
        return 'Generating';
      case 'completed':
        return 'Completed';
      case 'error':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'listening':
        return 'Listening';
      default:
        return 'Idle';
    }
  }

  String _backgroundStatusDescription(Map<String, dynamic> status) {
    final value = (status['status'] as String? ?? 'idle').toLowerCase();
    final progress = status['progress'] as int? ?? 0;
    final error = status['error'] as String?;

    switch (value) {
      case 'starting':
        return 'Preparing your cloud generation request and foreground notification.';
      case 'running':
        return progress > 0
            ? 'Background generation is running. Progress: $progress%.'
            : 'Background generation is running with an ongoing notification.';
      case 'completed':
        return 'The last background generation finished successfully.';
      case 'cancelled':
        return 'The current background task was stopped.';
      case 'error':
        return error == null || error.isEmpty
            ? 'The background task failed.'
            : error;
      default:
        return 'No background generation is currently active.';
    }
  }

  Widget _buildBackgroundTaskCard(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final status = _backgroundTaskStatus ??
        const {
          'status': 'idle',
          'progress': 0,
          'isRunning': false,
        };
    final progress = status['progress'] as int? ?? 0;
    final isActive = _hasActiveBackgroundTask;
    final label = _formatBackgroundStatus(status['status'] as String?);

    return PremiumCard(
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(LucideIcons.cloudCog, color: scheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Background Queue',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: text.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh background status',
                onPressed: _refreshBackgroundTaskStatus,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _backgroundStatusDescription(status),
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (isActive && progress > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: progress / 100,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: scheme.primary.withValues(alpha: 0.15),
            ),
          ],
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/background-settings'),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('Open Queue Settings'),
              ),
              if (isActive)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: _cancelBackgroundTask,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18),
                  label: const Text('Stop Task'),
                ),
            ],
          ),
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.08);
  }

  Future<void> _showArtifactModeSheet(
    BuildContext context,
    WidgetRef ref,
    String type,
  ) async {
    if (_generatingType != null) return;
    final notebookContext = await _resolveNotebookContext(
      actionLabel: 'create a ${_artifactTitle(type).toLowerCase()}',
    );
    if (notebookContext == null || !mounted || !context.mounted) return;

    final title = _artifactTitle(type);
    final hasActiveTask = _hasActiveBackgroundTask;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final text = Theme.of(sheetContext).textTheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose how you want to create this artifact.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.bookOpen,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Using notebook: ${notebookContext.title}',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    child: Icon(LucideIcons.sparkles, color: scheme.primary),
                  ),
                  title: const Text('Generate now'),
                  subtitle: const Text(
                    'Keep the app open and jump straight to the result when it is ready.',
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _generateArtifactNow(
                      ref,
                      type,
                      notebookId: notebookContext.id,
                    );
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: scheme.secondary.withValues(alpha: 0.12),
                    child: Icon(LucideIcons.cloudCog, color: scheme.secondary),
                  ),
                  title: const Text('Generate in background'),
                  subtitle: Text(
                    hasActiveTask
                        ? 'Finish or stop the current background task before starting another one.'
                        : 'Starts a foreground notification so you can leave the app while it runs.',
                  ),
                  enabled: !hasActiveTask,
                  onTap: hasActiveTask
                      ? null
                      : () {
                          Navigator.pop(sheetContext);
                          _generateArtifactInBackground(
                            ref,
                            type,
                            notebookId: notebookContext.id,
                          );
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _prepareArtifactGeneration(
    WidgetRef ref,
    String type, {
    required String notebookId,
  }) async {
    final allSources = ref.read(sourceProvider);
    final sources = allSources.where((s) => s.notebookId == notebookId).toList();

    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The selected notebook has no sources yet'),
        ),
      );
      return false;
    }

    final creditCost = type == 'study-guide'
        ? CreditCosts.generateStudyGuide
        : type == 'mind-map'
            ? CreditCosts.generateMindMap
            : CreditCosts.generateStudyGuide;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: creditCost,
      feature: 'generate_$type',
    );
    return hasCredits;
  }

  Future<void> _generateArtifactNow(
    WidgetRef ref,
    String type, {
    required String notebookId,
  }) async {
    if (_generatingType != null) return;
    final canProceed = await _prepareArtifactGeneration(
      ref,
      type,
      notebookId: notebookId,
    );
    if (!canProceed) return;

    setState(() => _generatingType = type);

    try {
      await ref.read(artifactProvider.notifier).generate(
            type,
            notebookId: notebookId,
            showBubble: true,
          );
      if (!mounted) return;
      final allArtifacts = ref.read(artifactProvider);
      if (allArtifacts.isNotEmpty) {
        context.push('/artifact', extra: allArtifacts.last);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingType = null);
      }
    }
  }

  Future<void> _generateArtifactInBackground(
    WidgetRef ref,
    String type, {
    required String notebookId,
  }) async {
    if (_generatingType != null || _hasActiveBackgroundTask) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Finish or stop the current background task before starting another one.',
            ),
          ),
        );
      }
      return;
    }

    final notificationsReady = await _ensureBackgroundNotificationPermission();
    if (!notificationsReady) return;
    if (!mounted) return;

    final canProceed = await _prepareArtifactGeneration(
      ref,
      type,
      notebookId: notebookId,
    );
    if (!canProceed) return;

    setState(() => _generatingType = type);

    try {
      final started =
          await ref.read(artifactProvider.notifier).generateInBackground(
                type,
                notebookId: notebookId,
              );

      await _refreshBackgroundTaskStatus();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            started
                ? '${_artifactTitle(type)} is running in the background. You can leave the app after the notification appears.'
                : 'Background generation could not start.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingType = null);
      }
    }
  }

  Future<void> _cancelBackgroundTask() async {
    await backgroundAIService.cancelActiveTask();
    await _refreshBackgroundTaskStatus();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Background task stopped')),
    );
  }

  Future<bool> _ensureBackgroundNotificationPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) {
      return true;
    }

    final requested = await Permission.notification.request();
    if (requested.isGranted) {
      return true;
    }

    if (!mounted) return false;

    final openSettings = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Notification Permission Needed'),
            content: const Text(
              'Background generation needs notification permission so Android can show the required ongoing foreground-service notification.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Open Settings'),
              ),
            ],
          ),
        ) ??
        false;

    if (openSettings) {
      await openAppSettings();
    }

    return false;
  }

  Future<void> _generateAudioOverview(
    WidgetRef ref, {
    required String notebookId,
    required String notebookTitle,
    required String title,
    required String podcastType,
    required List<String> hosts,
    String? topic,
  }) async {
    final notebookSources = ref
        .read(sourceProvider)
        .where((source) => source.notebookId == notebookId)
        .toList();
    if (notebookSources.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add sources to "$notebookTitle" before generating a podcast.',
          ),
        ),
      );
      return;
    }

    // Check and consume credits for podcast generation
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.podcastGeneration,
      feature: 'podcast_generation',
    );
    if (!hasCredits) return;

    try {
      await ref.read(audioOverviewProvider.notifier).generate(
            title,
            isPodcast: true,
            topic: topic,
            hosts: hosts,
            podcastType: podcastType,
            notebookId: notebookId,
          );

      // We don't need a snackbar here because the UI updates to show generation progress
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Error generating audio: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  void _showAudioHistory(
      BuildContext context, WidgetRef ref, List<dynamic> items) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Text('Audio History',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(),
            ListView.builder(
              shrinkWrap: true,
              itemCount: items.length,
              itemBuilder: (context, index) {
                final ov = items[items.length - 1 - index];
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(LucideIcons.headphones,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(ov.title),
                  subtitle: Text(
                      '${ov.createdAt.day}/${ov.createdAt.month} • ${ov.duration.inMinutes}m'),
                  onTap: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => AudioPlayerSheet(overview: ov),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<_StudioNotebookContext?> _resolveNotebookContext({
    required String actionLabel,
  }) async {
    if (widget.notebookId != null && widget.notebookId!.isNotEmpty) {
      final notebooks = ref.read(notebookProvider);
      final notebook = notebooks.where((n) => n.id == widget.notebookId).firstOrNull;
      if (notebook != null) {
        return _StudioNotebookContext.fromNotebook(notebook);
      }

      return _StudioNotebookContext(
        id: widget.notebookId!,
        title: 'Selected notebook',
        sourceCount: ref
            .read(sourceProvider)
            .where((source) => source.notebookId == widget.notebookId)
            .length,
      );
    }

    final notebooks = ref
        .read(notebookProvider)
        .where((notebook) => notebook.sourceCount > 0)
        .toList();

    if (notebooks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Create a notebook and add sources before using Studio tools.',
            ),
          ),
        );
      }
      return null;
    }

    final selected = await showModalBottomSheet<_StudioNotebookContext>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final text = Theme.of(sheetContext).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose notebook',
                  style: text.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Select which notebook to use before you $actionLabel.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: notebooks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final notebook = notebooks[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.12),
                          ),
                        ),
                        tileColor: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        leading: CircleAvatar(
                          backgroundColor: scheme.primary.withValues(alpha: 0.12),
                          child: Icon(
                            LucideIcons.bookOpen,
                            color: scheme.primary,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          notebook.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${notebook.sourceCount} sources',
                        ),
                        trailing: Icon(
                          LucideIcons.chevronRight,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                        onTap: () => Navigator.pop(
                          sheetContext,
                          _StudioNotebookContext.fromNotebook(notebook),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return null;
    return selected;
  }

  Future<void> _openVisualStudio() async {
    final notebookContext = await _resolveNotebookContext(
      actionLabel: 'generate an image',
    );
    if (notebookContext == null || !mounted) return;

    context.push(
      '/visual-studio',
      extra: {
        'notebookId': notebookContext.id,
        'notebookTitle': notebookContext.title,
      },
    );
  }

  Future<void> _openEbookCreator() async {
    final notebookContext = await _resolveNotebookContext(
      actionLabel: 'start an ebook',
    );
    if (notebookContext == null || !mounted) return;

    context.push(
      '/ebook-creator',
      extra: {
        'notebookId': notebookContext.id,
        'notebookTitle': notebookContext.title,
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -10,
            top: -10,
            child: Icon(icon, size: 80, color: color.withValues(alpha: 0.1)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: isLoading
                      ? SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: color,
                          ),
                        )
                      : Icon(
                          icon,
                          color: color,
                          size: 24,
                        ),
                ),
                const Spacer(),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          )
        ],
      ),
    );
    // ... replaced standard Card logic with PremiumCard and improved layout
  }
}

const _podcastTypeOptions = [
  _PodcastTypeOption(
    id: 'deep_dive',
    label: 'Deep Dive',
    description: 'Detailed and conversational with extra context and analysis.',
    defaultTitle: 'Deep Dive Podcast',
    icon: LucideIcons.mic,
  ),
  _PodcastTypeOption(
    id: 'quick_brief',
    label: 'Quick Brief',
    description: 'Fast highlights and takeaways in a short episode.',
    defaultTitle: 'Quick Brief Podcast',
    icon: LucideIcons.sparkles,
  ),
  _PodcastTypeOption(
    id: 'debate',
    label: 'Debate',
    description:
        'Two hosts challenge each other with pros, cons, and tradeoffs.',
    defaultTitle: 'Debate Podcast',
    icon: LucideIcons.messageSquare,
  ),
  _PodcastTypeOption(
    id: 'storytelling',
    label: 'Storytelling',
    description: 'More narrative and example-driven with a polished flow.',
    defaultTitle: 'Storytelling Podcast',
    icon: LucideIcons.bookOpen,
  ),
  _PodcastTypeOption(
    id: 'interview',
    label: 'Interview',
    description:
        'One host leads with questions while the other teaches and explains.',
    defaultTitle: 'Interview Podcast',
    icon: LucideIcons.users,
  ),
  _PodcastTypeOption(
    id: 'news_roundup',
    label: 'News Roundup',
    description: 'Headline-style coverage with fast updates and context.',
    defaultTitle: 'News Roundup Podcast',
    icon: LucideIcons.fileText,
  ),
  _PodcastTypeOption(
    id: 'teaching_mode',
    label: 'Teaching Mode',
    description: 'Clear, step-by-step explanations designed for learning.',
    defaultTitle: 'Teaching Mode Podcast',
    icon: LucideIcons.graduationCap,
  ),
];

const _podcastPrimaryHostPrefKey = 'podcast_primary_host_name';
const _podcastSecondaryHostPrefKey = 'podcast_secondary_host_name';
const _defaultPodcastPrimaryHost = 'Sarah';
const _defaultPodcastSecondaryHost = 'Adam';

class _PodcastTypeOption {
  const _PodcastTypeOption({
    required this.id,
    required this.label,
    required this.description,
    required this.defaultTitle,
    required this.icon,
  });

  final String id;
  final String label;
  final String description;
  final String defaultTitle;
  final IconData icon;
}

class _PodcastWizardStep {
  const _PodcastWizardStep({
    required this.label,
    required this.icon,
    required this.subtitle,
  });

  final String label;
  final IconData icon;
  final String subtitle;
}

const _podcastWizardSteps = [
  _PodcastWizardStep(
    label: 'Format',
    icon: Icons.tune_rounded,
    subtitle: 'Choose the podcast style',
  ),
  _PodcastWizardStep(
    label: 'Angle',
    icon: Icons.edit_note_rounded,
    subtitle: 'Set the title and focus',
  ),
  _PodcastWizardStep(
    label: 'Hosts',
    icon: Icons.people_alt_outlined,
    subtitle: 'Name the hosts and review',
  ),
];

_PodcastTypeOption _podcastTypeById(String id) {
  return _podcastTypeOptions.firstWhere(
    (option) => option.id == id,
    orElse: () => _podcastTypeOptions.first,
  );
}

/// Step-by-step podcast setup dialog for Studio.
class _PodcastSettingsDialog extends StatefulWidget {
  final String notebookTitle;
  final List<String> initialHosts;
  final Future<void> Function(
    String title,
    String podcastType,
    String? topic,
    List<String> hosts,
  ) onGenerate;

  const _PodcastSettingsDialog({
    required this.notebookTitle,
    required this.initialHosts,
    required this.onGenerate,
  });

  @override
  State<_PodcastSettingsDialog> createState() => _PodcastSettingsDialogState();
}

class _PodcastSettingsDialogState extends State<_PodcastSettingsDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _primaryHostController;
  late final TextEditingController _secondaryHostController;
  late final TextEditingController _topicController;
  String _selectedType = _podcastTypeOptions.first.id;
  bool _hasCustomTitle = false;
  int _currentStep = 0;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: _podcastTypeOptions.first.defaultTitle,
    );
    _primaryHostController = TextEditingController(
      text: widget.initialHosts.isNotEmpty &&
              widget.initialHosts.first.trim().isNotEmpty
          ? widget.initialHosts.first.trim()
          : _defaultPodcastPrimaryHost,
    );
    _secondaryHostController = TextEditingController(
      text: widget.initialHosts.length > 1 &&
              widget.initialHosts[1].trim().isNotEmpty
          ? widget.initialHosts[1].trim()
          : _defaultPodcastSecondaryHost,
    );
    _topicController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _primaryHostController.dispose();
    _secondaryHostController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  void _selectPodcastType(String type) {
    if (type == _selectedType) return;

    final previousDefault = _podcastTypeById(_selectedType).defaultTitle;
    final nextDefault = _podcastTypeById(type).defaultTitle;
    final currentTitle = _titleController.text.trim();
    final shouldRefreshTitle = !_hasCustomTitle ||
        currentTitle.isEmpty ||
        currentTitle == previousDefault;

    setState(() {
      _selectedType = type;
    });

    if (shouldRefreshTitle) {
      _titleController.value = TextEditingValue(
        text: nextDefault,
        selection: TextSelection.collapsed(offset: nextDefault.length),
      );
      _hasCustomTitle = false;
    }
  }

  String get _resolvedTitle {
    final title = _titleController.text.trim();
    return title.isEmpty ? _podcastTypeById(_selectedType).defaultTitle : title;
  }

  String? get _resolvedTopic {
    final topic = _topicController.text.trim();
    return topic.isEmpty ? null : topic;
  }

  List<String> get _resolvedHosts => [
        _primaryHostController.text.trim().isEmpty
            ? _defaultPodcastPrimaryHost
            : _primaryHostController.text.trim(),
        _secondaryHostController.text.trim().isEmpty
            ? _defaultPodcastSecondaryHost
            : _secondaryHostController.text.trim(),
      ];

  bool get _isLastStep => _currentStep == _podcastWizardSteps.length - 1;

  void _moveStep(int delta) {
    final nextStep = _currentStep + delta;
    if (nextStep < 0 || nextStep >= _podcastWizardSteps.length) return;
    setState(() => _currentStep = nextStep);
  }

  Future<void> _submit() async {
    Navigator.pop(context);
    await widget.onGenerate(
      _resolvedTitle,
      _selectedType,
      _resolvedTopic,
      _resolvedHosts,
    );
  }

  Widget _buildStepIndicator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: List.generate(_podcastWizardSteps.length, (index) {
        final step = _podcastWizardSteps[index];
        final isActive = index == _currentStep;
        final isComplete = index < _currentStep;
        final accentColor = isComplete || isActive
            ? scheme.primary
            : scheme.outline.withValues(alpha: 0.7);

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index == _podcastWizardSteps.length - 1 ? 0 : 12,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isActive
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surface.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: accentColor.withValues(alpha: isActive ? 0.45 : 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isComplete || isActive
                          ? accentColor
                          : accentColor.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: isComplete
                        ? Icon(
                            Icons.check,
                            size: 16,
                            color: scheme.onPrimary,
                          )
                        : Icon(
                            step.icon,
                            size: 16,
                            color: isActive
                                ? scheme.onPrimary
                                : scheme.onSurfaceVariant,
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.label,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required Widget child,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: scheme.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildSummaryChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text.rich(
              TextSpan(
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent(
    BuildContext context,
    _PodcastTypeOption selectedType,
  ) {
    switch (_currentStep) {
      case 0:
        return _buildSectionCard(
          context,
          icon: Icons.podcasts_rounded,
          title: 'Pick the format',
          description:
              'Start with the podcast style. The next step will shape the title and focus around this choice.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _podcastTypeOptions.map((option) {
                  final isSelected = option.id == _selectedType;
                  return ChoiceChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(option.icon, size: 16),
                        const SizedBox(width: 6),
                        Text(option.label),
                      ],
                    ),
                    onSelected: (_) => _selectPodcastType(option.id),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.14),
                  ),
                ),
                child: Text(
                  selectedType.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
            ],
          ),
        );
      case 1:
        return _buildSectionCard(
          context,
          icon: Icons.edit_rounded,
          title: 'Set the angle',
          description:
              'Give the episode a clear title and optionally point the hosts toward a specific topic or question.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Episode Title',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: selectedType.defaultTitle,
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (value) {
                  final trimmed = value.trim();
                  _hasCustomTitle = trimmed.isNotEmpty &&
                      trimmed != _podcastTypeById(_selectedType).defaultTitle;
                  setState(() {});
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Focus Topic (Optional)',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _topicController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText:
                      'e.g. "Key financial metrics" or "What changed after the new policy"',
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildSummaryChip(
                    context,
                    icon: LucideIcons.layers,
                    label: 'Format',
                    value: selectedType.label,
                  ),
                  _buildSummaryChip(
                    context,
                    icon: LucideIcons.type,
                    label: 'Suggested title',
                    value: _resolvedTitle,
                  ),
                ],
              ),
            ],
          ),
        );
      default:
        final hosts = _resolvedHosts;
        return _buildSectionCard(
          context,
          icon: LucideIcons.users,
          title: 'Name the hosts',
          description:
              'Pick the two AI host names for this episode. Your last custom names will still be remembered.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _primaryHostController,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _defaultPodcastPrimaryHost,
                        labelText: 'Host 1',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _secondaryHostController,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: _defaultPodcastSecondaryHost,
                        labelText: 'Host 2',
                        prefixIcon: const Icon(Icons.person_outline),
                        filled: true,
                        fillColor: Theme.of(context)
                            .colorScheme
                            .surface
                            .withValues(alpha: 0.5),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.14),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready to generate',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _buildSummaryChip(
                          context,
                          icon: LucideIcons.bookOpen,
                          label: 'Notebook',
                          value: widget.notebookTitle,
                        ),
                        _buildSummaryChip(
                          context,
                          icon: Icons.podcasts_rounded,
                          label: 'Format',
                          value: selectedType.label,
                        ),
                        _buildSummaryChip(
                          context,
                          icon: LucideIcons.type,
                          label: 'Title',
                          value: _resolvedTitle,
                        ),
                        if (_resolvedTopic != null)
                          _buildSummaryChip(
                            context,
                            icon: Icons.gps_fixed_rounded,
                            label: 'Focus',
                            value: _resolvedTopic!,
                          ),
                        _buildSummaryChip(
                          context,
                          icon: LucideIcons.users,
                          label: 'Hosts',
                          value: '${hosts[0]} and ${hosts[1]}',
                        ),
                        _buildSummaryChip(
                          context,
                          icon: LucideIcons.coins,
                          label: 'Cost',
                          value:
                              '${CreditCosts.podcastGeneration} AI Credits',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = _podcastTypeById(_selectedType);
    final currentStep = _podcastWizardSteps[_currentStep];
    final useCompactActions = MediaQuery.of(context).size.width < 430;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: GlassContainer(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      LucideIcons.headphones,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Podcast Generator',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Step ${_currentStep + 1} of ${_podcastWizardSteps.length}: ${currentStep.label}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color:
                                      Theme.of(context).colorScheme.secondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.bookOpen,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Using notebook: ${widget.notebookTitle}',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _buildStepIndicator(context),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: KeyedSubtree(
                    key: ValueKey(_currentStep),
                    child: _buildStepContent(context, selectedType),
                  ),
                ),
                const SizedBox(height: 24),
                if (useCompactActions) ...[
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      if (_currentStep > 0)
                        OutlinedButton(
                          onPressed: () => _moveStep(-1),
                          child: const Text('Back'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed:
                          _isLastStep ? _submit : () => _moveStep(1),
                      icon: Icon(
                        _isLastStep
                            ? LucideIcons.sparkles
                            : LucideIcons.arrowRight,
                        size: 18,
                      ),
                      label: Text(_isLastStep ? 'Generate Podcast' : 'Next'),
                    ),
                  ),
                ] else
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const Spacer(),
                      if (_currentStep > 0) ...[
                        OutlinedButton(
                          onPressed: () => _moveStep(-1),
                          child: const Text('Back'),
                        ),
                        const SizedBox(width: 10),
                      ],
                      FilledButton.icon(
                        onPressed:
                            _isLastStep ? _submit : () => _moveStep(1),
                        icon: Icon(
                          _isLastStep
                              ? LucideIcons.sparkles
                              : LucideIcons.arrowRight,
                          size: 18,
                        ),
                        label:
                            Text(_isLastStep ? 'Generate Podcast' : 'Next'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StudioNotebookContext {
  const _StudioNotebookContext({
    required this.id,
    required this.title,
    required this.sourceCount,
  });

  factory _StudioNotebookContext.fromNotebook(Notebook notebook) {
    return _StudioNotebookContext(
      id: notebook.id,
      title: notebook.title,
      sourceCount: notebook.sourceCount,
    );
  }

  final String id;
  final String title;
  final int sourceCount;
}
