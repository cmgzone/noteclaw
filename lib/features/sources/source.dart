import 'package:freezed_annotation/freezed_annotation.dart';

part 'source.freezed.dart';
part 'source.g.dart';

@freezed
class Source with _$Source {
  const factory Source({
    required String id,
    required String notebookId,
    required String title,
    required String
        type, // drive, file, url, youtube, audio, text, image, github, code
    required DateTime addedAt,
    required String content, // raw text or transcript
    String? summary,
    DateTime? summaryGeneratedAt,
    String? imageUrl, // URL or base64 data URL for image sources
    String? thumbnailUrl, // Optional thumbnail for previews
    @Default([]) List<String> tagIds,
    @Default({})
    Map<String, dynamic>
        metadata, // Additional metadata (e.g., GitHub info, agent info)
  }) = _Source;

  factory Source.fromJson(Map<String, dynamic> json) => _$SourceFromJson(json);
}

/// Extension methods for Source to check for GitHub and agent-related properties
extension SourceExtensions on Source {
  static const String _previewViewportMeta =
      '<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">';

  static const String _previewBaseStyles = '''
    <style data-noteclaw-preview-base>
      html {
        width: 100%;
      }

      body {
        margin: 0;
        padding: 0;
        width: 100%;
        max-width: 100%;
        overflow-x: hidden;
      }

      img,
      video,
      canvas,
      svg,
      iframe {
        max-width: 100%;
      }
    </style>
  ''';

  String? get mimeType {
    final rawValue = metadata['mimeType'] ?? metadata['mime_type'];
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
    return null;
  }

  String? get sourceUrl {
    final rawValue = metadata['url'] ?? metadata['sourceUrl'];
    if (rawValue is String && rawValue.trim().isNotEmpty) {
      return rawValue.trim();
    }
    return null;
  }

  /// Check if this is a GitHub source
  bool get isGitHubSource => type == 'github';

  /// Check if this source was created by a coding agent
  bool get hasAgentSession => metadata['agentSessionId'] != null;

  /// Get the agent name if this source was created by an agent
  String? get agentName => metadata['agentName'] as String?;

  /// Get the agent session ID if this source was created by an agent
  String? get agentSessionId => metadata['agentSessionId'] as String?;

  /// Get GitHub owner if this is a GitHub source
  String? get githubOwner => metadata['owner'] as String?;

  /// Get GitHub repo if this is a GitHub source
  String? get githubRepo => metadata['repo'] as String?;

  /// Get GitHub path if this is a GitHub source
  String? get githubPath => metadata['path'] as String?;

  /// Get GitHub branch if this is a GitHub source
  String? get githubBranch => metadata['branch'] as String?;

  /// Get GitHub commit SHA if this is a GitHub source
  String? get githubCommitSha => metadata['commitSha'] as String?;

  /// Get the detected language if this is a GitHub source
  String? get language => metadata['language'] as String?;

  bool get isHtmlSource {
    final normalizedMimeType = mimeType?.toLowerCase();
    if (normalizedMimeType != null && normalizedMimeType.contains('html')) {
      return true;
    }

    final normalizedLanguage = language?.toLowerCase();
    if (normalizedLanguage != null &&
        ['html', 'htm', 'xhtml'].contains(normalizedLanguage)) {
      return true;
    }

    final normalizedContent = content.toLowerCase();
    return normalizedContent.contains('```html') ||
        normalizedContent.contains('<!doctype html') ||
        normalizedContent.contains('<html') ||
        normalizedContent.contains('</html>');
  }

  bool get hasRenderableHtmlMarkup {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return false;
    }

    final fencedHtmlMatch = RegExp(
      r'```html\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final extracted = fencedHtmlMatch?.group(1)?.trim() ?? trimmed;
    final lower = extracted.toLowerCase();

    if (lower.contains('&lt;html') || lower.contains('&lt;body')) {
      return false;
    }

    if (lower.contains('<!doctype html') ||
        lower.contains('<html') ||
        lower.contains('<body') ||
        lower.contains('<head')) {
      return true;
    }

    final tagMatches = RegExp(
      r'<([a-z][a-z0-9:-]*)\b[^>]*>',
      caseSensitive: false,
    ).allMatches(extracted);

    if (tagMatches.length < 3) {
      return false;
    }

    const commonHtmlTags = {
      'div',
      'span',
      'main',
      'section',
      'article',
      'header',
      'footer',
      'nav',
      'h1',
      'h2',
      'h3',
      'p',
      'a',
      'img',
      'button',
      'form',
      'input',
      'script',
      'style',
    };

    final matchedTags = tagMatches
        .map((match) => (match.group(1) ?? '').toLowerCase())
        .where(commonHtmlTags.contains)
        .toSet();

    return matchedTags.length >= 2;
  }

  String? get renderableHtmlDocument {
    if (!isHtmlSource || !hasRenderableHtmlMarkup) {
      return null;
    }

    var html = content.trim();
    if (html.isEmpty) {
      return null;
    }

    final fencedHtmlMatch = RegExp(
      r'```html\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(html);
    if (fencedHtmlMatch != null) {
      html = fencedHtmlMatch.group(1)?.trim() ?? html;
    } else {
      final fencedMatch = RegExp(
        r'```[a-z0-9_-]*\s*([\s\S]*?)```',
        caseSensitive: false,
      ).firstMatch(html);
      if (fencedMatch != null) {
        html = fencedMatch.group(1)?.trim() ?? html;
      }
    }

    final lowerHtml = html.toLowerCase();
    final closingHtmlIndex = lowerHtml.lastIndexOf('</html>');
    if (closingHtmlIndex >= 0) {
      html = html.substring(0, closingHtmlIndex + 7).trim();
    }

    final hasDocumentTag =
        RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(html);
    if (hasDocumentTag) {
      return _normalizePreviewHtml(html);
    }

    return '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    $_previewViewportMeta
    <title>$title</title>
    $_previewBaseStyles
  </head>
  <body>
$html
  </body>
</html>''';
  }

  String _normalizePreviewHtml(String html) {
    var normalizedHtml = html;
    final hasViewportMeta = RegExp(
      r'<meta[^>]+name\s*=\s*["'']viewport["''][^>]*>',
      caseSensitive: false,
    ).hasMatch(normalizedHtml);
    final hasBaseStyles = normalizedHtml.contains(
      'data-noteclaw-preview-base',
    );

    if (!hasViewportMeta || !hasBaseStyles) {
      final headMatch = RegExp(r'<head[^>]*>', caseSensitive: false)
          .firstMatch(normalizedHtml);
      if (headMatch != null) {
        final insertionOffset = headMatch.end;
        final buffer = StringBuffer();
        buffer.write(normalizedHtml.substring(0, insertionOffset));
        if (!hasViewportMeta) {
          buffer.write(_previewViewportMeta);
        }
        if (!hasBaseStyles) {
          buffer.write(_previewBaseStyles);
        }
        buffer.write(normalizedHtml.substring(insertionOffset));
        normalizedHtml = buffer.toString();
      } else {
        normalizedHtml = '''
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    ${hasViewportMeta ? '' : _previewViewportMeta}
    ${hasBaseStyles ? '' : _previewBaseStyles}
    <title>$title</title>
  </head>
  <body>
$normalizedHtml
  </body>
</html>''';
      }
    }

    return normalizedHtml;
  }

  /// Get the GitHub URL if this is a GitHub source
  String? get githubUrl => metadata['githubUrl'] as String?;

  /// Get the original conversation context if this source was created by an agent
  String? get conversationContext =>
      metadata['conversationContext'] as String? ??
      metadata['originalContext'] as String?;

  /// Check if this source has conversation context
  bool get hasConversationContext =>
      conversationContext != null && conversationContext!.isNotEmpty;

  /// Get verification result if this is a verified code source
  Map<String, dynamic>? get verification =>
      metadata['verification'] as Map<String, dynamic>?;

  /// Check if this source is verified
  bool get isVerified =>
      verification != null && verification!['isValid'] == true;

  /// Get verification score
  int? get verificationScore => verification?['score'] as int?;

  /// Get the description if available
  String? get description => metadata['description'] as String?;
}
