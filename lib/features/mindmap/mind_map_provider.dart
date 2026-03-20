import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ai/ai_settings_service.dart';
import 'package:uuid/uuid.dart';
import 'mind_map_node.dart';
import '../sources/source_provider.dart';
import '../gamification/gamification_provider.dart';
import '../notebook/notebook_chat_context_builder.dart';
import '../../core/api/api_service.dart';
import '../../core/services/activity_logger_service.dart';

/// Provider for managing mind maps
class MindMapNotifier extends StateNotifier<List<MindMap>> {
  final Ref ref;

  MindMapNotifier(this.ref) : super([]) {
    _loadMindMaps();
  }

  Future<void> _loadMindMaps() async {
    try {
      final api = ref.read(apiServiceProvider);
      final mapsData = await api.getMindMaps();
      state = mapsData.map((j) => MindMap.fromBackendJson(j)).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (e) {
      debugPrint('Error loading mind maps: $e');
      state = [];
    }
  }

  /// Get mind maps for a specific notebook
  List<MindMap> getMindMapsForNotebook(String notebookId) {
    return state.where((mm) => mm.notebookId == notebookId).toList();
  }

  /// Add a new mind map
  Future<MindMap> addMindMap(MindMap mindMap) async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.saveMindMap(
        title: mindMap.title,
        notebookId: mindMap.notebookId,
        sourceId: mindMap.sourceId,
        rootNode: mindMap.rootNode.toBackendJson(),
        textContent: mindMap.textContent,
      );
      final savedData =
          Map<String, dynamic>.from(response['mindMap'] ?? response);

      final savedMindMap = MindMap.fromBackendJson(savedData);
      state = [savedMindMap, ...state.where((mm) => mm.id != savedMindMap.id)];
      return savedMindMap;
    } catch (e) {
      debugPrint('Error adding mind map: $e');
      rethrow;
    }
  }

  /// Update existing mind map
  Future<void> updateMindMap(MindMap mindMap) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.saveMindMap(
        id: mindMap.id,
        title: mindMap.title,
        notebookId: mindMap.notebookId,
        sourceId: mindMap.sourceId,
        rootNode: mindMap.rootNode.toBackendJson(),
        textContent: mindMap.textContent,
      );
      await _loadMindMaps();
    } catch (e) {
      debugPrint('Error updating mind map: $e');
    }
  }

  /// Delete a mind map
  Future<void> deleteMindMap(String id) async {
    // Current backend doesn't have deleteMindMap yet, I should add it
    await _loadMindMaps();
  }

  /// Generate mind map from sources using AI
  Future<MindMap> generateFromSources({
    required String notebookId,
    required String title,
    String? sourceId,
    String? focusTopic,
    String mapStyle = 'balanced',
  }) async {
    final sources = ref.read(sourceProvider);
    final relevantSources = sourceId != null
        ? sources.where((s) => s.id == sourceId).toList()
        : sources.where((s) => s.notebookId == notebookId).toList();

    if (relevantSources.isEmpty) {
      throw Exception('No sources found to generate mind map from');
    }

    final sourceContent =
        await NotebookChatContextBuilder.buildContextTextForCurrentModel(
      read: ref.read,
      sources: relevantSources,
      objective:
          'Create a $mapStyle mind map for "$title". ${focusTopic != null && focusTopic.trim().isNotEmpty ? 'Focus area: ${focusTopic.trim()}.' : ''}',
    );

    return _generateFromContent(
      notebookId: notebookId,
      title: title,
      content: sourceContent,
      sourceId: sourceId,
      focusTopic: focusTopic,
      mapStyle: mapStyle,
    );
  }

  /// Generate mind map from arbitrary text content such as an ebook
  Future<MindMap> generateFromContent({
    required String notebookId,
    required String title,
    required String content,
    String? sourceId,
    String? focusTopic,
    String mapStyle = 'balanced',
  }) {
    if (content.trim().isEmpty) {
      throw Exception('No content available to generate mind map from');
    }

    return _generateFromContent(
      notebookId: notebookId,
      title: title,
      content: content,
      sourceId: sourceId,
      focusTopic: focusTopic,
      mapStyle: mapStyle,
    );
  }

  Future<MindMap> _generateFromContent({
    required String notebookId,
    required String title,
    required String content,
    String? sourceId,
    String? focusTopic,
    required String mapStyle,
  }) async {
    final normalizedNotebookId = notebookId.trim();
    if (normalizedNotebookId.isEmpty) {
      throw Exception('Choose a notebook to save the mind map');
    }
    final mapStyleGuidance = _mapStyleGuidance(mapStyle);
    final focusInstruction = focusTopic != null && focusTopic.trim().isNotEmpty
        ? 'Give extra attention to this focus area: "${focusTopic.trim()}".'
        : '';

    final prompt = '''
You are a knowledge architect building a high-signal mind map.
Create a hierarchical mind map based on the following content.
The mind map should identify key concepts, relationships, and memorable takeaways.
$mapStyleGuidance
$focusInstruction

TITLE:
$title

CONTENT:
$content

Return your response in TWO parts:

PART 1 - TEXT VERSION:
# [Central Topic]
## Branch 1: [Main Concept]
- Sub-topic 1.1
  - Detail
- Sub-topic 1.2

## Branch 2: [Main Concept]
- Sub-topic 2.1

---JSON_START---

PART 2 - JSON VERSION (after the marker above):
{
  "id": "root",
  "label": "Central Topic",
  "children": [
    {
      "id": "b1",
      "label": "Main Concept 1",
      "children": [
        {
          "id": "b1-1",
          "label": "Sub-topic 1.1",
          "children": [
            {"id": "b1-1-a", "label": "Detail", "children": []}
          ]
        },
        {"id": "b1-2", "label": "Sub-topic 1.2", "children": []}
      ]
    }
  ]
}

Requirements:
- Create 4-6 main branches when the material supports it.
- Add 2-4 sub-topics per branch.
- Add third-level detail nodes when helpful.
- Keep labels short, specific, and scannable.
- Prefer concrete concepts over vague filler terms.
- Return raw text and raw JSON only. No markdown code fences.
''';

    final response = await _callAI(prompt);
    final (textContent, rootNode) = _parseMindMapResponse(response, title);

    final now = DateTime.now();
    final mindMap = MindMap(
      id: const Uuid().v4(),
      title: title,
      notebookId: normalizedNotebookId,
      sourceId: sourceId,
      rootNode: rootNode,
      textContent: textContent,
      createdAt: now,
      updatedAt: now,
    );

    final savedMindMap = await addMindMap(mindMap);

    ref.read(gamificationProvider.notifier).trackMindmapCreated();
    ref.read(gamificationProvider.notifier).trackFeatureUsed('mindmap');
    ref.read(activityLoggerProvider).logMindmapCreated(title, savedMindMap.id);

    return savedMindMap;
  }

  Future<String> _callAI(String prompt) async {
    try {
      final settings = await AISettingsService.getSettingsWithDefault(ref.read);
      final model = settings.getEffectiveModel();

      debugPrint(
          '[MindMapProvider] Using AI provider: ${settings.provider}, model: $model');

      final apiService = ref.read(apiServiceProvider);
      final messages = [
        {'role': 'user', 'content': prompt}
      ];

      return await apiService.chatWithAI(
        messages: messages,
        provider: settings.provider,
        model: model,
      );
    } catch (e) {
      debugPrint('[MindMapProvider] AI call failed: $e');
      rethrow;
    }
  }

  (String, MindMapNode) _parseMindMapResponse(
      String response, String fallbackTitle) {
    String textContent = response.trim();
    MindMapNode? rootNode;

    debugPrint('[MindMapProvider] Parsing response length: ${response.length}');

    try {
      final parts = response.split('---JSON_START---');
      if (parts.length >= 2) {
        textContent = parts[0].trim();
        final jsonPart = _extractJsonObject(parts[1]);
        if (jsonPart != null) {
          final jsonData = jsonDecode(jsonPart);
          rootNode = _parseNodeFromJson(jsonData, 0);
          debugPrint('[MindMapProvider] Parsed from JSON marker');
        }
      }

      if (rootNode == null) {
        final jsonPart = _extractJsonObject(response);
        if (jsonPart != null) {
          try {
            final jsonData = jsonDecode(jsonPart);
            rootNode = _parseNodeFromJson(jsonData, 0);
            debugPrint('[MindMapProvider] Parsed from embedded JSON');
          } catch (_) {}
        }
      }

      if (rootNode == null) {
        rootNode = _parseOutlineToNodes(textContent, fallbackTitle);
        debugPrint('[MindMapProvider] Parsed from outline structure');
      }
    } catch (e) {
      debugPrint('[MindMapProvider] Error parsing mind map: $e');
    }

    rootNode ??= MindMapNode(
      id: 'root',
      label: fallbackTitle,
      level: 0,
      children: [],
    );

    if (textContent.isEmpty ||
        (textContent == response.trim() &&
            !_containsOutlineStructure(textContent))) {
      textContent = _buildTextOutline(rootNode);
    }

    debugPrint(
        '[MindMapProvider] Root node children: ${rootNode.children.length}');
    return (textContent, rootNode);
  }

  MindMapNode _parseNodeFromJson(dynamic json, int level) {
    if (json is! Map<String, dynamic>) {
      return MindMapNode(
        id: const Uuid().v4(),
        label: json.toString(),
        level: level,
        children: [],
      );
    }

    final children = (json['children'] as List<dynamic>?)
            ?.map((child) => _parseNodeFromJson(child, level + 1))
            .toList() ??
        [];

    return MindMapNode(
      id: json['id'] ?? const Uuid().v4(),
      label: json['label'] ?? 'Untitled',
      level: level,
      children: children,
    );
  }

  MindMapNode _parseOutlineToNodes(String text, String fallbackTitle) {
    final lines = text.split('\n');
    String rootLabel = fallbackTitle;
    final root =
        _MutableMindMapNode(id: 'root', label: fallbackTitle, level: 0);
    final stack = <_MutableMindMapNode>[root];

    for (final originalLine in lines) {
      final line = originalLine.replaceAll('\t', '  ');
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed == '---JSON_START---') break;
      if (trimmed.startsWith('```')) continue;
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) continue;

      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(trimmed);
      if (headingMatch != null) {
        final headingDepth = headingMatch.group(1)!.length;
        final label = _cleanNodeLabel(headingMatch.group(2)!);
        if (label.isEmpty) continue;

        if (headingDepth == 1) {
          rootLabel = label;
          root.label = label;
          stack
            ..clear()
            ..add(root);
          continue;
        }

        final nodeLevel = headingDepth - 1;
        final node = _MutableMindMapNode(
            id: const Uuid().v4(), label: label, level: nodeLevel);

        while (stack.length > nodeLevel) {
          stack.removeLast();
        }
        stack.last.children.add(node);
        stack.add(node);
        continue;
      }

      final bulletMatch =
          RegExp(r'^(\s*)([-*]|\d+[.)])\s+(.+)$').firstMatch(line);
      if (bulletMatch != null) {
        final indent = bulletMatch.group(1)!.length;
        final nestingLevel = indent ~/ 2;
        final nodeLevel = 2 + nestingLevel;
        final label = _cleanNodeLabel(bulletMatch.group(3)!);
        if (label.isEmpty) continue;

        final node = _MutableMindMapNode(
            id: const Uuid().v4(), label: label, level: nodeLevel);

        while (stack.length > nodeLevel) {
          stack.removeLast();
        }
        while (stack.length < nodeLevel) {
          final parent = stack.last;
          if (parent.children.isEmpty) break;
          stack.add(parent.children.last);
        }
        stack.last.children.add(node);
        stack.add(node);
        continue;
      }

      if (root.children.isEmpty) {
        final label = _cleanNodeLabel(trimmed);
        if (label.isNotEmpty) {
          root.children.add(
            _MutableMindMapNode(id: const Uuid().v4(), label: label, level: 1),
          );
        }
      }
    }

    final resolvedRoot = root.copyWith(label: rootLabel);
    return _freezeMutableNode(resolvedRoot);
  }

  String _mapStyleGuidance(String mapStyle) {
    switch (mapStyle) {
      case 'relationships':
        return 'Emphasize how concepts connect, influence each other, or depend on one another. Prefer branches that reveal relationships and comparisons.';
      case 'process':
        return 'Emphasize sequences, workflows, stages, and cause-and-effect steps. Organize the map so progression is easy to follow.';
      case 'study':
        return 'Emphasize definitions, examples, categories, and memory-friendly study cues. Prefer clear educational structure.';
      case 'balanced':
      default:
        return 'Balance concepts, structure, examples, and relationships so the map gives a strong overall understanding.';
    }
  }

  String? _extractJsonObject(String input) {
    final start = input.indexOf('{');
    if (start == -1) return null;

    var depth = 0;
    var inString = false;
    var escaped = false;

    for (var i = start; i < input.length; i++) {
      final char = input[i];

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == '\\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }

      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) {
          return input.substring(start, i + 1);
        }
      }
    }

    return null;
  }

  bool _containsOutlineStructure(String text) {
    return RegExp(r'^(#|\s*[-*]|\s*\d+[.)])\s+', multiLine: true)
        .hasMatch(text);
  }

  String _cleanNodeLabel(String value) {
    return value
        .replaceAll(RegExp(r'^[\-\*]\s*'), '')
        .replaceAll(RegExp(r'^\d+[.)]\s*'), '')
        .replaceAll(
            RegExp(r'^(Branch|Section|Topic)\s+\d+\s*:\s*',
                caseSensitive: false),
            '')
        .replaceAll(RegExp(r'^\[(.+)\]$'), r'$1')
        .trim();
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

  MindMapNode _freezeMutableNode(_MutableMindMapNode node) {
    return MindMapNode(
      id: node.id,
      label: node.label,
      level: node.level,
      children: node.children.map(_freezeMutableNode).toList(),
    );
  }
}

class _MutableMindMapNode {
  _MutableMindMapNode({
    required this.id,
    required this.label,
    required this.level,
    List<_MutableMindMapNode>? children,
  }) : children = children ?? [];

  final String id;
  String label;
  final int level;
  final List<_MutableMindMapNode> children;

  _MutableMindMapNode copyWith({String? label}) {
    return _MutableMindMapNode(
      id: id,
      label: label ?? this.label,
      level: level,
      children: children,
    );
  }
}

final mindMapProvider =
    StateNotifierProvider<MindMapNotifier, List<MindMap>>((ref) {
  return MindMapNotifier(ref);
});
