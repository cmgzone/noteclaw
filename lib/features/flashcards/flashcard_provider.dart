import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:uuid/uuid.dart';
import 'flashcard.dart';
import '../sources/source_provider.dart';
import '../gamification/gamification_provider.dart';
import '../notebook/notebook_chat_context_builder.dart';
import '../../core/api/api_service.dart';
import '../../core/ai/ai_settings_service.dart';

/// Provider for managing flashcard decks
class FlashcardNotifier extends StateNotifier<List<FlashcardDeck>> {
  final Ref ref;

  FlashcardNotifier(this.ref) : super([]) {
    _loadDecks();
  }

  Future<void> _loadDecks() async {
    try {
      final api = ref.read(apiServiceProvider);
      final decksData = await api.getFlashcardDecks();

      // Fetch cards for each deck
      final decksWithCards = <FlashcardDeck>[];
      for (final deckJson in decksData) {
        final deckId = deckJson['id'] as String;
        try {
          final cardsData = await api.getFlashcardsForDeck(deckId);
          deckJson['cards'] = cardsData;
        } catch (e) {
          debugPrint('Error loading cards for deck $deckId: $e');
          deckJson['cards'] = [];
        }
        decksWithCards.add(FlashcardDeck.fromBackendJson(deckJson));
      }

      state = decksWithCards
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading flashcard decks: $e');
      state = [];
    }
  }

  /// Get decks for a specific notebook
  List<FlashcardDeck> getDecksForNotebook(String notebookId) {
    return state.where((deck) => deck.notebookId == notebookId).toList();
  }

  /// Add a new deck
  Future<FlashcardDeck> addDeck(FlashcardDeck deck) async {
    try {
      final api = ref.read(apiServiceProvider);
      final savedData = await api.createFlashcardDeck(
        title: deck.title,
        notebookId: deck.notebookId,
        sourceId: deck.sourceId,
        cards: deck.cards.map((c) => c.toBackendJson()).toList(),
      );

      // Check if savedData is valid
      if (savedData.isEmpty || savedData['id'] == null) {
        debugPrint(
            '[FlashcardProvider] Backend returned invalid deck data, using local deck');
        // Add local deck to state as fallback
        state = [deck, ...state];
        return deck;
      }

      // The backend returns the deck, but we need to fetch cards separately
      // since createFlashcardDeck doesn't return them
      final deckId = savedData['id'] as String;

      try {
        final cardsData = await api.getFlashcardsForDeck(deckId);
        savedData['cards'] = cardsData;
      } catch (e) {
        debugPrint(
            '[FlashcardProvider] Failed to fetch cards, using local cards: $e');
        // Use local cards if fetch fails
        savedData['cards'] = deck.cards.map((c) => c.toBackendJson()).toList();
      }

      // Parse the saved deck from backend response
      final savedDeck = FlashcardDeck.fromBackendJson(savedData);

      // Add to state with the server-generated data
      state = [savedDeck, ...state.where((d) => d.id != savedDeck.id)];

      return savedDeck;
    } catch (e) {
      debugPrint('Error adding deck: $e');
      rethrow; // Rethrow so the UI can show the error
    }
  }

  /// Update existing deck
  Future<void> updateDeck(FlashcardDeck deck) async {
    try {
      // The backend API for updating a deck is not yet implemented.
      // For now, we just reload the decks to reflect any potential changes
      // if the update was handled elsewhere or if this method is called
      // after a local modification that needs to be re-synced.
      await _loadDecks();
    } catch (e) {
      debugPrint('Error updating deck: $e');
    }
  }

  /// Delete a deck
  Future<void> deleteDeck(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteFlashcardDeck(id);
      state = state.where((deck) => deck.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting deck: $e');
    }
  }

  /// Generate flashcards from sources using AI
  Future<FlashcardDeck> generateFromSources({
    required String notebookId,
    required String title,
    String? sourceId,
    int cardCount = 10,
  }) async {
    // Get source content
    final sources = ref.read(sourceProvider);
    final relevantSources = sourceId != null
        ? sources.where((s) => s.id == sourceId).toList()
        : sources.where((s) => s.notebookId == notebookId).toList();

    if (relevantSources.isEmpty) {
      throw Exception('No sources found to generate flashcards from');
    }

    final sourceContent =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: relevantSources,
      objective:
          'Generate $cardCount flashcards that cover key concepts, definitions, relationships, and important facts.',
    );

    // Build prompt for AI
    final prompt = '''
Generate exactly $cardCount flashcards from the following content. 
Each flashcard should have a clear question and concise answer.
Focus on key concepts, definitions, and important facts.

CONTENT:
$sourceContent

Return ONLY a JSON array with this exact format:
[
  {"question": "What is...?", "answer": "It is...", "difficulty": 1},
  {"question": "How does...?", "answer": "It works by...", "difficulty": 2}
]

difficulty: 1=easy, 2=medium, 3=hard
''';

    // Call AI service
    final response = await _callAI(prompt);
    final cards = _parseFlashcardsFromResponse(response, notebookId, sourceId);

    if (cards.isEmpty) {
      throw Exception('Failed to generate flashcards from AI response');
    }

    final now = DateTime.now();
    final deck = FlashcardDeck(
      id: const Uuid().v4(),
      title: title,
      notebookId: notebookId,
      sourceId: sourceId,
      cards: cards,
      createdAt: now,
      updatedAt: now,
    );

    // Try to save to backend, but don't fail if it doesn't work
    try {
      final savedDeck = await addDeck(deck);
      return savedDeck;
    } catch (e) {
      debugPrint(
          '[FlashcardProvider] Backend save failed, using local deck: $e');
      // Add to local state even if backend fails
      state = [deck, ...state];
      return deck;
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

      debugPrint(
          '[FlashcardProvider] Using AI provider: ${settings.provider}, model: $model');

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
      debugPrint('[FlashcardProvider] AI call failed: $e');
      rethrow;
    }
  }

  List<Flashcard> _parseFlashcardsFromResponse(
      String response, String notebookId, String? sourceId) {
    try {
      // Extract JSON from response
      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(response);
      if (jsonMatch == null) throw Exception('No JSON array found');

      final List<dynamic> jsonList = jsonDecode(jsonMatch.group(0)!);
      final now = DateTime.now();

      return jsonList.map((item) {
        return Flashcard(
          id: const Uuid().v4(),
          question: item['question'] ?? '',
          answer: item['answer'] ?? '',
          notebookId: notebookId,
          sourceId: sourceId,
          difficulty: item['difficulty'] ?? 1,
          createdAt: now,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error parsing flashcards: $e');
      return [];
    }
  }

  /// Record a review attempt for a card
  Future<void> recordReview(
      String deckId, String cardId, bool wasCorrect) async {
    // Track gamification - 1 flashcard reviewed
    ref.read(gamificationProvider.notifier).trackFlashcardsReviewed(1);
    ref.read(gamificationProvider.notifier).trackFeatureUsed('flashcards');

    // Sync to backend
    try {
      final api = ref.read(apiServiceProvider);
      await api.updateFlashcardProgress(
        cardId: cardId,
        wasCorrect: wasCorrect,
      );
      // Optional: reload state to get server-calculated nextReviewAt
      // await _loadDecks();
    } catch (e) {
      debugPrint('Error recording review: $e');
    }
  }
}

final flashcardProvider =
    StateNotifierProvider<FlashcardNotifier, List<FlashcardDeck>>((ref) {
  return FlashcardNotifier(ref);
});
