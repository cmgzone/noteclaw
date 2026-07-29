import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api/api_service.dart';
import '../../core/auth/custom_auth_service.dart';
import '../../core/config/env_config.dart';
import '../memory/memory_models.dart';
import '../subscription/widgets/subscription_overview.dart';
import 'api_tokens_section.dart';

enum _WorkspaceMenuAction { account, refresh, signOut }

class MemoryWorkspaceState {
  const MemoryWorkspaceState({
    this.notebooks = const [],
    this.websocketInfo = const {},
    this.topicAccess = const {},
    this.isLoading = false,
    this.error,
  });

  final List<MemoryNotebook> notebooks;
  final Map<String, dynamic> websocketInfo;
  final Map<String, dynamic> topicAccess;
  final bool isLoading;
  final String? error;

  int get sourceCount =>
      notebooks.fold(0, (total, notebook) => total + notebook.sourceCount);
  int get liveConnections => notebooks.fold(
        0,
        (total, notebook) => total + notebook.session.websocketConnectionCount,
      );
  int get liveNotebooks =>
      notebooks.where((notebook) => notebook.session.websocketConnected).length;
  List<String> get liveAgentNames => notebooks
      .expand((notebook) => notebook.session.connectedClients)
      .where((name) => name.trim().isNotEmpty)
      .toSet()
      .toList(growable: false)
    ..sort();
}

class MemoryWorkspaceNotifier extends StateNotifier<MemoryWorkspaceState> {
  MemoryWorkspaceNotifier(this.ref) : super(const MemoryWorkspaceState()) {
    refresh();
  }

  final Ref ref;

  Future<void> refresh() async {
    state = MemoryWorkspaceState(
      notebooks: state.notebooks,
      websocketInfo: state.websocketInfo,
      topicAccess: state.topicAccess,
      isLoading: true,
    );

    try {
      final api = ref.read(apiServiceProvider);
      List<Map<String, dynamic>> rows = [];
      Map<String, dynamic> wsInfo = {};
      Map<String, dynamic> topicAccess = {};
      String? firstError;

      try {
        rows = await api.getMemoryNotebooks();
      } catch (e) {
        firstError = _friendlyError(e);
      }

      try {
        wsInfo = await api.getAgentWebSocketInfo();
      } catch (e) {
        // Ignored optional info failure
      }

      try {
        topicAccess = await api.getAgentTopicAccess();
      } catch (e) {
        // Ignored optional topic access failure
      }

      state = MemoryWorkspaceState(
        notebooks: rows
            .map(MemoryNotebook.fromJson)
            .where((notebook) => notebook.id.isNotEmpty)
            .toList(growable: false),
        websocketInfo: wsInfo,
        topicAccess: topicAccess,
        error: rows.isEmpty ? firstError : null,
      );
    } catch (error) {
      state = MemoryWorkspaceState(
        notebooks: state.notebooks,
        websocketInfo: state.websocketInfo,
        topicAccess: state.topicAccess,
        error: _friendlyError(error),
      );
    }
  }
}

final memoryWorkspaceProvider =
    StateNotifierProvider<MemoryWorkspaceNotifier, MemoryWorkspaceState>(
  MemoryWorkspaceNotifier.new,
);

class AgentConnectionsScreen extends ConsumerWidget {
  const AgentConnectionsScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(customAuthStateProvider.notifier).signOut();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(memoryWorkspaceProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: const _Brand(),
        actions: [
          const SubscriptionBalanceButton(),
          PopupMenuButton<_WorkspaceMenuAction>(
            tooltip: 'Workspace menu',
            icon: const Icon(LucideIcons.moreVertical, size: 20),
            onSelected: (action) async {
              switch (action) {
                case _WorkspaceMenuAction.account:
                  context.push('/settings/account');
                  break;
                case _WorkspaceMenuAction.refresh:
                  await Future.wait([
                    ref.read(memoryWorkspaceProvider.notifier).refresh(),
                    ref.read(apiTokensProvider.notifier).refresh(),
                  ]);
                  break;
                case _WorkspaceMenuAction.signOut:
                  await _signOut(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _WorkspaceMenuAction.account,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.settings, size: 18),
                  title: Text('Account settings'),
                ),
              ),
              PopupMenuItem(
                value: _WorkspaceMenuAction.refresh,
                enabled: !workspace.isLoading,
                child: const ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.refreshCw, size: 18),
                  title: Text('Refresh workspace'),
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: _WorkspaceMenuAction.signOut,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(LucideIcons.logOut, size: 18),
                  title: Text('Sign out'),
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(memoryWorkspaceProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 48),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WorkspaceHeader(state: workspace),
                    const SizedBox(height: 16),
                    _MetricStrip(state: workspace),
                    const SizedBox(height: 18),
                    const SubscriptionOverviewCard(),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const tokens = _TokenAccessCard();
                        const connection = _ConnectionCard();

                        if (constraints.maxWidth < 880) {
                          return const Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              tokens,
                              SizedBox(height: 14),
                              connection,
                            ],
                          );
                        }

                        return const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 6, child: tokens),
                            SizedBox(width: 18),
                            Expanded(flex: 5, child: connection),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 28),
                    _TopicAccessPanel(
                      matrix: workspace.topicAccess,
                    ),
                    const SizedBox(height: 28),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final notebooks = _NotebookSection(state: workspace);
                        const capabilities = Column(
                          children: [
                            _AgentToolsCard(),
                          ],
                        );

                        if (constraints.maxWidth < 880) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              notebooks,
                              const SizedBox(height: 18),
                              capabilities,
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: notebooks),
                            const SizedBox(width: 18),
                            const Expanded(flex: 4, child: capabilities),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            LucideIcons.brainCircuit,
            color: scheme.onPrimary,
            size: 20,
          ),
        ),
        const SizedBox(width: 11),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'NoteClaw',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            Text(
              'AGENT MEMORY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.primary,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({required this.state});

  final MemoryWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.all(24),
      color: scheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'PRIVATE WORKSPACE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Shared memory for every agent on your project.',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      height: 1.12,
                    ),
              ),
              const SizedBox(height: 10),
              Text(
                'Agents on this account can restore durable settings, share '
                'project context in real time, and request focused code reviews.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.55,
                    ),
              ),
            ],
          );

          final status = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LiveDot(active: state.liveConnections > 0),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.liveConnections > 0 ? 'Memory live' : 'Ready',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      state.liveConnections > 0
                          ? state.liveAgentNames.isNotEmpty
                              ? state.liveAgentNames.take(2).join(' · ')
                              : '${state.liveConnections} active connection${state.liveConnections == 1 ? '' : 's'}'
                          : 'Waiting for an agent',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 20),
                Align(alignment: Alignment.centerLeft, child: status),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 28),
              status,
            ],
          );
        },
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.state});

  final MemoryWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = constraints.maxWidth >= 700
            ? 3
            : constraints.maxWidth >= 430
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (count - 1)) / count;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            _Metric(
              width: width,
              icon: LucideIcons.library,
              value: '${state.notebooks.length}',
              label: 'Memory notebooks',
            ),
            _Metric(
              width: width,
              icon: LucideIcons.layers,
              value: '${state.sourceCount}',
              label: 'Namespace sources',
            ),
            _Metric(
              width: width,
              icon: LucideIcons.radio,
              value: '${state.liveConnections}',
              label: 'Live agent clients',
            ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.width,
    required this.icon,
    required this.value,
    required this.label,
  });

  final double width;
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      child: _Panel(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, size: 19, color: scheme.primary),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
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

class _TopicAccessPanel extends ConsumerStatefulWidget {
  const _TopicAccessPanel({required this.matrix});

  final Map<String, dynamic> matrix;

  @override
  ConsumerState<_TopicAccessPanel> createState() => _TopicAccessPanelState();
}

class _TopicAccessPanelState extends ConsumerState<_TopicAccessPanel> {
  String? _agentId;
  Set<String> _selectedTopicIds = {};
  bool _saving = false;

  List<Map<String, dynamic>> get _agents =>
      List<dynamic>.from(widget.matrix['agents'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  List<Map<String, dynamic>> get _topics =>
      List<dynamic>.from(widget.matrix['topics'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  List<Map<String, dynamic>> get _grants =>
      List<dynamic>.from(widget.matrix['grants'] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _syncSelection();
  }

  @override
  void didUpdateWidget(covariant _TopicAccessPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matrix != widget.matrix) _syncSelection();
  }

  void _syncSelection() {
    final agents = _agents;
    if (agents.isEmpty) {
      _agentId = null;
      _selectedTopicIds = {};
      return;
    }
    final knownAgent = agents.any((agent) => agent['id'] == _agentId);
    _selectAgent(
      knownAgent ? _agentId! : agents.first['id']?.toString() ?? '',
      rebuild: false,
    );
  }

  void _selectAgent(String id, {bool rebuild = true}) {
    void update() {
      _agentId = id;
      _selectedTopicIds = _grants
          .where((grant) =>
              grant['agentSessionId'] == id && grant['canRead'] == true)
          .map((grant) => grant['notebookId']?.toString() ?? '')
          .where((topicId) => topicId.isNotEmpty)
          .toSet();
    }

    if (rebuild) {
      setState(update);
    } else {
      update();
    }
  }

  Future<void> _save() async {
    final agentId = _agentId;
    if (agentId == null || agentId.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(apiServiceProvider).updateAgentTopicAccess(
            agentId,
            _selectedTopicIds.toList(growable: false),
          );
      await ref.read(memoryWorkspaceProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Agent topic access updated')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _createTopic() async {
    final agentId = _agentId;
    if (agentId == null || agentId.isEmpty) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New topic notebook'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 120,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.pop(dialogContext, value.trim());
            }
          },
          decoration: const InputDecoration(
            labelText: 'Topic name',
            hintText: 'e.g. Product launch',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty || !mounted) return;

    setState(() => _saving = true);
    try {
      final api = ref.read(apiServiceProvider);
      final topic = await api.createNotebook(
        title: title,
        description: 'Topic notebook for organized memories and sources',
        category: 'Agent memory topic',
      );
      final topicId = topic['id']?.toString() ?? '';
      if (topicId.isEmpty) throw Exception('The topic was not created.');
      final nextIds = {..._selectedTopicIds, topicId};
      await api.updateAgentTopicAccess(
          agentId, nextIds.toList(growable: false));
      _selectedTopicIds = nextIds;
      await ref.read(memoryWorkspaceProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Topic “$title” created')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final agents = _agents;
    final topics = _topics;

    return _Panel(
      padding: const EdgeInsets.all(20),
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  LucideIcons.shieldCheck,
                  color: scheme.primary,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Topic access',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Each notebook is a topic. Choose the memories and sources '
                      'each agent may read through MCP.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (agents.isEmpty)
            Text(
              'Connect an MCP agent to create its private notebook and manage its topics.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: _agentId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Agent',
                prefixIcon: Icon(LucideIcons.bot, size: 18),
              ),
              items: agents
                  .map(
                    (agent) => DropdownMenuItem<String>(
                      value: agent['id']?.toString(),
                      child: Text(
                        '${agent['mcpClientName'] ?? agent['agentName'] ?? 'Agent'} · '
                        '${agent['agentIdentifier'] ?? ''}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                if (value != null) _selectAgent(value);
              },
            ),
            const SizedBox(height: 14),
            if (topics.isEmpty)
              Text(
                'No topic notebooks are available yet.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: topics.map((topic) {
                  final topicId = topic['id']?.toString() ?? '';
                  final selected = _selectedTopicIds.contains(topicId);
                  return FilterChip(
                    selected: selected,
                    showCheckmark: true,
                    avatar: const Icon(LucideIcons.bookOpen, size: 15),
                    label: Text(
                      '${topic['title'] ?? 'Untitled'} '
                      '(${topic['sourceCount'] ?? 0})',
                    ),
                    onSelected: (value) {
                      setState(() {
                        if (value) {
                          _selectedTopicIds.add(topicId);
                        } else {
                          _selectedTopicIds.remove(topicId);
                        }
                      });
                    },
                  );
                }).toList(growable: false),
              ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _saving ? null : _createTopic,
                  icon: const Icon(LucideIcons.plus, size: 17),
                  label: const Text('New topic'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(LucideIcons.save, size: 17),
                  label: const Text('Save access'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _NotebookSection extends StatelessWidget {
  const _NotebookSection({required this.state});

  final MemoryWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Memory notebooks',
          subtitle:
              'One readable notebook per shared agent or project session.',
          trailing: state.isLoading && state.notebooks.isNotEmpty
              ? const SizedBox(
                  width: 17,
                  height: 17,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (state.isLoading && state.notebooks.isEmpty)
          const _LoadingPanel()
        else if (state.error != null && state.notebooks.isEmpty)
          _EmptyPanel(
            icon: LucideIcons.alertCircle,
            title: 'Could not load memory',
            description: state.error!,
          )
        else if (state.notebooks.isEmpty)
          const _EmptyPanel(
            icon: LucideIcons.library,
            title: 'No memory notebooks yet',
            description:
                'Connect an agent through MCP. Its first memory session will appear here automatically.',
          )
        else
          ...state.notebooks.map(
            (notebook) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotebookCard(notebook: notebook),
            ),
          ),
        if (state.error != null && state.notebooks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              state.error!,
              style: TextStyle(color: scheme.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _NotebookCard extends StatelessWidget {
  const _NotebookCard({required this.notebook});

  final MemoryNotebook notebook;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = notebook.session.websocketConnected;
    return _Panel(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () => context.push('/memory-notebooks/${notebook.id}'),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final icon = Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  LucideIcons.bookOpen,
                  color: scheme.primary,
                  size: 21,
                ),
              );
              final content = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notebook.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (notebook.isAgentNotebook)
                        _StatusBadge(live: live)
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'TOPIC',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    notebook.isAgentNotebook
                        ? '${notebook.session.displayAgentName} · ${notebook.session.agentIdentifier}'
                        : (notebook.description.isNotEmpty
                            ? notebook.description
                            : 'Notebook memories and sources'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _Meta(
                        icon: LucideIcons.layers,
                        text:
                            '${notebook.sourceCount} source${notebook.sourceCount == 1 ? '' : 's'}',
                      ),
                      _Meta(
                        icon: LucideIcons.clock3,
                        text: _relativeTime(notebook.updatedAt),
                      ),
                      const _Meta(
                        icon: LucideIcons.messageSquare,
                        text: 'Chat ready',
                      ),
                    ],
                  ),
                ],
              );

              if (constraints.maxWidth < 430) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(height: 13),
                    content,
                  ],
                );
              }

              return Row(
                children: [
                  icon,
                  const SizedBox(width: 14),
                  Expanded(child: content),
                  const SizedBox(width: 10),
                  Icon(
                    LucideIcons.chevronRight,
                    color: scheme.onSurfaceVariant,
                    size: 19,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AgentToolsCard extends StatelessWidget {
  const _AgentToolsCard();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionHeader(
            title: 'Agent tools',
            subtitle: 'A compact MCP surface with a clear purpose.',
          ),
          SizedBox(height: 16),
          _ToolRow(
            icon: LucideIcons.database,
            title: 'Durable memory',
            description: 'Read, write, compact, and restore project context.',
            label: '7 tools',
          ),
          Divider(height: 25),
          _ToolRow(
            icon: LucideIcons.code2,
            title: 'Code review',
            description:
                'Check correctness, security, and maintainability before shipping.',
            label: 'review_code',
          ),
          Divider(height: 25),
          _ToolRow(
            icon: LucideIcons.search,
            title: 'Web & deep research',
            description:
                'Search current sources, build cited reports, and save them to notebooks.',
            label: '5 tools',
          ),
          Divider(height: 25),
          _ToolRow(
            icon: LucideIcons.radio,
            title: 'Live collaboration',
            description:
                'Multiple agents share one session over authenticated WebSocket.',
            label: 'real time',
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends StatelessWidget {
  const _ToolRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.label,
  });

  final IconData icon;
  final String title;
  final String description;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: scheme.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                          fontFamily: label.contains('_') ? 'monospace' : null,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard();

  static const _remoteConfiguration = '''{
  "mcpServers": {
    "noteclaw-memory": {
      "url": "${EnvConfig.hostedMcpUrl}",
      "headers": {
        "Authorization": "Bearer nclaw_your-token-here"
      }
    }
  }
}''';

  Future<void> _copy(
    BuildContext context,
    String value,
    String label,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$label copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionHeader(
            title: 'Connect an agent',
            subtitle:
                'Connect directly to hosted MCP—no server installation required.',
          ),
          const SizedBox(height: 16),
          const _ConnectionStep(
            number: '1',
            title: 'Create an agent token',
            description:
                'Generate a revocable token in MCP access below. Each agent should use its own token.',
          ),
          const SizedBox(height: 12),
          const _ConnectionStep(
            number: '2',
            title: 'Add this remote MCP configuration',
            description:
                'Paste it into Codex, Claude, Cursor, or another client that supports Streamable HTTP.',
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _remoteConfiguration,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _copy(
                      context,
                      _remoteConfiguration,
                      'Remote MCP configuration',
                    ),
                    icon: const Icon(LucideIcons.copy, size: 16),
                    label: const Text('Copy configuration'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _ConnectionStep(
            number: '3',
            title: 'Discover the memory notebook',
            description:
                'The first connection creates a private notebook automatically. Compatible clients list permitted notebooks as MCP Resources.',
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: EdgeInsets.zero,
            leading: Icon(
              LucideIcons.terminalSquare,
              color: scheme.onSurfaceVariant,
              size: 19,
            ),
            title: const Text(
              'Client only supports local stdio?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'Use the lightweight local bridge as a fallback.',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: SelectableText(
                        'npx -y @noteclaw/mcp-server',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _copy(
                        context,
                        'npx -y @noteclaw/mcp-server',
                        'Local MCP command',
                      ),
                      tooltip: 'Copy local command',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(LucideIcons.copy, size: 17),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionStep extends StatelessWidget {
  const _ConnectionStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            number,
            style: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TokenAccessCard extends ConsumerWidget {
  const _TokenAccessCard();

  void _createToken(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (context) => TokenGenerationDialog(
        onGenerate: (name, expiresAt) =>
            ref.read(apiTokensProvider.notifier).generateToken(name, expiresAt),
      ),
    );
  }

  void _revokeToken(BuildContext context, WidgetRef ref, ApiToken token) {
    showDialog<void>(
      context: context,
      builder: (context) => RevokeTokenDialog(
        token: token,
        onRevoke: () =>
            ref.read(apiTokensProvider.notifier).revokeToken(token.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(apiTokensProvider);
    final scheme = Theme.of(context).colorScheme;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const header = _SectionHeader(
                title: 'MCP access',
                subtitle:
                    'Tokens authenticate both MCP calls and WebSocket sessions.',
              );
              final button = FilledButton.icon(
                onPressed: state.canCreateMore
                    ? () => _createToken(context, ref)
                    : null,
                icon: const Icon(LucideIcons.plus, size: 17),
                label: const Text('New token'),
              );
              if (constraints.maxWidth < 560) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 14),
                    button,
                  ],
                );
              }
              return Row(
                children: [
                  const Expanded(child: header),
                  const SizedBox(width: 18),
                  button,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const LinearProgressIndicator()
          else if (state.error != null)
            Text(state.error!, style: TextStyle(color: scheme.error))
          else if (state.tokens.isEmpty)
            Text(
              'Create a token to connect your first agent.',
              style: TextStyle(color: scheme.onSurfaceVariant),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: state.tokens
                  .map(
                    (token) => _TokenChip(
                      token: token,
                      onRevoke: () => _revokeToken(context, ref, token),
                    ),
                  )
                  .toList(growable: false),
            ),
        ],
      ),
    );
  }
}

class _TokenChip extends StatelessWidget {
  const _TokenChip({required this.token, required this.onRevoke});

  final ApiToken token;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
      padding: const EdgeInsets.fromLTRB(12, 10, 5, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.keyRound, size: 16, color: scheme.primary),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  token.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  token.displayToken,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                    fontSize: 11,
                  ),
                ),
                if (token.boundAgentSessionId != null)
                  Text(
                    'Bound · ${token.boundAgentSessionId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.primary,
                      fontFamily: 'monospace',
                      fontSize: 9,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRevoke,
            tooltip: 'Revoke token',
            visualDensity: VisualDensity.compact,
            icon: Icon(LucideIcons.trash2, size: 16, color: scheme.error),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF36B7B4) : const Color(0xFF8D8792);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 7),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = live ? const Color(0xFF278E92) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LiveDot(active: live),
          const SizedBox(width: 6),
          Text(
            live ? 'Live' : 'Stored',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(text, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }
}

class _LoadingPanel extends StatelessWidget {
  const _LoadingPanel();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      child: SizedBox(
        height: 130,
        child: Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Icon(icon, size: 28, color: scheme.primary),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime? date) {
  if (date == null) return 'No updates yet';
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) return 'Updated now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  return '${date.day}/${date.month}/${date.year}';
}

String _friendlyError(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}
