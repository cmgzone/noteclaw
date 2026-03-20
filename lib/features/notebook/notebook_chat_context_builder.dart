import '../../core/ai/ai_settings_service.dart';
import '../sources/source.dart';

class NotebookChatContextBuilder {
  static const int _minimumContextChars = 12000;
  static const int _maximumContextChars = 180000;
  static const int _maximumDetailedSources = 12;

  static Future<String> buildContextTextForCurrentModel({
    required ProviderRead read,
    required List<Source> sources,
    required String objective,
  }) async {
    final contextWindowTokens =
        await AISettingsService.getCurrentModelContextWindow(read);
    return buildContextText(
      sources: sources,
      objective: objective,
      maxContextChars: estimateContextCharBudget(contextWindowTokens),
    );
  }

  static String buildContextText({
    required List<Source> sources,
    required String objective,
    int maxContextChars = 70000,
  }) {
    return build(
      sources: sources,
      query: objective,
      maxContextChars: maxContextChars,
    ).join('\n\n');
  }

  static List<String> build({
    required List<Source> sources,
    required String query,
    int maxContextChars = 70000,
  }) {
    if (sources.isEmpty) return const [];

    final safeMaxContextChars = _clampInt(
      maxContextChars,
      _minimumContextChars,
      _maximumContextChars,
    );
    final queryTerms = _extractQueryTerms(query);
    final rankedSources = sources
        .map(
          (source) => _RankedSource(
            source: source,
            score: _scoreSource(source, queryTerms),
          ),
        )
        .toList()
      ..sort((a, b) {
        final scoreComparison = b.score.compareTo(a.score);
        if (scoreComparison != 0) return scoreComparison;
        return b.source.addedAt.compareTo(a.source.addedAt);
      });

    final sections = <String>[];
    final overviewSection = _buildOverviewSection(
      rankedSources,
      query,
      queryTerms,
    );
    sections.add(overviewSection);

    final catalogSection = _buildCatalogSection(rankedSources);
    sections.add(catalogSection);

    final usedChars = overviewSection.length + catalogSection.length;
    final remainingChars = safeMaxContextChars - usedChars;
    if (remainingChars > 2000) {
      final detailSection = _buildPriorityDetailSection(
        rankedSources,
        queryTerms,
        remainingChars,
      );
      if (detailSection.isNotEmpty) {
        sections.add(detailSection);
      }
    }

    return sections;
  }

  static int estimateContextCharBudget(int contextWindowTokens) {
    final safeContextWindow =
        contextWindowTokens > 0 ? contextWindowTokens : 32768;
    final estimatedChars = (safeContextWindow * 2.1).floor();
    return _clampInt(
      estimatedChars,
      _minimumContextChars,
      _maximumContextChars,
    );
  }

  static String _buildOverviewSection(
    List<_RankedSource> rankedSources,
    String query,
    Set<String> queryTerms,
  ) {
    final codeSourceCount = rankedSources
        .where(
            (item) => item.source.isGitHubSource || item.source.type == 'code')
        .length;
    final highRelevanceCount =
        rankedSources.where((item) => item.score >= 8).length;
    final mediumRelevanceCount =
        rankedSources.where((item) => item.score >= 4 && item.score < 8).length;
    final backgroundCount =
        rankedSources.length - highRelevanceCount - mediumRelevanceCount;

    final typeCounts = <String, int>{};
    for (final item in rankedSources) {
      final type = _sourceTypeLabel(item.source);
      typeCounts[type] = (typeCounts[type] ?? 0) + 1;
    }

    final sortedTypes = typeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topTypes = sortedTypes
        .take(4)
        .map((entry) => '${entry.key}: ${entry.value}')
        .join(', ');

    final buffer = StringBuffer()
      ..writeln('### Notebook Coverage')
      ..writeln(
        'This notebook has ${rankedSources.length} sources. Every source is listed in the catalog below so large notebooks are still represented end to end.',
      )
      ..writeln('Current objective: ${_limitInline(query, 240)}')
      ..writeln(
        'Code sources: $codeSourceCount | Other sources: ${rankedSources.length - codeSourceCount}',
      )
      ..writeln(
        'Relevance buckets for this request: high $highRelevanceCount, medium $mediumRelevanceCount, background $backgroundCount',
      );

    if (topTypes.isNotEmpty) {
      buffer.writeln('Source mix: $topTypes');
    }

    if (queryTerms.isNotEmpty) {
      buffer.writeln(
        'Query terms used for ranking: ${queryTerms.take(8).join(', ')}',
      );
    }

    buffer.writeln(
      'Use the full catalog for breadth and the priority excerpts for deeper evidence when answering.',
    );

    return buffer.toString().trimRight();
  }

  static String _buildCatalogSection(List<_RankedSource> rankedSources) {
    final synopsisLimit = rankedSources.length >= 150 ? 72 : 110;
    final titleLimit = rankedSources.length >= 150 ? 42 : 56;
    final pathLimit = rankedSources.length >= 150 ? 44 : 64;

    final lines = <String>[
      '### All Source Catalog',
      'Each source appears once here, ordered by estimated relevance to the current request.',
    ];

    for (var index = 0; index < rankedSources.length; index++) {
      final item = rankedSources[index];
      final source = item.source;
      final title = _limitInline(source.title, titleLimit);
      final path = source.githubPath != null && source.githubPath!.isNotEmpty
          ? ' | path: ${_limitInline(source.githubPath!, pathLimit)}'
          : '';
      final language = source.language != null && source.language!.isNotEmpty
          ? ' | lang: ${source.language}'
          : '';
      final synopsis = _buildSynopsis(source, maxLength: synopsisLimit);

      lines.add(
        '${index + 1}. [${_relevanceLabel(item.score)}] ${_sourceTypeLabel(source)}$language | $title$path | $synopsis',
      );
    }

    return lines.join('\n');
  }

  static String _buildPriorityDetailSection(
    List<_RankedSource> rankedSources,
    Set<String> queryTerms,
    int maxChars,
  ) {
    final relevantSources =
        rankedSources.where((item) => item.score > 0).toList();
    final selectedSources =
        (relevantSources.isNotEmpty ? relevantSources : rankedSources)
            .take(_maximumDetailedSources)
            .toList();

    if (selectedSources.isEmpty) return '';

    final lines = <String>[
      '### Priority Excerpts',
      'These are the strongest source matches for the current request. Use them for detail, while keeping the full catalog in mind for coverage.',
    ];
    var usedChars = lines.join('\n').length;

    for (var index = 0; index < selectedSources.length; index++) {
      final remainingSources = selectedSources.length - index;
      final remainingChars = maxChars - usedChars;
      if (remainingSources <= 0 || remainingChars < 700) {
        break;
      }

      final perSourceBudget = _clampInt(
        (remainingChars / remainingSources).floor(),
        700,
        2600,
      );
      final detail = _buildSourceDetail(
        selectedSources[index].source,
        queryTerms,
        perSourceBudget,
      );

      if (detail.isEmpty) {
        continue;
      }

      lines.add(detail);
      usedChars += detail.length + 1;
    }

    return lines.join('\n\n');
  }

  static String _buildSourceDetail(
    Source source,
    Set<String> queryTerms,
    int maxChars,
  ) {
    final headerLines = <String>[
      '#### ${_limitInline(source.title, 100)}',
      'Type: ${_sourceTypeLabel(source)}${source.language != null && source.language!.isNotEmpty ? ' | Language: ${source.language}' : ''}',
    ];

    if (source.githubOwner != null && source.githubRepo != null) {
      headerLines.add('Repository: ${source.githubOwner}/${source.githubRepo}');
    }
    if (source.githubPath != null && source.githubPath!.isNotEmpty) {
      headerLines.add('Path: ${source.githubPath}');
    }

    final synopsis = _buildSynopsis(source, maxLength: 220);
    if (synopsis.isNotEmpty) {
      headerLines.add('Summary: $synopsis');
    }

    final header = headerLines.join('\n');
    final remainingChars = maxChars - header.length - 2;
    if (remainingChars <= 120) {
      return _trimToLength(header, maxChars);
    }

    final excerpt = _buildExcerpt(source, queryTerms, remainingChars);
    if (excerpt.isEmpty) {
      return _trimToLength(header, maxChars);
    }

    return _trimToLength('$header\n$excerpt', maxChars);
  }

  static String _buildExcerpt(
    Source source,
    Set<String> queryTerms,
    int maxChars,
  ) {
    if (source.content.trim().isEmpty) {
      return '';
    }

    if (source.isGitHubSource || source.type == 'code') {
      return _buildCodeExcerpt(source, queryTerms, maxChars);
    }

    return _buildTextExcerpt(source.content, queryTerms, maxChars);
  }

  static String _buildCodeExcerpt(
    Source source,
    Set<String> queryTerms,
    int maxChars,
  ) {
    final lines = source.content.replaceAll('\r\n', '\n').split('\n');
    if (lines.isEmpty) {
      return '';
    }

    final matchIndexes = <int>[];
    for (var i = 0; i < lines.length; i++) {
      final normalizedLine = lines[i].toLowerCase();
      if (queryTerms.any(normalizedLine.contains)) {
        matchIndexes.add(i);
      }
      if (matchIndexes.length >= 10) {
        break;
      }
    }

    if (matchIndexes.isEmpty) {
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim().toLowerCase();
        if (_looksLikeCodeLandmark(trimmed)) {
          matchIndexes.add(i);
        }
        if (matchIndexes.length >= 5) {
          break;
        }
      }
    }

    if (matchIndexes.isEmpty) {
      matchIndexes.add(0);
    }

    final windows = <_LineWindow>[];
    for (final index in matchIndexes) {
      final start = index - 2 < 0 ? 0 : index - 2;
      final end = index + 2 >= lines.length ? lines.length - 1 : index + 2;

      if (windows.isNotEmpty && start <= windows.last.end + 1) {
        final previousWindow = windows.removeLast();
        windows.add(
          _LineWindow(
            previousWindow.start,
            end > previousWindow.end ? end : previousWindow.end,
          ),
        );
      } else {
        windows.add(_LineWindow(start, end));
      }

      if (windows.length >= 4) {
        break;
      }
    }

    final snippetLines = <String>[];
    var usedChars = 0;
    final language = source.language ?? '';

    void addSnippetLine(String line) {
      final nextLength = line.length + 1;
      if (usedChars + nextLength > maxChars) {
        return;
      }
      snippetLines.add(line);
      usedChars += nextLength;
    }

    addSnippetLine('```$language');
    for (var windowIndex = 0; windowIndex < windows.length; windowIndex++) {
      if (windowIndex > 0) {
        addSnippetLine('// ...');
      }

      final window = windows[windowIndex];
      for (var lineIndex = window.start; lineIndex <= window.end; lineIndex++) {
        final trimmedLine = _trimToLength(lines[lineIndex], 220);
        final formattedLine =
            '${(lineIndex + 1).toString().padLeft(4)} | $trimmedLine';
        addSnippetLine(formattedLine);
      }
    }
    addSnippetLine('```');

    return snippetLines.join('\n');
  }

  static String _buildTextExcerpt(
    String content,
    Set<String> queryTerms,
    int maxChars,
  ) {
    final normalizedContent = content.replaceAll('\r\n', '\n').trim();
    if (normalizedContent.isEmpty) return '';

    final rawSegments = normalizedContent
        .split(RegExp(r'\n\s*\n'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();

    final segments = rawSegments.isNotEmpty
        ? rawSegments
        : normalizedContent
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();

    final prioritizedSegments = <String>[];
    for (final segment in segments) {
      final lowered = segment.toLowerCase();
      if (queryTerms.any(lowered.contains)) {
        prioritizedSegments.add(segment);
      }
      if (prioritizedSegments.length >= 3) {
        break;
      }
    }

    if (prioritizedSegments.isEmpty) {
      prioritizedSegments.addAll(segments.take(2));
    }

    final excerptLines = <String>[];
    var usedChars = 0;
    for (var index = 0; index < prioritizedSegments.length; index++) {
      final segment = _trimToLength(prioritizedSegments[index], 420);
      final prefix = index == 0 ? '' : '\n...\n';
      final piece = '$prefix$segment';
      if (usedChars + piece.length > maxChars) {
        break;
      }
      excerptLines.add(piece);
      usedChars += piece.length;
    }

    return excerptLines.join();
  }

  static double _scoreSource(Source source, Set<String> queryTerms) {
    var score = 0.0;
    if (source.isGitHubSource) score += 2.5;
    if (source.type == 'code') score += 1.8;
    if (source.hasAgentSession) score += 0.4;

    score += _countMatches(source.title, queryTerms) * 4.0;
    score += _countMatches(source.githubPath ?? '', queryTerms) * 4.5;
    score += _countMatches(source.summary ?? '', queryTerms) * 3.5;
    score += _countMatches(source.description ?? '', queryTerms) * 2.5;
    score += _countMatches(_metadataSummary(source), queryTerms) * 2.0;

    final searchableContent = source.content.length > 5000
        ? '${source.content.substring(0, 2500)}\n${source.content.substring(source.content.length - 2500)}'
        : source.content;
    score += _countMatches(searchableContent, queryTerms) * 1.2;

    final ageInDays = DateTime.now().difference(source.addedAt).inDays.abs();
    if (ageInDays <= 7) {
      score += 0.8;
    } else if (ageInDays <= 30) {
      score += 0.4;
    }

    if (queryTerms.isEmpty) {
      score += 0.5;
    }

    return score;
  }

  static bool _looksLikeCodeLandmark(String line) {
    return line.startsWith('class ') ||
        line.startsWith('interface ') ||
        line.startsWith('enum ') ||
        line.startsWith('type ') ||
        line.startsWith('typedef ') ||
        line.startsWith('function ') ||
        line.startsWith('def ') ||
        line.startsWith('async function ') ||
        line.contains(' extends ') ||
        line.contains(' implements ') ||
        line.startsWith('export ') ||
        line.startsWith('import ');
  }

  static int _countMatches(String value, Set<String> queryTerms) {
    if (value.isEmpty || queryTerms.isEmpty) return 0;
    final normalized = value.toLowerCase();
    var count = 0;
    for (final term in queryTerms) {
      if (normalized.contains(term)) {
        count++;
      }
    }
    return count;
  }

  static Set<String> _extractQueryTerms(String query) {
    final stopWords = <String>{
      'a',
      'an',
      'and',
      'are',
      'be',
      'but',
      'by',
      'for',
      'from',
      'get',
      'how',
      'i',
      'in',
      'into',
      'is',
      'it',
      'like',
      'many',
      'of',
      'on',
      'or',
      'please',
      'show',
      'that',
      'the',
      'this',
      'to',
      'use',
      'what',
      'with',
      'would',
      'you',
    };

    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_./-]+'))
        .where((term) => term.length >= 2 && !stopWords.contains(term))
        .take(12)
        .toSet();
  }

  static String _buildSynopsis(Source source, {required int maxLength}) {
    final candidates = <String?>[
      source.summary,
      source.description,
      source.metadata['analysisSummary']?.toString(),
      source.metadata['analysis_summary']?.toString(),
      source.metadata['summary']?.toString(),
      source.metadata['description']?.toString(),
    ];

    for (final candidate in candidates) {
      final cleaned = _cleanInline(candidate);
      if (cleaned.isNotEmpty) {
        return _limitInline(cleaned, maxLength);
      }
    }

    final derived = source.isGitHubSource || source.type == 'code'
        ? _extractCodeSynopsis(source.content)
        : _firstMeaningfulSnippet(source.content);

    return _limitInline(derived, maxLength);
  }

  static String _metadataSummary(Source source) {
    final owner = source.githubOwner;
    final repo = source.githubRepo;
    final path = source.githubPath;
    final agentName = source.agentName;
    return [
      if (owner != null && repo != null) '$owner/$repo',
      if (path != null) path,
      if (agentName != null) agentName,
    ].join(' ');
  }

  static String _extractCodeSynopsis(String content) {
    final lines = content
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final matches = <String>[];
    for (final line in lines) {
      final lowered = line.toLowerCase();
      if (_looksLikeCodeLandmark(lowered) || lowered.startsWith('@')) {
        matches.add(_cleanInline(line));
      }
      if (matches.length >= 3) {
        break;
      }
    }

    if (matches.isNotEmpty) {
      return matches.join(' | ');
    }

    return _firstMeaningfulSnippet(content);
  }

  static String _firstMeaningfulSnippet(String content) {
    final normalizedLines = content
        .replaceAll('\r\n', '\n')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(4)
        .map(_cleanInline)
        .where((line) => line.isNotEmpty)
        .toList();

    return normalizedLines.join(' ');
  }

  static String _cleanInline(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _limitInline(String value, int maxLength) {
    final cleaned = _cleanInline(value);
    return _trimToLength(cleaned, maxLength);
  }

  static String _trimToLength(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    if (maxLength <= 3) return value.substring(0, maxLength);
    return '${value.substring(0, maxLength - 3)}...';
  }

  static String _relevanceLabel(double score) {
    if (score >= 8) return 'high';
    if (score >= 4) return 'medium';
    return 'background';
  }

  static String _sourceTypeLabel(Source source) {
    if (source.isGitHubSource) return 'github';
    if (source.type == 'code') return 'code';
    return source.type;
  }

  static int _clampInt(int value, int min, int max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

class _RankedSource {
  const _RankedSource({
    required this.source,
    required this.score,
  });

  final Source source;
  final double score;
}

class _LineWindow {
  const _LineWindow(this.start, this.end);

  final int start;
  final int end;
}
