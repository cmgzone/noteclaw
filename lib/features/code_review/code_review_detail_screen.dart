import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'code_review_detail_view.dart';
import 'code_review_provider.dart';

class CodeReviewDetailScreen extends ConsumerWidget {
  const CodeReviewDetailScreen({
    super.key,
    required this.reviewId,
  });

  final String reviewId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewAsync = ref.watch(codeReviewDetailProvider(reviewId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Details'),
      ),
      body: reviewAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(
                  'Unable to load this review.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    ref.invalidate(codeReviewDetailProvider(reviewId));
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
        data: (review) => RefreshIndicator(
          onRefresh: () =>
              ref.refresh(codeReviewDetailProvider(reviewId).future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              CodeReviewDetailView(review: review),
            ],
          ),
        ),
      ),
    );
  }
}
