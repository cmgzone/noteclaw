import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';
import 'infographic.dart';
import '../sources/source_provider.dart';
import '../notebook/notebook_chat_context_builder.dart';
import '../../core/ai/gemini_image_service.dart';
import '../../core/api/api_service.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/security/global_credentials_service.dart';
import '../../core/services/activity_logger_service.dart';

/// Provider for managing infographics
class InfographicNotifier extends StateNotifier<List<Infographic>> {
  final Ref ref;

  InfographicNotifier(this.ref) : super([]) {
    _loadInfographics();
  }

  Future<void> _loadInfographics() async {
    try {
      final api = ref.read(apiServiceProvider);
      final infoData = await api.getInfographics();
      state = infoData.map((j) => Infographic.fromBackendJson(j)).toList();
    } catch (e) {
      debugPrint('Error loading infographics: $e');
      state = [];
    }
  }

  /// Get infographics for a specific source
  List<Infographic> getInfographicsForSource(String sourceId) {
    return state.where((info) => info.sourceId == sourceId).toList();
  }

  /// Get infographics for a specific notebook
  List<Infographic> getInfographicsForNotebook(String notebookId) {
    return state.where((info) => info.notebookId == notebookId).toList();
  }

  /// Add a new infographic
  Future<void> addInfographic(Infographic infographic) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.saveInfographic(
        title: infographic.title,
        notebookId: infographic.notebookId,
        sourceId: infographic.sourceId,
        imageUrl: infographic.imageUrl,
        imageBase64: infographic.imageBase64,
        style: infographic.style.name,
      );
      // Immediately add to state for instant UI update
      state = [infographic, ...state];
      // Then reload from backend to get server-generated IDs
      await _loadInfographics();
    } catch (e) {
      debugPrint('Error adding infographic: $e');
      rethrow; // Rethrow so the UI can show the error
    }
  }

  /// Delete an infographic
  Future<void> deleteInfographic(String id) async {
    // Current backend doesn't have deleteInfographic yet
    // state = state.where((info) => info.id != id).toList();
    await _loadInfographics();
  }

  /// Generate infographic description from source using AI
  /// This generates a description that can be used with an image generation API
  Future<String> generateInfographicPrompt({
    required String sourceId,
    InfographicStyle style = InfographicStyle.modern,
  }) async {
    // Get source
    final sources = ref.read(sourceProvider);
    final source = sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('Source not found'),
    );

    final styleDescriptions = {
      InfographicStyle.modern:
          'Clean, modern design with gradients and rounded shapes',
      InfographicStyle.minimal:
          'Minimalist design with simple icons and lots of whitespace',
      InfographicStyle.colorful:
          'Vibrant, colorful design with bold graphics and contrasts',
      InfographicStyle.professional:
          'Corporate, professional design with charts and data visualization',
      InfographicStyle.playful:
          'Fun, playful design with illustrations and hand-drawn elements',
    };
    final sourceContext =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: [source],
      objective:
          'Create an infographic image prompt that visualizes the most important concepts, facts, and relationships from this source.',
    );

    final prompt = '''
Create a detailed image generation prompt for an infographic.
The infographic should summarize the key concepts from the following content:

CONTENT:
$sourceContext

STYLE: ${styleDescriptions[style]}

Generate a prompt suitable for DALL-E or similar image generation AI.
The prompt should describe:
1. Layout (vertical/horizontal sections)
2. Key data points or concepts to visualize
3. Icons and graphics to include
4. Color scheme
5. Typography style

Return ONLY the image generation prompt, no other text.
''';

    return await _callAI(prompt);
  }

  Future<({String? imageUrl, String? imageBase64})> generateInfographicImage({
    required String prompt,
  }) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final provider = settings.provider;
    final model = settings.model;
    final creds = ref.read(globalCredentialsServiceProvider);

    String? apiKey;
    if (provider == 'openrouter') {
      apiKey = await creds.getApiKey('openrouter');
    } else {
      apiKey = await creds.getApiKey('gemini');
    }

    final imageService = GeminiImageService(apiKey: apiKey);
    final generatedImage = await imageService.generateImage(
      prompt,
      provider: provider,
      model: model,
    );

    return _normalizeGeneratedImage(generatedImage);
  }

  Future<
      ({
        String prompt,
        String? imageUrl,
        String? imageBase64,
        bool isHtmlFallback,
      })> generateInfographicAsset({
    required String sourceId,
    required String title,
    required InfographicStyle style,
  }) async {
    final prompt = await generateInfographicPrompt(
      sourceId: sourceId,
      style: style,
    );

    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    if (settings.provider != 'openrouter') {
      final html = await generateInfographicHtml(
        sourceId: sourceId,
        title: title,
        style: style,
      );
      return (
        prompt: prompt,
        imageUrl: _htmlToDataUrl(html),
        imageBase64: null,
        isHtmlFallback: true,
      );
    }

    try {
      final image = await generateInfographicImage(prompt: prompt);
      if (_looksLikePlaceholderImage(
        imageUrl: image.imageUrl,
        imageBase64: image.imageBase64,
      )) {
        final html = await generateInfographicHtml(
          sourceId: sourceId,
          title: title,
          style: style,
        );
        return (
          prompt: prompt,
          imageUrl: _htmlToDataUrl(html),
          imageBase64: null,
          isHtmlFallback: true,
        );
      }

      return (
        prompt: prompt,
        imageUrl: image.imageUrl,
        imageBase64: image.imageBase64,
        isHtmlFallback: false,
      );
    } catch (_) {
      final html = await generateInfographicHtml(
        sourceId: sourceId,
        title: title,
        style: style,
      );
      return (
        prompt: prompt,
        imageUrl: _htmlToDataUrl(html),
        imageBase64: null,
        isHtmlFallback: true,
      );
    }
  }

  /// Create infographic with generated or provided image
  Future<Infographic> createInfographic({
    required String sourceId,
    required String notebookId,
    required String title,
    String? imageUrl,
    String? imageBase64,
    InfographicStyle style = InfographicStyle.modern,
  }) async {
    final infographic = Infographic(
      id: const Uuid().v4(),
      title: title,
      sourceId: sourceId,
      notebookId: notebookId,
      imageUrl: imageUrl,
      imageBase64: imageBase64,
      style: style,
      createdAt: DateTime.now(),
    );

    await addInfographic(infographic);

    // Log activity to social feed
    ref.read(activityLoggerProvider).logInfographicCreated(
          title,
          infographic.id,
        );

    return infographic;
  }

  Future<String> generateInfographicHtml({
    required String sourceId,
    required String title,
    required InfographicStyle style,
  }) async {
    final sources = ref.read(sourceProvider);
    final source = sources.firstWhere(
      (s) => s.id == sourceId,
      orElse: () => throw Exception('Source not found'),
    );

    final styleDescriptions = {
      InfographicStyle.modern:
          'bold modern editorial design with cards, gradients, and clean hierarchy',
      InfographicStyle.minimal:
          'minimal layout with restrained color, generous spacing, and strong typography',
      InfographicStyle.colorful:
          'color-rich visual storytelling with contrasting panels and vivid highlights',
      InfographicStyle.professional:
          'professional information design with executive-summary clarity and polished charts/cards',
      InfographicStyle.playful:
          'playful magazine-style storytelling with expressive sections and friendly visual cues',
    };

    final sourceContext =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: [source],
      objective:
          'Create a standalone HTML infographic for "$title" using the ${style.name} style. Highlight the most important concepts, facts, and relationships.',
    );

    final prompt = '''
Create a single self-contained HTML infographic page.
Return ONLY valid HTML with inline CSS. No markdown fences. No explanations.

Requirements:
- Use semantic HTML with a polished infographic layout
- Inline CSS only, no external assets, fonts, scripts, or network requests
- Responsive design that looks good on mobile and desktop
- Clear title, section headers, callout cards, and concise supporting text
- Use the "${styleDescriptions[style]}" visual direction
- Prefer clean sections, stat cards, comparison blocks, timelines, or concept maps when helpful
- Keep text grounded strictly in the provided source material

TITLE:
$title

SOURCE MATERIAL:
$sourceContext
''';

    final response = await _callAI(prompt);
    return _extractHtmlDocument(response, title);
  }

  ({String? imageUrl, String? imageBase64}) _normalizeGeneratedImage(
    String image,
  ) {
    final trimmed = image.trim();
    if (trimmed.isEmpty) {
      return (imageUrl: null, imageBase64: null);
    }

    if (trimmed.startsWith('data:image/')) {
      final commaIndex = trimmed.indexOf(',');
      if (commaIndex != -1 && commaIndex + 1 < trimmed.length) {
        return (
          imageUrl: null,
          imageBase64: trimmed.substring(commaIndex + 1),
        );
      }
    }

    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=\s]+$');
    if (base64Pattern.hasMatch(trimmed) && !trimmed.startsWith('http')) {
      return (
        imageUrl: null,
        imageBase64: trimmed.replaceAll(RegExp(r'\s+'), ''),
      );
    }

    return (imageUrl: trimmed, imageBase64: null);
  }

  bool _looksLikePlaceholderImage({
    String? imageUrl,
    String? imageBase64,
  }) {
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      return false;
    }
    if (imageUrl == null || imageUrl.isEmpty) {
      return true;
    }
    return imageUrl.startsWith('data:image/svg+xml;base64,');
  }

  String _htmlToDataUrl(String html) {
    return Uri.dataFromString(
      html,
      mimeType: 'text/html',
      encoding: utf8,
    ).toString();
  }

  String _extractHtmlDocument(String response, String title) {
    final fencedMatch = RegExp(
      r'```html\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(response);
    if (fencedMatch != null) {
      return fencedMatch.group(1)!.trim();
    }

    final doctypeMatch = RegExp(
      r'<!DOCTYPE html[\s\S]*</html>',
      caseSensitive: false,
    ).firstMatch(response);
    if (doctypeMatch != null) {
      return doctypeMatch.group(0)!.trim();
    }

    final htmlMatch = RegExp(
      r'<html[\s\S]*</html>',
      caseSensitive: false,
    ).firstMatch(response);
    if (htmlMatch != null) {
      return htmlMatch.group(0)!.trim();
    }

    final escaped = const HtmlEscape().convert(response.trim());
    final safeTitle = const HtmlEscape().convert(title);
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$safeTitle</title>
  <style>
    :root {
      color-scheme: light;
      --bg: #f4efe5;
      --card: #fffaf2;
      --ink: #1d2a33;
      --muted: #56636f;
      --accent: #c7692d;
      --line: #dfd2bf;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      padding: 24px;
      background: linear-gradient(180deg, #f7f2e8 0%, #efe4d2 100%);
      color: var(--ink);
      font-family: Georgia, "Times New Roman", serif;
    }
    .wrap {
      max-width: 960px;
      margin: 0 auto;
      background: var(--card);
      border: 1px solid var(--line);
      border-radius: 24px;
      overflow: hidden;
      box-shadow: 0 24px 60px rgba(29, 42, 51, 0.12);
    }
    header {
      padding: 32px;
      background: linear-gradient(135deg, var(--accent) 0%, #df8c52 100%);
      color: white;
    }
    main {
      padding: 28px;
    }
    h1 { margin: 0 0 8px; }
    p { margin: 0; }
    pre {
      margin: 0;
      white-space: pre-wrap;
      font: 500 15px/1.6 Consolas, monospace;
      color: var(--muted);
    }
  </style>
</head>
<body>
  <div class="wrap">
    <header>
      <h1>$safeTitle</h1>
      <p>HTML fallback infographic</p>
    </header>
    <main>
      <pre>$escaped</pre>
    </main>
  </div>
</body>
</html>
''';
  }

  Future<String> _callAI(String prompt) async {
    try {
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final model = settings.model;

      if (model == null || model.isEmpty) {
        throw Exception(
            'No AI model selected. Please configure a model in settings.');
      }

      debugPrint(
          '[InfographicProvider] Using AI provider: ${settings.provider}, model: $model');

      // Use Backend Proxy (Admin's API keys)
      final apiService = ref.read(apiServiceProvider);
      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      return await apiService.chatWithAI(
        messages: messages,
        provider: settings.provider,
        model: model,
      );
    } catch (e) {
      debugPrint('[InfographicProvider] AI call failed: $e');
      rethrow;
    }
  }
}

final infographicProvider =
    StateNotifierProvider<InfographicNotifier, List<Infographic>>((ref) {
  return InfographicNotifier(ref);
});
