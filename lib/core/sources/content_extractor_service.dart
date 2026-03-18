import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../api/api_service.dart';

class ContentExtractorService {
  final Ref ref;

  ContentExtractorService(this.ref);

  /// Extract content from YouTube video
  /// Uses a simple approach to get video info and captions
  Future<String> extractYouTubeContent(String url) async {
    try {
      final videoId = _extractYouTubeVideoId(url);
      if (videoId == null) {
        return 'Invalid YouTube URL';
      }

      // Get video info via noembed (free, no API key needed)
      final infoUrl = 'https://noembed.com/embed?url=$url';
      final infoResponse = await http.get(Uri.parse(infoUrl));

      String title = 'YouTube Video';
      String description = '';

      if (infoResponse.statusCode == 200) {
        final info = jsonDecode(infoResponse.body);
        title = info['title'] ?? 'YouTube Video';
        description =
            info['author_name'] != null ? 'By: ${info['author_name']}' : '';
      }

      // Try to get captions via a public transcript API
      // Note: This is a fallback approach - proper implementation would use youtube_explode_dart
      String transcript = await _fetchYouTubeTranscript(videoId);

      final content = StringBuffer();
      content.writeln('# $title');
      if (description.isNotEmpty) {
        content.writeln(description);
      }
      content.writeln('\nVideo ID: $videoId');
      content.writeln('URL: $url');

      if (transcript.isNotEmpty) {
        content.writeln('\n## Transcript');
        content.writeln(transcript);
      } else {
        content.writeln('\n## Note');
        content.writeln(
            'Transcript extraction requires the youtube_explode_dart package.');
        content.writeln('Add it to pubspec.yaml for full transcript support.');
      }

      return content.toString();
    } catch (e) {
      debugPrint('Error extracting YouTube content: $e');
      return 'YouTube video added. Transcript extraction failed: $e';
    }
  }

  String? _extractYouTubeVideoId(String url) {
    // Handle various YouTube URL formats
    final patterns = [
      RegExp(r'youtu\.be/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/watch\?v=([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/embed/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/v/([a-zA-Z0-9_-]{11})'),
      RegExp(r'youtube\.com/shorts/([a-zA-Z0-9_-]{11})'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  Future<String> _fetchYouTubeTranscript(String videoId) async {
    // This is a placeholder - full implementation requires youtube_explode_dart
    // or a backend service with YouTube Data API access
    try {
      // Try a public transcript service (may have rate limits)
      final transcriptUrl =
          'https://yt-transcript-api.vercel.app/api/transcript?videoId=$videoId';
      final response = await http.get(Uri.parse(transcriptUrl)).timeout(
            const Duration(seconds: 10),
            onTimeout: () => http.Response('', 408),
          );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data.map((item) => item['text'] ?? '').join(' ');
        }
      }
    } catch (e) {
      debugPrint('Transcript fetch failed: $e');
    }
    return '';
  }

  /// Extract content from Google Drive file
  Future<String> extractGoogleDriveContent(String url) async {
    try {
      final fileId = _extractGoogleDriveFileId(url);
      if (fileId == null) {
        return 'Invalid Google Drive URL';
      }

      final fileType = _detectGoogleDriveFileType(url);

      // For public files, try direct export
      String? content;

      switch (fileType) {
        case 'document':
          // Google Docs can be exported as plain text
          content = await _exportGoogleDoc(fileId);
          break;
        case 'spreadsheet':
          // Google Sheets can be exported as CSV
          content = await _exportGoogleSheet(fileId);
          break;
        case 'presentation':
          // Google Slides - export as text (limited)
          content = await _exportGoogleSlides(fileId);
          break;
        default:
          // Generic file - try to download and extract text
          content = await _downloadAndExtract(fileId);
      }

      if (content != null && content.isNotEmpty) {
        return content;
      }

      // Fallback message
      return '''Google Drive File
ID: $fileId
Type: $fileType
URL: $url

Note: Full content extraction requires:
1. The file must be publicly shared (Anyone with link can view)
2. For Docs/Sheets/Slides, the file must allow export

If the file is private, please make it publicly accessible or copy the content manually.''';
    } catch (e) {
      debugPrint('Error extracting Google Drive content: $e');
      return 'Google Drive file added. Full extraction failed: $e';
    }
  }

  String? _extractGoogleDriveFileId(String url) {
    final patterns = [
      RegExp(r'drive\.google\.com/file/d/([a-zA-Z0-9_-]+)'),
      RegExp(r'drive\.google\.com/open\?id=([a-zA-Z0-9_-]+)'),
      RegExp(r'docs\.google\.com/document/d/([a-zA-Z0-9_-]+)'),
      RegExp(r'docs\.google\.com/spreadsheets/d/([a-zA-Z0-9_-]+)'),
      RegExp(r'docs\.google\.com/presentation/d/([a-zA-Z0-9_-]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  String _detectGoogleDriveFileType(String url) {
    if (url.contains('docs.google.com/document')) return 'document';
    if (url.contains('docs.google.com/spreadsheets')) return 'spreadsheet';
    if (url.contains('docs.google.com/presentation')) return 'presentation';
    return 'file';
  }

  Future<String?> _exportGoogleDoc(String fileId) async {
    try {
      final exportUrl =
          'https://docs.google.com/document/d/$fileId/export?format=txt';
      final response = await http.get(Uri.parse(exportUrl)).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 200) {
        return response.body;
      }
    } catch (e) {
      debugPrint('Google Doc export failed: $e');
    }
    return null;
  }

  Future<String?> _exportGoogleSheet(String fileId) async {
    try {
      final exportUrl =
          'https://docs.google.com/spreadsheets/d/$fileId/export?format=csv';
      final response = await http.get(Uri.parse(exportUrl)).timeout(
            const Duration(seconds: 15),
          );

      if (response.statusCode == 200) {
        // Convert CSV to readable format
        final lines = response.body.split('\n');
        final buffer = StringBuffer();
        for (final line in lines.take(100)) {
          // Limit to 100 rows
          buffer.writeln(line);
        }
        if (lines.length > 100) {
          buffer.writeln('... (${lines.length - 100} more rows)');
        }
        return buffer.toString();
      }
    } catch (e) {
      debugPrint('Google Sheet export failed: $e');
    }
    return null;
  }

  Future<String?> _exportGoogleSlides(String fileId) async {
    try {
      // Slides don't have a direct text export, but we can try PDF and extract
      // For now, return a placeholder
      return 'Google Slides presentation. Full text extraction requires Google API access.';
    } catch (e) {
      debugPrint('Google Slides export failed: $e');
    }
    return null;
  }

  Future<String?> _downloadAndExtract(String fileId) async {
    // For binary files, we'd need to download and process them
    // This requires additional packages like syncfusion_flutter_pdf, etc.
    return null;
  }

  /// Extract content from web URL
  Future<String> extractWebContent(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0)',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        // Basic HTML to text conversion
        String content = response.body;

        // Remove script and style tags
        content = content.replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        );
        content = content.replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        );

        // Remove HTML tags
        content = content.replaceAll(RegExp(r'<[^>]*>'), ' ');

        // Clean up whitespace
        content = content.replaceAll(RegExp(r'\s+'), ' ').trim();

        // Decode HTML entities
        content = _decodeHtmlEntities(content);

        return content;
      }
      return 'Failed to load content (HTTP ${response.statusCode})';
    } catch (e) {
      return 'Error loading content: $e';
    }
  }

  String _decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  /// Ingest source (extract content and create chunks/embeddings)
  Future<Map<String, dynamic>?> ingestSource({
    required String sourceId,
    String url = '',
  }) async {
    debugPrint('Ingest source called for: $sourceId');

    final api = ref.read(apiServiceProvider);

    try {
      final source = await api.getSource(sourceId);
      final existingUrl = source['url'] as String? ?? '';
      final resolvedUrl = url.isNotEmpty ? url : existingUrl;

      String content = source['content'] as String? ?? '';
      if (content.trim().isEmpty && resolvedUrl.isNotEmpty) {
        if (_extractYouTubeVideoId(resolvedUrl) != null) {
          content = await extractYouTubeContent(resolvedUrl);
        } else {
          content = await extractWebContent(resolvedUrl);
        }
      }

      if (content.trim().isNotEmpty) {
        await api.updateSource(
          sourceId,
          content: content,
          url: resolvedUrl.isNotEmpty ? resolvedUrl : null,
        );
      }

      // Trigger backend ingestion (chunk + embed + store)
      await api.post('/rag/ingestion/process', {
        'sourceId': sourceId,
      });

      return {
        'success': true,
        'sourceId': sourceId,
        'contentLength': content.length,
        if (resolvedUrl.isNotEmpty) 'url': resolvedUrl,
      };
    } catch (e) {
      debugPrint('Ingest source failed for $sourceId: $e');
      return {
        'success': false,
        'sourceId': sourceId,
        'error': e.toString(),
      };
    }
  }
}

final contentExtractorServiceProvider =
    Provider((ref) => ContentExtractorService(ref));
