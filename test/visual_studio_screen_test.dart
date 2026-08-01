import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/features/studio/visual_studio_screen.dart';

void main() {
  testWidgets('Visual Studio renders its generation controls', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: VisualStudioScreen(
            notebookId: 'notebook-test',
            notebookTitle: 'Test notebook',
          ),
        ),
      ),
    );

    expect(find.text('Visual Studio'), findsOneWidget);
    expect(find.text('Using notebook: Test notebook'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Generate Image'), findsOneWidget);
  });
}
