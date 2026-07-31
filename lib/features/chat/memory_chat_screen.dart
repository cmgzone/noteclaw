import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/api/api_service.dart';
import '../../ui/digital_librarian.dart';
import '../../ui/forge.dart';
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
      backgroundColor: DigitalLibrarian.background,
      bottomNavigationBar: const MemoryNavigationBar(
        selected: MemoryDestination.chat,
      ),
      body: ForgeBackground(
        glowTwo: DigitalLibrarian.primaryStrong,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Header(
                hasContext: selectedId != null,
                liveConnections: workspace.liveConnections,
                onRefresh: () =>
                    ref.read(memoryWorkspaceProvider.notifier).refresh(),
              ),
              if (notebooks.isNotEmpty)
                _NotebookStrip(
                  notebooks: notebooks,
                  selectedId: selectedId,
                  onSelect: _select,
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
        ),
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
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: DigitalLibrarian.primaryStrong.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color:
                        DigitalLibrarian.primaryStrong.withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(LucideIcons.messagesSquare,
                    size: 32, color: DigitalLibrarian.primary),
              ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
              const SizedBox(height: 22),
              Text('No notebook to talk with yet',
                  style: Forge.display(context, size: 21)),
              const SizedBox(height: 8),
              Text(
                workspace.error ??
                    'Once an agent stores memory, you can ask questions grounded only in that notebook.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: DigitalLibrarian.primary.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FutureBuilder<MemoryNotebookDetail>(
      future: _detail,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.alertCircle,
                      color: Color(0xFFF27E9D), size: 30),
                  const SizedBox(height: 10),
                  Text('Could not open this memory',
                      style: Forge.display(context, size: 18)),
                  const SizedBox(height: 6),
                  Text(
                    snapshot.error.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: DigitalLibrarian.primary.withValues(alpha: 0.5),
                    ),
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
    );
  }
}

class _Header extends StatelessWidget {
  final bool hasContext;
  final int liveConnections;
  final VoidCallback onRefresh;

  const _Header({
    required this.hasContext,
    required this.liveConnections,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ForgeEyebrow('SHARED MEMORY CHAT'),
                const SizedBox(height: 6),
                Text('Talk to your memory',
                    style: Forge.display(context, size: 27)),
              ],
            ),
          ),
          ForgeStatus(
            label: liveConnections > 0 ? 'Syncing' : 'Stored',
            active: liveConnections > 0,
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRefresh,
            tooltip: 'Refresh notebooks',
            icon: Icon(
              LucideIcons.refreshCw,
              size: 17,
              color: DigitalLibrarian.primary.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms).slideX(begin: -0.05, end: 0);
  }
}

/// Horizontal strip of notebook chips — a lightweight "chat list".
class _NotebookStrip extends StatelessWidget {
  final List<MemoryNotebook> notebooks;
  final String? selectedId;
  final ValueChanged<String> onSelect;

  const _NotebookStrip({
    required this.notebooks,
    required this.selectedId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: notebooks.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final notebook = notebooks[index];
          final selected = notebook.id == selectedId;
          return GestureDetector(
            onTap: () => onSelect(notebook.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? DigitalLibrarian.primaryStrong.withValues(alpha: 0.2)
                    : DigitalLibrarian.surfaceLow,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: selected
                      ? DigitalLibrarian.primaryStrong.withValues(alpha: 0.6)
                      : DigitalLibrarian.outline.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    selected ? LucideIcons.bookOpenCheck : LucideIcons.bookOpen,
                    size: 14,
                    color: selected
                        ? DigitalLibrarian.primary
                        : DigitalLibrarian.primary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      notebook.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? DigitalLibrarian.primary
                            : DigitalLibrarian.primary.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).animate().fadeIn(delay: 120.ms, duration: 380.ms);
  }
}
