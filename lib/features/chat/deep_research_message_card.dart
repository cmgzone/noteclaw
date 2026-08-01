import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui/widgets/app_network_image.dart';
import 'message.dart';

class DeepResearchMessageCard extends StatefulWidget {
  const DeepResearchMessageCard({
    super.key,
    required this.message,
    this.onSpeak,
  });

  final Message message;
  final VoidCallback? onSpeak;

  @override
  State<DeepResearchMessageCard> createState() =>
      _DeepResearchMessageCardState();
}

class _DeepResearchMessageCardState extends State<DeepResearchMessageCard> {
  static const _collapsedCharacters = 1400;
  bool _expanded = false;

  bool get _isError {
    final value = widget.message.text.toLowerCase();
    return value.contains('deep research error') || value.startsWith('error:');
  }

  bool get _isRunning {
    if (_isError) return false;
    final status = widget.message.webBrowsingStatus?.toLowerCase();
    if (status != null && status.isNotEmpty) {
      return !status.contains('complete') && !status.contains('failed');
    }
    final text = widget.message.text.toLowerCase().trim();
    return text.startsWith('starting deep research') ||
        text.startsWith('reconnecting to background research') ||
        text.contains('research queued on the server') ||
        text.contains('research is running on the server');
  }

  String get _cleanStatus {
    final raw = widget.message.webBrowsingStatus?.trim().isNotEmpty == true
        ? widget.message.webBrowsingStatus!.trim()
        : widget.message.text.trim();
    return raw.replaceFirst(RegExp(r'^>\s*'), '').trim();
  }

  String get _report {
    final text = widget.message.text.trim();
    const marker = '**Deep Research Error**';
    final markerIndex = text.indexOf(marker);
    if (markerIndex >= 0) {
      return text.substring(markerIndex + marker.length).trim();
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _isError
        ? scheme.error
        : _isRunning
            ? scheme.tertiary
            : scheme.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.16),
                  accent.withValues(alpha: 0.035),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accent.withValues(alpha: 0.22)),
                  ),
                  child: Icon(
                    _isError
                        ? LucideIcons.alertTriangle
                        : _isRunning
                            ? LucideIcons.search
                            : LucideIcons.fileText,
                    color: accent,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'DEEP RESEARCH',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: accent,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isError
                            ? 'Research stopped'
                            : _isRunning
                                ? 'Working in the background'
                                : 'Research report ready',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurface,
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
                _StatusPill(
                  color: accent,
                  label: _isError
                      ? 'FAILED'
                      : _isRunning
                          ? 'LIVE'
                          : 'COMPLETE',
                  showDot: _isRunning,
                ),
              ],
            ),
          ),
          if (_isRunning) ...[
            LinearProgressIndicator(
              minHeight: 3,
              color: accent,
              backgroundColor: accent.withValues(alpha: 0.08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _cleanStatus,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 18, 18),
              child: Text(
                'You can leave the app. This job will continue on the server and reconnect when you return.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
              ),
            ),
          ] else ...[
            if (!_isError) _buildReport(context, accent),
            if (_isError)
              Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  _report,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                        height: 1.45,
                      ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildReport(BuildContext context, Color accent) {
    final scheme = Theme.of(context).colorScheme;
    final report = _report;
    final canCollapse = report.length > _collapsedCharacters;
    final visibleReport = canCollapse && !_expanded
        ? '${report.substring(0, _collapsedCharacters).trimRight()}\n\n…'
        : report;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                icon: LucideIcons.link2,
                label: '${widget.message.webBrowsingSources.length} sources',
                color: accent,
              ),
              if (widget.message.webBrowsingScreenshots.isNotEmpty)
                _MetricChip(
                  icon: LucideIcons.image,
                  label:
                      '${widget.message.webBrowsingScreenshots.length} visuals',
                  color: accent,
                ),
              _MetricChip(
                icon: LucideIcons.clock,
                label: _formatTime(widget.message.timestamp),
                color: accent,
              ),
            ],
          ),
          if (widget.message.webBrowsingSources.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildSources(context),
          ],
          if (widget.message.webBrowsingScreenshots.isNotEmpty) ...[
            const SizedBox(height: 14),
            _buildVisuals(context),
          ],
          const SizedBox(height: 18),
          MarkdownBody(
            data: visibleReport,
            selectable: true,
            styleSheet: MarkdownStyleSheet(
              p: TextStyle(color: scheme.onSurface, fontSize: 15, height: 1.55),
              h1: TextStyle(
                color: scheme.onSurface,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              h2: TextStyle(
                color: scheme.onSurface,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
              h3: TextStyle(
                color: scheme.onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
              strong: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
              blockquoteDecoration: BoxDecoration(
                color: accent.withValues(alpha: 0.07),
                border: Border(left: BorderSide(color: accent, width: 3)),
                borderRadius: BorderRadius.circular(8),
              ),
              blockquotePadding: const EdgeInsets.all(12),
              codeblockDecoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              listBullet: TextStyle(color: accent),
            ),
            onTapLink: (_, href, __) => _openUrl(href),
          ),
          if (canCollapse) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(
                _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
              ),
              label: Text(_expanded ? 'Show less' : 'Read full report'),
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: report));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Research report copied')),
                  );
                },
                icon: const Icon(LucideIcons.copy, size: 16),
                label: const Text('Copy'),
              ),
              if (widget.onSpeak != null) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  onPressed: widget.onSpeak,
                  icon: const Icon(LucideIcons.volume2, size: 18),
                  tooltip: 'Read report aloud',
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSources(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sources = widget.message.webBrowsingSources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SOURCES',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...sources.take(5).map((url) {
              final uri = Uri.tryParse(url);
              final domain = uri?.host.replaceFirst('www.', '') ?? url;
              return ActionChip(
                onPressed: () => _openUrl(url),
                avatar: const Icon(LucideIcons.externalLink, size: 13),
                label: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 145),
                  child: Text(
                    domain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                visualDensity: VisualDensity.compact,
              );
            }),
            if (sources.length > 5)
              Chip(
                label: Text('+${sources.length - 5} more'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisuals(BuildContext context) {
    final visuals = widget.message.webBrowsingScreenshots.take(4).toList();
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visuals.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final url = visuals[index];
          return InkWell(
            onTap: () => _showImage(context, url),
            borderRadius: BorderRadius.circular(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AppNetworkImage(
                imageUrl: url,
                width: 126,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openUrl(String? value) async {
    final uri = Uri.tryParse(value ?? '');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.84,
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AppNetworkImage(
                      imageUrl: url,
                      width: MediaQuery.sizeOf(context).width * 0.84,
                      height: MediaQuery.sizeOf(context).height * 0.68,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: IconButton.filledTonal(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final difference = DateTime.now().difference(time);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'just now';
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.color,
    required this.label,
    required this.showDot,
  });

  final Color color;
  final String label;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
