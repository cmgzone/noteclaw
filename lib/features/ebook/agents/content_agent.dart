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

  String _projectVoice(EbookProject project) {
    final audience = project.targetAudience.trim();
    if (audience.isEmpty) {
      return 'clear, credible, and engaging for a broad audience';
    }

    return 'clear, credible, engaging, and well-paced for $audience';
  }

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
You are a developmental editor designing a strong nonfiction ebook.

Title: ${project.title}
Topic: ${project.topic}
Target Audience: ${project.targetAudience}
Desired voice: ${_projectVoice(project)}

Research Context:
$researchSummary

Create a chapter plan with 6-8 chapters that:
- moves from foundations to deeper insight or practical application
- avoids overlap between chapters
- gives each chapter a distinct reader outcome
- feels specific to the research context instead of generic

Each line must follow this exact format:
1. [Chapter Title]: [1-2 sentence chapter brief]

In each chapter brief, include:
- what the reader will learn
- the key angle, tension, or question the chapter covers
- the most useful examples or evidence to highlight

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
    final authorLine = project.branding.authorName.trim().isEmpty
        ? ''
        : 'Author voice reference: ${project.branding.authorName.trim()}\n';
    final prompt = '''
You are an expert nonfiction author writing a polished ebook chapter.

Book Title: ${project.title}
Audience: ${project.targetAudience}
Tone: ${_projectVoice(project)}
$authorLine

Research Context:
$researchSummary

Chapter Description:
${chapter.content}

Write a chapter that is substantive, well-structured, and clearly grounded in the research context.

Requirements:
- Write in Markdown.
- Do not include the chapter title at the top; the app adds it separately.
- Open with a strong hook or framing paragraph.
- Use 4-6 meaningful section headings.
- Explain ideas with concrete examples, comparisons, or scenarios when helpful.
- Use bullets only when they improve clarity.
- End with a short takeaway or recap section.
- Aim for roughly 900-1400 words unless the material clearly needs less.

Quality bar:
- Avoid filler, repetition, and vague generalities.
- Do not invent facts, quotes, or statistics.
- If the source material is uncertain, write carefully and acknowledge nuance.
- Make the chapter feel purposeful and readable, not like raw model output.
''';

    return await _generateContent(prompt, model: project.selectedModel);
  }
}

final contentAgentProvider = Provider<ContentAgent>((ref) => ContentAgent(ref));
