import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class WebSearchScreen extends ConsumerStatefulWidget {
  const WebSearchScreen({super.key});

  @override
  ConsumerState<WebSearchScreen> createState() => _WebSearchScreenState();
}

class _WebSearchScreenState extends ConsumerState<WebSearchScreen> {
  static const _webSearchHistoryKey = 'web_search_history_v1';
  static const _deepResearchHistoryKey = 'deep_research_history_v1';
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _filterDomainController =
      TextEditingController();
  bool _isDeepResearch = false;
  bool _isResearching = false;
  List<ResearchUpdate> _researchUpdates = [];
  ResearchUpdate? _finalResult;
  SearchType _searchType = SearchType.web;

  // New feature states
  ResearchDepth _selectedDepth = ResearchDepth.standard;
  ResearchTemplate _selectedTemplate = ResearchTemplate.general;

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

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _filterDomainController.dispose();
    super.dispose();
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
        await ref.read(searchProvider.notifier).search(query, type: _searchType);
        final latestState = ref.read(searchProvider);
        if (latestState.status == SearchStatus.success) {
          await _saveWebSearchHistory(query, _searchType);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Search failed: ${_getFriendlyErrorMessage(e.toString())}')),
          );
        }
      }
    }
  }

  Future<void> _performDeepResearch(String query) async {
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
          notebookId: '',
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
        final list = (jsonDecode(webHistoryRaw) as List)
            .cast<Map<String, dynamic>>();
        loadedWeb = list
            .map(_WebSearchHistoryItem.fromJson)
            .where((item) => item.query.trim().isNotEmpty)
            .toList();
      } catch (_) {}
    }

    if (deepHistoryRaw != null && deepHistoryRaw.isNotEmpty) {
      try {
        final list = (jsonDecode(deepHistoryRaw) as List)
            .cast<Map<String, dynamic>>();
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
        (item) =>
            !(item.query.toLowerCase() == normalizedQuery.toLowerCase() &&
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
        (item) =>
            !(item.query.toLowerCase() == normalizedQuery.toLowerCase() &&
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final searchState = ref.watch(searchProvider);
    final filteredResults = _applyFilters(searchState.results);

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
          else if (searchState.results.isNotEmpty &&
              filteredResults.isEmpty)
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
              ElevatedButton.icon(
                onPressed: () => _addReportAsSource(_finalResult!),
                icon: const Icon(Icons.add),
                label: const Text('Add Report to Notebook'),
              ),
            const SizedBox(height: 24),
            if (((_finalResult?.images ?? _researchUpdates.last.images) ?? [])
                .isNotEmpty) ...[
              Text('Images', style: text.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ((_finalResult?.images ??
                            _researchUpdates.last.images) ??
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
    await ref.read(sourceProvider.notifier).addSource(
          title: 'Research: ${_searchController.text}',
          type: 'report',
          content: result.result!,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report added to notebook')),
      );
      context.go('/sources');
    }
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
