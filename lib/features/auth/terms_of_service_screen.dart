import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_service.dart';
import '../../theme/app_theme.dart';

class TermsOfServiceScreen extends ConsumerStatefulWidget {
  const TermsOfServiceScreen({super.key});

  @override
  ConsumerState<TermsOfServiceScreen> createState() =>
      _TermsOfServiceScreenState();
}

class _TermsOfServiceScreenState extends ConsumerState<TermsOfServiceScreen> {
  late Future<String> _termsFuture;

  @override
  void initState() {
    super.initState();
    _termsFuture = ref.read(apiServiceProvider).getTermsOfService();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms & Conditions'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      body: FutureBuilder<String>(
        future: _termsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading terms: ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final content = snapshot.data;

          if (content == null || content.isEmpty) {
            return const Center(
              child: Text('No terms and conditions available.'),
            );
          }

          return Markdown(
            data: content,
            padding: const EdgeInsets.all(16),
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: const TextStyle(fontSize: 16, height: 1.5),
              h1: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              h2: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              blockSpacing: 16,
            ),
          );
        },
      ),
    );
  }
}
