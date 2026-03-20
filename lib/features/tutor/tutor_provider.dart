import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tutor_session.dart';
import '../sources/source_provider.dart';
import '../gamification/gamification_provider.dart';
import '../notebook/notebook_chat_context_builder.dart';
import '../../core/api/api_service.dart';
import '../../core/ai/ai_settings_service.dart';

/// Provider for managing AI Tutor sessions
class TutorNotifier extends StateNotifier<List<TutorSession>> {
  final Ref ref;

  TutorNotifier(this.ref) : super([]) {
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getTutorSessions();
      state = data
          .map((json) => TutorSession.fromJson(_convertBackendSession(json)))
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading tutor sessions: $e');
      state = [];
    }
  }

  Map<String, dynamic> _convertBackendSession(Map<String, dynamic> raw) {
    return {
      'id': raw['id'],
      'notebookId': raw['notebook_id'],
      'sourceId': raw['source_id'],
      'topic': raw['topic'],
      'style': raw['style'],
      'difficulty': raw['difficulty'],
      'totalScore': raw['total_score'] ?? 0,
      'exchanges': raw['exchanges'] is String
          ? jsonDecode(raw['exchanges'])
          : (raw['exchanges'] ?? []),
      'summary': raw['summary'],
      'createdAt': raw['created_at'],
      'updatedAt': raw['updated_at'],
    };
  }

  Future<void> _saveSession(TutorSession session) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.createTutorSession({
        'id': session.id,
        'notebookId': session.notebookId,
        'sourceId': session.sourceId,
        'topic': session.topic,
        'style': session.style.name,
        'difficulty': session.difficulty.name,
        'exchanges': session.exchanges.map((e) => e.toJson()).toList(),
        'exchangeCount': session.exchanges.length,
      });
    } catch (e) {
      debugPrint('Error saving tutor session: $e');
      rethrow; // Rethrow so the UI can show the error
    }
  }

  List<TutorSession> getSessionsForNotebook(String notebookId) {
    return state.where((s) => s.notebookId == notebookId).toList();
  }

  TutorSession? getSession(String id) {
    try {
      return state.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<TutorSession> startSession({
    required String notebookId,
    required String topic,
    String? sourceId,
    TutorDifficulty difficulty = TutorDifficulty.adaptive,
    TutorStyle style = TutorStyle.socratic,
  }) async {
    final session = TutorSession(
      notebookId: notebookId,
      sourceId: sourceId,
      topic: topic,
      difficulty: difficulty,
      style: style,
    );

    state = [session, ...state];
    await _saveSession(session);

    return session;
  }

  Future<void> updateSession(TutorSession session) async {
    final index = state.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      state = [...state]..[index] = session;
      await _saveSession(session);
    }
  }

  Future<void> deleteSession(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteTutorSession(id);
      state = state.where((s) => s.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting tutor session: $e');
    }
  }

  /// Generate the next tutor exchange based on session state
  Future<TutorExchange> generateNextExchange(String sessionId) async {
    final session = getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final sources = ref.read(sourceProvider);
    final relevantSources = session.sourceId != null
        ? sources.where((s) => s.id == session.sourceId).toList()
        : sources.where((s) => s.notebookId == session.notebookId).toList();

    if (relevantSources.isEmpty) {
      throw Exception('No sources found for tutoring');
    }

    final sourceContent =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: relevantSources,
      objective:
          'Tutor the user on "${session.topic}" using the ${session.style.displayName} style at ${session.difficulty.displayName} difficulty.',
    );

    final prompt = _buildTutorPrompt(session, sourceContent);
    final response = await _callAI(prompt);
    final exchange = _parseExchange(response);

    final updatedSession = session.copyWith(
      exchanges: [...session.exchanges, exchange],
      questionsAsked: exchange.type == ExchangeType.question
          ? session.questionsAsked + 1
          : session.questionsAsked,
    );

    await updateSession(updatedSession);
    return exchange;
  }

  /// Process user's response and generate feedback
  Future<TutorExchange> processResponse(
    String sessionId,
    String exchangeId,
    String userResponse,
  ) async {
    final session = getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final exchangeIndex =
        session.exchanges.indexWhere((e) => e.id == exchangeId);
    if (exchangeIndex < 0) throw Exception('Exchange not found');

    final exchange = session.exchanges[exchangeIndex];

    final sources = ref.read(sourceProvider);
    final relevantSources = session.sourceId != null
        ? sources.where((s) => s.id == session.sourceId).toList()
        : sources.where((s) => s.notebookId == session.notebookId).toList();

    final sourceContent =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: relevantSources,
      objective:
          'Evaluate a student response about "${session.topic}" and ground the feedback in the most relevant source material.',
    );

    final prompt = _buildFeedbackPrompt(
      session,
      exchange,
      userResponse,
      sourceContent,
    );

    final response = await _callAI(prompt);
    final feedback = _parseFeedback(response);

    // Update the exchange with user response and feedback
    final updatedExchange = exchange.copyWith(
      userResponse: userResponse,
      feedback: feedback['feedback'],
      wasCorrect: feedback['wasCorrect'],
    );

    final updatedExchanges = [...session.exchanges];
    updatedExchanges[exchangeIndex] = updatedExchange;

    final updatedSession = session.copyWith(
      exchanges: updatedExchanges,
      correctAnswers: feedback['wasCorrect'] == true
          ? session.correctAnswers + 1
          : session.correctAnswers,
    );

    await updateSession(updatedSession);
    return updatedExchange;
  }

  /// End the session and generate a summary
  Future<TutorExchange> endSession(String sessionId) async {
    final session = getSession(sessionId);
    if (session == null) throw Exception('Session not found');

    final prompt = _buildSummaryPrompt(session);
    final response = await _callAI(prompt);

    final summaryExchange = TutorExchange(
      type: ExchangeType.summary,
      content: response,
    );

    final updatedSession = session.copyWith(
      exchanges: [...session.exchanges, summaryExchange],
      isComplete: true,
    );

    await updateSession(updatedSession);

    // Track gamification
    ref.read(gamificationProvider.notifier).trackTutorSessionCompleted(
          accuracy: updatedSession.accuracy,
        );
    ref.read(gamificationProvider.notifier).trackFeatureUsed('tutor');

    return summaryExchange;
  }

  String _buildTutorPrompt(TutorSession session, String sourceContent) {
    final styleGuide = _getStyleGuide(session.style);
    final difficultyGuide = _getDifficultyGuide(session.difficulty, session);
    final history = _formatHistory(session.exchanges);

    return '''
You are an expert AI tutor using the ${session.style.displayName} teaching method.
Your goal is to help the student deeply understand: "${session.topic}"

TEACHING STYLE:
$styleGuide

DIFFICULTY LEVEL: ${session.difficulty.displayName}
$difficultyGuide

SOURCE MATERIAL:
$sourceContent

CONVERSATION HISTORY:
$history

Generate the next tutoring exchange. Focus on:
1. Testing understanding through thoughtful questions
2. Building on previous responses
3. Guiding the student to discover answers themselves
4. Being encouraging but accurate

Respond with JSON:
{
  "type": "question|hint|explanation|encouragement",
  "content": "Your message to the student"
}

Keep responses concise but meaningful. Ask ONE clear question at a time.
''';
  }

  String _buildFeedbackPrompt(
    TutorSession session,
    TutorExchange exchange,
    String userResponse,
    String sourceContent,
  ) {
    return '''
You are an AI tutor evaluating a student's response.

TOPIC: ${session.topic}
DIFFICULTY: ${session.difficulty.displayName}

SOURCE MATERIAL:
$sourceContent

TUTOR'S QUESTION:
${exchange.content}

STUDENT'S RESPONSE:
$userResponse

Evaluate the response and provide constructive feedback.
Be encouraging even when correcting mistakes.
If partially correct, acknowledge what's right before addressing gaps.

Respond with JSON:
{
  "wasCorrect": true/false,
  "feedback": "Your feedback message (2-4 sentences)"
}
''';
  }

  String _buildSummaryPrompt(TutorSession session) {
    final history = _formatHistory(session.exchanges);

    return '''
Summarize this tutoring session on "${session.topic}".

SESSION STATS:
- Questions asked: ${session.questionsAsked}
- Correct answers: ${session.correctAnswers}
- Accuracy: ${(session.accuracy * 100).toStringAsFixed(0)}%

CONVERSATION:
$history

Provide a brief, encouraging summary that:
1. Highlights what the student learned well
2. Identifies areas for further study
3. Gives specific recommendations for improvement
4. Ends with encouragement

Keep it to 3-4 paragraphs.
''';
  }

  String _getStyleGuide(TutorStyle style) {
    switch (style) {
      case TutorStyle.socratic:
        return '''
- Ask probing questions that lead to discovery
- Never give direct answers; guide through questioning
- Use "What do you think would happen if...?" style questions
- Build understanding step by step''';
      case TutorStyle.explanatory:
        return '''
- Explain concepts clearly first
- Then test understanding with questions
- Provide examples before asking for application
- Balance teaching with assessment''';
      case TutorStyle.challenge:
        return '''
- Present problems to solve
- Encourage critical thinking
- Ask "why" and "how" questions
- Push for deeper analysis''';
      case TutorStyle.mixed:
        return '''
- Vary between explanation and questioning
- Adapt based on student responses
- Use examples, questions, and challenges
- Keep the session dynamic''';
    }
  }

  String _getDifficultyGuide(TutorDifficulty difficulty, TutorSession session) {
    switch (difficulty) {
      case TutorDifficulty.beginner:
        return 'Use simple language, provide more hints, break down complex ideas.';
      case TutorDifficulty.intermediate:
        return 'Balance challenge with support, expect some prior knowledge.';
      case TutorDifficulty.advanced:
        return 'Ask complex questions, expect detailed answers, minimal hints.';
      case TutorDifficulty.adaptive:
        final accuracy = session.accuracy;
        if (accuracy > 0.8) {
          return 'Student performing well - increase difficulty, ask deeper questions.';
        } else if (accuracy < 0.5 && session.questionsAsked > 2) {
          return 'Student struggling - provide more support and simpler questions.';
        }
        return 'Maintain current difficulty, adjust based on responses.';
    }
  }

  String _formatHistory(List<TutorExchange> exchanges) {
    if (exchanges.isEmpty) return 'No previous exchanges.';

    return exchanges.map((e) {
      final role = e.type == ExchangeType.question ? 'Tutor' : 'Tutor';
      var text = '$role (${e.type.name}): ${e.content}';
      if (e.userResponse != null) {
        text += '\nStudent: ${e.userResponse}';
      }
      if (e.feedback != null) {
        text += '\nFeedback: ${e.feedback}';
      }
      return text;
    }).join('\n\n');
  }

  TutorExchange _parseExchange(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        return TutorExchange(
          type: ExchangeType.question,
          content: response,
        );
      }

      final json = jsonDecode(jsonMatch.group(0)!);
      final typeStr = json['type'] as String? ?? 'question';
      final type = ExchangeType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => ExchangeType.question,
      );

      return TutorExchange(
        type: type,
        content: json['content'] ?? response,
      );
    } catch (e) {
      return TutorExchange(
        type: ExchangeType.question,
        content: response,
      );
    }
  }

  Map<String, dynamic> _parseFeedback(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        return {'wasCorrect': null, 'feedback': response};
      }

      final json = jsonDecode(jsonMatch.group(0)!);
      return {
        'wasCorrect': json['wasCorrect'] as bool?,
        'feedback': json['feedback'] as String? ?? response,
      };
    } catch (e) {
      return {'wasCorrect': null, 'feedback': response};
    }
  }

  Future<String> _callAI(String prompt) async {
    try {
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
    } catch (e) {
      debugPrint('[TutorProvider] AI call failed: $e');
      rethrow;
    }
  }
}

final tutorProvider =
    StateNotifierProvider<TutorNotifier, List<TutorSession>>((ref) {
  return TutorNotifier(ref);
});
