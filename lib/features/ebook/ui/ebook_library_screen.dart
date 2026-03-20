import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../ebook_provider.dart';
import '../models/ebook_project.dart';
import 'ebook_reader_screen.dart';
import '../../../ui/widgets/app_network_image.dart';

class EbookLibraryScreen extends ConsumerStatefulWidget {
  const EbookLibraryScreen({super.key});

  @override
  ConsumerState<EbookLibraryScreen> createState() => _EbookLibraryScreenState();
}

class _EbookLibraryScreenState extends ConsumerState<EbookLibraryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(ebookProvider.notifier).loadEbooks());
  }

  @override
  Widget build(BuildContext context) {
    final ebooks = ref.watch(ebookProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Ebooks'),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => ref.read(ebookProvider.notifier).refresh(),
            tooltip: 'Refresh Library',
          ),
          IconButton(
            icon: const Icon(LucideIcons.plus),
            onPressed: () => context.push('/ebook-creator'),
            tooltip: 'Create New Ebook',
          ),
        ],
      ),
      body: ebooks.isEmpty
          ? _EmptyState(onCreatePressed: () => context.push('/ebook-creator'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: ebooks.length,
              itemBuilder: (context, index) {
                final ebook = ebooks[index];
                return _EbookCard(
                  ebook: ebook,
                  onTap: () => _openEbook(context, ebook),
                  onDelete: () => _confirmDelete(context, ref, ebook),
                );
              },
            ),
      floatingActionButton: ebooks.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/ebook-creator'),
              icon: const Icon(LucideIcons.plus),
              label: const Text('New Ebook'),
            )
          : null,
    );
  }

  void _openEbook(BuildContext context, EbookProject ebook) {
    if (ebook.status == EbookStatus.completed) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EbookReaderScreen(project: ebook)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ebook is ${ebook.status.name}. Cannot open yet.'),
        ),
      );
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, EbookProject ebook) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Ebook?'),
        content: Text('Are you sure you want to delete "${ebook.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              ref.read(ebookProvider.notifier).deleteEbook(ebook.id);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreatePressed;

  const _EmptyState({required this.onCreatePressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.bookOpen,
              size: 80,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'No Ebooks Yet',
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first AI-generated ebook',
              style: text.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onCreatePressed,
              icon: const Icon(LucideIcons.sparkles),
              label: const Text('Create Ebook'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EbookCard extends StatelessWidget {
  final EbookProject ebook;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _EbookCard({
    required this.ebook,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final brandColor = Color(ebook.branding.primaryColorValue);
    final coverImageUrl = ebook.coverImageUrl;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            // Cover thumbnail
            Container(
              width: 80,
              height: 110,
              decoration: BoxDecoration(
                color: brandColor.withValues(alpha: 0.2),
              ),
              child: coverImageUrl == null || coverImageUrl.isEmpty
                  ? Icon(LucideIcons.book, color: brandColor, size: 32)
                  : AppNetworkImage(
                      imageUrl: coverImageUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorWidget: (_) =>
                          Icon(LucideIcons.book, color: brandColor, size: 32),
                    ),
            ),
            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ebook.title,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ebook.topic,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _StatusChip(status: ebook.status),
                        const Spacer(),
                        Text(
                          '${ebook.chapters.length} chapters',
                          style: text.labelSmall,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // Actions
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') onDelete();
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(LucideIcons.trash2, size: 18),
                      SizedBox(width: 8),
                      Text('Delete'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final EbookStatus status;

  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      EbookStatus.draft => (Colors.grey, 'Draft'),
      EbookStatus.generating => (Colors.orange, 'Generating'),
      EbookStatus.completed => (Colors.green, 'Completed'),
      EbookStatus.error => (Colors.red, 'Error'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
