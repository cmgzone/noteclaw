import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/search/search_provider.dart';
import '../../core/search/serper_service.dart';
import '../../features/sources/source_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/theme/theme_provider.dart';
import '../../core/ai/deep_research_service.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'youtube_player_dialog.dart';
import '../subscription/services/credit_manager.dart';
import '../../ui/widgets/app_network_image.dart';
import '../home/create_notebook_dialog.dart';
import '../notebook/notebook.dart';
import '../notebook/notebook_provider.dart';
import '../../ui/digital_librarian.dart';
import '../../ui/forge.dart';

class WebSearchScreen extends ConsumerStatefulWidget {
  const WebSearchScreen({
    super.key,
    this.initialDeepResearch = false,
  });

  final bool initialDeepResearch;

  @override
  ConsumerState<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends ConsumerState<WebSearchScreen> {
  static const _webSearchHistoryKey = 'web_search_history_v1';
  static const _deepResearchHistoryKey = 'deep_research_history_v1';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _filterDomainController = TextEditingController();
  bool _isDeepResearch = false;
  bool _isResearching = false;
  List<ResearchUpdate> _researchUpdates = [];
  ResearchUpdate? _finalResult;
  SearchType _searchType = SearchType.web;

  // New feature states
  ResearchDepth _selectedDepth = ResearchDepth.standard;
  ResearchTemplate _selectedTemplate = ResearchTemplate.general;
  String? _selectedResearchNotebookId;

  // Streaming state for live site icons (matching deep_research_screen)
  final List<String> _searchedSites = [];
  String? _currentSearchQuery;

  // Filters for standard search
  String _filterDomain = '';
  bool _filterHasDate = false;
  bool _filterHasSource = false;
  bool _filterHasImage = false;
  List<_WebSearchHistoryItem> _webSearchHistory = [];
  List<_DeepResearchHistoryItem> _deepResearchHistory = [];
  static const List<String> _deepResearchPromptIdeas = [
    'Compare the strongest AI coding assistants for small product teams',
    'Create a market brief on AI note-taking tools for students',
    'Summarize current research on spaced repetition and memory retention',
    'Find credible sources on running local LLMs on consumer hardware',
  ];

  @override
  void initState() {
    super.initState();
    _isDeepResearch = widget.initialDeepResearch;
    _searchController.addListener(_handleSearchChanged);
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _filterDomainController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _clearFilters() {
    setState(() {
      _filterDomain = '';
      _filterHasDate = false;
      _filterHasSource = false;
      _filterHasImage = false;
      _filterDomainController.clear();
    });
  }

  List<SerperSearchResult> _applyFilters(List<SerperSearchResult> results) {
    if (_filterDomain.isEmpty &&
        !_filterHasDate &&
        !_filterHasSource &&
        !_filterHasImage) {
      return results;
    }

    final query = _filterDomain.trim().toLowerCase();
    return results.where((result) {
      if (query.isNotEmpty) {
        final domain = _extractDomain(result.link)?.toLowerCase() ?? '';
        final link = result.link.toLowerCase();
        final source = result.source?.toLowerCase() ?? '';
        if (!domain.contains(query) &&
            !link.contains(query) &&
            !source.contains(query)) {
          return false;
        }
      }
      if (_filterHasDate && (result.date == null || result.date!.isEmpty)) {
        return false;
      }
      if (_filterHasSource &&
          (result.source == null || result.source!.isEmpty)) {
        return false;
      }
      if (_filterHasImage &&
          (result.imageUrl == null || result.imageUrl!.isEmpty)) {
        return false;
      }
      return true;
    }).toList();
  }

  // Helper methods for favicon display (matching deep_research_screen)
  String? _extractDomain(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return null;
    }
  }

  String _getFaviconUrl(String domain) {
    // Use Google's favicon service for reliable favicons
    return 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
  }

  Future<void> _performSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    if (_isDeepResearch) {
      _performDeepResearch(query);
    } else {
      // Check and consume credits for web search
      final hasCredits = await ref.tryUseCredits(
        context: context,
        amount: CreditCosts.webSearch,
        feature: 'web_search',
      );
      if (!hasCredits) return;

      try {
        await ref
            .read(searchProvider.notifier)
            .search(query, type: _searchType);
        final latestState = ref.read(searchProvider);
        if (latestState.status == SearchStatus.success) {
          await _saveWebSearchHistory(query, _searchType);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Search failed: ${_getFriendlyErrorMessage(e.toString())}')),
          );
        }
      }
    }
  }

  Future<void> _performDeepResearch(String query) async {
    FocusScope.of(context).unfocus();

    // Check and consume credits for deep research (more for deep mode)
    final creditAmount = _selectedDepth == ResearchDepth.deep
        ? CreditCosts.deepResearch * 2
        : CreditCosts.deepResearch;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: creditAmount,
      feature: 'deep_research',
    );
    if (!hasCredits) return;

    setState(() {
      _isResearching = true;
      _researchUpdates = [];
      _finalResult = null;
      _searchedSites.clear();
      _currentSearchQuery = null;
    });

    ref
        .read(deepResearchServiceProvider)
        .research(
          query: query,
          notebookId: _selectedResearchNotebookId ?? '',
          depth: _selectedDepth,
          template: _selectedTemplate,
        )
        .listen(
      (update) {
        if (!mounted) return;
        setState(() {
          _researchUpdates.add(update);

          // Extract current search query from status
          if (update.status.contains('Searching:')) {
            final match =
                RegExp(r'Searching: "(.+?)"').firstMatch(update.status);
            if (match != null) {
              _currentSearchQuery = match.group(1);
            }
          }

          // Track sources as they come in for live favicon display
          if (update.sources != null) {
            for (final source in update.sources!) {
              final domain = _extractDomain(source.url);
              if (domain != null && !_searchedSites.contains(domain)) {
                _searchedSites.add(domain);
              }
            }
          }

          // Show streaming results as they come in
          if (update.result != null) {
            _finalResult = update;
          }

          // Mark complete when done
          if (update.isComplete) {
            _finalResult = update;
            _isResearching = false;
          }
        });
        if (update.isComplete &&
            update.result != null &&
            update.result!.trim().isNotEmpty) {
          _saveDeepResearchHistory(
            query: query,
            depth: _selectedDepth,
            template: _selectedTemplate,
            summary: update.result,
          );
        }
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

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final webHistoryRaw = prefs.getString(_webSearchHistoryKey);
    final deepHistoryRaw = prefs.getString(_deepResearchHistoryKey);

    List<_WebSearchHistoryItem> loadedWeb = [];
    List<_DeepResearchHistoryItem> loadedDeep = [];

    if (webHistoryRaw != null && webHistoryRaw.isNotEmpty) {
      try {
        final list =
            (jsonDecode(webHistoryRaw) as List).cast<Map<String, dynamic>>();
        loadedWeb = list
            .map(_WebSearchHistoryItem.fromJson)
            .where((item) => item.query.trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }

    if (deepHistoryRaw != null && deepHistoryRaw.isNotEmpty) {
      try {
        final list =
            (jsonDecode(deepHistoryRaw) as List).cast<Map<String, dynamic>>();
        loadedDeep = list
            .map(_DeepResearchHistoryItem.fromJson)
            .where((item) => item.query.trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _webSearchHistory = loadedWeb;
      _deepResearchHistory = loadedDeep;
    });
  }

  Future<void> _saveWebSearchHistory(String query, SearchType type) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    final updatedHistory = [
      _WebSearchHistoryItem(
        query: normalizedQuery,
        searchType: type.name,
        timestamp: DateTime.now(),
      ),
      ..._webSearchHistory.where(
        (item) => !(item.query.toLowerCase() == normalizedQuery.toLowerCase() &&
            item.searchType == type.name),
      ),
    ].take(20).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _webSearchHistoryKey,
      jsonEncode(updatedHistory.map((item) => item.toJson()).toList()),
    );

    if (!mounted) return;
    setState(() {
      _webSearchHistory = updatedHistory;
    });
  }

  Future<void> _saveDeepResearchHistory({
    required String query,
    required ResearchDepth depth,
    required ResearchTemplate template,
    String? summary,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) return;

    final updatedHistory = [
      _DeepResearchHistoryItem(
        query: normalizedQuery,
        depth: depth.name,
        template: template.name,
        summary: _cleanSummary(summary),
        timestamp: DateTime.now(),
      ),
      ..._deepResearchHistory.where(
        (item) => !(item.query.toLowerCase() == normalizedQuery.toLowerCase() &&
            item.depth == depth.name &&
            item.template == template.name),
      ),
    ].take(20).toList();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _deepResearchHistoryKey,
      jsonEncode(updatedHistory.map((item) => item.toJson()).toList()),
    );

    if (!mounted) return;
    setState(() {
      _deepResearchHistory = updatedHistory;
    });
  }

  Future<void> _clearWebHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_webSearchHistoryKey);
    if (!mounted) return;
    setState(() {
      _webSearchHistory = [];
    });
  }

  Future<void> _clearDeepHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_deepResearchHistoryKey);
    if (!mounted) return;
    setState(() {
      _deepResearchHistory = [];
    });
  }

  String _cleanSummary(String? summary) {
    if (summary == null || summary.trim().isEmpty) return '';
    final compact = summary.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 140) return compact;
    return '${compact.substring(0, 140)}...';
  }

  String _formatHistoryTime(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}';
  }

  Widget _buildWebHistorySection(ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Search History', style: text.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: _clearWebHistory,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 68,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _webSearchHistory.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _webSearchHistory[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    setState(() {
                      _isDeepResearch = false;
                      _searchType = SearchType.values.firstWhere(
                        (type) => type.name == item.searchType,
                        orElse: () => SearchType.web,
                      );
                      _searchController.text = item.query;
                    });
                    await _performSearch();
                  },
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.searchType} • ${_formatHistoryTime(item.timestamp)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.2, delay: 210.ms).fadeIn();
  }

  Widget _buildDeepHistorySection(ColorScheme scheme, TextTheme text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Research History', style: text.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: _clearDeepHistory,
                child: const Text('Clear'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _deepResearchHistory.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final item = _deepResearchHistory[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final depth = ResearchDepth.values.firstWhere(
                      (value) => value.name == item.depth,
                      orElse: () => ResearchDepth.standard,
                    );
                    final template = ResearchTemplate.values.firstWhere(
                      (value) => value.name == item.template,
                      orElse: () => ResearchTemplate.general,
                    );
                    setState(() {
                      _isDeepResearch = true;
                      _selectedDepth = depth;
                      _selectedTemplate = template;
                      _searchController.text = item.query;
                    });
                    await _performSearch();
                  },
                  child: Container(
                    width: 270,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (item.summary.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            item.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${item.depth}/${item.template} • ${_formatHistoryTime(item.timestamp)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.2, delay: 210.ms).fadeIn();
  }

  void _addAsSource(SerperSearchResult result) async {
    try {
      // Fetch the page content
      final content =
          await ref.read(searchProvider.notifier).fetchPageContent(result.link);

      // Add as a source
      await ref.read(sourceProvider.notifier).addSource(
        title: result.title,
        type: 'web',
        content: '''Title: ${result.title}
URL: ${result.link}

Summary:
${result.snippet}

Content:
$content''',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${result.title}" as source'),
            action: SnackBarAction(
              label: 'View',
              onPressed: () => context.go('/sources'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final errorMessage = _getFriendlyErrorMessage(e.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error adding source: $errorMessage')),
        );
      }
    }
  }

  String _getFriendlyErrorMessage(String? error) {
    if (error == null) return 'Unknown error occurred';
    if (error.contains('404')) {
      return 'Page not found (404). The source might be unavailable.';
    } else if (error.contains('403')) {
      return 'Access denied (403). The source might be protected.';
    }
    return error.replaceAll('Exception:', '').trim();
  }

  List<ResearchSource> _currentResearchSources() {
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

  String _notebookTitleFor(String notebookId) {
    final notebooks = ref.read(notebookProvider);
    for (final notebook in notebooks) {
      if (notebook.id == notebookId) {
        return notebook.title;
      }
    }
    return 'selected notebook';
  }

  Future<void> _showCreateNotebookDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CreateNotebookDialog(initialCategory: 'Research'),
    );
  }

  Future<String?> _showNotebookPicker() async {
    final notebooks = ref.read(notebookProvider);

    if (notebooks.isEmpty) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Create a notebook first to save deep research as sources.',
          ),
          action: SnackBarAction(
            label: 'Create',
            onPressed: _showCreateNotebookDialog,
          ),
        ),
      );
      return null;
    }

    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Choose notebook', style: text.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Pick where you want to save this research.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: notebooks.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final notebook = notebooks[index];
                      final isSelected =
                          notebook.id == _selectedResearchNotebookId;

                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context, notebook.id),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? scheme.primaryContainer
                                  : scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isSelected
                                    ? scheme.primary
                                    : scheme.outline.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.book_outlined,
                                  color: isSelected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        notebook.title,
                                        style: text.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${notebook.sourceCount} sources',
                                        style: text.bodySmall?.copyWith(
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check_circle,
                                      color: scheme.primary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showCreateNotebookDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create Notebook'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _ensureResearchNotebookSelected() async {
    if (_selectedResearchNotebookId != null &&
        _selectedResearchNotebookId!.isNotEmpty) {
      return _selectedResearchNotebookId;
    }

    final notebookId = await _showNotebookPicker();
    if (notebookId != null && mounted) {
      setState(() {
        _selectedResearchNotebookId = notebookId;
      });
    }
    return notebookId;
  }

  Future<void> _addResearchSourcesAsSources() async {
    final notebookId = await _ensureResearchNotebookSelected();
    if (notebookId == null) return;

    final sources = _currentResearchSources();
    if (sources.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No research sources available to save.')),
      );
      return;
    }

    int savedCount = 0;

    for (final source in sources) {
      try {
        final sourceTitle = source.title.trim().isEmpty
            ? (Uri.tryParse(source.url)?.host ?? 'Research source')
            : source.title.trim();

        final sourceContent = [
          'Title: $sourceTitle',
          'URL: ${source.url}',
          if ((source.snippet ?? '').trim().isNotEmpty) ...[
            '',
            'Snippet:',
            source.snippet!.trim(),
          ],
          if (source.content.trim().isNotEmpty) ...[
            '',
            'Content:',
            source.content.trim(),
          ],
        ].join('\n');

        await ref.read(sourceProvider.notifier).addSource(
              title: sourceTitle,
              type: 'web',
              content: sourceContent,
              url: source.url,
              notebookId: notebookId,
            );
        savedCount++;
      } catch (_) {
        continue;
      }
    }

    if (!mounted) return;

    final notebookTitle = _notebookTitleFor(notebookId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved $savedCount of ${sources.length} research sources to "$notebookTitle".',
        ),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => context.push('/memory-notebooks/$notebookId'),
        ),
      ),
    );
  }

  int get _estimatedDeepResearchCreditCost {
    return _selectedDepth == ResearchDepth.deep
        ? CreditCosts.deepResearch * 2
        : CreditCosts.deepResearch;
  }

  List<ResearchUpdate> _visibleResearchUpdates() {
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

  void _applyResearchPrompt(String prompt) {
    _searchController.text = prompt;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: prompt.length),
    );
    _searchFocus.requestFocus();
  }

  void _resetResearchSession() {
    setState(() {
      _isResearching = false;
      _researchUpdates = [];
      _finalResult = null;
      _searchedSites.clear();
      _currentSearchQuery = null;
    });
  }

  Future<void> _openResearchSource(ResearchSource source) async {
    final uri = Uri.tryParse(source.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _chooseResearchNotebook() async {
    if (ref.read(notebookProvider).isEmpty) {
      await _showCreateNotebookDialog();
      return;
    }

    final notebookId = await _showNotebookPicker();
    if (notebookId != null && mounted) {
      setState(() {
        _selectedResearchNotebookId = notebookId;
      });
    }
  }

  Widget _buildDeepResearchScaffold(
    BuildContext context,
    ColorScheme scheme,
    TextTheme text,
    List<Notebook> notebooks,
  ) {
    final hasSession =
        _isResearching || _researchUpdates.isNotEmpty || _finalResult != null;
    final destinationLabel = _selectedResearchNotebookId != null &&
            _selectedResearchNotebookId!.isNotEmpty
        ? _notebookTitleFor(_selectedResearchNotebookId!)
        : 'Choose when saving';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Deep Research'),
            Text(
              destinationLabel,
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
          IconButton(
            icon: const Icon(Icons.language_rounded),
            tooltip: 'Switch to web search',
            onPressed: _isResearching
                ? null
                : () => setState(() => _isDeepResearch = false),
          ),
          if (hasSession)
            IconButton(
              icon: const Icon(Icons.restart_alt_rounded),
              tooltip: 'Start a new research session',
              onPressed: _isResearching ? null : _resetResearchSession,
            ),
          if (_finalResult?.result != null)
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save report to notebook',
              onPressed: () => _addReportAsSource(_finalResult!),
            ),
        ],
      ),
      body: ForgeBackground(
        glowOne: DigitalLibrarian.primaryStrong,
        glowTwo: DigitalLibrarian.secondary,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 1080;

            final rail = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDeepResearchHeroCard(
                  scheme: scheme,
                  text: text,
                  destinationLabel: destinationLabel,
                ).animate().fadeIn().slideY(begin: 0.05),
                const SizedBox(height: 18),
                _buildDeepResearchBriefCard(
                  scheme: scheme,
                  text: text,
                  notebooks: notebooks,
                  destinationLabel: destinationLabel,
                ).animate().fadeIn(delay: 80.ms).slideY(begin: 0.05),
                const SizedBox(height: 18),
                _buildDeepResearchSettingsCard(
                  scheme: scheme,
                  text: text,
                ).animate().fadeIn(delay: 140.ms).slideY(begin: 0.05),
                if (hasSession) ...[
                  const SizedBox(height: 18),
                  _buildDeepResearchSnapshotCard(
                    scheme: scheme,
                    text: text,
                  ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05),
                ],
              ],
            );

            final canvas = AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: hasSession
                  ? _buildDeepResearchCanvas(
                      key: const ValueKey('deep-research-active-canvas'),
                      scheme: scheme,
                      text: text,
                    )
                  : _buildDeepResearchEmptyCanvas(
                      key: const ValueKey('deep-research-empty-canvas'),
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

  Widget _buildDeepResearchHeroCard({
    required ColorScheme scheme,
    required TextTheme text,
    required String destinationLabel,
  }) {
    return ForgePanel(
      accent: DigitalLibrarian.secondary,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ForgeEyebrow('DEEP RESEARCH'),
          const SizedBox(height: 10),
          Text(
            'Run broader web research from the same screen you use for search.',
            style: Forge.display(context, size: 21, height: 1.2),
          ),
          const SizedBox(height: 10),
          Text(
            'Turn one prompt into a source-backed report, follow the live crawl, and save the finished research back into "$destinationLabel".',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: DigitalLibrarian.primary.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ForgeChip(
                icon: LucideIcons.bookOpen,
                label: destinationLabel,
                color: DigitalLibrarian.secondary,
              ),
              ForgeChip(
                icon: LucideIcons.zap,
                label: '$_estimatedDeepResearchCreditCost credits',
                color: const Color(0xFFF2B544),
              ),
              ForgeChip(
                icon: _templateIcon(_selectedTemplate),
                label: _templateLabel(_selectedTemplate),
                color: DigitalLibrarian.primaryStrong,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeepResearchBriefCard({
    required ColorScheme scheme,
    required TextTheme text,
    required List<Notebook> notebooks,
    required String destinationLabel,
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
            children: _deepResearchPromptIdeas.map((prompt) {
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
                onPressed:
                    _isResearching ? null : () => _applyResearchPrompt(prompt),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (notebooks.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _showCreateNotebookDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create notebook to save research'),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: _isResearching ? null : _chooseResearchNotebook,
              icon: const Icon(Icons.book_outlined),
              label: Text('Save destination: $destinationLabel'),
            ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      !_isResearching && hasQuery ? _performSearch : null,
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
            'This run will use $_estimatedDeepResearchCreditCost credits. When it finishes, you can save the report and gathered sources back into "$destinationLabel".',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeepResearchSettingsCard({
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

  Widget _buildDeepResearchSnapshotCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final latestUpdate =
        _researchUpdates.isNotEmpty ? _researchUpdates.last : _finalResult;
    final sources = _currentResearchSources();
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

  Widget _buildDeepResearchEmptyCanvas({
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

  Widget _buildDeepResearchCanvas({
    Key? key,
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final currentSources = _currentResearchSources();
    final recentUpdates = _visibleResearchUpdates();

    return KeyedSubtree(
      key: key,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDeepResearchRunCard(
            scheme: scheme,
            text: text,
            recentUpdates: recentUpdates,
          ).animate().fadeIn().slideY(begin: 0.04),
          if (_searchedSites.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDeepResearchSitesCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 70.ms).slideY(begin: 0.04),
          ],
          if (currentSources.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDeepResearchSourcesCard(
              scheme: scheme,
              text: text,
              sources: currentSources,
            ).animate().fadeIn(delay: 120.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.result != null) ...[
            const SizedBox(height: 18),
            _buildDeepResearchReportCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 170.ms).slideY(begin: 0.04),
          ],
          if (((_finalResult?.images ??
                      (_researchUpdates.isNotEmpty
                          ? _researchUpdates.last.images
                          : null)) ??
                  [])
              .isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDeepResearchImagesCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.videos != null &&
              _finalResult!.videos!.isNotEmpty) ...[
            const SizedBox(height: 18),
            _buildDeepResearchVideosCard(
              scheme: scheme,
              text: text,
            ).animate().fadeIn(delay: 230.ms).slideY(begin: 0.04),
          ],
          if (_finalResult?.error != null && _finalResult?.result == null) ...[
            const SizedBox(height: 18),
            _buildDeepResearchErrorCard(
              scheme: scheme,
              text: text,
              message: _finalResult!.error!,
            ).animate().fadeIn(delay: 260.ms).slideY(begin: 0.04),
          ],
        ],
      ),
    );
  }

  Widget _buildDeepResearchRunCard({
    required ColorScheme scheme,
    required TextTheme text,
    required List<ResearchUpdate> recentUpdates,
  }) {
    final latestUpdate =
        _researchUpdates.isNotEmpty ? _researchUpdates.last : _finalResult;
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
                          : 'The last completed run is ready for review and can be saved into your notebook workspace.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                    if (_currentSearchQuery != null &&
                        _currentSearchQuery!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Currently searching: "$_currentSearchQuery"',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
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
                          label: '$_estimatedDeepResearchCreditCost credits',
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

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  meter,
                  const SizedBox(width: 14),
                  Expanded(child: summaryBox),
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

  Widget _buildDeepResearchSitesCard({
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
                    placeholder: (context) => Container(
                      width: 18,
                      height: 18,
                      color: scheme.surfaceContainerHighest,
                    ),
                    errorWidget: (context) => Icon(
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

  Widget _buildDeepResearchSourcesCard({
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
                  onOpen: () => _openResearchSource(source),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildDeepResearchReportCard({
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
                onPressed: () => _addReportAsSource(_finalResult!),
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save report'),
              ),
              if (_currentResearchSources().isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _addResearchSourcesAsSources,
                  icon: const Icon(Icons.library_add_outlined),
                  label:
                      Text('Save ${_currentResearchSources().length} sources'),
                ),
              OutlinedButton.icon(
                onPressed: _isResearching ? null : _performSearch,
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
            child: Builder(
              builder: (context) {
                try {
                  return MarkdownBody(
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
                      if (config.alt == 'VIDEO') {
                        return _buildVideoCard(config.uri.toString());
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AppNetworkImage(
                            imageUrl: config.uri.toString(),
                            width: config.width,
                            height: config.height,
                            fit: BoxFit.cover,
                            placeholder: (context) => Container(
                              height: 220,
                              color: scheme.surfaceContainerHighest,
                              child: const Center(
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context) => Container(
                              height: 120,
                              color: scheme.surfaceContainerHighest,
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.broken_image,
                                        color: scheme.outline),
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
                  );
                } catch (e) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.error_outline, color: scheme.error),
                            const SizedBox(width: 8),
                            Text(
                              'Error rendering report',
                              style: text.titleMedium?.copyWith(
                                color: scheme.onErrorContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'The research completed but there was an error displaying the report. You can still view the raw content below.',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onErrorContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            _finalResult!.result ?? 'No content available',
                            style: text.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeepResearchImagesCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    final images = ((_finalResult?.images ??
                (_researchUpdates.isNotEmpty
                    ? _researchUpdates.last.images
                    : null)) ??
            [])
        .whereType<String>()
        .toList();

    return _ResearchSurface(
      title: 'Research Imagery',
      subtitle:
          'Visual references collected during the run, kept alongside the report for quick context.',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: images.map((url) {
          return InkWell(
            onTap: () => _showDeepResearchImagePreview(context, url),
            borderRadius: BorderRadius.circular(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AppNetworkImage(
                imageUrl: url,
                width: 132,
                height: 132,
                fit: BoxFit.cover,
                errorWidget: (context) => Container(
                  width: 132,
                  height: 132,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDeepResearchVideosCard({
    required ColorScheme scheme,
    required TextTheme text,
  }) {
    return _ResearchSurface(
      title: 'Related Videos',
      subtitle:
          'Helpful follow-up explainers and walkthroughs pulled into the same research session.',
      child: Column(
        children: _finalResult!.videos!
            .map((url) => _buildVideoCard(url, isPreview: true))
            .toList(),
      ),
    );
  }

  Widget _buildDeepResearchErrorCard({
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final searchState = ref.watch(searchProvider);
    final notebooks = ref.watch(notebookProvider);
    final filteredResults = _applyFilters(searchState.results);

    if (_isDeepResearch) {
      return _buildDeepResearchScaffold(context, scheme, text, notebooks);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Web Search'),
        actions: [
          Consumer(builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return IconButton(
              icon: Icon(
                  mode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
              tooltip: mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            );
          }),
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Icon(Icons.search,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    decoration: InputDecoration(
                      hintText: 'Search the web for sources...',
                      hintStyle: text.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                      border: InputBorder.none,
                    ),
                    style: text.bodyMedium,
                    onSubmitted: (_) => _performSearch(),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear,
                        color: scheme.onSurface.withValues(alpha: 0.6)),
                    onPressed: () {
                      _searchController.clear();
                      ref.read(searchProvider.notifier).clearResults();
                    },
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ).animate().slideY(begin: 0.2).fadeIn(),

          // Search filters
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Web Search'),
                  selected: !_isDeepResearch,
                  onSelected: (v) => setState(() => _isDeepResearch = !v),
                  backgroundColor: scheme.surface,
                ),
                const SizedBox(width: 8),
                FilterChip(
                  avatar: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Deep Research'),
                  selected: _isDeepResearch,
                  onSelected: (v) => setState(() => _isDeepResearch = v),
                  backgroundColor: scheme.surface,
                ),
              ],
            ),
          ).animate().slideY(begin: 0.2, delay: 100.ms).fadeIn(),

          // Deep Research Options (depth and template)
          if (_isDeepResearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Depth selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text('Depth: ',
                            style: text.labelMedium
                                ?.copyWith(color: scheme.onSurface)),
                        const SizedBox(width: 8),
                        ...ResearchDepth.values.map((depth) {
                          final isSelected = _selectedDepth == depth;
                          final label = depth == ResearchDepth.quick
                              ? 'Quick'
                              : depth == ResearchDepth.standard
                                  ? 'Standard'
                                  : 'Deep';
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label,
                                  style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedDepth = depth);
                                }
                              },
                              selectedColor: scheme.primaryContainer,
                              showCheckmark: false,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Template selector
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text('Template: ',
                            style: text.labelMedium
                                ?.copyWith(color: scheme.onSurface)),
                        const SizedBox(width: 8),
                        ...ResearchTemplate.values.map((template) {
                          final isSelected = _selectedTemplate == template;
                          final label = template == ResearchTemplate.general
                              ? 'General'
                              : template == ResearchTemplate.academic
                                  ? 'Academic'
                                  : template ==
                                          ResearchTemplate.productComparison
                                      ? 'Compare'
                                      : template ==
                                              ResearchTemplate.marketAnalysis
                                          ? 'Market'
                                          : template ==
                                                  ResearchTemplate.howToGuide
                                              ? 'How-To'
                                              : 'Pros/Cons';
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(label,
                                  style: const TextStyle(fontSize: 12)),
                              selected: isSelected,
                              onSelected: (selected) {
                                if (selected) {
                                  setState(() => _selectedTemplate = template);
                                }
                              },
                              selectedColor: scheme.primaryContainer,
                              showCheckmark: false,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (notebooks.isEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _showCreateNotebookDialog,
                        icon: const Icon(Icons.add),
                        label: const Text('Create notebook to save research'),
                      ),
                    )
                  else
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedResearchNotebookId,
                      decoration: const InputDecoration(
                        labelText: 'Save research to notebook',
                        hintText: 'Choose a notebook now or when saving',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.book_outlined),
                      ),
                      style: TextStyle(color: scheme.onSurface),
                      dropdownColor: scheme.surfaceContainer,
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(
                            'Ask me when saving',
                            style: TextStyle(color: scheme.onSurface),
                          ),
                        ),
                        ...notebooks.map(
                          (notebook) => DropdownMenuItem(
                            value: notebook.id,
                            child: Text(
                              notebook.title,
                              style: TextStyle(color: scheme.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedResearchNotebookId = value;
                        });
                      },
                      selectedItemBuilder: (context) {
                        return [
                          Text(
                            'Ask me when saving',
                            style: TextStyle(color: scheme.onSurface),
                          ),
                          ...notebooks.map(
                            (notebook) => Text(
                              notebook.title,
                              style: TextStyle(color: scheme.onSurface),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ];
                      },
                    ),
                ],
              ),
            ).animate().slideY(begin: 0.2, delay: 120.ms).fadeIn(),

          // Search type selector (when not in deep research mode)
          if (!_isDeepResearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.language, size: 16),
                          SizedBox(width: 4),
                          Text('Web'),
                        ],
                      ),
                      selected: _searchType == SearchType.web,
                      onSelected: (v) {
                        if (v) setState(() => _searchType = SearchType.web);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image, size: 16),
                          SizedBox(width: 4),
                          Text('Images'),
                        ],
                      ),
                      selected: _searchType == SearchType.images,
                      onSelected: (v) {
                        if (v) setState(() => _searchType = SearchType.images);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.newspaper, size: 16),
                          SizedBox(width: 4),
                          Text('News'),
                        ],
                      ),
                      selected: _searchType == SearchType.news,
                      onSelected: (v) {
                        if (v) setState(() => _searchType = SearchType.news);
                      },
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.video_library, size: 16),
                          SizedBox(width: 4),
                          Text('Videos'),
                        ],
                      ),
                      selected: _searchType == SearchType.videos,
                      onSelected: (v) {
                        if (v) setState(() => _searchType = SearchType.videos);
                      },
                    ),
                  ],
                ),
              ),
            ).animate().slideY(begin: 0.2, delay: 150.ms).fadeIn(),

          // Filters (standard search only)
          if (!_isDeepResearch)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _filterDomainController,
                    decoration: InputDecoration(
                      hintText: 'Filter by domain or source (e.g. nytimes.com)',
                      prefixIcon: const Icon(Icons.filter_alt_outlined),
                      suffixIcon: _filterDomain.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: _clearFilters,
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onChanged: (value) {
                      setState(() => _filterDomain = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilterChip(
                        label: const Text('Has Date'),
                        selected: _filterHasDate,
                        onSelected: (value) {
                          setState(() => _filterHasDate = value);
                        },
                      ),
                      FilterChip(
                        label: const Text('Has Source'),
                        selected: _filterHasSource,
                        onSelected: (value) {
                          setState(() => _filterHasSource = value);
                        },
                      ),
                      FilterChip(
                        label: const Text('Has Image'),
                        selected: _filterHasImage,
                        onSelected: (value) {
                          setState(() => _filterHasImage = value);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ).animate().slideY(begin: 0.2, delay: 180.ms).fadeIn(),
          if (!_isDeepResearch && _webSearchHistory.isNotEmpty)
            _buildWebHistorySection(scheme, text),
          if (_isDeepResearch && _deepResearchHistory.isNotEmpty)
            _buildDeepHistorySection(scheme, text),

          const SizedBox(height: 16),

          if (searchState.verification != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.verified, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Verification: like=${searchState.verification['details']?['like']}, share=${searchState.verification['details']?['share']}',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Search status
          if (_isDeepResearch)
            _buildDeepResearchUI(scheme, text)
          else if (searchState.status == SearchStatus.loading)
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Searching the web...'),
                  ],
                ),
              ),
            )
          else if (searchState.status == SearchStatus.error)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: scheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Search failed',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      searchState.error ?? 'Unknown error occurred',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _performSearch,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            )
          else if (searchState.status == SearchStatus.success &&
              searchState.results.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search_off,
                      size: 64,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No results found',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try different keywords or check your internet connection',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else if (searchState.results.isNotEmpty && filteredResults.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.filter_alt_off,
                      size: 64,
                      color: scheme.onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No results match your filters',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try adjusting or clearing your filters',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('Clear Filters'),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredResults.isNotEmpty)
            Expanded(
              child: _searchType == SearchType.images
                  ? GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: filteredResults.length,
                      itemBuilder: (context, index) {
                        final result = filteredResults[index];
                        return _ImageResultCard(
                          result: result,
                          onAddSource: () => _addAsSource(result),
                          onTap: () => _showImagePreview(context, result),
                        )
                            .animate()
                            .scale(
                              begin: const Offset(0.8, 0.8),
                              delay: Duration(milliseconds: index * 50),
                            )
                            .fadeIn();
                      },
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: filteredResults.length,
                      itemBuilder: (context, index) {
                        final result = filteredResults[index];
                        return _SearchResultCard(
                          result: result,
                          onAddSource: () => _addAsSource(result),
                          onShare: () => Share.share(result.link),
                          onVerify: () => ref
                              .read(searchProvider.notifier)
                              .verifyYouTube(result.link),
                        )
                            .animate()
                            .slideX(
                              begin: 0.2,
                              delay: Duration(milliseconds: index * 50),
                            )
                            .fadeIn();
                      },
                    ),
            )
          else
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.travel_explore,
                      size: 64,
                      color: scheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Search the Web',
                      style: text.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Find and add web sources to your notebook',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    ElevatedButton.icon(
                      onPressed: () => _searchFocus.requestFocus(),
                      icon: const Icon(Icons.search),
                      label: const Text('Start Searching'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: searchState.status == SearchStatus.success &&
              filteredResults.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddAllDialog(context, filteredResults),
              icon: const Icon(Icons.add_circle_outline),
              label: Text('Add All (${filteredResults.length})'),
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            )
          : null,
    );
  }

  void _showHelpDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Web Search Help'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to use web search:',
              style: text.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildHelpItem(
              icon: Icons.search,
              title: 'Search Tips',
              description:
                  'Use specific keywords and phrases for better results',
              scheme: scheme,
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              icon: Icons.add_circle_outline,
              title: 'Add Sources',
              description: 'Tap the + button to add search results as sources',
              scheme: scheme,
            ),
            const SizedBox(height: 12),
            _buildHelpItem(
              icon: Icons.filter_list,
              title: 'Filters',
              description: 'Filter by domain or require date/source/image',
              scheme: scheme,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem({
    required IconData icon,
    required String title,
    required String description,
    required ColorScheme scheme,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showAddAllDialog(
      BuildContext context, List<SerperSearchResult> results) {
    final text = Theme.of(context).textTheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add All Sources?'),
        content: Text(
          'This will add ${results.length} web sources to your notebook. '
          'You can always remove them later.',
          style: text.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _addAllSources(results);
            },
            child: const Text('Add All'),
          ),
        ],
      ),
    );
  }

  void _addAllSources(List<SerperSearchResult> results) async {
    int addedCount = 0;

    for (final result in results) {
      try {
        final content = await ref
            .read(searchProvider.notifier)
            .fetchPageContent(result.link);
        await ref.read(sourceProvider.notifier).addSource(
          title: result.title,
          type: 'web',
          content: '''Title: ${result.title}
URL: ${result.link}

Summary:
${result.snippet}

Content:
$content''',
        );
        addedCount++;
      } catch (e) {
        // Continue with other sources if one fails
        continue;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added $addedCount of ${results.length} sources'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.go('/sources'),
          ),
        ),
      );
    }
  }

  Widget _buildDeepResearchUI(ColorScheme scheme, TextTheme text) {
    if (_researchUpdates.isEmpty && !_isResearching) {
      return Expanded(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Deep Research Agent',
                  style: text.headlineSmall?.copyWith(color: scheme.onSurface)),
              const SizedBox(height: 8),
              Text(
                'I can browse the web, read pages, and\nwrite a comprehensive report for you.',
                textAlign: TextAlign.center,
                style:
                    text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Expanded(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Progress section with live favicons (shown during research)
          if (_isResearching) ...[
            // Progress bar
            LinearProgressIndicator(
              value: _researchUpdates.isNotEmpty
                  ? _researchUpdates.last.progress
                  : 0,
              borderRadius: BorderRadius.circular(4),
              minHeight: 6,
            ),
            const SizedBox(height: 12),
            // Status with current search query
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: scheme.secondary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _researchUpdates.isNotEmpty
                              ? _researchUpdates.last.status
                              : 'Starting...',
                          style: text.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (_currentSearchQuery != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Looking up: "$_currentSearchQuery"',
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn().slideX(),
            // Live Favicons
            if (_searchedSites.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _searchedSites.length,
                  itemBuilder: (context, index) {
                    final domain = _searchedSites[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Chip(
                        avatar: CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: AppNetworkImage(
                            imageUrl: _getFaviconUrl(domain),
                            width: 16,
                            height: 16,
                            errorWidget: (context) => Icon(
                              Icons.language,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        label:
                            Text(domain, style: const TextStyle(fontSize: 11)),
                        backgroundColor: scheme.surfaceContainerHighest,
                        side: BorderSide.none,
                        padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
                        visualDensity: VisualDensity.compact,
                      ),
                    ).animate().scale(curve: Curves.elasticOut);
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
          ],
          if (_finalResult != null &&
              _finalResult!.result != null &&
              _finalResult!.result!.isNotEmpty) ...[
            Card(
              color: scheme.surfaceContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Builder(
                  builder: (context) {
                    try {
                      return MarkdownBody(
                        data: _finalResult!.result!,
                        styleSheet: MarkdownStyleSheet(
                          h1: text.headlineSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: text.titleLarge?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          h3: text.titleMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          p: text.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          listBullet: text.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                          ),
                          strong: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
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
                        sizedImageBuilder: (config) {
                          try {
                            if (config.alt == 'VIDEO') {
                              return _buildVideoCard(config.uri.toString());
                            }
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AppNetworkImage(
                                imageUrl: config.uri.toString(),
                                width: config.width,
                                height: config.height,
                                errorWidget: (context) =>
                                    const SizedBox.shrink(),
                              ),
                            );
                          } catch (e) {
                            return const SizedBox.shrink();
                          }
                        },
                      );
                    } catch (e) {
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.error_outline, color: scheme.error),
                                const SizedBox(width: 8),
                                Text(
                                  'Error rendering report',
                                  style: text.titleMedium?.copyWith(
                                    color: scheme.onErrorContainer,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'The research completed but there was an error displaying the report. You can still view the raw content below.',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: SelectableText(
                                _finalResult!.result ?? 'No content available',
                                style: text.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_finalResult!.result != null &&
                _finalResult!.result!.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => _addReportAsSource(_finalResult!),
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save Report to Notebook'),
                  ),
                  if (_currentResearchSources().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _addResearchSourcesAsSources,
                      icon: const Icon(Icons.library_add_outlined),
                      label: Text(
                        'Save ${_currentResearchSources().length} Sources to Notebook',
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(height: 24),
            if (((_finalResult?.images ?? _researchUpdates.last.images) ?? [])
                .isNotEmpty) ...[
              Text('Images', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    ((_finalResult?.images ?? _researchUpdates.last.images) ??
                            [])
                        .map((url) {
                  return InkWell(
                    onTap: () => _showDeepResearchImagePreview(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AppNetworkImage(
                        imageUrl: url,
                        width: 110,
                        height: 110,
                        fit: BoxFit.cover,
                        errorWidget: (context) => Container(
                          width: 110,
                          height: 110,
                          color: scheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.broken_image,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
            ],
            if (((_finalResult?.videos ?? _researchUpdates.last.videos) ?? [])
                .isNotEmpty) ...[
              Text('Videos', style: text.titleSmall),
              const SizedBox(height: 8),
              ...((_finalResult?.videos ?? _researchUpdates.last.videos) ?? [])
                  .map((url) => _buildVideoCard(url)),
              const SizedBox(height: 24),
            ],
            const Divider(),
            const SizedBox(height: 8),
            Text('Research Log', style: text.titleSmall),
            const SizedBox(height: 8),
          ],
          // Show error if research failed
          if (_finalResult != null &&
              _finalResult!.error != null &&
              _finalResult!.result == null) ...[
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: scheme.error, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Research Failed',
                            style: text.titleLarge?.copyWith(
                              color: scheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _finalResult!.error!,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _researchUpdates.clear();
                              _finalResult = null;
                              _searchedSites.clear();
                              _currentSearchQuery = null;
                            });
                            _performSearch();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try Again'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: scheme.error,
                            foregroundColor: scheme.onError,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _researchUpdates.clear();
                              _finalResult = null;
                              _searchedSites.clear();
                              _currentSearchQuery = null;
                              _isResearching = false;
                            });
                          },
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          ..._researchUpdates.map((update) {
            final isLast = update == _researchUpdates.last;
            return ListTile(
              leading: isLast && _isResearching
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.check_circle, size: 20, color: scheme.primary),
              title: Text(update.status, style: text.bodyMedium),
              dense: true,
            );
          }),
          // Sources Referenced section with favicons
          if (_finalResult != null &&
              _researchUpdates.isNotEmpty &&
              _researchUpdates.last.sources != null &&
              _researchUpdates.last.sources!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Sources Referenced', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _researchUpdates.last.sources!.map((source) {
                final domain = _extractDomain(source.url);
                return ActionChip(
                  avatar: CircleAvatar(
                    backgroundColor: Colors.transparent,
                    child: AppNetworkImage(
                      imageUrl: _getFaviconUrl(domain ?? ''),
                      width: 16,
                      height: 16,
                      errorWidget: (context) => Icon(
                        Icons.language,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  label: Text(
                    source.title.isEmpty ? 'Source' : source.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () async {
                    final uri = Uri.tryParse(source.url);
                    if (uri != null) {
                      // Import url_launcher if not already imported
                      // For now, just show a snackbar with the URL
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Source: ${source.url}')),
                      );
                    }
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  void _addReportAsSource(ResearchUpdate result) async {
    final notebookId = await _ensureResearchNotebookSelected();
    if (notebookId == null) return;

    await ref.read(sourceProvider.notifier).addSource(
          title: 'Research: ${_searchController.text}',
          type: 'report',
          content: result.result!,
          notebookId: notebookId,
        );
    if (!mounted) return;

    final notebookTitle = _notebookTitleFor(notebookId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Report saved to "$notebookTitle".'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => context.push('/memory-notebooks/$notebookId'),
        ),
      ),
    );
  }

  void _showImagePreview(BuildContext context, SerperSearchResult result) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            // Image
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                ),
                child: result.imageUrl != null
                    ? AppNetworkImage(
                        imageUrl: result.imageUrl!,
                        fit: BoxFit.contain,
                        placeholder: (context) => Container(
                          padding: const EdgeInsets.all(32),
                          color: Colors.grey[900],
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context) => Container(
                          padding: const EdgeInsets.all(32),
                          color: Colors.grey[900],
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image,
                                  size: 64, color: Colors.white54),
                              SizedBox(height: 16),
                              Text(
                                'Failed to load image',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.all(32),
                        color: Colors.grey[900],
                        child: const Icon(Icons.image_not_supported,
                            size: 64, color: Colors.white54),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            // Image info card
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    result.link,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _addAsSource(result);
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('Add to Sources'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: () => Share.share(result.link),
                        icon: const Icon(Icons.share),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showDeepResearchImagePreview(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Flexible(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7,
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                ),
                child: AppNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (context) => Container(
                    padding: const EdgeInsets.all(32),
                    color: Colors.grey[900],
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  errorWidget: (context) => Container(
                    padding: const EdgeInsets.all(32),
                    color: Colors.grey[900],
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.broken_image,
                            size: 64, color: Colors.white54),
                        SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(String url, {bool isPreview = false}) {
    final videoId = _extractVideoId(url);
    final thumbnailUrl =
        videoId != null ? 'https://img.youtube.com/vi/$videoId/0.jpg' : null;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          if (videoId != null) {
            _showVideoPlayer(context, videoId);
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (thumbnailUrl != null)
              AppNetworkImage(
                imageUrl: thumbnailUrl,
                width: isPreview ? null : double.infinity,
                height: isPreview ? 120 : 200,
                fit: BoxFit.cover,
                errorWidget: (context) => Container(
                  height: isPreview ? 120 : 200,
                  width: isPreview ? 160 : double.infinity,
                  color: Colors.black12,
                  child: const Center(child: Icon(Icons.video_library)),
                ),
              )
            else
              Container(
                height: isPreview ? 120 : 200,
                width: isPreview ? 160 : double.infinity,
                color: Colors.black12,
                child: const Center(child: Icon(Icons.video_library)),
              ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.play_arrow, color: Colors.white, size: 32),
            ),
          ],
        ),
      ),
    );
  }

  void _showVideoPlayer(BuildContext context, String videoId) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        child: YouTubePlayerDialog(videoId: videoId),
      ),
    );
  }

  String? _extractVideoId(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    if (uri.host.contains('youtube.com')) {
      return uri.queryParameters['v'];
    }
    if (uri.host.contains('youtu.be')) {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    return null;
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
                placeholder: (context) => Container(
                  height: 128,
                  color: scheme.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context) => Container(
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
                            placeholder: (context) => Container(
                              width: 20,
                              height: 20,
                              color: scheme.surfaceContainerHighest,
                            ),
                            errorWidget: (context) => Icon(
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

class _WebSearchHistoryItem {
  final String query;
  final String searchType;
  final DateTime timestamp;

  _WebSearchHistoryItem({
    required this.query,
    required this.searchType,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        'searchType': searchType,
        'timestamp': timestamp.toIso8601String(),
      };

  factory _WebSearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return _WebSearchHistoryItem(
      query: json['query']?.toString() ?? '',
      searchType: json['searchType']?.toString() ?? SearchType.web.name,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _DeepResearchHistoryItem {
  final String query;
  final String depth;
  final String template;
  final String summary;
  final DateTime timestamp;

  _DeepResearchHistoryItem({
    required this.query,
    required this.depth,
    required this.template,
    required this.summary,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'query': query,
        'depth': depth,
        'template': template,
        'summary': summary,
        'timestamp': timestamp.toIso8601String(),
      };

  factory _DeepResearchHistoryItem.fromJson(Map<String, dynamic> json) {
    return _DeepResearchHistoryItem(
      query: json['query']?.toString() ?? '',
      depth: json['depth']?.toString() ?? ResearchDepth.standard.name,
      template: json['template']?.toString() ?? ResearchTemplate.general.name,
      summary: json['summary']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.result,
    required this.onAddSource,
    required this.onShare,
    required this.onVerify,
  });

  final SerperSearchResult result;
  final VoidCallback onAddSource;
  final VoidCallback onShare;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: () => _showResultDetails(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const SizedBox(height: 4),
                        Text(
                          result.link,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.public,
                      color: scheme.primary,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                result.snippet,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onAddSource,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add Source'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(width: 8),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: onShare,
                    icon: Icon(
                      Icons.share,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showResultDetails(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    result.title,
                    style: text.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              result.link,
              style: text.bodyMedium?.copyWith(
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Summary',
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              result.snippet,
              style: text.bodyMedium,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onAddSource();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add as Source'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      onShare();
                    },
                    icon: const Icon(Icons.share),
                    label: const Text('Share'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Image Result Card for grid display
class _ImageResultCard extends StatelessWidget {
  const _ImageResultCard({
    required this.result,
    required this.onAddSource,
    required this.onTap,
  });

  final SerperSearchResult result;
  final VoidCallback onAddSource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image thumbnail
            Expanded(
              child: Container(
                width: double.infinity,
                color: scheme.surfaceContainerHighest,
                child: result.imageUrl != null
                    ? AppNetworkImage(
                        imageUrl: result.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (context) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        errorWidget: (context) {
                          return Container(
                            color: scheme.surfaceContainerHighest,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  size: 48,
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.4),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Image unavailable',
                                  style: text.bodySmall?.copyWith(
                                    color:
                                        scheme.onSurface.withValues(alpha: 0.4),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.image_not_supported,
                            size: 48,
                            color: scheme.onSurface.withValues(alpha: 0.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No preview',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            // Title and add button
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.title,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAddSource,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
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
