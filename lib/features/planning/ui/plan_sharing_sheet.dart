import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../../../core/api/api_service.dart';
import '../models/plan.dart';
import '../planning_provider.dart';

/// Bottom sheet for managing agent access to a plan.
/// Implements Requirements: 7.1, 7.2
/// - 7.1: Grant agent access to a plan
/// - 7.2: Revoke agent access from a plan
class PlanSharingSheet extends ConsumerStatefulWidget {
  final Plan plan;

  const PlanSharingSheet({super.key, required this.plan});

  /// Show the plan sharing sheet as a modal bottom sheet
  static Future<void> show(BuildContext context, Plan plan) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PlanSharingSheet(plan: plan),
    );
  }

  @override
  ConsumerState<PlanSharingSheet> createState() => _PlanSharingSheetState();
}

class _PlanSharingSheetState extends ConsumerState<PlanSharingSheet> {
  bool _isLoading = false;
  bool _isLoadingAgents = true;
  List<AgentAccess> _sharedAgents = [];
  List<_AvailableAgent> _availableAgents = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingAgents = true;
      _error = null;
    });

    try {
      // Load current shared agents from the plan
      _sharedAgents =
          widget.plan.sharedAgents.where((a) => a.revokedAt == null).toList();

      // Load available agents from the API
      final apiService = ref.read(apiServiceProvider);
      final notebooks = await apiService.getAgentNotebooks();

      _availableAgents = notebooks.map((n) {
        return _AvailableAgent(
          sessionId: n['agent_session_id'] as String? ?? n['id'] as String,
          name: n['agent_name'] as String? ??
              n['agentName'] as String? ??
              'Unknown Agent',
          identifier: n['agent_identifier'] as String? ??
              n['agentIdentifier'] as String? ??
              '',
          status: n['agent_status'] as String? ??
              n['agentStatus'] as String? ??
              'active',
        );
      }).toList();

      setState(() => _isLoadingAgents = false);
    } catch (e) {
      setState(() {
        _isLoadingAgents = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        LucideIcons.share2,
                        color: scheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Share Plan',
                            style: text.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.plan.title,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.x),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
              const Divider(height: 1),
              // Content
              Expanded(
                child: _isLoadingAgents
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildErrorState(scheme, text)
                        : _buildContent(scrollController, scheme, text),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(ColorScheme scheme, TextTheme text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 48,
              color: scheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load agents',
              style: text.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: text.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(LucideIcons.refreshCw, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    ScrollController scrollController,
    ColorScheme scheme,
    TextTheme text,
  ) {
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        // Privacy toggle
        _PrivacyToggle(
          isPrivate: widget.plan.isPrivate,
          onChanged: _togglePrivacy,
          isLoading: _isLoading,
        ).animate().fadeIn(delay: 100.ms),
        const SizedBox(height: 24),
        // Shared agents section
        _SectionHeader(
          icon: LucideIcons.users,
          title: 'Shared With',
          count: _sharedAgents.length,
        ),
        const SizedBox(height: 12),
        if (_sharedAgents.isEmpty)
          _EmptyAgentsCard(scheme: scheme, text: text)
        else
          ..._sharedAgents.asMap().entries.map((entry) {
            final index = entry.key;
            final agent = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SharedAgentCard(
                agent: agent,
                onRevoke: () => _revokeAccess(agent),
                isLoading: _isLoading,
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 150 + index * 50)),
            );
          }),
        const SizedBox(height: 24),
        // Available agents section
        _SectionHeader(
          icon: LucideIcons.bot,
          title: 'Available Agents',
          count: _getUnsharedAgents().length,
        ),
        const SizedBox(height: 12),
        if (_getUnsharedAgents().isEmpty)
          _NoAvailableAgentsCard(scheme: scheme, text: text)
        else
          ..._getUnsharedAgents().asMap().entries.map((entry) {
            final index = entry.key;
            final agent = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _AvailableAgentCard(
                agent: agent,
                onGrant: () => _grantAccess(agent),
                isLoading: _isLoading,
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: 200 + index * 50)),
            );
          }),
        const SizedBox(height: 16),
        // Manual share section
        _ManualShareSection(
          onShare: _grantAccessManually,
          isLoading: _isLoading,
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }

  List<_AvailableAgent> _getUnsharedAgents() {
    final sharedIds = _sharedAgents.map((a) => a.agentSessionId).toSet();
    return _availableAgents
        .where((a) => !sharedIds.contains(a.sessionId) && a.status == 'active')
        .toList();
  }

  Future<void> _togglePrivacy(bool isPrivate) async {
    setState(() => _isLoading = true);
    try {
      await ref.read(planningProvider.notifier).updatePlan(
            widget.plan.id,
            isPrivate: isPrivate,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPrivate ? 'Plan is now private' : 'Plan is now public',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update privacy: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Grant access to an agent
  /// Implements Requirement 7.1
  Future<void> _grantAccess(_AvailableAgent agent) async {
    setState(() => _isLoading = true);
    try {
      final access = await ref.read(planningProvider.notifier).grantAgentAccess(
        agentSessionId: agent.sessionId,
        agentName: agent.name,
        permissions: ['read', 'update', 'create_task'],
      );
      if (access != null && mounted) {
        setState(() {
          _sharedAgents = [..._sharedAgents, access];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${agent.name} can now access this plan'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to grant access: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Grant access manually by session ID
  Future<void> _grantAccessManually(String sessionId, String? name) async {
    setState(() => _isLoading = true);
    try {
      final access = await ref.read(planningProvider.notifier).grantAgentAccess(
        agentSessionId: sessionId,
        agentName: name,
        permissions: ['read', 'update', 'create_task'],
      );
      if (access != null && mounted) {
        setState(() {
          _sharedAgents = [..._sharedAgents, access];
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Agent ${name ?? sessionId} can now access this plan'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to grant access: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Revoke access from an agent
  /// Implements Requirement 7.2
  Future<void> _revokeAccess(AgentAccess agent) async {
    final confirmed = await _showRevokeConfirmation(agent);
    if (!confirmed) return;

    setState(() => _isLoading = true);
    try {
      final success = await ref
          .read(planningProvider.notifier)
          .revokeAgentAccess(agent.agentSessionId);
      if (success && mounted) {
        setState(() {
          _sharedAgents = _sharedAgents
              .where((a) => a.agentSessionId != agent.agentSessionId)
              .toList();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${agent.agentName ?? 'Agent'} access revoked'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to revoke access: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _showRevokeConfirmation(AgentAccess agent) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          LucideIcons.userMinus,
          size: 48,
          color: Theme.of(context).colorScheme.error,
        ),
        title: const Text('Revoke Access?'),
        content: Text(
          'Are you sure you want to revoke access for ${agent.agentName ?? 'this agent'}?\n\n'
          'They will no longer be able to view or update this plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

/// Model for available agents from the API
class _AvailableAgent {
  final String sessionId;
  final String name;
  final String identifier;
  final String status;

  const _AvailableAgent({
    required this.sessionId,
    required this.name,
    required this.identifier,
    required this.status,
  });
}

/// Privacy toggle widget
class _PrivacyToggle extends StatelessWidget {
  final bool isPrivate;
  final ValueChanged<bool> onChanged;
  final bool isLoading;

  const _PrivacyToggle({
    required this.isPrivate,
    required this.onChanged,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isPrivate
                  ? Colors.amber.withValues(alpha: 0.1)
                  : Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPrivate ? LucideIcons.lock : LucideIcons.globe,
              color: isPrivate ? Colors.amber : Colors.green,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPrivate ? 'Private Plan' : 'Shared Plan',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isPrivate
                      ? 'Only you and shared agents can access'
                      : 'All your connected agents can access',
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Switch(
              value: !isPrivate,
              onChanged: (value) => onChanged(!value),
            ),
        ],
      ),
    );
  }
}

/// Section header widget
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.toString(),
            style: text.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

/// Empty agents card
class _EmptyAgentsCard extends StatelessWidget {
  final ColorScheme scheme;
  final TextTheme text;

  const _EmptyAgentsCard({required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          Icon(
            LucideIcons.userPlus,
            size: 32,
            color: scheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No agents have access yet',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Share this plan with agents below',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// No available agents card
class _NoAvailableAgentsCard extends StatelessWidget {
  final ColorScheme scheme;
  final TextTheme text;

  const _NoAvailableAgentsCard({required this.scheme, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          Icon(
            LucideIcons.terminal,
            size: 32,
            color: scheme.outline.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 12),
          Text(
            'No available agents',
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect an agent via MCP first',
            style: text.bodySmall?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shared agent card widget
class _SharedAgentCard extends StatelessWidget {
  final AgentAccess agent;
  final VoidCallback onRevoke;
  final bool isLoading;

  const _SharedAgentCard({
    required this.agent,
    required this.onRevoke,
    required this.isLoading,
  });

  IconData _getAgentIcon() {
    final name = (agent.agentName ?? '').toLowerCase();
    if (name.contains('claude')) return Icons.smart_toy_outlined;
    if (name.contains('kiro')) return Icons.auto_awesome;
    if (name.contains('cursor')) return Icons.code;
    if (name.contains('copilot')) return Icons.assistant;
    return Icons.terminal;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Agent icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getAgentIcon(),
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          // Agent info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.agentName ?? 'Unknown Agent',
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      LucideIcons.calendar,
                      size: 12,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Shared ${dateFormat.format(agent.grantedAt)}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Permissions
                Wrap(
                  spacing: 4,
                  children: agent.permissions.map((p) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        p,
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          // Revoke button
          IconButton(
            onPressed: isLoading ? null : onRevoke,
            icon: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    LucideIcons.userMinus,
                    size: 20,
                    color: scheme.error,
                  ),
            tooltip: 'Revoke access',
          ),
        ],
      ),
    );
  }
}

/// Available agent card widget
class _AvailableAgentCard extends StatelessWidget {
  final _AvailableAgent agent;
  final VoidCallback onGrant;
  final bool isLoading;

  const _AvailableAgentCard({
    required this.agent,
    required this.onGrant,
    required this.isLoading,
  });

  IconData _getAgentIcon() {
    final name = agent.name.toLowerCase();
    if (name.contains('claude')) return Icons.smart_toy_outlined;
    if (name.contains('kiro')) return Icons.auto_awesome;
    if (name.contains('cursor')) return Icons.code;
    if (name.contains('copilot')) return Icons.assistant;
    return Icons.terminal;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          // Agent icon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              _getAgentIcon(),
              size: 20,
              color: Colors.purple,
            ),
          ),
          const SizedBox(width: 12),
          // Agent info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.name,
                  style: text.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (agent.identifier.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    agent.identifier,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Grant button
          FilledButton.icon(
            onPressed: isLoading ? null : onGrant,
            icon: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.userPlus, size: 16),
            label: const Text('Share'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Manual share section for entering agent session ID directly
class _ManualShareSection extends StatefulWidget {
  final Future<void> Function(String sessionId, String? name) onShare;
  final bool isLoading;

  const _ManualShareSection({
    required this.onShare,
    required this.isLoading,
  });

  @override
  State<_ManualShareSection> createState() => _ManualShareSectionState();
}

class _ManualShareSectionState extends State<_ManualShareSection> {
  final _sessionIdController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isExpanded = false;

  @override
  void dispose() {
    _sessionIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.link,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Share with Session ID',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Enter an agent session ID manually',
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 20,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          // Expandable content
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _sessionIdController,
                    decoration: InputDecoration(
                      labelText: 'Agent Session ID *',
                      hintText: 'Enter the agent session ID',
                      prefixIcon: const Icon(LucideIcons.key, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(LucideIcons.clipboard, size: 18),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _sessionIdController.text = data!.text!;
                          }
                        },
                        tooltip: 'Paste from clipboard',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'Agent Name (optional)',
                      hintText: 'e.g., Claude, Kiro, Cursor',
                      prefixIcon: const Icon(LucideIcons.bot, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.isLoading ||
                              _sessionIdController.text.trim().isEmpty
                          ? null
                          : () {
                              widget.onShare(
                                _sessionIdController.text.trim(),
                                _nameController.text.trim().isEmpty
                                    ? null
                                    : _nameController.text.trim(),
                              );
                              _sessionIdController.clear();
                              _nameController.clear();
                            },
                      icon: widget.isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(LucideIcons.share2, size: 16),
                      label: const Text('Share with Agent'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
