import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_service.dart';
import '../../core/utils/app_logger.dart';
import 'models/study_group.dart';

const _logger = AppLogger('SocialSharingProvider');

// =====================================================
// Models

// =====================================================

class SharedContent {
  final String id;
  final String userId;
  final String contentType;
  final String contentId;
  final String? caption;
  final bool isPublic;
  final int viewCount;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final String? contentTitle;
  final String? contentDescription;
  final int likeCount;
  final int saveCount;
  final bool userLiked;
  final bool userSaved;

  SharedContent({
    required this.id,
    required this.userId,
    required this.contentType,
    required this.contentId,
    this.caption,
    this.isPublic = true,
    this.viewCount = 0,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.contentTitle,
    this.contentDescription,
    this.likeCount = 0,
    this.saveCount = 0,
    this.userLiked = false,
    this.userSaved = false,
  });

  factory SharedContent.fromJson(Map<String, dynamic> json) {
    return SharedContent(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      contentType: json['content_type']?.toString() ??
          json['contentType']?.toString() ??
          '',
      contentId:
          json['content_id']?.toString() ?? json['contentId']?.toString() ?? '',
      caption: json['caption']?.toString(),
      isPublic: json['is_public'] ?? json['isPublic'] ?? true,
      viewCount: _parseInt(json['view_count'] ?? json['viewCount']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ??
              json['createdAt']?.toString() ??
              '') ??
          DateTime.now(),
      username: json['username']?.toString(),
      avatarUrl:
          json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      contentTitle:
          json['content_title']?.toString() ?? json['contentTitle']?.toString(),
      contentDescription: json['content_description']?.toString() ??
          json['contentDescription']?.toString(),
      likeCount: _parseInt(json['like_count'] ?? json['likeCount']),
      saveCount: _parseInt(json['save_count'] ?? json['saveCount']),
      userLiked: json['user_liked'] ?? json['userLiked'] ?? false,
      userSaved: json['user_saved'] ?? json['userSaved'] ?? false,
    );
  }

  static int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class DiscoverableNotebook {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String? coverImage;
  final String? category;
  final int sourceCount;
  final int viewCount;
  final int shareCount;
  final bool isPublic;
  final bool isLocked;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final int likeCount;
  final bool userLiked;

  DiscoverableNotebook({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.coverImage,
    this.category,
    this.sourceCount = 0,
    this.viewCount = 0,
    this.shareCount = 0,
    this.isPublic = false,
    this.isLocked = false,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.likeCount = 0,
    this.userLiked = false,
  });

  factory DiscoverableNotebook.fromJson(Map<String, dynamic> json) {
    return DiscoverableNotebook(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      coverImage:
          json['cover_image']?.toString() ?? json['coverImage']?.toString(),
      category: json['category']?.toString(),
      sourceCount:
          SharedContent._parseInt(json['source_count'] ?? json['sourceCount']),
      viewCount:
          SharedContent._parseInt(json['view_count'] ?? json['viewCount']),
      shareCount:
          SharedContent._parseInt(json['share_count'] ?? json['shareCount']),
      isPublic: json['is_public'] ?? json['isPublic'] ?? false,
      isLocked: json['is_locked'] ?? json['isLocked'] ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ??
              json['createdAt']?.toString() ??
              '') ??
          DateTime.now(),
      username: json['username']?.toString(),
      avatarUrl:
          json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      likeCount:
          SharedContent._parseInt(json['like_count'] ?? json['likeCount']),
      userLiked: json['user_liked'] ?? json['userLiked'] ?? false,
    );
  }
}

class DiscoverablePlan {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final String status;
  final int viewCount;
  final int shareCount;
  final bool isPublic;
  final int taskCount;
  final int completionPercentage;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final int likeCount;
  final bool userLiked;

  DiscoverablePlan({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.status = 'draft',
    this.viewCount = 0,
    this.shareCount = 0,
    this.isPublic = false,
    this.taskCount = 0,
    this.completionPercentage = 0,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.likeCount = 0,
    this.userLiked = false,
  });

  factory DiscoverablePlan.fromJson(Map<String, dynamic> json) {
    return DiscoverablePlan(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      status: json['status']?.toString() ?? 'draft',
      viewCount:
          SharedContent._parseInt(json['view_count'] ?? json['viewCount']),
      shareCount:
          SharedContent._parseInt(json['share_count'] ?? json['shareCount']),
      isPublic: json['is_public'] ?? json['isPublic'] ?? false,
      taskCount:
          SharedContent._parseInt(json['task_count'] ?? json['taskCount']),
      completionPercentage: SharedContent._parseInt(
          json['completion_percentage'] ?? json['completionPercentage']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ??
              json['createdAt']?.toString() ??
              '') ??
          DateTime.now(),
      username: json['username']?.toString(),
      avatarUrl:
          json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      likeCount:
          SharedContent._parseInt(json['like_count'] ?? json['likeCount']),
      userLiked: json['user_liked'] ?? json['userLiked'] ?? false,
    );
  }
}

class DiscoverableEbook {
  final String id;
  final String userId;
  final String title;
  final String? topic;
  final String? targetAudience;
  final String? coverImage;
  final int chapterCount;
  final int viewCount;
  final int shareCount;
  final bool isPublic;
  final DateTime createdAt;
  final String? username;
  final String? avatarUrl;
  final int likeCount;
  final bool userLiked;

  DiscoverableEbook({
    required this.id,
    required this.userId,
    required this.title,
    this.topic,
    this.targetAudience,
    this.coverImage,
    this.chapterCount = 0,
    this.viewCount = 0,
    this.shareCount = 0,
    this.isPublic = false,
    required this.createdAt,
    this.username,
    this.avatarUrl,
    this.likeCount = 0,
    this.userLiked = false,
  });

  factory DiscoverableEbook.fromJson(Map<String, dynamic> json) {
    return DiscoverableEbook(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['userId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      topic: json['topic']?.toString(),
      targetAudience: json['target_audience']?.toString() ??
          json['targetAudience']?.toString(),
      coverImage:
          json['cover_image']?.toString() ?? json['coverImage']?.toString(),
      chapterCount: SharedContent._parseInt(
          json['chapter_count'] ?? json['chapterCount']),
      viewCount:
          SharedContent._parseInt(json['view_count'] ?? json['viewCount']),
      shareCount:
          SharedContent._parseInt(json['share_count'] ?? json['shareCount']),
      isPublic: json['is_public'] ?? json['isPublic'] ?? false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ??
              json['createdAt']?.toString() ??
              '') ??
          DateTime.now(),
      username: json['username']?.toString(),
      avatarUrl:
          json['avatar_url']?.toString() ?? json['avatarUrl']?.toString(),
      likeCount:
          SharedContent._parseInt(json['like_count'] ?? json['likeCount']),
      userLiked: json['user_liked'] ?? json['userLiked'] ?? false,
    );
  }
}

class ContentStats {
  final int totalNotebooks;
  final int publicNotebooks;
  final int totalPlans;
  final int publicPlans;
  final int totalViews;
  final int totalLikes;
  final int totalShares;

  ContentStats({
    this.totalNotebooks = 0,
    this.publicNotebooks = 0,
    this.totalPlans = 0,
    this.publicPlans = 0,
    this.totalViews = 0,
    this.totalLikes = 0,
    this.totalShares = 0,
  });

  factory ContentStats.fromJson(Map<String, dynamic> json) {
    return ContentStats(
      totalNotebooks: SharedContent._parseInt(
          json['totalNotebooks'] ?? json['total_notebooks']),
      publicNotebooks: SharedContent._parseInt(
          json['publicNotebooks'] ?? json['public_notebooks']),
      totalPlans:
          SharedContent._parseInt(json['totalPlans'] ?? json['total_plans']),
      publicPlans:
          SharedContent._parseInt(json['publicPlans'] ?? json['public_plans']),
      totalViews:
          SharedContent._parseInt(json['totalViews'] ?? json['total_views']),
      totalLikes:
          SharedContent._parseInt(json['totalLikes'] ?? json['total_likes']),
      totalShares:
          SharedContent._parseInt(json['totalShares'] ?? json['total_shares']),
    );
  }
}

// =====================================================
// State Classes
// =====================================================

class DiscoverState {
  final List<DiscoverableNotebook> notebooks;
  final List<DiscoverablePlan> plans;
  final List<DiscoverableEbook> ebooks;
  final List<StudyGroup> groups;
  final bool isLoadingNotebooks;
  final bool isLoadingPlans;
  final bool isLoadingEbooks;
  final bool isLoadingGroups;
  final bool hasMoreNotebooks;
  final bool hasMorePlans;
  final bool hasMoreEbooks;
  final bool hasMoreGroups;
  final String? error;

  DiscoverState({
    this.notebooks = const [],
    this.plans = const [],
    this.ebooks = const [],
    this.groups = const [],
    this.isLoadingNotebooks = false,
    this.isLoadingPlans = false,
    this.isLoadingEbooks = false,
    this.isLoadingGroups = false,
    this.hasMoreNotebooks = true,
    this.hasMorePlans = true,
    this.hasMoreEbooks = true,
    this.hasMoreGroups = true,
    this.error,
  });

  DiscoverState copyWith({
    List<DiscoverableNotebook>? notebooks,
    List<DiscoverablePlan>? plans,
    List<DiscoverableEbook>? ebooks,
    List<StudyGroup>? groups,
    bool? isLoadingNotebooks,
    bool? isLoadingPlans,
    bool? isLoadingEbooks,
    bool? isLoadingGroups,
    bool? hasMoreNotebooks,
    bool? hasMorePlans,
    bool? hasMoreEbooks,
    bool? hasMoreGroups,
    String? error,
  }) {
    return DiscoverState(
      notebooks: notebooks ?? this.notebooks,
      plans: plans ?? this.plans,
      ebooks: ebooks ?? this.ebooks,
      groups: groups ?? this.groups,
      isLoadingNotebooks: isLoadingNotebooks ?? this.isLoadingNotebooks,
      isLoadingPlans: isLoadingPlans ?? this.isLoadingPlans,
      isLoadingEbooks: isLoadingEbooks ?? this.isLoadingEbooks,
      isLoadingGroups: isLoadingGroups ?? this.isLoadingGroups,
      hasMoreNotebooks: hasMoreNotebooks ?? this.hasMoreNotebooks,
      hasMorePlans: hasMorePlans ?? this.hasMorePlans,
      hasMoreEbooks: hasMoreEbooks ?? this.hasMoreEbooks,
      hasMoreGroups: hasMoreGroups ?? this.hasMoreGroups,
      error: error,
    );
  }
}

class SocialFeedState {
  final List<SharedContent> items;
  final bool isLoading;
  final bool hasMore;
  final String? error;

  SocialFeedState({
    this.items = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
  });

  SocialFeedState copyWith({
    List<SharedContent>? items,
    bool? isLoading,
    bool? hasMore,
    String? error,
  }) {
    return SocialFeedState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
    );
  }
}

// =====================================================
// Providers
// =====================================================

class DiscoverNotifier extends StateNotifier<DiscoverState> {
  final ApiService _api;

  DiscoverNotifier(this._api) : super(DiscoverState());

  Future<void> loadNotebooks({
    bool refresh = false,
    String? search,
    String? category,
    String sortBy = 'recent',
  }) async {
    if (state.isLoadingNotebooks) return;

    state = state.copyWith(isLoadingNotebooks: true, error: null);
    try {
      final offset = refresh ? 0 : state.notebooks.length;
      String url =
          '/social-sharing/discover/notebooks?limit=20&offset=$offset&sortBy=$sortBy';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      if (category != null && category.isNotEmpty) {
        url += '&category=${Uri.encodeComponent(category)}';
      }

      final response = await _api.get(url);
      final notebooksList = response['notebooks'] as List? ?? [];
      final notebooks =
          notebooksList.map((n) => DiscoverableNotebook.fromJson(n)).toList();

      state = state.copyWith(
        notebooks: refresh ? notebooks : [...state.notebooks, ...notebooks],
        isLoadingNotebooks: false,
        hasMoreNotebooks: notebooks.length >= 20,
      );
    } catch (e, stack) {
      _logger.error('Error loading discoverable notebooks', e, stack);
      state = state.copyWith(isLoadingNotebooks: false, error: e.toString());
    }
  }

  Future<void> loadPlans({
    bool refresh = false,
    String? search,
    String? status,
    String sortBy = 'recent',
  }) async {
    if (state.isLoadingPlans) return;

    state = state.copyWith(isLoadingPlans: true, error: null);
    try {
      final offset = refresh ? 0 : state.plans.length;
      String url =
          '/social-sharing/discover/plans?limit=20&offset=$offset&sortBy=$sortBy';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }
      if (status != null && status.isNotEmpty) {
        url += '&status=${Uri.encodeComponent(status)}';
      }

      final response = await _api.get(url);
      final plansList = response['plans'] as List? ?? [];
      final plans = plansList.map((p) => DiscoverablePlan.fromJson(p)).toList();

      state = state.copyWith(
        plans: refresh ? plans : [...state.plans, ...plans],
        isLoadingPlans: false,
        hasMorePlans: plans.length >= 20,
      );
    } catch (e, stack) {
      _logger.error('Error loading discoverable plans', e, stack);
      state = state.copyWith(isLoadingPlans: false, error: e.toString());
    }
  }

  Future<void> loadEbooks({
    bool refresh = false,
    String? search,
    String sortBy = 'recent',
  }) async {
    if (state.isLoadingEbooks) return;

    state = state.copyWith(isLoadingEbooks: true, error: null);
    try {
      final offset = refresh ? 0 : state.ebooks.length;
      String url =
          '/social-sharing/discover/ebooks?limit=20&offset=$offset&sortBy=$sortBy';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }

      final response = await _api.get(url);
      final ebooksList = response['ebooks'] as List? ?? [];
      final ebooks =
          ebooksList.map((e) => DiscoverableEbook.fromJson(e)).toList();

      state = state.copyWith(
        ebooks: refresh ? ebooks : [...state.ebooks, ...ebooks],
        isLoadingEbooks: false,
        hasMoreEbooks: ebooks.length >= 20,
      );
    } catch (e, stack) {
      _logger.error('Error loading discoverable ebooks', e, stack);
      state = state.copyWith(isLoadingEbooks: false, error: e.toString());
    }
  }

  Future<void> loadGroups({
    bool refresh = false,
    String? search,
  }) async {
    if (state.isLoadingGroups) return;

    state = state.copyWith(isLoadingGroups: true, error: null);
    try {
      final offset = refresh ? 0 : state.groups.length;
      String url = '/social/groups/discover?limit=20&offset=$offset';
      if (search != null && search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(search)}';
      }

      final response = await _api.get(url);
      final groupsList = response['groups'] as List? ?? [];
      final groups = groupsList.map((g) => StudyGroup.fromJson(g)).toList();

      state = state.copyWith(
        groups: refresh ? groups : [...state.groups, ...groups],
        isLoadingGroups: false,
        hasMoreGroups: groups.length >= 20,
      );
    } catch (e, stack) {
      _logger.error('Error loading discoverable groups', e, stack);
      state = state.copyWith(isLoadingGroups: false, error: e.toString());
    }
  }

  Future<void> likeNotebook(String notebookId) async {
    try {
      await _api.post('/social-sharing/like', {
        'contentType': 'notebook',
        'contentId': notebookId,
      });
      // Update local state
      state = state.copyWith(
        notebooks: state.notebooks.map((n) {
          if (n.id == notebookId) {
            return DiscoverableNotebook(
              id: n.id,
              userId: n.userId,
              title: n.title,
              description: n.description,
              coverImage: n.coverImage,
              category: n.category,
              sourceCount: n.sourceCount,
              viewCount: n.viewCount,
              shareCount: n.shareCount,
              isPublic: n.isPublic,
              isLocked: n.isLocked,
              createdAt: n.createdAt,
              username: n.username,
              avatarUrl: n.avatarUrl,
              likeCount: n.userLiked ? n.likeCount : n.likeCount + 1,
              userLiked: true,
            );
          }
          return n;
        }).toList(),
      );
    } catch (e) {
      _logger.error('Error liking notebook', e);
    }
  }

  Future<void> unlikeNotebook(String notebookId) async {
    try {
      await _api.delete('/social-sharing/like');
      // Note: DELETE with body might need special handling
    } catch (e) {
      _logger.error('Error unliking notebook', e);
    }
  }

  Future<void> likePlan(String planId) async {
    try {
      await _api.post('/social-sharing/like', {
        'contentType': 'plan',
        'contentId': planId,
      });
      // Update local state
      state = state.copyWith(
        plans: state.plans.map((p) {
          if (p.id == planId) {
            return DiscoverablePlan(
              id: p.id,
              userId: p.userId,
              title: p.title,
              description: p.description,
              status: p.status,
              viewCount: p.viewCount,
              shareCount: p.shareCount,
              isPublic: p.isPublic,
              taskCount: p.taskCount,
              completionPercentage: p.completionPercentage,
              createdAt: p.createdAt,
              username: p.username,
              avatarUrl: p.avatarUrl,
              likeCount: p.userLiked ? p.likeCount : p.likeCount + 1,
              userLiked: true,
            );
          }
          return p;
        }).toList(),
      );
    } catch (e) {
      _logger.error('Error liking plan', e);
    }
  }

  Future<void> likeEbook(String ebookId) async {
    try {
      await _api.post('/social-sharing/like', {
        'contentType': 'ebook',
        'contentId': ebookId,
      });
      state = state.copyWith(
        ebooks: state.ebooks.map((e) {
          if (e.id == ebookId) {
            return DiscoverableEbook(
              id: e.id,
              userId: e.userId,
              title: e.title,
              topic: e.topic,
              targetAudience: e.targetAudience,
              coverImage: e.coverImage,
              chapterCount: e.chapterCount,
              viewCount: e.viewCount,
              shareCount: e.shareCount,
              isPublic: e.isPublic,
              createdAt: e.createdAt,
              username: e.username,
              avatarUrl: e.avatarUrl,
              likeCount: e.userLiked ? e.likeCount : e.likeCount + 1,
              userLiked: true,
            );
          }
          return e;
        }).toList(),
      );
    } catch (e) {
      _logger.error('Error liking ebook', e);
    }
  }
}

class SocialFeedNotifier extends StateNotifier<SocialFeedState> {
  final ApiService _api;

  SocialFeedNotifier(this._api) : super(SocialFeedState());

  Future<void> loadFeed({bool refresh = false, String? contentType}) async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      final offset = refresh ? 0 : state.items.length;
      String url = '/social-sharing/feed?limit=20&offset=$offset';
      if (contentType != null && contentType != 'all') {
        url += '&contentType=$contentType';
      }

      final response = await _api.get(url);
      final feedList = response['feed'] as List? ?? [];
      final items = feedList.map((f) => SharedContent.fromJson(f)).toList();

      state = state.copyWith(
        items: refresh ? items : [...state.items, ...items],
        isLoading: false,
        hasMore: items.length >= 20,
      );
    } catch (e, stack) {
      _logger.error('Error loading social feed', e, stack);
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

// =====================================================
// Service for sharing actions
// =====================================================

class SocialSharingService {
  final ApiService _api;

  SocialSharingService(this._api);

  Future<void> shareContent({
    required String contentType,
    required String contentId,
    String? caption,
    bool isPublic = true,
  }) async {
    await _api.post('/social-sharing/share', {
      'contentType': contentType,
      'contentId': contentId,
      if (caption != null) 'caption': caption,
      'isPublic': isPublic,
    });
  }

  Future<void> setNotebookPublic(String notebookId, bool isPublic) async {
    await _api.patch('/social-sharing/notebooks/$notebookId/visibility', {
      'isPublic': isPublic,
    });
  }

  Future<void> setNotebookLocked(String notebookId, bool isLocked) async {
    await _api.patch('/social-sharing/notebooks/$notebookId/lock', {
      'isLocked': isLocked,
    });
  }

  Future<void> setPlanPublic(String planId, bool isPublic) async {
    await _api.patch('/social-sharing/plans/$planId/visibility', {
      'isPublic': isPublic,
    });
  }

  Future<void> recordView(String contentType, String contentId) async {
    await _api.post('/social-sharing/view', {
      'contentType': contentType,
      'contentId': contentId,
    });
  }

  Future<ContentStats> getMyStats() async {
    final response = await _api.get('/social-sharing/my-stats');
    return ContentStats.fromJson(response['stats'] ?? {});
  }

  Future<void> likeContent(String contentType, String contentId) async {
    await _api.post('/social-sharing/like', {
      'contentType': contentType,
      'contentId': contentId,
    });
  }

  Future<void> saveContent(String contentType, String contentId) async {
    await _api.post('/social-sharing/save', {
      'contentType': contentType,
      'contentId': contentId,
    });
  }
}

// =====================================================
// Provider Definitions
// =====================================================

final discoverProvider =
    StateNotifierProvider<DiscoverNotifier, DiscoverState>((ref) {
  return DiscoverNotifier(ref.watch(apiServiceProvider));
});

final socialFeedProvider =
    StateNotifierProvider<SocialFeedNotifier, SocialFeedState>((ref) {
  return SocialFeedNotifier(ref.watch(apiServiceProvider));
});

final socialSharingServiceProvider = Provider<SocialSharingService>((ref) {
  return SocialSharingService(ref.watch(apiServiceProvider));
});
