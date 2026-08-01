import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../sources/source_provider.dart';
import '../sources/add_source_sheet.dart';
import '../../ui/widgets/source_card.dart';
import '../sources/source_detail_screen.dart';
import '../sources/edit_text_note_sheet.dart';
import 'notebook_provider.dart';
import 'notebook.dart';
import 'notebook_cover_sheet.dart';
import '../mindmap/mind_map_provider.dart';
import '../../theme/app_theme.dart';
import '../../core/extensions/color_compat.dart';
import '../subscription/services/credit_manager.dart';
import '../social/ui/share_content_sheet.dart';
import '../social/ui/content_privacy_sheet.dart';

class NotebookDetailScreen extends ConsumerWidget {
  final String notebookId;

  const NotebookDetailScreen({super.key, required this.notebookId});

  void _handleBack(BuildContext context) {
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSources = ref.watch(sourceProvider);
    final notebooks = ref.watch(notebookProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Check if notebooks are loaded
    if (notebooks.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Find the notebook
    Notebook? notebook;
    try {
      notebook = notebooks.firstWhere((n) => n.id == notebookId);
    } catch (_) {
      notebook = null;
    }

    if (notebook == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Notebook Not Found'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Notebook not found or has been deleted',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _handleBack(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    // Filter sources by notebook
    final sources =
        allSources.where((s) => s.notebookId == notebookId).toList();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Premium App Bar with gradient
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => _handleBack(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                notebook.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 4,
                      color: Colors.black45,
                    ),
                  ],
                ),
              ),
              centerTitle: true,
              background: _buildNotebookHeaderBackground(notebook),
            ),
            actions: [
              // Share button
              IconButton(
                onPressed: () => showShareContentSheet(
                  context,
                  contentType: 'notebook',
                  contentId: notebookId,
                  contentTitle: notebook!.title,
                ),
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: 'Share notebook',
              ),
              IconButton(
                onPressed: () => _showNotebookActions(context, ref, notebook),
                icon: const Icon(Icons.more_vert, color: Colors.white),
                tooltip: 'Notebook actions',
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _NotebookOverviewCard(
                    notebook: notebook,
                    sourceCount: sources.length,
                    updatedLabel: _formatNotebookRelativeDate(notebook.updatedAt),
                    onAddSource: () => _showAddSourceSheet(context),
                  ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.08),
                  const SizedBox(height: 24),
                  Text(
                    'Notebook workspace',
                    style: text.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Start with chat or research, then turn this notebook into study tools and visual outputs.',
                    style: text.bodyMedium?.copyWith(
                      color: scheme.secondaryText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 760;
                      final secondaryColumns = constraints.maxWidth >= 980 ? 3 : 2;
                      const spacing = 12.0;
                      final tileWidth =
                          (constraints.maxWidth - (spacing * (secondaryColumns - 1))) /
                              secondaryColumns;

                      final secondaryTiles = [
                        SizedBox(
                          width: tileWidth,
                          child: _NotebookFeatureTile(
                            icon: Icons.mic_none_rounded,
                            title: 'Studio',
                            subtitle: 'Audio, podcast, and voice workflows',
                            color: const Color(0xFFEC4899),
                            onTap: () =>
                                context.push('/notebook/$notebookId/studio'),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _NotebookFeatureTile(
                            icon: Icons.style_outlined,
                            title: 'Flashcards',
                            subtitle: 'Turn sources into study cards',
                            color: Colors.orange,
                            onTap: () =>
                                context.push('/notebook/$notebookId/flashcards'),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _NotebookFeatureTile(
                            icon: Icons.quiz_outlined,
                            title: 'Quizzes',
                            subtitle: 'Check what you actually retained',
                            color: Colors.teal,
                            onTap: () =>
                                context.push('/notebook/$notebookId/quizzes'),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _NotebookFeatureTile(
                            icon: Icons.school_outlined,
                            title: 'Tutor',
                            subtitle: 'Practice with guided explanations',
                            color: const Color(0xFF10B981),
                            onTap: () => context
                                .push('/notebook/$notebookId/tutor-sessions'),
                          ),
                        ),
                        SizedBox(
                          width: tileWidth,
                          child: _NotebookFeatureTile(
                            icon: Icons.account_tree_outlined,
                            title: 'Mind maps',
                            subtitle: 'Visualize structure and relationships',
                            color: Colors.amber.shade700,
                            onTap: () => _showMindMapsSheet(context),
                          ),
                        ),
                      ];

                      return Column(
                        children: [
                          if (isWide)
                            Row(
                              children: [
                                Expanded(
                                  child: _NotebookPrimaryActionCard(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    title: 'Chat with this notebook',
                                    subtitle:
                                        'Ask grounded questions across all attached sources.',
                                    accent: const Color(0xFF8B5CF6),
                                    onTap: () =>
                                        context.push('/notebook/$notebookId/chat'),
                                  ),
                                ),
                                const SizedBox(width: spacing),
                                Expanded(
                                  child: _NotebookPrimaryActionCard(
                                    icon: Icons.travel_explore_rounded,
                                    title: 'Research deeper',
                                    subtitle:
                                        'Run broader analysis and source-aware exploration.',
                                    accent: const Color(0xFF0EA5E9),
                                    onTap: () => context
                                        .push('/notebook/$notebookId/research'),
                                  ),
                                ),
                              ],
                            )
                          else ...[
                            _NotebookPrimaryActionCard(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'Chat with this notebook',
                              subtitle:
                                  'Ask grounded questions across all attached sources.',
                              accent: const Color(0xFF8B5CF6),
                              onTap: () =>
                                  context.push('/notebook/$notebookId/chat'),
                            ),
                            const SizedBox(height: spacing),
                            _NotebookPrimaryActionCard(
                              icon: Icons.travel_explore_rounded,
                              title: 'Research deeper',
                              subtitle:
                                  'Run broader analysis and source-aware exploration.',
                              accent: const Color(0xFF0EA5E9),
                              onTap: () =>
                                  context.push('/notebook/$notebookId/research'),
                            ),
                          ],
                          const SizedBox(height: spacing),
                          Wrap(
                            spacing: spacing,
                            runSpacing: spacing,
                            children: secondaryTiles,
                          ),
                        ],
                      );
                    },
                  ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.06),
                ],
              ),
            ),
          ),

          // Sources Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notebook sources',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${sources.length} item${sources.length == 1 ? '' : 's'} attached to this notebook',
                        style: text.bodySmall?.copyWith(
                          color: scheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddSourceSheet(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add source'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Sources List
          sources.isEmpty
              ? SliverFillRemaining(
                  hasScrollBody: false,
                  child: _buildEmptyState(context, scheme, text),
                )
              : SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final source = sources[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildSourceItem(context, ref, source, index),
                        );
                      },
                      childCount: sources.length,
                    ),
                  ),
                ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }

  Widget _buildNotebookHeaderBackground(
    Notebook notebook,
  ) {
    final coverImage = notebook.coverImage?.trim();

    if (coverImage == null || coverImage.isEmpty) {
      return _buildNotebookHeaderFallback();
    }

    final imageWidget = _buildNotebookCoverImage(coverImage);
    if (imageWidget == null) {
      return _buildNotebookHeaderFallback();
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        imageWidget,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.10),
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotebookHeaderFallback() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        Positioned(
          top: -60,
          right: -20,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
        ),
        Positioned(
          bottom: -40,
          left: 20,
          child: Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildNotebookCoverImage(String coverImage) {
    if (coverImage.startsWith('data:image/svg+xml')) {
      return _buildNotebookHeaderFallback();
    }

    final decodedBytes = _decodeCoverImageBytes(coverImage);
    if (decodedBytes != null) {
      return Image.memory(
        decodedBytes,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildNotebookHeaderFallback(),
      );
    }

    if (coverImage.startsWith('http://') || coverImage.startsWith('https://')) {
      return Image.network(
        coverImage,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildNotebookHeaderFallback(),
      );
    }

    return null;
  }

  Uint8List? _decodeCoverImageBytes(String coverImage) {
    try {
      final payload = coverImage.startsWith('data:')
          ? coverImage.split(',').last
          : coverImage;
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  Widget _buildEmptyState(
      BuildContext context, ColorScheme scheme, TextTheme text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Image.asset(
                'assets/images/empty_sources.png',
                height: 120,
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            ),
            const SizedBox(height: 24),
            Text(
              'No sources yet',
              style: text.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 12),
            Text(
              'Add sources to this notebook to get started.\nSupports YouTube, Google Drive, web URLs, and more!',
              style: text.bodyMedium?.copyWith(
                color: scheme.secondaryText,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms),
          ],
        ),
      ),
    );
  }

  /// Build a source item - either a GitHubSourceCard or regular SourceCard
  /// Requirements: 4.1 - Display GitHub sources alongside other source types
  Widget _buildSourceItem(
      BuildContext context, WidgetRef ref, source, int index) {
    // Check if this is a GitHub source
    final isGitHubSource = source.type == 'github';

    if (isGitHubSource) {
      // Convert to GitHubSource and use GitHubSourceCard
      return _buildGitHubSourceCard(context, ref, source, index);
    }

    // Regular source card
    return SourceCard(
      source: source,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceDetailScreen(sourceId: source.id),
          ),
        );
      },
      onEdit:
          source.type == 'text' ? () => _showEditSheet(context, source) : null,
      onDelete: () => _confirmDelete(context, ref, source),
    ).animate().fadeIn(
          delay: Duration(milliseconds: index * 50),
        );
  }

  /// Build a GitHub source card - uses regular SourceCard for consistency
  /// Requirements: 4.1 - Display GitHub sources alongside other source types
  Widget _buildGitHubSourceCard(
      BuildContext context, WidgetRef ref, source, int index) {
    // For GitHub sources, just use the regular SourceCard which handles all source types
    // This avoids the complexity of loading GitHubSource separately
    return SourceCard(
      source: source,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceDetailScreen(sourceId: source.id),
          ),
        );
      },
      onEdit: null, // GitHub sources are not editable inline
      onDelete: () => _confirmDelete(context, ref, source),
    ).animate().fadeIn(
          delay: Duration(milliseconds: index * 50),
        );
  }

  void _showAddSourceSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: AddSourceSheet(notebookId: notebookId),
      ),
    );
  }

  void _showEditSheet(BuildContext context, source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: EditTextNoteSheet(source: source),
      ),
    );
  }

  void _showNotebookActions(BuildContext context, WidgetRef ref, notebook) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.share),
              title: const Text('Share Notebook'),
              subtitle: const Text('Post to discover feed'),
              onTap: () {
                Navigator.pop(context);
                showShareContentSheet(
                  context,
                  contentType: 'notebook',
                  contentId: notebookId,
                  contentTitle: notebook.title,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Privacy Settings'),
              subtitle: Text(notebook.isPublic ? 'Public' : 'Private'),
              onTap: () {
                Navigator.pop(context);
                showContentPrivacySheet(
                  context,
                  contentType: 'notebook',
                  contentId: notebookId,
                  contentTitle: notebook.title,
                  isPublic: notebook.isPublic,
                  isLocked: notebook.isLocked,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.visibility),
              title: const Text('View Stats'),
              subtitle: Text(
                  '${notebook.viewCount} views • ${notebook.shareCount} shares'),
              onTap: () => Navigator.pop(context),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Change Cover'),
              subtitle: const Text('Upload or generate with AI'),
              onTap: () {
                Navigator.pop(context);
                showNotebookCoverSheet(context, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename Notebook'),
              onTap: () {
                Navigator.pop(context);
                _showRenameDialog(context, ref, notebook);
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Export Sources'),
              onTap: () {
                Navigator.pop(context);
                _exportNotebook(context, ref, notebook);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Delete Notebook',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteNotebook(context, ref, notebook);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, source) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Source'),
        content: Text('Are you sure you want to delete "${source.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(sourceProvider.notifier).deleteSource(source.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Source deleted'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, notebook) {
    final controller = TextEditingController(text: notebook.title);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Notebook'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Notebook name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(context);
              _renameNotebook(context, ref, notebook.id, value.trim());
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(context);
                _renameNotebook(context, ref, notebook.id, newName);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _renameNotebook(BuildContext context, WidgetRef ref, String notebookId,
      String newTitle) async {
    try {
      await ref.read(notebookProvider.notifier).updateNotebook(
            notebookId,
            newTitle,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Renamed to "$newTitle"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to rename: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _exportNotebook(BuildContext context, WidgetRef ref, notebook) async {
    final sources = ref.read(sourceProvider);

    // Show export format dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Notebook'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Export "${notebook.title}" with ${sources.length} sources'),
            const SizedBox(height: 16),
            const Text('Choose format:'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportAsMarkdown(context, notebook, sources);
            },
            icon: const Icon(Icons.description),
            label: const Text('Markdown'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportAsJSON(context, notebook, sources);
            },
            icon: const Icon(Icons.code),
            label: const Text('JSON'),
          ),
        ],
      ),
    );
  }

  void _exportAsMarkdown(BuildContext context, notebook, List sources) async {
    final buffer = StringBuffer();

    buffer.writeln('# ${notebook.title}');
    buffer.writeln();
    buffer.writeln('Exported on ${DateTime.now().toString()}');
    buffer.writeln();
    buffer.writeln('## Sources (${sources.length})');
    buffer.writeln();

    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      buffer.writeln('### ${i + 1}. ${source.title}');
      buffer.writeln();
      buffer.writeln('**Type:** ${source.type}');
      buffer.writeln('**Added:** ${source.addedAt}');
      buffer.writeln();
      buffer.writeln('**Content:**');
      buffer.writeln();
      buffer.writeln(source.content);
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    // Use share_plus to share the markdown
    await Share.share(
      buffer.toString(),
      subject: '${notebook.title} - Notebook Export',
    );
  }

  void _exportAsJSON(BuildContext context, notebook, List sources) async {
    final data = {
      'notebook': {
        'id': notebook.id,
        'title': notebook.title,
        'created_at': notebook.createdAt.toIso8601String(),
        'source_count': sources.length,
      },
      'sources': sources
          .map((s) => {
                'id': s.id,
                'title': s.title,
                'type': s.type,
                'content': s.content,
                'added_at': s.addedAt.toIso8601String(),
                'tag_ids': s.tagIds,
              })
          .toList(),
      'exported_at': DateTime.now().toIso8601String(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);

    await Share.share(
      jsonString,
      subject: '${notebook.title} - Notebook Export (JSON)',
    );
  }

  void _confirmDeleteNotebook(BuildContext context, WidgetRef ref, notebook) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Notebook'),
        content: Text(
            'Are you sure you want to delete "${notebook.title}"? This will also delete all sources in this notebook.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref
                  .read(notebookProvider.notifier)
                  .deleteNotebook(notebook.id);
              if (context.mounted) {
                context.go('/home');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Notebook deleted'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showMindMapsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _MindMapsSheet(notebookId: notebookId),
    );
  }
}

class _NotebookOverviewCard extends StatelessWidget {
  const _NotebookOverviewCard({
    required this.notebook,
    required this.sourceCount,
    required this.updatedLabel,
    required this.onAddSource,
  });

  final Notebook notebook;
  final int sourceCount;
  final String updatedLabel;
  final VoidCallback onAddSource;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final description = notebook.description.trim().isNotEmpty
        ? notebook.description.trim()
        : sourceCount == 0
            ? 'Add your first source to unlock grounded chat, research, and study workflows.'
            : 'This notebook is ready for grounded answers, source-aware research, and learning tools.';
    final notebookType = notebook.isAgentNotebook
        ? (notebook.agentName?.trim().isNotEmpty == true
            ? notebook.agentName!.trim()
            : 'Agent')
        : 'Personal';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
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
                      'Notebook hub',
                      style: text.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      description,
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              FilledButton.icon(
                onPressed: onAddSource,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add source'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _NotebookMetaChip(
                icon: Icons.folder_open_rounded,
                label: notebook.category,
                color: scheme.primary,
              ),
              _NotebookMetaChip(
                icon: sourceCount == 0
                    ? Icons.info_outline_rounded
                    : Icons.auto_awesome_rounded,
                label: sourceCount == 0 ? 'Needs sources' : 'AI ready',
                color: sourceCount == 0 ? scheme.secondary : scheme.tertiary,
              ),
              _NotebookMetaChip(
                icon:
                    notebook.isPublic ? Icons.public_rounded : Icons.lock_outline,
                label: notebook.isPublic ? 'Public' : 'Private',
                color: notebook.isPublic ? scheme.secondary : scheme.outline,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _NotebookOverviewStat(
                  icon: Icons.source_outlined,
                  label: 'Sources',
                  value: '$sourceCount',
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NotebookOverviewStat(
                  icon: Icons.schedule_rounded,
                  label: 'Updated',
                  value: updatedLabel,
                  color: scheme.secondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _NotebookOverviewStat(
                  icon: notebook.isAgentNotebook
                      ? Icons.hub_outlined
                      : Icons.person_outline_rounded,
                  label: 'Type',
                  value: notebookType,
                  color: scheme.tertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatNotebookRelativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays > 30) {
    return '${(diff.inDays / 30).floor()}mo';
  }
  if (diff.inDays > 0) {
    return '${diff.inDays}d';
  }
  return 'Today';
}

class _NotebookMetaChip extends StatelessWidget {
  const _NotebookMetaChip({
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _NotebookOverviewStat extends StatelessWidget {
  const _NotebookOverviewStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.secondaryText,
                ),
          ),
        ],
      ),
    );
  }
}

class _NotebookPrimaryActionCard extends StatelessWidget {
  const _NotebookPrimaryActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 170,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                accent.withValues(alpha: 0.14),
                scheme.surface,
              ],
            ),
            border: Border.all(
              color: accent.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.10),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: accent, size: 22),
              ),
              const Spacer(),
              Text(
                title,
                style: text.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Open',
                    style: text.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_forward_rounded, color: accent, size: 20),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotebookFeatureTile extends StatelessWidget {
  const _NotebookFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 132,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const Spacer(),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: scheme.secondaryText,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _mindMapStyleOptions = [
  _MindMapStyleOption(
    id: 'balanced',
    label: 'Balanced',
    description: 'Good overall structure with concepts, examples, and links.',
  ),
  _MindMapStyleOption(
    id: 'relationships',
    label: 'Relationships',
    description: 'Highlights dependencies, comparisons, and connections.',
  ),
  _MindMapStyleOption(
    id: 'process',
    label: 'Process',
    description: 'Organizes steps, flows, and sequences clearly.',
  ),
  _MindMapStyleOption(
    id: 'study',
    label: 'Study',
    description: 'Optimized for definitions, categories, and memorization.',
  ),
];

class _MindMapStyleOption {
  const _MindMapStyleOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

_MindMapStyleOption _mindMapStyleById(String id) {
  return _mindMapStyleOptions.firstWhere(
    (option) => option.id == id,
    orElse: () => _mindMapStyleOptions.first,
  );
}

/// Sheet for viewing and generating mind maps
class _MindMapsSheet extends ConsumerStatefulWidget {
  final String notebookId;

  const _MindMapsSheet({required this.notebookId});

  @override
  ConsumerState<_MindMapsSheet> createState() => _MindMapsSheetState();
}

class _MindMapsSheetState extends ConsumerState<_MindMapsSheet> {
  bool _isGenerating = false;
  final _titleController = TextEditingController(text: 'Mind Map');
  final _focusController = TextEditingController();
  String? _selectedSourceId;
  String _mapStyle = _mindMapStyleOptions.first.id;

  @override
  void dispose() {
    _titleController.dispose();
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mindMaps = ref.watch(mindMapProvider);
    final allSources = ref.watch(sourceProvider);
    final notebookSources =
        allSources.where((s) => s.notebookId == widget.notebookId).toList();
    final notebookMindMaps =
        mindMaps.where((mm) => mm.notebookId == widget.notebookId).toList();
    final selectedStyle = _mindMapStyleById(_mapStyle);

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: keyboardInset),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: scheme.onSurface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 8),
                        child: Row(
                          children: [
                            const Icon(Icons.account_tree, color: Colors.teal),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Mind Maps', style: text.titleLarge),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                      ),
                      const Divider(),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: 'Title',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSourceId ?? '__all__',
                              decoration: InputDecoration(
                                labelText: 'Source Scope',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '__all__',
                                  child: Text('All notebook sources'),
                                ),
                                ...notebookSources.map(
                                  (source) => DropdownMenuItem(
                                    value: source.id,
                                    child: Text(
                                      source.title,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _selectedSourceId =
                                      value == '__all__' ? null : value;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            Text('Map Style', style: text.labelMedium),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _mindMapStyleOptions.map((option) {
                                return ChoiceChip(
                                  label: Text(option.label),
                                  selected: option.id == _mapStyle,
                                  onSelected: (_) {
                                    setState(() => _mapStyle = option.id);
                                  },
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerHighest
                                    .withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                selectedStyle.description,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.secondaryText,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _focusController,
                              decoration: InputDecoration(
                                labelText: 'Focus Area',
                                hintText:
                                    'Optional: e.g. causes, timeline, architecture',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    _isGenerating ? null : _generateMindMap,
                                icon: _isGenerating
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.auto_awesome),
                                label: Text(
                                  _isGenerating ? 'Generating...' : 'Generate',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (notebookMindMaps.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.account_tree_outlined,
                            size: 64,
                            color: scheme.onSurface.withValues(alpha: 0.3),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No mind maps yet',
                            style: text.titleMedium?.copyWith(
                              color: scheme.secondaryText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Generate one from your sources!',
                            style: text.bodySmall?.copyWith(
                              color: scheme.hintText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final mm = notebookMindMaps[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.account_tree,
                                  color: Colors.teal,
                                ),
                              ),
                              title: Text(mm.title),
                              subtitle: Text(
                                'Created ${_formatDate(mm.createdAt)}',
                                style: text.bodySmall,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () {
                                Navigator.pop(context);
                                context.push('/mindmap/${mm.id}');
                              },
                            ),
                          );
                        },
                        childCount: notebookMindMaps.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generateMindMap() async {
    if (_titleController.text.trim().isEmpty) return;

    // Check and consume credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.generateMindMap,
      feature: 'generate_mindmap',
    );
    if (!hasCredits) return;

    setState(() => _isGenerating = true);
    try {
      final mindMap =
          await ref.read(mindMapProvider.notifier).generateFromSources(
                notebookId: widget.notebookId,
                title: _titleController.text.trim(),
                sourceId: _selectedSourceId,
                focusTopic: _focusController.text.trim(),
                mapStyle: _mapStyle,
              );

      if (!mounted) return;
      Navigator.pop(context);
      context.push('/mindmap/${mindMap.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'Just now';
  }
}
