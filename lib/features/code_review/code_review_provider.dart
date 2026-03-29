import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_service.dart';

// Models
class CodeReviewIssue {
  final String id;
  final String severity; // error, warning, info
  final String category; // security, performance, style, logic, best-practice
  final String message;
  final int? line;
  final int? column;
  final String? suggestion;
  final String? codeExample;

  CodeReviewIssue({
    required this.id,
    required this.severity,
    required this.category,
    required this.message,
    this.line,
    this.column,
    this.suggestion,
    this.codeExample,
  });

  factory CodeReviewIssue.fromJson(Map<String, dynamic> json) {
    return CodeReviewIssue(
      id: json['id'] ?? '',
      severity: json['severity'] ?? 'info',
      category: json['category'] ?? 'best-practice',
      message: json['message'] ?? '',
      line: json['line'],
      column: json['column'],
      suggestion: json['suggestion'],
      codeExample: json['codeExample'],
    );
  }
}

class CodeReview {
  final String id;
  final String code;
  final String language;
  final String reviewType;
  final int score;
  final String summary;
  final List<CodeReviewIssue> issues;
  final List<String> suggestions;
  final List<String>? relatedFilesUsed;
  final Map<String, dynamic>? metadata;
  final String source;
  final String? toolName;
  final DateTime createdAt;

  CodeReview({
    required this.id,
    required this.code,
    required this.language,
    required this.reviewType,
    required this.score,
    required this.summary,
    required this.issues,
    required this.suggestions,
    this.relatedFilesUsed,
    this.metadata,
    required this.source,
    this.toolName,
    required this.createdAt,
  });

  factory CodeReview.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map<String, dynamic>
        ? json['metadata'] as Map<String, dynamic>
        : json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null;

    return CodeReview(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      language: json['language'] ?? '',
      reviewType: json['reviewType'] ?? 'comprehensive',
      score: json['score'] ?? 0,
      summary: json['summary'] ?? '',
      issues: (json['issues'] as List<dynamic>?)
              ?.map((e) => CodeReviewIssue.fromJson(e))
              .toList() ??
          [],
      suggestions: (json['suggestions'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      relatedFilesUsed: (json['relatedFilesUsed'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList(),
      metadata: metadata,
      source: json['source']?.toString() ??
          metadata?['source']?.toString() ??
          'app',
      toolName:
          json['toolName']?.toString() ?? metadata?['toolName']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  bool get isContextAware =>
      (relatedFilesUsed != null && relatedFilesUsed!.isNotEmpty) ||
      metadata?['isContextAware'] == true;
  bool get isMcp => source == 'mcp';
  int get errorCount => issues.where((i) => i.severity == 'error').length;
  int get warningCount => issues.where((i) => i.severity == 'warning').length;
  int get infoCount => issues.where((i) => i.severity == 'info').length;
}

class CodeReviewHistoryItem {
  final String id;
  final String codePreview;
  final String language;
  final String reviewType;
  final int score;
  final String summary;
  final int errorCount;
  final int warningCount;
  final int infoCount;
  final int relatedFileCount;
  final Map<String, dynamic>? metadata;
  final String source;
  final String? toolName;
  final DateTime createdAt;

  CodeReviewHistoryItem({
    required this.id,
    required this.codePreview,
    required this.language,
    required this.reviewType,
    required this.score,
    required this.summary,
    required this.errorCount,
    required this.warningCount,
    required this.infoCount,
    required this.relatedFileCount,
    this.metadata,
    required this.source,
    this.toolName,
    required this.createdAt,
  });

  factory CodeReviewHistoryItem.fromJson(Map<String, dynamic> json) {
    final issueCount = json['issueCount'] as Map<String, dynamic>? ?? {};
    final metadata = json['metadata'] is Map<String, dynamic>
        ? json['metadata'] as Map<String, dynamic>
        : json['metadata'] is Map
            ? Map<String, dynamic>.from(json['metadata'] as Map)
            : null;
    return CodeReviewHistoryItem(
      id: json['id'] ?? '',
      codePreview: json['codePreview'] ?? '',
      language: json['language'] ?? '',
      reviewType: json['reviewType'] ?? 'comprehensive',
      score: json['score'] ?? 0,
      summary: json['summary'] ?? '',
      errorCount: issueCount['errors'] ?? 0,
      warningCount: issueCount['warnings'] ?? 0,
      infoCount: issueCount['info'] ?? 0,
      relatedFileCount: json['relatedFileCount'] ?? 0,
      metadata: metadata,
      source: json['source']?.toString() ??
          metadata?['source']?.toString() ??
          'app',
      toolName:
          json['toolName']?.toString() ?? metadata?['toolName']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  bool get isMcp => source == 'mcp';
  bool get isContextAware =>
      relatedFileCount > 0 || metadata?['isContextAware'] == true;
}

class CodeComparisonResult {
  final int originalScore;
  final int updatedScore;
  final int improvement;
  final List<CodeReviewIssue> resolvedIssues;
  final List<CodeReviewIssue> newIssues;
  final String summary;

  CodeComparisonResult({
    required this.originalScore,
    required this.updatedScore,
    required this.improvement,
    required this.resolvedIssues,
    required this.newIssues,
    required this.summary,
  });

  factory CodeComparisonResult.fromJson(Map<String, dynamic> json) {
    return CodeComparisonResult(
      originalScore: json['originalScore'] ?? 0,
      updatedScore: json['updatedScore'] ?? 0,
      improvement: json['improvement'] ?? 0,
      resolvedIssues: (json['resolvedIssues'] as List<dynamic>?)
              ?.map((e) => CodeReviewIssue.fromJson(e))
              .toList() ??
          [],
      newIssues: (json['newIssues'] as List<dynamic>?)
              ?.map((e) => CodeReviewIssue.fromJson(e))
              .toList() ??
          [],
      summary: json['summary'] ?? '',
    );
  }
}

/// GitHub context for context-aware code reviews
class GitHubReviewContext {
  final String owner;
  final String repo;
  final String? branch;
  final int maxFiles;
  final int maxFileSize;

  GitHubReviewContext({
    required this.owner,
    required this.repo,
    this.branch,
    this.maxFiles = 5,
    this.maxFileSize = 50000,
  });

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'repo': repo,
        if (branch != null) 'branch': branch,
        'maxFiles': maxFiles,
        'maxFileSize': maxFileSize,
      };
}

// State
class CodeReviewState {
  final bool isLoading;
  final CodeReview? currentReview;
  final List<CodeReviewHistoryItem> history;
  final CodeComparisonResult? comparisonResult;
  final String? error;

  CodeReviewState({
    this.isLoading = false,
    this.currentReview,
    this.history = const [],
    this.comparisonResult,
    this.error,
  });

  CodeReviewState copyWith({
    bool? isLoading,
    CodeReview? currentReview,
    List<CodeReviewHistoryItem>? history,
    CodeComparisonResult? comparisonResult,
    String? error,
  }) {
    return CodeReviewState(
      isLoading: isLoading ?? this.isLoading,
      currentReview: currentReview ?? this.currentReview,
      history: history ?? this.history,
      comparisonResult: comparisonResult ?? this.comparisonResult,
      error: error,
    );
  }
}

// Provider
class CodeReviewNotifier extends StateNotifier<CodeReviewState> {
  final ApiService _apiService;

  CodeReviewNotifier(this._apiService) : super(CodeReviewState());

  Future<CodeReview?> reviewCode({
    required String code,
    required String language,
    String reviewType = 'comprehensive',
    String? context,
    bool saveReview = true,
    GitHubReviewContext? githubContext,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final body = <String, dynamic>{
        'code': code,
        'language': language,
        'reviewType': reviewType,
        'context': context,
        'saveReview': saveReview,
      };

      // Add GitHub context if provided for context-aware review
      if (githubContext != null) {
        body['githubContext'] = githubContext.toJson();
      }

      final response = await _apiService.post('/coding-agent/review', body);

      if (response['success'] == true && response['review'] != null) {
        final review = CodeReview.fromJson(response['review']);
        state = state.copyWith(isLoading: false, currentReview: review);
        return review;
      } else {
        throw Exception(response['error'] ?? 'Failed to review code');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  Future<void> loadHistory({
    String? language,
    int limit = 50,
    int? minScore,
    int? maxScore,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final params = <String, String>{};
      if (language != null) params['language'] = language;
      params['limit'] = limit.toString();
      if (minScore != null) params['minScore'] = minScore.toString();
      if (maxScore != null) params['maxScore'] = maxScore.toString();

      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response =
          await _apiService.get('/coding-agent/reviews?$queryString');

      if (response['success'] == true) {
        final reviews = (response['reviews'] as List<dynamic>?)
                ?.map((e) => CodeReviewHistoryItem.fromJson(e))
                .toList() ??
            [];
        state = state.copyWith(isLoading: false, history: reviews);
      } else {
        throw Exception(response['error'] ?? 'Failed to load history');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<CodeReview?> getReviewDetail(String reviewId) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.get('/coding-agent/reviews/$reviewId');

      if (response['success'] == true && response['review'] != null) {
        final review = CodeReview.fromJson(response['review']);
        state = state.copyWith(isLoading: false, currentReview: review);
        return review;
      } else {
        throw Exception(response['error'] ?? 'Failed to get review');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  Future<CodeComparisonResult?> compareVersions({
    required String originalCode,
    required String updatedCode,
    required String language,
    String? context,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final response = await _apiService.post('/coding-agent/review/compare', {
        'originalCode': originalCode,
        'updatedCode': updatedCode,
        'language': language,
        'context': context,
      });

      if (response['success'] == true && response['comparison'] != null) {
        final comparison =
            CodeComparisonResult.fromJson(response['comparison']);
        state = state.copyWith(isLoading: false, comparisonResult: comparison);
        return comparison;
      } else {
        throw Exception(response['error'] ?? 'Failed to compare versions');
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
      return null;
    }
  }

  void clearCurrentReview() {
    state = state.copyWith(currentReview: null);
  }

  void clearComparison() {
    state = state.copyWith(comparisonResult: null);
  }
}

// Providers
final codeReviewProvider =
    StateNotifierProvider<CodeReviewNotifier, CodeReviewState>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return CodeReviewNotifier(apiService);
});

final codeReviewDetailProvider = FutureProvider.autoDispose
    .family<CodeReview, String>((ref, reviewId) async {
  final apiService = ref.watch(apiServiceProvider);
  final response = await apiService.get('/coding-agent/reviews/$reviewId');

  if (response['success'] == true && response['review'] != null) {
    return CodeReview.fromJson(response['review']);
  }

  throw Exception(response['error'] ?? 'Failed to load review details');
});
