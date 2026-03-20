// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'audio_overview_provider.dart';
import 'audio_player_sheet.dart';
import 'artifact_provider.dart';
import '../sources/source_provider.dart';
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
                            onTap: () =>
                                _generateArtifact(context, ref, 'study-guide'),
                          ),
                          _TemplateCard(
                            title: 'Executive Brief',
                            subtitle: 'Actionable insights',
                            icon: LucideIcons.fileText,
                            color: Colors.green,
                            isLoading: _generatingType == 'brief',
                            onTap: () =>
                                _generateArtifact(context, ref, 'brief'),
                          ),
                          _TemplateCard(
                            title: 'FAQ',
                            subtitle: 'Common questions',
                            icon: LucideIcons.helpCircle,
                            color: Colors.orange,
                            isLoading: _generatingType == 'faq',
                            onTap: () => _generateArtifact(context, ref, 'faq'),
                          ),
                          _TemplateCard(
                            title: 'Timeline',
                            subtitle: 'Chronological events',
                            icon: LucideIcons.calendarClock,
                            color: Colors.purple,
                            isLoading: _generatingType == 'timeline',
                            onTap: () =>
                                _generateArtifact(context, ref, 'timeline'),
                          ),
                          _TemplateCard(
                            title: 'Visual Studio',
                            subtitle: 'Generate Images',
                            icon: LucideIcons.image,
                            color: Colors.pink,
                            onTap: () => context.push('/visual-studio'),
                          ),
                          _TemplateCard(
                            title: 'Ebook Creator',
                            subtitle: 'AI Agents at work',
                            icon: LucideIcons.book,
                            color: Colors.indigo,
                            onTap: () => context.push('/ebook-creator'),
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
                      'Choose a title, style, and focus to generate a custom podcast.',
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

  void _showPodcastSettings(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => _PodcastSettingsDialog(
        onGenerate: (title, podcastType, topic) => _generateAudioOverview(
          ref,
          title: title,
          podcastType: podcastType,
          topic: topic,
        ),
      ),
    );
  }

  void _generateArtifact(
      BuildContext context, WidgetRef ref, String type) async {
    if (_generatingType != null) return;

    // Check sources
    final allSources = ref.read(sourceProvider);
    final sources = widget.notebookId != null
        ? allSources.where((s) => s.notebookId == widget.notebookId).toList()
        : allSources;

    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some sources first')),
      );
      return;
    }

    // Check and consume credits based on artifact type
    final creditCost = type == 'study-guide'
        ? CreditCosts.generateStudyGuide
        : type == 'mind-map'
            ? CreditCosts.generateMindMap
            : CreditCosts
                .generateStudyGuide; // Default cost for other artifacts

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: creditCost,
      feature: 'generate_$type',
    );
    if (!hasCredits) return;

    setState(() => _generatingType = type);

    try {
      await ref.read(artifactProvider.notifier).generate(
            type,
            notebookId: widget.notebookId,
            showBubble: true,
          );
      if (context.mounted) {
        final allArtifacts = ref.read(artifactProvider);
        if (allArtifacts.isNotEmpty) {
          context.push('/artifact', extra: allArtifacts.last);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _generatingType = null);
      }
    }
  }

  Future<void> _generateAudioOverview(
    WidgetRef ref, {
    required String title,
    required String podcastType,
    String? topic,
  }) async {
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
            podcastType: podcastType,
            notebookId: widget.notebookId,
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

_PodcastTypeOption _podcastTypeById(String id) {
  return _podcastTypeOptions.firstWhere(
    (option) => option.id == id,
    orElse: () => _podcastTypeOptions.first,
  );
}

/// Podcast Settings Dialog with voice customization (Refined UI)
class _PodcastSettingsDialog extends StatefulWidget {
  final void Function(String title, String podcastType, String? topic)
      onGenerate;

  const _PodcastSettingsDialog({required this.onGenerate});

  @override
  State<_PodcastSettingsDialog> createState() => _PodcastSettingsDialogState();
}

class _PodcastSettingsDialogState extends State<_PodcastSettingsDialog> {
  late final TextEditingController _titleController;
  String _selectedType = _podcastTypeOptions.first.id;
  String? _topic;
  bool _hasCustomTitle = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: _podcastTypeOptions.first.defaultTitle,
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final selectedType = _podcastTypeById(_selectedType);

    // Return a refined Dialog
    return Dialog(
      backgroundColor: Colors.transparent,
      child: GlassContainer(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Icon(LucideIcons.settings,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text('Podcast Settings',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 24),
            // Content
            // Content
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Podcast Name',
                    style: Theme.of(context).textTheme.labelMedium),
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (value) {
                    final trimmed = value.trim();
                    _hasCustomTitle = trimmed.isNotEmpty &&
                        trimmed != _podcastTypeById(_selectedType).defaultTitle;
                  },
                ),
                const SizedBox(height: 16),
                Text('Podcast Type',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.15),
                    ),
                  ),
                  child: Text(
                    selectedType.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Focus Topic (Optional)',
                    style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'e.g. "Key financial metrics"',
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surface
                        .withValues(alpha: 0.5),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onChanged: (val) => _topic = val,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(LucideIcons.users,
                        size: 16,
                        color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 8),
                    const Text('Hosts: Sarah (AI) & Adam (AI)'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () {
                    final title = _titleController.text.trim().isEmpty
                        ? selectedType.defaultTitle
                        : _titleController.text.trim();
                    Navigator.pop(context);
                    widget.onGenerate(title, _selectedType, _topic);
                  },
                  icon: const Icon(LucideIcons.sparkles, size: 18),
                  label: const Text('Generate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
