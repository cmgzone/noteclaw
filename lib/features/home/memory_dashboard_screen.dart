import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../ui/digital_librarian.dart';
import '../memory/memory_models.dart';
import '../settings/agent_connections_screen.dart';
import '../subscription/widgets/subscription_overview.dart';
import 'notebook_pins_provider.dart';

class MemoryDashboardScreen extends ConsumerWidget {
  const MemoryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(memoryWorkspaceProvider);
    final notebooks = workspace.notebooks;
    final pinsState = ref.watch(notebookPinsProvider);
    final defaultIds =
        notebooks.take(3).map((n) => n.id).toList(growable: false);
    final pinnedIds = pinsState.customized ? pinsState.pins : defaultIds.toSet();
    final pinned = notebooks
        .where((n) => pinnedIds.contains(n.id))
        .toList(growable: false);
    void togglePin(String id) =>
        ref.read(notebookPinsProvider.notifier).toggle(id, defaultIds);
    final liveLabel = workspace.liveAgentNames.isNotEmpty
        ? workspace.liveAgentNames.take(2).join(' + ')
        : workspace.liveConnections > 0
            ? '${workspace.liveConnections} agent connection${workspace.liveConnections == 1 ? '' : 's'}'
            : 'Memory bank ready';

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(compact: true),
        actions: [
          const SubscriptionBalanceButton(),
          IconButton(
            onPressed: () => _showSearch(context, notebooks),
            tooltip: 'Search memories',
            icon: const Icon(LucideIcons.search, size: 19),
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: const MemoryNavigationBar(
        selected: MemoryDestination.memory,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/agents'),
        tooltip: 'Connect an agent',
        child: const Icon(LucideIcons.plus),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(memoryWorkspaceProvider.notifier).refresh(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: DigitalLibrarian.surfaceLow.withValues(alpha: 0.72),
                  border: Border(
                    top: BorderSide(
                      color: DigitalLibrarian.outline.withValues(alpha: 0.35),
                    ),
                    bottom: BorderSide(
                      color: DigitalLibrarian.outline.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                child: LiveStatus(
                  label: workspace.liveConnections > 0
                      ? 'Live: $liveLabel'
                      : liveLabel,
                  active: workspace.liveConnections > 0,
                  compact: true,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1080),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TechnicalLabel(
                          'Pinned notebooks',
                          trailing: TextButton(
                            onPressed: () => context.go('/agents'),
                            child: const Text('MANAGE'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _PinnedNotebooks(
                          notebooks: pinned,
                          loading: workspace.isLoading && notebooks.isEmpty,
                          onUnpin: togglePin,
                        ),
                        const SizedBox(height: 24),
                        TechnicalLabel(
                          'All memories',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          trailing: Text(
                            '${workspace.sourceCount} SOURCES',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: DigitalLibrarian.secondary,
                                  fontSize: 9,
                                ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (workspace.error != null && notebooks.isEmpty)
                          _DashboardMessage(
                            icon: LucideIcons.alertCircle,
                            title: 'Could not load memory',
                            message: workspace.error!,
                          )
                        else if (!workspace.isLoading && notebooks.isEmpty)
                          const _DashboardMessage(
                            icon: LucideIcons.database,
                            title: 'Your memory bank is ready',
                            message:
                                'Connect a third-party agent through MCP. Its first notebook will appear here automatically.',
                          )
                        else
                          ...notebooks.map(
                            (notebook) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _MemoryRow(
                                notebook: notebook,
                                isPinned: pinnedIds.contains(notebook.id),
                                onTogglePin: () => togglePin(notebook.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearch(
    BuildContext context,
    List<MemoryNotebook> notebooks,
  ) {
    showSearch<void>(
      context: context,
      delegate: _MemorySearchDelegate(notebooks),
    );
  }
}

class _PinnedNotebooks extends StatelessWidget {
  const _PinnedNotebooks({
    required this.notebooks,
    required this.loading,
    required this.onUnpin,
  });

  final List<MemoryNotebook> notebooks;
  final bool loading;
  final ValueChanged<String> onUnpin;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        height: 132,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final count = notebooks.isEmpty ? 1 : notebooks.length;
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (notebooks.isEmpty) {
            return SizedBox(
              width: 280,
              child: DigitalLibrarianPanel(
                color: DigitalLibrarian.surfaceLowest,
                borderColor: DigitalLibrarian.outline.withValues(alpha: 0.55),
                onTap: () => context.go('/agents'),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.plus, size: 20),
                    SizedBox(height: 8),
                    TechnicalLabel('Connect your first notebook'),
                  ],
                ),
              ),
            );
          }
          final notebook = notebooks[index];
          return SizedBox(
            width: 280,
            child: DigitalLibrarianPanel(
              onTap: () => context.push('/memory-notebooks/${notebook.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notebook.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () => onUnpin(notebook.id),
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            LucideIcons.pinOff,
                            size: 15,
                            color: DigitalLibrarian.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Updated ${relativeMemoryTime(notebook.updatedAt)}',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(fontSize: 9),
                        ),
                      ),
                      _AgentCount(notebook: notebook),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MemoryRow extends StatelessWidget {
  const _MemoryRow({
    required this.notebook,
    this.isPinned = false,
    this.onTogglePin,
  });

  final MemoryNotebook notebook;
  final bool isPinned;
  final VoidCallback? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final session = notebook.session;
    return DigitalLibrarianPanel(
      padding: const EdgeInsets.all(14),
      onTap: () => context.push('/memory-notebooks/${notebook.id}'),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: notebook.isAgentNotebook
                  ? DigitalLibrarian.primaryStrong.withValues(alpha: 0.16)
                  : DigitalLibrarian.tertiary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              notebook.isAgentNotebook ? LucideIcons.bot : LucideIcons.bookOpen,
              size: 18,
              color: notebook.isAgentNotebook
                  ? DigitalLibrarian.primary
                  : DigitalLibrarian.tertiary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        notebook.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DigitalLibrarian.surfaceLowest,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: DigitalLibrarian.outline,
                        ),
                      ),
                      child: Text(
                        notebook.isAgentNotebook ? '#AGENT' : '#TOPIC',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DigitalLibrarian.tertiary,
                              fontSize: 8,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  notebook.description.isNotEmpty
                      ? notebook.description
                      : '${notebook.sourceCount} sources · ${session.displayAgentName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              LiveStatus(
                label: session.websocketConnected ? 'LIVE' : 'STORED',
                active: session.websocketConnected,
                compact: true,
              ),
              const SizedBox(height: 6),
              Text(
                relativeMemoryTime(notebook.updatedAt),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontSize: 8),
              ),
            ],
          ),
          if (onTogglePin != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onTogglePin,
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isPinned ? LucideIcons.pin : LucideIcons.pinOff,
                  size: 16,
                  color: isPinned
                      ? DigitalLibrarian.secondary
                      : DigitalLibrarian.primary.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AgentCount extends StatelessWidget {
  const _AgentCount({required this.notebook});

  final MemoryNotebook notebook;

  @override
  Widget build(BuildContext context) {
    final count = notebook.session.connectedClients.isNotEmpty
        ? notebook.session.connectedClients.length
        : notebook.isAgentNotebook
            ? 1
            : 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: DigitalLibrarian.surfaceHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.bot, size: 11),
          const SizedBox(width: 4),
          Text(
            '$count Agent${count == 1 ? '' : 's'}',
            style:
                Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 8),
          ),
        ],
      ),
    );
  }
}

class _DashboardMessage extends StatelessWidget {
  const _DashboardMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DigitalLibrarianPanel(
      color: DigitalLibrarian.surfaceLow,
      child: Column(
        children: [
          Icon(icon, color: DigitalLibrarian.primary),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _MemorySearchDelegate extends SearchDelegate<void> {
  _MemorySearchDelegate(this.notebooks);

  final List<MemoryNotebook> notebooks;

  @override
  String get searchFieldLabel => 'Search memory notebooks';

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            onPressed: () => query = '',
            icon: const Icon(LucideIcons.x),
          ),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        onPressed: () => close(context, null),
        icon: const Icon(LucideIcons.arrowLeft),
      );

  @override
  Widget buildResults(BuildContext context) => _results(context);

  @override
  Widget buildSuggestions(BuildContext context) => _results(context);

  Widget _results(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    final matches = notebooks
        .where(
          (notebook) =>
              normalized.isEmpty ||
              notebook.title.toLowerCase().contains(normalized) ||
              notebook.description.toLowerCase().contains(normalized) ||
              notebook.session.displayAgentName
                  .toLowerCase()
                  .contains(normalized),
        )
        .toList(growable: false);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: matches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _MemoryRow(
        notebook: matches[index],
      ),
    );
  }
}
