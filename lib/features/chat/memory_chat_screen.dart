import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api/api_service.dart';
import '../../ui/digital_librarian.dart';
import '../memory/memory_models.dart';
import '../settings/agent_connections_screen.dart';
import 'memory_chat_panel.dart';

class MemoryChatScreen extends ConsumerStatefulWidget {
  const MemoryChatScreen({
    super.key,
    this.initialNotebookId,
  });

  final String? initialNotebookId;

  @override
  ConsumerState<MemoryChatScreen> createState() => _MemoryChatScreenState();
}

class _MemoryChatScreenState extends ConsumerState<MemoryChatScreen> {
  String? _selectedNotebookId;
  String? _loadedNotebookId;
  Future<MemoryNotebookDetail>? _detail;

  @override
  void initState() {
    super.initState();
    _selectedNotebookId = widget.initialNotebookId;
  }

  Future<MemoryNotebookDetail> _load(String notebookId) async {
    final response =
        await ref.read(apiServiceProvider).getMemoryNotebook(notebookId);
    return MemoryNotebookDetail.fromJson(response);
  }

  void _select(String notebookId) {
    setState(() {
      _selectedNotebookId = notebookId;
      _loadedNotebookId = notebookId;
      _detail = _load(notebookId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final workspace = ref.watch(memoryWorkspaceProvider);
    final notebooks = workspace.notebooks;
    final selectedId = _selectedNotebookId ??
        (notebooks.isNotEmpty ? notebooks.first.id : null);

    if (selectedId != null && _loadedNotebookId != selectedId) {
      _loadedNotebookId = selectedId;
      _detail = _load(selectedId);
    }

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(
          compact: true,
          eyebrow: 'Shared memory chat',
        ),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(memoryWorkspaceProvider.notifier).refresh(),
            tooltip: 'Refresh notebooks',
            icon: const Icon(LucideIcons.refreshCw, size: 18),
          ),
          const SizedBox(width: 6),
        ],
      ),
      bottomNavigationBar: const MemoryNavigationBar(
        selected: MemoryDestination.chat,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: DigitalLibrarian.surfaceLow.withValues(alpha: 0.74),
              border: Border(
                bottom: BorderSide(
                  color: DigitalLibrarian.outline.withValues(alpha: 0.45),
                ),
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 920),
                child: Row(
                  children: [
                    const Icon(
                      LucideIcons.sparkles,
                      color: DigitalLibrarian.secondary,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        selectedId == null
                            ? 'No active memory context'
                            : 'Active context: notebook memory',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DigitalLibrarian.secondary,
                              fontSize: 9,
                            ),
                      ),
                    ),
                    LiveStatus(
                      label:
                          workspace.liveConnections > 0 ? 'SYNCING' : 'STORED',
                      active: workspace.liveConnections > 0,
                      compact: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildContent(
              context,
              workspace: workspace,
              notebooks: notebooks,
              selectedId: selectedId,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context, {
    required MemoryWorkspaceState workspace,
    required List<MemoryNotebook> notebooks,
    required String? selectedId,
  }) {
    if (workspace.isLoading && notebooks.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (notebooks.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DigitalLibrarianPanel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    LucideIcons.messagesSquare,
                    size: 30,
                    color: DigitalLibrarian.primary,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No notebook to talk with yet',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    workspace.error ??
                        'Once an agent stores memory, you can ask questions grounded only in that notebook.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: DropdownButtonFormField<String>(
                initialValue: selectedId,
                decoration: const InputDecoration(
                  prefixIcon: Icon(LucideIcons.bookOpen, size: 18),
                  labelText: 'Notebook',
                ),
                items: notebooks
                    .map(
                      (notebook) => DropdownMenuItem(
                        value: notebook.id,
                        child: Text(
                          notebook.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) _select(value);
                },
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: FutureBuilder<MemoryNotebookDetail>(
                future: _detail,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  if (snapshot.hasError || !snapshot.hasData) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              LucideIcons.alertCircle,
                              color: Color(0xFFFFB4AB),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Could not open this memory',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              snapshot.error.toString(),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return MemoryChatPanel(
                    key: ValueKey(snapshot.data!.notebook.id),
                    notebook: snapshot.data!.notebook,
                    sources: snapshot.data!.sources,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
