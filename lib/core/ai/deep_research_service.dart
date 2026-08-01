import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import '../../features/gamification/gamification_provider.dart';
import 'ai_settings_service.dart';

final deepResearchServiceProvider = Provider<DeepResearchService>((ref) {
  return DeepResearchService(ref);
});

/// Research depth levels
enum ResearchDepth { quick, standard, deep }

/// Research templates
enum ResearchTemplate {
  general,
  academic,
  productComparison,
  marketAnalysis,
  howToGuide,
  prosAndCons,
  shopping,
}

/// Source credibility
enum SourceCredibility {
  academic,
  government,
  news,
  professional,
  blog,
  unknown
}

/// Research source model
class ResearchSource {
  final String title;
  final String url;
  final String content;
  final String? snippet;
  final String? imageUrl;
  final SourceCredibility credibility;
  final int credibilityScore;

  ResearchSource({
    required this.title,
    required this.url,
    required this.content,
    this.snippet,
    this.imageUrl,
    this.credibility = SourceCredibility.unknown,
    this.credibilityScore = 60,
  });

  factory ResearchSource.fromJson(Map<String, dynamic> json) {
    return ResearchSource(
      title: json['title'] ?? '',
      url: json['url'] ?? '',
      content: json['content'] ?? '',
      snippet: json['snippet'],
      imageUrl: json['imageUrl'],
      credibility: _parseCredibility(json['credibility']),
      credibilityScore: json['credibilityScore'] ?? 60,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'url': url,
        'content': content,
        'snippet': snippet,
        'imageUrl': imageUrl,
        'credibility': credibility.name,
        'credibilityScore': credibilityScore,
      };

  static SourceCredibility _parseCredibility(String? value) {
    if (value == null) return SourceCredibility.unknown;
    try {
      return SourceCredibility.values.firstWhere((e) => e.name == value);
    } catch (_) {
      return SourceCredibility.unknown;
    }
  }
}

// Helper function at module level for parsing credibility
SourceCredibility _parseCredibility(String? value) {
  if (value == null) return SourceCredibility.unknown;
  try {
    return SourceCredibility.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SourceCredibility.unknown,
    );
  } catch (_) {
    return SourceCredibility.unknown;
  }
}

/// Research update for progress tracking
class ResearchUpdate {
  final String status;
  final double progress;
  final String? result;
  final List<ResearchSource>? sources;
  final List<String>? images;
  final List<String>? videos;
  final bool isComplete;
  final String? error;
  final String? jobId;

  ResearchUpdate({
    required this.status,
    required this.progress,
    this.result,
    this.sources,
    this.images,
    this.videos,
    this.isComplete = false,
    this.error,
    this.jobId,
  });
}

class ActiveResearchJob {
  final String owner;
  final String jobId;
  final String query;
  final String notebookId;
  final ResearchDepth depth;
  final ResearchTemplate template;
  final bool useNotebookContext;

  const ActiveResearchJob({
    required this.owner,
    required this.jobId,
    required this.query,
    required this.notebookId,
    required this.depth,
    required this.template,
    required this.useNotebookContext,
  });

  Map<String, dynamic> toJson() => {
        'owner': owner,
        'jobId': jobId,
        'query': query,
        'notebookId': notebookId,
        'depth': depth.name,
        'template': template.name,
        'useNotebookContext': useNotebookContext,
      };

  factory ActiveResearchJob.fromJson(Map<String, dynamic> json) {
    return ActiveResearchJob(
      owner: json['owner']?.toString() ?? 'general',
      jobId: json['jobId']?.toString() ?? '',
      query: json['query']?.toString() ?? '',
      notebookId: json['notebookId']?.toString() ?? '',
      depth: ResearchDepth.values.firstWhere(
        (value) => value.name == json['depth'],
        orElse: () => ResearchDepth.standard,
      ),
      template: ResearchTemplate.values.firstWhere(
        (value) => value.name == json['template'],
        orElse: () => ResearchTemplate.general,
      ),
      useNotebookContext: json['useNotebookContext'] == true,
    );
  }
}

/// Clean, simple deep research service - Backend Powered
class DeepResearchService {
  final Ref ref;
  static const _activeJobsKey = 'active_deep_research_jobs_v1';
  static const _pollInterval = Duration(seconds: 3);

  DeepResearchService(this.ref);

  Future<Map<String, dynamic>> _readActiveJobs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeJobsKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _rememberJob(ActiveResearchJob job) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = await _readActiveJobs();
    jobs[job.owner] = job.toJson();
    await prefs.setString(_activeJobsKey, jsonEncode(jobs));
  }

  Future<void> _forgetJob(ActiveResearchJob job) async {
    final prefs = await SharedPreferences.getInstance();
    final jobs = await _readActiveJobs();
    final current = jobs[job.owner];
    if (current is Map && current['jobId']?.toString() != job.jobId) return;
    jobs.remove(job.owner);
    await prefs.setString(_activeJobsKey, jsonEncode(jobs));
  }

  Future<ActiveResearchJob?> getActiveJob(String owner) async {
    final jobs = await _readActiveJobs();
    final value = jobs[owner];
    if (value is! Map) return null;
    final job = ActiveResearchJob.fromJson(Map<String, dynamic>.from(value));
    return job.jobId.isEmpty ? null : job;
  }

  List<ResearchSource> _parseSources(dynamic value) {
    if (value is! List) return const <ResearchSource>[];
    return value.whereType<Map>().map((source) {
      final json = Map<String, dynamic>.from(source);
      return ResearchSource(
        title: json['title']?.toString() ?? 'Source',
        url: json['url']?.toString() ?? '',
        content:
            json['content']?.toString() ?? json['snippet']?.toString() ?? '',
        snippet: json['snippet']?.toString(),
        imageUrl: json['imageUrl']?.toString(),
        credibility: _parseCredibility(json['credibility']?.toString()),
        credibilityScore: (json['credibilityScore'] as num?)?.toInt() ??
            (json['credibility_score'] as num?)?.toInt() ??
            60,
      );
    }).toList();
  }

  Map<String, dynamic> _parseResult(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String && value.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(value) as Map);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  double _parseProgress(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Stream<ResearchUpdate> resume(ActiveResearchJob job) => _followJob(job);

  Stream<ResearchUpdate> _followJob(ActiveResearchJob job) async* {
    final api = ref.read(apiServiceProvider);
    var temporaryFailures = 0;

    while (true) {
      Map<String, dynamic> payload;
      try {
        payload = await api.getDeepResearchJob(job.jobId);
        temporaryFailures = 0;
      } catch (error) {
        final message = error.toString();
        if (message.contains('404')) {
          await _forgetJob(job);
          yield ResearchUpdate(
            status: 'Research job was not found',
            progress: 0,
            isComplete: true,
            error: message,
            jobId: job.jobId,
          );
          return;
        }

        temporaryFailures += 1;
        yield ResearchUpdate(
          status: 'Research continues in the background. Reconnecting...',
          progress: 0,
          jobId: job.jobId,
        );
        final retrySeconds = temporaryFailures.clamp(1, 10) * 3;
        await Future<void>.delayed(Duration(seconds: retrySeconds));
        continue;
      }

      final status = payload['status']?.toString() ?? 'pending';
      final statusMessage = payload['status_message']?.toString();
      final progress = _parseProgress(payload['progress']);

      if (status == 'completed') {
        final result = _parseResult(payload['result']);
        final report = result['report']?.toString() ?? '';
        final sources = _parseSources(result['sources']);
        final images = (result['images'] as List?)
                ?.map((value) => value.toString())
                .toList() ??
            const <String>[];
        final videos = (result['videos'] as List?)
                ?.map((value) => value.toString())
                .toList() ??
            const <String>[];

        await _forgetJob(job);
        try {
          ref.read(gamificationProvider.notifier).trackDeepResearch();
        } catch (error) {
          debugPrint('[DeepResearch] Gamification tracking error: $error');
        }
        yield ResearchUpdate(
          status: statusMessage ?? 'Research complete!',
          progress: 1,
          result: report.isEmpty ? null : report,
          sources: sources,
          images: images,
          videos: videos,
          isComplete: true,
          jobId: job.jobId,
        );
        return;
      }

      if (status == 'failed') {
        await _forgetJob(job);
        final error = payload['error']?.toString() ?? 'Research failed';
        yield ResearchUpdate(
          status: 'Research failed',
          progress: progress,
          isComplete: true,
          error: error,
          jobId: job.jobId,
        );
        return;
      }

      yield ResearchUpdate(
        status: statusMessage ??
            (status == 'pending'
                ? 'Research queued on the server...'
                : 'Research is running on the server...'),
        progress: progress,
        jobId: job.jobId,
      );
      await Future<void>.delayed(_pollInterval);
    }
  }

  /// Starts durable backend research and follows it by job ID. The backend
  /// keeps working if Android suspends or closes the current connection.
  Stream<ResearchUpdate> research({
    required String query,
    required String notebookId,
    ResearchDepth depth = ResearchDepth.standard,
    ResearchTemplate template = ResearchTemplate.general,
    bool useNotebookContext = false,
    String owner = 'general',
    String? provider,
    String? model,
  }) async* {
    try {
      final api = ref.read(apiServiceProvider);

      // Get AI settings (provider/model)
      final settings =
          await AISettingsService.getSettingsWithProviderDetection(ref.read);
      final effectiveProvider = provider?.trim().isNotEmpty == true
          ? provider!.trim()
          : settings.provider;
      final effectiveModel =
          model?.trim().isNotEmpty == true ? model!.trim() : settings.model;

      final response = await api.startDeepResearchJob(
        query: query,
        notebookId: notebookId,
        depth: depth.name,
        template: template.name,
        includeImages: true,
        useNotebookContext: useNotebookContext,
        provider: effectiveProvider,
        model: effectiveModel,
      );
      final jobId = response['jobId']?.toString() ?? '';
      if (jobId.isEmpty) {
        throw Exception('The backend did not return a research job ID.');
      }
      final job = ActiveResearchJob(
        owner: owner,
        jobId: jobId,
        query: query,
        notebookId: notebookId,
        depth: depth,
        template: template,
        useNotebookContext: useNotebookContext,
      );
      await _rememberJob(job);
      yield ResearchUpdate(
        status: 'Research started on the server...',
        progress: 0,
        jobId: jobId,
      );
      yield* _followJob(job);
    } catch (e, stackTrace) {
      debugPrint('[DeepResearch] Error: $e');
      debugPrint('[DeepResearch] Stack trace: $stackTrace');

      // Provide a user-friendly error message
      String errorMessage = 'An error occurred during research';
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        errorMessage = 'Authentication error. Please log in again.';
      } else if (e.toString().contains('network') ||
          e.toString().contains('connection')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      }

      yield ResearchUpdate(
        status: errorMessage,
        progress: 0.0,
        isComplete: true,
        error: e.toString(),
      );
    }
  }

  // Previous helper methods for credibility can be removed as backend handles logic,
  // or kept if we want to run credibility scoring on the frontend for now.
  // I've removed them to keep the file clean.
}
