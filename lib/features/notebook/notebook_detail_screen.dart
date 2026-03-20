import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
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
              background: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      gradient: AppTheme.premiumGradient,
                    ),
                  ),
                  // Abstract shapes
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
              ),
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

          // Quick Actions (Horizontal Stories Style)
          SliverToBoxAdapter(
            child: Container(
              height: 110,
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _QuickActionItem(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => context.push('/notebook/$notebookId/chat'),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.search,
                    label: 'Research',
                    color: const Color(0xFF0EA5E9),
                    onTap: () => context.push('/notebook/$notebookId/research'),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.mic,
                    label: 'Audio',
                    color: const Color(0xFFEC4899),
                    onTap: () => context.push('/notebook/$notebookId/studio'),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.style_outlined,
                    label: 'Flashcards',
                    color: Colors.orange,
                    onTap: () =>
                        context.push('/notebook/$notebookId/flashcards'),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.quiz_outlined,
                    label: 'Quizzes',
                    color: Colors.teal,
                    onTap: () => context.push('/notebook/$notebookId/quizzes'),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.account_tree_outlined,
                    label: 'Mind Map',
                    color: Colors.amber,
                    onTap: () => _showMindMapsSheet(context),
                  ),
                  const SizedBox(width: 16),
                  _QuickActionItem(
                    icon: Icons.school_outlined,
                    label: 'Tutor',
                    color: const Color(0xFF10B981), // Green
                    onTap: () =>
                        context.push('/notebook/$notebookId/tutor-sessions'),
                  ),
                ],
              ),
            ),
          ),

          // Stats Dashboard
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      icon: Icons.source,
                      label: 'Sources',
                      value: '${sources.length}',
                      color: scheme.primary,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: scheme.outline.withValues(alpha: 0.1),
                    ),
                    _StatItem(
                      icon: Icons.schedule,
                      label: 'Created',
                      value: _formatDate(notebook.createdAt),
                      color: scheme.secondary,
                    ),
                    Container(
                      width: 1,
                      height: 40,
                      color: scheme.outline.withValues(alpha: 0.1),
                    ),
                    _StatItem(
                      icon: Icons.auto_awesome,
                      label: 'AI Ready',
                      value: sources.isEmpty ? 'No' : 'Yes',
                      color: scheme.tertiary,
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1),
            ),
          ),

          // Sources Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 32, 20, 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Sources (${sources.length})',
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _showAddSourceSheet(context),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSourceSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Source'),
      ),
    );
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

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d';
    } else {
      return 'Today';
    }
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

class _QuickActionItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ).animate().scale(duration: 400.ms, curve: Curves.easeOutBack);
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
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
