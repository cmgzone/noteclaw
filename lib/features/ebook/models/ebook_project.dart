import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';
import 'branding_config.dart';
import 'ebook_chapter.dart';

part 'ebook_project.freezed.dart';
part 'ebook_project.g.dart';

enum EbookStatus { draft, generating, completed, error }

/// Image source options for ebook generation
enum ImageSourceType { aiGenerated, webSearch, both }

@freezed
class EbookProject with _$EbookProject {
  const factory EbookProject({
    required String id,
    required String title,
    required String topic,
    required String targetAudience,
    required BrandingConfig branding,
    @Default([]) List<EbookChapter> chapters,
    @Default(EbookStatus.draft) EbookStatus status,
    required String selectedModel,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? coverImageUrl,
    String? notebookId,
    @Default([]) List<String> chapterAudioUrls,
    @Default('Starting...') String currentPhase,
    // Deep Research settings
    @Default(false) bool useDeepResearch,
    @Default(ImageSourceType.aiGenerated) ImageSourceType imageSource,
    String? deepResearchSummary,
    @Default([]) List<String> webSearchedImages,
  }) = _EbookProject;

  const EbookProject._();

  factory EbookProject.fromBackendJson(Map<String, dynamic> json) =>
      EbookProject(
        id: json['id'].toString(),
        title: json['title'],
        topic: json['topic'],
        targetAudience: json['target_audience'] ?? '',
        branding: BrandingConfig.fromBackendJson(
          _parseBrandingJson(json['branding']),
        ),
        chapters: (json['chapters'] as List? ?? [])
            .map((c) => EbookChapter.fromBackendJson(c))
            .toList(),
        status: EbookStatus.values.firstWhere(
          (s) => s.name == (json['status'] ?? 'draft'),
          orElse: () => EbookStatus.draft,
        ),
        selectedModel: json['selected_model'] ?? '',
        createdAt: DateTime.parse(json['created_at']),
        updatedAt: DateTime.parse(json['updated_at']),
        coverImageUrl: json['cover_image_url'] ?? json['cover_image'],
        notebookId: json['notebook_id'],
        chapterAudioUrls: List<String>.from(json['chapter_audio_urls'] ?? []),
        currentPhase: json['current_phase'] ?? 'Starting...',
        useDeepResearch: json['use_deep_research'] ?? false,
        imageSource: ImageSourceType.values.firstWhere(
          (s) => s.name == (json['image_source'] ?? 'aiGenerated'),
          orElse: () => ImageSourceType.aiGenerated,
        ),
        deepResearchSummary: json['deep_research_summary'],
        webSearchedImages: List<String>.from(json['web_searched_images'] ?? []),
      );

  Map<String, dynamic> toBackendJson() => {
        'id': id,
        'title': title,
        'topic': topic,
        'target_audience': targetAudience,
        'branding': branding.toBackendJson(),
        'chapters': chapters.map((c) => c.toBackendJson()).toList(),
        'status': status.name,
        'selected_model': selectedModel,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'cover_image_url': coverImageUrl,
        'notebook_id': notebookId,
        'chapter_audio_urls': chapterAudioUrls,
        'current_phase': currentPhase,
        'use_deep_research': useDeepResearch,
        'image_source': imageSource.name,
        'deep_research_summary': deepResearchSummary,
        'web_searched_images': webSearchedImages,
      };

  factory EbookProject.fromJson(Map<String, dynamic> json) =>
      _$EbookProjectFromJson(json);

  static Map<String, dynamic> _parseBrandingJson(dynamic rawBranding) {
    if (rawBranding is Map<String, dynamic>) {
      return rawBranding;
    }

    if (rawBranding is Map) {
      return Map<String, dynamic>.from(rawBranding);
    }

    if (rawBranding is String && rawBranding.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBranding);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return {};
      }
    }

    return {};
  }
}
