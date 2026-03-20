import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/ai/ai_settings_service.dart';
import '../../../core/api/api_service.dart';
import '../models/ebook_project.dart';
import '../models/ebook_chapter.dart';

class ContentAgent {
  final Ref ref;
  static const Uuid _uuid = Uuid();

  ContentAgent(this.ref);

  Future<String> _generateContent(String prompt, {String? model}) async {
    // Determine provider and model
    String provider;
    String targetModel;

    if (model != null && model.isNotEmpty) {
      // Use the model selected for this specific project
      // Check if it looks like an OpenRouter model ID (usually vendor/model)
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

  Future<List<EbookChapter>> generateOutline(
      EbookProject project, String researchSummary) async {
    final prompt = '''
You are an expert author and editor. Create a detailed chapter outline for an ebook.

Title: ${project.title}
Topic: ${project.topic}
Target Audience: ${project.targetAudience}

Research Context:
$researchSummary

Generate a list of 5-8 chapters. For each chapter, provide a title and a brief description of what it will cover.
Return ONLY the list in this format:
1. [Chapter Title]: [Description]
2. [Chapter Title]: [Description]
...
''';

    final response =
        await _generateContent(prompt, model: project.selectedModel);

    // Parse response into chapters
    final chapters = <EbookChapter>[];
    final lines = response.split('\n');
    int order = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final match = RegExp(r'^\d+\.\s*(.+?):\s*(.+)').firstMatch(line);
      if (match != null) {
        chapters.add(EbookChapter(
          id: _uuid.v4(),
          title: match.group(1)!.trim(),
          content: match.group(2)!.trim(), // Initially just the description
          orderIndex: order++,
        ));
      }
    }

    return chapters;
  }

  Future<String> writeChapter(EbookProject project, EbookChapter chapter,
      String researchSummary) async {
    final prompt = '''
You are an expert author. Write the full content for Chapter ${chapter.orderIndex + 1}: "${chapter.title}".

Book Title: ${project.title}
Audience: ${project.targetAudience}
Tone: Professional yet engaging

Research Context:
$researchSummary

Chapter Description:
${chapter.content}

Write a comprehensive, well-structured chapter in Markdown format. 
Include headings, bullet points, and clear paragraphs. 
Do not include the chapter title at the top (it will be added by the layout).
''';

    return await _generateContent(prompt, model: project.selectedModel);
  }
}

final contentAgentProvider = Provider<ContentAgent>((ref) => ContentAgent(ref));
