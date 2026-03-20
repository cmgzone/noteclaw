import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../../theme/app_theme.dart';
import '../../../core/ai/ai_provider.dart';
import '../../subscription/services/credit_manager.dart';
import '../models/design_artifact.dart';
import '../models/design_document.dart';
import '../planning_provider.dart';
import '../models/requirement.dart';
import '../services/design_html_builder.dart';
import 'design_engine_preview.dart';
import 'design_node_inspector.dart';

enum _DesignPreviewMode {
  html,
  engine,
}

class _StructuredDesignResponse {
  final String html;
  final DesignDocument? document;

  const _StructuredDesignResponse({
    required this.html,
    required this.document,
  });
}

/// AI UI Design Generator Screen
/// Generates premium HTML/CSS designs based on plan context, previews in WebView, captures screenshots
class UIDesignGeneratorScreen extends ConsumerStatefulWidget {
  final String planId;

  const UIDesignGeneratorScreen({super.key, required this.planId});

  @override
  ConsumerState<UIDesignGeneratorScreen> createState() =>
      _UIDesignGeneratorScreenState();
}

class _UIDesignGeneratorScreenState
    extends ConsumerState<UIDesignGeneratorScreen> {
  final TextEditingController _promptController = TextEditingController();
  final ScreenshotController _screenshotController = ScreenshotController();

  WebViewController? _webViewController;
  String? _generatedHtml;
  DesignDocument? _generatedDesignDocument;
  Uint8List? _screenshot;
  bool _isGenerating = false;
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _isRegeneratingSection = false;
  _DesignPreviewMode _previewMode = _DesignPreviewMode.html;
  String? _selectedDesignScreenId;
  String? _selectedDesignNodeId;
  String _selectedStyle = 'modern';
  String _selectedColorScheme = 'purple';

  // Plan context
  List<Requirement> _selectedRequirements = [];
  bool _useExistingDesignNotes = true;
  bool _showContextPanel = true;

  final List<String> _styles = [
    'modern',
    'minimal',
    'glassmorphism',
    'neumorphism',
    'gradient',
    'dark',
    'corporate',
    'playful',
  ];

  final Map<String, List<String>> _colorSchemes = {
    'purple': ['#8B5CF6', '#A78BFA', '#C4B5FD'],
    'blue': ['#3B82F6', '#60A5FA', '#93C5FD'],
    'green': ['#10B981', '#34D399', '#6EE7B7'],
    'orange': ['#F97316', '#FB923C', '#FDBA74'],
    'pink': ['#EC4899', '#F472B6', '#F9A8D4'],
    'teal': ['#14B8A6', '#2DD4BF', '#5EEAD4'],
  };

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white);
  }

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App Bar
          SliverAppBar(
            floating: true,
            pinned: true,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                LucideIcons.palette,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'AI UI Designer',
                              style: text.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Content
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Plan Context Panel
                  _buildPlanContextPanel(scheme, text),
                  const SizedBox(height: 20),

                  // Design Prompt Input
                  _buildPromptSection(scheme, text),
                  const SizedBox(height: 20),

                  // Style Selection
                  _buildStyleSelection(scheme, text),
                  const SizedBox(height: 16),

                  // Color Scheme Selection
                  _buildColorSchemeSelection(scheme, text),
                  const SizedBox(height: 24),

                  // Generate Button
                  _buildGenerateButton(scheme),
                  const SizedBox(height: 24),

                  // Preview Section
                  if (_generatedHtml != null) ...[
                    _buildPreviewSection(scheme, text),
                    const SizedBox(height: 16),

                    // Action Buttons
                    _buildActionButtons(scheme),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanContextPanel(ColorScheme scheme, TextTheme text) {
    final planState = ref.watch(planningProvider);
    final plan = planState.currentPlan;

    if (plan == null) {
      return const SizedBox.shrink();
    }

    final requirements = plan.requirements;
    final designNotes = plan.designNotes;

    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _showContextPanel = !_showContextPanel),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(LucideIcons.fileText, color: scheme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan Context: ${plan.title}',
                          style: text.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${requirements.length} requirements • ${designNotes.length} design notes',
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _showContextPanel
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          if (_showContextPanel) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Use existing design notes toggle
                  if (designNotes.isNotEmpty) ...[
                    SwitchListTile(
                      title: const Text('Use existing design notes as context'),
                      subtitle:
                          Text('${designNotes.length} design notes available'),
                      value: _useExistingDesignNotes,
                      onChanged: (v) =>
                          setState(() => _useExistingDesignNotes = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Requirements selection
                  if (requirements.isNotEmpty) ...[
                    Text(
                      'Select requirements to design for:',
                      style: text.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: requirements.length,
                        itemBuilder: (context, index) {
                          final req = requirements[index];
                          final isSelected =
                              _selectedRequirements.contains(req);
                          return CheckboxListTile(
                            title: Text(
                              req.title,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              req.earsPattern.name,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.primary,
                              ),
                            ),
                            value: isSelected,
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _selectedRequirements.add(req);
                                } else {
                                  _selectedRequirements.remove(req);
                                }
                              });
                            },
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Quick select buttons
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => setState(() =>
                              _selectedRequirements = List.from(requirements)),
                          icon: const Icon(LucideIcons.checkSquare, size: 16),
                          label: const Text('Select All'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _selectedRequirements.clear()),
                          icon: const Icon(LucideIcons.square, size: 16),
                          label: const Text('Clear'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.info,
                              size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'No requirements yet. Add requirements in the plan to use them as design context.',
                              style: text.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildPromptSection(ColorScheme scheme, TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.sparkles, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Describe Your Design',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText:
                    'e.g., A modern dashboard with user stats, charts, and a sidebar navigation...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: scheme.surface,
              ),
            ),
            const SizedBox(height: 12),
            // Quick prompts
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildQuickPrompt('Landing Page', scheme),
                _buildQuickPrompt('Dashboard', scheme),
                _buildQuickPrompt('Login Form', scheme),
                _buildQuickPrompt('Pricing Cards', scheme),
                _buildQuickPrompt('Profile Card', scheme),
                _buildQuickPrompt('Feature Section', scheme),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildQuickPrompt(String label, ColorScheme scheme) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: () {
        _promptController.text = 'Create a premium $label design';
      },
      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.3),
    );
  }

  Widget _buildStyleSelection(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Design Style',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _styles.length,
            itemBuilder: (context, index) {
              final style = _styles[index];
              final isSelected = style == _selectedStyle;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    style.substring(0, 1).toUpperCase() + style.substring(1),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() => _selectedStyle = style);
                    }
                  },
                  selectedColor: scheme.primary,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : scheme.onSurface,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildColorSchemeSelection(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Color Scheme',
          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: _colorSchemes.entries.map((entry) {
            final isSelected = entry.key == _selectedColorScheme;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => setState(() => _selectedColorScheme = entry.key),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: entry.value
                          .map((c) =>
                              Color(int.parse(c.replaceFirst('#', '0xFF'))))
                          .toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Color(int.parse(
                                      entry.value[0].replaceFirst('#', '0xFF')))
                                  .withValues(alpha: 0.5),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildGenerateButton(ColorScheme scheme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _isGenerating ? null : _generateDesign,
        icon: _isGenerating
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(LucideIcons.wand2),
        label: Text(_isGenerating ? 'Generating...' : 'Generate Design'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).scale();
  }

  Widget _buildPreviewSection(ColorScheme scheme, TextTheme text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.eye, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              _generatedDesignDocument != null
                  ? 'Design Preview'
                  : 'Live Preview',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_screenshot != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.check,
                        color: Colors.green, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Screenshot captured',
                      style:
                          TextStyle(color: Colors.green.shade700, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (_generatedDesignDocument != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('HTML'),
                selected: _previewMode == _DesignPreviewMode.html,
                onSelected: (_) {
                  setState(() => _previewMode = _DesignPreviewMode.html);
                },
              ),
              ChoiceChip(
                label: const Text('Engine'),
                selected: _previewMode == _DesignPreviewMode.engine,
                onSelected: (_) {
                  setState(() => _previewMode = _DesignPreviewMode.engine);
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        Screenshot(
          controller: _screenshotController,
          child: Container(
            height: 500,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: _previewMode == _DesignPreviewMode.engine &&
                    _generatedDesignDocument != null
                ? DesignEnginePreview(
                    document: _generatedDesignDocument!,
                    selectedScreenId: _selectedDesignScreenId,
                    selectedNodeId: _selectedDesignNodeId,
                    onScreenSelected: _handleEngineScreenSelected,
                    onNodeSelected: _handleEngineNodeSelected,
                  )
                : WebViewWidget(controller: _webViewController!),
          ),
        ),
        if (_previewMode == _DesignPreviewMode.engine &&
            _generatedDesignDocument != null) ...[
          const SizedBox(height: 12),
          DesignNodeInspector(
            screen: _selectedScreenSpec,
            node: _selectedNodeSpec,
            onApply: _applySelectedNodeEdits,
            onRegenerate: _regenerateSelectedNode,
            isRegenerating: _isRegeneratingSection,
            onClearSelection: () {
              setState(() {
                _selectedDesignScreenId = null;
                _selectedDesignNodeId = null;
              });
            },
          ),
        ],
      ],
    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1);
  }

  Widget _buildActionButtons(ColorScheme scheme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isCapturing ? null : _captureScreenshot,
            icon: _isCapturing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(LucideIcons.camera),
            label: Text(_isCapturing ? 'Capturing...' : 'Capture Screenshot'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: (_isSaving || _generatedHtml == null)
                ? null
                : _saveAsDesignNote,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.save),
            label: Text(_isSaving ? 'Saving...' : 'Save Design'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    ).animate().fadeIn(delay: 500.ms);
  }

  DesignScreenSpec? get _selectedScreenSpec {
    final document = _generatedDesignDocument;
    final screenId = _selectedDesignScreenId;
    if (document == null || screenId == null) return null;
    return document.findScreen(screenId);
  }

  DesignNodeSpec? get _selectedNodeSpec {
    final document = _generatedDesignDocument;
    final screenId = _selectedDesignScreenId;
    final nodeId = _selectedDesignNodeId;
    if (document == null || screenId == null || nodeId == null) return null;
    return document.findNode(screenId, nodeId);
  }

  void _handleEngineScreenSelected(String screenId) {
    final screen = _generatedDesignDocument?.findScreen(screenId);
    setState(() {
      _selectedDesignScreenId = screenId;
      _selectedDesignNodeId = screen != null && screen.nodes.isNotEmpty
          ? screen.nodes.first.id
          : null;
    });
  }

  void _handleEngineNodeSelected(String screenId, String nodeId) {
    setState(() {
      _selectedDesignScreenId = screenId;
      _selectedDesignNodeId = nodeId;
    });
  }

  void _applySelectedNodeEdits(DesignNodeSpec updatedNode) {
    final document = _generatedDesignDocument;
    final screenId = _selectedDesignScreenId;
    final nodeId = _selectedDesignNodeId;
    if (document == null || screenId == null || nodeId == null) return;

    final updatedDocument = document.updateNode(
      screenId,
      nodeId,
      (_) => updatedNode,
    );

    _syncGeneratedHtmlFromDocument(updatedDocument);
  }

  void _seedSelectionFromDocument(DesignDocument? document) {
    if (document == null || document.screens.isEmpty) {
      _selectedDesignScreenId = null;
      _selectedDesignNodeId = null;
      return;
    }

    final firstScreen = document.screens.first;
    _selectedDesignScreenId = firstScreen.id;
    _selectedDesignNodeId =
        firstScreen.nodes.isNotEmpty ? firstScreen.nodes.first.id : null;
  }

  Future<void> _regenerateSelectedNode() async {
    final document = _generatedDesignDocument;
    final screen = _selectedScreenSpec;
    final node = _selectedNodeSpec;
    if (document == null || screen == null || node == null) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 2,
      feature: 'ui_design_section_regenerate',
    );
    if (!hasCredits) return;

    setState(() => _isRegeneratingSection = true);

    try {
      final prompt = _buildNodeRegenerationPrompt(
        document: document,
        screen: screen,
        node: node,
      );

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(prompt, style: ChatStyle.standard);

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final regeneratedNode = _extractRegeneratedNodeFromResponse(
        aiState.lastResponse ?? '',
        fallbackNode: node,
      );

      if (regeneratedNode == null) {
        throw Exception('Could not parse regenerated node');
      }

      final updatedDocument = document.updateNode(
        screen.id,
        node.id,
        (_) => regeneratedNode,
      );

      await _syncGeneratedHtmlFromDocument(updatedDocument);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Section regenerated and synced to the HTML preview.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to regenerate section: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRegeneratingSection = false);
      }
    }
  }

  Future<void> _syncGeneratedHtmlFromDocument(DesignDocument document) async {
    final html = DesignDocumentHtmlBuilder.build(
      document,
      title: _promptController.text.trim().isNotEmpty
          ? _promptController.text.trim()
          : document.title,
      initialScreenId: _selectedDesignScreenId,
    );

    if (!mounted) return;

    setState(() {
      _generatedDesignDocument = document;
      _generatedHtml = html;
    });

    await _webViewController?.loadHtmlString(html);
  }

  Future<void> _generateDesign() async {
    if (_promptController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe your design')),
      );
      return;
    }

    // Check credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 3,
      feature: 'ui_design_generator',
    );
    if (!hasCredits) return;

    setState(() {
      _isGenerating = true;
      _screenshot = null;
      _generatedDesignDocument = null;
      _previewMode = _DesignPreviewMode.html;
      _selectedDesignScreenId = null;
      _selectedDesignNodeId = null;
    });

    try {
      final colors = _colorSchemes[_selectedColorScheme]!;
      final prompt = _buildDesignPrompt(colors);

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(prompt, style: ChatStyle.standard);

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final response = aiState.lastResponse ?? '';
      final structuredResponse = _extractStructuredDesignResponse(response);
      final html = structuredResponse.html;

      if (html.isNotEmpty) {
        setState(() {
          _generatedHtml = html;
          _generatedDesignDocument = structuredResponse.document;
          if (structuredResponse.document != null) {
            _previewMode = _DesignPreviewMode.engine;
            _seedSelectionFromDocument(structuredResponse.document);
          }
        });
        await _webViewController?.loadHtmlString(html);
      } else {
        throw Exception('Could not generate valid HTML');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  String _buildDesignPrompt(List<String> colors) {
    final planState = ref.read(planningProvider);
    final plan = planState.currentPlan;

    // Build context from selected requirements
    String requirementsContext = '';
    if (_selectedRequirements.isNotEmpty) {
      requirementsContext = '''

**Selected Requirements to Design For:**
${_selectedRequirements.map((r) => '''
- **${r.title}**
  ${r.description.isNotEmpty ? 'Description: ${r.description}' : ''}
  ${r.acceptanceCriteria.isNotEmpty ? 'Acceptance Criteria: ${r.acceptanceCriteria.join(", ")}' : ''}
''').join('\n')}
''';
    }

    // Build context from existing design notes
    String designNotesContext = '';
    if (_useExistingDesignNotes &&
        plan != null &&
        plan.designNotes.isNotEmpty) {
      final relevantNotes =
          plan.designNotes.take(3).toList(); // Limit to 3 most recent
      designNotesContext = '''

**Existing Design Decisions (for consistency):**
${relevantNotes.map((n) => '- ${n.content.length > 200 ? '${n.content.substring(0, 200)}...' : n.content}').join('\n')}
''';
    }

    // Build plan context
    String planContext = '';
    if (plan != null) {
      planContext = '''

**Project Context:**
- Project: ${plan.title}
- Description: ${plan.description.isNotEmpty ? plan.description : 'N/A'}
''';
    }

    return '''Generate a structured UI design package for the following request:

**Design Request:** ${_promptController.text}
$planContext
$requirementsContext
$designNotesContext
**Style:** $_selectedStyle
**Primary Color:** ${colors[0]}
**Secondary Color:** ${colors[1]}
**Accent Color:** ${colors[2]}

**Requirements:**
1. Create a premium, professional UI design
2. Use modern CSS techniques (flexbox, grid, gradients, shadows)
3. Include smooth transitions and hover effects
4. Make it responsive and mobile-friendly
5. Use the specified color scheme throughout
6. Add realistic placeholder content based on the project context
7. Include icons using emoji or Unicode symbols
8. The design should look polished and production-ready
9. If requirements are provided, ensure the UI addresses those specific features

**Style Guidelines for "$_selectedStyle":**
${_getStyleGuidelines()}

**Output Format:**
Return EXACTLY two tagged sections and nothing else:

[[NOTECLAW_DESIGN_SPEC_JSON]]
{valid JSON}
[[/NOTECLAW_DESIGN_SPEC_JSON]]
[[NOTECLAW_HTML]]
<!DOCTYPE html>...full html...
</html>
[[/NOTECLAW_HTML]]

**JSON Schema Rules:**
- The JSON root must contain: schemaVersion, title, summary, theme, screens
- theme fields: style, primaryColor, secondaryColor, accentColor, backgroundColor, surfaceColor, textColor, radius
- screens must contain 1 or 2 screens only
- each screen must contain: id, name, description, nodes
- supported node types only: hero, stats_row, card_list, feature_grid, action_bar, form, timeline, quote, content, cta
- each node may contain: id, type, title, subtitle, body, label, value, icon, variant, items
- each item may contain: title, subtitle, label, value, meta, icon, tags
- keep content concise, realistic, and aligned with the requested UI
- use valid hex colors in the theme

**HTML Rules:**
- The HTML must be self-contained with all CSS in a <style> tag
- The HTML should visually match the JSON design closely
- Make it responsive and polished
- Do not use markdown fences inside either section''';
  }

  String _getStyleGuidelines() {
    switch (_selectedStyle) {
      case 'modern':
        return 'Clean lines, subtle shadows, rounded corners, whitespace, sans-serif fonts';
      case 'minimal':
        return 'Maximum whitespace, simple typography, monochrome accents, no decorations';
      case 'glassmorphism':
        return 'Frosted glass effect, blur backgrounds, transparency, light borders';
      case 'neumorphism':
        return 'Soft shadows, extruded elements, subtle gradients, tactile feel';
      case 'gradient':
        return 'Bold gradients, vibrant colors, dynamic backgrounds, modern feel';
      case 'dark':
        return 'Dark backgrounds, neon accents, high contrast, sleek appearance';
      case 'corporate':
        return 'Professional, trustworthy, structured layout, business-appropriate';
      case 'playful':
        return 'Rounded shapes, bright colors, fun animations, friendly feel';
      default:
        return 'Modern and professional';
    }
  }

  String _buildNodeRegenerationPrompt({
    required DesignDocument document,
    required DesignScreenSpec screen,
    required DesignNodeSpec node,
  }) {
    final requirementSummary = _selectedRequirements.isNotEmpty
        ? _selectedRequirements
            .map((r) => '- ${r.title}: ${r.description}')
            .join('\n')
        : '- No specific requirements selected';

    return '''Rewrite one structured UI node for a design engine.

**Design Request:** ${_promptController.text.trim()}
**Style:** $_selectedStyle
**Color Scheme:** $_selectedColorScheme
**Theme JSON:**
${jsonEncode(document.theme.toJson())}

**Selected Requirements:**
$requirementSummary

**Screen Context JSON:**
${jsonEncode(screen.toJson())}

**Current Node JSON:**
${jsonEncode(node.toJson())}

**Task:**
- Rewrite ONLY the selected node to be sharper, more realistic, and more polished
- Preserve the same node `id`
- Preserve the same node `type`
- Keep the content aligned with the existing screen and design request
- You may improve: title, subtitle, body, label, value, icon, variant, items, props
- If the node uses items, return realistic items that fit the node type

Return ONLY one valid JSON object for the rewritten node.
Do not include markdown, explanations, or code fences.''';
  }

  String _extractHtmlFromResponse(String response) {
    // Try to extract HTML from the response
    String html = response.trim();

    // Remove markdown code blocks if present
    if (html.contains('```html')) {
      final start = html.indexOf('```html') + 7;
      final end = html.lastIndexOf('```');
      if (end > start) {
        html = html.substring(start, end).trim();
      }
    } else if (html.contains('```')) {
      final start = html.indexOf('```') + 3;
      final end = html.lastIndexOf('```');
      if (end > start) {
        html = html.substring(start, end).trim();
      }
    }

    // Ensure it starts with DOCTYPE or html tag
    if (!html.toLowerCase().startsWith('<!doctype') &&
        !html.toLowerCase().startsWith('<html')) {
      // Try to find the start of HTML
      final doctypeIndex = html.toLowerCase().indexOf('<!doctype');
      final htmlIndex = html.toLowerCase().indexOf('<html');
      final startIndex =
          doctypeIndex >= 0 ? doctypeIndex : (htmlIndex >= 0 ? htmlIndex : -1);
      if (startIndex >= 0) {
        html = html.substring(startIndex);
      }
    }

    return html;
  }

  _StructuredDesignResponse _extractStructuredDesignResponse(String response) {
    final jsonBlock = _extractTaggedBlock(
      response,
      '[[NOTECLAW_DESIGN_SPEC_JSON]]',
      '[[/NOTECLAW_DESIGN_SPEC_JSON]]',
    );
    final htmlBlock = _extractTaggedBlock(
      response,
      '[[NOTECLAW_HTML]]',
      '[[/NOTECLAW_HTML]]',
    );

    DesignDocument? document;
    if (jsonBlock != null && jsonBlock.trim().isNotEmpty) {
      try {
        var normalizedJson = jsonBlock.trim();
        if (normalizedJson.startsWith('```json') &&
            normalizedJson.endsWith('```')) {
          normalizedJson =
              normalizedJson.substring(7, normalizedJson.length - 3).trim();
        } else if (normalizedJson.startsWith('```') &&
            normalizedJson.endsWith('```')) {
          normalizedJson =
              normalizedJson.substring(3, normalizedJson.length - 3).trim();
        }

        final decoded = jsonDecode(normalizedJson);
        if (decoded is Map) {
          document =
              DesignDocument.fromJson(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        document = null;
      }
    }

    final html = _extractHtmlFromResponse(
      htmlBlock != null && htmlBlock.trim().isNotEmpty ? htmlBlock : response,
    );
    return _StructuredDesignResponse(html: html, document: document);
  }

  String? _extractTaggedBlock(String text, String startTag, String endTag) {
    final startIndex = text.indexOf(startTag);
    final endIndex = text.indexOf(endTag);
    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      return null;
    }
    return text.substring(startIndex + startTag.length, endIndex).trim();
  }

  DesignNodeSpec? _extractRegeneratedNodeFromResponse(
    String response, {
    required DesignNodeSpec fallbackNode,
  }) {
    var normalized = response.trim();
    if (normalized.startsWith('```json') && normalized.endsWith('```')) {
      normalized = normalized.substring(7, normalized.length - 3).trim();
    } else if (normalized.startsWith('```') && normalized.endsWith('```')) {
      normalized = normalized.substring(3, normalized.length - 3).trim();
    }

    final firstBrace = normalized.indexOf('{');
    final lastBrace = normalized.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      normalized = normalized.substring(firstBrace, lastBrace + 1);
    }

    try {
      final decoded = jsonDecode(normalized);
      if (decoded is! Map) return null;
      final mergedJson = Map<String, dynamic>.from(fallbackNode.toJson())
        ..addAll(Map<String, dynamic>.from(decoded))
        ..['id'] = fallbackNode.id
        ..['type'] = fallbackNode.type;
      return DesignNodeSpec.fromJson(mergedJson);
    } catch (_) {
      return null;
    }
  }

  Future<void> _captureScreenshot() async {
    setState(() => _isCapturing = true);

    try {
      // Wait a moment for WebView to fully render
      await Future.delayed(const Duration(milliseconds: 500));

      final image = await _screenshotController.capture(
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.0,
      );

      if (image != null) {
        setState(() => _screenshot = image);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Screenshot captured successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = false);
      }
    }
  }

  Future<void> _saveAsDesignNote() async {
    if (_generatedHtml == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please generate a design first')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      String screenshotPath = '';

      // Save screenshot to file if captured
      if (_screenshot != null) {
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        screenshotPath = '${directory.path}/design_$timestamp.png';
        final file = File(screenshotPath);
        await file.writeAsBytes(_screenshot!);
      }

      // Build requirements context for the note
      String requirementsSection = '';
      if (_selectedRequirements.isNotEmpty) {
        requirementsSection = '''
### Designed For Requirements:
${_selectedRequirements.map((r) => '- ${r.title}').join('\n')}
''';
      }

      // Create design note content with HTML and screenshot reference
      const codeBlockStart = '```html';
      const codeBlockEnd = '```';
      final designContent = '''## 🎨 UI Design: ${_promptController.text}

**Type:** UI Design (HTML/CSS)
**Style:** $_selectedStyle
**Color Scheme:** $_selectedColorScheme
**Generated:** ${DateTime.now().toIso8601String()}
$requirementsSection
${screenshotPath.isNotEmpty ? '''
### Screenshot
![Design Preview](file://$screenshotPath)
''' : ''}
### HTML Code
$codeBlockStart
$_generatedHtml
$codeBlockEnd

---
*This UI design was generated by AI UI Designer and can be used as a reference for implementation.*
''';

      // Get requirement IDs for linking
      final requirementIds = _selectedRequirements.map((r) => r.id).toList();

      final planning = ref.read(planningProvider.notifier);
      final generatedAt = DateTime.now().toIso8601String();
      final designDocumentJson = _generatedDesignDocument?.toJson();

      final designNote = await planning.createDesignNote(
        content: designContent,
        requirementIds: requirementIds,
      );
      final designArtifact = await planning.createDesignArtifact(
        name: _promptController.text.trim().isEmpty
            ? 'Generated UI Design'
            : _promptController.text.trim(),
        artifactType: DesignArtifactType.screenSet,
        status: DesignArtifactStatus.ready,
        source: DesignArtifactSource.aiGenerated,
        schemaVersion: designDocumentJson != null ? 2 : 1,
        rootData: {
          'format': designDocumentJson != null ? 'structured_html' : 'html',
          'html': _generatedHtml,
          if (designDocumentJson != null) 'document': designDocumentJson,
          'prompt': _promptController.text.trim(),
          'style': _selectedStyle,
          'colorScheme': _selectedColorScheme,
          'requirementIds': requirementIds,
        },
        metadata: {
          'generatedAt': generatedAt,
          'screenshotPath': screenshotPath,
          'linkedRequirementCount': requirementIds.length,
          'usedExistingDesignNotes': _useExistingDesignNotes,
          'hasStructuredPreview': designDocumentJson != null,
        },
        changeSummary: designDocumentJson != null
            ? 'Initial AI-generated UI design with structured screen spec'
            : 'Initial AI-generated UI design',
      );

      if (designNote == null && designArtifact == null) {
        throw Exception('Failed to save design outputs');
      }

      if (mounted) {
        final savedBoth = designNote != null && designArtifact != null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LucideIcons.check, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    savedBoth
                        ? 'Design saved! ${requirementIds.isNotEmpty ? "Linked to ${requirementIds.length} requirement(s)." : ""}'
                        : 'Design saved partially. Check plan outputs.',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
