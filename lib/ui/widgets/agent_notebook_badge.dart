import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// A badge widget that displays agent name and connection status
/// for notebooks created by third-party coding agents.
///
/// Requirements: 1.4, 4.1
class AgentNotebookBadge extends StatelessWidget {
  const AgentNotebookBadge({
    super.key,
    required this.agentName,
    this.status = 'active',
    this.compact = false,
    this.onCoverImage = false,
  });

  /// The name of the coding agent (e.g., "Claude", "Kiro", "OpenClaw")
  final String agentName;

  /// Connection status: 'active', 'expired', or 'disconnected'
  final String status;

  /// Whether to show a compact version (icon only)
  final bool compact;

  /// Whether the badge is displayed on a cover image (affects colors)
  final bool onCoverImage;

  Color _getStatusColor(ColorScheme scheme) {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF22C55E); // Green
      case 'expired':
        return const Color(0xFFF59E0B); // Amber
      case 'disconnected':
        return const Color(0xFFEF4444); // Red
      default:
        return scheme.outline;
    }
  }

  IconData _getAgentIcon() {
    final name = agentName.toLowerCase();
    if (name.contains('claude')) {
      return Icons.smart_toy_outlined;
    } else if (name.contains('kiro')) {
      return Icons.auto_awesome;
    } else if (name.contains('openclaw') || name.contains('cursor')) {
      return Icons.code;
    } else if (name.contains('copilot')) {
      return Icons.assistant;
    }
    return Icons.terminal;
  }

  String _getStatusText() {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Connected';
      case 'expired':
        return 'Session Expired';
      case 'disconnected':
        return 'Disconnected';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = _getStatusColor(scheme);

    if (compact) {
      return _buildCompactBadge(scheme, statusColor);
    }

    return _buildFullBadge(context, scheme, statusColor);
  }

  Widget _buildCompactBadge(ColorScheme scheme, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: onCoverImage
            ? Colors.black.withValues(alpha: 0.5)
            : scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: statusColor.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getAgentIcon(),
            size: 14,
            color: onCoverImage ? Colors.white : scheme.primary,
          ),
          const SizedBox(width: 4),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.8, 0.8));
  }

  Widget _buildFullBadge(
    BuildContext context,
    ColorScheme scheme,
    Color statusColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: onCoverImage
            ? Colors.black.withValues(alpha: 0.6)
            : scheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onCoverImage
              ? Colors.white.withValues(alpha: 0.2)
              : scheme.primary.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Agent icon
          Icon(
            _getAgentIcon(),
            size: 14,
            color: onCoverImage ? Colors.white : scheme.primary,
          ),
          const SizedBox(width: 6),
          // Agent name
          Text(
            agentName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: onCoverImage ? Colors.white : scheme.primary,
            ),
          ),
          const SizedBox(width: 6),
          // Status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  _getStatusText(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: onCoverImage
                        ? Colors.white.withValues(alpha: 0.9)
                        : statusColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: -0.2);
  }
}
