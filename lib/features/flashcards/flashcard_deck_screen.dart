import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'flashcard.dart';
import 'flashcard_provider.dart';
import '../../core/services/activity_logger_service.dart';

/// Screen for viewing and studying a flashcard deck
class FlashcardDeckScreen extends ConsumerStatefulWidget {
  final String deckId;

  const FlashcardDeckScreen({super.key, required this.deckId});

  @override
  ConsumerState<FlashcardDeckScreen> createState() =>
      _FlashcardDeckScreenState();
}

class _FlashcardDeckScreenState extends ConsumerState<FlashcardDeckScreen> {
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _correctCount = 0;
  int _incorrectCount = 0;

  @override
  Widget build(BuildContext context) {
    final decks = ref.watch(flashcardProvider);
    final deck = decks.firstWhere(
      (d) => d.id == widget.deckId,
      orElse: () => FlashcardDeck(
        id: '',
        title: 'Not Found',
        notebookId: '',
        cards: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (deck.cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(deck.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _goBackToFlashcards(deck.notebookId),
          ),
        ),
        body: const Center(
          child: Text('No flashcards in this deck'),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isComplete = _currentIndex >= deck.cards.length;

    if (isComplete) {
      return _buildCompletionScreen(context, deck, scheme, text);
    }

    final card = deck.cards[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(deck.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBackToFlashcards(deck.notebookId),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${deck.cards.length}',
                style: text.titleMedium,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            LinearProgressIndicator(
              value: (_currentIndex + 1) / deck.cards.length,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),

            // Score display
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildScoreChip(
                    icon: LucideIcons.check,
                    label: '$_correctCount',
                    color: Colors.green,
                  ),
                  const SizedBox(width: 24),
                  _buildScoreChip(
                    icon: LucideIcons.x,
                    label: '$_incorrectCount',
                    color: Colors.red,
                  ),
                ],
              ),
            ),

            // Flashcard
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _showAnswer = !_showAnswer),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _buildFlashcard(card, scheme, text),
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: _showAnswer
                  ? Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonal(
                            onPressed: () =>
                                _recordAnswer(false, deck.id, card.id),
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.red.withValues(alpha: 0.15),
                              foregroundColor: Colors.red,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.thumbsDown),
                                SizedBox(width: 8),
                                Text('Didn\'t Know'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed: () =>
                                _recordAnswer(true, deck.id, card.id),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(LucideIcons.thumbsUp),
                                SizedBox(width: 8),
                                Text('Got It!'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : FilledButton.icon(
                      onPressed: () => setState(() => _showAnswer = true),
                      icon: const Icon(LucideIcons.eye),
                      label: const Text('Show Answer'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlashcard(Flashcard card, ColorScheme scheme, TextTheme text) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      transitionBuilder: (child, animation) {
        return RotationTransition(
          turns: Tween(begin: 0.5, end: 1.0).animate(animation),
          child: child,
        );
      },
      child: Card(
        key: ValueKey(_showAnswer),
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: _showAnswer
                  ? [
                      scheme.primaryContainer,
                      scheme.primary.withValues(alpha: 0.3),
                    ]
                  : [
                      scheme.surfaceContainerHighest,
                      scheme.surface,
                    ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _showAnswer ? LucideIcons.lightbulb : LucideIcons.helpCircle,
                size: 48,
                color: _showAnswer
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface.withValues(alpha: 0.5),
              ).animate().scale(delay: 100.ms),
              const SizedBox(height: 24),
              Text(
                _showAnswer ? 'Answer' : 'Question',
                style: text.labelLarge?.copyWith(
                  color: _showAnswer
                      ? scheme.onPrimaryContainer.withValues(alpha: 0.7)
                      : scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _showAnswer ? card.answer : card.question,
                style: text.headlineSmall?.copyWith(
                  color: _showAnswer
                      ? scheme.onPrimaryContainer
                      : scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: 24),
              if (!_showAnswer)
                Text(
                  'Tap to reveal answer',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ).animate().fadeIn(delay: 500.ms),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompletionScreen(
    BuildContext context,
    FlashcardDeck deck,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final total = deck.cards.length;
    final percentage = ((_correctCount / total) * 100).round();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBackToFlashcards(deck.notebookId),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.trophy,
                  size: 64,
                  color: scheme.onPrimaryContainer,
                ),
              ).animate().scale(delay: 200.ms, curve: Curves.elasticOut),
              const SizedBox(height: 32),
              Text(
                'Great Job!',
                style: text.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 16),
              Text(
                'You got $percentage% correct',
                style: text.titleLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatCard(
                    icon: LucideIcons.check,
                    label: 'Correct',
                    value: '$_correctCount',
                    color: Colors.green,
                    scheme: scheme,
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    icon: LucideIcons.x,
                    label: 'Incorrect',
                    value: '$_incorrectCount',
                    color: Colors.red,
                    scheme: scheme,
                  ),
                ],
              ).animate().fadeIn(delay: 800.ms),
              const SizedBox(height: 48),
              FilledButton.icon(
                onPressed: () => _resetSession(),
                icon: const Icon(LucideIcons.rotateCcw),
                label: const Text('Study Again'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ).animate().fadeIn(delay: 1000.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _goBackToFlashcards(deck.notebookId),
                child: const Text('Back to Flashcards'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required ColorScheme scheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  void _recordAnswer(bool wasCorrect, String deckId, String cardId) {
    ref.read(flashcardProvider.notifier).recordReview(
          deckId,
          cardId,
          wasCorrect,
        );

    final decks = ref.read(flashcardProvider);
    final deck = decks.firstWhere((d) => d.id == deckId,
        orElse: () => FlashcardDeck(
              id: '',
              title: 'Unknown',
              notebookId: '',
              cards: [],
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ));

    setState(() {
      if (wasCorrect) {
        _correctCount++;
      } else {
        _incorrectCount++;
      }
      _showAnswer = false;
      _currentIndex++;

      // Log activity when deck is completed
      if (_currentIndex >= deck.cards.length) {
        ref.read(activityLoggerProvider).logFlashcardDeckCompleted(
              deck.title,
              deckId,
            );
      }
    });
  }

  void _resetSession() {
    setState(() {
      _currentIndex = 0;
      _showAnswer = false;
      _correctCount = 0;
      _incorrectCount = 0;
    });
  }

  void _goBackToFlashcards(String notebookId) {
    if (!mounted) return;
    if (notebookId.isNotEmpty) {
      context.go('/notebook/$notebookId/flashcards');
      return;
    }
    context.go('/home');
  }
}
