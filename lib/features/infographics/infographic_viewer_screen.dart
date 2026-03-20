import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'infographic.dart';
import 'infographic_provider.dart';
import '../../ui/widgets/app_network_image.dart';

/// Screen for viewing an infographic
class InfographicViewerScreen extends StatefulWidget {
  final Infographic infographic;

  const InfographicViewerScreen({super.key, required this.infographic});

  @override
  State<InfographicViewerScreen> createState() =>
      _InfographicViewerScreenState();
}

class _InfographicViewerScreenState extends State<InfographicViewerScreen> {
  final TransformationController _transformController =
      TransformationController();
  WebViewController? _htmlController;

  @override
  void initState() {
    super.initState();
    _initHtmlController();
  }

  void _initHtmlController() {
    final html = widget.infographic.htmlContent;
    if (html == null || html.isEmpty) return;

    _htmlController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..loadHtmlString(html);
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.8),
        foregroundColor: Colors.white,
        title: Text(widget.infographic.title),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.zoomIn),
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(LucideIcons.zoomOut),
            onPressed: _zoomOut,
          ),
          IconButton(
            icon: const Icon(LucideIcons.maximize2),
            onPressed: _resetZoom,
          ),
          IconButton(
            icon: const Icon(LucideIcons.share),
            onPressed: () => _shareInfographic(context),
          ),
        ],
      ),
      body: _buildContent(scheme, text),
    );
  }

  Widget _buildContent(ColorScheme scheme, TextTheme text) {
    // Check if we have image data
    final hasHtml = widget.infographic.hasHtmlContent;
    final hasUrl = widget.infographic.imageUrl != null &&
        widget.infographic.imageUrl!.isNotEmpty &&
        !hasHtml;
    final hasBase64 = widget.infographic.imageBase64 != null &&
        widget.infographic.imageBase64!.isNotEmpty;

    if (!hasUrl && !hasBase64 && !hasHtml) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.imagePlus,
                size: 64,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Infographic not yet generated',
              style: text.titleLarge?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Use an image generation service to create the visual',
              style: text.bodyMedium?.copyWith(color: Colors.white60),
            ),
          ],
        ).animate().fadeIn(),
      );
    }

    if (hasHtml && _htmlController != null) {
      return Container(
        color: Colors.white,
        child: WebViewWidget(controller: _htmlController!),
      );
    }

    Widget image;
    if (hasUrl) {
      final imageUrl = widget.infographic.imageUrl!;
      if (imageUrl.startsWith('data:image/')) {
        try {
          final commaIndex = imageUrl.indexOf(',');
          final base64Data =
              commaIndex == -1 ? imageUrl : imageUrl.substring(commaIndex + 1);
          final bytes = base64Decode(base64Data);
          image = Image.memory(
            Uint8List.fromList(bytes),
            fit: BoxFit.contain,
          );
        } catch (e) {
          return _buildErrorState(text);
        }
      } else {
        image = AppNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.contain,
          placeholder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
          errorWidget: (context) => _buildErrorState(text),
        );
      }
    } else {
      // Decode base64
      try {
        final bytes = base64Decode(widget.infographic.imageBase64!);
        image = Image.memory(
          Uint8List.fromList(bytes),
          fit: BoxFit.contain,
        );
      } catch (e) {
        return _buildErrorState(text);
      }
    }

    return InteractiveViewer(
      transformationController: _transformController,
      boundaryMargin: const EdgeInsets.all(double.infinity),
      minScale: 0.5,
      maxScale: 4.0,
      child: Center(
        child: image,
      ),
    );
  }

  Widget _buildErrorState(TextTheme text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            LucideIcons.cloudOff,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load image',
            style: text.titleMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.3).clamp(0.5, 4.0);
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(2, 2, newScale);
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.3).clamp(0.5, 4.0);
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(2, 2, newScale);
  }

  void _resetZoom() {
    _transformController.value = Matrix4.identity();
  }

  Future<void> _shareInfographic(BuildContext context) async {
    final infographic = widget.infographic;

    if (infographic.hasHtmlContent && infographic.htmlContent != null) {
      try {
        final tempDir = await getTemporaryDirectory();
        final fileName = 'infographic_${infographic.id}.html';
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsString(infographic.htmlContent!);

        await Share.shareXFiles(
          [XFile(file.path)],
          text: infographic.title,
          subject: infographic.title,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // If we have a URL, share it directly
    if (infographic.imageUrl != null && infographic.imageUrl!.isNotEmpty) {
      if (infographic.imageUrl!.startsWith('data:image/')) {
        try {
          final commaIndex = infographic.imageUrl!.indexOf(',');
          final base64Data = commaIndex == -1
              ? infographic.imageUrl!
              : infographic.imageUrl!.substring(commaIndex + 1);
          final bytes = base64Decode(base64Data);
          final tempDir = await getTemporaryDirectory();
          final fileName = 'infographic_${infographic.id}.png';
          final file = File('${tempDir.path}/$fileName');
          await file.writeAsBytes(bytes);

          await Share.shareXFiles(
            [XFile(file.path)],
            text: infographic.title,
            subject: infographic.title,
          );
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to share: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await Share.share(
        '${infographic.title}\n\n${infographic.imageUrl}',
        subject: infographic.title,
      );
      return;
    }

    // If we have base64 data, save to temp file and share
    if (infographic.imageBase64 != null &&
        infographic.imageBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(infographic.imageBase64!);
        final tempDir = await getTemporaryDirectory();
        final fileName = 'infographic_${infographic.id}.png';
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(bytes);

        await Share.shareXFiles(
          [XFile(file.path)],
          text: infographic.title,
          subject: infographic.title,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to share: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // No image data to share
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No image available to share'),
      ),
    );
  }
}

/// Bottom sheet for generating infographics
class InfographicGeneratorSheet extends ConsumerStatefulWidget {
  final String sourceId;
  final String notebookId;
  final String sourceTitle;

  const InfographicGeneratorSheet({
    super.key,
    required this.sourceId,
    required this.notebookId,
    required this.sourceTitle,
  });

  @override
  ConsumerState<InfographicGeneratorSheet> createState() =>
      _InfographicGeneratorSheetState();
}

class _InfographicGeneratorSheetState
    extends ConsumerState<InfographicGeneratorSheet> {
  InfographicStyle _selectedStyle = InfographicStyle.modern;
  bool _isGenerating = false;
  String? _generatedPrompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    LucideIcons.image,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Generate Infographic', style: text.titleLarge),
                      Text(
                        'For: ${widget.sourceTitle}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      _isGenerating ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          const Divider(),

          // Style selection
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                      onSelected: _isGenerating
                          ? null
                          : (selected) {
                              if (selected) {
                                setState(() => _selectedStyle = style);
                              }
                            },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // Generated prompt preview
          if (_generatedPrompt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.sparkles,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Generated Prompt',
                          style: text.labelMedium?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _generatedPrompt!,
                      style: text.bodySmall,
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

          // Generate button
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isGenerating ? null : _generatePrompt,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(LucideIcons.sparkles),
                label: Text(
                  _generatedPrompt == null
                      ? 'Generate Prompt'
                      : 'Regenerate Prompt',
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),

          // Note about image generation
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Text(
              'Note: The generated prompt can be used with DALL-E, Midjourney, or other image generation services.',
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
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

  Future<void> _generatePrompt() async {
    setState(() => _isGenerating = true);

    try {
      final prompt = await ref
          .read(infographicProvider.notifier)
          .generateInfographicPrompt(
            sourceId: widget.sourceId,
            style: _selectedStyle,
          );

      if (!mounted) return;
      setState(() {
        _generatedPrompt = prompt;
        _isGenerating = false;
      });
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
}
