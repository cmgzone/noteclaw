import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ebook_project.dart';
import '../models/ebook_chapter.dart';
import '../models/ebook_image.dart';
import '../ebook_provider.dart';
import 'research_agent.dart';
import 'content_agent.dart';
import 'designer_agent.dart';
import '../../sources/source_provider.dart';
import '../../gamification/gamification_provider.dart';
import '../../../core/services/wakelock_service.dart';
import '../../../core/ai/deep_research_service.dart';
import '../../../core/services/overlay_bubble_service.dart';

class EbookOrchestrator extends StateNotifier<EbookProject?> {
  final Ref ref;

  EbookOrchestrator(this.ref) : super(null);

  Future<void> startGeneration(EbookProject project,
      {List<String> context = const []}) async {
    // Keep screen awake during ebook generation (can take several minutes)
    await wakelockService.acquire();

    // Show overlay bubble
    await overlayBubbleService.show(status: 'Initializing Ebook Agent...');

    state = project.copyWith(
        status: EbookStatus.generating, currentPhase: 'Initializing...');

    try {
      await ref.read(ebookProvider.notifier).updateEbook(state!);

      // 0. Context Gathering (if Notebook selected)
      state = state!.copyWith(currentPhase: 'Loading notebook sources...');
      await overlayBubbleService.updateStatus('Loading sources...');

      List<String> effectiveContext = [...context];
      List<String> webSearchedImages = [];
      String? deepResearchSummary;

      if (project.notebookId != null) {
        final sources = await ref
            .read(sourceProvider.notifier)
            .getSourcesForNotebook(project.notebookId!);
        effectiveContext.addAll(
            sources.map((s) => "Source: ${s.title}\nContent: ${s.content}"));
      }

      // 0.5 Deep Research Phase (if enabled)
      if (project.useDeepResearch) {
        state = state!.copyWith(
            currentPhase: 'Deep Research Agent: Searching the web...');
        await overlayBubbleService.updateStatus('Deep Researching...');

        final deepResearchService = ref.read(deepResearchServiceProvider);

        try {
          // Use a completer with timeout for better control
          bool researchComplete = false;
          final researchFuture = () async {
            await for (final update in deepResearchService.research(
              query: '${project.topic} for ${project.targetAudience}',
              notebookId: project.notebookId ?? '',
            )) {
              if (researchComplete) break;

              state = state!
                  .copyWith(currentPhase: 'Deep Research: ${update.status}');

              // Update bubble with research progress occasionally
              if (update.status.contains('Searching') ||
                  update.status.contains('Analyzing')) {
                await overlayBubbleService
                    .updateStatus('Researching: ${update.status}');
              }

              if (update.result != null) {
                deepResearchSummary = update.result;
                effectiveContext
                    .add('Deep Research Summary:\n${update.result}');
                researchComplete = true;
                break;
              }
            }
          }();

          // Wait with timeout
          await researchFuture.timeout(
            const Duration(minutes: 4),
            onTimeout: () {
              debugPrint(
                  '[EbookOrchestrator] Deep research timed out after 4 minutes');
              researchComplete = true;
            },
          );
        } catch (e) {
          debugPrint('[EbookOrchestrator] Deep research error: $e');
          state = state!.copyWith(
              currentPhase: 'Deep Research failed, continuing without it...');
          await overlayBubbleService
              .updateStatus('Research skipped, continuing...');
          await Future.delayed(const Duration(seconds: 1));
          // Continue without deep research results
        }

        state = state!.copyWith(
          deepResearchSummary: deepResearchSummary,
          webSearchedImages: webSearchedImages,
        );
      }

      // 1. Research Phase
      state =
          state!.copyWith(currentPhase: 'Research Agent: Gathering facts...');
      await overlayBubbleService.updateStatus('Gathering facts...');
      final researchAgent = ref.read(researchAgentProvider);
      final researchSummary = await researchAgent.researchTopic(project.topic,
          context: effectiveContext,
          notebookId: project.notebookId,
          model: project.selectedModel);

      //2. Outline Phase
      state =
          state!.copyWith(currentPhase: 'Content Agent: Creating outline...');
      await overlayBubbleService.updateStatus('Creating outline...');
      final contentAgent = ref.read(contentAgentProvider);
      final chapters =
          await contentAgent.generateOutline(project, researchSummary);

      state =
          state!.copyWith(chapters: chapters, currentPhase: 'Outline ready!');

      // 3. Cover Art Phase - Always use AI for cover
      state = state!
          .copyWith(currentPhase: 'Designer Agent: Creating cover art...');
      await overlayBubbleService.updateStatus('Designing cover art...');
      final designerAgent = ref.read(designerAgentProvider);
      final coverUrl = await designerAgent.generateCoverArt(project);

      state = state!
          .copyWith(coverImageUrl: coverUrl, currentPhase: 'Cover designed!');

      // 4. Chapter Generation Phase (Parallel or Sequential)
      // For now, sequential to avoid rate limits and better state updates
      List<EbookChapter> updatedChapters = [];
      int webImageIndex = 0;

      for (var i = 0; i < chapters.length; i++) {
        final chapter = chapters[i];
        final progress = ((i / chapters.length) * 100).toInt();

        state = state!.copyWith(
            currentPhase:
                'Writing chapter ${i + 1}/${chapters.length}: ${chapter.title}...');

        await overlayBubbleService.updateStatus(
          'Writing Ch ${i + 1}: ${chapter.title}',
          progress: progress,
        );

        // Update status to show this chapter is generating
        updatedChapters = [...state!.chapters];
        final index = updatedChapters.indexWhere((c) => c.id == chapter.id);
        if (index != -1) {
          updatedChapters[index] = chapter.copyWith(isGenerating: true);
          state = state!.copyWith(chapters: updatedChapters);
        }

        // Write content
        final content =
            await contentAgent.writeChapter(project, chapter, researchSummary);

        // Generate or fetch illustration based on image source setting
        String illustrationUrl;
        String imagePrompt;

        if (project.imageSource == ImageSourceType.webSearch &&
            webSearchedImages.isNotEmpty) {
          // Use web searched images
          state = state!.copyWith(
              currentPhase: 'Using web image for "${chapter.title}"...');
          illustrationUrl =
              webSearchedImages[webImageIndex % webSearchedImages.length];
          imagePrompt = 'Web image for ${chapter.title}';
          webImageIndex++;
        } else if (project.imageSource == ImageSourceType.both &&
            webSearchedImages.isNotEmpty &&
            i % 2 == 1) {
          // Alternate: odd chapters use web images
          state = state!.copyWith(
              currentPhase: 'Using web image for "${chapter.title}"...');
          illustrationUrl =
              webSearchedImages[webImageIndex % webSearchedImages.length];
          imagePrompt = 'Web image for ${chapter.title}';
          webImageIndex++;
        } else {
          // Use AI generated images
          state = state!.copyWith(
              currentPhase:
                  'Designer: Creating illustration for "${chapter.title}"...');
          await overlayBubbleService.updateStatus(
            'Illustrating Ch ${i + 1}...',
            progress: progress,
          );
          illustrationUrl = await designerAgent.generateChapterIllustration(
              chapter, "consistent book style");
          imagePrompt = 'AI illustration for ${chapter.title}';
        }

        final image = EbookImage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          prompt: imagePrompt,
          url: illustrationUrl,
          caption: chapter.title,
        );

        // Update chapter with content and image
        updatedChapters = [...state!.chapters];
        final completedIndex =
            updatedChapters.indexWhere((c) => c.id == chapter.id);
        if (completedIndex != -1) {
          updatedChapters[completedIndex] = chapter.copyWith(
            content: content,
            images: [image],
            isGenerating: false,
          );
          state = state!.copyWith(chapters: updatedChapters);
        }
      }

      state = state!.copyWith(
          status: EbookStatus.completed,
          currentPhase: 'Ebook complete! 🎉',
          updatedAt: DateTime.now());

      await overlayBubbleService.updateStatus('Ebook Complete! 🎉',
          progress: 100);
      await Future.delayed(const Duration(seconds: 2));
      await overlayBubbleService.hide();

      // Track gamification
      ref.read(gamificationProvider.notifier).trackEbookGenerated();
      ref.read(gamificationProvider.notifier).trackFeatureUsed('ebook');

      // Save completed ebook to library
      await ref.read(ebookProvider.notifier).addEbook(state!);
    } catch (e) {
      state = state!.copyWith(
          status: EbookStatus.error, currentPhase: 'Generation failed: $e');

      await overlayBubbleService.updateStatus('Error: Generation Failed');
      await Future.delayed(const Duration(seconds: 3));
      await overlayBubbleService.hide();

      // Save error state too so user can see it in library
      await ref.read(ebookProvider.notifier).updateEbook(state!);
    } finally {
      // Release wake lock when done
      await wakelockService.release();
    }
  }

  void setProject(EbookProject project) {
    state = project;
  }
}

final ebookOrchestratorProvider =
    StateNotifierProvider<EbookOrchestrator, EbookProject?>((ref) {
  return EbookOrchestrator(ref);
});
