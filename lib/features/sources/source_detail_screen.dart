import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/media/media_service.dart';
import '../../core/api/api_service.dart';
import 'source.dart';
import 'source_provider.dart';
import 'source_chat_sheet.dart';
import 'source_conversation_provider.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../features/fact_check/fact_check_service.dart';
import '../../theme/app_theme.dart';
import 'dart:ui'; // For glass effects

class SourceDetailScreen extends ConsumerWidget {
  const SourceDetailScreen(
      {super.key,
      required this.sourceId,
      this.highlightChunkId,
      this.highlightSnippet});
  final String sourceId;
  final String? highlightChunkId;
  final String? highlightSnippet;

  void _showFactCheckSheet(
      BuildContext context, WidgetRef ref, String content) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FactCheckSheet(content: content),
    );
  }

  void _showAgentChatSheet(
      BuildContext context, Source source, String? agentName) {
    showSourceChatSheet(
      context,
      source: source,
      agentName: agentName,
    );
  }

  Future<void> _deleteSource(
      BuildContext context, WidgetRef ref, Source source) async {
    final isChat = source.type == 'agent_chat';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isChat ? 'Delete chat?' : 'Delete source?'),
        content: Text(
          isChat
              ? 'This will delete the chat thread and all of its messages. This cannot be undone.'
              : 'This will delete "${source.title}" and its conversation. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(sourceProvider.notifier).deleteSource(source.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(isChat ? 'Chat deleted' : 'Source deleted')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourceProvider);
    final source = sources.firstWhere((s) => s.id == sourceId,
        orElse: () => Source(
            id: sourceId,
            notebookId: '',
            title: 'Unknown',
            type: 'url',
            addedAt: DateTime.now(),
            content: ''));
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    // Check if this source has an agent session
    final hasAgentAsync = ref.watch(sourceHasAgentProvider(sourceId));
    final hasAgent = hasAgentAsync.valueOrNull ?? false;
    final effectiveHasAgent = source.hasAgentSession || hasAgent;

    // Get agent name from source metadata if available
    final String? agentName = source.agentName;

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        title: Text(source.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Chat with Agent button - only show when we can resolve an agent session
          // Requirements: 3.1
          if (effectiveHasAgent)
            IconButton(
              icon: const Icon(LucideIcons.terminal),
              tooltip: 'Chat with Agent',
              onPressed: () => _showAgentChatSheet(context, source, agentName),
            ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Verify Facts',
            onPressed: () => _showFactCheckSheet(context, ref, source.content),
          ),
          IconButton(
            icon: const Icon(LucideIcons.trash2),
            tooltip: source.type == 'agent_chat' ? 'Delete chat' : 'Delete source',
            onPressed: () => _deleteSource(context, ref, source),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  source.type == 'youtube'
                      ? Icons.play_circle_outline
                      : source.type == 'code'
                          ? LucideIcons.code2
                          : Icons.article_outlined,
                  size: 16,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${source.type.toUpperCase()} • Added on ${source.addedAt.day}/${source.addedAt.month}/${source.addedAt.year}',
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                // Agent badge for code sources
                if (effectiveHasAgent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.bot,
                          size: 12,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          source.agentName ?? 'Agent',
                          style: text.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Agent context section - show conversation context for agent-created sources
          if (source.hasConversationContext || source.hasAgentSession)
            _AgentContextSection(source: source),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              child: _DetailBody(
                  key: ValueKey(
                      '${source.id}:${source.content.hashCode}:${source.metadata.hashCode}'),
                  source: source,
                  highlightChunkId: highlightChunkId,
                  highlightSnippet: highlightSnippet),
            ),
          ),
        ],
      ),
      // Floating action button for chat with agent
      floatingActionButton: effectiveHasAgent
          ? FloatingActionButton.extended(
              onPressed: () => _showAgentChatSheet(context, source, agentName),
              icon: const Icon(LucideIcons.terminal),
              label: const Text('Chat with Agent'),
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            )
          : null,
    );
  }
}

enum _SourceViewMode { preview, code }

class _ChunkItem {
  _ChunkItem({required this.id, required this.text, required this.index});
  final String id;
  final String text;
  final int index;
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody(
      {super.key,
      required this.source,
      this.highlightChunkId,
      this.highlightSnippet});
  final Source source;
  final String? highlightChunkId;
  final String? highlightSnippet;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  static const String _mobilePreviewUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  final ScrollController _scroll = ScrollController();
  List<_ChunkItem> _chunks = [];
  int _highlightIndex = -1;
  WebViewController? _htmlPreviewController;
  String? _htmlPreviewDocument;
  Uri? _previewUrl;
  int _htmlPreviewLoadToken = 0;
  _SourceViewMode _viewMode = _SourceViewMode.code;
  bool _isHtmlPreviewLoading = false;
  bool _htmlPreviewError = false;

  @override
  void initState() {
    super.initState();
    _initializeHtmlPreview();
    _loadChunks();
  }

  @override
  void didUpdateWidget(covariant _DetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);

    final sourceChanged = oldWidget.source.id != widget.source.id ||
        oldWidget.source.content != widget.source.content ||
        oldWidget.source.type != widget.source.type ||
        oldWidget.source.metadata.toString() != widget.source.metadata.toString();

    final highlightChanged =
        oldWidget.highlightChunkId != widget.highlightChunkId ||
            oldWidget.highlightSnippet != widget.highlightSnippet;

    if (sourceChanged) {
      _initializeHtmlPreview();
      _loadChunks();
    } else if (highlightChanged) {
      setState(() {
        _highlightIndex = _findHighlightIndex();
      });
    }
  }

  void _initializeHtmlPreview() {
    final previewToken = ++_htmlPreviewLoadToken;
    _previewUrl = null;
    _htmlPreviewDocument = widget.source.renderableHtmlDocument;
    final sourceUrl = widget.source.sourceUrl;
    if ((sourceUrl != null && sourceUrl.isNotEmpty) && widget.source.type == 'url') {
      _previewUrl = Uri.tryParse(sourceUrl);
    }

    final hasHtmlDocument =
        _htmlPreviewDocument != null && _htmlPreviewDocument!.isNotEmpty;
    final hasPreviewUrl = _previewUrl != null;
    if (!hasHtmlDocument && !hasPreviewUrl) {
      _viewMode = _SourceViewMode.code;
      _htmlPreviewController = null;
      _isHtmlPreviewLoading = false;
      _htmlPreviewError = false;
      return;
    }

    if (kIsWeb) {
      _viewMode = _SourceViewMode.code;
      _htmlPreviewController = null;
      _isHtmlPreviewLoading = false;
      _htmlPreviewError = false;
      return;
    }

    _viewMode = _SourceViewMode.preview;
    _isHtmlPreviewLoading = true;
    _htmlPreviewError = false;
    _htmlPreviewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setUserAgent(_mobilePreviewUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) async {
            if (previewToken != _htmlPreviewLoadToken) return;
            await _normalizePreviewLayout();
            if (!mounted) return;
            if (previewToken != _htmlPreviewLoadToken) return;
            setState(() => _isHtmlPreviewLoading = false);
          },
          onWebResourceError: (_) {
            if (!mounted) return;
            if (previewToken != _htmlPreviewLoadToken) return;
            setState(() {
              _htmlPreviewError = true;
              _isHtmlPreviewLoading = false;
            });
          },
        ),
      );

    if (hasPreviewUrl) {
      _htmlPreviewController!.loadRequest(_previewUrl!);
    } else {
      _htmlPreviewController!.loadHtmlString(_htmlPreviewDocument!);
    }
  }

  Future<void> _normalizePreviewLayout() async {
    final controller = _htmlPreviewController;
    if (controller == null) return;

    try {
      await controller.runJavaScript('''
(() => {
  const head = document.head || document.getElementsByTagName('head')[0];
  if (head && !document.querySelector('meta[name="viewport"]')) {
    const meta = document.createElement('meta');
    meta.name = 'viewport';
    meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no';
    head.appendChild(meta);
  }

  let style = document.getElementById('noteclaw-preview-runtime-style');
  if (!style) {
    style = document.createElement('style');
    style.id = 'noteclaw-preview-runtime-style';
    style.textContent = `
      html, body, *, *::before, *::after {
        width: 100% !important;
        max-width: 100% !important;
        margin: 0 !important;
        padding: 0 !important;
        overflow-x: hidden !important;
        writing-mode: horizontal-tb !important;
        text-orientation: mixed !important;
      }

      body {
        min-height: 100vh;
        word-break: normal !important;
        overflow-wrap: anywhere !important;
      }

      img, video, canvas, svg, iframe, table, pre, code {
        max-width: 100% !important;
      }

      * {
        max-inline-size: 100%;
      }

      body { touch-action: manipulation; }
    `;
    if (head) {
      head.appendChild(style);
    }
  }
})();
''');
    } catch (_) {
      // Best-effort normalization only.
    }
  }

  Future<void> _loadChunks() async {
    final api = ref.read(apiServiceProvider);
    final chunks = await api.getChunksForSource(widget.source.id);

    if (chunks.isEmpty && widget.source.content.isNotEmpty) {
      final items = [
        _ChunkItem(
          id: 'full_content',
          text: widget.source.content,
          index: 0,
        )
      ];
      setState(() {
        _chunks = items;
        _highlightIndex = _findHighlightIndex();
      });
      return;
    }

    final items = chunks
        .map((e) => _ChunkItem(
              id: e['id']?.toString() ?? '',
              text: (e['content_text'] ?? '') as String,
              index: e['chunk_index'] is int
                  ? e['chunk_index'] as int
                  : int.tryParse('${e['chunk_index']}') ?? 0,
            ))
        .toList();
    setState(() {
      _chunks = items;
      _highlightIndex = _findHighlightIndex();
    });
    if (_highlightIndex >= 0) {
      await Future.delayed(const Duration(milliseconds: 50));
      _scroll.animateTo(
        _highlightIndex * 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  int _findHighlightIndex() {
    if (widget.highlightChunkId != null) {
      final i = _chunks.indexWhere((c) => c.id == widget.highlightChunkId);
      if (i >= 0) return i;
    }
    if (widget.highlightSnippet != null) {
      final i =
          _chunks.indexWhere((c) => c.text.contains(widget.highlightSnippet!));
      if (i >= 0) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isMediaSource =
        widget.source.type == 'image' || widget.source.type == 'video';
    final supportsHtmlPreview =
        (_htmlPreviewDocument != null && _htmlPreviewDocument!.isNotEmpty) ||
        _previewUrl != null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isMediaSource
            ? _buildMediaSourceBody(context)
            : supportsHtmlPreview
                ? _buildHtmlCapableSourceBody(context)
                : _buildStandardSourceBody(context),
      ),
    );
  }

  Widget _buildMediaSourceBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: _MediaViewer(source: widget.source),
        ),
        if (widget.highlightSnippet != null &&
            widget.highlightSnippet!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildMatchesPanel(context),
          ),
        const SizedBox(height: 8),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: _buildChunkList(context),
          ),
        ),
      ],
    );
  }

  Widget _buildStandardSourceBody(BuildContext context) {
    return Column(
      children: [
        if (widget.source.isHtmlSource)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildHtmlAsTextNotice(context),
          ),
        if (widget.highlightSnippet != null && widget.highlightSnippet!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: _buildMatchesPanel(context),
          ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildChunkList(context),
          ),
        ),
      ],
    );
  }

  Widget _buildHtmlCapableSourceBody(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: _buildHtmlSourceToolbar(context),
        ),
        const SizedBox(height: 12),
        if (_viewMode == _SourceViewMode.code &&
            widget.highlightSnippet != null &&
            widget.highlightSnippet!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildMatchesPanel(context),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _viewMode == _SourceViewMode.preview
                ? _buildHtmlPreviewPanel(context)
                : _buildChunkList(context),
          ),
        ),
      ],
    );
  }

  Widget _buildHtmlSourceToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    const previewAvailable = !kIsWeb;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.web_asset_outlined,
                  size: 18,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Website Source',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      previewAvailable
                          ? 'Preview and code'
                          : 'Code view only on this platform',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (previewAvailable)
                ChoiceChip(
                  label: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.smartphone, size: 16),
                      SizedBox(width: 6),
                      Text('Preview'),
                    ],
                  ),
                  selected: _viewMode == _SourceViewMode.preview,
                  onSelected: (selected) {
                    if (!selected) return;
                    setState(() => _viewMode = _SourceViewMode.preview);
                  },
                ),
              ChoiceChip(
                label: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.code, size: 16),
                    SizedBox(width: 6),
                    Text('Code'),
                  ],
                ),
                selected: _viewMode == _SourceViewMode.code,
                onSelected: (selected) {
                  if (!selected) return;
                  setState(() => _viewMode = _SourceViewMode.code);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHtmlPreviewPanel(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_htmlPreviewDocument == null || _htmlPreviewDocument!.isEmpty) {
      if (_previewUrl != null) {
        return _buildLiveWebsitePreview(context, scheme);
      }
      return _buildHtmlPreviewUnavailableCard(
        context,
        message: 'This source does not contain a renderable HTML document yet.',
      );
    }

    if (kIsWeb || _htmlPreviewController == null) {
      return _buildHtmlPreviewUnavailableCard(
        context,
        message:
            'HTML preview is only available on app builds with WebView support. Switch to Code to inspect the source.',
      );
    }

    if (_htmlPreviewError) {
      return _buildHtmlPreviewUnavailableCard(
        context,
        message:
            'The preview could not be rendered, but the saved code is still available.',
        actionLabel: 'Retry Preview',
        onAction: () {
          setState(() {
            _htmlPreviewError = false;
            _isHtmlPreviewLoading = true;
          });
          if (_previewUrl != null) {
            _htmlPreviewController!.loadRequest(_previewUrl!);
          } else if (_htmlPreviewDocument != null) {
            _htmlPreviewController!.loadHtmlString(_htmlPreviewDocument!);
          }
        },
      );
    }

    Widget content = Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(controller: _htmlPreviewController!),
        ),
        if (_isHtmlPreviewLoading)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface.withValues(alpha: 0.86),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 375.0;
        final previewWidth = availableWidth.clamp(240.0, 430.0).toDouble();

        return Center(
          child: Container(
            width: previewWidth,
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(previewWidth < 300 ? 24 : 28),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.3),
                width: previewWidth < 300 ? 5 : 8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(previewWidth < 300 ? 18 : 24),
              child: content,
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveWebsitePreview(BuildContext context, ColorScheme scheme) {
    if (_previewUrl == null) {
      return _buildHtmlPreviewUnavailableCard(
        context,
        message: 'No website URL is available for preview.',
      );
    }

    Widget content = Stack(
      children: [
        Positioned.fill(
          child: WebViewWidget(controller: _htmlPreviewController!),
        ),
        if (_isHtmlPreviewLoading)
          Positioned.fill(
            child: ColoredBox(
              color: scheme.surface.withValues(alpha: 0.86),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: content,
      ),
    );
  }

  Widget _buildHtmlPreviewUnavailableCard(
    BuildContext context, {
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.web_asset_off_outlined,
            size: 34,
            color: scheme.outline,
          ),
          const SizedBox(height: 14),
          Text(
            'Preview Unavailable',
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onAction,
              child: Text(actionLabel),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHtmlAsTextNotice(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: scheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This source is marked as HTML, but the saved content is extracted text rather than a full HTML document. Showing the source in a readable code/text view instead of the broken preview.',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchesPanel(BuildContext context) {
    final snippet = widget.highlightSnippet;
    if (snippet == null || snippet.isEmpty || _chunks.isEmpty) {
      return const SizedBox.shrink();
    }
    final matches = <int>[];
    for (var i = 0; i < _chunks.length; i++) {
      if (_chunks[i].text.contains(snippet)) matches.add(i);
    }
    if (matches.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(
            color:
                Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Matches (${matches.length})',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: matches.map((i) {
              final preview = _chunks[i].text;
              final label = preview.length > 36
                  ? '${preview.substring(0, 36)}…'
                  : preview;
              return ActionChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                onPressed: () {
                  setState(() => _highlightIndex = i);
                  _scroll.animateTo(i * 100,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildChunkList(BuildContext context) {
    if (_chunks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.description_outlined,
                  size: 48, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(
                'No Text Extracted',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.source.content.isEmpty
                    ? 'The content for this source appears to be empty. This typically happens if the file or URL failed to process on the server.'
                    : 'Text extraction returned no results.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
              ),
              if (widget.source.content.isEmpty) ...[
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    // Refresh parent provider
                    await ref.read(sourceProvider.notifier).loadSources();
                    // Refresh chunks
                    _loadChunks();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Data'),
                ),
                const SizedBox(height: 12),
                Text(
                  'If refreshing doesn\'t help, please delete and re-add this source.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // For single chunk (full content), display as formatted text
    if (_chunks.length == 1) {
      final c = _chunks[0];
      return SingleChildScrollView(
        controller: _scroll,
        child: _buildFormattedContent(context, c.text, scheme, textTheme),
      );
    }

    // For multiple chunks, display as cards
    return ListView.builder(
      controller: _scroll,
      itemCount: _chunks.length,
      itemBuilder: (context, i) {
        final c = _chunks[i];
        final highlight = i == _highlightIndex;
        final snippet = widget.highlightSnippet;
        InlineSpan contentSpan;
        if (highlight && snippet != null && snippet.isNotEmpty) {
          final idx = c.text.indexOf(snippet);
          if (idx >= 0) {
            final before = c.text.substring(0, idx);
            final middle = c.text.substring(idx, idx + snippet.length);
            final after = c.text.substring(idx + snippet.length);
            contentSpan = TextSpan(children: [
              TextSpan(text: before),
              TextSpan(
                text: middle,
                style: TextStyle(
                    backgroundColor: scheme.primary.withValues(alpha: 0.15)),
              ),
              TextSpan(text: after),
            ]);
          } else {
            contentSpan = TextSpan(text: c.text);
          }
        } else {
          contentSpan = TextSpan(text: c.text);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: highlight
                ? scheme.primaryContainer.withValues(alpha: 0.3)
                : scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlight
                  ? scheme.primary.withValues(alpha: 0.3)
                  : scheme.outline.withValues(alpha: 0.1),
              width: highlight ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Chunk header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(11)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.format_quote,
                      size: 16,
                      color: scheme.primary.withValues(alpha: 0.7),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Section ${i + 1}',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${c.text.split(' ').length} words',
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: widget.source.type == 'report'
                    ? MarkdownBody(
                        data: c.text,
                        selectable: true,
                        styleSheet: _buildMarkdownStyleSheet(context),
                      )
                    : widget.source.type == 'code'
                        ? _buildCodeBlockText(
                            context,
                            contentSpan,
                            isChunkCard: true,
                          )
                    : Text.rich(
                        contentSpan,
                        style: textTheme.bodyLarge?.copyWith(
                          height: 1.7,
                          color: scheme.onSurface.withValues(alpha: 0.85),
                          letterSpacing: 0.2,
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFormattedContent(
    BuildContext context,
    String text,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    if (widget.source.type == 'code') {
      return _buildCodeBlockContainer(context, text);
    }

    // Check if content looks like markdown
    final hasMarkdown = text.contains('# ') ||
        text.contains('## ') ||
        text.contains('**') ||
        text.contains('- ') ||
        text.contains('```') ||
        widget.source.type == 'report';

    if (hasMarkdown) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.1),
          ),
        ),
        child: MarkdownBody(
          data: text,
          selectable: true,
          styleSheet: _buildMarkdownStyleSheet(context),
        ),
      );
    }

    // For plain text, format it nicely with paragraphs
    final paragraphs = text.split(RegExp(r'\n\n+'));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: paragraphs.map((paragraph) {
          final trimmed = paragraph.trim();
          if (trimmed.isEmpty) return const SizedBox(height: 16);

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: SelectableText(
              trimmed,
              style: textTheme.bodyLarge?.copyWith(
                height: 1.8,
                color: scheme.onSurface.withValues(alpha: 0.85),
                letterSpacing: 0.3,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCodeBlockContainer(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SelectableText(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.55,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCodeBlockText(
    BuildContext context,
    InlineSpan contentSpan, {
    bool isChunkCard = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: isChunkCard ? EdgeInsets.zero : const EdgeInsets.all(16),
      decoration: isChunkCard
          ? null
          : BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: SelectableText.rich(
                TextSpan(children: [contentSpan]),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      height: 1.55,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
              ),
            ),
          );
        },
      ),
    );
  }

  MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: textTheme.bodyLarge?.copyWith(
        height: 1.7,
        color: scheme.onSurface.withValues(alpha: 0.85),
        letterSpacing: 0.2,
      ),
      h1: textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.primary,
        height: 1.4,
      ),
      h2: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
        height: 1.4,
      ),
      h3: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
        height: 1.4,
      ),
      h4: textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurface.withValues(alpha: 0.9),
      ),
      blockquote: textTheme.bodyLarge?.copyWith(
        color: scheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
        height: 1.6,
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: scheme.primary.withValues(alpha: 0.5),
            width: 4,
          ),
        ),
        color: scheme.primaryContainer.withValues(alpha: 0.1),
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      code: textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: scheme.surfaceContainerHighest,
        color: scheme.primary,
      ),
      codeblockDecoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      codeblockPadding: const EdgeInsets.all(16),
      listBullet: textTheme.bodyLarge?.copyWith(
        color: scheme.primary,
      ),
      listIndent: 24,
      blockSpacing: 16,
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

class _MediaViewer extends ConsumerWidget {
  const _MediaViewer({required this.source});
  final Source source;

  @override
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.read(mediaServiceProvider);
    return FutureBuilder<Uint8List?>(
      future: service.getMediaBytes(source.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
              height: 200, child: Center(child: CircularProgressIndicator()));
        }
        final bytes = snap.data;
        if (bytes == null) return const Text('Media not found');

        if (source.type == 'image') {
          return Center(child: Image.memory(bytes));
        } else if (source.type == 'video') {
          // Video from bytes is harder with video_player, usually needs a file.
          // For now, show placeholder or unsupported message as video_player doesn't support memory easily without writing to file.
          return const Center(
              child: Text('Video playback from DB not fully supported yet'));
        }
        return SingleChildScrollView(
            child: Text('Unsupported media type: ${source.type}'));
      },
    );
  }
}

class _VideoPlayerView extends StatefulWidget {
  const _VideoPlayerView({required this.url});
  final String url;

  @override
  State<_VideoPlayerView> createState() => _VideoPlayerViewState();
}

class _VideoPlayerViewState extends State<_VideoPlayerView> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) {
          setState(() => _initialized = true);
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        AspectRatio(
          aspectRatio: _controller.value.aspectRatio,
          child: VideoPlayer(_controller),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
            ),
          ],
        )
      ],
    );
  }
}

class _FactCheckSheet extends ConsumerStatefulWidget {
  const _FactCheckSheet({required this.content});
  final String content;

  @override
  ConsumerState<_FactCheckSheet> createState() => _FactCheckSheetState();
}

class _FactCheckSheetState extends ConsumerState<_FactCheckSheet> {
  bool _isLoading = true;
  List<FactCheckResult> _results = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      final results = await ref
          .read(factCheckServiceProvider)
          .verifyContent(widget.content);
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.outline.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.fact_check,
                        color: scheme.onPrimaryContainer, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Fact Check Analysis',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Powered by AI verification',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              if (_isLoading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Expanded(
                    child: Center(
                        child: Text('Error: $_error',
                            style: TextStyle(color: scheme.error))))
              else if (_results.isEmpty)
                Expanded(
                    child: Center(
                        child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 48, color: Colors.green.withValues(alpha: 0.5)),
                    const SizedBox(height: 16),
                    const Text('No controversial claims identified',
                        style: TextStyle(fontWeight: FontWeight.w500)),
                  ],
                )))
              else
                Expanded(
                  child: ListView.separated(
                    itemCount: _results.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      final item = _results[index];
                      Color statusColor;
                      IconData statusIcon;
                      Color bgStatusColor;

                      switch (item.verdict.toLowerCase()) {
                        case 'true':
                          statusColor = Colors.green;
                          bgStatusColor = Colors.green;
                          statusIcon = Icons.check_circle;
                          break;
                        case 'false':
                          statusColor = Colors.red;
                          bgStatusColor = Colors.red;
                          statusIcon = Icons.cancel;
                          break;
                        case 'misleading':
                          statusColor = Colors.orange;
                          bgStatusColor = Colors.orange;
                          statusIcon = Icons.warning;
                          break;
                        default:
                          statusColor = Colors.grey;
                          bgStatusColor = Colors.grey;
                          statusIcon = Icons.help;
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: scheme.outline.withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: bgStatusColor.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color:
                                        scheme.outline.withValues(alpha: 0.05),
                                  ),
                                ),
                                color: bgStatusColor.withValues(alpha: 0.05),
                              ),
                              child: Row(
                                children: [
                                  Icon(statusIcon,
                                      color: statusColor, size: 16),
                                  const SizedBox(width: 8),
                                  Text(item.verdict.toUpperCase(),
                                      style: TextStyle(
                                          color: statusColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          letterSpacing: 1)),
                                  const Spacer(),
                                  Text(
                                    '${(item.confidence * 100).toInt()}% CONFIDENCE',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.5),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.claim,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      height: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    item.explanation,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: scheme.onSurface
                                              .withValues(alpha: 0.8),
                                          height: 1.5,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget to display agent context and metadata for agent-created sources
class _AgentContextSection extends StatelessWidget {
  const _AgentContextSection({required this.source});
  final Source source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.3),
            scheme.secondaryContainer.withValues(alpha: 0.2),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.bot,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Created by ${source.agentName ?? 'Coding Agent'}',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (source.description != null)
                        Text(
                          source.description!,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                // Verification badge
                if (source.isVerified)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.verified,
                          size: 14,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          source.verificationScore != null
                              ? '${source.verificationScore}%'
                              : 'Verified',
                          style: textTheme.labelSmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Conversation context
          if (source.hasConversationContext)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        LucideIcons.messageSquare,
                        size: 14,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Original Context',
                        style: textTheme.labelMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: scheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Text(
                      source.conversationContext!,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.85),
                        height: 1.5,
                      ),
                      maxLines: 5,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
