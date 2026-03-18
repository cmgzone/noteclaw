import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/gemini_image_service.dart';
import '../../../core/security/global_credentials_service.dart';
import '../../../core/search/serper_service.dart';
import '../models/ebook_project.dart';
import '../models/ebook_chapter.dart';
import '../../../core/ai/ai_settings_service.dart';

class DesignerAgent {
  final Ref ref;

  DesignerAgent(this.ref);

  Future<GeminiImageService> _getImageService(
      {required String? providerOverride}) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final provider = providerOverride ?? settings.provider;
    final creds = ref.read(globalCredentialsServiceProvider);

    String? apiKey;
    if (provider == 'openrouter') {
      apiKey = await creds.getApiKey('openrouter');
    } else {
      apiKey = await creds.getApiKey('gemini');
    }

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key not found for $provider');
    }
    return GeminiImageService(apiKey: apiKey);
  }

  /// Fallback: fetch a real image from web search when AI image gen is unavailable.
  Future<String?> _fetchWebImage(String query) async {
    try {
      debugPrint('[DesignerAgent] Falling back to web image search for: $query');
      final serper = SerperService(ref);
      final results = await serper.search(
        query,
        type: 'images',
        num: 5,
      );

      for (final result in results) {
        if (result.imageUrl != null && result.imageUrl!.isNotEmpty) {
          debugPrint('[DesignerAgent] Found web image: ${result.imageUrl}');
          return result.imageUrl;
        }
      }
    } catch (e) {
      debugPrint('[DesignerAgent] Web image search failed: $e');
    }
    return null;
  }

  /// Returns true if the url is a placeholder SVG (not a real image).
  bool _isPlaceholder(String url) {
    return url.startsWith('data:image/svg+xml');
  }

  Future<String> generateCoverArt(EbookProject project) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);

    final prompt = '''
Book cover design for a book titled "${project.title}".
Topic: ${project.topic}
Style: Professional, modern, minimalist, high quality, 4k.
Primary color: ${project.branding.primaryColorValue.toRadixString(16)}
''';

    try {
      final imageService =
          await _getImageService(providerOverride: settings.provider);
      final url = await imageService.generateImage(prompt,
          provider: settings.provider, model: settings.model);

      if (_isPlaceholder(url)) {
        // AI model returned placeholder — try web image
        final webUrl = await _fetchWebImage(
            '${project.title} ${project.topic} book cover professional');
        return webUrl ?? url; // return web image or keep placeholder as last resort
      }
      return url;
    } catch (e) {
      debugPrint(
          '[DesignerAgent] Cover art AI generation failed: $e — trying web fallback');
      final webUrl = await _fetchWebImage(
          '${project.title} ${project.topic} book cover professional');
      if (webUrl != null) return webUrl;
      return _buildColoredPlaceholder(project.topic);
    }
  }

  Future<String> generateChapterIllustration(
      EbookChapter chapter, String style) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);

    // Safely get content preview
    final contentPreview = chapter.content.isEmpty
        ? chapter.title
        : chapter.content.substring(0, chapter.content.length.clamp(0, 100));

    final prompt = '''
Illustration for a book chapter titled "${chapter.title}".
Context: $contentPreview...
Style: $style, consistent, professional.
''';

    try {
      final imageService =
          await _getImageService(providerOverride: settings.provider);
      final url = await imageService.generateImage(prompt,
          provider: settings.provider, model: settings.model);

      if (_isPlaceholder(url)) {
        // AI model returned placeholder — try web image
        final webUrl =
            await _fetchWebImage('${chapter.title} illustration professional');
        return webUrl ?? url;
      }
      return url;
    } catch (e) {
      debugPrint(
          '[DesignerAgent] Chapter illustration AI generation failed: $e — trying web fallback');
      final webUrl =
          await _fetchWebImage('${chapter.title} illustration professional');
      if (webUrl != null) return webUrl;
      return _buildColoredPlaceholder(chapter.title);
    }
  }

  /// Builds a simple colored gradient SVG placeholder as a last resort.
  String _buildColoredPlaceholder(String label) {
    final truncated =
        label.length > 40 ? '${label.substring(0, 40)}...' : label;
    final svg = '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">'
        '<defs><linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">'
        '<stop offset="0%" style="stop-color:#6366f1;stop-opacity:1"/>'
        '<stop offset="100%" style="stop-color:#a855f7;stop-opacity:1"/>'
        '</linearGradient></defs>'
        '<rect width="400" height="400" fill="url(#grad)" rx="16"/>'
        '<text x="50%" y="50%" font-size="18" fill="white" text-anchor="middle"'
        ' dominant-baseline="middle" font-family="sans-serif">$truncated</text>'
        '</svg>';
    return 'data:image/svg+xml;base64,${base64Encode(utf8.encode(svg))}';
  }
}

final designerAgentProvider =
    Provider<DesignerAgent>((ref) => DesignerAgent(ref));
