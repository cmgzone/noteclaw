import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../../core/auth/custom_auth_service.dart';
import '../../core/api/api_service.dart';
import '../../core/rag/chunk.dart';
import '../../core/rag/smart_ingestion_provider.dart';
import '../gamification/gamification_provider.dart';
import 'source.dart';

class SourceNotifier extends StateNotifier<List<Source>> {
  SourceNotifier(this.ref) : super([]) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    await loadSources();
  }

  Future<void> loadSources() async {
    try {
      final authState = ref.read(customAuthStateProvider);
      final user = authState.user;
      if (user == null) {
        debugPrint('⚠️ Source loadSources: No user logged in');
        state = [];
        return;
      }

      debugPrint('✅ Source loadSources: user=${user.uid}');

      final apiService = ref.read(apiServiceProvider);

      // Get all notebooks first
      final notebooks = await apiService.getNotebooks();

      // Get sources for each notebook in parallel
      final sourcesFutures = notebooks.map((notebook) async {
        try {
          return await apiService.getSourcesForNotebook(notebook['id']);
        } catch (e) {
          debugPrint(
              '⚠️ Error loading sources for notebook ${notebook['id']}: $e');
          return <Map<String, dynamic>>[];
        }
      });

      final sourcesLists = await Future.wait(sourcesFutures);
      List<Map<String, dynamic>> allSources =
          sourcesLists.expand((i) => i).toList();

      debugPrint('📊 Loaded ${allSources.length} sources');

      state = allSources.map((sourceData) {
        debugPrint(
            '📝 Processing source: ${sourceData['id']} - ${sourceData['title']}');

        // Extract metadata if present (for GitHub sources and agent-created sources)
        Map<String, dynamic> metadata = {};
        if (sourceData['metadata'] != null && sourceData['metadata'] is Map) {
          metadata = Map<String, dynamic>.from(sourceData['metadata'] as Map);
        }

        return Source(
          id: sourceData['id'] as String,
          notebookId: sourceData['notebook_id'] as String,
          title: sourceData['title'] as String,
          type: sourceData['type'] as String,
          addedAt: DateTime.parse(sourceData['created_at'] as String),
          content: sourceData['content'] as String? ?? '',
          imageUrl: sourceData['imageUrl'] as String?,
          tagIds: [], // Tags will be handled separately if needed
          metadata: metadata,
        );
      }).toList();

      debugPrint('✅ Loaded ${state.length} sources successfully');

      // Ingest all sources into vector store for RAG and artifacts
      Future.microtask(() => _ingestAllSources());
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading sources: $e');
      debugPrint('Stack trace: $stackTrace');
      state = [];
    }
  }

  Future<void> deleteSource(String sourceId) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteSource(sourceId);
      state = state.where((s) => s.id != sourceId).toList();
    } catch (e) {
      debugPrint('Error deleting source: $e');
    }
  }

  Future<void> updateSource({
    required String sourceId,
    String? title,
    String? content,
    String? url,
    List<String>? tagIds,
  }) async {
    try {
      final apiService = ref.read(apiServiceProvider);

      await apiService.updateSource(
        sourceId,
        title: title,
        content: content,
        url: url,
      );

      state = state.map((s) {
        if (s.id == sourceId) {
          return s.copyWith(
            title: title ?? s.title,
            content: content ?? s.content,
            tagIds: tagIds ?? s.tagIds,
          );
        }
        return s;
      }).toList();
    } catch (e) {
      debugPrint('Error updating source: $e');
    }
  }

  /// Ingest all loaded sources into the vector store for RAG queries and artifact generation
  Future<void> _ingestAllSources() async {
    if (state.isEmpty) return;

    debugPrint('🔄 Ingesting ${state.length} sources into vector store...');

    for (final source in state) {
      try {
        // Read the FutureProvider and await its future so that any error is
        // caught here rather than escaping to Flutter's unhandled-error handler.
        await ref.read(ingestionProvider(source).future);
      } catch (e) {
        debugPrint('⚠️ Failed to ingest source ${source.id}: $e');
      }
    }

    debugPrint('✅ Ingestion complete for all sources');
  }

  Future<void> addSource({
    required String title,
    required String type,
    String? content,
    String? url,
    Uint8List? mediaBytes,
    String? notebookId,
  }) async {
    try {
      final authState = ref.read(customAuthStateProvider);
      final user = authState.user;
      if (user == null) {
        debugPrint('⚠️ Error: No user logged in - cannot add source');
        throw Exception('User must be logged in to add sources');
      }

      final apiService = ref.read(apiServiceProvider);

      debugPrint(
          'SourceNotifier addSource: title=$title, type=$type, user=${user.uid}');

      // Get or use notebook
      String finalNotebookId;
      if (notebookId == null) {
        debugPrint('No notebookId provided, using first available notebook');
        final notebooks = await apiService.getNotebooks();

        if (notebooks.isNotEmpty) {
          finalNotebookId = notebooks.first['id'] as String;
          debugPrint('Using existing notebook: $finalNotebookId');
        } else {
          // Create a default notebook
          final newNotebook = await apiService.createNotebook(
            title: 'My Notebook',
            description: 'Default notebook',
          );
          finalNotebookId = newNotebook['id'] as String;
          debugPrint('Created new default notebook: $finalNotebookId');
        }
      } else {
        finalNotebookId = notebookId;
      }

      // Handle image data
      String? imageUrl;
      if (mediaBytes != null) {
        // Convert bytes to base64 data URL
        final base64Image = base64Encode(mediaBytes);
        imageUrl = 'data:image/png;base64,$base64Image';
      }

      debugPrint('Saving source to API: notebookId=$finalNotebookId');
      final sourceData = await apiService.createSource(
        notebookId: finalNotebookId,
        type: type,
        title: title,
        content: content,
        url: url,
        imageUrl: imageUrl,
      );

      final source = Source(
        id: sourceData['id'] as String,
        notebookId: sourceData['notebook_id'] as String,
        title: sourceData['title'] as String,
        type: sourceData['type'] as String,
        addedAt: DateTime.parse(sourceData['created_at'] as String),
        content: sourceData['content'] as String? ?? '',
        imageUrl: sourceData['imageUrl'] as String?,
        metadata:
            sourceData['metadata'] != null && sourceData['metadata'] is Map
                ? Map<String, dynamic>.from(sourceData['metadata'] as Map)
                : {},
      );

      state = [source, ...state];
      debugPrint('Source added successfully, total sources: ${state.length}');

      // Track gamification
      ref.read(gamificationProvider.notifier).trackSourceAdded();

      // Trigger ingestion in the background — observe the future so errors
      // are caught and don't escape to Flutter's global error handler.
      try {
        debugPrint('Triggering ingestion for source: ${source.id}');
        if (source.notebookId.isNotEmpty) {
          ref.read(ingestionProvider(source).future).catchError((e) {
            debugPrint('Warning: Ingestion failed for source ${source.id}: $e');
            return <Chunk>[];
          });
        }
      } catch (e) {
        debugPrint('Warning: Ingestion failed for source ${source.id}: $e');
      }

      // Refresh from API
      await Future.delayed(const Duration(milliseconds: 100));
      await loadSources();
    } catch (e, stackTrace) {
      debugPrint('Error adding source: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  Future<List<Source>> getSourcesForNotebook(String notebookId) async {
    // If state is empty, try loading first
    if (state.isEmpty) {
      await loadSources();
    }
    return state.where((s) => s.notebookId == notebookId).toList();
  }
}

final sourceProvider = StateNotifierProvider<SourceNotifier, List<Source>>(
  (ref) {
    // Watch auth state to trigger rebuild on login/logout
    ref.watch(customAuthStateProvider);
    return SourceNotifier(ref);
  },
);
