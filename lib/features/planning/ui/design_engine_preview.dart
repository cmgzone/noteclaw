import 'package:flutter/material.dart';

import '../models/design_document.dart';

class DesignEnginePreview extends StatefulWidget {
  final DesignDocument document;
  final String? selectedScreenId;
  final String? selectedNodeId;
  final ValueChanged<String>? onScreenSelected;
  final void Function(String screenId, String nodeId)? onNodeSelected;

  const DesignEnginePreview({
    super.key,
    required this.document,
    this.selectedScreenId,
    this.selectedNodeId,
    this.onScreenSelected,
    this.onNodeSelected,
  });

  @override
  State<DesignEnginePreview> createState() => _DesignEnginePreviewState();
}

class _DesignEnginePreviewState extends State<DesignEnginePreview> {
  int _selectedScreenIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncSelectedScreenIndex();
  }

  @override
  void didUpdateWidget(covariant DesignEnginePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedScreenId != widget.selectedScreenId ||
        oldWidget.document.screens.length != widget.document.screens.length) {
      _syncSelectedScreenIndex();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _PreviewPalette.fromTheme(widget.document.theme);
    final screens = widget.document.screens;
    final screen = screens.isEmpty
        ? null
        : screens[_selectedScreenIndex.clamp(0, screens.length - 1)];

    if (screen == null) {
      return const Center(child: Text('No structured screens available'));
    }

    return Container(
      color: palette.background,
      child: Column(
        children: [
          if (screens.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(screens.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(screens[index].name),
                            selected: index == _selectedScreenIndex,
                            onSelected: (_) {
                              setState(() => _selectedScreenIndex = index);
                              widget.onScreenSelected?.call(screens[index].id);
                            },
                          ),
                        );
                  }),
                ),
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (screen.name.isNotEmpty)
                    Text(
                      screen.name,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  if (screen.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      screen.description,
                      style: TextStyle(color: palette.mutedText, height: 1.5),
                    ),
                    const SizedBox(height: 16),
                  ],
                  ...screen.nodes
                      .map((node) => _buildNode(screen.id, node, palette)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNode(
    String screenId,
    DesignNodeSpec node,
    _PreviewPalette palette,
  ) {
    switch (node.type) {
      case 'hero':
        return _wrap(
          palette: palette,
          screenId: screenId,
          nodeId: node.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (node.label.isNotEmpty)
                Text(
                  node.label,
                  style: TextStyle(
                    color: palette.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (node.label.isNotEmpty) const SizedBox(height: 10),
              Text(
                node.title,
                style: TextStyle(
                  color: palette.text,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (node.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  node.subtitle,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (node.body.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  node.body,
                  style: TextStyle(color: palette.mutedText, height: 1.55),
                ),
              ],
              if (node.items.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: node.items.take(2).toList().asMap().entries.map((entry) {
                    final item = entry.value;
                    final label =
                        item.title.isNotEmpty ? item.title : item.label;
                    return _actionChip(
                      label,
                      palette,
                      filled: entry.key == 0,
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      case 'stats_row':
        return _wrap(
          palette: palette,
          screenId: screenId,
          nodeId: node.id,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: node.items.map((item) {
                return Container(
                  width: 140,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: palette.background,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.value.isNotEmpty ? item.value : item.title,
                        style: TextStyle(
                          color: palette.text,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.label.isNotEmpty ? item.label : item.subtitle,
                        style: TextStyle(color: palette.mutedText),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        );
      case 'feature_grid':
        return _wrap(
          palette: palette,
          screenId: screenId,
          nodeId: node.id,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 12) / 2;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: node.items.map((item) {
                  return SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.background,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title.isNotEmpty ? item.title : item.label,
                            style: TextStyle(
                              color: palette.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (item.subtitle.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              item.subtitle,
                              style: TextStyle(
                                color: palette.mutedText,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        );
      case 'card_list':
      case 'timeline':
      case 'content':
      case 'quote':
      case 'cta':
      case 'action_bar':
      case 'form':
      default:
        return _wrap(
          palette: palette,
          screenId: screenId,
          nodeId: node.id,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (node.title.isNotEmpty)
                Text(
                  node.title,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              if (node.subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  node.subtitle,
                  style: TextStyle(
                    color: palette.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (node.body.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  node.body,
                  style: TextStyle(color: palette.mutedText, height: 1.55),
                ),
              ],
              if (node.items.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...node.items.map((item) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: palette.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title.isNotEmpty ? item.title : item.label,
                                style: TextStyle(
                                  color: palette.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (item.subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  item.subtitle,
                                  style: TextStyle(
                                    color: palette.mutedText,
                                    height: 1.45,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        );
    }
  }

  Widget _wrap({
    required _PreviewPalette palette,
    required String screenId,
    required String nodeId,
    required Widget child,
  }) {
    final isSelected =
        widget.selectedScreenId == screenId && widget.selectedNodeId == nodeId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(palette.radius),
          onTap: () => widget.onNodeSelected?.call(screenId, nodeId),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(palette.radius),
              border: Border.all(
                color: isSelected ? palette.primary : palette.outline,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  void _syncSelectedScreenIndex() {
    final targetId = widget.selectedScreenId;
    if (targetId == null || widget.document.screens.isEmpty) {
      _selectedScreenIndex = 0;
      return;
    }

    final index =
        widget.document.screens.indexWhere((screen) => screen.id == targetId);
    _selectedScreenIndex = index >= 0 ? index : 0;
  }

  Widget _actionChip(
    String label,
    _PreviewPalette palette, {
    required bool filled,
  }) {
    final background = filled ? palette.accent : Colors.transparent;
    final foreground = filled
        ? (background.computeLuminance() > 0.5 ? Colors.black : Colors.white)
        : palette.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: filled ? null : Border.all(color: palette.outline),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PreviewPalette {
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color text;
  final Color mutedText;
  final Color outline;
  final double radius;

  const _PreviewPalette({
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.text,
    required this.mutedText,
    required this.outline,
    required this.radius,
  });

  factory _PreviewPalette.fromTheme(DesignThemeSpec theme) {
    final primary = _parseHexColor(theme.primaryColor, const Color(0xFF2563EB));
    final accent = _parseHexColor(theme.accentColor, const Color(0xFFF59E0B));
    final background =
        _parseHexColor(theme.backgroundColor, const Color(0xFFF8FAFC));
    final surface = _parseHexColor(theme.surfaceColor, Colors.white);
    final text = _parseHexColor(theme.textColor, const Color(0xFF0F172A));
    return _PreviewPalette(
      primary: primary,
      accent: accent,
      background: background,
      surface: surface,
      text: text,
      mutedText: Color.alphaBlend(
        text.withValues(alpha: 0.55),
        background,
      ),
      outline: Color.alphaBlend(
        primary.withValues(alpha: 0.12),
        background,
      ),
      radius: theme.radius <= 0 ? 20 : theme.radius,
    );
  }
}

Color _parseHexColor(String value, Color fallback) {
  final normalized = value.trim().replaceAll('#', '');
  if (normalized.isEmpty) return fallback;
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (hex.length != 8) return fallback;
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null ? fallback : Color(parsed);
}
