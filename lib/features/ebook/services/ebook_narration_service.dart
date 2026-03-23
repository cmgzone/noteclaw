import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/voice_service.dart';
import '../models/ebook_project.dart';

enum NarrationState { idle, playing, paused }

class NarrationStatus {
  final NarrationState state;
  final int currentChapterIndex;
  final String? currentText;
  final String? error;

  const NarrationStatus({
    this.state = NarrationState.idle,
    this.currentChapterIndex = 0,
    this.currentText,
    this.error,
  });

  NarrationStatus copyWith({
    NarrationState? state,
    int? currentChapterIndex,
    String? currentText,
    String? error,
  }) {
    return NarrationStatus(
      state: state ?? this.state,
      currentChapterIndex: currentChapterIndex ?? this.currentChapterIndex,
      currentText: currentText ?? this.currentText,
      error: error,
    );
  }
}

class EbookNarrationService extends StateNotifier<NarrationStatus> {
  final VoiceService _voiceService;
  EbookProject? _currentProject;
  bool _shouldContinue = false;

  EbookNarrationService(this._voiceService) : super(const NarrationStatus());

  Future<void> startNarration(EbookProject project,
      {int startChapter = 0}) async {
    _currentProject = project;
    _shouldContinue = true;

    state = NarrationStatus(
      state: NarrationState.playing,
      currentChapterIndex: startChapter,
    );

    await _narrateFromChapter(startChapter);
  }

  Future<void> _narrateFromChapter(int chapterIndex) async {
    if (_currentProject == null) return;

    final chapters = _currentProject!.chapters;
    debugPrint(
        '[Narration] Starting from chapter $chapterIndex of ${chapters.length}');

    for (int i = chapterIndex; i < chapters.length && _shouldContinue; i++) {
      final chapter = chapters[i];
      debugPrint('[Narration] Processing chapter ${i + 1}: ${chapter.title}');

      state = state.copyWith(
        currentChapterIndex: i,
        currentText: 'Chapter ${i + 1}: ${chapter.title}',
      );

      try {
        // Narrate chapter title
        final chapterTitle = 'Chapter ${i + 1}. ${chapter.title}';
        debugPrint('[Narration] Speaking title: $chapterTitle');
        await _voiceService.speak(chapterTitle);

        // Wait for TTS completion
        await _waitForSpeechCompletion();
        await Future.delayed(const Duration(milliseconds: 800));

        if (!_shouldContinue) break;

        // Narrate chapter content in chunks
        final content = _cleanContentForNarration(chapter.content);
        debugPrint('[Narration] Cleaned content length: ${content.length}');

        // Skip if chapter has no meaningful content
        if (content.trim().isEmpty) {
          debugPrint('[Narration] Chapter ${i + 1} has no content, skipping');
          continue;
        }

        final chunks = _splitIntoChunks(content, 500);
        debugPrint('[Narration] Split into ${chunks.length} chunks');

        for (int j = 0; j < chunks.length; j++) {
          if (!_shouldContinue) break;

          final chunk = chunks[j];
          debugPrint('[Narration] Speaking chunk ${j + 1}/${chunks.length}');

          state = state.copyWith(
              currentText: chunk.substring(0, chunk.length.clamp(0, 100)));

          await _voiceService.speak(chunk);
          await _waitForSpeechCompletion();
          await Future.delayed(const Duration(milliseconds: 400));
        }

        // Pause between chapters
        if (_shouldContinue && i < chapters.length - 1) {
          debugPrint('[Narration] Pausing before next chapter');
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (e) {
        debugPrint('[Narration] Error in chapter ${i + 1}: $e');
        state = state.copyWith(
          state: NarrationState.idle,
          error: 'Narration error: $e',
        );
        return;
      }
    }

    if (_shouldContinue) {
      debugPrint('[Narration] Completed all chapters');
      state = const NarrationStatus(state: NarrationState.idle);
    }
  }

  /// Wait for the current speech to complete
  Future<void> _waitForSpeechCompletion() async {
    // Give TTS time to process - the awaitSpeakCompletion should handle this,
    // but we add a small buffer to ensure proper sequencing
    await Future.delayed(const Duration(milliseconds: 100));
  }

  String _cleanContentForNarration(String content) {
    return VoiceService.sanitizeNarrationText(content);
  }

  List<String> _splitIntoChunks(String text, int maxLength) {
    final chunks = <String>[];
    final sentences = text.split(RegExp(r'(?<=[.!?])\s+'));

    String currentChunk = '';
    for (final sentence in sentences) {
      // Skip empty sentences
      final trimmedSentence = sentence.trim();
      if (trimmedSentence.isEmpty) continue;

      if ((currentChunk + trimmedSentence).length > maxLength &&
          currentChunk.isNotEmpty) {
        final trimmedChunk = currentChunk.trim();
        if (trimmedChunk.isNotEmpty) {
          chunks.add(trimmedChunk);
        }
        currentChunk = trimmedSentence;
      } else {
        currentChunk += ' $trimmedSentence';
      }
    }

    final finalChunk = currentChunk.trim();
    if (finalChunk.isNotEmpty) {
      chunks.add(finalChunk);
    }

    // Filter out any chunks that are just whitespace or too short
    return chunks.where((chunk) => chunk.trim().length > 2).toList();
  }

  void pause() {
    _shouldContinue = false;
    _voiceService.stopSpeaking();
    state = state.copyWith(state: NarrationState.paused);
  }

  Future<void> resume() async {
    if (_currentProject == null) return;
    _shouldContinue = true;
    state = state.copyWith(state: NarrationState.playing);
    await _narrateFromChapter(state.currentChapterIndex);
  }

  void stop() {
    _shouldContinue = false;
    _voiceService.stopSpeaking();
    _currentProject = null;
    state = const NarrationStatus();
  }

  void skipToChapter(int index) {
    if (_currentProject == null) return;
    if (index < 0 || index >= _currentProject!.chapters.length) return;

    _shouldContinue = false;
    _voiceService.stopSpeaking();

    Future.delayed(const Duration(milliseconds: 100), () {
      startNarration(_currentProject!, startChapter: index);
    });
  }
}

final ebookNarrationProvider =
    StateNotifierProvider<EbookNarrationService, NarrationStatus>((ref) {
  final voiceService = ref.read(voiceServiceProvider);
  return EbookNarrationService(voiceService);
});
