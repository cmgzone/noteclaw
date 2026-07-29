import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../ui/digital_librarian.dart';
import 'code_review_detail_view.dart';
import 'code_review_github_file_picker.dart';
import 'code_review_provider.dart';
import '../github/github_provider.dart';

class CodeReviewScreen extends ConsumerStatefulWidget {
  const CodeReviewScreen({super.key});

  @override
  ConsumerState<CodeReviewScreen> createState() => _CodeReviewScreenState();
}

class _CodeReviewScreenState extends ConsumerState<CodeReviewScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _codeController = TextEditingController();
  final _ownerController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController();
  String _selectedLanguage = 'dart';
  String _selectedReviewType = 'comprehensive';
  String? _selectedGitHubRepoFullName;
  String? _selectedGitHubFilePath;
  String? _selectedGitHubBranch;

  // GitHub context for context-aware reviews
  bool _useGitHubContext = false;

  final _languages = [
    'dart',
    'javascript',
    'typescript',
    'python',
    'java',
    'kotlin',
    'swift',
    'go',
    'rust',
    'c',
    'cpp',
    'csharp',
    'php',
    'ruby',
    'sql'
  ];

  final _reviewTypes = [
    ('comprehensive', 'Comprehensive', Icons.analytics),
    ('security', 'Security', Icons.security),
    ('performance', 'Performance', Icons.speed),
    ('readability', 'Readability', Icons.visibility),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Load history on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncGitHubState();
      ref.read(codeReviewProvider.notifier).loadHistory();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _ownerController.dispose();
    _repoController.dispose();
    _branchController.dispose();
    super.dispose();
  }

  Future<void> _syncGitHubState() async {
    final githubNotifier = ref.read(githubProvider.notifier);
    await githubNotifier.checkStatus();

    final githubState = ref.read(githubProvider);
    if (githubState.isConnected && githubState.repos.isEmpty) {
      await githubNotifier.loadRepos();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codeReviewProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(
          compact: true,
          eyebrow: 'Code review',
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'New Review', icon: Icon(Icons.rate_review)),
            Tab(text: 'History', icon: Icon(Icons.history)),
          ],
        ),
      ),
      bottomNavigationBar: const MemoryToolNavigationBar(
        selected: MemoryToolDestination.codeReview,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildNewReviewTab(state, theme),
          _buildHistoryTab(state, theme),
        ],
      ),
    );
  }

  Widget _buildNewReviewTab(CodeReviewState state, ThemeData theme) {
    final githubState = ref.watch(githubProvider);
    final isGitHubConnected = githubState.isConnected;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildReviewIntro(theme),
          const SizedBox(height: 16),
          // Language selector
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Language',
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedLanguage,
                      isExpanded: true,
                      isDense: true,
                      items: _languages.map((lang) {
                        return DropdownMenuItem(value: lang, child: Text(lang));
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedLanguage = value);
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Paste button
              IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Paste from clipboard',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _codeController.text = data!.text!;
                  }
                },
              ),
              if (isGitHubConnected) ...[
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  onPressed: state.isLoading ? null : _loadCodeFromGitHub,
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('GitHub'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // Review type chips
          Wrap(
            spacing: 8,
            children: _reviewTypes.map((type) {
              final isSelected = _selectedReviewType == type.$1;
              return ChoiceChip(
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(type.$3, size: 16),
                    const SizedBox(width: 4),
                    Text(type.$2),
                  ],
                ),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) setState(() => _selectedReviewType = type.$1);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Code input
          TextField(
            controller: _codeController,
            maxLines: 12,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Code to review',
              hintText: isGitHubConnected
                  ? 'Paste code or load a file from GitHub...'
                  : 'Enter or paste code to review...',
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.3),
            ),
          ),
          if (_selectedGitHubFilePath != null) ...[
            const SizedBox(height: 12),
            _buildGitHubFileBanner(theme),
          ],
          const SizedBox(height: 16),

          // GitHub Context Toggle
          _buildGitHubContextSection(theme),
          const SizedBox(height: 16),

          // Submit button
          FilledButton.icon(
            onPressed: state.isLoading ? null : _submitReview,
            icon: state.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.rate_review),
            label: Text(state.isLoading ? 'Reviewing...' : 'Review Code'),
          ),
          const SizedBox(height: 24),

          // Results
          if (state.currentReview != null)
            CodeReviewDetailView(review: state.currentReview!),
          if (state.error != null)
            Card(
              color: theme.colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(state.error!,
                    style:
                        TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreIndicator(
    int score,
    ThemeData theme, {
    double size = 80,
  }) {
    Color color;
    if (score >= 90) {
      color = Colors.green;
    } else if (score >= 70) {
      color = Colors.lightGreen;
    } else if (score >= 50) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: size * 0.1,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '$score',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: size * 0.28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab(CodeReviewState state, ThemeData theme) {
    if (state.isLoading && state.history.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text('No review history yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Run an in-app review or an MCP verification to get started',
                style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(codeReviewProvider.notifier).loadHistory(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHistoryOverview(state.history, theme),
          const SizedBox(height: 14),
          ...state.history.map((item) => _buildHistoryCard(item, theme)),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(CodeReviewHistoryItem item, ThemeData theme) {
    final scheme = theme.colorScheme;
    final sourceColor = _sourceColor(item.source, theme);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: sourceColor.withValues(alpha: 0.18),
        ),
      ),
      child: InkWell(
        onTap: () => context.pushNamed(
          'code-review-detail',
          pathParameters: {'reviewId': item.id},
        ),
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildScoreIndicator(item.score, theme, size: 72),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildMetaChip(
                              label: _sourceLabel(item.source),
                              icon: item.isMcp
                                  ? Icons.memory_rounded
                                  : Icons.rate_review_rounded,
                              color: sourceColor,
                              theme: theme,
                              compact: true,
                            ),
                            _buildMetaChip(
                              label: item.language.toUpperCase(),
                              icon: Icons.code_rounded,
                              color: scheme.secondary,
                              theme: theme,
                              compact: true,
                            ),
                            _buildMetaChip(
                              label: _reviewTypeLabel(
                                item.reviewType,
                                toolName: item.toolName,
                              ),
                              icon: _reviewTypeIcon(
                                item.reviewType,
                                toolName: item.toolName,
                              ),
                              color: scheme.primary,
                              theme: theme,
                              compact: true,
                            ),
                            if (item.isContextAware)
                              _buildMetaChip(
                                label: item.relatedFileCount > 0
                                    ? '${item.relatedFileCount} related files'
                                    : 'Context-aware',
                                icon: Icons.auto_awesome_rounded,
                                color: scheme.tertiary,
                                theme: theme,
                                compact: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _reviewHeadline(
                            item.reviewType,
                            toolName: item.toolName,
                          ),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (item.summary.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.summary,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: scheme.outline,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  item.codePreview,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildSmallIssueChip(
                        label: 'Errors',
                        count: item.errorCount,
                        color: Colors.red,
                      ),
                      _buildSmallIssueChip(
                        label: 'Warnings',
                        count: item.warningCount,
                        color: Colors.orange,
                      ),
                      _buildSmallIssueChip(
                        label: 'Info',
                        count: item.infoCount,
                        color: Colors.blue,
                      ),
                    ],
                  ),
                  Text(
                    _formatDate(item.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

  Widget _buildHistoryOverview(
    List<CodeReviewHistoryItem> history,
    ThemeData theme,
  ) {
    final mcpCount = history.where((item) => item.isMcp).length;
    final contextCount = history.where((item) => item.isContextAware).length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.secondaryContainer,
            theme.colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review timeline',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'A combined stream of manual reviews, MCP verification runs, and context-aware analysis.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _buildMetricCard(
                label: 'Total',
                value: history.length,
                icon: Icons.history_toggle_off_rounded,
                color: theme.colorScheme.primary,
                theme: theme,
              ),
              _buildMetricCard(
                label: 'MCP',
                value: mcpCount,
                icon: Icons.memory_rounded,
                color: theme.colorScheme.tertiary,
                theme: theme,
              ),
              _buildMetricCard(
                label: 'Context-aware',
                value: contextCount,
                icon: Icons.auto_awesome_rounded,
                color: theme.colorScheme.secondary,
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmallIssueChip({
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildReviewIntro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primaryContainer,
            theme.colorScheme.surface,
          ],
        ),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ship cleaner reviews faster',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Run focused reviews, compare manual and MCP-generated feedback, and keep the strongest findings in one history stream.',
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildMetaChip(
                label: 'App reviews',
                icon: Icons.rate_review_rounded,
                color: theme.colorScheme.primary,
                theme: theme,
              ),
              _buildMetaChip(
                label: 'MCP history',
                icon: Icons.memory_rounded,
                color: theme.colorScheme.tertiary,
                theme: theme,
              ),
              _buildMetaChip(
                label: 'Repo context',
                icon: Icons.auto_awesome_rounded,
                color: theme.colorScheme.secondary,
                theme: theme,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _sourceColor(String source, ThemeData theme) {
    return source == 'mcp'
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
  }

  String _sourceLabel(String source) {
    return source == 'mcp' ? 'MCP Review' : 'App Review';
  }

  String _reviewHeadline(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
        return 'MCP verification pass';
      case 'verify_and_save':
        return 'Verified and saved source review';
      case 'analyze_code':
        return 'MCP deep analysis';
      default:
        return '${_reviewTypeLabel(reviewType, toolName: toolName)} review';
    }
  }

  String _reviewTypeLabel(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
        return 'Verify';
      case 'verify_and_save':
        return 'Verify + Save';
      case 'analyze_code':
        return 'Analyze';
      case 'comprehensive':
        return 'Comprehensive';
      case 'security':
        return 'Security';
      case 'performance':
        return 'Performance';
      case 'readability':
        return 'Readability';
      default:
        return _titleCase(reviewType);
    }
  }

  IconData _reviewTypeIcon(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
      case 'verify_and_save':
        return Icons.verified_outlined;
      case 'analyze_code':
        return Icons.analytics_outlined;
      case 'security':
        return Icons.security_rounded;
      case 'performance':
        return Icons.speed_rounded;
      case 'readability':
        return Icons.visibility_rounded;
      default:
        return Icons.rate_review_rounded;
    }
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes.clamp(1, 59);
      return '$minutes min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  Widget _buildGitHubContextSection(ThemeData theme) {
    final githubState = ref.watch(githubProvider);
    final isConnected = githubState.isConnected;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: _useGitHubContext
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Context-Aware Review',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: _useGitHubContext,
                  onChanged: isConnected
                      ? (value) => setState(() => _useGitHubContext = value)
                      : null,
                ),
              ],
            ),
            if (!isConnected) ...[
              const SizedBox(height: 8),
              Text(
                'Connect GitHub to enable context-aware reviews',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => context.push('/github'),
                icon: const Icon(Icons.link, size: 16),
                label: const Text('Connect GitHub'),
              ),
            ] else if (_useGitHubContext) ...[
              const SizedBox(height: 12),
              Text(
                'Load a file with the GitHub button above, or enter a repo here so the AI can fetch related files for imports and dependencies.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ownerController,
                      decoration: const InputDecoration(
                        labelText: 'Owner',
                        hintText: 'username',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('/'),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _repoController,
                      decoration: const InputDecoration(
                        labelText: 'Repository',
                        hintText: 'repo-name',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _branchController,
                decoration: const InputDecoration(
                  labelText: 'Branch (optional)',
                  hintText: 'main',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              // Quick select from connected repos
              if (githubState.repos.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: githubState.repos.take(5).map((repo) {
                    return ActionChip(
                      avatar: const Icon(Icons.folder, size: 16),
                      label:
                          Text(repo.name, style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        setState(() {
                          _ownerController.text = repo.owner;
                          _repoController.text = repo.name;
                          _branchController.text = repo.defaultBranch;
                        });
                      },
                    );
                  }).toList(),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGitHubFileBanner(ThemeData theme) {
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.source_outlined, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Loaded from GitHub',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                if (_selectedGitHubRepoFullName != null)
                  Text(
                    _selectedGitHubRepoFullName!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  _selectedGitHubFilePath!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
                if (_selectedGitHubBranch != null &&
                    _selectedGitHubBranch!.isNotEmpty)
                  Text(
                    'Branch: $_selectedGitHubBranch',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Clear GitHub file',
            onPressed: () {
              setState(() {
                _selectedGitHubRepoFullName = null;
                _selectedGitHubFilePath = null;
                _selectedGitHubBranch = null;
              });
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCodeFromGitHub() async {
    final selection = await showGitHubReviewFilePicker(
      context,
      initialOwner: _ownerController.text.trim().isEmpty
          ? null
          : _ownerController.text.trim(),
      initialRepo: _repoController.text.trim().isEmpty
          ? null
          : _repoController.text.trim(),
      initialBranch: _branchController.text.trim().isEmpty
          ? null
          : _branchController.text.trim(),
    );

    if (!mounted || selection == null) {
      return;
    }

    setState(() {
      _codeController.text = selection.content;
      _selectedLanguage = selection.language;
      _selectedGitHubRepoFullName = selection.repo.fullName;
      _selectedGitHubFilePath = selection.path;
      _selectedGitHubBranch = selection.branch;
      _ownerController.text = selection.repo.owner;
      _repoController.text = selection.repo.name;
      _branchController.text = selection.branch;
      _useGitHubContext = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Loaded ${selection.path.split('/').last} from ${selection.repo.fullName}',
        ),
      ),
    );
  }

  Future<void> _submitReview() async {
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter some code to review')),
      );
      return;
    }

    // Build GitHub context if enabled
    GitHubReviewContext? githubContext;
    if (_useGitHubContext &&
        _ownerController.text.isNotEmpty &&
        _repoController.text.isNotEmpty) {
      githubContext = GitHubReviewContext(
        owner: _ownerController.text.trim(),
        repo: _repoController.text.trim(),
        branch: _branchController.text.trim().isNotEmpty
            ? _branchController.text.trim()
            : null,
      );
    }

    await ref.read(codeReviewProvider.notifier).reviewCode(
          code: _codeController.text,
          language: _selectedLanguage,
          reviewType: _selectedReviewType,
          githubContext: githubContext,
        );
  }
}
