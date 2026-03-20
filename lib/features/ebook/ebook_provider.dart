import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_service.dart';
import '../../core/auth/custom_auth_service.dart';
import '../../core/services/activity_logger_service.dart';
import 'models/ebook_project.dart';
import 'models/ebook_chapter.dart';

class EbookNotifier extends StateNotifier<List<EbookProject>> {
  final Ref ref;
  int _latestLoadToken = 0;

  EbookNotifier(this.ref) : super([]) {
    _init();
  }

  Future<void> _init() async {
    ref.listen(customAuthStateProvider, (previous, next) {
      if (next.isAuthenticated) {
        loadEbooks();
        return;
      }

      if (!next.isLoading) {
        _latestLoadToken++;
        if (mounted) {
          state = [];
        }
      }
    });

    final authState = ref.read(customAuthStateProvider);
    if (authState.isAuthenticated) {
      await loadEbooks();
    }
  }

  Future<void> loadEbooks() async {
    final authState = ref.read(customAuthStateProvider);
    if (!authState.isAuthenticated || authState.user == null) {
      _latestLoadToken++;
      if (mounted) {
        state = [];
      }
      return;
    }

    final loadToken = ++_latestLoadToken;
    final previousState = state;

    try {
      final api = ref.read(apiServiceProvider);
      final projectsData = await api.getEbookProjects();

      final projects = <EbookProject>[];
      for (var j in projectsData) {
        try {
          final project = EbookProject.fromBackendJson(j);
          // Load chapters for each project
          final chaptersData = await api.getEbookChapters(project.id);
          final updatedProject = project.copyWith(
            chapters: chaptersData
                .map((c) => EbookChapter.fromBackendJson(c))
                .toList(),
          );
          projects.add(updatedProject);
        } catch (e) {
          debugPrint('Error loading ebook project: $e');
        }
      }

      if (!mounted || loadToken != _latestLoadToken) return;
      state = projects..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading ebooks: $e');
      if (!mounted || loadToken != _latestLoadToken) return;
      state = previousState;
    }
  }

  Future<void> refresh() => loadEbooks();

  Future<bool> addEbook(EbookProject ebook) async {
    return _persistEbook(
      ebook,
      logCreation: ebook.status == EbookStatus.completed,
    );
  }

  Future<bool> updateEbook(EbookProject ebook) async {
    return _persistEbook(ebook);
  }

  Future<bool> _persistEbook(
    EbookProject ebook, {
    bool logCreation = false,
  }) async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.saveEbookProject(
        id: ebook.id,
        title: ebook.title,
        topic: ebook.topic,
        targetAudience: ebook.targetAudience,
        branding: ebook.branding.toBackendJson(),
        selectedModel: ebook.selectedModel,
        notebookId: ebook.notebookId,
        status: ebook.status.name,
        coverImage: ebook.coverImageUrl,
      );
      final savedProject =
          Map<String, dynamic>.from(response['project'] ?? response);
      final savedProjectId = savedProject['id']?.toString() ?? ebook.id;
      final persistedEbook = ebook.copyWith(
        id: savedProjectId,
        createdAt: _parseBackendDate(
              savedProject['created_at']?.toString(),
            ) ??
            ebook.createdAt,
        updatedAt: _parseBackendDate(
              savedProject['updated_at']?.toString(),
            ) ??
            DateTime.now(),
        coverImageUrl: savedProject['cover_image_url'] ??
            savedProject['cover_image'] ??
            ebook.coverImageUrl,
      );

      // If there are chapters, sync them
      if (ebook.chapters.isNotEmpty && savedProjectId.isNotEmpty) {
        try {
          await api.syncEbookChapters(
            projectId: savedProjectId,
            chapters: ebook.chapters.map((c) => c.toBackendJson()).toList(),
          );
        } catch (e) {
          debugPrint('Error syncing ebook chapters: $e');
        }
      }

      _upsertLocalState(persistedEbook);

      if (logCreation) {
        try {
          ref.read(activityLoggerProvider).logEbookCreated(
                persistedEbook.title,
                persistedEbook.id,
              );
        } catch (e) {
          debugPrint('Error logging ebook activity: $e');
        }
      }

      await loadEbooks();
      return true;
    } catch (e) {
      debugPrint('Error saving ebook: $e');
      return false;
    }
  }

  Future<void> deleteEbook(String id) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deleteEbookProject(id);
      state = state.where((e) => e.id != id).toList();
    } catch (e) {
      debugPrint('Error deleting ebook: $e');
    }
  }

  EbookProject? getEbook(String id) {
    try {
      return state.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  void _upsertLocalState(EbookProject ebook) {
    final nextState = [...state];
    final existingIndex = nextState.indexWhere((item) => item.id == ebook.id);

    if (existingIndex == -1) {
      nextState.add(ebook);
    } else {
      nextState[existingIndex] = ebook;
    }

    nextState.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    state = nextState;
  }

  DateTime? _parseBackendDate(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
}

final ebookProvider =
    StateNotifierProvider<EbookNotifier, List<EbookProject>>((ref) {
  return EbookNotifier(ref);
});
