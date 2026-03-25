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
      String? targetAudience,
      String? model}) async {
    try {
      String sourceContext = context.join('\n\n');

      // Note: Source fetching is handled by EbookOrchestrator before calling this method
      // The orchestrator passes sources via the context parameter

      final prompt = '''
You are the lead research agent for a high-quality ebook.

Topic: "$topic"
Target audience: ${targetAudience?.trim().isNotEmpty == true ? targetAudience!.trim() : 'General readers'}

Existing Context (from User's Notebook):
$sourceContext

Create a structured research brief in Markdown with these sections:

## Core Thesis
What the ebook should help the reader understand.

## Must-Include Facts And Examples
Bullet points with the strongest supporting details drawn from the context.

## Key Terms And Concepts
Definitions, frameworks, and recurring ideas the reader must understand.

## Timeline Or Historical Anchors
Important dates, phases, or sequences if they exist.

## Audience Angle
What matters most for this target audience and what level of explanation they need.

## Misconceptions, Nuance, And Cautions
Ambiguities, tradeoffs, and places where the writing should avoid overclaiming.

## Strong Chapter Opportunities
6-10 promising chapter angles or questions the book should cover.

Rules:
- Stay grounded in the provided context.
- Do not invent statistics, quotes, or dates.
- If something is uncertain, say that clearly.
- Favor specific, high-signal details over generic summary.
''';

      return await _generateContent(prompt, model: model);
    } catch (e) {
      return "Research failed: $e";
    }
  }
}

final researchAgentProvider =
    Provider<ResearchAgent>((ref) => ResearchAgent(ref));
