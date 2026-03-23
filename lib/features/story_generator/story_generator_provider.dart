import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/ai_settings_service.dart';
import 'package:uuid/uuid.dart';
import 'story.dart';
import '../../core/ai/gemini_image_service.dart';
import '../../core/search/serper_service.dart';
import '../../core/api/api_service.dart';
import '../../core/security/ai_api_key_resolver.dart';
import '../../core/services/activity_logger_service.dart';

class StoryGeneratorState {
  final List<Story> stories;
  final bool isGenerating;
  final String status;
  final double progress;
  final String? error;

  const StoryGeneratorState({
    this.stories = const [],
    this.isGenerating = false,
    this.status = '',
    this.progress = 0.0,
    this.error,
  });

  StoryGeneratorState copyWith({
    List<Story>? stories,
    bool? isGenerating,
    String? status,
    double? progress,
    String? error,
  }) {
    return StoryGeneratorState(
      stories: stories ?? this.stories,
      isGenerating: isGenerating ?? this.isGenerating,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: error,
    );
  }
}

class StoryGeneratorNotifier extends StateNotifier<StoryGeneratorState> {
  final Ref ref;

  StoryGeneratorNotifier(this.ref) : super(const StoryGeneratorState()) {
    _loadStories();
  }

  Future<void> _loadStories() async {
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.getStories();
      final stories = data
          .map((json) => Story.fromJson(_convertBackendStory(json)))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      state = state.copyWith(stories: stories);
    } catch (e) {
      debugPrint('Error loading stories: $e');
    }
  }

  Map<String, dynamic> _convertBackendStory(Map<String, dynamic> raw) {
    return {
      'id': raw['id'],
      'title': raw['title'],
      'summary': raw['summary'],
      'coverImage': raw['cover_image'],
      'genre': raw['genre'],
      'tone': raw['tone'],
      'isFiction': raw['is_fiction'] ?? false,
      'sources': raw['sources'] is String
          ? jsonDecode(raw['sources'])
          : (raw['sources'] ?? []),
      'chapters': raw['chapters'] is String
          ? jsonDecode(raw['chapters'])
          : (raw['chapters'] ?? []),
      'characters': raw['characters'] is String
          ? jsonDecode(raw['characters'])
          : (raw['characters'] ?? []),
      'createdAt': raw['created_at'],
      'updatedAt': raw['updated_at'],
    };
  }

  Future<void> _saveStory(Story story) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.createStory({
        'id': story.id,
        'title': story.title,
        'summary': story.content,
        'coverImage': story.coverImageUrl,
        'genre': story.genre,
        'tone': story.tone.name,
        'isFiction': story.type == StoryType.fiction,
        'sources': story.sources,
        'chapters': story.chapters.map((c) => c.toJson()).toList(),
        'characters': story.characters.map((c) => c.toJson()).toList(),
      });
    } catch (e) {
      debugPrint('Error saving story: $e');
    }
  }

  Future<void> deleteStory(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteStory(id);
      state = state.copyWith(
        stories: state.stories.where((s) => s.id != id).toList(),
      );
    } catch (e) {
      debugPrint('Error deleting story: $e');
    }
  }

  /// Generate a real story based on web research
  Stream<StoryGeneratorState> generateRealStory({
    required String topic,
    String? style,
  }) async* {
    state = state.copyWith(
      isGenerating: true,
      status: 'Researching topic...',
      progress: 0.1,
      error: null,
    );
    yield state;

    try {
      final serperService = SerperService(ref);

      // Search for real information
      state =
          state.copyWith(status: 'Searching web for facts...', progress: 0.2);
      yield state;

      final searchResults = await serperService.search(topic, num: 8);
      final imageResults =
          await serperService.search(topic, type: 'images', num: 6);

      final imageUrls = imageResults
          .where((r) => r.imageUrl != null)
          .map((r) => r.imageUrl!)
          .toList();

      state = state.copyWith(
        status: 'Found ${searchResults.length} sources, gathering content...',
        progress: 0.4,
      );
      yield state;

      // Gather content from sources
      final sourceContents = <String>[];
      final sourceUrls = <String>[];

      for (final result in searchResults.take(5)) {
        try {
          final content = await serperService.fetchPageContent(result.link);

          if (content.length > 100) {
            // Clamp content to 1500 chars to avoid context overflow
            final truncated =
                content.length > 1500 ? content.substring(0, 1500) : content;
            sourceContents.add('${result.title}:\n$truncated');
            sourceUrls.add(result.link);
          }
        } catch (e) {
          if (result.snippet.isNotEmpty) {
            sourceContents.add('${result.title}:\n${result.snippet}');
            sourceUrls.add(result.link);
          }
        }
      }

      state = state.copyWith(
          status: 'Writing story from research...', progress: 0.6);
      yield state;

      // Generate story from research
      final story = await _generateStoryFromResearch(
        topic: topic,
        sources: sourceContents,
        style: style,
        imageUrls: imageUrls,
      );

      final now = DateTime.now();
      final newStory = Story(
        id: const Uuid().v4(),
        title: story['title'] ?? topic,
        type: StoryType.realStory,
        content: story['content'] ?? '',
        chapters: _parseChapters(story['chapters']),
        imageUrls: imageUrls,
        coverImageUrl: imageUrls.isNotEmpty ? imageUrls.first : null,
        sources: sourceUrls,
        createdAt: now,
        updatedAt: now,
      );

      state = state.copyWith(
        stories: [newStory, ...state.stories],
        isGenerating: false,
        status: 'Story complete!',
        progress: 1.0,
      );
      yield state;
      await _saveStory(newStory);

      // Log activity to social feed
      ref
          .read(activityLoggerProvider)
          .logStoryCreated(newStory.title, newStory.id);
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
        status: 'Failed',
      );
      yield state;
    }
  }

  String _getToneGuide(StoryTone tone) {
    switch (tone) {
      case StoryTone.dark:
        return 'Use atmospheric, foreboding language. Explore themes of struggle, moral ambiguity, and the darker aspects of human nature.';
      case StoryTone.lighthearted:
        return 'Keep the mood upbeat and optimistic. Include moments of joy, warmth, and gentle humor.';
      case StoryTone.suspenseful:
        return 'Build tension throughout. Use short sentences during tense moments, create uncertainty, and keep readers on edge.';
      case StoryTone.romantic:
        return 'Focus on emotional connections and chemistry between characters. Include tender moments and heartfelt dialogue.';
      case StoryTone.humorous:
        return 'Include witty dialogue, comedic situations, and clever wordplay. Balance humor with heart.';
      case StoryTone.inspirational:
        return 'Emphasize hope, perseverance, and triumph over adversity. Create moments that uplift and motivate.';
      case StoryTone.melancholic:
        return 'Explore themes of loss, nostalgia, and bittersweet emotions. Use reflective, poetic language.';
      default:
        return 'Balance various emotional tones naturally throughout the narrative.';
    }
  }

  /// Generate a fiction story with AI-generated images
  Stream<StoryGeneratorState> generateFictionStory({
    required String prompt,
    String? genre,
    int chapterCount = 3,
    StoryTone tone = StoryTone.neutral,
    StoryLength length = StoryLength.medium,
    String? setting,
  }) async* {
    state = state.copyWith(
      isGenerating: true,
      status: 'Crafting your story outline...',
      progress: 0.1,
      error: null,
    );
    yield state;

    try {
      // Calculate chapters and words based on length
      final actualChapters = length.chapterCount;
      final wordsPerChapter = length.wordsPerChapter;

      // Generate story content
      state = state.copyWith(
          status: 'Writing immersive narrative...', progress: 0.3);
      yield state;

      final storyData = await _generateFictionContent(
        prompt: prompt,
        genre: genre,
        chapterCount: actualChapters,
        tone: tone,
        wordsPerChapter: wordsPerChapter,
        setting: setting,
      );

      state =
          state.copyWith(status: 'Generating cover image...', progress: 0.5);
      yield state;

      // Generate AI images - use environment API key from config
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);

      // Get correct API key
      final resolvedKey = await ref
          .read(aiApiKeyResolverProvider)
          .resolveForProvider(settings.provider);
      final imageService = GeminiImageService(apiKey: resolvedKey.apiKey);

      final imageUrls = <String>[];

      // Generate cover image
      final coverPrompt =
          'Book cover art for: ${storyData['title']}. ${storyData['coverDescription'] ?? prompt}. Digital art, cinematic, detailed.';
      final coverUrl = await imageService.generateImage(coverPrompt,
          provider: settings.provider, model: settings.model);
      imageUrls.add(coverUrl);

      // Generate chapter images
      final chapters = _parseChapters(storyData['chapters']);
      final updatedChapters = <StoryChapter>[];

      for (int i = 0; i < chapters.length; i++) {
        state = state.copyWith(
          status: 'Generating image for chapter ${i + 1}...',
          progress: 0.5 + (0.4 * (i / chapters.length)),
        );
        yield state;

        String? chapterImageUrl;
        try {
          final imgPrompt =
              'Scene illustration: ${chapters[i].title}. Fantasy art style, detailed, atmospheric.';
          chapterImageUrl = await imageService.generateImage(imgPrompt,
              provider: settings.provider, model: settings.model);
          imageUrls.add(chapterImageUrl);
        } catch (e) {
          debugPrint('Failed to generate chapter image: $e');
        }

        updatedChapters.add(StoryChapter(
          id: chapters[i].id,
          title: chapters[i].title,
          content: chapters[i].content,
          imageUrl: chapterImageUrl,
          order: chapters[i].order,
        ));
      }

      // Parse characters
      final characters = _parseCharacters(storyData['characters']);

      final now = DateTime.now();
      final newStory = Story(
        id: const Uuid().v4(),
        title: storyData['title'] ?? 'Untitled Story',
        type: StoryType.fiction,
        content: storyData['content'] ?? '',
        chapters: updatedChapters,
        imageUrls: imageUrls,
        coverImageUrl: coverUrl,
        genre: genre,
        length: length,
        tone: tone,
        characters: characters,
        setting: storyData['setting'] ?? setting,
        createdAt: now,
        updatedAt: now,
      );

      state = state.copyWith(
        stories: [newStory, ...state.stories],
        isGenerating: false,
        status: 'Story complete!',
        progress: 1.0,
      );
      yield state;
      await _saveStory(newStory);

      // Log activity to social feed
      ref
          .read(activityLoggerProvider)
          .logStoryCreated(newStory.title, newStory.id);
    } catch (e) {
      state = state.copyWith(
        isGenerating: false,
        error: e.toString(),
        status: 'Failed',
      );
      yield state;
    }
  }

  Future<Map<String, dynamic>> _generateStoryFromResearch({
    required String topic,
    required List<String> sources,
    String? style,
    List<String>? imageUrls,
  }) async {
    var sourcesText = sources.join('\n\n---\n\n');
    // Limit sources text to 500,000 chars (approx 125k tokens) to prevent overflow on smaller models
    // But allow enough for large context models like DeepSeek/Gemini
    if (sourcesText.length > 500000) {
      sourcesText = sourcesText.substring(0, 500000);
      sourcesText += '\n...(truncated)...';
    }

    final prompt = '''
You are a storyteller. Write an engaging narrative story based on the following real research about "$topic".
${style != null ? 'Writing style: $style' : ''}

Research Sources:
$sourcesText

Create a compelling story with:
1. An engaging title
2. 3-4 chapters with titles
3. Vivid descriptions and narrative flow
4. Facts woven naturally into the story

Return JSON format:
{
  "title": "Story Title",
  "content": "Full story summary",
  "chapters": [
    {"title": "Chapter 1 Title", "content": "Chapter content..."},
    {"title": "Chapter 2 Title", "content": "Chapter content..."}
  ]
}
''';

    final response = await _callAI(prompt);
    return _parseJsonResponse(response);
  }

  Future<Map<String, dynamic>> _generateFictionContent({
    required String prompt,
    String? genre,
    int chapterCount = 3,
    StoryTone tone = StoryTone.neutral,
    int wordsPerChapter = 600,
    String? setting,
  }) async {
    final toneGuide = _getToneGuide(tone);
    final aiPrompt = '''
You are a master storyteller and creative fiction writer. Write an immersive, professionally-crafted story based on this prompt: "$prompt"

${genre != null ? 'Genre: $genre' : ''}
${setting != null ? 'Setting: $setting' : ''}
Tone/Mood: ${tone.displayName} - $toneGuide

STORY REQUIREMENTS:
1. Create a captivating, unique title that hooks readers
2. Write exactly $chapterCount chapters, each approximately $wordsPerChapter words
3. Each chapter MUST have:
   - An attention-grabbing opening hook (first 1-2 sentences that pull readers in)
   - Rich sensory descriptions (sight, sound, smell, touch, taste)
   - Natural, character-revealing dialogue with distinct voices
   - Internal character thoughts and emotions
   - A mini cliffhanger or compelling ending that makes readers want more
4. Create memorable, three-dimensional characters with:
   - Clear motivations and flaws
   - Unique speech patterns and mannerisms
   - Character arcs that show growth or change
5. Build a vivid, immersive world with consistent rules
6. Use "show don't tell" - demonstrate emotions through actions
7. Include plot twists or surprises that feel earned
8. End with a satisfying conclusion that resolves the main conflict

WRITING STYLE:
- Vary sentence length for rhythm and pacing
- Use active voice predominantly
- Include metaphors and vivid imagery
- Create tension through pacing and stakes
- Make every scene serve the plot or character development

Return JSON format:
{
  "title": "Compelling Story Title",
  "content": "A gripping 2-3 sentence synopsis that captures the essence of the story",
  "coverDescription": "Detailed visual description for cover art: main character appearance, key scene, mood, colors",
  "setting": "Time period and location description",
  "characters": [
    {"name": "Character Name", "role": "protagonist/antagonist/supporting", "description": "Physical and personality description"}
  ],
  "chapters": [
    {
      "title": "Chapter Title",
      "hook": "The attention-grabbing opening line",
      "content": "Full chapter content with rich descriptions, dialogue, and narrative...",
      "cliffhanger": "The compelling chapter ending"
    }
  ]
}
''';

    final response = await _callAI(aiPrompt);
    return _parseJsonResponse(response);
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
    );
  }

  Map<String, dynamic> _parseJsonResponse(String response) {
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch != null) {
        return jsonDecode(jsonMatch.group(0)!);
      }
    } catch (e) {
      debugPrint('JSON parse error: $e');
    }
    return {'title': 'Story', 'content': response, 'chapters': []};
  }

  List<StoryChapter> _parseChapters(dynamic chaptersData) {
    if (chaptersData == null) return [];
    try {
      final list = chaptersData as List;
      return list.asMap().entries.map((entry) {
        final data = entry.value;
        return StoryChapter(
          id: const Uuid().v4(),
          title: data['title'] ?? 'Chapter ${entry.key + 1}',
          content: data['content'] ?? '',
          order: entry.key,
          hook: data['hook'],
          cliffhanger: data['cliffhanger'],
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  List<StoryCharacter> _parseCharacters(dynamic charactersData) {
    if (charactersData == null) return [];
    try {
      final list = charactersData as List;
      return list.map((data) {
        return StoryCharacter(
          name: data['name'] ?? 'Unknown',
          role: data['role'] ?? 'supporting',
          description: data['description'] ?? '',
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }
}

final storyGeneratorProvider =
    StateNotifierProvider<StoryGeneratorNotifier, StoryGeneratorState>((ref) {
  return StoryGeneratorNotifier(ref);
});
