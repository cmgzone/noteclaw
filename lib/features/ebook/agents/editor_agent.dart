import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/ai_settings_service.dart';
import '../../../core/api/api_service.dart';

class EditorAgent {
  final Ref ref;

  EditorAgent(this.ref);

  Future<String> _generateContent(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.model;

    if (model == null || model.isEmpty) {
      throw Exception(
          'No AI model selected. Please configure a model in settings.');
    }

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
  }

  Future<String> refineText(String text, String instruction) async {
    try {
      final prompt = '''
You are an expert Editor Agent.
Instruction: $instruction
Original Text:
"$text"

Rewrite the text following the instruction.

Rules:
- Maintain the core meaning and all grounded facts.
- Preserve existing Markdown headings, lists, and structure unless the instruction says otherwise.
- Improve clarity, rhythm, transitions, and readability.
- Remove repetition and generic filler.
- Do not add fabricated details.

Return ONLY the rewritten text.
''';

      return await _generateContent(prompt);
    } catch (e) {
      return text; // Fallback to original
    }
  }
}

final editorAgentProvider = Provider<EditorAgent>((ref) => EditorAgent(ref));
