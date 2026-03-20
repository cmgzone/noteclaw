import 'package:flutter/material.dart';

import '../models/design_document.dart';

class DesignNodeInspector extends StatefulWidget {
  final DesignScreenSpec? screen;
  final DesignNodeSpec? node;
  final ValueChanged<DesignNodeSpec> onApply;
  final VoidCallback? onClearSelection;
  final Future<void> Function()? onRegenerate;
  final bool isRegenerating;

  const DesignNodeInspector({
    super.key,
    required this.screen,
    required this.node,
    required this.onApply,
    this.onClearSelection,
    this.onRegenerate,
    this.isRegenerating = false,
  });

  @override
  State<DesignNodeInspector> createState() => _DesignNodeInspectorState();
}

class _DesignNodeInspectorState extends State<DesignNodeInspector> {
  late final TextEditingController _titleController;
  late final TextEditingController _subtitleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _subtitleController = TextEditingController();
    _bodyController = TextEditingController();
    _labelController = TextEditingController();
    _syncControllers();
  }

  @override
  void didUpdateWidget(covariant DesignNodeInspector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      _syncControllers();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _bodyController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final node = widget.node;
    final screen = widget.screen;

    if (node == null || screen == null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIconsForInspector.edit3, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Node Inspector',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Switch to Engine preview and tap a block to edit its content.',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIconsForInspector.edit3, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Editing ${node.type}',
                        style: text.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Screen: ${screen.name}',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onClearSelection != null)
                  TextButton(
                    onPressed: widget.onClearSelection,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildField(
              controller: _titleController,
              label: 'Title',
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _subtitleController,
              label: 'Subtitle',
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _labelController,
              label: 'Label',
              maxLines: 1,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _bodyController,
              label: 'Body',
              maxLines: 5,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.onRegenerate != null)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.isRegenerating ? null : _regenerate,
                      icon: widget.isRegenerating
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        widget.isRegenerating
                            ? 'Regenerating...'
                            : 'Regenerate Section',
                      ),
                    ),
                  ),
                if (widget.onRegenerate != null) const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: widget.isRegenerating ? null : _apply,
                    child: const Text('Apply Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required int maxLines,
  }) {
    return TextField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  void _syncControllers() {
    final node = widget.node;
    _titleController.text = node?.title ?? '';
    _subtitleController.text = node?.subtitle ?? '';
    _bodyController.text = node?.body ?? '';
    _labelController.text = node?.label ?? '';
  }

  void _apply() {
    final node = widget.node;
    if (node == null) return;
    widget.onApply(
      node.copyWith(
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim(),
        body: _bodyController.text.trim(),
        label: _labelController.text.trim(),
      ),
    );
  }

  Future<void> _regenerate() async {
    final callback = widget.onRegenerate;
    if (callback == null) return;
    await callback();
  }
}

class LucideIconsForInspector {
  static const IconData edit3 = Icons.edit_outlined;
}
