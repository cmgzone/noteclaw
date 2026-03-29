import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'quiz.dart';
import 'quiz_provider.dart';

/// Screen for taking a quiz
class QuizScreen extends ConsumerStatefulWidget {
  final String quizId;

  const QuizScreen({super.key, required this.quizId});

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int _currentIndex = 0;
  int? _selectedOption;
  bool _showResult = false;
  List<int?> _userAnswers = [];
  bool _attemptRecorded = false;
  final Stopwatch _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
  }

  @override
  void dispose() {
    _stopwatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quizzes = ref.watch(quizProvider);
    final quiz = quizzes.firstWhere(
      (q) => q.id == widget.quizId,
      orElse: () => Quiz(
        id: '',
        title: 'Not Found',
        notebookId: '',
        questions: [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (quiz.questions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(quiz.title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _goBackToQuizzes(quiz.notebookId),
          ),
        ),
        body: const Center(
          child: Text('No questions in this quiz'),
        ),
      );
    }

    // Initialize user answers if needed
    if (_userAnswers.isEmpty) {
      _userAnswers = List.filled(quiz.questions.length, null);
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isComplete = _currentIndex >= quiz.questions.length;

    if (isComplete) {
      return _buildResultsScreen(context, quiz, scheme, text);
    }

    final question = quiz.questions[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(quiz.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBackToQuizzes(quiz.notebookId),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentIndex + 1} / ${quiz.questions.length}',
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
              value: (_currentIndex + 1) / quiz.questions.length,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(scheme.primary),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Question
                    Text(
                      'Question ${_currentIndex + 1}',
                      style: text.labelLarge?.copyWith(
                        color: scheme.primary,
                      ),
                    ).animate().fadeIn(),
                    const SizedBox(height: 8),
                    Text(
                      question.question,
                      style: text.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: scheme.onSurface,
                      ),
                    ).animate().fadeIn(delay: 100.ms),
                    const SizedBox(height: 32),

                    // Options
                    ...List.generate(question.options.length, (index) {
                      final isSelected = _selectedOption == index;
                      final isCorrect =
                          _showResult && index == question.correctOptionIndex;
                      final isWrong = _showResult &&
                          isSelected &&
                          index != question.correctOptionIndex;

                      Color cardColor = scheme.surface;
                      Color borderColor = scheme.outline.withValues(alpha: 0.3);

                      if (_showResult) {
                        if (isCorrect) {
                          cardColor = Colors.green.withValues(alpha: 0.15);
                          borderColor = Colors.green;
                        } else if (isWrong) {
                          cardColor = Colors.red.withValues(alpha: 0.15);
                          borderColor = Colors.red;
                        }
                      } else if (isSelected) {
                        cardColor = scheme.primaryContainer;
                        borderColor = scheme.primary;
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: InkWell(
                          onTap: _showResult
                              ? null
                              : () => setState(() => _selectedOption = index),
                          borderRadius: BorderRadius.circular(16),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: borderColor, width: 2),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isSelected || isCorrect
                                        ? (isCorrect
                                            ? Colors.green
                                            : isWrong
                                                ? Colors.red
                                                : scheme.primary)
                                        : scheme.surfaceContainerHighest,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: isCorrect
                                        ? const Icon(LucideIcons.check,
                                            size: 18, color: Colors.white)
                                        : isWrong
                                            ? const Icon(LucideIcons.x,
                                                size: 18, color: Colors.white)
                                            : Text(
                                                String.fromCharCode(65 + index),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isSelected
                                                      ? Colors.white
                                                      : scheme.onSurface,
                                                ),
                                              ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    question.options[index],
                                    style: text.bodyLarge?.copyWith(
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ).animate().fadeIn(delay: (150 * index).ms),
                      );
                    }),

                    // Explanation (shown after answering)
                    if (_showResult && question.explanation != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              scheme.tertiaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              LucideIcons.lightbulb,
                              color: scheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Explanation',
                                    style: text.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.onTertiaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    question.explanation!,
                                    style: text.bodyMedium?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ).animate().fadeIn(delay: 300.ms),
                    ],
                  ],
                ),
              ),
            ),

            // Action buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: _showResult
                  ? FilledButton.icon(
                      onPressed: _nextQuestion,
                      icon: Icon(
                        _currentIndex < quiz.questions.length - 1
                            ? LucideIcons.arrowRight
                            : LucideIcons.checkCircle,
                      ),
                      label: Text(
                        _currentIndex < quiz.questions.length - 1
                            ? 'Next Question'
                            : 'See Results',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                    )
                  : FilledButton.icon(
                      onPressed: _selectedOption != null ? _checkAnswer : null,
                      icon: const Icon(LucideIcons.check),
                      label: const Text('Check Answer'),
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

  Widget _buildResultsScreen(
    BuildContext context,
    Quiz quiz,
    ColorScheme scheme,
    TextTheme text,
  ) {
    final correctCount = _userAnswers.asMap().entries.where((e) {
      return e.value == quiz.questions[e.key].correctOptionIndex;
    }).length;

    final percentage = ((correctCount / quiz.questions.length) * 100).round();
    final timeTaken = _stopwatch.elapsed;

    // Record the attempt
    if (!_attemptRecorded) {
      _attemptRecorded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(quizProvider.notifier).recordAttempt(
              quiz.id,
              correctCount,
              quiz.questions.length,
              timeTaken,
            );
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Quiz Results'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _goBackToQuizzes(quiz.notebookId),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Score circle
              Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      percentage >= 70
                          ? Colors.green
                          : percentage >= 50
                              ? Colors.orange
                              : Colors.red,
                      percentage >= 70
                          ? Colors.green.shade700
                          : percentage >= 50
                              ? Colors.orange.shade700
                              : Colors.red.shade700,
                    ],
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$percentage%',
                        style: text.headlineLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '$correctCount/${quiz.questions.length}',
                        style: text.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ).animate().scale(delay: 200.ms, curve: Curves.elasticOut),
              const SizedBox(height: 32),

              // Message
              Text(
                percentage >= 70
                    ? 'Excellent! 🎉'
                    : percentage >= 50
                        ? 'Good effort! 👍'
                        : 'Keep practicing! 💪',
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                ),
              ).animate().fadeIn(delay: 400.ms),
              const SizedBox(height: 8),
              Text(
                'Time: ${_formatDuration(timeTaken)}',
                style: text.titleMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ).animate().fadeIn(delay: 500.ms),
              const SizedBox(height: 32),

              // Stats grid
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildStatCard(
                    Icons.check_circle,
                    'Correct',
                    '$correctCount',
                    Colors.green,
                    scheme,
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    Icons.cancel,
                    'Incorrect',
                    '${quiz.questions.length - correctCount}',
                    Colors.red,
                    scheme,
                  ),
                ],
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: 48),

              // Action buttons
              FilledButton.icon(
                onPressed: () {
                  setState(() {
                    _currentIndex = 0;
                    _selectedOption = null;
                    _showResult = false;
                    _userAnswers = [];
                    _attemptRecorded = false;
                    _stopwatch.reset();
                    _stopwatch.start();
                  });
                },
                icon: const Icon(LucideIcons.rotateCcw),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
              ).animate().fadeIn(delay: 800.ms),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => _goBackToQuizzes(quiz.notebookId),
                child: const Text('Back to Quizzes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(
    IconData icon,
    String label,
    String value,
    Color color,
    ColorScheme scheme,
  ) {
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

  void _checkAnswer() {
    setState(() {
      _userAnswers[_currentIndex] = _selectedOption;
      _showResult = true;
    });
  }

  void _nextQuestion() {
    setState(() {
      _currentIndex++;
      _selectedOption = null;
      _showResult = false;
    });
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  void _goBackToQuizzes(String notebookId) {
    if (!mounted) return;
    if (notebookId.isNotEmpty) {
      context.go('/notebook/$notebookId/quizzes');
      return;
    }
    context.go('/home');
  }
}
