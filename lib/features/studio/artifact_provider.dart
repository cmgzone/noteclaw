import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/rag/vector_store.dart';
import '../../core/rag/rag_provider.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/api/api_service.dart';
import '../../core/services/wakelock_service.dart';
import '../../core/services/background_ai_service.dart';
import '../../core/services/overlay_bubble_service.dart';
import '../../features/sources/source_provider.dart';
import '../../features/sources/source.dart';
import '../notebook/notebook_chat_context_builder.dart';
import 'artifact.dart';

class ArtifactNotifier extends StateNotifier<List<Artifact>> {
  ArtifactNotifier(this.ref) : super([]);
  final Ref ref;

  Future<String> _getSelectedProvider() async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    return settings.provider;
  }

  Future<String> _getSelectedModel() async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    return settings.getEffectiveModel();
  }

  Future<String> _generateWithAI(String prompt) async {
    final provider = await _getSelectedProvider();
    final model = await _getSelectedModel();

    try {
      // Use Backend Proxy (Admin's API keys)
      final apiService = ref.read(apiServiceProvider);
      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      return await apiService.chatWithAI(
        messages: messages,
        provider: provider,
        model: model,
      );
    } catch (e) {
      debugPrint('[ArtifactProvider] AI generation failed: $e');
      rethrow;
    }
  }

  Future<void> generate(String type,
      {String? notebookId, bool showBubble = false}) async {
    debugPrint(
        '[ArtifactProvider] Generating artifact: type=$type, notebookId=$notebookId');

    // Show floating bubble if requested
    if (showBubble) {
      await overlayBubbleService.show(
          status: 'Creating ${_titleForType(type)}...');
    }

    // Keep screen awake during AI generation
    return wakelockService.withWakeLock(() async {
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      final title = _titleForType(type);

      try {
        if (showBubble) {
          await overlayBubbleService.updateStatus('Analyzing sources...');
        }

        final content =
            await _generateRichContent(type, notebookId: notebookId);
        debugPrint(
            '[ArtifactProvider] Generated content length: ${content.length}');

        final artifact = Artifact(
          id: id,
          title: title,
          type: type,
          content: content,
          createdAt: DateTime.now(),
          notebookId: notebookId,
        );
        state = [...state, artifact];
        debugPrint('[ArtifactProvider] Artifact added to state successfully');

        if (showBubble) {
          await overlayBubbleService.updateStatus('Complete! ✓');
          await Future.delayed(const Duration(seconds: 1));
          await overlayBubbleService.hide();
        }
      } catch (e) {
        debugPrint('[ArtifactProvider] Error generating artifact: $e');
        if (showBubble) {
          await overlayBubbleService.updateStatus('Error ✗');
          await Future.delayed(const Duration(seconds: 2));
          await overlayBubbleService.hide();
        }
        rethrow;
      }
    });
  }

  /// Check for completed background tasks and add results
  Future<void> checkBackgroundTasks() async {
    final statusMap = await backgroundAIService.getTaskStatus();
    if (statusMap['status'] == 'completed') {
      final result = await backgroundAIService.getTaskResult();
      final prefs = await SharedPreferences.getInstance();
      final taskType = prefs.getString('bg_task_type');
      final taskId = prefs.getString('bg_task_id');

      if (result != null && taskType == 'artifact' && taskId != null) {
        // Check if we already have this artifact
        final exists = state.any((a) => a.id == taskId);
        if (!exists) {
          final artifact = Artifact(
            id: taskId,
            title: prefs.getString('bg_task_title') ?? 'Background Artifact',
            type: prefs.getString('bg_artifact_type') ?? 'study-guide',
            content: result,
            createdAt: DateTime.now(),
            notebookId: prefs.getString('bg_notebook_id'),
          );
          state = [...state, artifact];
          debugPrint('[ArtifactProvider] Added background-generated artifact');
        }

        // Clear task
        await prefs.remove('bg_task_status');
        await prefs.remove('bg_task_result');
      }
    }
  }

  /// Start background generation (for when app may close)
  /// Note: Background generation currently requires manual API key setup.
  /// This feature may be deprecated in favor of standard generate() with Backend Proxy.
  Future<void> generateInBackground(String type, {String? notebookId}) async {
    final provider = await _getSelectedProvider();
    final model = await _getSelectedModel();

    final sources = ref.read(sourceProvider);
    final filteredSources = notebookId != null
        ? sources.where((s) => s.notebookId == notebookId).toList()
        : sources;

    final sourceContent = await _buildSourceContent(
      filteredSources,
      objective: _objectiveForArtifactType(type),
    );
    final prompt = _buildPromptForType(type, sourceContent);
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();

    // Save metadata for when task completes
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bg_task_title', _titleForType(type));
    await prefs.setString('bg_artifact_type', type);
    if (notebookId != null) {
      await prefs.setString('bg_notebook_id', notebookId);
    }

    // Note: Background generation uses legacy API key approach
    // This feature should be migrated to use Backend Proxy in future
    await backgroundAIService.startGeneration(
      taskType: 'artifact',
      taskId: taskId,
      params: {
        'apiKey': '', // Backend proxy handles keys now
        'provider': provider,
        'model': model,
        'prompt': prompt,
        'title': _titleForType(type),
      },
    );

    debugPrint('[ArtifactProvider] Started background generation: $taskId');
  }

  String _buildPromptForType(String type, String sourceContent) {
    switch (type) {
      case 'study-guide':
        return '''Create a comprehensive study guide based on:
$sourceContent

Include: Overview, Key Concepts, Important Details, Summary Points, Study Tips.
Format in clean Markdown.''';
      case 'brief':
        return '''Create an executive briefing based on:
$sourceContent

Include: Executive Summary, Key Findings, Analysis, Recommendations, Conclusion.
Format in clean Markdown.''';
      case 'faq':
        return '''Create FAQ based on:
$sourceContent

Generate 8-12 Q&A pairs covering important topics.
Format as **Q:** and A: in Markdown.''';
      case 'timeline':
        return '''Create a timeline based on:
$sourceContent

Identify key events and order chronologically.
Format in Markdown with dates/periods as headers.''';
      default:
        return 'Summarize: $sourceContent';
    }
  }

  /// Get artifacts for a specific notebook, or all if notebookId is null
  List<Artifact> getArtifactsForNotebook(String? notebookId) {
    if (notebookId == null) {
      return state; // Return all artifacts
    }
    return state.where((a) => a.notebookId == notebookId).toList();
  }

  String _titleForType(String type) {
    switch (type) {
      case 'study-guide':
        return 'Study Guide';
      case 'brief':
        return 'Briefing Document';
      case 'faq':
        return 'FAQ';
      case 'timeline':
        return 'Timeline';
      case 'mind-map':
        return 'Mind Map';
      default:
        return 'Artifact';
    }
  }

  Future<String> _generateRichContent(String type, {String? notebookId}) async {
    // Ensure sources are loaded
    final sourceNotifier = ref.read(sourceProvider.notifier);
    await sourceNotifier.loadSources();

    final sources = ref.read(sourceProvider);
    final vectorStore = ref.read(vectorStoreProvider);

    debugPrint('[ArtifactProvider] Total sources: ${sources.length}');
    debugPrint(
        '[ArtifactProvider] Vector store chunks: ${vectorStore.chunkCount}');

    // Filter sources by notebook if notebookId is provided
    final List<Source> filteredSources = notebookId != null
        ? sources.where((s) => s.notebookId == notebookId).toList()
        : sources;

    debugPrint(
        '[ArtifactProvider] Filtered sources for notebook $notebookId: ${filteredSources.length}');

    // Log source content lengths
    for (final source in filteredSources.take(3)) {
      final contentPreview = source.content.length > 50
          ? '${source.content.substring(0, 50)}...'
          : source.content;
      debugPrint(
          '[ArtifactProvider] Source "${source.title}" content length: ${source.content.length}, preview: $contentPreview');
    }

    if (filteredSources.isEmpty) {
      debugPrint('[ArtifactProvider] No sources found, returning placeholder');
      return _getPlaceholderContent(type);
    }

    // Build source content for AI
    final sourceContent = await _buildSourceContent(
      filteredSources,
      objective: _objectiveForArtifactType(type),
    );
    debugPrint(
        '[ArtifactProvider] Built source content length: ${sourceContent.length}');

    if (sourceContent.trim().isEmpty) {
      debugPrint(
          '[ArtifactProvider] Source content is empty, sources may have no content');
      return _getPlaceholderContent(type);
    }

    try {
      debugPrint('[ArtifactProvider] Attempting AI generation for type: $type');
      switch (type) {
        case 'study-guide':
          return await _generateStudyGuideWithAI(
              sourceContent, filteredSources);
        case 'brief':
          return await _generateBriefWithAI(sourceContent, filteredSources);
        case 'faq':
          return await _generateFAQWithAI(sourceContent, filteredSources);
        case 'timeline':
          return await _generateTimelineWithAI(sourceContent, filteredSources);
        case 'mind-map':
          return await _generateMindMapWithAI(sourceContent, filteredSources);
        default:
          return _getPlaceholderContent(type);
      }
    } catch (e) {
      debugPrint('[ArtifactProvider] AI generation failed: $e');
      debugPrint('[ArtifactProvider] Falling back to basic extraction');
      // Fallback to basic extraction
      switch (type) {
        case 'study-guide':
          return await _generateStudyGuide(filteredSources, vectorStore);
        case 'brief':
          return await _generateBrief(filteredSources, vectorStore);
        case 'faq':
          return await _generateFAQ(filteredSources, vectorStore);
        case 'timeline':
          return await _generateTimeline(filteredSources, vectorStore);
        case 'mind-map':
          return await _generateMindMap(filteredSources, vectorStore);
        default:
          return _getPlaceholderContent(type);
      }
    }
  }

  Future<String> _buildSourceContent(
    List<Source> sources, {
    required String objective,
  }) async {
    // Filter out sources with no real content (e.g., media placeholders)
    final validSources = sources.where((s) {
      final content = s.content;
      // Skip media placeholders and empty content
      if (content.isEmpty || content.startsWith('media://')) {
        debugPrint(
            '[ArtifactProvider] Skipping source "${s.title}" - no text content');
        return false;
      }
      return true;
    }).toList();

    debugPrint(
        '[ArtifactProvider] Valid sources with content: ${validSources.length}/${sources.length}');

    if (validSources.isEmpty) {
      return '';
    }

    final contextText =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: validSources,
      objective: objective,
    );

    debugPrint(
        '[ArtifactProvider] Built source content: ${contextText.length} chars from ${validSources.length} valid sources');
    return contextText;
  }

  String _objectiveForArtifactType(String type) {
    switch (type) {
      case 'study-guide':
        return 'Create a study guide that organizes the notebook into key concepts, important details, summaries, and study tips.';
      case 'brief':
        return 'Create an executive brief with the most important findings, analysis, recommendations, and conclusions.';
      case 'faq':
        return 'Create an FAQ that covers the most important notebook topics with clear, grounded answers.';
      case 'timeline':
        return 'Create a timeline that extracts the most important events, milestones, or developments in order.';
      case 'mind-map':
        return 'Create a mind map that highlights the central topic, major branches, supporting ideas, and relationships.';
      default:
        return 'Summarize the notebook sources into a clear, high-signal artifact.';
    }
  }

  Future<String> _generateStudyGuideWithAI(
      String sourceContent, List<Source> sources) async {
    final prompt = '''
You are an expert educator. Create a comprehensive study guide based on the following source materials.

SOURCE MATERIALS:
$sourceContent

Create a well-structured study guide with:
1. **Overview** - Brief introduction to the topic
2. **Key Concepts** - Main ideas and definitions (use bullet points)
3. **Important Details** - Supporting information and examples
4. **Summary Points** - Quick review items
5. **Study Tips** - How to effectively learn this material

Format the output in clean Markdown. Be thorough but concise.
''';
    return await _generateWithAI(prompt);
  }

  Future<String> _generateBriefWithAI(
      String sourceContent, List<Source> sources) async {
    final prompt = '''
You are a senior analyst. Create an executive briefing document based on the following source materials.

SOURCE MATERIALS:
$sourceContent

Create a professional briefing document with:
1. **Executive Summary** - Key takeaways in 2-3 sentences
2. **Key Findings** - Main insights from the sources (bullet points)
3. **Analysis** - Deeper examination of important points
4. **Recommendations** - Actionable next steps
5. **Conclusion** - Final thoughts

Format the output in clean Markdown. Be direct and actionable.
''';
    return await _generateWithAI(prompt);
  }

  Future<String> _generateFAQWithAI(
      String sourceContent, List<Source> sources) async {
    final prompt = '''
You are a helpful assistant. Create a comprehensive FAQ based on the following source materials.

SOURCE MATERIALS:
$sourceContent

Generate 8-12 frequently asked questions and answers that:
1. Cover the most important topics from the sources
2. Address common questions someone might have
3. Provide clear, accurate answers based on the source content
4. Range from basic to more advanced questions

Format as:
**Q: [Question]**
A: [Answer]

Use clean Markdown formatting.
''';
    return await _generateWithAI(prompt);
  }

  Future<String> _generateTimelineWithAI(
      String sourceContent, List<Source> sources) async {
    final prompt = '''
You are a historian and analyst. Create a timeline based on the following source materials.

SOURCE MATERIALS:
$sourceContent

Create a chronological timeline that:
1. Identifies key events, milestones, or developments mentioned in the sources
2. Orders them chronologically (use dates if available, or logical sequence)
3. Provides brief descriptions for each event
4. Shows the progression and relationships between events

Format as:
## Timeline

### [Date/Period 1]
**[Event Title]**
[Description]

### [Date/Period 2]
**[Event Title]**
[Description]

If no specific dates are mentioned, create a logical sequence of events or concepts.
Use clean Markdown formatting.
''';
    return await _generateWithAI(prompt);
  }

  Future<String> _generateMindMapWithAI(
      String sourceContent, List<Source> sources) async {
    final prompt = '''
You are a knowledge architect. Create a mind map structure based on the following source materials.

SOURCE MATERIALS:
$sourceContent

Create a hierarchical mind map that:
1. Identifies the central topic/theme
2. Shows main branches (major concepts)
3. Shows sub-branches (supporting ideas)
4. Highlights connections between concepts

Format as a text-based mind map:

# [Central Topic]

## Branch 1: [Main Concept]
- Sub-topic 1.1
  - Detail
  - Detail
- Sub-topic 1.2
  - Detail

## Branch 2: [Main Concept]
- Sub-topic 2.1
- Sub-topic 2.2

## Connections
- [Concept A] ↔ [Concept B]: [relationship]
- [Concept C] → [Concept D]: [relationship]

Use clean Markdown formatting with clear hierarchy.
''';
    return await _generateWithAI(prompt);
  }

  String _getPlaceholderContent(String type) {
    switch (type) {
      case 'study-guide':
        return '''# Study Guide

## Key Concepts
*No sources available yet. Add some sources to generate a comprehensive study guide.*

## Important Topics
* Study materials will appear here once you add sources

## Summary Points
* Add PDFs, web pages, or text content to get started''';
      case 'brief':
        return '''# Executive Brief

## Overview
*No sources available for analysis. Add sources to generate insights.*

## Key Findings
* Add content to see actionable insights

## Recommendations
* Sources needed for data-driven recommendations

## Next Steps
1. Add relevant sources
2. Generate comprehensive brief''';
      case 'faq':
        return '''# Frequently Asked Questions

## Common Questions
**Q: What content is available?**
A: Add sources to generate relevant FAQs based on your materials.

**Q: How do I get started?**
A: Upload PDFs, paste text, or add web links to build your knowledge base.

**Q: What types of sources are supported?**
A: Text content, PDF documents, and web pages.

## Additional Questions
*Add sources to generate more specific FAQs based on your content.*''';
      case 'timeline':
        return '''# Timeline

## No Events Found
*Add sources containing historical information or dated events to generate a timeline.*

## How to Create Timeline
1. Add sources with chronological data
2. Include dates, events, or milestones
3. Generate timeline visualization

## Example Timeline Structure
- **Event 1**: Description
- **Event 2**: Description
- **Event 3**: Description''';
      case 'mind-map':
        return '''# Mind Map

## Central Topic
*Add sources to generate a mind map of key concepts and relationships.*

## Main Branches
* **Concept 1**: *Add content to see related ideas*
* **Concept 2**: *Add content to see connections*
* **Concept 3**: *Add content to see relationships*

## Sub-branches
*Detailed connections will appear once you add sources.*

## Connections
*Relationship mapping requires source content.*''';
      default:
        return 'Generated content';
    }
  }

  Future<String> _generateStudyGuide(
      List<Source> sources, VectorStore vectorStore) async {
    // Extract key concepts from sources using RAG
    const conceptsQuery = "key concepts main ideas important points";
    final retrieved = await vectorStore.search(conceptsQuery, topK: 8);

    if (retrieved.isEmpty) {
      // If no chunks, generate from source content directly
      if (sources.isNotEmpty) {
        final sourceContent = sources
            .map((s) {
              final content = s.content as String? ?? '';
              final preview = content.length > 200
                  ? '${content.substring(0, 200)}...'
                  : content;
              return "• **${s.title}**: $preview";
            })
            .take(5)
            .join("\n\n");

        return '''# Study Guide

## Key Concepts
Based on your ${sources.length} source${sources.length > 1 ? 's' : ''}:

$sourceContent

## Important Topics
${sources.map((s) => "• ${s.title}").join("\n")}

## Summary Points
* Review the content from your sources above
* Focus on the main ideas and key information
* Use this guide to organize your learning

## Note
💡 For better study guides with AI-powered insights, ensure your sources are properly processed. The system will automatically extract key concepts and create more detailed summaries.''';
      }
      return _getPlaceholderContent('study-guide');
    }

    final concepts = retrieved
        .map((r) =>
            "• ${r.$1.text.substring(0, r.$1.text.length.clamp(0, 150))}")
        .take(8)
        .join("\n");

    return '''# Study Guide

## Key Concepts
$concepts

## Important Topics
Based on your ${sources.length} source${sources.length > 1 ? 's' : ''}:
${sources.map((s) => "• ${s.title}").join("\n")}

## Summary Points
${retrieved.map((r) => "• ${r.$1.text.substring(0, r.$1.text.length.clamp(0, 100))}...").take(5).join("\n")}

## Key Takeaways
* Review the main concepts above
* Focus on the most relevant information from your sources
* Use this guide to reinforce your understanding''';
  }

  Future<String> _generateBrief(
      List<Source> sources, VectorStore vectorStore) async {
    const insightsQuery = "insights findings conclusions recommendations";
    final retrieved = await vectorStore.search(insightsQuery, topK: 6);

    if (retrieved.isEmpty) {
      if (sources.isNotEmpty) {
        final sourceList =
            sources.map((s) => "• ${s.title}").take(10).join("\n");
        return '''# Executive Brief

## Overview
Analysis of ${sources.length} source${sources.length > 1 ? 's' : ''}.

## Sources Analyzed
$sourceList

## Key Findings
Your sources contain valuable information that can be analyzed for insights once processing is complete.

## Recommendations
• Review your source materials thoroughly
• Identify key themes and patterns
• Extract actionable insights from the content

## Next Steps
1. Ensure all sources are properly loaded
2. Review the content for main ideas
3. Identify actionable items
4. Add more sources for comprehensive analysis''';
      }
      return _getPlaceholderContent('brief');
    }

    final keyPoints = retrieved
        .map((r) =>
            "• ${r.$1.text.substring(0, r.$1.text.length.clamp(0, 120))}")
        .take(6)
        .join("\n");

    return '''# Executive Brief

## Overview
Analysis of ${sources.length} source${sources.length > 1 ? 's' : ''} providing comprehensive insights.

## Key Findings
$keyPoints

## Recommendations
Based on the analyzed content:
• Focus on the most critical information identified
• Prioritize actionable insights from your sources
• Consider the relationships between different concepts

## Next Steps
1. Review the key findings above
2. Identify actionable items from your sources
3. Implement insights in your work or studies
4. Add additional sources for deeper analysis''';
  }

  Future<String> _generateFAQ(
      List<Source> sources, VectorStore vectorStore) async {
    const questionsQuery = "what how why when where who";
    final retrieved = await vectorStore.search(questionsQuery, topK: 6);

    if (retrieved.isEmpty) {
      if (sources.isNotEmpty) {
        return '''# Frequently Asked Questions

## Common Questions

**Q: What sources are available?**
A: You have ${sources.length} source${sources.length > 1 ? 's' : ''} loaded: ${sources.map((s) => s.title).take(3).join(", ")}${sources.length > 3 ? "..." : ""}.

**Q: How can I get more detailed FAQs?**
A: The system will automatically generate more specific questions and answers once your sources are fully processed.

**Q: What types of content do I have?**
A: Your sources include: ${sources.map((s) => s.type).toSet().join(", ")}.

**Q: How accurate is this information?**
A: All answers are based directly on your uploaded sources and materials.

**Q: Can I add more questions?**
A: Yes, continue exploring your sources to discover additional insights and generate more FAQs.''';
      }
      return _getPlaceholderContent('faq');
    }

    final faqs = retrieved
        .map((r) {
          final text = r.$1.text;
          final question = text.split('.').first.trim();
          final answer = text.length > question.length
              ? text.substring(question.length).trim()
              : "Based on your source content.";
          return "**Q: $question?**\nA: ${answer.isNotEmpty ? answer : "This information is available in your sources."}";
        })
        .take(5)
        .join("\n\n");

    return '''# Frequently Asked Questions

## Common Questions
$faqs

## Additional Questions
**Q: What other information is available?**
A: Your ${sources.length} source${sources.length > 1 ? 's' : ''} contain${sources.length > 1 ? '' : 's'} extensive information that can be explored further.

**Q: How accurate is this information?**
A: All answers are based directly on your uploaded sources and materials.

**Q: Can I add more questions?**
A: Yes, continue exploring your sources to discover additional insights and generate more FAQs.''';
  }

  Future<String> _generateTimeline(
      List<Source> sources, VectorStore vectorStore) async {
    const timelineQuery = "timeline history dates events chronological order";
    final retrieved = await vectorStore.search(timelineQuery, topK: 8);

    if (retrieved.isEmpty) {
      if (sources.isNotEmpty) {
        final sourceList =
            sources.map((s) => "• ${s.title}").take(10).join("\n");
        return '''# Timeline

## Sources Available
$sourceList

## Creating Your Timeline
Once your sources are processed, the system will automatically extract:
• Dates and time periods
• Historical events
• Chronological sequences
• Key milestones

## Key Periods
Based on your ${sources.length} source${sources.length > 1 ? 's' : ''}

## Note
💡 Add sources with dates, events, or historical information for a more detailed timeline.''';
      }
      return _getPlaceholderContent('timeline');
    }

    final events = retrieved
        .map((r) {
          final text = r.$1.text;
          final dateMatch = RegExp(
                  r'\b(?:January|February|March|April|May|June|July|August|September|October|November|December|\d{4})')
              .firstMatch(text);
          final date = dateMatch?.group(0) ?? "Various dates";
          final description = text.substring(0, text.length.clamp(0, 80));
          return "• **$date**: $description...";
        })
        .take(6)
        .join("\n");

    return '''# Timeline

## Chronological Overview
$events

## Key Periods
Based on your ${sources.length} source${sources.length > 1 ? 's' : ''}:
${sources.map((s) => "• ${s.title}").join("\n")}

## Historical Context
The timeline above represents key events and milestones identified from your source materials.

## Additional Events
*More events may be available in your sources. Consider exploring specific time periods or themes.*''';
  }

  Future<String> _generateMindMap(
      List<Source> sources, VectorStore vectorStore) async {
    const conceptsQuery =
        "concepts relationships connections main ideas themes";
    final retrieved = await vectorStore.search(conceptsQuery, topK: 8);

    if (retrieved.isEmpty) {
      if (sources.isNotEmpty) {
        final sourceList =
            sources.map((s) => "• **${s.title}**").take(8).join("\n");
        return '''# Mind Map

## Central Topic
Your Knowledge Base (${sources.length} sources)

## Main Branches
$sourceList

## Creating Connections
Once your sources are processed, the system will:
• Extract key concepts and themes
• Identify relationships between ideas
• Map connections across sources
• Visualize knowledge structure

## Note
💡 The mind map will become more detailed as the system analyzes your content.''';
      }
      return _getPlaceholderContent('mind-map');
    }

    final mainConcepts = retrieved.take(4).map((r) {
      final text = r.$1.text;
      final concept = text.split('.').first.trim();
      return "• **$concept**";
    }).join("\n");

    const subConcepts =
        "• Supporting details\n• Related concepts\n• Key examples\n• Important connections";

    return '''# Mind Map

## Central Topic
*Based on your ${sources.length} source${sources.length > 1 ? 's' : ''}*

## Main Branches
$mainConcepts

## Sub-branches
$subConcepts

## Connections
* **Concept 1** → Related ideas and examples
* **Concept 2** → Supporting evidence and details
* **Concept 3** → Applications and implications
* **Concept 4** → Connections to other topics

## Relationships
The mind map shows how different concepts from your sources connect and relate to each other, providing a comprehensive overview of the subject matter.''';
  }
}

final artifactProvider =
    StateNotifierProvider<ArtifactNotifier, List<Artifact>>(
        (ref) => ArtifactNotifier(ref));
