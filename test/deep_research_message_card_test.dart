import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/features/chat/deep_research_message_card.dart';
import 'package:noteclaw/features/chat/message.dart';

void main() {
  Widget buildSubject(Message message) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DeepResearchMessageCard(message: message),
        ),
      ),
    );
  }

  testWidgets('shows a compact live state for background research',
      (tester) async {
    await tester.pumpWidget(buildSubject(Message(
      id: 'live-research',
      text: 'Starting deep research...',
      isUser: false,
      timestamp: DateTime.now(),
      isDeepSearch: true,
      isWebBrowsing: true,
      webBrowsingStatus: 'Reading trusted sources',
    )));

    expect(find.text('DEEP RESEARCH'), findsOneWidget);
    expect(find.text('Working in the background'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('Reading trusted sources'), findsOneWidget);
    expect(find.textContaining('You can leave the app'), findsOneWidget);
  });

  testWidgets('shows a structured completed report with source actions',
      (tester) async {
    await tester.pumpWidget(buildSubject(Message(
      id: 'completed-research',
      text: '## Summary\n\nThe research found a clear answer.',
      isUser: false,
      timestamp: DateTime.now(),
      isDeepSearch: true,
      isWebBrowsing: true,
      webBrowsingStatus: 'Research complete',
      webBrowsingSources: const [
        'https://example.com/report',
        'https://docs.example.org/source',
      ],
    )));

    expect(find.text('Research report ready'), findsOneWidget);
    expect(find.text('COMPLETE'), findsOneWidget);
    expect(find.text('2 sources'), findsOneWidget);
    expect(find.text('SOURCES'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('docs.example.org'), findsOneWidget);
    expect(find.text('Summary'), findsOneWidget);
    expect(find.textContaining('clear answer'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
