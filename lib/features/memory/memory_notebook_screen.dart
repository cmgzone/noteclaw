import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api/api_service.dart';
import '../../ui/digital_librarian.dart';
import 'memory_models.dart';

class MemoryNotebookScreen extends ConsumerStatefulWidget {
  const MemoryNotebookScreen({
    super.key,
    required this.notebookId,
  });

  final String notebookId;

  @override
  ConsumerState<MemoryNotebookScreen> createState() =>
      _MemoryNotebookScreenState();
}

class _MemoryNotebookScreenState extends ConsumerState<MemoryNotebookScreen> {
  late Future<MemoryNotebookDetail> _detail;
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    _detail = _load();
  }

  Future<MemoryNotebookDetail> _load() async {
    final response =
        await ref.read(apiServiceProvider).getMemoryNotebook(widget.notebookId);
    return MemoryNotebookDetail.fromJson(response);
  }

  Future<void> _refresh() async {
    setState(() => _detail = _load());
    await _detail;
  }

  Future<void> _editMemory(
    MemoryNotebookDetail detail,
    MemorySource source,
  ) async {
    if (!source.isMemorySource || detail.notebook.session.id.isEmpty) return;
    final controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(source.memory),
    );
    String? validationError;
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit ${source.namespace} memory'),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Edit the JSON object. Version checking prevents overwriting a newer agent update.'),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 12,
                  maxLines: 20,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    errorText: validationError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                try {
                  final decoded = jsonDecode(controller.text);
                  if (decoded is! Map) {
                    throw const FormatException('Memory must be a JSON object');
                  }
                  Navigator.pop(dialogContext, true);
                } catch (error) {
                  setDialogState(
                      () => validationError = 'Invalid JSON: $error');
                }
              },
              child: const Text('Save memory'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true || !mounted) {
      controller.dispose();
      return;
    }

    try {
      final memory =
          Map<String, dynamic>.from(jsonDecode(controller.text) as Map);
      await ref.read(apiServiceProvider).updateAgentMemory(
            agentSessionId: detail.notebook.session.id,
            namespace: source.namespace,
            mode: 'replace',
            memory: memory,
            expectedVersion: source.version,
            actorIdentifier: 'noteclaw_flutter',
          );
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Memory updated')));
      }
    } catch (error) {
      if (mounted) {
        final message = error.toString().contains('409')
            ? 'This memory changed while you were editing. Refresh and try again.'
            : 'Failed to update memory: $error';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        titleSpacing: 16,
        title: const NoteClawHeader(
          compact: true,
          eyebrow: 'Memory notebook',
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh memory',
            icon: const Icon(LucideIcons.refreshCw, size: 19),
          ),
          const SizedBox(width: 10),
        ],
      ),
      bottomNavigationBar: const MemoryToolNavigationBar(
        selected: MemoryToolDestination.notebook,
      ),
      body: FutureBuilder<MemoryNotebookDetail>(
        future: _detail,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return _LoadError(
              message: _friendlyError(snapshot.error ?? 'Notebook not found'),
              onRetry: _refresh,
            );
          }

          final detail = snapshot.data!;
          final sources = detail.visibleSources;
          final selected = sources.isEmpty
              ? null
              : sources.firstWhere(
                  (source) => source.id == _selectedSourceId,
                  orElse: () => sources.first,
                );

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 44),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NotebookHeader(detail: detail),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: () => context.push(
                                '/memory-notebooks/${detail.notebook.id}/chat',
                              ),
                              icon: const Icon(
                                LucideIcons.messagesSquare,
                                size: 18,
                              ),
                              label: const Text('Chat with this memory'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => context.push(
                                '/visual-studio',
                                extra: {
                                  'notebookId': detail.notebook.id,
                                  'notebookTitle': detail.notebook.title,
                                },
                              ),
                              icon: const Icon(
                                LucideIcons.wand2,
                                size: 18,
                              ),
                              label: const Text('Visual Studio'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        _MemoryBrowser(
                          sources: sources,
                          selected: selected,
                          onSelected: (source) => setState(
                            () => _selectedSourceId = source.id,
                          ),
                          onEdit: (source) => _editMemory(detail, source),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({required this.detail});

  final MemoryNotebookDetail detail;

  @override
  Widget build(BuildContext context) {
    final notebook = detail.notebook;
    final session = notebook.session;
    final scheme = Theme.of(context).colorScheme;

    return _Panel(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final copy = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  LucideIcons.bookOpen,
                  size: 23,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notebook.title,
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                              ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notebook.description.isEmpty
                          ? 'Durable memory written by ${session.displayAgentName}.'
                          : notebook.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          );

          final metadata = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                icon: LucideIcons.layers,
                label:
                    '${detail.visibleSources.length} source${detail.visibleSources.length == 1 ? '' : 's'}',
              ),
              _Badge(
                icon: LucideIcons.bot,
                label: session.displayAgentName,
              ),
              _Badge(
                icon: LucideIcons.radio,
                label: session.websocketConnected
                    ? '${session.websocketConnectionCount} live'
                    : 'Stored',
                active: session.websocketConnected,
              ),
            ],
          );

          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 18),
                metadata,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: copy),
              const SizedBox(width: 20),
              metadata,
            ],
          );
        },
      ),
    );
  }
}

class _MemoryBrowser extends StatelessWidget {
  const _MemoryBrowser({
    required this.sources,
    required this.selected,
    required this.onSelected,
    required this.onEdit,
  });

  final List<MemorySource> sources;
  final MemorySource? selected;
  final ValueChanged<MemorySource> onSelected;
  final ValueChanged<MemorySource> onEdit;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) {
      return const _Panel(
        child: SizedBox(
          height: 300,
          child: _EmptyMemory(),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 660) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SourcePicker(
                sources: sources,
                selected: selected!,
                onSelected: onSelected,
              ),
              const SizedBox(height: 12),
              _SourceViewer(source: selected!, onEdit: onEdit),
            ],
          );
        }

        return SizedBox(
          height: 650,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 230,
                child: _SourcePicker(
                  sources: sources,
                  selected: selected!,
                  onSelected: onSelected,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _SourceViewer(source: selected!, onEdit: onEdit)),
            ],
          ),
        );
      },
    );
  }
}

class _SourcePicker extends StatelessWidget {
  const _SourcePicker({
    required this.sources,
    required this.selected,
    required this.onSelected,
  });

  final List<MemorySource> sources;
  final MemorySource selected;
  final ValueChanged<MemorySource> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 7, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sources',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  '${sources.length}',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (MediaQuery.sizeOf(context).width < 660)
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return SizedBox(
                    width: 190,
                    child: _SourceItem(
                      source: source,
                      selected: source.id == selected.id,
                      onTap: () => onSelected(source),
                    ),
                  );
                },
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: sources.length,
                separatorBuilder: (_, __) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final source = sources[index];
                  return _SourceItem(
                    source: source,
                    selected: source.id == selected.id,
                    onTap: () => onSelected(source),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _SourceItem extends StatelessWidget {
  const _SourceItem({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final MemorySource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.11)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                source.isMemorySource
                    ? LucideIcons.code2
                    : LucideIcons.fileText,
                size: 17,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      source.isMemorySource
                          ? source.namespace
                          : source.sourceType.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceViewer extends StatelessWidget {
  const _SourceViewer({required this.source, required this.onEdit});

  final MemorySource source;
  final ValueChanged<MemorySource> onEdit;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: source.content));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memory source copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final memory = _memoryPayload(source);

    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 14, 8, 13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        source.title,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        source.isMemorySource
                            ? '${source.namespace} · version ${source.version}'
                            : source.sourceType.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed:
                      source.isMemorySource ? () => onEdit(source) : null,
                  tooltip: 'Edit memory',
                  icon: const Icon(LucideIcons.pencil, size: 17),
                ),
                IconButton(
                  onPressed: () => _copy(context),
                  tooltip: 'Copy source',
                  icon: const Icon(LucideIcons.copy, size: 17),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          Container(
            constraints: const BoxConstraints(minHeight: 320, maxHeight: 570),
            child: memory.isEmpty
                ? Center(
                    child: Text(
                      'This source does not contain any memory fields yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : Scrollbar(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: _StructuredMemoryView(memory: memory),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

Map<String, dynamic> _memoryPayload(MemorySource source) {
  if (source.memory.isNotEmpty) return source.memory;
  final content = source.content.trim();
  if (content.isEmpty) return const {};
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    // Plain text sources are wrapped below so they still render readably.
  }
  return {'content': source.content};
}

dynamic _normalizeMemoryValue(dynamic value) {
  dynamic current = value;
  for (var attempt = 0; attempt < 2; attempt++) {
    if (current is! String) break;
    final trimmed = current.trim();
    final looksLikeJson = (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']'));
    if (!looksLikeJson) break;
    try {
      current = jsonDecode(trimmed);
    } catch (_) {
      break;
    }
  }
  return current;
}

String _readableMemoryLabel(String value) {
  return value
      .replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');
}

String _memoryValueType(dynamic value) {
  final normalized = _normalizeMemoryValue(value);
  if (normalized == null) return 'empty';
  if (normalized is List) return '${normalized.length} items';
  if (normalized is Map) return '${normalized.length} fields';
  if (normalized is bool) return 'yes / no';
  if (normalized is num) return 'number';
  return 'text';
}

class _StructuredMemoryView extends StatelessWidget {
  const _StructuredMemoryView({required this.memory});

  final Map<String, dynamic> memory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < memory.entries.length; index++) ...[
          _MemoryFieldCard(
            name: memory.entries.elementAt(index).key,
            value: memory.entries.elementAt(index).value,
          ),
          if (index < memory.entries.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _MemoryFieldCard extends StatelessWidget {
  const _MemoryFieldCard({
    required this.name,
    required this.value,
  });

  final String name;
  final dynamic value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _readableMemoryLabel(name),
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.65,
                ),
              ),
            ),
            Text(
              _memoryValueType(value),
              style: TextStyle(
                color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
                fontFamily: 'monospace',
                fontSize: 9,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        _MemoryValueView(value: value),
      ],
    );
  }
}

class _MemoryValueView extends StatelessWidget {
  const _MemoryValueView({
    required this.value,
    this.depth = 0,
  });

  final dynamic value;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final normalized = _normalizeMemoryValue(value);

    if (normalized == null) {
      return Text(
        'No value',
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (normalized is bool) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: normalized
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            normalized ? 'Yes' : 'No',
            style: TextStyle(
              color: normalized ? scheme.primary : scheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    if (normalized is String || normalized is num) {
      return SelectableText(
        normalized.toString(),
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.9),
          fontSize: 13,
          height: 1.5,
        ),
      );
    }

    if (depth >= 4) {
      return SelectableText(
        const JsonEncoder.withIndent('  ').convert(normalized),
        style: TextStyle(
          color: scheme.onSurfaceVariant,
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.45,
        ),
      );
    }

    if (normalized is List) {
      if (normalized.isEmpty) {
        return Text(
          'No items',
          style: TextStyle(color: scheme.onSurfaceVariant),
        );
      }
      final visibleItems = normalized.take(50).toList(growable: false);
      return Column(
        children: [
          for (var index = 0; index < visibleItems.length; index++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index + 1}.',
                      style: TextStyle(
                        color: scheme.primary,
                        fontFamily: 'monospace',
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _MemoryValueView(
                      value: visibleItems[index],
                      depth: depth + 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (normalized.length > visibleItems.length) ...[
            const SizedBox(height: 8),
            Text(
              '${normalized.length - visibleItems.length} additional items are hidden.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ],
      );
    }

    final map =
        (normalized as Map).map((key, item) => MapEntry(key.toString(), item));
    if (map.isEmpty) {
      return Text(
        'No fields',
        style: TextStyle(color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < map.entries.length; index++) ...[
          Text(
            _readableMemoryLabel(map.entries.elementAt(index).key),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.45,
            ),
          ),
          const SizedBox(height: 5),
          _MemoryValueView(
            value: map.entries.elementAt(index).value,
            depth: depth + 1,
          ),
          if (index < map.entries.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class LegacyMemoryChatPanel extends ConsumerStatefulWidget {
  const LegacyMemoryChatPanel({
    super.key,
    required this.notebook,
    required this.sources,
  });

  final MemoryNotebook notebook;
  final List<MemorySource> sources;

  @override
  ConsumerState<LegacyMemoryChatPanel> createState() => _MemoryChatPanelState();
}

class _MemoryChatPanelState extends ConsumerState<LegacyMemoryChatPanel> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<MemoryChatMessage> _messages = [];
  bool _isSending = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestedPrompt]) async {
    final message = (suggestedPrompt ?? _controller.text).trim();
    if (message.isEmpty || _isSending) return;

    final history = _messages.map((item) => item.toJson()).toList();
    setState(() {
      _messages.add(MemoryChatMessage(role: 'user', content: message));
      _controller.clear();
      _isSending = true;
      _error = null;
    });
    _scrollToEnd();

    try {
      final response =
          await ref.read(apiServiceProvider).chatWithMemoryNotebook(
                notebookId: widget.notebook.id,
                message: message,
                history: history,
              );
      final answer = response['answer']?.toString().trim();
      if (!mounted) return;
      setState(() {
        _messages.add(
          MemoryChatMessage(
            role: 'assistant',
            content: answer?.isNotEmpty == true
                ? answer!
                : 'The memory assistant returned an empty response.',
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
        _scrollToEnd();
      }
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    LucideIcons.messageSquare,
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ask this memory',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        'Grounded in ${widget.sources.length} source${widget.sources.length == 1 ? '' : 's'}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: scheme.outlineVariant),
          SizedBox(
            height: 420,
            child: _messages.isEmpty
                ? _ChatEmpty(onPrompt: _send)
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(14),
                    itemCount: _messages.length + (_isSending ? 1 : 0),
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _ThinkingBubble();
                      }
                      return _MessageBubble(message: _messages[index]);
                    },
                  ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(LucideIcons.alertCircle, size: 15, color: scheme.error),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          Divider(height: 1, color: scheme.outlineVariant),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_isSending,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Ask about this project memory…',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _send,
                  tooltip: 'Send',
                  icon: const Icon(LucideIcons.arrowUp, size: 18),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatEmpty extends StatelessWidget {
  const _ChatEmpty({required this.onPrompt});

  final ValueChanged<String> onPrompt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const prompts = [
      'What is the current project state?',
      'What decisions have the agents made?',
      'What should happen next?',
    ];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            LucideIcons.sparkles,
            size: 25,
            color: scheme.primary,
          ),
          const SizedBox(height: 11),
          Text(
            'Talk to the notebook',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            'Answers use only the stored agent memories in this notebook.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 18),
          ...prompts.map(
            (prompt) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: OutlinedButton(
                onPressed: () => onPrompt(prompt),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                ),
                child: Text(
                  prompt,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final MemoryChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 310),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: message.isUser
              ? scheme.primary
              : scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(13),
            topRight: const Radius.circular(13),
            bottomLeft: Radius.circular(message.isUser ? 13 : 3),
            bottomRight: Radius.circular(message.isUser ? 3 : 13),
          ),
        ),
        child: SelectableText(
          message.content,
          style: TextStyle(
            color: message.isUser ? scheme.onPrimary : scheme.onSurface,
            fontSize: 13,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _ThinkingBubble extends StatelessWidget {
  const _ThinkingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(13),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? const Color(0xFF278E92) : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
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

class _Panel extends StatelessWidget {
  const _Panel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
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

class _EmptyMemory extends StatelessWidget {
  const _EmptyMemory();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.inbox, size: 28, color: scheme.primary),
            const SizedBox(height: 11),
            const Text(
              'This notebook is ready',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 5),
            Text(
              'Its first namespace will appear after an agent writes memory.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.alertCircle, color: scheme.error, size: 30),
              const SizedBox(height: 12),
              const Text(
                'Could not open this notebook',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 17),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _friendlyError(Object error) {
  final message = error.toString();
  return message.startsWith('Exception: ')
      ? message.substring('Exception: '.length)
      : message;
}
