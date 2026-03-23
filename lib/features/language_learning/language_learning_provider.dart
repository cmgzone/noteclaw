import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'language_session.dart';
import '../../core/api/api_service.dart';
import '../gamification/gamification_provider.dart';
import '../../core/ai/ai_settings_service.dart';

class LanguageLearningNotifier extends StateNotifier<List<LanguageSession>> {
  final Ref ref;

  LanguageLearningNotifier(this.ref) : super([]) {
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getLanguageSessions();
      state = data
          .map((json) => LanguageSession.fromJson(_convertBackendSession(json)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading language sessions: $e');
      state = [];
    }
  }

  Map<String, dynamic> _convertBackendSession(Map<String, dynamic> raw) {
    return {
      'id': raw['id'],
      'targetLanguage': raw['target_language'],
      'nativeLanguage': raw['native_language'],
      'proficiency': raw['proficiency'],
      'topic': raw['topic'],
      'messages': raw['messages'] is String
          ? jsonDecode(raw['messages'])
          : (raw['messages'] ?? []),
      'createdAt': raw['created_at'],
      'updatedAt': raw['updated_at'],
    };
  }

  Future<void> _saveSession(LanguageSession session) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.createLanguageSession({
        'id': session.id,
        'targetLanguage': session.targetLanguage,
        'nativeLanguage': session.nativeLanguage,
        'proficiency': session.proficiency.name,
        'topic': session.topic,
        'messages': session.messages.map((m) => m.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('Error saving language session: $e');
    }
  }

  LanguageSession? getSession(String id) {
    try {
      return state.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<LanguageSession> startSession({
    required String targetLanguage,
    String nativeLanguage = 'English',
    LanguageProficiency proficiency = LanguageProficiency.beginner,
    String? topic,
  }) async {
    final session = LanguageSession(
      targetLanguage: targetLanguage,
      nativeLanguage: nativeLanguage,
      proficiency: proficiency,
      topic: topic,
    );

    state = [session, ...state];
    await _saveSession(session);

    // Generate initial greeting
    await _generateTutorResponse(session.id, isInitial: true);

    return ref.read(languageLearningProvider.notifier).getSession(session.id)!;
  }

  Future<void> sendMessage(String sessionId, String content) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final userMessage = LanguageMessage(
      role: LanguageRole.user,
      content: content,
    );

    final updatedSession = session.copyWith(
      messages: [...session.messages, userMessage],
    );
    await _updateSession(updatedSession);

    // Gamification
    ref.read(gamificationProvider.notifier).trackLanguageMessageSent();

    await _generateTutorResponse(sessionId);
  }

  Future<void> completeSession(String sessionId) async {
    // In the future we could mark the session as archived/completed in the model
    await ref
        .read(gamificationProvider.notifier)
        .trackLanguageSessionCompleted();
  }

  Future<void> _updateSession(LanguageSession session) async {
    final index = state.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      state = [...state]..[index] = session;
      await _saveSession(session);
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteLanguageSession(id);
      state = state.where((s) => s.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting language session: $e');
    }
  }

  Future<void> _generateTutorResponse(String sessionId,
      {bool isInitial = false}) async {
    final session = getSession(sessionId);
    if (session == null) return;

    final prompt = _buildPrompt(session, isInitial);

    try {
      final response = await _callAI(prompt);
      final parsed = _parseResponse(response);

      final tutorMessage = LanguageMessage(
        role: LanguageRole.tutor,
        content: parsed['content'] ?? response,
        translation: parsed['translation'],
        correction: parsed['correction'],
        pronunciation: parsed['pronunciation'],
      );

      final updatedSession = session.copyWith(
        messages: [...session.messages, tutorMessage],
      );
      await _updateSession(updatedSession);
    } catch (e) {
      debugPrint('Error generating language response: $e');
      // Add error message as system message or handle gracefully
    }
  }

  String _buildPrompt(LanguageSession session, bool isInitial) {
    final history = session.messages.map((m) {
      return '${m.role.name.toUpperCase()}: ${m.content}';
    }).join('\n');

    final topicContext = session.topic != null
        ? 'Focus on the topic: "${session.topic}".'
        : 'General conversation.';

    return '''
You are an expert language tutor teaching ${session.targetLanguage} to a ${session.nativeLanguage} speaker.
Student Proficiency: ${session.proficiency.name}
$topicContext

ROLE:
1. Converse primarily in ${session.targetLanguage}.
2. Adjust complexity to the student's proficiency level (${session.proficiency.name}).
3. Provide helpful corrections if the student makes mistakes.
4. Provide translations to ${session.nativeLanguage} for difficult phrases.
5. Provide pronunciation guides (IPA or phonetic) for new words.

${isInitial ? 'Start the conversation with a friendly greeting and a question about the topic.' : 'Continue the conversation naturally.'}

Respond with a JSON object:
{
  "content": "Your response in ${session.targetLanguage}",
  "translation": "Translation in ${session.nativeLanguage}",
  "correction": "Correction of student's last message (if applicable, otherwise null)",
  "pronunciation": "Phonetic guide for key words (optional)"
}

CONVERSATION HISTORY:
$history
''';
  }

  Map<String, dynamic> _parseResponse(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!);
      }
    } catch (e) {
      debugPrint('Error parsing JSON response: $e');
    }
    return {'content': response};
  }

  Future<String> _callAI(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.getEffectiveModel();

    // Use Backend Proxy (Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': prompt}
    ];

    return await apiService.chatWithAI(
      messages: messages,
      provider: settings.provider,
      model: model,
      billingFeature: 'chat_message',
    );
  }
}

final languageLearningProvider =
    StateNotifierProvider<LanguageLearningNotifier, List<LanguageSession>>(
        (ref) {
  return LanguageLearningNotifier(ref);
});
