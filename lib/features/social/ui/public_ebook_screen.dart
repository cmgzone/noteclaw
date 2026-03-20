import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/api/api_service.dart';
import '../../../core/utils/public_share_link.dart';
import '../../../ui/widgets/app_network_image.dart';
import '../../ebook/ebook_provider.dart';
import '../../ebook/models/ebook_project.dart';
import '../../ebook/ui/ebook_reader_screen.dart';
import '../social_sharing_provider.dart';

class PublicEbookScreen extends ConsumerStatefulWidget {
  const PublicEbookScreen({super.key, required this.ebookId});

  final String ebookId;

  @override
  ConsumerState<PublicEbookScreen> createState() => _PublicEbookScreenState();
}

class _PublicEbookScreenState extends ConsumerState<PublicEbookScreen> {
  bool _isLoading = true;
  bool _isForking = false;
  bool _isLiking = false;
  String? _error;
  EbookProject? _ebook;
  Map<String, dynamic>? _owner;
  int _likeCount = 0;
  int _viewCount = 0;
  bool _userLiked = false;

  @override
  void initState() {
    super.initState();
    _loadEbook();
  }

  Future<void> _loadEbook() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.get('/social-sharing/public/ebooks/${widget.ebookId}');

      if (!mounted) return;

      if (response['success'] != true || response['ebook'] == null) {
        setState(() {
          _error = 'Ebook not found or not public';
          _isLoading = false;
        });
        return;
      }

      final ebookJson = Map<String, dynamic>.from(response['ebook'] as Map);
      ebookJson['chapters'] = List<dynamic>.from(response['chapters'] ?? const []);
      final ebook = EbookProject.fromBackendJson(ebookJson);

      setState(() {
        _ebook = ebook;
        _owner = response['owner'] is Map
            ? Map<String, dynamic>.from(response['owner'] as Map)
            : null;
        _likeCount = _parseInt(ebookJson['like_count']);
        _viewCount = _parseInt(ebookJson['view_count']);
        _userLiked = ebookJson['user_liked'] == true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _forkEbook() async {
    setState(() => _isForking = true);

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post('/social-sharing/fork/ebook/${widget.ebookId}', {});

      if (!mounted) return;

      if (response['success'] == true && response['ebook'] != null) {
        final ebookJson = Map<String, dynamic>.from(response['ebook'] as Map);
        ebookJson['chapters'] =
            List<dynamic>.from(response['chapters'] ?? const []);
        final forkedEbook = EbookProject.fromBackendJson(ebookJson);

        await ref.read(ebookProvider.notifier).refresh();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ebook forked! ${response['chaptersCopied'] ?? forkedEbook.chapters.length} chapters copied.',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => EbookReaderScreen(project: forkedEbook),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fork ebook: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isForking = false);
      }
    }
  }

  Future<void> _sharePublicLink() async {
    final ebook = _ebook;
    if (ebook == null) return;

    try {
      final publicUrl = buildPublicShareLink('/social/ebook/${widget.ebookId}');
      await Share.share(
        'Ebook: ${ebook.title}\n$publicUrl',
        subject: ebook.title,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share ebook: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _likeEbook() async {
    if (_userLiked || _isLiking) return;

    setState(() => _isLiking = true);
    try {
      await ref.read(socialSharingServiceProvider).likeContent('ebook', widget.ebookId);
      if (!mounted) return;
      setState(() {
        _userLiked = true;
        _likeCount++;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to like ebook: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLiking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ebook = _ebook;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || ebook == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Public Ebook')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.auto_stories_outlined, size: 64),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Ebook not found',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => context.pop(),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final primaryColor = Color(ebook.branding.primaryColorValue);
    final ownerName = _owner?['username']?.toString() ?? 'Unknown';
    final chapterCount = ebook.chapters.length;

    return Scaffold(
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _userLiked ? null : _likeEbook,
                  icon: _isLiking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _userLiked ? Icons.favorite : Icons.favorite_border,
                          color: _userLiked ? Colors.red : null,
                        ),
                  label: Text(_userLiked ? 'Liked' : 'Like'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _isForking ? null : _forkEbook,
                  icon: _isForking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.fork_right),
                  label: Text(_isForking ? 'Forking...' : 'Fork to My Ebooks'),
                ),
              ),
            ],
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(ebook.title),
            expandedHeight: 300,
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                tooltip: 'Share Link',
                onPressed: _sharePublicLink,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _buildCover(ebook, primaryColor),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: primaryColor.withValues(alpha: 0.15),
                        child: Text(
                          ownerName.isNotEmpty ? ownerName[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'by $ownerName',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Published ${timeago.format(ebook.createdAt)}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _StatChip(icon: Icons.menu_book_outlined, label: '$chapterCount chapters'),
                      _StatChip(icon: Icons.visibility_outlined, label: '$_viewCount views'),
                      _StatChip(icon: Icons.favorite_border, label: '$_likeCount likes'),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (ebook.topic.isNotEmpty) ...[
                    Text(
                      'Topic',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(ebook.topic, style: Theme.of(context).textTheme.bodyLarge),
                    const SizedBox(height: 16),
                  ],
                  if (ebook.targetAudience.isNotEmpty) ...[
                    Text(
                      'Audience',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      ebook.targetAudience,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = ebook.chapters[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 28),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.5),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chapter ${index + 1}',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chapter.title,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          MarkdownBody(data: chapter.content),
                        ],
                      ),
                    ),
                  );
                },
                childCount: ebook.chapters.length,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCover(EbookProject ebook, Color primaryColor) {
    final coverImageUrl = ebook.coverImageUrl;
    if (coverImageUrl == null || coverImageUrl.isEmpty) {
      return Container(color: primaryColor);
    }

    if (coverImageUrl.startsWith('data:image')) {
      return Image.memory(
        base64Decode(coverImageUrl.split(',').last),
        fit: BoxFit.cover,
      );
    }

    return AppNetworkImage(
      imageUrl: coverImageUrl,
      fit: BoxFit.cover,
      errorWidget: (_) => Container(color: primaryColor),
    );
  }

  int _parseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
