import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/core/ai/deep_research_service.dart';

void main() {
  group('Deep Research Service - Crash Fix Tests', () {
    test('ResearchSource handles null values gracefully', () {
      final source = ResearchSource(
        title: '',
        url: '',
        content: '',
        snippet: null,
        credibility: SourceCredibility.unknown,
      );

      expect(source.title, '');
      expect(source.url, '');
      expect(source.content, '');
      expect(source.snippet, null);
    });

    test('ResearchSource.fromJson handles missing fields', () {
      final json = <String, dynamic>{
        'title': null,
        'url': null,
      };

      final source = ResearchSource.fromJson(json);

      expect(source.title, '');
      expect(source.url, '');
      expect(source.content, '');
      expect(source.credibility, SourceCredibility.unknown);
    });
  });
}
