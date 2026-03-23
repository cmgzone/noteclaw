import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ai/gemini_service.dart';
import '../ai/gemini_image_service.dart';
import '../ai/openrouter_service.dart';
import '../../features/sources/source_provider.dart';
import '../../features/notebook/notebook_provider.dart';
import '../../core/security/ai_api_key_resolver.dart';
import '../../features/ebook/ebook_provider.dart';
import '../../features/ebook/models/ebook_project.dart';
import '../../features/ebook/models/branding_config.dart';
import 'package:uuid/uuid.dart';
import '../../core/ai/ai_settings_service.dart';

final voiceActionHandlerProvider = Provider<VoiceActionHandler>((ref) {
  return VoiceActionHandler(ref);
});

class VoiceActionResult {
  final String response;
  final bool actionPerformed;
  final String? actionType;
  final String? imageUrl;

  VoiceActionResult({
    required this.response,
    this.actionPerformed = false,
    this.actionType,
    this.imageUrl,
  });
}

class VoiceActionHandler {
  final Ref ref;
  VoiceActionHandler(this.ref);

  /// Generate AI content using the user's selected provider (OpenRouter or Gemini)
  Future<String> _generateAIContent(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.model;

    if (model == null || model.isEmpty) {
      throw Exception(
          'No AI model selected. Please configure a model in settings.');
    }

    if (settings.provider == 'openrouter') {
      final resolvedKey = await ref
          .read(aiApiKeyResolverProvider)
          .resolveForService('openrouter');
      final apiKey = resolvedKey.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception(
            'OpenRouter API key not configured. Please add it in settings.');
      }
      return await OpenRouterService()
          .generateContent(prompt, model: model, apiKey: apiKey);
    } else {
      final resolvedKey = await ref
          .read(aiApiKeyResolverProvider)
          .resolveForService('gemini');
      final apiKey = resolvedKey.apiKey;
      if (apiKey == null || apiKey.isEmpty) {
        throw Exception(
            'Gemini API key not configured. Please add it in settings.');
      }
      return await GeminiService(apiKey: apiKey)
          .generateContent(prompt, model: model);
    }
  }

  Future<GeminiImageService> _getImageService() async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final resolvedKey = await ref
        .read(aiApiKeyResolverProvider)
        .resolveForProvider(settings.provider);
    return GeminiImageService(apiKey: resolvedKey.apiKey);
  }

  Future<VoiceActionResult> processUserInput(
    String userText,
    List<String> conversationHistory,
  ) async {
    // Fast keyword-based intent detection first (no AI call needed)
    final fastIntent = _detectIntentFast(userText);

    if (fastIntent['action'] != 'conversation') {
      // Handle action directly without AI intent detection
      switch (fastIntent['action']) {
        case 'create_note':
          return await _createNote(userText, fastIntent);
        case 'search_sources':
          return await _searchSources(userText, fastIntent);
        case 'list_sources':
          return await _listSources();
        case 'create_notebook':
          return await _createNotebook(userText, fastIntent);
        case 'list_notebooks':
          return await _listNotebooks();
        case 'get_summary':
          return await _getSummary();
        case 'generate_image':
          return await _generateImage(userText, fastIntent);
        case 'create_ebook':
          return await _createEbook(userText, fastIntent);
      }
    }

    // For conversation, respond directly without intent detection
    return await _handleConversation(userText, conversationHistory);
  }

  /// Fast keyword-based intent detection - no AI call needed
  Map<String, dynamic> _detectIntentFast(String userText) {
    final text = userText.toLowerCase().trim();

    // Create note patterns
    if (_matchesAny(text, [
      'create a note',
      'save a note',
      'write a note',
      'make a note',
      'add a note',
      'new note'
    ])) {
      final content = _extractAfter(
          text, ['about', 'called', 'titled', 'saying', 'that says']);
      return {
        'action': 'create_note',
        'title': content.isNotEmpty
            ? _capitalize(content.split(' ').take(5).join(' '))
            : 'Voice Note',
        'content': content.isNotEmpty ? content : userText,
      };
    }

    // Search patterns
    if (_matchesAny(
        text, ['search for', 'find', 'look for', 'search my', 'query'])) {
      final query = _extractAfter(
          text, ['search for', 'find', 'look for', 'search my', 'query']);
      return {
        'action': 'search_sources',
        'query': query.isNotEmpty ? query : userText,
      };
    }

    // List sources
    if (_matchesAny(text,
        ['list my sources', 'show my sources', 'what sources', 'my sources'])) {
      return {'action': 'list_sources'};
    }

    // Create notebook
    if (_matchesAny(text, [
      'create a notebook',
      'new notebook',
      'make a notebook',
      'add a notebook'
    ])) {
      final title = _extractAfter(text, ['called', 'named', 'titled']);
      return {
        'action': 'create_notebook',
        'title': title.isNotEmpty ? _capitalize(title) : 'New Notebook',
      };
    }

    // List notebooks
    if (_matchesAny(text, [
      'list my notebooks',
      'show my notebooks',
      'what notebooks',
      'my notebooks'
    ])) {
      return {'action': 'list_notebooks'};
    }

    // Summary
    if (_matchesAny(
        text, ['summarize', 'summary', 'give me a summary', 'summarise'])) {
      return {'action': 'get_summary'};
    }

    // Generate image
    if (_matchesAny(text, [
      'generate an image',
      'create an image',
      'make an image',
      'draw',
      'generate image',
      'create image'
    ])) {
      final prompt =
          _extractAfter(text, ['of', 'showing', 'with', 'that shows']);
      return {
        'action': 'generate_image',
        'content': prompt.isNotEmpty ? prompt : userText,
      };
    }

    // Create ebook
    if (_matchesAny(text, [
      'create an ebook',
      'write an ebook',
      'make an ebook',
      'new ebook',
      'create ebook'
    ])) {
      final topic = _extractAfter(text, ['about', 'on', 'called', 'titled']);
      return {
        'action': 'create_ebook',
        'title': topic.isNotEmpty
            ? _capitalize(topic.split(' ').take(5).join(' '))
            : 'New Ebook',
        'content': topic.isNotEmpty ? topic : 'General Topic',
      };
    }

    // Default to conversation
    return {'action': 'conversation'};
  }

  bool _matchesAny(String text, List<String> patterns) {
    return patterns.any((p) => text.contains(p));
  }

  String _extractAfter(String text, List<String> keywords) {
    for (final keyword in keywords) {
      final index = text.indexOf(keyword);
      if (index != -1) {
        return text.substring(index + keyword.length).trim();
      }
    }
    return '';
  }

  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  Future<VoiceActionResult> _createNote(
    String userText,
    Map<String, dynamic> intent,
  ) async {
    try {
      final title = intent['title'] as String? ?? 'Voice Note';
      final content = intent['content'] as String? ?? userText;

      await ref.read(sourceProvider.notifier).addSource(
            title: title,
            type: 'text',
            content: content,
          );

      return VoiceActionResult(
        response: 'I\'ve saved your note titled "$title" to your sources.',
        actionPerformed: true,
        actionType: 'create_note',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t save the note. Please try again.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _searchSources(
    String userText,
    Map<String, dynamic> intent,
  ) async {
    try {
      final query = intent['query'] as String? ?? userText;
      final sources = ref.read(sourceProvider);

      final matches = sources.where((source) {
        final searchText = '${source.title} ${source.content}'.toLowerCase();
        return searchText.contains(query.toLowerCase());
      }).toList();

      if (matches.isEmpty) {
        return VoiceActionResult(
          response: 'I couldn\'t find any sources matching "$query".',
          actionPerformed: true,
          actionType: 'search_sources',
        );
      }

      final summary = matches.take(3).map((s) => s.title).join(', ');
      return VoiceActionResult(
        response:
            'I found ${matches.length} sources. The top matches are: $summary',
        actionPerformed: true,
        actionType: 'search_sources',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I had trouble searching your sources.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _listSources() async {
    try {
      final sources = ref.read(sourceProvider);

      if (sources.isEmpty) {
        return VoiceActionResult(
          response: 'You don\'t have any sources yet.',
          actionPerformed: true,
          actionType: 'list_sources',
        );
      }

      final count = sources.length;
      final types = sources.map((s) => s.type).toSet();

      return VoiceActionResult(
        response:
            'You have $count sources including ${types.join(', ')} types.',
        actionPerformed: true,
        actionType: 'list_sources',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t retrieve your sources.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _createNotebook(
    String userText,
    Map<String, dynamic> intent,
  ) async {
    try {
      final title = intent['title'] as String? ?? 'New Notebook';

      await ref.read(notebookProvider.notifier).addNotebook(title);

      return VoiceActionResult(
        response: 'I\'ve created a new notebook called "$title".',
        actionPerformed: true,
        actionType: 'create_notebook',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t create the notebook.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _listNotebooks() async {
    try {
      final notebooks = ref.read(notebookProvider);

      if (notebooks.isEmpty) {
        return VoiceActionResult(
          response: 'You don\'t have any notebooks yet.',
          actionPerformed: true,
          actionType: 'list_notebooks',
        );
      }

      final names = notebooks.take(5).map((n) => n.title).join(', ');
      return VoiceActionResult(
        response:
            'You have ${notebooks.length} notebooks. Here are some: $names',
        actionPerformed: true,
        actionType: 'list_notebooks',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t retrieve your notebooks.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _getSummary() async {
    try {
      final sources = ref.read(sourceProvider);

      if (sources.isEmpty) {
        return VoiceActionResult(
          response: 'You don\'t have any sources to summarize yet.',
          actionPerformed: true,
          actionType: 'get_summary',
        );
      }

      final recentSources = sources.take(5).toList();
      final context = recentSources
          .map((s) =>
              '${s.title}: ${s.content.substring(0, s.content.length > 200 ? 200 : s.content.length)}')
          .join('\n\n');

      final summaryPrompt = '''
Provide a brief spoken summary of these sources in 2-3 sentences:

$context
''';

      final summary = await _generateAIContent(summaryPrompt);

      return VoiceActionResult(
        response: summary,
        actionPerformed: true,
        actionType: 'get_summary',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t generate a summary.',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _handleConversation(
    String userText,
    List<String> conversationHistory,
  ) async {
    try {
      final contextPrompt = '''
You are a helpful AI voice assistant for a notebook app.
Keep responses concise and conversational.
No markdown formatting - this will be spoken aloud.

Previous conversation:
${conversationHistory.take(10).join('\n')}

User: $userText

Respond naturally and helpfully:
''';

      final response = await _generateAIContent(contextPrompt);

      return VoiceActionResult(
        response: response,
        actionPerformed: false,
      );
    } catch (e) {
      debugPrint('Voice conversation error: $e');
      // Provide more helpful error message
      String errorMessage = 'Sorry, I had trouble processing that.';
      final errorStr = e.toString().toLowerCase();
      if (errorStr.contains('api key') || errorStr.contains('not configured')) {
        errorMessage = 'Please configure your AI API key in settings.';
      } else if (errorStr.contains('network') ||
          errorStr.contains('connection') ||
          errorStr.contains('socket')) {
        errorMessage = 'Please check your internet connection and try again.';
      } else if (errorStr.contains('quota') || errorStr.contains('rate')) {
        errorMessage =
            'API rate limit reached. Please wait a moment and try again.';
      }
      return VoiceActionResult(
        response: errorMessage,
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _generateImage(
    String userText,
    Map<String, dynamic> intent,
  ) async {
    try {
      final prompt = intent['content'] as String? ?? userText;

      // Use AI to enhance the prompt for better image generation
      final enhancedPrompt = await _generateAIContent('''
Convert this user request into a detailed, vivid image generation prompt (max 2 sentences):
"$prompt"

Return only the enhanced prompt, nothing else.
''');

      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final imageGen = await _getImageService();
      final imageUrl = await imageGen.generateImage(
        enhancedPrompt.trim(),
        provider: settings.provider,
        model: settings.model,
      );

      return VoiceActionResult(
        response: 'I\'ve generated your image!',
        actionPerformed: true,
        actionType: 'generate_image',
        imageUrl: imageUrl,
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t generate the image. ${e.toString()}',
        actionPerformed: false,
      );
    }
  }

  Future<VoiceActionResult> _createEbook(
    String userText,
    Map<String, dynamic> intent,
  ) async {
    try {
      final title = intent['title'] as String? ?? 'New Ebook';
      final topic = intent['content'] as String? ?? 'General Topic';

      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final currentModel = settings.model ?? '';

      if (currentModel.isEmpty) {
        throw Exception('No AI model selected for ebook creation');
      }

      final id = const Uuid().v4();
      final now = DateTime.now();
      final ebook = EbookProject(
        id: id,
        title: title,
        topic: topic,
        targetAudience: 'General Audience',
        branding: const BrandingConfig(
          primaryColorValue: 0xFF000000,
          fontFamily: 'Roboto',
        ),
        selectedModel: currentModel,
        createdAt: now,
        updatedAt: now,
        status: EbookStatus.draft,
      );

      await ref.read(ebookProvider.notifier).addEbook(ebook);

      return VoiceActionResult(
        response:
            'I\'ve created a new ebook project titled "$title" about "$topic".',
        actionPerformed: true,
        actionType: 'create_ebook',
      );
    } catch (e) {
      return VoiceActionResult(
        response: 'Sorry, I couldn\'t create the ebook.',
        actionPerformed: false,
      );
    }
  }
}
