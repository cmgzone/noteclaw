import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/ai_settings_service.dart';
import '../../../core/api/api_service.dart';

class ResearchAgent {
  final Ref ref;

  ResearchAgent(this.ref);

  Future<String> _generateContent(String prompt, {String? model}) async {
    // Determine provider and model
    String provider;
    String targetModel;

    if (model != null && model.isNotEmpty) {
      // Use the model selected for this specific project
      // Check if it looks like an OpenRouter model ID (usually vendor/model)
      // or definitely isn't a known Google model
      final isOpenRouterParams = model.contains('/') ||
          model.startsWith('openai/') ||
          model.startsWith('anthropic/') ||
          model.startsWith('deepseek/');

      if (isOpenRouterParams) {
        provider = 'openrouter';
        targetModel = model;
      } else {
        provider = 'gemini';
        targetModel = model;
      }
    } else {
      // Fallback to global settings
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      provider = settings.provider;
      targetModel = settings.getEffectiveModel();
    }

    // Use Backend Proxy (Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': prompt}
    ];

    return await apiService.chatWithAI(
      messages: messages,
      provider: provider,
      model: targetModel,
      receiveTimeout: const Duration(minutes: 3),
      sendTimeout: const Duration(minutes: 2),
    );
  }

  Future<String> researchTopic(String topic,
      {List<String> context = const [],
      String? notebookId,
      String? model}) async {
    try {
      String sourceContext = context.join('\n\n');

      // Note: Source fetching is handled by EbookOrchestrator before calling this method
      // The orchestrator passes sources via the context parameter

      final prompt = '''
You are a Research Agent tasked with gathering key information for an ebook about: "$topic".

Existing Context (from User's Notebook):
$sourceContext

Please provide a comprehensive summary of key facts, important dates, main concepts, and interesting details that should be included in this ebook. 
Focus on accuracy and depth, prioritizing the provided context.
''';

      return await _generateContent(prompt, model: model);
    } catch (e) {
      return "Research failed: $e";
    }
  }
}

final researchAgentProvider =
    Provider<ResearchAgent>((ref) => ResearchAgent(ref));
