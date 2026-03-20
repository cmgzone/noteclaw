import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';

import 'add_source_sheet.dart';
import 'source_provider.dart';
import 'source_detail_screen.dart';
import 'source.dart';
import '../../core/ai/ai_provider.dart';
import '../notebook/notebook_provider.dart';
import '../../theme/motion.dart';
import '../../core/media/media_service.dart';
import '../../core/api/api_service.dart';

class EnhancedSourcesScreen extends ConsumerStatefulWidget {
  const EnhancedSourcesScreen({super.key});

  @override
  ConsumerState<EnhancedSourcesScreen> createState() =>
      _EnhancedSourcesScreenState();
}

class _EnhancedSourcesScreenState extends ConsumerState<EnhancedSourcesScreen> {
  bool _showAIResearch = false;
  String _researchQuery = '';
  bool _isSelectionMode = false;
  final Set<String> _selectedSourceIds = <String>{};

  void _enterSelectionMode(String sourceId) {
    setState(() {
      _isSelectionMode = true;
      _selectedSourceIds.add(sourceId);
    });
  }

  void _toggleSelection(String sourceId) {
    setState(() {
      if (_selectedSourceIds.contains(sourceId)) {
        _selectedSourceIds.remove(sourceId);
        if (_selectedSourceIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedSourceIds.add(sourceId);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedSourceIds.clear();
    });
  }

  void _toggleSelectAll(List<Source> sources) {
    setState(() {
      if (_selectedSourceIds.length == sources.length) {
        _selectedSourceIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedSourceIds
          ..clear()
          ..addAll(sources.map((source) => source.id));
        _isSelectionMode = sources.isNotEmpty;
      }
    });
  }

  Future<void> _deleteSelectedSources() async {
    final count = _selectedSourceIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete $count sources?'),
        content: const Text(
          'This action cannot be undone. All selected sources will be permanently removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final deletedCount = await ref
        .read(sourceProvider.notifier)
        .deleteSources(_selectedSourceIds.toList());

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deletedCount == count
              ? '$deletedCount sources deleted'
              : 'Deleted $deletedCount of $count selected sources',
        ),
        backgroundColor:
            deletedCount > 0 ? Colors.green : Theme.of(context).colorScheme.error,
      ),
    );

    _exitSelectionMode();
  }

  void _showExportDialog() {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Icon(Icons.download_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            const Text('Export Notebook'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose export format:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _ExportOptionTile(
              icon: Icons.picture_as_pdf,
              title: 'PDF Document',
              subtitle: 'Professional document format',
              color: Colors.red,
              onTap: () => _exportAsPDF(),
            ),
            const SizedBox(height: 8),
            _ExportOptionTile(
              icon: Icons.code,
              title: 'Markdown File',
              subtitle: 'Plain text with formatting',
              color: Colors.blue,
              onTap: () => _exportAsMarkdown(),
            ),
            const SizedBox(height: 8),
            _ExportOptionTile(
              icon: Icons.text_fields,
              title: 'Plain Text',
              subtitle: 'Simple text format',
              color: Colors.green,
              onTap: () => _exportAsText(),
            ),
            const SizedBox(height: 8),
            _ExportOptionTile(
              icon: Icons.data_object,
              title: 'JSON Data',
              subtitle: 'Structured data format',
              color: Colors.purple,
              onTap: () => _exportAsJSON(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _buildNotebookPdf(
    String title,
    List<Source> sources,
  ) async {
    final pdf = pw.Document();
    final generatedOn = DateTime.now().toLocal();

    pdf.addPage(
      pw.MultiPage(
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text('Generated: ${generatedOn.toString().split(' ')[0]}'),
          pw.SizedBox(height: 8),
          pw.Text('Sources: ${sources.length}'),
          pw.SizedBox(height: 16),
          for (var i = 0; i < sources.length; i++)
            _buildPdfSourceSection(i, sources[i]),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildPdfSourceSection(int index, Source source) {
    final addedOn = source.addedAt.toLocal().toString().split(' ')[0];
    final contentPreview = source.content.length > 1200
        ? '${source.content.substring(0, 1200)}...'
        : source.content;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          '${index + 1}. ${source.title}',
          style: pw.TextStyle(
            fontSize: 16,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Type: ${source.type}'),
        pw.Text('Added: $addedOn'),
        if (source.summary != null && source.summary!.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Summary:',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          pw.Paragraph(text: source.summary!),
        ],
        pw.SizedBox(height: 6),
        pw.Text(
          'Content:',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        ),
        pw.Paragraph(text: contentPreview),
        pw.Divider(),
        pw.SizedBox(height: 8),
      ],
    );
  }

  Future<void> _exportAsPDF() async {
    Navigator.pop(context);
    final sources = ref.read(sourceProvider);
    final notebooks = ref.read(notebookProvider);
    final notebook = notebooks.isNotEmpty ? notebooks.first : null;
    final title = notebook?.title ?? 'Notebook';

    try {
      final pdfBytes = await _buildNotebookPdf(title, sources);
      final tempDir = await getTemporaryDirectory();
      final sanitizedTitle = title.replaceAll(RegExp(r'[^\w\s-]'), '');
      final fileName =
          '${sanitizedTitle}_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pdfBytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: title,
        text: 'Notebook: $title',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export PDF: $e')),
      );
    }
  }

  void _exportAsMarkdown() {
    Navigator.pop(context);
    final sources = ref.read(sourceProvider);
    final notebooks = ref.read(notebookProvider);
    final notebook = notebooks.isNotEmpty ? notebooks.first : null;
    String markdown = '# ${notebook?.title ?? "Notebook"}\n\n';
    markdown += 'Generated on ${DateTime.now().toString().split(' ')[0]}\n\n';
    markdown += '## Sources (${sources.length})\n\n';
    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      markdown += '### ${i + 1}. ${source.title}\n';
      markdown += '- **Type**: ${source.type}\n';
      markdown += '- **Added**: ${source.addedAt.toString().split(' ')[0]}\n';
      if (source.content.length > 200) {
        markdown += '- **Preview**: ${source.content.substring(0, 200)}...\n';
      } else {
        markdown += '- **Content**: ${source.content}\n';
      }
      markdown += '\n---\n\n';
    }
    Share.share(markdown, subject: 'Sources - Markdown Export');
  }

  void _exportAsText() {
    Navigator.pop(context);
    final sources = ref.read(sourceProvider);
    final notebooks = ref.read(notebookProvider);
    final notebook = notebooks.isNotEmpty ? notebooks.first : null;
    String text = '${notebook?.title ?? "Notebook"}\n';
    text += '=' * (notebook?.title.length ?? 10) + '\n\n';
    text += 'Sources (${sources.length}):\n\n';
    for (int i = 0; i < sources.length; i++) {
      final source = sources[i];
      text += '${i + 1}. ${source.title}\n';
      text += '   Type: ${source.type}\n';
      text += '   Added: ${source.addedAt.toString().split(' ')[0]}\n';
      if (source.content.length > 100) {
        text += '   Preview: ${source.content.substring(0, 100)}...\n';
      } else {
        text += '   Content: ${source.content}\n';
      }
      text += '\n';
    }
    Share.share(text, subject: 'Sources - Text Export');
  }

  void _exportAsJSON() {
    Navigator.pop(context);
    final sources = ref.read(sourceProvider);
    final notebooks = ref.read(notebookProvider);
    final notebook = notebooks.isNotEmpty ? notebooks.first : null;
    final data = {
      'title': notebook?.title ?? 'Notebook',
      'createdAt': DateTime.now().toIso8601String(),
      'sourceCount': sources.length,
      'sources': sources
          .map((s) => {
                'title': s.title,
                'type': s.type,
                'content': s.content,
                'addedAt': s.addedAt.toIso8601String(),
              })
          .toList(),
    };
    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    Share.share(jsonString, subject: 'Sources - JSON Export');
  }

  void _showAIResearchDialog() {
    final scheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Icon(Icons.auto_awesome, color: scheme.tertiary),
            const SizedBox(width: 12),
            const Text('AI Research Assistant'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What would you like to research?',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g., "Summarize climate change impacts"',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: scheme.surface,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Text(
              'AI will analyze your sources and provide insights.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final query = controller.text.trim();
              if (query.isNotEmpty) {
                Navigator.pop(context);
                _performAIResearch(query);
              }
            },
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Research'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  void _performAIResearch(String query) async {
    final sources = ref.read(sourceProvider);
    final sourceContext =
        sources.map((s) => '${s.title}: ${s.content}').toList();
    setState(() {
      _showAIResearch = true;
      _researchQuery = query;
    });
    try {
      await ref.read(aiProvider.notifier).generateContent(
            'Based on these sources, please provide a comprehensive research response to: $query',
            context: sourceContext,
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Research failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sources = ref.watch(sourceProvider);
    final aiState = ref.watch(aiProvider);

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) async {
        if (_isSelectionMode) {
          _exitSelectionMode();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _isSelectionMode
              ? IconButton(
                  onPressed: _exitSelectionMode,
                  icon: const Icon(Icons.close),
                )
              : null,
          title: Text(
            _isSelectionMode
                ? '${_selectedSourceIds.length} selected'
                : 'Sources',
          ),
          actions: _isSelectionMode
              ? [
                  IconButton(
                    onPressed:
                        sources.isEmpty ? null : () => _toggleSelectAll(sources),
                    icon: Icon(
                      _selectedSourceIds.length == sources.length &&
                              sources.isNotEmpty
                          ? Icons.deselect
                          : Icons.select_all,
                    ),
                    tooltip: _selectedSourceIds.length == sources.length &&
                            sources.isNotEmpty
                        ? 'Deselect all'
                        : 'Select all',
                  ),
                  IconButton(
                    onPressed: _selectedSourceIds.isEmpty
                        ? null
                        : _deleteSelectedSources,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete selected',
                  ),
                ]
              : [
                  IconButton(
                    onPressed: _showExportDialog,
                    icon: const Icon(Icons.download_outlined),
                    tooltip: 'Export notebook',
                  ).animate().scale(duration: Motion.short, delay: Motion.short),
                  IconButton(
                    onPressed: _showAIResearchDialog,
                    icon: const Icon(Icons.auto_awesome),
                    tooltip: 'AI Research Assistant',
                  ).animate().scale(duration: Motion.short, delay: Motion.medium),
                  IconButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const AddSourceSheet(),
                    ),
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Add source',
                  ).animate().scale(duration: Motion.short, delay: Motion.long),
                ],
        ),
        body: Column(
          children: [
            if (!_isSelectionMode)
            // Header section with premium design
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.1),
                    scheme.secondary.withValues(alpha: 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          Icons.source,
                          color: scheme.primary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Research Sources',
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${sources.length} sources collected',
                              style: text.bodyMedium?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Source type chips
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _SourceChip(
                          label: 'Web Search',
                          icon: LucideIcons.globe,
                          color: scheme.primary),
                      _SourceChip(
                          label: 'Upload File',
                          icon: LucideIcons.fileUp,
                          color: scheme.secondary),
                      const _SourceChip(
                          label: 'YouTube',
                          icon: LucideIcons.youtube,
                          color: Colors.red),
                      _SourceChip(
                          label: 'Audio',
                          icon: LucideIcons.mic,
                          color: scheme.tertiary),
                    ],
                  ),
                ],
              ),
            )
                .animate()
                .slideY(begin: 0.2, duration: Motion.medium)
                .fadeIn(duration: Motion.medium),

            // AI Research Results
            if (_showAIResearch && aiState.status == AIStatus.loading)
              Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI is researching: "$_researchQuery"',
                      style: text.bodyMedium,
                    ),
                  ),
                ],
              ),
              )
                .animate()
                .slideY(begin: -0.2, duration: Motion.short)
                .fadeIn(duration: Motion.short),

            if (_showAIResearch && aiState.status == AIStatus.success)
              Expanded(
                child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.tertiary.withValues(alpha: 0.1),
                      scheme.primary.withValues(alpha: 0.05),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: scheme.tertiary.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header - fixed at top
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                      child: Row(
                        children: [
                          Icon(Icons.auto_awesome,
                              color: scheme.tertiary, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'AI Research Results',
                            style: text.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.tertiary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () =>
                                setState(() => _showAIResearch = false),
                            icon: const Icon(Icons.close, size: 18),
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                    ),
                    const Divider(),
                    // Scrollable content
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          aiState.lastResponse ?? 'No response generated',
                          style: text.bodyMedium?.copyWith(
                            height: 1.6,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                    // Action buttons - fixed at bottom
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _copyToClipboard(aiState.lastResponse ?? ''),
                              icon: const Icon(Icons.copy, size: 16),
                              label: const Text('Copy'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _shareResearch(aiState.lastResponse ?? ''),
                              icon: const Icon(Icons.share, size: 16),
                              label: const Text('Share'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _saveAsSource(aiState.lastResponse ?? ''),
                            icon: const Icon(Icons.save, size: 16),
                            label: const Text('Save'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ),
              )
                .animate()
                .slideY(begin: -0.2, duration: Motion.short)
                .fadeIn(duration: Motion.short),

            // Sources list (hide when AI research is showing)
            if (!(_showAIResearch && aiState.status == AIStatus.success))
              Expanded(
                child: sources.isEmpty
                    ? _EmptySourcesView(scheme: scheme, text: text)
                    : _SourcesList(
                        sources: sources,
                        isSelectionMode: _isSelectionMode,
                        selectedSourceIds: _selectedSourceIds,
                        onToggleSelection: _toggleSelection,
                        onEnterSelectionMode: _enterSelectionMode,
                      ),
              ),
          ],
        ),

      // Premium floating action buttons
        floatingActionButton: _isSelectionMode
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FloatingActionButton.extended(
                    onPressed: () => context.go('/search'),
                    heroTag: 'web_search',
                    backgroundColor: scheme.secondary,
                    icon: const Icon(Icons.search),
                    label: const Text('Web Search'),
                  ).animate().scale(
                      duration: Motion.short,
                      delay:
                          const Duration(milliseconds: 5 * Motion.baseStagger)),
                  const SizedBox(height: 16),
                  FloatingActionButton(
                    onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (_) => Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius:
                              const BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: const AddSourceSheet(),
                      ),
                    ),
                    heroTag: 'add_source',
                    backgroundColor: scheme.primary,
                    child: const Icon(Icons.add),
                  ).animate().scale(
                      duration: Motion.short,
                      delay:
                          const Duration(milliseconds: 6 * Motion.baseStagger)),
                ],
              ),
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Research copied to clipboard')),
    );
  }

  void _shareResearch(String text) {
    Share.share(text, subject: 'AI Research Results');
  }

  void _saveAsSource(String content) async {
    if (content.isEmpty) return;

    try {
      await ref.read(sourceProvider.notifier).addSource(
            title: 'AI Research: $_researchQuery',
            type: 'report',
            content: content,
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Research saved as source')),
        );
        setState(() => _showAIResearch = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }
}

class _SourcesList extends StatelessWidget {
  const _SourcesList({
    required this.sources,
    required this.isSelectionMode,
    required this.selectedSourceIds,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
  });

  final List<Source> sources;
  final bool isSelectionMode;
  final Set<String> selectedSourceIds;
  final ValueChanged<String> onToggleSelection;
  final ValueChanged<String> onEnterSelectionMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: sources.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final s = sources[index];
        final isSelected = selectedSourceIds.contains(s.id);
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isSelected
                ? BorderSide(color: scheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: ListTile(
            onTap: () {
              if (isSelectionMode) {
                onToggleSelection(s.id);
                return;
              }

              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SourceDetailScreen(sourceId: s.id),
                ),
              );
            },
            onLongPress: () => onEnterSelectionMode(s.id),
            leading: isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggleSelection(s.id),
                  )
                : Icon(_iconForType(s.type), color: scheme.primary),
            title: Text(
              s.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${s.type} - ${s.addedAt.day}/${s.addedAt.month}/${s.addedAt.year}'),
                _IndexStatusBadge(sourceId: s.id),
              ],
            ),
            trailing: isSelectionMode ? null : _PreviewTrailing(source: s),
          ),
        );
      },
    );
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'drive':
        return Icons.drive_folder_upload;
      case 'file':
        return Icons.attach_file;
      case 'url':
        return Icons.link;
      case 'youtube':
        return Icons.video_library;
      case 'audio':
        return Icons.audiotrack;
      default:
        return Icons.source;
    }
  }
}

class _IndexStatusBadge extends ConsumerStatefulWidget {
  const _IndexStatusBadge({required this.sourceId});
  final String sourceId;

  @override
  ConsumerState<_IndexStatusBadge> createState() => _IndexStatusBadgeState();
}

class _IndexStatusBadgeState extends ConsumerState<_IndexStatusBadge> {
  bool _indexed = false;

  @override
  void initState() {
    super.initState();
    _check();
    _subscribe();
  }

  Future<void> _check() async {
    final api = ref.read(apiServiceProvider);
    final has = await api.sourceHasChunks(widget.sourceId);
    if (mounted) setState(() => _indexed = has);
  }

  void _subscribe() {
    // Polling or real-time if Neon supports it (not implemented here, just check once)
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _indexed
            ? Colors.green.withValues(alpha: 0.12)
            : Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(_indexed ? 'Indexed' : 'Processing',
          style: TextStyle(
              fontSize: 11, color: _indexed ? Colors.green : Colors.orange)),
    ).animate().fadeIn(duration: Motion.short);
  }
}

class _PreviewTrailing extends ConsumerWidget {
  const _PreviewTrailing({required this.source});
  final Source source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (source.type != 'image' && source.type != 'video') {
      return IconButton(
        icon: const Icon(Icons.open_in_new),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => SourceDetailScreen(sourceId: source.id)),
        ),
      );
    }
    final service = ref.read(mediaServiceProvider);
    return FutureBuilder<Uint8List?>(
      future: service.getMediaBytes(source.id),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2));
        }
        final bytes = snap.data;
        if (bytes == null) {
          return IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => SourceDetailScreen(sourceId: source.id)),
            ),
          );
        }
        if (source.type == 'image') {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover)
                .animate()
                .fadeIn(duration: Motion.short),
          );
        }
        return IconButton(
          icon: const Icon(Icons.open_in_new),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => SourceDetailScreen(sourceId: source.id)),
          ),
        );
      },
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      onPressed: () {
        // Handle different source types
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Add $label source')),
        );
      },
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.1),
      labelStyle: TextStyle(color: color, fontSize: 12),
    ).animate().scale(duration: Motion.short);
  }
}

class _EmptySourcesView extends StatelessWidget {
  const _EmptySourcesView({
    required this.scheme,
    required this.text,
  });

  final ColorScheme scheme;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.1),
                  scheme.secondary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              Icons.source_outlined,
              size: 60,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
          )
              .animate()
              .scale(duration: Motion.xLong)
              .fadeIn(duration: Motion.medium),
          const SizedBox(height: 24),
          Text(
            'No sources yet',
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          )
              .animate()
              .slideY(begin: 0.2, duration: Motion.medium)
              .fadeIn(duration: Motion.medium),
          const SizedBox(height: 8),
          Text(
            'Add sources to start building your research',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .slideY(begin: 0.2, duration: Motion.medium, delay: Motion.short)
              .fadeIn(duration: Motion.medium),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search),
            label: const Text('Search the Web'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ).animate().scale(duration: Motion.short, delay: Motion.medium),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const AddSourceSheet(),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text('Upload File'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ).animate().scale(duration: Motion.short, delay: Motion.long),
        ],
      ),
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  const _ExportOptionTile({
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
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      tileColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
    );
  }
}
