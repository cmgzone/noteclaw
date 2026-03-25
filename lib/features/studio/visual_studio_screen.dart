import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../core/ai/gemini_image_service.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/security/ai_api_key_resolver.dart';
import '../sources/source_provider.dart';
import '../sources/source.dart';

class VisualStudioScreen extends ConsumerStatefulWidget {
  const VisualStudioScreen({
    super.key,
    this.notebookId,
    this.notebookTitle,
  });

  final String? notebookId;
  final String? notebookTitle;

  @override
  ConsumerState<VisualStudioScreen> createState() => _VisualStudioScreenState();
}

class _VisualStudioScreenState extends ConsumerState<VisualStudioScreen> {
  final _promptController = TextEditingController();
  String? _generatedImageUrl;
  String? _providerLabel;
  String? _modelLabel;
  String? _backendLabel;
  String? _backendNote;
  String? _keySourceLabel;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadImageRoutePreview();
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _loadImageRoutePreview() async {
    final route = await _resolveImageRoute();
    if (!mounted) return;
    setState(() {
      _providerLabel = route.providerLabel;
      _modelLabel = route.modelLabel;
      _backendLabel = route.backendLabel;
      _backendNote = route.note;
      _keySourceLabel = route.keySourceLabel;
    });
  }

  void _generateImage() async {
    final rawPrompt = _promptController.text.trim();
    if (rawPrompt.isEmpty) return;
    final aspectRatio = _inferAspectRatio(rawPrompt);

    setState(() {
      _isGenerating = true;
      _generatedImageUrl = null;
    });

    try {
      final prompt = _buildPromptWithNotebookContext(
        rawPrompt,
        aspectRatio: aspectRatio,
      );
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final route = await _resolveImageRoute(
        providerOverride: settings.provider,
        modelOverride: settings.model,
      );

      final imageService = GeminiImageService(apiKey: route.apiKey);
      final result = await imageService.generateImageResult(
        prompt,
        provider: settings.provider,
        model: settings.model,
        aspectRatio: aspectRatio,
      );

      if (mounted) {
        setState(() {
          _generatedImageUrl = result.imageUrl;
          _providerLabel = route.providerLabel;
          _modelLabel = route.modelLabel;
          _backendLabel = result.backendLabel;
          _backendNote = result.note ?? route.note;
          _keySourceLabel = route.displayKeySourceLabelFor(result.backend);
          _isGenerating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation failed: $e')),
        );
      }
    }
  }

  Set<String> _extractPromptKeywords(String prompt) {
    const stopWords = {
      'the',
      'and',
      'for',
      'with',
      'that',
      'this',
      'from',
      'into',
      'your',
      'have',
      'make',
      'create',
      'show',
      'about',
      'image',
      'visual',
      'illustration',
      'design',
      'want',
      'need',
    };

    return RegExp(r'[a-z0-9]+')
        .allMatches(prompt.toLowerCase())
        .map((match) => match.group(0)!)
        .where((word) => word.length > 2 && !stopWords.contains(word))
        .take(10)
        .toSet();
  }

  int _sourceScore(Source source, Set<String> keywords) {
    final haystack =
        '${source.title} ${source.content}'.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    var score = source.title.trim().isNotEmpty ? 2 : 0;

    for (final keyword in keywords) {
      if (haystack.contains(keyword)) {
        score += keyword.length >= 6 ? 4 : 2;
      }
    }

    score += (source.content.length ~/ 900).clamp(0, 4);
    return score;
  }

  List<Source> _selectRelevantSources(String prompt) {
    final notebookId = widget.notebookId;
    if (notebookId == null || notebookId.isEmpty) return const [];

    final keywords = _extractPromptKeywords(prompt);
    final sources = ref
        .read(sourceProvider)
        .where((source) => source.notebookId == notebookId)
        .where((source) => source.content.trim().isNotEmpty)
        .toList();

    sources.sort(
      (a, b) => _sourceScore(b, keywords).compareTo(_sourceScore(a, keywords)),
    );

    return sources.take(5).toList();
  }

  String _inferAspectRatio(String prompt) {
    final normalized = prompt.toLowerCase();

    if (normalized.contains('youtube') ||
        normalized.contains('banner') ||
        normalized.contains('header') ||
        normalized.contains('hero image') ||
        normalized.contains('presentation') ||
        normalized.contains('slide') ||
        normalized.contains('landscape') ||
        normalized.contains('wide')) {
      return '16:9';
    }

    if (normalized.contains('phone wallpaper') ||
        normalized.contains('mobile wallpaper') ||
        normalized.contains('story format') ||
        normalized.contains('portrait phone')) {
      return '9:16';
    }

    if (normalized.contains('book cover') ||
        normalized.contains('ebook cover') ||
        normalized.contains('poster') ||
        normalized.contains('portrait') ||
        normalized.contains('flyer')) {
      return '4:5';
    }

    return '1:1';
  }

  String _inferVisualMode(String prompt) {
    final normalized = prompt.toLowerCase();

    if (normalized.contains('infographic') ||
        normalized.contains('diagram') ||
        normalized.contains('chart') ||
        normalized.contains('map')) {
      return 'editorial infographic';
    }

    if (normalized.contains('cover') ||
        normalized.contains('poster') ||
        normalized.contains('thumbnail')) {
      return 'cover-quality concept art';
    }

    if (normalized.contains('portrait') ||
        normalized.contains('character') ||
        normalized.contains('person')) {
      return 'cinematic character illustration';
    }

    if (normalized.contains('product') ||
        normalized.contains('mockup') ||
        normalized.contains('render')) {
      return 'high-end product render';
    }

    return 'polished editorial illustration';
  }

  bool _wantsReadableText(String prompt) {
    final normalized = prompt.toLowerCase();
    return normalized.contains('text') ||
        normalized.contains('typography') ||
        normalized.contains('caption') ||
        normalized.contains('quote') ||
        normalized.contains('label') ||
        normalized.contains('logo with text') ||
        normalized.contains('poster title');
  }

  String _buildPromptWithNotebookContext(
    String prompt, {
    required String aspectRatio,
  }) {
    final notebookTitle = (widget.notebookTitle ?? '').trim();
    final visualMode = _inferVisualMode(prompt);
    final textInstruction = _wantsReadableText(prompt)
        ? 'If text is truly necessary, keep it minimal, prominent, and easy to read.'
        : 'Do not include readable text, captions, UI chrome, logos, or watermarks.';

    final sources = _selectRelevantSources(prompt);
    if (sources.isEmpty) {
      return '''
Create a finished, production-quality $visualMode.

Primary request:
$prompt

Preferred framing: $aspectRatio

Art direction:
- strong focal subject and intentional composition
- cohesive lighting and color harmony
- use specific visual details rather than generic stock imagery
- $textInstruction
- deliver one clear, confident concept rather than a cluttered collage
''';
    }

    final contextLines = sources.map((source) {
      final snippet = source.content.replaceAll(RegExp(r'\s+'), ' ').trim();
      final preview =
          snippet.length > 220 ? '${snippet.substring(0, 220)}...' : snippet;
      return '- ${source.title}: $preview';
    }).join('\n');

    return '''
Create a finished, production-quality $visualMode grounded in the notebook "$notebookTitle".

Primary request:
$prompt

Preferred framing: $aspectRatio

Use the notebook evidence below to choose accurate subjects, props, settings, symbols, and mood.
Prioritize the user's request, but make the final image feel specific to this notebook instead of generic.

Notebook context:
$contextLines

Art direction:
- strong focal point and clean composition
- specific details pulled from the notebook references
- visually coherent lighting, palette, and mood
- avoid generic stock-photo or clip-art styling
- $textInstruction
- produce one strong image concept, not a moodboard
''';
  }

  bool _isRemoteImage(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  bool _isDataImage(String value) {
    return value.startsWith('data:image/');
  }

  bool _isSvgDataImage(String value) {
    return value.startsWith('data:image/svg+xml');
  }

  Future<Uint8List> _readGeneratedImageBytes(String imageValue) async {
    if (_isDataImage(imageValue)) {
      final parts = imageValue.split(',');
      if (parts.length < 2) {
        throw Exception('Invalid image data received');
      }
      return base64Decode(parts.last);
    }

    if (_isRemoteImage(imageValue)) {
      final response = await http.get(Uri.parse(imageValue)).timeout(
            const Duration(seconds: 60),
          );
      if (response.statusCode != 200) {
        throw Exception('Failed to download generated image');
      }
      return response.bodyBytes;
    }

    throw Exception('Unsupported image format');
  }

  Future<void> _saveAndShareImage() async {
    if (_generatedImageUrl == null) return;

    try {
      final bytes = await _readGeneratedImageBytes(_generatedImageUrl!);

      // Get temporary directory
      final tempDir = await getTemporaryDirectory();
      final file = File(
          '${tempDir.path}/generated_image_${DateTime.now().millisecondsSinceEpoch}.png');

      // Write bytes to file
      await file.writeAsBytes(bytes);

      // Share the file
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Generated with Visual Studio: ${_promptController.text}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Image ready to share!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save/share: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Visual Studio'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.notebookTitle != null &&
                widget.notebookTitle!.trim().isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.bookOpen,
                      size: 18,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Using notebook: ${widget.notebookTitle}',
                        style: text.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _buildRoutingCard(scheme, text),
            const SizedBox(height: 16),
            // Prompt Input
            TextField(
              controller: _promptController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: widget.notebookTitle != null
                    ? 'Describe the image you want to create from this notebook...'
                    : 'Describe the image you want to generate...',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor:
                    scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),

            // Generate Button
            FilledButton.icon(
              onPressed: _isGenerating ? null : _generateImage,
              icon: _isGenerating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: scheme.onPrimary))
                  : const Icon(LucideIcons.wand2),
              label: Text(_isGenerating ? 'Dreaming...' : 'Generate Image'),
            ),

            const SizedBox(height: 32),

            // Result Area
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                alignment: Alignment.center,
                child: _buildContent(scheme, text),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme scheme, TextTheme text) {
    if (_isGenerating) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Creating your masterpiece...', style: text.bodyLarge),
        ],
      );
    }

    if (_generatedImageUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_isRemoteImage(_generatedImageUrl!))
              Image.network(
                _generatedImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildImageFallback(
                  scheme,
                  text,
                  'Generated image preview is unavailable.',
                ),
              )
            else if (_isDataImage(_generatedImageUrl!) &&
                !_isSvgDataImage(_generatedImageUrl!))
              Image.memory(
                base64Decode(_generatedImageUrl!.split(',').last),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildImageFallback(
                  scheme,
                  text,
                  'Generated image preview is unavailable.',
                ),
              )
            else
              _buildImageFallback(
                scheme,
                text,
                'Image generated. Use share to export the result.',
              ),
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.small(
                onPressed: _saveAndShareImage,
                child: const Icon(Icons.share),
              ),
            ),
          ],
        ),
      ).animate().fadeIn();
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(LucideIcons.image, size: 64, color: scheme.outline),
        const SizedBox(height: 16),
        Text(
          'Your imagination awaits',
          style: text.titleMedium?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }

  Widget _buildImageFallback(
    ColorScheme scheme,
    TextTheme text,
    String message,
  ) {
    return Container(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.image, size: 56, color: scheme.primary),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutingCard(ColorScheme scheme, TextTheme text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
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
                'Image generation path',
                style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _RouteChip(label: 'Provider', value: _providerLabel ?? 'Loading'),
              _RouteChip(label: 'Model', value: _modelLabel ?? 'Loading'),
              _RouteChip(label: 'Backend', value: _backendLabel ?? 'Loading'),
              _RouteChip(label: 'Key', value: _keySourceLabel ?? 'Loading'),
            ],
          ),
          if (_backendNote != null && _backendNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _backendNote!,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<_VisualStudioImageRoute> _resolveImageRoute({
    String? providerOverride,
    String? modelOverride,
  }) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final provider = (providerOverride ?? settings.provider).trim();
    final model = (modelOverride ?? settings.model ?? '').trim();
    final resolvedKey =
        await ref.read(aiApiKeyResolverProvider).resolveForProvider(provider);

    final providerLabel = _formatProviderLabel(provider);
    final modelLabel = model.isEmpty ? 'No model selected' : model;

    if (provider == 'openrouter') {
      if (model.isEmpty) {
        return _VisualStudioImageRoute(
          apiKey: resolvedKey.apiKey,
          hasDirectApiKey: resolvedKey.hasKey,
          providerLabel: providerLabel,
          modelLabel: modelLabel,
          backendLabel: 'Pollinations fallback',
          keySourceLabel:
              resolvedKey.hasKey ? resolvedKey.sourceLabel : 'No API key',
          note:
              'Select an image-capable OpenRouter model to use direct image generation here.',
        );
      }

      return _VisualStudioImageRoute(
        apiKey: resolvedKey.apiKey,
        hasDirectApiKey: resolvedKey.hasKey,
        providerLabel: providerLabel,
        modelLabel: modelLabel,
        backendLabel:
            resolvedKey.hasKey ? 'OpenRouter' : 'Pollinations fallback',
        keySourceLabel:
            resolvedKey.hasKey ? resolvedKey.sourceLabel : 'No API key',
        note: resolvedKey.hasKey
            ? 'OpenRouter image generation will use ${resolvedKey.sourceLabel.toLowerCase()}.'
            : 'No OpenRouter key is available, so the free fallback will be used for images.',
      );
    }

    return _VisualStudioImageRoute(
      apiKey: resolvedKey.apiKey,
      hasDirectApiKey: false,
      providerLabel: providerLabel,
      modelLabel: modelLabel,
      backendLabel: 'Pollinations fallback',
      keySourceLabel: 'Not used',
      note:
          'Image generation currently uses Pollinations when Gemini is selected.',
    );
  }

  String _formatProviderLabel(String provider) {
    switch (provider) {
      case 'openrouter':
        return 'OpenRouter';
      case 'gemini':
        return 'Gemini';
      default:
        if (provider.isEmpty) {
          return 'Unknown';
        }
        return '${provider[0].toUpperCase()}${provider.substring(1)}';
    }
  }
}

class _VisualStudioImageRoute {
  const _VisualStudioImageRoute({
    required this.providerLabel,
    required this.modelLabel,
    required this.backendLabel,
    required this.keySourceLabel,
    required this.hasDirectApiKey,
    this.apiKey,
    this.note,
  });

  final String? apiKey;
  final String providerLabel;
  final String modelLabel;
  final String backendLabel;
  final String keySourceLabel;
  final bool hasDirectApiKey;
  final String? note;

  String displayKeySourceLabelFor(ImageGenerationBackend backend) {
    if (backend == ImageGenerationBackend.openRouter) {
      return keySourceLabel;
    }
    if (hasDirectApiKey) {
      return keySourceLabel;
    }
    return keySourceLabel;
  }
}

class _RouteChip extends StatelessWidget {
  const _RouteChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
