import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../search/serper_service.dart';
import 'ai_provider.dart';

/// Represents a web browsing action taken by the AI
class WebBrowsingAction {
  final String type; // 'search', 'visit', 'screenshot', 'extract'
  final String description;
  final String? url;
  final String? query;
  final String? content;
  final String? screenshotUrl;
  final DateTime timestamp;

  WebBrowsingAction({
    required this.type,
    required this.description,
    this.url,
    this.query,
    this.content,
    this.screenshotUrl,
    required this.timestamp,
  });
}

/// Update sent during web browsing
class WebBrowsingUpdate {
  final String status;
  final String? currentUrl;
  final String? screenshotUrl;
  final List<WebBrowsingAction> actions;
  final String? partialResponse;
  final bool isComplete;
  final String? finalResponse;
  final List<String> sources;

  WebBrowsingUpdate({
    required this.status,
    this.currentUrl,
    this.screenshotUrl,
    this.actions = const [],
    this.partialResponse,
    this.isComplete = false,
    this.finalResponse,
    this.sources = const [],
  });
}

class WebBrowsingService {
  final Ref ref;

  WebBrowsingService(this.ref);

  /// Browse the web to answer a user query with real-time updates
  Stream<WebBrowsingUpdate> browse({
    required String query,
    int maxPages = 3,
  }) async* {
    final actions = <WebBrowsingAction>[];
    final sources = <String>[];
    final contentBuffer = StringBuffer();

    try {
      // Step 1: Search the web
      yield WebBrowsingUpdate(
        status: 'Searching the web for: "$query"',
        actions: actions,
      );

      final serper = ref.read(serperServiceProvider);
      final searchResults = await serper.search(query, num: 5);

      if (searchResults.isEmpty) {
        yield WebBrowsingUpdate(
          status: 'No results found',
          isComplete: true,
          finalResponse:
              'I couldn\'t find any relevant information for your query.',
          actions: actions,
        );
        return;
      }

      actions.add(WebBrowsingAction(
        type: 'search',
        description:
            'Searched for "$query" - found ${searchResults.length} results',
        query: query,
        timestamp: DateTime.now(),
      ));

      yield WebBrowsingUpdate(
        status: 'Found ${searchResults.length} results, analyzing top pages...',
        actions: actions,
      );

      // Step 2: Visit top pages and extract content
      int pagesVisited = 0;
      for (final result in searchResults.take(maxPages)) {
        pagesVisited++;

        yield WebBrowsingUpdate(
          status: 'Reading page $pagesVisited/$maxPages: ${result.title}',
          currentUrl: result.link,
          actions: actions,
        );

        // Get screenshot of the page
        final screenshotUrl = await _getPageScreenshot(result.link);

        // Fetch page content
        final content = await serper.fetchPageContent(result.link);

        if (content.isNotEmpty) {
          // Truncate content to avoid token limits
          final truncatedContent = content.length > 3000
              ? '${content.substring(0, 3000)}...'
              : content;

          contentBuffer
              .writeln('\n--- Source: ${result.title} (${result.link}) ---');
          contentBuffer.writeln(truncatedContent);

          sources.add(result.link);

          actions.add(WebBrowsingAction(
            type: 'visit',
            description: 'Visited: ${result.title}',
            url: result.link,
            content: truncatedContent.substring(
                0, truncatedContent.length.clamp(0, 200)),
            screenshotUrl: screenshotUrl,
            timestamp: DateTime.now(),
          ));

          yield WebBrowsingUpdate(
            status: 'Extracted content from ${result.title}',
            currentUrl: result.link,
            screenshotUrl: screenshotUrl,
            actions: actions,
            sources: sources,
          );
        }

        // Small delay to avoid rate limiting
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Step 3: Generate AI response based on gathered content
      yield WebBrowsingUpdate(
        status: 'Analyzing information and generating response...',
        actions: actions,
        sources: sources,
      );

      final prompt =
          '''Based on the following web search results, provide a comprehensive and accurate answer to the user's question.

User Question: $query

Web Search Results:
${contentBuffer.toString()}

Instructions:
1. Synthesize information from multiple sources
2. Provide accurate, up-to-date information
3. Cite sources when making specific claims
4. If information conflicts between sources, mention this
5. Format your response clearly with sections if needed

Response:''';

      // Use AI provider to generate response
      // Route synthesis through the backend so the selected provider and
      // credit accounting are authoritative for every Flutter build.
      await ref
          .read(aiProvider.notifier)
          .generateContent(prompt, billingFeature: 'chat_message');
      final response =
          ref.read(aiProvider).lastResponse ?? 'Unable to generate response';

      actions.add(WebBrowsingAction(
        type: 'extract',
        description: 'Generated response from ${sources.length} sources',
        timestamp: DateTime.now(),
      ));

      yield WebBrowsingUpdate(
        status: 'Complete',
        isComplete: true,
        finalResponse: response,
        actions: actions,
        sources: sources,
      );
    } catch (e) {
      debugPrint('[WebBrowsingService] Error: $e');
      yield WebBrowsingUpdate(
        status: 'Error: $e',
        isComplete: true,
        finalResponse: 'I encountered an error while browsing the web: $e',
        actions: actions,
        sources: sources,
      );
    }
  }

  /// Get a screenshot of a webpage using a screenshot API
  Future<String?> _getPageScreenshot(String url) async {
    try {
      // Using thum.io for free webpage screenshots
      final screenshotUrl = 'https://image.thum.io/get/width/400/crop/600/$url';

      // Verify the screenshot URL works
      final response = await http
          .head(Uri.parse(screenshotUrl))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return screenshotUrl;
      }
      return null;
    } catch (e) {
      debugPrint('[WebBrowsingService] Screenshot error: $e');
      return null;
    }
  }
}

final webBrowsingServiceProvider = Provider((ref) => WebBrowsingService(ref));
