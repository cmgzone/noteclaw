import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/ai_settings_service.dart';
import 'package:uuid/uuid.dart';
import 'quiz.dart';
import '../sources/source_provider.dart';
import '../gamification/gamification_provider.dart';
import '../notebook/notebook_chat_context_builder.dart';
import '../../core/api/api_service.dart';
import '../../core/services/activity_logger_service.dart';

/// Provider for managing quizzes
class QuizNotifier extends StateNotifier<List<Quiz>> {
  final Ref ref;

  QuizNotifier(this.ref) : super([]) {
    _loadQuizzes();
  }

  Future<void> _loadQuizzes() async {
    try {
      final api = ref.read(apiServiceProvider);
      final quizzesData = await api.getQuizzes();
      state = quizzesData.map((j) => Quiz.fromBackendJson(j)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading quizzes: $e');
      state = [];
    }
  }

  /// Get quizzes for a specific notebook
  List<Quiz> getQuizzesForNotebook(String notebookId) {
    return state.where((quiz) => quiz.notebookId == notebookId).toList();
  }

  /// Add a new quiz
  Future<void> addQuiz(Quiz quiz) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.createQuiz(
        title: quiz.title,
        notebookId: quiz.notebookId,
        sourceId: quiz.sourceId,
        questions: quiz.questions.map((q) => q.toBackendJson()).toList(),
      );
      // Immediately add to state for instant UI update
      state = [quiz, ...state];
      // Then reload from backend to get server-generated IDs
      await _loadQuizzes();
    } catch (e) {
      debugPrint('Error adding quiz: $e');
      rethrow; // Rethrow so the UI can show the error
    }
  }

  /// Update existing quiz
  Future<void> updateQuiz(Quiz quiz) async {
    await _loadQuizzes();
  }

  /// Delete a quiz
  Future<void> deleteQuiz(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteQuiz(id);
      state = state.where((quiz) => quiz.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting quiz: $e');
    }
  }

  /// Generate quiz from sources using AI
  Future<Quiz> generateFromSources({
    required String notebookId,
    required String title,
    String? sourceId,
    int questionCount = 10,
  }) async {
    // Get source content
    final sources = ref.read(sourceProvider);
    final relevantSources = sourceId != null
        ? sources.where((s) => s.id == sourceId).toList()
        : sources.where((s) => s.notebookId == notebookId).toList();

    if (relevantSources.isEmpty) {
      throw Exception('No sources found to generate quiz from');
    }

    final sourceContent =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: relevantSources,
      objective:
          'Generate $questionCount multiple-choice questions with one correct answer and short explanations.',
    );

    // Build prompt for AI
    final prompt = '''
Generate exactly $questionCount multiple-choice questions from the following content.
Each question should have 4 options with exactly one correct answer.
Include a brief explanation for why the correct answer is right.

CONTENT:
$sourceContent

Return ONLY a JSON array with this exact format:
[
  {
    "question": "What is the main purpose of...?",
    "options": ["Option A", "Option B", "Option C", "Option D"],
    "correctOptionIndex": 0,
    "explanation": "The correct answer is A because..."
  }
]

correctOptionIndex: 0-3 (index of the correct option)
Vary difficulty across questions.
''';

    // Call AI service
    final response = await _callAI(prompt);
    final questions = _parseQuestionsFromResponse(response);

    final now = DateTime.now();
    final quiz = Quiz(
      id: const Uuid().v4(),
      title: title,
      notebookId: notebookId,
      sourceId: sourceId,
      questions: questions,
      createdAt: now,
      updatedAt: now,
    );

    await addQuiz(quiz);
    return quiz;
  }

  Future<String> _callAI(String prompt) async {
    try {
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final model = settings.getEffectiveModel();

      debugPrint(
          '[QuizProvider] Using AI provider: ${settings.provider}, model: $model');

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
      debugPrint('[QuizProvider] AI call failed: $e');
      rethrow;
    }
  }

  List<QuizQuestion> _parseQuestionsFromResponse(String response) {
    try {
      // Extract JSON from response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
      if (jsonMatch == null) throw Exception('No JSON array found');

      final List<dynamic> jsonList = jsonDecode(jsonMatch.group(0)!);

      return jsonList.map((item) {
        return QuizQuestion(
          id: const Uuid().v4(),
          question: item['question'] ?? '',
          options: List<String>.from(item['options'] ?? []),
          correctOptionIndex: item['correctOptionIndex'] ?? 0,
          explanation: item['explanation'],
        );
      }).toList();
    } catch (e) {
      debugPrint('Error parsing questions: $e');
      return [];
    }
  }

  /// Record a quiz attempt
  Future<void> recordAttempt(
      String quizId, int score, int total, Duration timeTaken) async {
    final index = state.indexWhere((q) => q.id == quizId);
    if (index < 0) return;

    final quiz = state[index];
    final now = DateTime.now();

    final updatedQuiz = quiz.copyWith(
      timesAttempted: quiz.timesAttempted + 1,
      lastScore: score,
      bestScore: (quiz.bestScore == null || score > quiz.bestScore!)
          ? score
          : quiz.bestScore,
      lastAttemptedAt: now,
      updatedAt: now,
    );

    state = [...state]..[index] = updatedQuiz;
    // Track gamification
    final isPerfect = score == total;
    ref
        .read(gamificationProvider.notifier)
        .trackQuizCompleted(isPerfect: isPerfect);
    ref.read(gamificationProvider.notifier).trackFeatureUsed('quiz');

    // Log activity to social feed
    final scorePercent = total > 0 ? ((score / total) * 100).round() : 0;
    ref.read(activityLoggerProvider).logQuizCompleted(
          quiz.title,
          scorePercent,
          quizId,
        );

    // Sync to backend
    try {
      final api = ref.read(apiServiceProvider);
      await api.recordQuizAttempt(
        quizId: quizId,
        score: score,
        total: total,
      );
      await _loadQuizzes();
    } catch (e) {
      debugPrint('Error recording attempt: $e');
    }
  }
}

final quizProvider = StateNotifierProvider<QuizNotifier, List<Quiz>>((ref) {
  return QuizNotifier(ref);
});
