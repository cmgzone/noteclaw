import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/github/github_service.dart';
import '../../ui/digital_librarian.dart';
import '../../ui/forge.dart';
import 'code_review_detail_view.dart';
import 'code_review_github_file_picker.dart';
import 'code_review_provider.dart';
import '../github/github_provider.dart';

class CodeReviewScreen extends ConsumerStatefulWidget {
  const CodeReviewScreen({super.key});

  @override
  ConsumerState<CodeReviewScreen> createState() => _CodeReviewScreenState();
}

class _CodeReviewScreenState extends ConsumerState<CodeReviewScreen> {
  int _tabIndex = 0; // 0 = new review, 1 = history
  final _codeController = TextEditingController();
  final _ownerController = TextEditingController();
  final _repoController = TextEditingController();
  final _branchController = TextEditingController();
  String _selectedLanguage = 'dart';
  String _selectedReviewType = 'comprehensive';
  String? _selectedGitHubRepoFullName;
  String? _selectedGitHubFilePath;
  String? _selectedGitHubBranch;

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
    ('comprehensive', 'Comprehensive', LucideIcons.layers),
    ('security', 'Security', LucideIcons.shield),
    ('performance', 'Performance', LucideIcons.zap),
    ('readability', 'Readability', LucideIcons.eye),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncGitHubState();
      ref.read(codeReviewProvider.notifier).loadHistory();
    });
  }

  @override
  void dispose() {
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
    final githubState = ref.watch(githubProvider);

    return Scaffold(
      backgroundColor: DigitalLibrarian.background,
      body: ForgeBackground(
        glowOne: DigitalLibrarian.tertiary,
        glowTwo: DigitalLibrarian.primaryStrong,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                githubConnected: githubState.isConnected,
                tabIndex: _tabIndex,
                onTabChanged: (i) => setState(() => _tabIndex = i),
              ),
              Expanded(
                child: _tabIndex == 0
                    ? _buildNewReviewTab(state)
                    : _buildHistoryTab(state),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: const MemoryToolNavigationBar(
        selected: MemoryToolDestination.codeReview,
      ),
    );
  }

  Widget _buildNewReviewTab(CodeReviewState state) {
    final githubState = ref.watch(githubProvider);
    final isGitHubConnected = githubState.isConnected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        // Language + actions row
        ForgePanel(
          accent: DigitalLibrarian.tertiary,
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(LucideIcons.code2,
                  size: 16, color: DigitalLibrarian.tertiary),
              const SizedBox(width: 10),
              SizedBox(
                width: 130,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedLanguage,
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: DigitalLibrarian.surfaceContainer,
                    style: Forge.mono(context,
                        size: 12,
                        color: DigitalLibrarian.primary,
                        letterSpacing: 0.4),
                    items: _languages
                        .map((lang) => DropdownMenuItem(
                              value: lang,
                              child: Text(lang),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _selectedLanguage = value);
                      }
                    },
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(LucideIcons.clipboard, size: 16),
                tooltip: 'Paste from clipboard',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _codeController.text = data!.text!;
                  }
                },
              ),
              if (isGitHubConnected)
                IconButton(
                  icon: const Icon(LucideIcons.github, size: 16),
                  tooltip: 'Load from GitHub',
                  onPressed: state.isLoading ? null : _loadCodeFromGitHub,
                ),
            ],
          ),
        ).animate().fadeIn(duration: 350.ms).slideY(
              begin: 0.1,
              end: 0,
              duration: 350.ms,
              curve: Curves.easeOutCubic,
            ),
        const SizedBox(height: 14),

        // Review type selector
        const ForgeEyebrow('REVIEW LENS'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _reviewTypes.map((type) {
            final isSelected = _selectedReviewType == type.$1;
            return ForgeChip(
              icon: type.$3,
              label: type.$2,
              color: DigitalLibrarian.tertiary,
              selected: isSelected,
              onTap: () => setState(() => _selectedReviewType = type.$1),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),

        // Code editor panel
        _CodeEditorPanel(
          controller: _codeController,
          language: _selectedLanguage,
          isGitHubConnected: isGitHubConnected,
          gitHubFile: _selectedGitHubFilePath,
          onClearGitHubFile: () {
            setState(() {
              _selectedGitHubRepoFullName = null;
              _selectedGitHubFilePath = null;
              _selectedGitHubBranch = null;
            });
          },
          gitHubRepo: _selectedGitHubRepoFullName,
          gitHubBranch: _selectedGitHubBranch,
        ),
        const SizedBox(height: 16),

        // GitHub context toggle
        _GitHubContextPanel(
          useContext: _useGitHubContext,
          onToggle: (v) => setState(() => _useGitHubContext = v),
          isConnected: isGitHubConnected,
          ownerController: _ownerController,
          repoController: _repoController,
          branchController: _branchController,
          repos: githubState.repos,
        ),
        const SizedBox(height: 18),

        ForgeButton(
          label: state.isLoading ? 'Reviewing…' : 'Run review',
          icon: state.isLoading ? null : LucideIcons.scan,
          color: DigitalLibrarian.tertiary,
          expand: true,
          onPressed: state.isLoading ? null : _submitReview,
        ),
        const SizedBox(height: 20),

        if (state.currentReview != null)
          CodeReviewDetailView(review: state.currentReview!),
        if (state.error != null)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF27E9D).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFF27E9D).withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              state.error!,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFF27E9D)),
            ),
          ),
      ],
    );
  }

  Widget _buildHistoryTab(CodeReviewState state) {
    if (state.isLoading && state.history.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    if (state.history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: DigitalLibrarian.tertiary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: DigitalLibrarian.tertiary.withValues(alpha: 0.35),
                ),
              ),
              child: const Icon(LucideIcons.history,
                  size: 32, color: DigitalLibrarian.tertiary),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 22),
            Text('No reviews yet', style: Forge.display(context, size: 22)),
            const SizedBox(height: 8),
            Text(
              'Run an in-app review or an MCP verification to get started.',
              style: TextStyle(
                fontSize: 13.5,
                color: DigitalLibrarian.primary.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    final mcpCount = state.history.where((item) => item.isMcp).length;
    final contextCount =
        state.history.where((item) => item.isContextAware).length;

    return RefreshIndicator(
      onRefresh: () => ref.read(codeReviewProvider.notifier).loadHistory(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          ForgePanel(
            accent: DigitalLibrarian.tertiary,
            child: Row(
              children: [
                ForgeStat(
                  value: '${state.history.length}',
                  label: 'Total',
                  color: DigitalLibrarian.primary,
                ),
                _divider(),
                ForgeStat(
                  value: '$mcpCount',
                  label: 'MCP',
                  color: DigitalLibrarian.tertiary,
                ),
                _divider(),
                ForgeStat(
                  value: '$contextCount',
                  label: 'Context',
                  color: DigitalLibrarian.secondary,
                ),
              ],
            ),
          ).animate().fadeIn(duration: 380.ms).slideY(
                begin: 0.1,
                end: 0,
                duration: 380.ms,
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 14),
          ...state.history.map(
            (item) => _HistoryCard(item: item)
                .animate()
                .fadeIn(duration: 380.ms)
                .slideY(
                  begin: 0.1,
                  end: 0,
                  duration: 380.ms,
                  curve: Curves.easeOutCubic,
                ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: DigitalLibrarian.outline.withValues(alpha: 0.5),
      );

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

class _Header extends StatelessWidget {
  final bool githubConnected;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  const _Header({
    required this.githubConnected,
    required this.tabIndex,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ForgeEyebrow('CODE REVIEW'),
                    const SizedBox(height: 6),
                    Text('Review console',
                        style: Forge.display(context, size: 30)),
                  ],
                ),
              ),
              ForgeStatus(
                label: githubConnected ? 'GitHub' : 'No GitHub',
                active: githubConnected,
                color: DigitalLibrarian.tertiary,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _TabSwitch(tabIndex: tabIndex, onTabChanged: onTabChanged),
        ],
      ),
    );
  }
}

class _TabSwitch extends StatelessWidget {
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  const _TabSwitch({required this.tabIndex, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DigitalLibrarian.surfaceLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DigitalLibrarian.outline.withValues(alpha: 0.6),
        ),
      ),
      child: Row(
        children: [
          _tab(context, 0, LucideIcons.scan, 'New review'),
          _tab(context, 1, LucideIcons.history, 'History'),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int index, IconData icon, String label) {
    final selected = tabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? DigitalLibrarian.tertiary.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? DigitalLibrarian.tertiary.withValues(alpha: 0.55)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected
                    ? DigitalLibrarian.tertiary
                    : DigitalLibrarian.primary.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? DigitalLibrarian.tertiary
                      : DigitalLibrarian.primary.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Code editor panel with a mono top bar and dark editing surface.
class _CodeEditorPanel extends StatelessWidget {
  final TextEditingController controller;
  final String language;
  final bool isGitHubConnected;
  final String? gitHubFile;
  final String? gitHubRepo;
  final String? gitHubBranch;
  final VoidCallback onClearGitHubFile;

  const _CodeEditorPanel({
    required this.controller,
    required this.language,
    required this.isGitHubConnected,
    required this.gitHubFile,
    required this.gitHubRepo,
    required this.gitHubBranch,
    required this.onClearGitHubFile,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: DigitalLibrarian.surfaceLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DigitalLibrarian.outline.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: DigitalLibrarian.surfaceContainer,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(13),
              ),
              border: Border(
                bottom: BorderSide(
                  color: DigitalLibrarian.outline.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Row(
                  children: [
                    _dot(const Color(0xFFFF5F57)),
                    _dot(const Color(0xFFFEBC2E)),
                    _dot(const Color(0xFF28C840)),
                  ],
                ),
                const SizedBox(width: 12),
                Text(
                  'source.$language',
                  style: Forge.mono(context,
                      size: 10.5,
                      color: DigitalLibrarian.primary.withValues(alpha: 0.7),
                      letterSpacing: 0.4),
                ),
                const Spacer(),
                Text(
                  'UTF-8',
                  style: Forge.mono(context,
                      size: 9,
                      color: DigitalLibrarian.primary.withValues(alpha: 0.4),
                      letterSpacing: 0.6),
                ),
              ],
            ),
          ),
          TextField(
            controller: controller,
            maxLines: 12,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12.5,
              height: 1.5,
              color: DigitalLibrarian.primary,
            ),
            decoration: InputDecoration(
              hintText: isGitHubConnected
                  ? '// paste code or load a file from GitHub…'
                  : '// enter or paste code to review…',
              hintStyle: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                color: DigitalLibrarian.primary.withValues(alpha: 0.3),
              ),
              border: InputBorder.none,
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.all(16),
            ),
          ),
          if (gitHubFile != null)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: DigitalLibrarian.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: DigitalLibrarian.tertiary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.github,
                      size: 14, color: DigitalLibrarian.tertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (gitHubRepo != null)
                          Text(
                            gitHubRepo!,
                            style: Forge.mono(context,
                                size: 9.5,
                                color: DigitalLibrarian.primary
                                    .withValues(alpha: 0.6),
                                letterSpacing: 0.3),
                          ),
                        Text(
                          gitHubFile!,
                          style: Forge.mono(context,
                              size: 10.5,
                              color: DigitalLibrarian.tertiary,
                              letterSpacing: 0.3),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Clear GitHub file',
                    onPressed: onClearGitHubFile,
                    icon: Icon(
                      LucideIcons.x,
                      size: 14,
                      color: DigitalLibrarian.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
        width: 9,
        height: 9,
        margin: const EdgeInsets.only(right: 5),
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

class _GitHubContextPanel extends StatelessWidget {
  final bool useContext;
  final ValueChanged<bool> onToggle;
  final bool isConnected;
  final TextEditingController ownerController;
  final TextEditingController repoController;
  final TextEditingController branchController;
  final List<GitHubRepo> repos;

  const _GitHubContextPanel({
    required this.useContext,
    required this.onToggle,
    required this.isConnected,
    required this.ownerController,
    required this.repoController,
    required this.branchController,
    required this.repos,
  });

  @override
  Widget build(BuildContext context) {
    return ForgePanel(
      accent: useContext ? DigitalLibrarian.secondary : null,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                LucideIcons.sparkles,
                size: 16,
                color: useContext
                    ? DigitalLibrarian.secondary
                    : DigitalLibrarian.primary.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Context-aware review',
                  style: Forge.display(context, size: 14.5),
                ),
              ),
              Switch(
                value: useContext,
                onChanged: isConnected ? onToggle : null,
                activeThumbColor: DigitalLibrarian.secondary,
              ),
            ],
          ),
          if (!isConnected) ...[
            const SizedBox(height: 6),
            Text(
              'Connect GitHub to enable context-aware reviews.',
              style: TextStyle(
                fontSize: 12.5,
                color: DigitalLibrarian.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 10),
            ForgeChip(
              icon: LucideIcons.link,
              label: 'Connect GitHub',
              color: DigitalLibrarian.secondary,
              onTap: () => context.push('/github'),
            ),
          ] else if (useContext) ...[
            const SizedBox(height: 8),
            Text(
              'Load a file above, or point at a repo so the AI can pull related files for imports and dependencies.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: DigitalLibrarian.primary.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ownerController,
                    decoration: const InputDecoration(
                      labelText: 'Owner',
                      hintText: 'username',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text('/',
                    style: TextStyle(
                      color: DigitalLibrarian.primary.withValues(alpha: 0.4),
                    )),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: repoController,
                    decoration: const InputDecoration(
                      labelText: 'Repository',
                      hintText: 'repo-name',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: branchController,
              decoration: const InputDecoration(
                labelText: 'Branch (optional)',
                hintText: 'main',
                isDense: true,
              ),
            ),
            if (repos.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: repos.take(5).map((repo) {
                  return ForgeChip(
                    icon: LucideIcons.folder,
                    label: repo.name,
                    color: DigitalLibrarian.primary,
                    onTap: () {
                      ownerController.text = repo.owner;
                      repoController.text = repo.name;
                      branchController.text = repo.defaultBranch;
                    },
                  );
                }).toList(),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  final CodeReviewHistoryItem item;

  const _HistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final sourceColor = item.source == 'mcp'
        ? DigitalLibrarian.tertiary
        : DigitalLibrarian.primaryStrong;

    return ForgePanel(
      margin: const EdgeInsets.only(bottom: 12),
      accent: sourceColor,
      onTap: () => context.pushNamed(
        'code-review-detail',
        pathParameters: {'reviewId': item.id},
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForgeScoreRing(score: item.score, size: 64),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        ForgeChip(
                          icon: item.isMcp ? LucideIcons.cpu : LucideIcons.scan,
                          label: item.source == 'mcp' ? 'MCP' : 'App',
                          color: sourceColor,
                        ),
                        ForgeChip(
                          label: item.language.toUpperCase(),
                          color: DigitalLibrarian.secondary,
                        ),
                        if (item.isContextAware)
                          const ForgeChip(
                            icon: LucideIcons.sparkles,
                            label: 'Context',
                            color: DigitalLibrarian.tertiary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _reviewHeadline(item.reviewType,
                          toolName: item.toolName),
                      style: Forge.display(context, size: 15.5),
                    ),
                    if (item.summary.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        item.summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: DigitalLibrarian.primary
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                LucideIcons.chevronRight,
                size: 17,
                color: DigitalLibrarian.primary.withValues(alpha: 0.4),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DigitalLibrarian.surfaceLowest,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: DigitalLibrarian.outline.withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              item.codePreview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                height: 1.5,
                color: DigitalLibrarian.primary.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _issueChip('Errors', item.errorCount, const Color(0xFFF27E9D)),
              const SizedBox(width: 6),
              _issueChip('Warn', item.warningCount, const Color(0xFFF2B544)),
              const SizedBox(width: 6),
              _issueChip('Info', item.infoCount, DigitalLibrarian.primaryStrong),
              const Spacer(),
              Text(
                _formatDate(item.createdAt),
                style: Forge.mono(context,
                    size: 9,
                    color: DigitalLibrarian.primary.withValues(alpha: 0.4),
                    letterSpacing: 0.4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _issueChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _reviewHeadline(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
        return 'MCP verification pass';
      case 'verify_and_save':
        return 'Verified & saved source review';
      case 'analyze_code':
        return 'MCP deep analysis';
      case 'security':
        return 'Security review';
      case 'performance':
        return 'Performance review';
      case 'readability':
        return 'Readability review';
      default:
        return 'Comprehensive review';
    }
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
}
