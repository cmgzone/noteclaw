import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'infographic_provider.dart';
import 'infographic.dart';
import 'infographic_viewer_screen.dart';
import '../sources/source_provider.dart';
import '../subscription/services/credit_manager.dart';
import '../../ui/widgets/app_network_image.dart';

class InfographicsListScreen extends ConsumerStatefulWidget {
  final String notebookId;

  const InfographicsListScreen({super.key, required this.notebookId});

  @override
  ConsumerState<InfographicsListScreen> createState() =>
      _InfographicsListScreenState();
}

class _InfographicsListScreenState
    extends ConsumerState<InfographicsListScreen> {
  @override
  Widget build(BuildContext context) {
    final infographics = ref.watch(infographicProvider);
    final notebookInfographics =
        infographics.where((i) => i.notebookId == widget.notebookId).toList();
    final sources = ref.watch(sourceProvider);
    final notebookSources =
        sources.where((s) => s.notebookId == widget.notebookId).toList();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Infographics'),
        actions: [
          if (notebookSources.isNotEmpty)
            IconButton(
              icon: const Icon(LucideIcons.plus),
              onPressed: () => _showCreateSheet(context),
              tooltip: 'Create Infographic',
            ),
        ],
      ),
      body: notebookInfographics.isEmpty
          ? _buildEmptyState(context, scheme, text, notebookSources.isNotEmpty)
          : _buildInfographicsList(context, notebookInfographics, scheme, text),
      floatingActionButton: notebookSources.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateSheet(context),
              icon: const Icon(LucideIcons.imagePlus),
              label: const Text('Create'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme scheme,
      TextTheme text, bool hasSources) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.image,
                size: 64,
                color: scheme.secondary,
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(
              'No Infographics Yet',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 12),
            Text(
              hasSources
                  ? 'Create visual summaries of your sources.\nTap the button below to get started.'
                  : 'Add some sources first, then create\nbeautiful infographics from them.',
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms),
            if (hasSources) ...[
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => _showCreateSheet(context),
                icon: const Icon(LucideIcons.imagePlus),
                label: const Text('Create Infographic'),
              ).animate().slideY(begin: 0.2, delay: 600.ms).fadeIn(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfographicsList(BuildContext context,
      List<Infographic> infographics, ColorScheme scheme, TextTheme text) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: infographics.length,
      itemBuilder: (context, index) {
        final infographic = infographics[index];
        return _InfographicCard(
          infographic: infographic,
          onTap: () => _viewInfographic(context, infographic),
          onDelete: () => _deleteInfographic(infographic),
        ).animate().fadeIn(delay: Duration(milliseconds: 100 * index));
      },
    );
  }

  void _showCreateSheet(BuildContext context) {
    final sources = ref.read(sourceProvider);
    final notebookSources =
        sources.where((s) => s.notebookId == widget.notebookId).toList();

    if (notebookSources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add sources first to create infographics')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: _SelectSourceSheet(
          sources: notebookSources,
          notebookId: widget.notebookId,
        ),
      ),
    );
  }

  void _viewInfographic(BuildContext context, Infographic infographic) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InfographicViewerScreen(infographic: infographic),
      ),
    );
  }

  void _deleteInfographic(Infographic infographic) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Infographic?'),
        content:
            Text('Are you sure you want to delete "${infographic.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref
          .read(infographicProvider.notifier)
          .deleteInfographic(infographic.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Infographic deleted')),
        );
      }
    }
  }
}

class _InfographicCard extends StatelessWidget {
  final Infographic infographic;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _InfographicCard({
    required this.infographic,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image preview or placeholder
            Container(
              height: 120,
              width: double.infinity,
              color: scheme.surfaceContainerHighest,
              child: infographic.imageUrl != null ||
                      infographic.imageBase64 != null
                  ? _buildImagePreview()
                  : Center(
                      child: Icon(
                        LucideIcons.image,
                        size: 48,
                        color: scheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          infographic.title,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStyleName(infographic.style),
                                style: text.labelSmall?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatDate(infographic.createdAt),
                              style: text.bodySmall?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(LucideIcons.trash2, color: scheme.error),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    if (infographic.hasHtmlContent) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF5E8D3), Color(0xFFE4C49A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.web_asset_rounded,
                size: 34,
                color: Colors.brown.shade700,
              ),
              const SizedBox(height: 8),
              Text(
                'HTML Infographic',
                style: TextStyle(
                  color: Colors.brown.shade900,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Fallback preview',
                style: TextStyle(
                  color: Colors.brown.shade700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final imageUrl = infographic.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      if (imageUrl.startsWith('data:image/')) {
        try {
          final commaIndex = imageUrl.indexOf(',');
          final base64Data =
              commaIndex == -1 ? imageUrl : imageUrl.substring(commaIndex + 1);
          final bytes = base64Decode(base64Data);
          return Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.cover,
          );
        } catch (_) {
          return const Center(
            child: Icon(LucideIcons.imageOff, size: 32),
          );
        }
      }

      return AppNetworkImage(
        imageUrl: imageUrl,
        fit: BoxFit.cover,
        errorWidget: (context) => const Center(
          child: Icon(LucideIcons.imageOff, size: 32),
        ),
      );
    }

    final imageBase64 = infographic.imageBase64;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(imageBase64);
        return Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.cover,
        );
      } catch (_) {
        return const Center(
          child: Icon(LucideIcons.imageOff, size: 32),
        );
      }
    }

    return const SizedBox.shrink();
  }

  String _getStyleName(InfographicStyle style) {
    return switch (style) {
      InfographicStyle.modern => 'Modern',
      InfographicStyle.minimal => 'Minimal',
      InfographicStyle.colorful => 'Colorful',
      InfographicStyle.professional => 'Professional',
      InfographicStyle.playful => 'Playful',
    };
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _SelectSourceSheet extends ConsumerStatefulWidget {
  final List<dynamic> sources;
  final String notebookId;

  const _SelectSourceSheet({
    required this.sources,
    required this.notebookId,
  });

  @override
  ConsumerState<_SelectSourceSheet> createState() => _SelectSourceSheetState();
}

class _SelectSourceSheetState extends ConsumerState<_SelectSourceSheet> {
  String? _selectedSourceId;
  InfographicStyle _selectedStyle = InfographicStyle.modern;
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) => Column(
        children: [
          // Handle
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
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Icon(LucideIcons.imagePlus, color: scheme.primary),
                const SizedBox(width: 12),
                Text('Create Infographic', style: text.titleLarge),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              children: [
                Text('Select Source', style: text.titleSmall),
                const SizedBox(height: 12),
                ...widget.sources.map((source) {
                  final isSelected = _selectedSourceId == source.id;
                  return Card(
                    color: isSelected ? scheme.primaryContainer : null,
                    child: ListTile(
                      leading: Icon(
                        _getSourceIcon(source.type),
                        color: isSelected ? scheme.onPrimaryContainer : null,
                      ),
                      title: Text(source.title),
                      subtitle: Text(source.type),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: scheme.primary)
                          : null,
                      onTap: () =>
                          setState(() => _selectedSourceId = source.id),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                Text('Visual Style', style: text.titleSmall),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: InfographicStyle.values.map((style) {
                    final isSelected = _selectedStyle == style;
                    return ChoiceChip(
                      label: Text(_getStyleName(style)),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedStyle = style);
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 32),
                FilledButton.icon(
                  onPressed: _selectedSourceId == null || _isGenerating
                      ? null
                      : _createInfographic,
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.sparkles),
                  label: Text(
                      _isGenerating ? 'Generating...' : 'Generate Infographic'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSourceIcon(String type) {
    return switch (type) {
      'text' => LucideIcons.fileText,
      'url' => LucideIcons.link,
      'youtube' => LucideIcons.youtube,
      'drive' => LucideIcons.hardDrive,
      'image' => LucideIcons.image,
      'audio' => LucideIcons.music,
      _ => LucideIcons.file,
    };
  }

  String _getStyleName(InfographicStyle style) {
    return switch (style) {
      InfographicStyle.modern => 'Modern',
      InfographicStyle.minimal => 'Minimal',
      InfographicStyle.colorful => 'Colorful',
      InfographicStyle.professional => 'Professional',
      InfographicStyle.playful => 'Playful',
    };
  }

  Future<void> _createInfographic() async {
    if (_selectedSourceId == null) return;

    // Check and consume credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.generateInfographic,
      feature: 'generate_infographic',
    );
    if (!hasCredits) return;

    setState(() => _isGenerating = true);

    try {
      final source =
          widget.sources.firstWhere((s) => s.id == _selectedSourceId);

      final asset =
          await ref.read(infographicProvider.notifier).generateInfographicAsset(
                sourceId: _selectedSourceId!,
                title: 'Infographic: ${source.title}',
                style: _selectedStyle,
              );

      await ref.read(infographicProvider.notifier).createInfographic(
            sourceId: _selectedSourceId!,
            notebookId: widget.notebookId,
            title: 'Infographic: ${source.title}',
            imageUrl: asset.imageUrl,
            imageBase64: asset.imageBase64,
            style: _selectedStyle,
          );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            asset.isHtmlFallback
                ? 'HTML infographic created because this model cannot generate images.'
                : 'Infographic created and added to your notebook.',
          ),
          action: SnackBarAction(
            label: 'View Prompt',
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Generated Prompt'),
                  content: SingleChildScrollView(child: Text(asset.prompt)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
