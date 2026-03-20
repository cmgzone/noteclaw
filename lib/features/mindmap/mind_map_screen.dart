import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:screenshot/screenshot.dart';

import '../../core/utils/file_download.dart';
import 'mind_map_node.dart';
import 'mind_map_provider.dart';

/// Screen for viewing a mind map with visual graph
class MindMapScreen extends ConsumerStatefulWidget {
  final String mindMapId;

  const MindMapScreen({super.key, required this.mindMapId});

  @override
  ConsumerState<MindMapScreen> createState() => _MindMapScreenState();
}

class _MindMapScreenState extends ConsumerState<MindMapScreen> {
  static const double _nodeWidth = 156.0;
  static const double _nodeHeight = 72.0;
  static const double _leafSpacing = 184.0;
  static const double _levelSpacing = 164.0;
  static const double _canvasPadding = 260.0;
  static const double _layoutStartX = _canvasPadding + (_nodeWidth / 2);
  static const double _layoutStartY = _canvasPadding + (_nodeHeight / 2);

  bool _showTextMode = false;
  bool _isExporting = false;
  final TransformationController _transformController =
      TransformationController();
  String? _selectedNodeId;

  // Cache node positions to avoid recalculating every frame
  final Map<String, Offset> _nodePositions = {};
  Rect _contentBounds = const Rect.fromLTWH(900, 900, 200, 200);
  String? _autoFittedMindMapId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fitToContent();
    });
  }

  void _fitToContent() {
    if (_nodePositions.isEmpty || !mounted) return;

    final viewportSize = MediaQuery.of(context).size;
    final availableWidth = math.max(200.0, viewportSize.width - 32);
    final availableHeight = math.max(240.0, viewportSize.height - 180);
    final widthScale = availableWidth / _contentBounds.width;
    final heightScale = availableHeight / _contentBounds.height;
    final scale = math.min(widthScale, heightScale).clamp(0.06, 1.1);
    final translateX =
        ((viewportSize.width - (_contentBounds.width * scale)) / 2) -
            (_contentBounds.left * scale);
    final translateY =
        ((availableHeight - (_contentBounds.height * scale)) / 2) +
            88 -
            (_contentBounds.top * scale);

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, scale);
    matrix.setEntry(1, 1, scale);
    matrix.setEntry(2, 2, 1.0);
    matrix.setTranslationRaw(translateX, translateY, 0.0);
    _transformController.value = matrix;
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-calculate layout if needed when dependencies change
  }

  void _calculateLayout(MindMapNode root) {
    _nodePositions.clear();
    _layoutTree(root, 0, _layoutStartX);
    _updateContentBounds();
  }

  double _layoutTree(MindMapNode node, int depth, double nextLeafX) {
    final y = _layoutStartY + (depth * _levelSpacing);

    if (node.children.isEmpty) {
      _nodePositions[node.id] = Offset(nextLeafX, y);
      return nextLeafX + _leafSpacing;
    }

    final childCenters = <double>[];
    var currentX = nextLeafX;

    for (final child in node.children) {
      currentX = _layoutTree(child, depth + 1, currentX);
      final childPosition = _nodePositions[child.id];
      if (childPosition != null) {
        childCenters.add(childPosition.dx);
      }
    }

    final x = childCenters.isEmpty
        ? nextLeafX
        : childCenters.reduce((sum, value) => sum + value) /
            childCenters.length;

    _nodePositions[node.id] = Offset(x, y);
    return currentX;
  }

  void _updateContentBounds() {
    if (_nodePositions.isEmpty) {
      _contentBounds = const Rect.fromLTWH(900, 900, 200, 200);
      return;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final position in _nodePositions.values) {
      minX = math.min(minX, position.dx - (_nodeWidth / 2));
      minY = math.min(minY, position.dy - (_nodeHeight / 2));
      maxX = math.max(maxX, position.dx + (_nodeWidth / 2));
      maxY = math.max(maxY, position.dy + (_nodeHeight / 2));
    }

    const horizontalPadding = 120.0;
    const verticalPadding = 100.0;
    _contentBounds = Rect.fromLTRB(
      minX - horizontalPadding,
      minY - verticalPadding,
      maxX + horizontalPadding,
      maxY + verticalPadding,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mindMaps = ref.watch(mindMapProvider);
    final mindMap = mindMaps.firstWhere(
      (mm) => mm.id == widget.mindMapId,
      orElse: () => MindMap(
        id: '',
        title: 'Not Found',
        notebookId: '',
        rootNode: const MindMapNode(id: 'root', label: 'Empty'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    // Calculate layout once for this build
    if (mindMap.rootNode.label != 'Empty') {
      _calculateLayout(mindMap.rootNode);
      if (_autoFittedMindMapId != mindMap.id) {
        _autoFittedMindMapId = mindMap.id;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_showTextMode) {
            _fitToContent();
          }
        });
      }
    }

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(mindMap.title),
        actions: [
          if (_isExporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            PopupMenuButton<_MindMapExportFormat>(
              tooltip: 'Export Mind Map',
              icon: const Icon(LucideIcons.download),
              onSelected: (format) {
                _exportMindMap(
                  format: format,
                  mindMap: mindMap,
                  scheme: scheme,
                  text: text,
                );
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _MindMapExportFormat.png,
                  child: Text('Download PNG'),
                ),
                PopupMenuItem(
                  value: _MindMapExportFormat.markdown,
                  child: Text('Download Markdown'),
                ),
                PopupMenuItem(
                  value: _MindMapExportFormat.json,
                  child: Text('Download JSON'),
                ),
              ],
            ),
          IconButton(
            icon: Icon(_showTextMode ? LucideIcons.network : LucideIcons.text),
            onPressed: () {
              setState(() => _showTextMode = !_showTextMode);
              if (_showTextMode == false) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _fitToContent();
                });
              }
            },
            tooltip: _showTextMode ? 'Visual Mode' : 'Text Mode',
          ),
          IconButton(
            icon: const Icon(LucideIcons.zoomIn),
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(LucideIcons.zoomOut),
            onPressed: _zoomOut,
          ),
          IconButton(
            icon: const Icon(LucideIcons.maximize2),
            onPressed: _resetZoom,
            tooltip: 'Fit View',
          ),
        ],
      ),
      body: _showTextMode
          ? _buildTextView(mindMap, scheme, text)
          : _buildGraphView(mindMap, scheme, text),
    );
  }

  Widget _buildTextView(MindMap mindMap, ColorScheme scheme, TextTheme text) {
    if (mindMap.textContent == null || mindMap.textContent!.isEmpty) {
      return Center(
        child: Text(
          'No text content available',
          style: text.bodyLarge?.copyWith(
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: SelectableText(
        mindMap.textContent!,
        style: text.bodyLarge?.copyWith(
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildGraphView(MindMap mindMap, ColorScheme scheme, TextTheme text) {
    // Check if mind map is empty or not found
    if (mindMap.id.isEmpty || mindMap.rootNode.label == 'Empty') {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              LucideIcons.network,
              size: 64,
              color: scheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Mind Map Not Found',
              style: text.titleLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This mind map may have been deleted',
              style: text.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    // Check if mind map has no branches (only root node)
    if (mindMap.rootNode.children.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                LucideIcons.alertCircle,
                size: 64,
                color: scheme.primary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Mind Map Structure Issue',
                style: text.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'This mind map only has a root node with no branches.\nTry switching to Text Mode to see the content.',
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => setState(() => _showTextMode = true),
                icon: const Icon(LucideIcons.text),
                label: const Text('View as Text'),
              ),
              if (mindMap.textContent != null &&
                  mindMap.textContent!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Root: ${mindMap.rootNode.label}',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          mindMap.textContent!.length > 200
                              ? '${mindMap.textContent!.substring(0, 200)}...'
                              : mindMap.textContent!,
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final canvasWidth = math.max(2400.0, _contentBounds.right + _canvasPadding);
    final canvasHeight =
        math.max(2200.0, _contentBounds.bottom + _canvasPadding);

    return Container(
      color: scheme.surface,
      child: Stack(
        children: [
          InteractiveViewer(
            transformationController: _transformController,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 0.05,
            maxScale: 4.0,
            child: SizedBox(
              width: canvasWidth,
              height: canvasHeight,
              child: CustomPaint(
                painter: MindMapPainter(
                  rootNode: mindMap.rootNode,
                  scheme: scheme,
                  selectedNodeId: _selectedNodeId,
                  nodePositions: _nodePositions,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ..._buildFlattenedWidgets(
                      mindMap.rootNode,
                      scheme,
                      text,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: _buildMapSummary(mindMap, scheme, text),
          ),
          if (_selectedNodeId != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _buildSelectedNodeCard(mindMap.rootNode, scheme, text),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildFlattenedWidgets(
    MindMapNode node,
    ColorScheme scheme,
    TextTheme text,
    {
    String? selectedNodeId,
    bool interactive = true,
    ValueChanged<String>? onNodeTap,
  }
  ) {
    if (!_nodePositions.containsKey(node.id)) return [];

    return _collectWidgetsRecursive(
      node,
      0,
      scheme,
      text,
      selectedNodeId: selectedNodeId ?? _selectedNodeId,
      interactive: interactive,
      onNodeTap: onNodeTap,
    );
  }

  List<Widget> _collectWidgetsRecursive(
    MindMapNode node,
    int depth,
    ColorScheme scheme,
    TextTheme text, {
    String? selectedNodeId,
    bool interactive = true,
    ValueChanged<String>? onNodeTap,
  }) {
    final List<Widget> list = [];
    final pos = _nodePositions[node.id];

    if (pos != null) {
      final nodeCard = Container(
        width: _nodeWidth,
        height: _nodeHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _getNodeColor(depth, scheme),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectedNodeId == node.id
                ? scheme.primary
                : scheme.outline.withValues(alpha: 0.1),
            width: selectedNodeId == node.id ? 3 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          node.label,
          style: text.bodyMedium?.copyWith(
            color: _getNodeTextColor(depth, scheme),
            fontWeight: depth == 0 ? FontWeight.bold : FontWeight.w500,
            fontSize: depth == 0 ? 16 : 14,
          ),
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
      );

      list.add(
        Positioned(
          left: pos.dx - (_nodeWidth / 2),
          top: pos.dy - (_nodeHeight / 2),
          child: interactive
              ? GestureDetector(
                  onTap: () {
                    if (onNodeTap != null) {
                      onNodeTap(node.id);
                    } else {
                      setState(() => _selectedNodeId = node.id);
                    }
                  },
                  child: nodeCard,
                )
              : nodeCard,
        ),
      );
    }

    for (var child in node.children) {
      list.addAll(
        _collectWidgetsRecursive(
          child,
          depth + 1,
          scheme,
          text,
          selectedNodeId: selectedNodeId,
          interactive: interactive,
          onNodeTap: onNodeTap,
        ),
      );
    }
    return list;
  }

  Future<void> _exportMindMap({
    required _MindMapExportFormat format,
    required MindMap mindMap,
    required ColorScheme scheme,
    required TextTheme text,
  }) async {
    if (_isExporting) return;

    setState(() => _isExporting = true);
    try {
      late final Uint8List bytes;
      late final String fileName;
      late final String mimeType;

      switch (format) {
        case _MindMapExportFormat.png:
          bytes = await _captureMindMapAsPng(mindMap, scheme, text);
          fileName = _buildExportFileName(mindMap.title, 'png');
          mimeType = 'image/png';
          break;
        case _MindMapExportFormat.markdown:
          bytes = Uint8List.fromList(
            utf8.encode(_buildMarkdownExport(mindMap)),
          );
          fileName = _buildExportFileName(mindMap.title, 'md');
          mimeType = 'text/markdown';
          break;
        case _MindMapExportFormat.json:
          bytes = Uint8List.fromList(
            utf8.encode(_buildJsonExport(mindMap)),
          );
          fileName = _buildExportFileName(mindMap.title, 'json');
          mimeType = 'application/json';
          break;
      }

      final savedPath = await saveFileBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );

      if (!mounted) return;
      final fileLabel = savedPath == null ? fileName : p.basename(savedPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported $fileLabel'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<Uint8List> _captureMindMapAsPng(
    MindMap mindMap,
    ColorScheme scheme,
    TextTheme text,
  ) async {
    final canvasWidth = math.max(2400.0, _contentBounds.right + _canvasPadding);
    final canvasHeight =
        math.max(2200.0, _contentBounds.bottom + _canvasPadding);
    final exportLongestSide = math.max(canvasWidth, canvasHeight);
    final pixelRatio =
        (3200 / exportLongestSide).clamp(0.9, 2.0).toDouble();

    final controller = ScreenshotController();
    return controller.captureFromWidget(
      InheritedTheme.captureAll(
        context,
        Material(
          color: scheme.surface,
          child: SizedBox(
            width: canvasWidth,
            height: canvasHeight,
            child: CustomPaint(
              painter: MindMapPainter(
                rootNode: mindMap.rootNode,
                scheme: scheme,
                selectedNodeId: null,
                nodePositions: _nodePositions,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: _buildFlattenedWidgets(
                  mindMap.rootNode,
                  scheme,
                  text,
                  selectedNodeId: null,
                  interactive: false,
                ),
              ),
            ),
          ),
        ),
      ),
      delay: const Duration(milliseconds: 20),
      pixelRatio: pixelRatio,
      targetSize: Size(canvasWidth, canvasHeight),
    );
  }

  String _buildMarkdownExport(MindMap mindMap) {
    final buffer = StringBuffer()
      ..writeln('# ${mindMap.title}')
      ..writeln()
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln('Mind Map ID: ${mindMap.id}')
      ..writeln();

    final outline = (mindMap.textContent != null && mindMap.textContent!.trim().isNotEmpty)
        ? mindMap.textContent!.trim()
        : _buildTextOutline(mindMap.rootNode);
    buffer.write(outline);
    return buffer.toString();
  }

  String _buildJsonExport(MindMap mindMap) {
    final data = {
      'mind_map': {
        'id': mindMap.id,
        'title': mindMap.title,
        'notebook_id': mindMap.notebookId,
        'source_id': mindMap.sourceId,
        'created_at': mindMap.createdAt.toIso8601String(),
        'updated_at': mindMap.updatedAt.toIso8601String(),
      },
      'root_node': mindMap.rootNode.toJson(),
      'text_content': mindMap.textContent ?? _buildTextOutline(mindMap.rootNode),
      'stats': {
        'nodes': _countNodes(mindMap.rootNode),
        'depth': _maxDepth(mindMap.rootNode) + 1,
        'branches': mindMap.rootNode.children.length,
      },
      'exported_at': DateTime.now().toIso8601String(),
    };

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  String _buildTextOutline(MindMapNode root) {
    final buffer = StringBuffer()..writeln('# ${root.label}');

    void visit(MindMapNode node, int depth) {
      for (final child in node.children) {
        if (depth == 0) {
          buffer.writeln('## ${child.label}');
        } else {
          final indent = '  ' * (depth - 1);
          buffer.writeln('$indent- ${child.label}');
        }
        visit(child, depth + 1);
      }
    }

    visit(root, 0);
    return buffer.toString().trim();
  }

  String _buildExportFileName(String title, String extension) {
    final safeTitle = title
        .trim()
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    final baseName = safeTitle.isEmpty ? 'mind_map' : safeTitle;
    return '${baseName}_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  Widget _buildMapSummary(MindMap mindMap, ColorScheme scheme, TextTheme text) {
    final totalNodes = _countNodes(mindMap.rootNode);
    final depth = _maxDepth(mindMap.rootNode);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _StatChip(
              label: 'Nodes',
              value: '$totalNodes',
              scheme: scheme,
            ),
            _StatChip(
              label: 'Depth',
              value: '${depth + 1}',
              scheme: scheme,
            ),
            _StatChip(
              label: 'Branches',
              value: '${mindMap.rootNode.children.length}',
              scheme: scheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedNodeCard(
      MindMapNode root, ColorScheme scheme, TextTheme text) {
    final selected = _findNodeById(root, _selectedNodeId!);
    if (selected == null) return const SizedBox.shrink();

    final path = _nodePath(root, _selectedNodeId!);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.18)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    selected.label,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _selectedNodeId = null),
                  icon: const Icon(LucideIcons.x),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              path.join('  /  '),
              style: text.bodySmall?.copyWith(
                color: scheme.secondary,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _StatChip(
                  label: 'Level',
                  value: '${selected.level + 1}',
                  scheme: scheme,
                ),
                _StatChip(
                  label: 'Children',
                  value: '${selected.children.length}',
                  scheme: scheme,
                ),
                _StatChip(
                  label: 'Leaf',
                  value: selected.children.isEmpty ? 'Yes' : 'No',
                  scheme: scheme,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _countNodes(MindMapNode node) {
    var count = 1;
    for (final child in node.children) {
      count += _countNodes(child);
    }
    return count;
  }

  int _maxDepth(MindMapNode node) {
    if (node.children.isEmpty) return node.level;
    return node.children
        .map(_maxDepth)
        .fold(node.level, (current, value) => math.max(current, value));
  }

  MindMapNode? _findNodeById(MindMapNode node, String id) {
    if (node.id == id) return node;
    for (final child in node.children) {
      final match = _findNodeById(child, id);
      if (match != null) return match;
    }
    return null;
  }

  List<String> _nodePath(MindMapNode node, String id) {
    if (node.id == id) {
      return [node.label];
    }

    for (final child in node.children) {
      final childPath = _nodePath(child, id);
      if (childPath.isNotEmpty) {
        return [node.label, ...childPath];
      }
    }

    return const [];
  }

  Color _getNodeColor(int depth, ColorScheme scheme) {
    if (depth == 0) return scheme.primaryContainer;
    if (depth == 1) return scheme.secondaryContainer;
    return scheme.surfaceContainerHighest;
  }

  Color _getNodeTextColor(int depth, ColorScheme scheme) {
    if (depth == 0) return scheme.onPrimaryContainer;
    if (depth == 1) return scheme.onSecondaryContainer;
    return scheme.onSurface;
  }

  void _zoomIn() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale * 1.3).clamp(0.05, 4.0);
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(2, 2, newScale)
      ..setTranslationRaw(
        _transformController.value.getTranslation().x,
        _transformController.value.getTranslation().y,
        0,
      ); // Keep translation? Ideally zoom to center but this is simple
  }

  void _zoomOut() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    final newScale = (currentScale / 1.3).clamp(0.05, 4.0);
    _transformController.value = Matrix4.identity()
      ..setEntry(0, 0, newScale)
      ..setEntry(1, 1, newScale)
      ..setEntry(2, 2, newScale)
      ..setTranslationRaw(
        _transformController.value.getTranslation().x,
        _transformController.value.getTranslation().y,
        0,
      );
  }

  void _resetZoom() {
    _fitToContent();
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.scheme,
  });

  final String label;
  final String value;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.secondary,
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }
}

enum _MindMapExportFormat { png, markdown, json }

/// Custom painter for drawing connection lines between nodes
class MindMapPainter extends CustomPainter {
  final MindMapNode rootNode;
  final ColorScheme scheme;
  final String? selectedNodeId;
  final Map<String, Offset> nodePositions;

  MindMapPainter({
    required this.rootNode,
    required this.scheme,
    this.selectedNodeId,
    required this.nodePositions,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.outline.withValues(alpha: 0.3)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    _drawConnectionsRecursive(canvas, rootNode, paint);
  }

  void _drawConnectionsRecursive(
    Canvas canvas,
    MindMapNode node,
    Paint paint,
  ) {
    final startPos = nodePositions[node.id];
    if (startPos == null) return;

    for (var child in node.children) {
      final endPos = nodePositions[child.id];
      if (endPos != null) {
        final path = Path()
          ..moveTo(startPos.dx, startPos.dy)
          ..quadraticBezierTo(
            (startPos.dx + endPos.dx) / 2,
            (startPos.dy + endPos.dy) / 2, // Straighter curve
            endPos.dx,
            endPos.dy,
          );
        canvas.drawPath(path, paint);
      }
      _drawConnectionsRecursive(canvas, child, paint);
    }
  }

  @override
  bool shouldRepaint(covariant MindMapPainter oldDelegate) {
    return oldDelegate.rootNode != rootNode ||
        oldDelegate.selectedNodeId != selectedNodeId ||
        oldDelegate.nodePositions != nodePositions;
  }
}
