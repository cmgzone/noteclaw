import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/auth/custom_auth_service.dart';
import '../providers/subscription_provider.dart';
import 'subscription_service.dart';
import '../../../core/api/api_service.dart';

/// Credit costs for different AI features
class CreditCosts {
  // Chat & Conversation
  static const int chatMessage = 1;
  static const int notebookChat = 1;
  static const int voiceMode = 2;
  static const int meetingMode = 3;

  // Content Generation
  static const int generateFlashcards = 2;
  static const int generateQuiz = 2;
  static const int generateMindMap = 3;
  static const int generateStudyGuide = 3;
  static const int generateInfographic = 5;

  // Research & Search
  static const int webSearch = 1;
  static const int deepResearch = 5;
  static const int codeReview = 2;

  // Audio & Media
  static const int podcastGeneration = 10;
  static const int audioOverview = 5;
  static const int textToSpeech = 2;
  static const int transcription = 3;

  // Ebook
  static const int ebookGeneration = 15;
  static const int ebookChapter = 5;

  // Story & Creative
  static const int storyGeneration = 5;
  static const int mealPlan = 2;

  // Tutor
  static const int tutorSession = 3;

  // Source Processing
  static const int sourceIngestion = 1;
  static const int youtubeTranscript = 2;

  static String getFeatureName(String feature) {
    final names = {
      'chat_message': 'AI Chat',
      'notebook_chat': 'Memory Notebook Chat',
      'voice_mode': 'Voice Mode',
      'meeting_mode': 'Meeting Mode',
      'generate_flashcards': 'Flashcard Generation',
      'generate_quiz': 'Quiz Generation',
      'generate_mindmap': 'Mind Map Generation',
      'generate_study_guide': 'Study Guide',
      'generate_infographic': 'Infographic',
      'web_search': 'Web Search',
      'deep_research': 'Deep Research',
      'code_review': 'Code Review',
      'podcast_generation': 'Podcast Generation',
      'audio_overview': 'Audio Overview',
      'text_to_speech': 'Text to Speech',
      'transcription': 'Transcription',
      'ebook_generation': 'Ebook Generation',
      'ebook_chapter': 'Ebook Chapter',
      'story_generation': 'Story Generation',
      'meal_plan': 'Meal Planning',
      'tutor_session': 'AI Tutor',
      'source_ingestion': 'Source Processing',
      'youtube_transcript': 'YouTube Transcript',
    };
    return names[feature] ?? feature;
  }
}

/// Credit Manager Provider
final creditManagerProvider = Provider<CreditManager>((ref) {
  return CreditManager(ref);
});

final featureCreditCostsProvider =
    FutureProvider<Map<String, int>>((ref) async {
  return ref.read(apiServiceProvider).getFeatureCreditCosts();
});

class CreditManager {
  final Ref _ref;

  CreditManager(this._ref);

  SubscriptionService get _service => _ref.read(subscriptionServiceProvider);
  String? get _userId => _ref.read(legacyUserProvider)?.uid;

  /// Check if user has enough credits for a feature
  /// This fetches fresh data from the API to ensure accuracy
  Future<bool> hasCredits(int amount) async {
    final userId = _userId;
    if (userId == null) return false;

    // Always fetch fresh balance from API
    return await _service.hasEnoughCredits(userId, amount);
  }

  /// Consume credits for a feature
  /// Returns true if successful, false if not enough credits
  Future<bool> useCredits({
    required int amount,
    required String feature,
    Map<String, dynamic>? metadata,
  }) async {
    final userId = _userId;
    if (userId == null) return false;

    try {
      final success = await _service.consumeCredits(
        userId: userId,
        amount: amount,
        feature: feature,
        metadata: metadata,
      );

      if (success) {
        // Invalidate the subscription provider to refresh UI
        _ref.invalidate(userSubscriptionProvider);
      }

      return success;
    } catch (e) {
      debugPrint('Error consuming credits: $e');
      return false;
    }
  }

  /// Get current credit balance (from cache - may be stale)
  int get currentBalance => _ref.read(creditBalanceProvider);

  /// Get fresh credit balance from API
  Future<int> getFreshBalance() async {
    final userId = _userId;
    if (userId == null) return 0;
    try {
      return await _service.getCreditBalance(userId);
    } catch (e) {
      debugPrint('Error fetching credit balance: $e');
      // Return cached balance on error, or a high number to not block user
      return currentBalance > 0 ? currentBalance : 999999;
    }
  }

  /// Show insufficient credits dialog
  static void showInsufficientCreditsDialog(
    BuildContext context, {
    required int required,
    required int available,
    required String feature,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Insufficient Credits'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You need $required credits for ${CreditCosts.getFeatureName(feature)}, '
              'but you only have $available credits.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Required:'),
                  Text(
                    '$required credits',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Available:'),
                  Text(
                    '$available credits',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              ctx.push('/subscription');
            },
            icon: const Icon(Icons.add_card),
            label: const Text('Get Credits'),
          ),
        ],
      ),
    );
  }

  /// Helper to check and consume credits with UI feedback
  /// Returns true if credits were consumed, false otherwise
  Future<bool> tryUseCredits({
    required BuildContext context,
    required int amount,
    required String feature,
    Map<String, dynamic>? metadata,
  }) async {
    // Fetch fresh balance from API to ensure accuracy
    final balance = await getFreshBalance();

    if (balance < amount) {
      if (context.mounted) {
        showInsufficientCreditsDialog(
          context,
          required: amount,
          available: balance,
          feature: feature,
        );
      }
      return false;
    }

    final success = await useCredits(
      amount: amount,
      feature: feature,
      metadata: metadata,
    );

    if (!success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to process credits. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }

    return success;
  }
}

/// Extension for easy credit checking in ConsumerWidgets
extension CreditManagerExtension on WidgetRef {
  CreditManager get creditManager => read(creditManagerProvider);

  Future<bool> tryUseCredits({
    required BuildContext context,
    required int amount,
    required String feature,
    Map<String, dynamic>? metadata,
  }) {
    return creditManager.tryUseCredits(
      context: context,
      amount: amount,
      feature: feature,
      metadata: metadata,
    );
  }
}
