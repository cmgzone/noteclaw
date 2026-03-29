import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'code_review_provider.dart';

class CodeReviewDetailView extends StatelessWidget {
  const CodeReviewDetailView({
    super.key,
    required this.review,
  });

  final CodeReview review;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sourceColor = _sourceColor(review.source, theme);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.surfaceContainerHighest,
                scheme.surface,
              ],
            ),
            border: Border.all(
              color: sourceColor.withValues(alpha: 0.22),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildScoreIndicator(review.score, theme, size: 92),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildMetaChip(
                                label: _sourceLabel(review.source),
                                icon: review.isMcp
                                    ? Icons.memory_rounded
                                    : Icons.rate_review_rounded,
                                color: sourceColor,
                                theme: theme,
                              ),
                              _buildMetaChip(
                                label: _reviewTypeLabel(
                                  review.reviewType,
                                  toolName: review.toolName,
                                ),
                                icon: _reviewTypeIcon(
                                  review.reviewType,
                                  toolName: review.toolName,
                                ),
                                color: scheme.primary,
                                theme: theme,
                              ),
                              _buildMetaChip(
                                label: review.language.toUpperCase(),
                                icon: Icons.code_rounded,
                                color: scheme.secondary,
                                theme: theme,
                              ),
                              if (review.isContextAware)
                                _buildMetaChip(
                                  label: review.relatedFilesUsed?.isNotEmpty ==
                                          true
                                      ? '${review.relatedFilesUsed!.length} related files'
                                      : 'Context-aware',
                                  icon: Icons.auto_awesome_rounded,
                                  color: scheme.tertiary,
                                  theme: theme,
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _reviewHeadline(
                              review.reviewType,
                              toolName: review.toolName,
                            ),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            review.summary,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Saved ${_formatDate(review.createdAt)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildMetricCard(
                      label: 'Errors',
                      value: review.errorCount,
                      icon: Icons.error_outline_rounded,
                      color: Colors.red,
                      theme: theme,
                    ),
                    _buildMetricCard(
                      label: 'Warnings',
                      value: review.warningCount,
                      icon: Icons.warning_amber_rounded,
                      color: Colors.orange,
                      theme: theme,
                    ),
                    _buildMetricCard(
                      label: 'Info',
                      value: review.infoCount,
                      icon: Icons.info_outline_rounded,
                      color: Colors.blue,
                      theme: theme,
                    ),
                    _buildMetricCard(
                      label: 'Suggestions',
                      value: review.suggestions.length,
                      icon: Icons.lightbulb_outline_rounded,
                      color: Colors.amber.shade800,
                      theme: theme,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (review.relatedFilesUsed?.isNotEmpty ?? false) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_open, size: 16, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Repository context used in this review',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: review.relatedFilesUsed!.map((file) {
                      return Tooltip(
                        message: file,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surface.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: scheme.outlineVariant,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.insert_drive_file, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                file.split('/').last,
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (review.issues.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildSectionHeader(
            title: 'Issues Found',
            subtitle:
                'Each issue includes severity, category, and suggested next action.',
            theme: theme,
          ),
          const SizedBox(height: 10),
          ...review.issues
              .map((issue) => _buildIssueCard(context, issue, theme)),
        ],
        if (review.suggestions.isNotEmpty) ...[
          const SizedBox(height: 20),
          _buildSectionHeader(
            title: 'Recommended Improvements',
            subtitle: 'Fast follow-ups you can apply after this review pass.',
            theme: theme,
          ),
          const SizedBox(height: 10),
          ...review.suggestions.map(
            (suggestion) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.lightbulb_outline_rounded,
                      size: 18,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildScoreIndicator(
    int score,
    ThemeData theme, {
    double size = 80,
  }) {
    Color color;
    if (score >= 90) {
      color = Colors.green;
    } else if (score >= 70) {
      color = Colors.lightGreen;
    } else if (score >= 50) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: score / 100,
            strokeWidth: size * 0.1,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '$score',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: size * 0.28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard(
    BuildContext context,
    CodeReviewIssue issue,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    Color severityColor;
    IconData severityIcon;
    switch (issue.severity) {
      case 'error':
        severityColor = Colors.red;
        severityIcon = Icons.error;
        break;
      case 'warning':
        severityColor = Colors.orange;
        severityIcon = Icons.warning;
        break;
      default:
        severityColor = Colors.blue;
        severityIcon = Icons.info;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: severityColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: severityColor.withValues(alpha: 0.2),
        ),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: severityColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(severityIcon, color: severityColor),
          ),
          title: Text(
            issue.message,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaChip(
                  label: issue.severity.toUpperCase(),
                  icon: severityIcon,
                  color: severityColor,
                  theme: theme,
                  compact: true,
                ),
                _buildMetaChip(
                  label: _titleCase(issue.category),
                  icon: Icons.sell_outlined,
                  color: scheme.secondary,
                  theme: theme,
                  compact: true,
                ),
                if (issue.line != null)
                  _buildMetaChip(
                    label: issue.column != null
                        ? 'Line ${issue.line}, Col ${issue.column}'
                        : 'Line ${issue.line}',
                    icon: Icons.segment_rounded,
                    color: scheme.tertiary,
                    theme: theme,
                    compact: true,
                  ),
              ],
            ),
          ),
          children: [
            if (issue.suggestion != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Suggested next step',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                issue.suggestion!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.45,
                ),
              ),
            ],
            if (issue.codeExample != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        issue.codeExample!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: issue.codeExample!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Copied to clipboard'),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
    required ThemeData theme,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withValues(alpha: 0.14),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required ThemeData theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildMetaChip({
    required String label,
    required IconData icon,
    required Color color,
    required ThemeData theme,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 14 : 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _sourceColor(String source, ThemeData theme) {
    return source == 'mcp'
        ? theme.colorScheme.tertiary
        : theme.colorScheme.primary;
  }

  String _sourceLabel(String source) {
    return source == 'mcp' ? 'MCP Review' : 'App Review';
  }

  String _reviewHeadline(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
        return 'MCP verification pass';
      case 'verify_and_save':
        return 'Verified and saved source review';
      case 'analyze_code':
        return 'MCP deep analysis';
      default:
        return '${_reviewTypeLabel(reviewType, toolName: toolName)} review';
    }
  }

  String _reviewTypeLabel(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
        return 'Verify';
      case 'verify_and_save':
        return 'Verify + Save';
      case 'analyze_code':
        return 'Analyze';
      case 'comprehensive':
        return 'Comprehensive';
      case 'security':
        return 'Security';
      case 'performance':
        return 'Performance';
      case 'readability':
        return 'Readability';
      default:
        return _titleCase(reviewType);
    }
  }

  IconData _reviewTypeIcon(String reviewType, {String? toolName}) {
    switch (toolName ?? reviewType) {
      case 'verify_code':
      case 'verify_and_save':
        return Icons.verified_outlined;
      case 'analyze_code':
        return Icons.analytics_outlined;
      case 'security':
        return Icons.security_rounded;
      case 'performance':
        return Icons.speed_rounded;
      case 'readability':
        return Icons.visibility_rounded;
      default:
        return Icons.rate_review_rounded;
    }
  }

  String _titleCase(String value) {
    return value
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) {
      final minutes = diff.inMinutes.clamp(1, 59);
      return '$minutes min ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    }
    if (diff.inDays == 0) {
      return 'Today';
    }
    if (diff.inDays == 1) {
      return 'Yesterday';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    }
    return '${date.day}/${date.month}/${date.year}';
  }
}
