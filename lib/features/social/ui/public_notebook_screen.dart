import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../social_sharing_provider.dart';
import '../../../core/api/api_service.dart';
import '../../../core/sources/source_icon_helper.dart';
import '../../../core/utils/public_share_link.dart';
import '../../../theme/app_theme.dart';

/// Screen to view a public notebook with its sources
/// Users can view source details and fork the notebook to their account
class PublicNotebookScreen extends ConsumerStatefulWidget {
  final String notebookId;

  const PublicNotebookScreen({super.key, required this.notebookId});

  @override
  ConsumerState<PublicNotebookScreen> createState() =>
      _PublicNotebookScreenState();
}

class _PublicNotebookScreenState extends ConsumerState<PublicNotebookScreen> {
  bool _isLoading = true;
  bool _isForking = false;
  String? _error;
  Map<String, dynamic>? _notebook;
  List<dynamic> _sources = [];
  Map<String, dynamic>? _owner;

  @override
  void initState() {
    super.initState();
    _loadNotebookDetails();
  }

  Future<void> _loadNotebookDetails() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      // Ensure notebookId is valid
      if (widget.notebookId.isEmpty) {
        throw Exception('Invalid notebook ID');
      }

      final response = await api
          .get('/social-sharing/public/notebooks/${widget.notebookId}');

      if (!mounted) return;

      if (response['success'] == true) {
        setState(() {
          _notebook = response['notebook'];
          _sources = response['sources'] ?? [];
          _owner = response['owner'];
          _isLoading = false;
        });

      } else {
        setState(() {
          _error = 'Notebook not found or not public';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _forkNotebook() async {
    setState(() => _isForking = true);

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.post(
        '/social-sharing/fork/notebook/${widget.notebookId}',
        {'includeSources': true},
      );

      if (!mounted) return;

      if (response['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Notebook forked! ${response['sourcesCopied']} sources copied.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                if (mounted) {
                  context.push('/notebook/${response['notebook']['id']}');
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to fork: $e'),
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

  void _showSourceDetail(Map<String, dynamic> source) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // Use theme's bottom sheet style implicitly or override here for extra fancy
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => _SourceDetailSheet(
          source: source,
          scrollController: scrollController,
        ),
      ),
    );
  }

  Future<void> _shareNotebook(String title) async {
    try {
      final publicUrl =
          buildPublicShareLink('/social/notebook/${widget.notebookId}');
      await Share.share(
        'Notebook: $title\n$publicUrl',
        subject: title,
      );
      try {
        await ref.read(socialSharingServiceProvider).shareContent(
              contentType: 'notebook',
              contentId: widget.notebookId,
            );
      } catch (_) {
        // Ignore analytics failures.
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to share: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Loading...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _notebook == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: theme.colorScheme.error),
              const SizedBox(height: 16),
              Text(_error ?? 'Notebook not found',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    final notebook = _notebook!;
    final title = notebook['title'] ?? 'Untitled';
    final description = notebook['description'];
    final sourceCount = _sources.length;
    final viewCount = notebook['view_count'] ?? 0;
    final likeCount = notebook['like_count'] ?? 0;
    final avatarUrl = _owner?['avatarUrl'];
    final username = _owner?['username'] ?? 'Unknown';

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: BackButton(
          color: Colors.white, // Always white on top of gradient
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            onPressed: () => _shareNotebook(title.toString()),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          // Premium Header with Gradient
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.premiumGradient,
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
                  child: Column(
                    children: [
                      // Large Icon / Avatar for Notebook
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.book, // Or category icon
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        title.toString(),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Owner pill
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.white24,
                              backgroundImage: (avatarUrl != null &&
                                      avatarUrl.toString().isNotEmpty)
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: (avatarUrl == null ||
                                      avatarUrl.toString().isEmpty)
                                  ? Text(
                                      username.isNotEmpty
                                          ? username[0].toUpperCase()
                                          : '?',
                                      style: const TextStyle(
                                          fontSize: 10, color: Colors.white),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'by $username',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (description != null &&
                          description.toString().isNotEmpty) ...[
                        Text(
                          description.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      // Glass Stats Row
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 24),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _StatVertical(
                              icon: Icons.filter_none,
                              value: sourceCount.toString(),
                              label: 'Sources',
                            ),
                            Container(
                                width: 1,
                                height: 24,
                                color: Colors.white24,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 24)),
                            _StatVertical(
                              icon: Icons.visibility,
                              value: viewCount.toString(),
                              label: 'Views',
                            ),
                            Container(
                                width: 1,
                                height: 24,
                                color: Colors.white24,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 24)),
                            _StatVertical(
                              icon: Icons.favorite,
                              value: likeCount.toString(),
                              label: 'Likes',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Sources header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
              child: Row(
                children: [
                  Text(
                    'Sources',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_sources.isNotEmpty)
                    FilledButton.icon(
                      onPressed: _isForking ? null : _forkNotebook,
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        foregroundColor: theme.colorScheme.onPrimaryContainer,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                      ),
                      icon: _isForking
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                              ),
                            )
                          : const Icon(Icons.fork_right, size: 18),
                      label: Text(_isForking ? 'Forking...' : 'Fork All'),
                    ),
                ],
              ),
            ),
          ),

          // Sources list
          if (_sources.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.auto_stories_outlined,
                          size: 64, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 16),
                      Text('No sources in this notebook',
                          style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final source = _sources[index];
                    if (source is! Map<String, dynamic>) {
                      return const SizedBox.shrink(); // Skip invalid data
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _SourceCard(
                        source: source,
                        onTap: () => _showSourceDetail(source),
                      ),
                    );
                  },
                  childCount: _sources.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    ref
                        .read(discoverProvider.notifier)
                        .likeNotebook(widget.notebookId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Liked!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: Icon(
                    notebook['user_liked'] == true
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: notebook['user_liked'] == true ? Colors.red : null,
                  ),
                  label: const Text('Like'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.premiumGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: theme.colorScheme.primary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _isForking ? null : _forkNotebook,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: _isForking
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.fork_right),
                    label: Text(
                        _isForking ? 'Forking...' : 'Fork to My Notebooks'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatVertical extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _StatVertical({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: Colors.white),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _SourceCard extends StatelessWidget {
  final Map<String, dynamic> source;
  final VoidCallback onTap;

  const _SourceCard({required this.source, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final title = source['title'] ?? 'Untitled';
    final type = source['type'] ?? 'text';
    final summary = source['summary'];
    final contentPreview = source['content_preview'];

    // Safely parse date
    final createdAtStr = source['created_at'];
    DateTime? addedAt;
    if (createdAtStr != null) {
      addedAt = DateTime.tryParse(createdAtStr.toString());
    }
    addedAt ??= DateTime.now();

    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: _getTypeColor(type)
                        .withValues(alpha: isDark ? 0.2 : 0.1),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _getTypeColor(type).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    SourceIconHelper.getIconForType(type),
                    color: _getTypeColor(type),
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.toString(),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        summary?.toString() ??
                            contentPreview?.toString() ??
                            'No preview available',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              type.toString().toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.access_time,
                              size: 12,
                              color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            timeago.format(addedAt),
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'youtube':
        return const Color(0xFFFF0000); // Youtube Red
      case 'url':
        return const Color(0xFF3B82F6); // Blue 500
      case 'drive':
        return const Color(0xFF22C55E); // Green 500
      case 'text':
        return const Color(0xFFF97316); // Orange 500
      case 'audio':
        return const Color(0xFFA855F7); // Purple 500
      case 'image':
        return const Color(0xFFEC4899); // Pink 500
      case 'github':
        return const Color(0xFF1F2937); // Gray 800
      case 'code':
        return const Color(0xFF14B8A6); // Teal 500
      default:
        return Colors.grey;
    }
  }
}

class _SourceDetailSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> source;
  final ScrollController scrollController;

  const _SourceDetailSheet({
    required this.source,
    required this.scrollController,
  });

  @override
  ConsumerState<_SourceDetailSheet> createState() => _SourceDetailSheetState();
}

class _SourceDetailSheetState extends ConsumerState<_SourceDetailSheet> {
  bool _isLoading = true;
  String? _fullContent;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFullContent();
  }

  Future<void> _loadFullContent() async {
    if (!mounted) return;

    // If we already have full content in the source map, use it
    if (widget.source['content'] != null &&
        widget.source['content'].toString().length > 500) {
      setState(() {
        _fullContent = widget.source['content'];
        _isLoading = false;
      });
      return;
    }

    try {
      final api = ref.read(apiServiceProvider);
      final id = widget.source['id'];

      final response = await api.get('/social-sharing/public/sources/$id');

      if (!mounted) return;

      if (response['success'] == true && response['source'] != null) {
        setState(() {
          _fullContent = response['source']['content'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load full content';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.source['title'] ?? 'Untitled';
    final type = widget.source['type'] ?? 'text';
    final summary = widget.source['summary'];
    final contentPreview = widget.source['content_preview'];

    // Use full content if loaded, otherwise fallback to preview
    final displayContent =
        _fullContent ?? widget.source['content'] ?? contentPreview;

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                    child: Text(
                  title.toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                )),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(SourceIconHelper.getIconForType(type),
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    type.toString().toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              )),
          const Divider(height: 32),
          // Content
          Expanded(
            child: ListView(
              controller: widget.scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              children: [
                if (summary != null && summary.toString().isNotEmpty) ...[
                  Text('Summary',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      summary.toString(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurface,
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                // Display error if present
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            size: 16, color: theme.colorScheme.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Text(_isLoading ? 'Content Preview' : 'Content',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    if (_isLoading) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 4),
                      Text('Loading full content...',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic,
                          )),
                    ]
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Text(
                    displayContent?.toString() ?? 'No content available',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
