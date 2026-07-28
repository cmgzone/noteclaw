import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'notebook.dart';
import '../gamification/gamification_provider.dart';
import '../../core/auth/custom_auth_service.dart';
import '../../core/api/api_service.dart';
import '../../core/services/activity_logger_service.dart';

final notebookInitialLoadCompleteProvider = StateProvider<bool>((ref) => false);

class NotebookNotifier extends StateNotifier<List<Notebook>> {
  NotebookNotifier(this.ref) : super([]) {
    _init();
  }

  final Ref ref;
  bool _isLoading = false;

  Future<void> _init() async {
    debugPrint('🚀 NotebookNotifier _init starting...');

    // Listen to auth state changes and reload notebooks
    ref.listen(customAuthStateProvider, (previous, next) {
      debugPrint(
          '🔔 Auth state changed: ${previous?.status} -> ${next.status}');
      debugPrint(
          '🔔 isAuthenticated: ${next.isAuthenticated}, user: ${next.user?.uid}');
      if (next.isAuthenticated && !_isLoading) {
        ref.read(notebookInitialLoadCompleteProvider.notifier).state = false;
        debugPrint(
            '🔄 Auth state changed to authenticated, reloading notebooks...');
        loadNotebooks();
      } else if (!next.isAuthenticated) {
        ref.read(notebookInitialLoadCompleteProvider.notifier).state = true;
        if (mounted) state = [];
      }
    });

    // Wait a bit for auth to initialize before loading
    final authState = ref.read(customAuthStateProvider);
    debugPrint(
        '🔍 Initial auth state: status=${authState.status}, isAuthenticated=${authState.isAuthenticated}');

    if (authState.isAuthenticated) {
      debugPrint('✅ Already authenticated, loading notebooks...');
      await loadNotebooks();
    } else if (authState.status == AuthStatus.initial ||
        authState.status == AuthStatus.loading) {
      debugPrint('⏳ Auth still initializing, waiting...');
      // Don't load yet - wait for auth state change
    } else {
      debugPrint('❌ Not authenticated, skipping notebook load');
      ref.read(notebookInitialLoadCompleteProvider.notifier).state = true;
    }
  }

  Future<void> loadNotebooks() async {
    if (_isLoading) {
      debugPrint('⏳ Already loading notebooks, skipping...');
      return;
    }

    _isLoading = true;
    ref.read(notebookInitialLoadCompleteProvider.notifier).state = false;

    try {
      final authState = ref.read(customAuthStateProvider);
      final user = authState.user;
      debugPrint(
          '🔍 Auth state: isAuthenticated=${authState.isAuthenticated}, status=${authState.status}, user=${user?.uid}');

      if (user == null) {
        debugPrint('⚠️ NotebookNotifier loadNotebooks: No user logged in');
        debugPrint('⚠️ Auth status: ${authState.status}');
        if (mounted) state = [];
        _isLoading = false;
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      debugPrint(
          '📚 Loading notebooks for user=${user.uid}, email=${user.email}');

      final notebooks = await apiService.getNotebooks();
      debugPrint('📚 API returned ${notebooks.length} notebooks');

      if (notebooks.isEmpty) {
        debugPrint('⚠️ No notebooks returned from API');
        debugPrint('⚠️ This could mean:');
        debugPrint('   1. User has no notebooks in database');
        debugPrint('   2. Token is invalid/expired');
        debugPrint('   3. User ID mismatch between app and backend');
        if (!mounted) return; // Guard added
        state = [];
        _isLoading = false;
        ref.read(notebookInitialLoadCompleteProvider.notifier).state = true;
        return;
      }

      // Log first notebook for debugging
      if (notebooks.isNotEmpty) {
        debugPrint('📖 First notebook data: ${notebooks.first}');
        debugPrint('📖 First notebook user_id: ${notebooks.first['user_id']}');
        debugPrint('📖 Current user uid: ${user.uid}');

        // Check if user IDs match
        if (notebooks.first['user_id'] != user.uid) {
          debugPrint('⚠️ WARNING: User ID mismatch!');
          debugPrint('   Notebook user_id: ${notebooks.first['user_id']}');
          debugPrint('   Current user uid: ${user.uid}');
        }
      }

      final loadedNotebooks = notebooks.map((notebook) {
        debugPrint('📖 Parsing: ${notebook['id']} - ${notebook['title']}');
        return Notebook.fromJson(notebook);
      }).toList();

      if (mounted) {
        state = loadedNotebooks;
        debugPrint('✅ Loaded ${state.length} notebooks into state');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error loading notebooks: $e');
      debugPrint('Stack trace: $stackTrace');
      // Don't reset state on error - keep existing notebooks
    } finally {
      _isLoading = false;
      ref.read(notebookInitialLoadCompleteProvider.notifier).state = true;
    }
  }

  /// Force refresh notebooks from the backend
  Future<void> refresh() async {
    debugPrint('🔄 Force refreshing notebooks...');
    await loadNotebooks();
  }

  Future<String?> addNotebook(String title, {String? category}) async {
    try {
      final authState = ref.read(customAuthStateProvider);
      final user = authState.user;
      if (user == null) {
        debugPrint('❌ NotebookNotifier addNotebook: No user logged in');
        return null;
      }

      final apiService = ref.read(apiServiceProvider);

      debugPrint(
          '📝 NotebookNotifier addNotebook: title=$title, category=$category, user=${user.uid}');

      final notebookData = await apiService.createNotebook(
        title: title,
        description: '',
        category: category ?? 'General',
      );

      debugPrint('📝 API response: $notebookData');

      final notebook = Notebook.fromJson(notebookData);

      // Update state immediately with the new notebook
      if (mounted) {
        final currentState = [...state];
        state = [notebook, ...currentState];
        debugPrint('✅ Notebook added to state, count=${state.length}');
      }

      // Track gamification (don't await to avoid blocking)
      ref.read(gamificationProvider.notifier).trackNotebookCreated();

      // Log activity to social feed
      ref.read(activityLoggerProvider).logNotebookCreated(title, notebook.id);

      return notebook.id;
    } catch (e, stackTrace) {
      debugPrint('❌ Error adding notebook: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow; // Rethrow so the dialog can show the error
    }
  }

  Future<void> deleteNotebook(String notebookId) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.deleteNotebook(notebookId);
      if (mounted) {
        state = state.where((n) => n.id != notebookId).toList();
      }
    } catch (e) {
      debugPrint('Error deleting notebook: $e');
    }
  }

  Future<void> updateNotebook(String notebookId, String newTitle) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final now = DateTime.now();

      await apiService.updateNotebook(
        notebookId,
        title: newTitle,
      );

      if (mounted) {
        state = state.map((n) {
          if (n.id == notebookId) {
            return n.copyWith(
              title: newTitle,
              updatedAt: now,
            );
          }
          return n;
        }).toList();
      }
    } catch (e) {
      debugPrint('Error updating notebook: $e');
    }
  }

  Future<void> updateNotebookCover(
      String notebookId, String? coverImage) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      final now = DateTime.now();

      await apiService.updateNotebook(
        notebookId,
        coverImage: coverImage,
      );

      if (mounted) {
        state = state.map((n) {
          if (n.id == notebookId) {
            return n.copyWith(
              coverImage: coverImage,
              updatedAt: now,
            );
          }
          return n;
        }).toList();
      }

      debugPrint('Notebook cover updated: $notebookId');
    } catch (e) {
      debugPrint('Error updating notebook cover: $e');
      rethrow;
    }
  }
}

final notebookProvider =
    StateNotifierProvider<NotebookNotifier, List<Notebook>>(
  (ref) {
    // Watch auth state to trigger rebuild on login/logout
    ref.watch(customAuthStateProvider);
    return NotebookNotifier(ref);
  },
);
