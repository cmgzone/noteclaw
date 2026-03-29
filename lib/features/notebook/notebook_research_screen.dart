import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/ai/deep_research_service.dart';
import '../../ui/widgets/app_network_image.dart';
import '../sources/source_provider.dart';
import '../subscription/services/credit_manager.dart';
import 'notebook.dart';
import 'notebook_provider.dart';

class NotebookResearchScreen extends ConsumerStatefulWidget {
  final String notebookId;

  const NotebookResearchScreen({super.key, required this.notebookId});

  @override
  ConsumerState<NotebookResearchScreen> createState() =>
      _NotebookResearchScreenState();
}

class _NotebookResearchScreenState
    extends ConsumerState<NotebookResearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _isResearching = false;
  List<ResearchUpdate> _researchUpdates = [];
  ResearchUpdate? _finalResult;

  ResearchDepth _selectedDepth = ResearchDepth.standard;
  ResearchTemplate _selectedTemplate = ResearchTemplate.general;

  final List<String> _searchedSites = [];

  static const List<String> _promptIdeas = [
    'Compare the strongest AI coding assistants for small product teams',
    'Create a market brief on AI note-taking tools for students',
    'Summarize current research on spaced repetition and memory retention',
    'Find credible sources on running local LLMs on consumer hardware',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleComposerChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleComposerChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  String? _extractDomain(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }

  String _getFaviconUrl(String domain) {
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
  }

  int get _estimatedCreditCost {
    return _selectedDepth == ResearchDepth.deep
        ? CreditCosts.deepResearch * 2
        : CreditCosts.deepResearch;
  }

  Notebook? _currentNotebook(List<Notebook> notebooks) {
    for (final notebook in notebooks) {
      if (notebook.id == widget.notebookId) {
        return notebook;
      }
    }
    return null;
  }

  List<ResearchSource> _currentSources() {
    if (_finalResult?.sources != null && _finalResult!.sources!.isNotEmpty) {
      return _finalResult!.sources!;
    }

    for (final update in _researchUpdates.reversed) {
      if (update.sources != null && update.sources!.isNotEmpty) {
        return update.sources!;
      }
    }

    return const [];
  }

  List<ResearchUpdate> _visibleUpdates() {
    final visible = <ResearchUpdate>[];
    final seen = <String>{};

    for (final update in _researchUpdates.reversed) {
      final key = '${update.status}|${update.progress.toStringAsFixed(2)}';
      if (seen.add(key)) {
        visible.add(update);
      }
      if (visible.length == 6) {
        break;
      }
    }

    return visible.reversed.toList();
  }

  String _depthLabel(ResearchDepth depth) {
    switch (depth) {
      case ResearchDepth.quick:
        return 'Quick';
      case ResearchDepth.standard:
        return 'Standard';
      case ResearchDepth.deep:
        return 'Deep';
    }
  }

  String _depthDescription(ResearchDepth depth) {
    switch (depth) {
      case ResearchDepth.quick:
        return 'Fast scan for an initial read on the topic.';
      case ResearchDepth.standard:
        return 'Balanced breadth and synthesis for most questions.';
      case ResearchDepth.deep:
        return 'Wider source sweep with more exhaustive synthesis.';
    }
  }

  String _templateLabel(ResearchTemplate template) {
    switch (template) {
      case ResearchTemplate.general:
        return 'General';
      case ResearchTemplate.academic:
        return 'Academic';
      case ResearchTemplate.productComparison:
        return 'Compare';
      case ResearchTemplate.marketAnalysis:
        return 'Market';
      case ResearchTemplate.howToGuide:
        return 'How-To';
      case ResearchTemplate.prosAndCons:
        return 'Pros / Cons';
      case ResearchTemplate.shopping:
        return 'Shopping';
    }
  }

  String _templateDescription(ResearchTemplate template) {
    switch (template) {
      case ResearchTemplate.general:
        return 'Open-ended exploration with a broad report structure.';
      case ResearchTemplate.academic:
        return 'More formal framing for evidence and research-backed context.';
      case ResearchTemplate.productComparison:
        return 'Organized around tradeoffs, options, and selection criteria.';
      case ResearchTemplate.marketAnalysis:
        return 'Useful for trends, positioning, and competitive landscape work.';
      case ResearchTemplate.howToGuide:
        return 'Step-based reporting that turns research into action.';
      case ResearchTemplate.prosAndCons:
        return 'Best for evaluating a decision from both sides quickly.';
      case ResearchTemplate.shopping:
        return 'Focused on buying decisions, options, and recommendation logic.';
    }
  }

  IconData _templateIcon(ResearchTemplate template) {
    switch (template) {
      case ResearchTemplate.general:
        return Icons.explore_outlined;
      case ResearchTemplate.academic:
        return Icons.school_outlined;
      case ResearchTemplate.productComparison:
        return Icons.balance_outlined;
      case ResearchTemplate.marketAnalysis:
        return Icons.insights_outlined;
      case ResearchTemplate.howToGuide:
        return Icons.route_outlined;
      case ResearchTemplate.prosAndCons:
        return Icons.compare_arrows_outlined;
      case ResearchTemplate.shopping:
        return Icons.shopping_bag_outlined;
    }
  }

  Color _credibilityColor(SourceCredibility credibility, ColorScheme scheme) {
    switch (credibility) {
      case SourceCredibility.academic:
        return const Color(0xFF0F766E);
      case SourceCredibility.government:
        return const Color(0xFF1D4ED8);
      case SourceCredibility.news:
        return const Color(0xFFC2410C);
      case SourceCredibility.professional:
        return const Color(0xFF7C3AED);
      case SourceCredibility.blog:
        return const Color(0xFF475569);
      case SourceCredibility.unknown:
        return scheme.onSurfaceVariant;
    }
  }

  String _credibilityLabel(SourceCredibility credibility) {
    switch (credibility) {
      case SourceCredibility.academic:
        return 'Academic';
      case SourceCredibility.government:
        return 'Government';
      case SourceCredibility.news:
        return 'News';
      case SourceCredibility.professional:
        return 'Professional';
      case SourceCredibility.blog:
        return 'Blog';
      case SourceCredibility.unknown:
        return 'Unknown';
    }
  }

  void _applyPrompt(String prompt) {
    _searchController.text = prompt;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: prompt.length),
    );
    _searchFocus.requestFocus();
  }

  void _resetSession() {
    setState(() {
      _isResearching = false;
      _researchUpdates = [];
      _finalResult = null;
      _searchedSites.clear();
    });
  }

  Future<void> _openSource(ResearchSource source) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _performResearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    FocusScope.of(context).unfocus();

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: _estimatedCreditCost,
      feature: 'deep_research',
    );
    if (!hasCredits) return;

    setState(() {
      _isResearching = true;
      _researchUpdates = [];
      _finalResult = null;
      _searchedSites.clear();
    });

    ref
        .read(deepResearchServiceProvider)
        .research(
          query: query,
          notebookId: widget.notebookId, // Save to THIS notebook
          depth: _selectedDepth,
          template: _selectedTemplate,
        )
        .listen(
      (update) {
        if (!mounted) return;
        setState(() {
          _researchUpdates.add(update);

          if (update.sources != null) {
            for (final source in update.sources!) {
              final domain = _extractDomain(source.url);
              if (domain != null && !_searchedSites.contains(domain)) {
                _searchedSites.add(domain);
              }
            }
          }

          if (update.result != null) {
            _finalResult = update;
          }

          if (update.isComplete) {
            _finalResult = update;
            _isResearching = false;
          }
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _isResearching = false;
          _finalResult = ResearchUpdate(
            status: 'Research failed',
            progress: 1,
            isComplete: true,
            error: e.toString(),
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Research failed: $e')),
        );
      },
    );
  }

  Future<void> _saveReportAsSource() async {
    if (_finalResult?.result == null) return;

    try {
      await ref.read(sourceProvider.notifier).addSource(
            title: 'Research: ${_searchController.text}',
            type: 'research',
            content: _finalResult!.result!,
            notebookId: widget.notebookId,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Research saved to notebook!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final notebooks = ref.watch(notebookProvider);
    final notebook = _currentNotebook(notebooks);
    final notebookTitle = notebook?.title ?? 'Current notebook';
    final hasSession =
        _isResearching || _researchUpdates.isNotEmpty || _finalResult != null;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deep Research'),
            Text(
              notebookTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          if (hasSession)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Start a new research session',
              onPressed: _isResearching ? null : _resetSession,
            ),
          if (_finalResult?.result != null)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save to notebook',
              onPressed: _saveReportAsSource,
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
              scheme.primaryContainer.withValues(alpha: 0.12),
              scheme.secondaryContainer.withValues(alpha: 0.10),
              scheme.surface,
            ],
            stops: const [0, 0.24, 0.60, 1],
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1080;

            final rail = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWorkspaceHeroCard(
                  scheme: scheme,
                  text: text,
                  notebookTitle: notebookTitle,
                ).animate().fadeIn().slideY(begin: 0.05),
                const SizedBox(height: 18),
                _buildResearchBriefCard(
                  scheme: scheme,
                  text: text,
                  notebookTitle: notebookTitle,
                ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.05),
                const SizedBox(height: 18),
                _buildRunSettingsCard(
                  scheme: scheme,
                  text: text,
                ).animate().fadeIn(delay: 140.ms).slideY(begin: 0.05),
                if (hasSession) ...[
                  const SizedBox(height: 18),
                  _buildSessionSnapshotCard(
                    scheme: scheme,
                    text: text,
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),
                ],
              ],
            );

            final canvas = AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: hasSession
                  ? _buildActiveResearchCanvas(
                      key: const ValueKey('active-canvas'),
                      scheme: scheme,
                      text: text,
                    )
                  : _buildEmptyResearchCanvas(
                      key: const ValueKey('empty-canvas'),
                      scheme: scheme,
                      text: text,
                    ),
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1360),
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(width: 390, child: rail),
                            const SizedBox(width: 20),
                            Expanded(child: canvas),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            rail,
                            const SizedBox(height: 18),
                            canvas,
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWorkspaceHeroCard({
    required ColorScheme scheme,
    required TextTheme text,
    required String notebookTitle,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F766E).withValues(alpha: 0.22),
            const Color(0xFFF59E0B).withValues(alpha: 0.16),
            scheme.surface.withValues(alpha: 0.96),
          ],
        ),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -32,
            right: -24,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.12),
              ),
            ),
          ),
          Positioned(
            bottom: -20,
            left: -10,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF97316).withValues(alpha: 0.10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.82),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: scheme.outline.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.radar_rounded,
                        size: 16,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Notebook-linked research workspace',
                        style: text.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Run broader web research without leaving your notebook.',
                  style: text.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Turn one prompt into a source-backed report, follow the live crawl, and save the finished research back into "$notebookTitle".',
                  style: text.bodyMedium?.copyWith(
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _ResearchMetricChip(
                      icon: Icons.book_outlined,
                      label: notebookTitle,
                      color: const Color(0xFF0F766E),
                    ),
                    _ResearchMetricChip(
                      icon: Icons.bolt_rounded,
                      label: '$_estimatedCreditCost credits',
                      color: const Color(0xFFF59E0B),
                    ),
                    _ResearchMetricChip(
                      icon: _templateIcon(_selectedTemplate),
                      label: _templateLabel(_selectedTemplate),
                      color: const Color(0xFF0EA5E9),
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

  Widget _buildResearchBriefCard({
    required ColorScheme scheme,
    required TextTheme text,
    required String notebookTitle,
  }) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return _ResearchSurface(
      title: 'Research Brief',
      subtitle:
          'Describe what you need, then tune the depth and reporting style before you launch the run.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              minLines: 5,
              maxLines: 8,
              enabled: !_isResearching,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText:
                    'What do you want to understand, compare, or validate?',
                hintStyle: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              ),
              style: text.bodyLarge?.copyWith(height: 1.45),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Starter prompts',
            style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _promptIdeas.map((prompt) {
              return ActionChip(
                label: SizedBox(
                  width: 220,
                  child: Text(
                    prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                avatar: const Icon(Icons.add_circle_outline, size: 16),
                onPressed: _isResearching ? null : () => _applyPrompt(prompt),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      !_isResearching && hasQuery ? _performResearch : null,
                  icon: _isResearching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _finalResult == null
                              ? Icons.travel_explore_rounded
                              : Icons.refresh_rounded,
                        ),
                  label: Text(
                    _isResearching
                        ? 'Researching...'
                        : _finalResult == null
                            ? 'Start research'
                            : 'Run again',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (hasQuery) ...[
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _isResearching
                      ? null
                      : () {
                          _searchController.clear();
                          _searchFocus.requestFocus();
                        },
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'This run will use $_estimatedCreditCost credits. When it finishes, you can save the report back into "$notebookTitle".',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunSettingsCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return _ResearchSurface(
      title: 'Run Settings',
      subtitle:
          'Balance speed vs. depth, then shape the report around the kind of answer you need.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Depth',
            style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...ResearchDepth.values.map((depth) {
            final selected = _selectedDepth == depth;
            final credits = depth == ResearchDepth.deep
                ? CreditCosts.deepResearch * 2
                : CreditCosts.deepResearch;

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DepthOptionCard(
                title: _depthLabel(depth),
                subtitle: _depthDescription(depth),
                credits: credits,
                selected: selected,
                accent: depth == ResearchDepth.quick
                    ? const Color(0xFF0EA5E9)
                    : depth == ResearchDepth.standard
                        ? const Color(0xFF0F766E)
                        : const Color(0xFFF97316),
                onTap: _isResearching
                    ? null
                    : () => setState(() => _selectedDepth = depth),
              ),
            );
          }),
          const SizedBox(height: 6),
          Text(
            'Template',
            style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: ResearchTemplate.values.map((template) {
              return _TemplateOptionChip(
                label: _templateLabel(template),
                icon: _templateIcon(template),
                selected: _selectedTemplate == template,
                onTap: _isResearching
                    ? null
                    : () => setState(() => _selectedTemplate = template),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            _templateDescription(_selectedTemplate),
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionSnapshotCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final latestUpdate =
        _researchUpdates.isNotEmpty ? _researchUpdates.last : _finalResult;
    final sources = _currentSources();
    final videos = _finalResult?.videos?.length ?? 0;
    final progress =
        latestUpdate?.progress ?? (_finalResult != null ? 1.0 : 0.0);

    return _ResearchSurface(
      title: 'Session Snapshot',
      subtitle: latestUpdate?.status ?? 'Waiting for the next update.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ResearchMetricChip(
                icon: Icons.language_rounded,
                label: '${_searchedSites.length} sites',
                color: const Color(0xFF0EA5E9),
              ),
              _ResearchMetricChip(
                icon: Icons.description_outlined,
                label: '${sources.length} sources',
                color: const Color(0xFF0F766E),
              ),
              _ResearchMetricChip(
                icon: Icons.video_library_outlined,
                label: '$videos videos',
                color: const Color(0xFFF97316),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: scheme.outline.withValues(alpha: 0.16),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _isResearching
                ? '${(progress * 100).toInt()}% complete'
                : _finalResult?.error != null
                    ? 'Run ended with an error'
                    : 'Research complete',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResearchCanvas({
    Key? key,
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return KeyedSubtree(
      key: key,
      child: _ResearchSurface(
        title: 'Research Canvas',
        subtitle:
            'Live source discovery, status updates, the synthesized report, and related media will appear here once you launch a run.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.surfaceContainerHighest.withValues(alpha: 0.82),
                    scheme.surface,
                  ],
                ),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.10),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF0F766E).withValues(alpha: 0.12),
                    ),
                    child: const Icon(
                      Icons.travel_explore_rounded,
                      size: 34,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Ready to run a broader research sweep',
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Use the left rail to define the brief, then launch a research pass that crawls relevant sources, assembles a report, and keeps the process visible while it runs.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 900;
                final cardWidth = isCompact
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 24) / 3;

                final cards = [
                  (
                    icon: Icons.public_rounded,
                    title: 'Source sweep',
                    subtitle:
                        'Track sites and domains as the run discovers useful material.',
                    color: const Color(0xFF0EA5E9),
                  ),
                  (
                    icon: Icons.timeline_rounded,
                    title: 'Live progress',
                    subtitle:
                        'Follow status changes instead of waiting on a black box.',
                    color: const Color(0xFF0F766E),
                  ),
                  (
                    icon: Icons.article_outlined,
                    title: 'Saveable output',
                    subtitle:
                        'Turn the final report into a notebook source when it is ready.',
                    color: const Color(0xFFF97316),
                  ),
                ];

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: cards.map((card) {
                    return SizedBox(
                      width: cardWidth,
                      child: _CanvasFeatureCard(
                        icon: card.icon,
                        title: card.title,
                        subtitle: card.subtitle,
                        color: card.color,
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveResearchCanvas({
    Key? key,
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final currentSources = _currentSources();
    final recentUpdates = _visibleUpdates();
    final latestUpdate =
        _researchUpdates.isNotEmpty ? _researchUpdates.last : _finalResult;

    return KeyedSubtree(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLiveResearchRunCard(
            scheme: scheme,
            text: text,
            latestUpdate: latestUpdate,
            recentUpdates: recentUpdates,
          ).animate().fadeIn().slideY(begin: 0.04),
          if (_searchedSites.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDiscoveredSitesCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 70.ms).slideY(begin: 0.04),
          ],
          if (currentSources.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildSourceIntelligenceCard(
              scheme: scheme,
              text: text,
              sources: currentSources,
            ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.result != null) ...[
            const SizedBox(height: 18),
            _buildReportCanvasCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 170.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.videos != null &&
              _finalResult!.videos!.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildVideoCanvasCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 220.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.error != null && _finalResult?.result == null) ...[
            const SizedBox(height: 18),
            _buildResearchErrorCard(
              scheme: scheme,
              text: text,
              message: _finalResult!.error!,
            ).animate().fadeIn(delay: 260.ms).slideY(begin: 0.04),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveResearchRunCard({
    required ColorScheme scheme,
    required TextTheme text,
    required ResearchUpdate? latestUpdate,
    required List<ResearchUpdate> recentUpdates,
  }) {
    final progress =
        latestUpdate?.progress ?? (_finalResult != null ? 1.0 : 0.0);

    return _ResearchSurface(
      title: _isResearching ? 'Live Research Run' : 'Latest Research Run',
      subtitle: _searchController.text.trim().isEmpty
          ? 'Current research session'
          : _searchController.text.trim(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;

              final meter = Container(
                width: compact ? double.infinity : 150,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.10),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 90,
                      height: 90,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: progress.clamp(0.0, 1.0),
                            strokeWidth: 8,
                            backgroundColor:
                                scheme.outline.withValues(alpha: 0.12),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: text.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _isResearching ? 'live' : 'done',
                                style: text.labelMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _isResearching ? 'Researching the web' : 'Run completed',
                      style: text.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              );

              final summaryBox = Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      latestUpdate?.status ?? 'Preparing your research run...',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isResearching
                          ? 'The agent is searching, ranking, and synthesizing sources in real time.'
                          : 'The last completed run is ready for review and can be saved back into your notebook.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress.clamp(0.0, 1.0),
                        minHeight: 10,
                        backgroundColor: scheme.outline.withValues(alpha: 0.14),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _ResearchMetricChip(
                          icon: Icons.layers_outlined,
                          label: _depthLabel(_selectedDepth),
                          color: const Color(0xFF0F766E),
                        ),
                        _ResearchMetricChip(
                          icon: _templateIcon(_selectedTemplate),
                          label: _templateLabel(_selectedTemplate),
                          color: const Color(0xFF0EA5E9),
                        ),
                        _ResearchMetricChip(
                          icon: Icons.bolt_rounded,
                          label: '$_estimatedCreditCost credits',
                          color: const Color(0xFFF97316),
                        ),
                      ],
                    ),
                  ],
                ),
              );

              if (compact) {
                return Column(
                  children: [
                    meter,
                    const SizedBox(height: 12),
                    summaryBox,
                  ],
                );
              }

              final summary = Expanded(
                child: summaryBox,
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  meter,
                  const SizedBox(width: 14),
                  summary,
                ],
              );
            },
          ),
          if (recentUpdates.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Research log',
              style: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Column(
              children: recentUpdates.map((update) {
                final isLatest = identical(update, recentUpdates.last);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isLatest
                        ? scheme.primaryContainer.withValues(alpha: 0.34)
                        : scheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isLatest
                          ? scheme.primary.withValues(alpha: 0.18)
                          : scheme.outline.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isLatest
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              update.status,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${(update.progress * 100).toInt()}% complete',
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDiscoveredSitesCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return _ResearchSurface(
      title: 'Discovered Sites',
      subtitle:
          'These domains have appeared during the current run, which makes it easier to see the breadth of the research sweep.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: _searchedSites.map((domain) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipOval(
                  child: AppNetworkImage(
                    imageUrl: _getFaviconUrl(domain),
                    width: 18,
                    height: 18,
                    fit: BoxFit.cover,
                    placeholder: (_) => Container(
                      width: 18,
                      height: 18,
                      color: scheme.surfaceContainerHighest,
                    ),
                    errorWidget: (_) => Icon(
                      Icons.public,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  domain,
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSourceIntelligenceCard({
    required ColorScheme scheme,
    required TextTheme text,
    required List<ResearchSource> sources,
  }) {
    return _ResearchSurface(
      title: 'Source Intelligence',
      subtitle:
          'The strongest sources gathered during the run, including credibility cues and quick paths back to the original pages.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 920;
          final cardWidth =
              compact ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;

          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: sources.take(6).map((source) {
              final domain = _extractDomain(source.url) ?? source.url;
              return SizedBox(
                width: cardWidth,
                child: _ResearchSourceCard(
                  source: source,
                  domain: domain,
                  faviconUrl: _extractDomain(source.url) != null
                      ? _getFaviconUrl(_extractDomain(source.url)!)
                      : null,
                  credibilityColor:
                      _credibilityColor(source.credibility, scheme),
                  credibilityLabel: _credibilityLabel(source.credibility),
                  onOpen: () => _openSource(source),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildReportCanvasCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return _ResearchSurface(
      title: 'Research Report',
      subtitle:
          'A synthesized write-up with structured headings, links, and media. Select text freely or save the report as a notebook source.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              FilledButton.icon(
                onPressed: _saveReportAsSource,
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save report'),
              ),
              OutlinedButton.icon(
                onPressed: _isResearching ? null : _performResearch,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Rerun'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: MarkdownBody(
              data: _finalResult!.result!,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                h1: text.headlineSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w800,
                ),
                h2: text.titleLarge?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                h3: text.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                p: text.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                  height: 1.6,
                ),
                listBullet: text.bodyMedium?.copyWith(
                  color: scheme.onSurface,
                ),
                strong: text.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
                em: text.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: scheme.onSurface,
                ),
                blockquote: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                code: text.bodySmall?.copyWith(
                  color: scheme.onSurface,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
              onTapLink: (displayText, href, title) {
                if (href != null) {
                  launchUrl(
                    Uri.parse(href),
                    mode: LaunchMode.externalApplication,
                  );
                }
              },
              sizedImageBuilder: (config) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: AppNetworkImage(
                      imageUrl: config.uri.toString(),
                      width: config.width,
                      height: config.height,
                      fit: BoxFit.cover,
                      placeholder: (_) => Container(
                        height: 220,
                        color: scheme.surfaceContainerHighest,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_) => Container(
                        height: 120,
                        color: scheme.surfaceContainerHighest,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.broken_image, color: scheme.outline),
                              const SizedBox(height: 6),
                              Text(
                                config.alt ?? 'Image failed to load',
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoCanvasCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return _ResearchSurface(
      title: 'Related Videos',
      subtitle:
          'Helpful follow-up explainers and walkthroughs pulled into the same research session.',
      child: SizedBox(
        height: 210,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: _finalResult!.videos!.length,
          itemBuilder: (context, index) {
            final videoUrl = _finalResult!.videos![index];
            final videoId = _extractYouTubeId(videoUrl);
            if (videoId == null) return const SizedBox.shrink();

            return Padding(
              padding: EdgeInsets.only(
                right: index < _finalResult!.videos!.length - 1 ? 12 : 0,
              ),
              child: _VideoCard(
                videoId: videoId,
                onPlay: () => _showVideoPlayer(videoId),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildResearchErrorCard({
    required ColorScheme scheme,
    required TextTheme text,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Research run failed',
                  style: text.titleMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String? _extractYouTubeId(String url) {
    // Handle various YouTube URL formats
    final regexes = [
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})'),
    ];

    for (final regex in regexes) {
      final match = regex.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  void _showVideoPlayer(String videoId) {
    if (kIsWeb) {
      final url = Uri.parse('https://www.youtube.com/watch?v=$videoId');
      launchUrl(url, mode: LaunchMode.externalApplication);
      return;
    }
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: _YouTubeWebViewPlayer(videoId: videoId),
      ),
    );
  }
}

class _ResearchSurface extends StatelessWidget {
  const _ResearchSurface({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ResearchMetricChip extends StatelessWidget {
  const _ResearchMetricChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DepthOptionCard extends StatelessWidget {
  const _DepthOptionCard({
    required this.title,
    required this.subtitle,
    required this.credits,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final int credits;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.60)
                  : scheme.outline.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? accent : scheme.outlineVariant,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: text.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$credits cr',
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TemplateOptionChip extends StatelessWidget {
  const _TemplateOptionChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primaryContainer.withValues(alpha: 0.8)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.36),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.32)
                  : scheme.outline.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CanvasFeatureCard extends StatelessWidget {
  const _CanvasFeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResearchSourceCard extends StatelessWidget {
  const _ResearchSourceCard({
    required this.source,
    required this.domain,
    required this.faviconUrl,
    required this.credibilityColor,
    required this.credibilityLabel,
    required this.onOpen,
  });

  final ResearchSource source;
  final String domain;
  final String? faviconUrl;
  final Color credibilityColor;
  final String credibilityLabel;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasImage =
        source.imageUrl != null && source.imageUrl!.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.10),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasImage)
              AppNetworkImage(
                imageUrl: source.imageUrl!,
                width: double.infinity,
                height: 128,
                fit: BoxFit.cover,
                placeholder: (_) => Container(
                  height: 128,
                  color: scheme.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_) => Container(
                  height: 128,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.language_rounded,
                    size: 40,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (faviconUrl != null)
                        ClipOval(
                          child: AppNetworkImage(
                            imageUrl: faviconUrl!,
                            width: 20,
                            height: 20,
                            fit: BoxFit.cover,
                            placeholder: (_) => Container(
                              width: 20,
                              height: 20,
                              color: scheme.surfaceContainerHighest,
                            ),
                            errorWidget: (_) => Icon(
                              Icons.public,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Icon(
                          Icons.public,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          domain,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: credibilityColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$credibilityLabel ${source.credibilityScore}',
                          style: text.labelSmall?.copyWith(
                            color: credibilityColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    source.title.trim().isEmpty ? domain : source.title.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (source.snippet ?? source.content).trim().isEmpty
                        ? 'No preview available for this source yet.'
                        : (source.snippet ?? source.content).trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Open source'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouTubeWebViewPlayer extends StatefulWidget {
  final String videoId;

  const _YouTubeWebViewPlayer({required this.videoId});

  @override
  State<_YouTubeWebViewPlayer> createState() => _YouTubeWebViewPlayerState();
}

class _YouTubeWebViewPlayerState extends State<_YouTubeWebViewPlayer> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    // Load YouTube mobile site directly - most reliable approach
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
          'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(
          Uri.parse('https://m.youtube.com/watch?v=${widget.videoId}'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('YouTube Video'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.black,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final String videoId;
  final VoidCallback onPlay;

  const _VideoCard({required this.videoId, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/mqdefault.jpg';

    return GestureDetector(
      onTap: onPlay,
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppNetworkImage(
                imageUrl: thumbnailUrl,
                fit: BoxFit.cover,
                placeholder: (_) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (_) => Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(Icons.video_library,
                      color: scheme.outline, size: 48),
                ),
              ),
              // Play button overlay
              Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              // Gradient overlay at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_circle_outline,
                          color: Colors.white, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Tap to play',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
