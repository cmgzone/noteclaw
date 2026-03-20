import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import '../models/ebook_project.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/ebook_export_service.dart';
import '../services/ebook_narration_service.dart';
import 'ebook_editor_screen.dart';
import '../../../core/extensions/color_compat.dart';
import '../../../core/utils/public_share_link.dart';
import '../../../ui/widgets/app_network_image.dart';
import '../../mindmap/mind_map_provider.dart';
import '../../notebook/notebook.dart';
import '../../notebook/notebook_provider.dart';
import '../../social/social_sharing_provider.dart';
import '../../subscription/services/credit_manager.dart';

class EbookReaderScreen extends ConsumerWidget {
  const EbookReaderScreen({super.key, required this.project});
  final EbookProject project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = project.branding;
    final primaryColor = Color(branding.primaryColorValue);

    return Scaffold(
      floatingActionButton:
          _NarrationFab(project: project, primaryColor: primaryColor),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(project.title),
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            expandedHeight: 300,
            actions: [
              IconButton(
                icon: const Icon(Icons.account_tree_outlined),
                onPressed: () async {
                  final mindMapId = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => _EbookMindMapSheet(project: project),
                  );

                  if (mindMapId != null && context.mounted) {
                    context.push('/mindmap/$mindMapId');
                  }
                },
                tooltip: 'Create Mind Map',
              ),
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EbookEditorScreen(project: project),
                    ),
                  );
                },
                tooltip: 'Edit Ebook',
              ),
              IconButton(
                icon: const Icon(Icons.public),
                onPressed: () => _sharePublicEbook(context, ref),
                tooltip: 'Share Public Ebook',
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: () => _exportPdf(context, ref),
                tooltip: 'Export PDF',
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: project.coverImageUrl != null
                  ? AppNetworkImage(
                      imageUrl: project.coverImageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (context) =>
                          Container(color: primaryColor),
                    )
                  : Container(color: primaryColor),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = project.chapters[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chapter ${index + 1}',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        chapter.title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 24),
                      if (chapter.images.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AppNetworkImage(
                            imageUrl: chapter.images.first.url,
                            height: 200,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (context) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      MarkdownBody(
                        data: chapter.content,
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(Theme.of(context))
                                .copyWith(
                          p: TextStyle(
                            fontSize: 16,
                            height: 1.6,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          h1: TextStyle(color: primaryColor),
                          h2: TextStyle(color: primaryColor),
                          h3: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          strong: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                          em: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontStyle: FontStyle.italic,
                          ),
                          listBullet: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const Divider(height: 64),
                    ],
                  );
                },
                childCount: project.chapters.length,
              ),
            ),
          ),
          // Sources Section
          if (project.notebookId != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sources',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 16),
                    const Text(
                        'This ebook was grounded in your personal notebook sources.'),
                  ],
                ),
              ),
            ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 80)),
        ],
      ),
    );
  }

  Future<void> _sharePublicEbook(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(socialSharingServiceProvider).shareContent(
            contentType: 'ebook',
            contentId: project.id,
          );
      final publicUrl = buildPublicShareLink('/social/ebook/${project.id}');
      await Share.share(
        'Ebook: ${project.title}\n$publicUrl',
        subject: project.title,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Public ebook link ready to share.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share ebook: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
    try {
      final pdfBytes =
          await ref.read(ebookExportServiceProvider).exportToPdf(project);
      final tempDir = await getTemporaryDirectory();
      final file =
          File('${tempDir.path}/${project.title.replaceAll(' ', '_')}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Check out my ebook: ${project.title}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}

const _ebookMindMapStyleOptions = [
  _EbookMindMapStyleOption(
    id: 'balanced',
    label: 'Balanced',
    description: 'Good overall structure with concepts, examples, and links.',
  ),
  _EbookMindMapStyleOption(
    id: 'relationships',
    label: 'Relationships',
    description: 'Highlights dependencies, comparisons, and connections.',
  ),
  _EbookMindMapStyleOption(
    id: 'process',
    label: 'Process',
    description: 'Organizes steps, flows, and sequences clearly.',
  ),
  _EbookMindMapStyleOption(
    id: 'study',
    label: 'Study',
    description: 'Optimized for definitions, categories, and memorization.',
  ),
];

class _EbookMindMapStyleOption {
  const _EbookMindMapStyleOption({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;
}

_EbookMindMapStyleOption _ebookMindMapStyleById(String id) {
  return _ebookMindMapStyleOptions.firstWhere(
    (option) => option.id == id,
    orElse: () => _ebookMindMapStyleOptions.first,
  );
}

class _EbookMindMapSheet extends ConsumerStatefulWidget {
  const _EbookMindMapSheet({required this.project});

  final EbookProject project;

  @override
  ConsumerState<_EbookMindMapSheet> createState() => _EbookMindMapSheetState();
}

class _EbookMindMapSheetState extends ConsumerState<_EbookMindMapSheet> {
  late final TextEditingController _titleController;
  final TextEditingController _focusController = TextEditingController();
  bool _isGenerating = false;
  String? _selectedNotebookId;
  String _mapStyle = _ebookMindMapStyleOptions.first.id;

  @override
  void initState() {
    super.initState();
    _selectedNotebookId = widget.project.notebookId;
    _titleController =
        TextEditingController(text: '${widget.project.title} Mind Map');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _focusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notebooks = ref.watch(notebookProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final selectedStyle = _ebookMindMapStyleById(_mapStyle);
    final effectiveNotebookId = _resolveNotebookId(notebooks);
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Icon(Icons.account_tree_outlined, color: Colors.teal),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Create Mind Map From Ebook',
                        style: text.titleLarge?.copyWith(
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
                const SizedBox(height: 8),
                Text(
                  'We will analyze this ebook\'s chapters and turn them into a visual mind map.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.secondaryText,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _titleController,
                  decoration: InputDecoration(
                    labelText: 'Mind Map Title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (notebooks.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(effectiveNotebookId ?? 'ebook-mindmap-notebook'),
                    initialValue: effectiveNotebookId,
                    decoration: InputDecoration(
                      labelText: 'Save To Notebook',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: notebooks
                        .map(
                          (notebook) => DropdownMenuItem(
                            value: notebook.id,
                            child: Text(
                              notebook.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _selectedNotebookId = value);
                    },
                  )
                else if (widget.project.notebookId != null &&
                    widget.project.notebookId!.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:
                          scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'This ebook already has a linked notebook, so the mind map will be saved there.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.secondaryText,
                      ),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Create a notebook first so we have somewhere to save the mind map.',
                      style: text.bodySmall?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text('Map Style', style: text.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _ebookMindMapStyleOptions.map((option) {
                    return ChoiceChip(
                      label: Text(option.label),
                      selected: option.id == _mapStyle,
                      onSelected: (_) => setState(() => _mapStyle = option.id),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
                    hintText: 'Optional: e.g. main arguments, workflow, themes',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This will use ${widget.project.chapters.length} chapters',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Credit cost: ${CreditCosts.generateMindMap}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isGenerating || effectiveNotebookId == null
                        ? null
                        : () => _generateMindMap(
                              notebookId: effectiveNotebookId!,
                            ),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(
                      _isGenerating ? 'Generating...' : 'Create Mind Map',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _resolveNotebookId(List<Notebook> notebooks) {
    final notebookIds = notebooks.map((notebook) => notebook.id).toSet();

    if (_selectedNotebookId != null && _selectedNotebookId!.isNotEmpty) {
      if (notebookIds.isEmpty || notebookIds.contains(_selectedNotebookId)) {
        return _selectedNotebookId;
      }
    }
    if (widget.project.notebookId != null &&
        widget.project.notebookId!.isNotEmpty) {
      if (notebookIds.isEmpty ||
          notebookIds.contains(widget.project.notebookId)) {
        return widget.project.notebookId;
      }
    }
    if (notebooks.isNotEmpty) {
      return notebooks.first.id;
    }
    return null;
  }

  Future<void> _generateMindMap({required String notebookId}) async {
    final title = _titleController.text.trim();
    if (title.isEmpty) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.generateMindMap,
      feature: 'generate_mindmap',
      metadata: {
        'ebookId': widget.project.id,
        'ebookTitle': widget.project.title,
      },
    );
    if (!hasCredits) return;

    setState(() => _isGenerating = true);
    try {
      final content = _buildEbookContent(widget.project);
      final mindMap =
          await ref.read(mindMapProvider.notifier).generateFromContent(
                notebookId: notebookId,
                title: title,
                content: content,
                focusTopic: _focusController.text.trim(),
                mapStyle: _mapStyle,
              );

      if (!mounted) return;
      Navigator.pop(context, mindMap.id);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate mind map: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _buildEbookContent(EbookProject project) {
    final buffer = StringBuffer()
      ..writeln('Ebook Title: ${project.title}')
      ..writeln('Topic: ${project.topic}')
      ..writeln('Audience: ${project.targetAudience}')
      ..writeln();

    for (var i = 0; i < project.chapters.length; i++) {
      final chapter = project.chapters[i];
      buffer.writeln('## Chapter ${i + 1}: ${chapter.title}');
      buffer.writeln(_truncateChapterContent(chapter.content));
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  String _truncateChapterContent(String content) {
    final cleaned = content.trim();
    if (cleaned.length <= 3500) return cleaned;
    return '${cleaned.substring(0, 3500)}...';
  }
}

class _NarrationFab extends ConsumerWidget {
  final EbookProject project;
  final Color primaryColor;

  const _NarrationFab({
    required this.project,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final narrationStatus = ref.watch(ebookNarrationProvider);
    final isPlaying = narrationStatus.state == NarrationState.playing;
    final isPaused = narrationStatus.state == NarrationState.paused;

    if (isPlaying || isPaused) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current chapter indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Text(
              'Ch. ${narrationStatus.currentChapterIndex + 1}/${project.chapters.length}',
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Previous chapter
              FloatingActionButton.small(
                heroTag: 'prev',
                onPressed: narrationStatus.currentChapterIndex > 0
                    ? () => ref
                        .read(ebookNarrationProvider.notifier)
                        .skipToChapter(narrationStatus.currentChapterIndex - 1)
                    : null,
                backgroundColor: primaryColor.withValues(alpha: 0.8),
                child: const Icon(Icons.skip_previous, color: Colors.white),
              ),
              const SizedBox(width: 8),
              // Play/Pause
              FloatingActionButton.extended(
                heroTag: 'play',
                onPressed: () {
                  if (isPlaying) {
                    ref.read(ebookNarrationProvider.notifier).pause();
                  } else {
                    ref.read(ebookNarrationProvider.notifier).resume();
                  }
                },
                backgroundColor: primaryColor,
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                label: Text(
                  isPlaying ? 'Pause' : 'Resume',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              // Next chapter
              FloatingActionButton.small(
                heroTag: 'next',
                onPressed: narrationStatus.currentChapterIndex <
                        project.chapters.length - 1
                    ? () => ref
                        .read(ebookNarrationProvider.notifier)
                        .skipToChapter(narrationStatus.currentChapterIndex + 1)
                    : null,
                backgroundColor: primaryColor.withValues(alpha: 0.8),
                child: const Icon(Icons.skip_next, color: Colors.white),
              ),
              const SizedBox(width: 8),
              // Stop
              FloatingActionButton.small(
                heroTag: 'stop',
                onPressed: () =>
                    ref.read(ebookNarrationProvider.notifier).stop(),
                backgroundColor: Colors.red,
                child: const Icon(Icons.stop, color: Colors.white),
              ),
            ],
          ),
        ],
      );
    }

    // Default state - start narration
    return FloatingActionButton.extended(
      onPressed: () => _showNarrationDialog(context, ref),
      icon: const Icon(Icons.headphones),
      label: const Text('Narrate'),
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
    );
  }

  void _showNarrationDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Start Audiobook',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose where to start narration',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondaryText,
                  ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.play_arrow, color: primaryColor),
              title: const Text('From Beginning'),
              onTap: () {
                Navigator.pop(ctx);
                ref
                    .read(ebookNarrationProvider.notifier)
                    .startNarration(project);
              },
            ),
            const Divider(),
            Text(
              'Or select a chapter:',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                itemCount: project.chapters.length,
                itemBuilder: (context, index) {
                  final chapter = project.chapters[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: primaryColor.withValues(alpha: 0.1),
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(color: primaryColor),
                      ),
                    ),
                    title: Text(
                      chapter.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(ebookNarrationProvider.notifier)
                          .startNarration(project, startChapter: index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
