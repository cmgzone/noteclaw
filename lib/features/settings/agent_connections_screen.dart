// ignore_for_file: deprecated_member_use
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/api/api_service.dart';
import '../../theme/app_theme.dart';
import '../../core/extensions/color_compat.dart';
import '../../ui/widgets/agent_notebook_badge.dart';
import 'api_tokens_section.dart';

/// Model for agent session data
/// Requirements: 4.1, 4.4
class AgentSession {
  final String id;
  final String agentName;
  final String agentIdentifier;
  final String status;
  final String? notebookId;
  final String? notebookTitle;
  final DateTime lastActivity;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;
  final List<String> memoryNamespaces;
  final DateTime? memoryUpdatedAt;
  final bool hasMemory;

  const AgentSession({
    required this.id,
    required this.agentName,
    required this.agentIdentifier,
    required this.status,
    this.notebookId,
    this.notebookTitle,
    required this.lastActivity,
    required this.createdAt,
    this.metadata,
    this.memoryNamespaces = const [],
    this.memoryUpdatedAt,
    this.hasMemory = false,
  });

  factory AgentSession.fromJson(Map<String, dynamic> json) {
    return AgentSession(
      id: json['id'] as String,
      agentName: json['agent_name'] as String? ??
          json['agentName'] as String? ??
          'Unknown Agent',
      agentIdentifier: json['agent_identifier'] as String? ??
          json['agentIdentifier'] as String? ??
          '',
      status: json['status'] as String? ?? 'active',
      notebookId:
          json['notebook_id'] as String? ?? json['notebookId'] as String?,
      notebookTitle:
          json['notebook_title'] as String? ?? json['notebookTitle'] as String?,
      lastActivity: json['last_activity'] != null
          ? DateTime.parse(json['last_activity'] as String)
          : json['lastActivity'] != null
              ? DateTime.parse(json['lastActivity'] as String)
              : DateTime.now(),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : json['createdAt'] != null
              ? DateTime.parse(json['createdAt'] as String)
              : DateTime.now(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      memoryNamespaces: json['memory_namespaces'] is List
          ? List<String>.from(json['memory_namespaces'])
          : const [],
      memoryUpdatedAt: json['memory_updated_at'] != null
          ? DateTime.tryParse(json['memory_updated_at'] as String)
          : json['memoryUpdatedAt'] != null
              ? DateTime.tryParse(json['memoryUpdatedAt'] as String)
              : null,
      hasMemory: json['has_memory'] as bool? ?? json['hasMemory'] as bool? ?? false,
    );
  }

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';
  bool get isDisconnected => status == 'disconnected';
}

/// State for agent connections
class AgentConnectionsState {
  final List<AgentSession> sessions;
  final bool isLoading;
  final String? error;

  const AgentConnectionsState({
    this.sessions = const [],
    this.isLoading = false,
    this.error,
  });

  AgentConnectionsState copyWith({
    List<AgentSession>? sessions,
    bool? isLoading,
    String? error,
  }) {
    return AgentConnectionsState(
      sessions: sessions ?? this.sessions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }

  int get activeCount => sessions.where((s) => s.isActive).length;
  int get expiredCount => sessions.where((s) => s.isExpired).length;
  int get disconnectedCount => sessions.where((s) => s.isDisconnected).length;
}

/// Provider for managing agent connections
/// Requirements: 4.1, 4.4
class AgentConnectionsNotifier extends StateNotifier<AgentConnectionsState> {
  final Ref ref;

  AgentConnectionsNotifier(this.ref) : super(const AgentConnectionsState()) {
    loadSessions();
  }

  /// Load all agent sessions from the API
  Future<void> loadSessions() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final apiService = ref.read(apiServiceProvider);
      final notebooks = await apiService.getAgentNotebooks();
      final memorySessions = await apiService.getAgentMemories();

      final memoryBySessionId = <String, Map<String, dynamic>>{};
      for (final row in memorySessions) {
        final sessionData =
            (row['session'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
        final memoryData =
            (row['memory'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
        final sessionId = sessionData['id'] as String?;
        if (sessionId == null || sessionId.isEmpty) {
          continue;
        }
        final memoryUpdatedAtRaw = memoryData['memoryUpdatedAt'] ??
            memoryData['memory_updated_at'];
        memoryBySessionId[sessionId] = {
          'hasMemory': memoryData['hasMemory'] as bool? ??
              memoryData['has_memory'] as bool? ??
              false,
          'memoryNamespaces': memoryData['namespaces'] is List
              ? List<String>.from(memoryData['namespaces'])
              : const <String>[],
          'memoryUpdatedAt': memoryUpdatedAtRaw is String
              ? DateTime.tryParse(memoryUpdatedAtRaw)
              : null,
        };
      }

      final sessions = notebooks.map((n) {
        final nestedSession =
            n['session'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        final sessionId = n['agent_session_id'] as String? ??
            nestedSession['id'] as String? ??
            n['id'] as String;
        final memoryInfo = memoryBySessionId[sessionId] ?? const <String, dynamic>{};

        // Extract agent session info from notebook metadata
        return AgentSession(
          id: sessionId,
          agentName: n['agent_name'] as String? ??
              nestedSession['agentName'] as String? ??
              n['agentName'] as String? ??
              'Unknown Agent',
          agentIdentifier: n['agent_identifier'] as String? ??
              nestedSession['agentIdentifier'] as String? ??
              n['agentIdentifier'] as String? ??
              '',
          status: n['agent_status'] as String? ??
              nestedSession['status'] as String? ??
              n['agentStatus'] as String? ??
              'active',
          notebookId: n['id'] as String?,
          notebookTitle: n['title'] as String?,
          lastActivity: n['last_activity'] != null
              ? DateTime.parse(n['last_activity'] as String)
              : n['updated_at'] != null
                  ? DateTime.parse(n['updated_at'] as String)
                  : DateTime.now(),
          createdAt: n['created_at'] != null
              ? DateTime.parse(n['created_at'] as String)
              : DateTime.now(),
          metadata: n['metadata'] as Map<String, dynamic>?,
          hasMemory: memoryInfo['hasMemory'] as bool? ?? false,
          memoryNamespaces: memoryInfo['memoryNamespaces'] is List
              ? List<String>.from(memoryInfo['memoryNamespaces'])
              : const [],
          memoryUpdatedAt: memoryInfo['memoryUpdatedAt'] as DateTime?,
        );
      }).toList();

      state = state.copyWith(
        sessions: sessions,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Disconnect an agent session
  /// Requirements: 4.3
  Future<bool> disconnectSession(String sessionId) async {
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.disconnectAgent(sessionId);

      // Update local state
      final updatedSessions = state.sessions.map((s) {
        if (s.id == sessionId) {
          return AgentSession(
            id: s.id,
            agentName: s.agentName,
            agentIdentifier: s.agentIdentifier,
            status: 'disconnected',
            notebookId: s.notebookId,
            notebookTitle: s.notebookTitle,
            lastActivity: DateTime.now(),
            createdAt: s.createdAt,
            metadata: s.metadata,
            memoryNamespaces: s.memoryNamespaces,
            memoryUpdatedAt: s.memoryUpdatedAt,
            hasMemory: s.hasMemory,
          );
        }
        return s;
      }).toList();

      state = state.copyWith(sessions: updatedSessions);
      return true;
    } catch (e) {
      state = state.copyWith(error: e.toString());
      return false;
    }
  }

  /// Refresh sessions
  Future<void> refresh() async {
    await loadSessions();
  }
}

/// Provider for agent connections
final agentConnectionsProvider =
    StateNotifierProvider<AgentConnectionsNotifier, AgentConnectionsState>(
  (ref) => AgentConnectionsNotifier(ref),
);

/// Screen showing all connected coding agents
/// Requirements: 4.1, 4.4
class AgentConnectionsScreen extends ConsumerWidget {
  const AgentConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(agentConnectionsProvider);

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.premiumGradient,
          ),
        ),
        title: const Text(
          'Agent Connections',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(agentConnectionsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(agentConnectionsProvider.notifier).refresh(),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // API Tokens Section - always visible
            const ApiTokensSection(),
            // Agent Sessions Section
            if (state.isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.error != null)
              _buildErrorState(context, ref, state.error!)
            else if (state.sessions.isEmpty)
              _buildEmptyState(context, scheme)
            else
              ..._buildSessionsListItems(context, ref, state, scheme),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, String error) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.alertCircle,
              size: 64,
              color: scheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load agents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(color: scheme.secondaryText),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(agentConnectionsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ColorScheme scheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.terminal,
                size: 64,
                color: scheme.primary,
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const SizedBox(height: 24),
            Text(
              'No Connected Agents',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ).animate().fadeIn(delay: 200.ms),
            const SizedBox(height: 12),
            Text(
              'Connect a coding agent like Claude, Kiro, or Cursor via MCP to see them here.',
              style: TextStyle(color: scheme.secondaryText),
              textAlign: TextAlign.center,
            ).animate().fadeIn(delay: 400.ms),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                // Show info dialog about connecting agents
                _showConnectionInfoDialog(context);
              },
              icon: const Icon(LucideIcons.helpCircle),
              label: const Text('How to Connect'),
            ).animate().fadeIn(delay: 600.ms),
          ],
        ),
      ),
    );
  }

  void _showConnectionInfoDialog(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(LucideIcons.terminal, size: 48, color: scheme.primary),
        title: const Text('Connecting Coding Agents'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To connect a coding agent:\n\n'
                '1. Configure the MCP server in your coding agent (Claude, Kiro, Cursor, etc.)\n\n'
                '2. Use the create_agent_notebook tool to create a dedicated notebook\n\n'
                '3. Save verified code using save_code_with_context\n\n'
                '4. Your agent will appear here once connected!',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSessionsListItems(
    BuildContext context,
    WidgetRef ref,
    AgentConnectionsState state,
    ColorScheme scheme,
  ) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: _buildStatsSummary(context, state, scheme),
      ),
      const SizedBox(height: 24),
      ...state.sessions.asMap().entries.map((entry) {
        final index = entry.key;
        final session = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: _AgentSessionCard(
            session: session,
            onDisconnect: () => _showDisconnectDialog(context, ref, session),
            onViewNotebook: session.notebookId != null
                ? () => context.push('/notebook/${session.notebookId}')
                : null,
            onViewMemory: () => _showMemoryDialog(context, ref, session),
          ).animate().fadeIn(delay: Duration(milliseconds: index * 100)),
        );
      }),
      const SizedBox(height: 32),
    ];
  }

  Widget _buildStatsSummary(
    BuildContext context,
    AgentConnectionsState state,
    ColorScheme scheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.1),
            scheme.secondary.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _StatItem(
              icon: LucideIcons.checkCircle,
              label: 'Active',
              value: state.activeCount.toString(),
              color: const Color(0xFF22C55E),
            ),
          ),
          Expanded(
            child: _StatItem(
              icon: LucideIcons.clock,
              label: 'Expired',
              value: state.expiredCount.toString(),
              color: const Color(0xFFF59E0B),
            ),
          ),
          Expanded(
            child: _StatItem(
                icon: LucideIcons.xCircle,
                label: 'Disconnected',
                value: state.disconnectedCount.toString(),
                color: const Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  void _showDisconnectDialog(
    BuildContext context,
    WidgetRef ref,
    AgentSession session,
  ) {
    final scheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(LucideIcons.unplug, size: 48, color: scheme.error),
        title: const Text('Disconnect Agent?'),
        content: Text(
          'Are you sure you want to disconnect ${session.agentName}?\n\n'
          'The notebook and sources will remain accessible, but you won\'t receive new messages from this agent.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ref
                  .read(agentConnectionsProvider.notifier)
                  .disconnectSession(session.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success
                          ? '${session.agentName} disconnected'
                          : 'Failed to disconnect agent',
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
            ),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMemoryDialog(
    BuildContext context,
    WidgetRef ref,
    AgentSession session,
  ) async {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading memory...'),
            ],
          ),
        ),
      ),
    );

    try {
      final apiService = ref.read(apiServiceProvider);
      final first = await apiService.getAgentMemory(
        agentSessionId: session.id,
        namespace: 'default',
      );

      final namespacesRaw = first['availableNamespaces'];
      final namespaces = namespacesRaw is List
          ? List<String>.from(namespacesRaw)
          : <String>[];
      final namespaceList = namespaces.isEmpty ? <String>['default'] : namespaces;

      final memoryByNamespace = <String, dynamic>{};
      for (final namespace in namespaceList) {
        final response = namespace == 'default'
            ? first
            : await apiService.getAgentMemory(
                agentSessionId: session.id,
                namespace: namespace,
              );
        memoryByNamespace[namespace] = response['memory'];
      }

      if (context.mounted) {
        Navigator.pop(context);
      }

      if (!context.mounted) {
        return;
      }

      showDialog(
        context: context,
        builder: (context) => _AgentMemoryViewerDialog(
          session: session,
          memoryByNamespace: memoryByNamespace,
          memoryUpdatedAt: first['memoryUpdatedAt'] as String?,
        ),
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load memory: $e'),
            backgroundColor: scheme.error,
          ),
        );
      }
    }
  }
}

class _AgentMemoryViewerDialog extends StatefulWidget {
  final AgentSession session;
  final Map<String, dynamic> memoryByNamespace;
  final String? memoryUpdatedAt;

  const _AgentMemoryViewerDialog({
    required this.session,
    required this.memoryByNamespace,
    required this.memoryUpdatedAt,
  });

  @override
  State<_AgentMemoryViewerDialog> createState() =>
      _AgentMemoryViewerDialogState();
}

class _AgentMemoryViewerDialogState extends State<_AgentMemoryViewerDialog>
    with SingleTickerProviderStateMixin {
  late final List<String> _namespaces;
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _namespaces = widget.memoryByNamespace.keys.toList(growable: false);
    _tabController = TabController(length: _namespaces.length, vsync: this);
    _searchController.addListener(() {
      setState(() {
        _query = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  String _namespaceText(String namespace) {
    final memory = widget.memoryByNamespace[namespace];
    return const JsonEncoder.withIndent('  ').convert(memory);
  }

  String _filteredText(String fullText) {
    if (_query.isEmpty) {
      return fullText;
    }
    final lines = const LineSplitter().convert(fullText);
    final filtered = lines
        .where((line) => line.toLowerCase().contains(_query))
        .toList(growable: false);
    if (filtered.isEmpty) {
      return 'No matches for "$_query"';
    }
    return filtered.join('\n');
  }

  Future<void> _copyCurrentNamespace() async {
    if (_namespaces.isEmpty) return;
    final namespace = _namespaces[_tabController.index];
    final text = _namespaceText(namespace);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied "$namespace" memory'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final updatedAt = widget.memoryUpdatedAt;

    return AlertDialog(
      icon: Icon(LucideIcons.brain, size: 36, color: scheme.primary),
      title: Text('${widget.session.agentName} Memory'),
      content: SizedBox(
        width: 820,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  'Namespaces: ${_namespaces.length}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.secondaryText,
                  ),
                ),
                if (updatedAt != null && updatedAt.isNotEmpty)
                  Text(
                    'Updated: $updatedAt',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.secondaryText,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search memory JSON',
                prefixIcon: const Icon(LucideIcons.search, size: 16),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () => _searchController.clear(),
                        icon: const Icon(Icons.close, size: 16),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: _namespaces.map((namespace) => Tab(text: namespace)).toList(),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 420,
              child: TabBarView(
                controller: _tabController,
                children: _namespaces.map((namespace) {
                  final fullText = _namespaceText(namespace);
                  final display = _filteredText(fullText);
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        display,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _copyCurrentNamespace,
          icon: const Icon(LucideIcons.copy, size: 16),
          label: const Text('Copy Namespace'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Stat item widget for the summary
class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: color,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.secondaryText,
              ),
        ),
      ],
    );
  }
}

/// Card widget for displaying an agent session
/// Requirements: 4.1, 4.2, 4.3
class _AgentSessionCard extends StatelessWidget {
  final AgentSession session;
  final VoidCallback onDisconnect;
  final VoidCallback? onViewNotebook;
  final VoidCallback onViewMemory;

  const _AgentSessionCard({
    required this.session,
    required this.onDisconnect,
    this.onViewNotebook,
    required this.onViewMemory,
  });

  IconData _getAgentIcon() {
    final name = session.agentName.toLowerCase();
    if (name.contains('claude')) return Icons.smart_toy_outlined;
    if (name.contains('kiro')) return Icons.auto_awesome;
    if (name.contains('cursor')) return Icons.code;
    if (name.contains('copilot')) return Icons.assistant;
    return Icons.terminal;
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    }
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.05),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                // Agent icon
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _getAgentIcon(),
                    size: 24,
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
                        session.agentName,
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AgentNotebookBadge(
                        agentName: session.agentIdentifier,
                        status: session.status,
                        compact: true,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _StatusChip(status: session.status),
                    const SizedBox(height: 6),
                    _MemoryHealthChip(
                      hasMemory: session.hasMemory,
                      namespaceCount: session.memoryNamespaces.length,
                      updatedAt: session.memoryUpdatedAt,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Details
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (session.notebookTitle != null) ...[
                  _DetailRow(
                    icon: LucideIcons.bookOpen,
                    label: 'Notebook',
                    value: session.notebookTitle!,
                  ),
                  const SizedBox(height: 8),
                ],
                _DetailRow(
                  icon: LucideIcons.clock,
                  label: 'Last Activity',
                  value: _formatTimeAgo(session.lastActivity),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon: LucideIcons.calendar,
                  label: 'Connected',
                  value: _formatTimeAgo(session.createdAt),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  icon: LucideIcons.brain,
                  label: 'Memory',
                  value: session.hasMemory
                      ? '${session.memoryNamespaces.length} namespaces'
                      : 'No memory saved',
                ),
                if (session.memoryUpdatedAt != null) ...[
                  const SizedBox(height: 8),
                  _DetailRow(
                    icon: LucideIcons.clock3,
                    label: 'Memory Updated',
                    value: _formatTimeAgo(session.memoryUpdatedAt!),
                  ),
                ],
              ],
            ),
          ),
          // Actions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.1),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onViewMemory,
                    icon: const Icon(LucideIcons.brain, size: 16),
                    label: const Text('View Memory'),
                  ),
                ),
                const SizedBox(width: 8),
                if (onViewNotebook != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onViewNotebook,
                      icon: const Icon(LucideIcons.externalLink, size: 16),
                      label: const Text('View Notebook'),
                    ),
                  ),
                if (onViewNotebook != null) const SizedBox(width: 8),
                if (session.isActive)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onDisconnect,
                      icon: const Icon(LucideIcons.unplug, size: 16),
                      label: const Text('Disconnect'),
                      style: FilledButton.styleFrom(
                        backgroundColor: scheme.error,
                      ),
                    ),
                  ),
                if (session.isExpired || session.isDisconnected)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        // Show reconnect info
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'To reconnect, use the coding agent to create a new session',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Reconnect Info'),
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

/// Status chip widget
class _StatusChip extends StatelessWidget {
  final String status;

  const _StatusChip({required this.status});

  Color _getColor() {
    switch (status.toLowerCase()) {
      case 'active':
        return const Color(0xFF22C55E);
      case 'expired':
        return const Color(0xFFF59E0B);
      case 'disconnected':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  String _getLabel() {
    switch (status.toLowerCase()) {
      case 'active':
        return 'Active';
      case 'expired':
        return 'Expired';
      case 'disconnected':
        return 'Disconnected';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _getLabel(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryHealthChip extends StatelessWidget {
  final bool hasMemory;
  final int namespaceCount;
  final DateTime? updatedAt;

  const _MemoryHealthChip({
    required this.hasMemory,
    required this.namespaceCount,
    required this.updatedAt,
  });

  Color _chipColor() {
    if (!hasMemory) {
      return const Color(0xFF9CA3AF);
    }
    if (updatedAt == null) {
      return const Color(0xFF10B981);
    }
    final age = DateTime.now().difference(updatedAt!);
    if (age.inDays <= 1) {
      return const Color(0xFF22C55E);
    }
    if (age.inDays <= 7) {
      return const Color(0xFFF59E0B);
    }
    return const Color(0xFFEF4444);
  }

  String _label() {
    if (!hasMemory) {
      return 'Memory empty';
    }
    if (updatedAt == null) {
      return '$namespaceCount namespaces';
    }
    final age = DateTime.now().difference(updatedAt!);
    if (age.inHours < 1) {
      return '$namespaceCount ns · fresh';
    }
    if (age.inDays < 1) {
      return '$namespaceCount ns · ${age.inHours}h';
    }
    return '$namespaceCount ns · ${age.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final color = _chipColor();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.brain, size: 10, color: color),
          const SizedBox(width: 5),
          Text(
            _label(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail row widget
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.secondaryText),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 13,
            color: scheme.secondaryText,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
