import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'artifact.dart';
import '../../core/extensions/color_compat.dart';

class ArtifactViewerScreen extends ConsumerWidget {
  const ArtifactViewerScreen({super.key, required this.artifact});
  final Artifact artifact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    // Debug: print artifact content
    debugPrint('[ArtifactViewer] Title: ${artifact.title}');
    debugPrint('[ArtifactViewer] Content length: ${artifact.content.length}');
    debugPrint(
        '[ArtifactViewer] Content preview: ${artifact.content.substring(0, artifact.content.length.clamp(0, 200))}');

    return Scaffold(
      appBar: AppBar(
        title: Text(artifact.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              onPressed: () => _export(context), icon: const Icon(Icons.share)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(artifact.title, style: text.headlineSmall),
            const SizedBox(height: 8),
            Text(
                'Generated ${artifact.createdAt.day}/${artifact.createdAt.month}/${artifact.createdAt.year}'),
            const SizedBox(height: 24),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: artifact.content.isEmpty
                    ? Center(
                        child: Text(
                          'No content generated. Check that your sources have content.',
                          style: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      )
                    : Markdown(
                        data: artifact.content,
                        shrinkWrap: false,
                        physics: const ClampingScrollPhysics(),
                        styleSheet: MarkdownStyleSheet(
                          h1: text.headlineSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                          h2: text.titleLarge?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                          h3: text.titleMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                          p: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          listBullet: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          strong: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          em: text.bodyMedium?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          blockquote: text.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.secondaryText,
                            fontStyle: FontStyle.italic,
                          ),
                          code: text.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _export(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      Share.share(
        '${artifact.title}\n\n${artifact.content}',
        sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size,
      );
    } else {
      Share.share('${artifact.title}\n\n${artifact.content}');
    }
  }
}
