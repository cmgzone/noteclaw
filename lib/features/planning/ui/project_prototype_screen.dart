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

import '../../../core/ai/ai_provider.dart';
import '../../subscription/services/credit_manager.dart';
import '../models/design_artifact.dart';
import '../models/design_document.dart';
import '../planning_provider.dart';
import '../services/design_html_builder.dart';
import 'design_engine_preview.dart';
import 'design_node_inspector.dart';

/// Device frame definitions for mobile preview
enum DeviceFrame {
  responsive('Responsive', null, null, LucideIcons.monitor),
  iphone14('iPhone 14', 390, 844, LucideIcons.smartphone),
  iphone14Pro('iPhone 14 Pro', 393, 852, LucideIcons.smartphone),
  iphoneSE('iPhone SE', 375, 667, LucideIcons.smartphone),
  pixel7('Pixel 7', 412, 915, LucideIcons.smartphone),
  galaxyS23('Galaxy S23', 360, 780, LucideIcons.smartphone),
  ipadMini('iPad Mini', 744, 1133, LucideIcons.tablet),
  ipadPro('iPad Pro 11"', 834, 1194, LucideIcons.tablet);

  final String name;
  final double? width;
  final double? height;
  final IconData icon;

  const DeviceFrame(this.name, this.width, this.height, this.icon);
}

enum _PrototypePreviewMode {
  html,
  engine,
}

/// Project Prototype Generator Screen
/// Auto-generates all screens for a project with navigation, interactive WebView preview
class ProjectPrototypeScreen extends ConsumerStatefulWidget {
  final String planId;

  const ProjectPrototypeScreen({super.key, required this.planId});

  @override
  ConsumerState<ProjectPrototypeScreen> createState() =>
      _ProjectPrototypeScreenState();
}

/// AI-decided design system based on project context
class _AIDesignSystem {
  final String style;
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final String backgroundColor;
  final String textColor;
  final String cardColor;
  final String fontFamily;
  final String borderRadius;
  final String shadowStyle;
  final String reasoning;

  _AIDesignSystem({
    required this.style,
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.backgroundColor,
    required this.textColor,
    required this.cardColor,
    required this.fontFamily,
    required this.borderRadius,
    required this.shadowStyle,
    required this.reasoning,
  });

  factory _AIDesignSystem.fromResponse(String response) {
    String extract(String key, String fallback) {
      final regex = RegExp('$key:\\s*([^\\n]+)', caseSensitive: false);
      final match = regex.firstMatch(response);
      return match?.group(1)?.trim() ?? fallback;
    }

    return _AIDesignSystem(
      style: extract('STYLE', 'modern'),
      primaryColor: extract('PRIMARY', '#6366F1'),
      secondaryColor: extract('SECONDARY', '#8B5CF6'),
      accentColor: extract('ACCENT', '#F59E0B'),
      backgroundColor: extract('BACKGROUND', '#F8FAFC'),
      textColor: extract('TEXT', '#1E293B'),
      cardColor: extract('CARD', '#FFFFFF'),
      fontFamily: extract('FONT', 'Inter'),
      borderRadius: extract('RADIUS', '16px'),
      shadowStyle: extract('SHADOW', 'soft'),
      reasoning:
          extract('REASONING', 'Professional design based on project context'),
    );
  }
}

class _ScreenDefinition {
  final String id;
  final String name;
  final String description;
  final bool isGenerated;
  final String? html;

  _ScreenDefinition({
    required this.id,
    required this.name,
    required this.description,
    this.isGenerated = false,
    this.html,
  });

  _ScreenDefinition copyWith({
    String? id,
    String? name,
    String? description,
    bool? isGenerated,
    String? html,
  }) {
    return _ScreenDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isGenerated: isGenerated ?? this.isGenerated,
      html: html ?? this.html,
    );
  }
}

class _StructuredPrototypeResponse {
  final String html;
  final DesignDocument? document;

  const _StructuredPrototypeResponse({
    required this.html,
    required this.document,
  });
}

class _ProjectPrototypeScreenState
    extends ConsumerState<ProjectPrototypeScreen> {
  final ScreenshotController _screenshotController = ScreenshotController();

  WebViewController? _webViewController;
  String? _fullPrototypeHtml;
  DesignDocument? _generatedDesignDocument;
  Uint8List? _screenshot;
  bool _isGenerating = false;
  bool _isCapturing = false;
  bool _isSaving = false;
  bool _isRegeneratingSection = false;
  bool _webViewReady = false;
  _PrototypePreviewMode _previewMode = _PrototypePreviewMode.html;
  String? _selectedDesignScreenId;
  String? _selectedDesignNodeId;
  String _currentScreen = 'home';
  double _generationProgress = 0;
  String _generationStatus = '';
  DeviceFrame _selectedDevice = DeviceFrame.iphone14;
  bool _isLandscape = false;

  // Screen definitions
  List<_ScreenDefinition> _screens = [];
  bool _screensAnalyzed = false;
  bool _isAnalyzing = false;

  // AI-decided design system
  _AIDesignSystem? _aiDesignSystem;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() => _webViewReady = true);
            }
          },
          onNavigationRequest: (request) {
            // Handle internal navigation
            if (request.url.startsWith('app://')) {
              final screenId = request.url.replaceFirst('app://', '');
              setState(() => _currentScreen = screenId);
              _navigateToScreen(screenId);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    // Load a placeholder to prevent black screen
    _loadPlaceholder();
  }

  void _loadPlaceholder() {
    const placeholderHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      color: white;
      text-align: center;
      padding: 20px;
    }
    .container {
      max-width: 300px;
    }
    .icon { font-size: 64px; margin-bottom: 20px; }
    h1 { font-size: 24px; margin-bottom: 12px; }
    p { font-size: 14px; opacity: 0.9; line-height: 1.5; }
  </style>
</head>
<body>
  <div class="container">
    <div class="icon">📱</div>
    <h1>Project Prototype</h1>
    <p>Analyze your project and generate screens to see an interactive mobile app prototype here.</p>
  </div>
</body>
</html>
''';
    _webViewController?.loadHtmlString(placeholderHtml);
  }

  void _navigateToScreen(String screenId) {
    if (_fullPrototypeHtml != null && _webViewController != null) {
      // Use a more robust navigation approach
      _webViewController!.runJavaScript('''
        (function() {
          // Try the navigateTo function first
          if (typeof navigateTo === 'function') {
            navigateTo('$screenId');
            return;
          }
          
          // Fallback: manually handle navigation
          var screens = document.querySelectorAll('.screen');
          screens.forEach(function(s) {
            s.classList.remove('active');
            s.style.display = 'none';
          });
          
          var target = document.getElementById('$screenId');
          if (target) {
            target.classList.add('active');
            target.style.display = 'flex';
          }
          
          // Update bottom nav if exists
          var navLinks = document.querySelectorAll('.bottom-nav a, nav a');
          navLinks.forEach(function(a) {
            a.classList.remove('active');
            if (a.getAttribute('data-screen') === '$screenId' || 
                a.getAttribute('href') === '#$screenId' ||
                a.getAttribute('onclick')?.includes('$screenId')) {
              a.classList.add('active');
            }
          });
        })();
      ''');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(scheme, text),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProjectInfo(scheme, text),
                  const SizedBox(height: 20),
                  _buildStyleSection(scheme, text),
                  const SizedBox(height: 20),
                  if (!_screensAnalyzed) ...[
                    _buildAnalyzeButton(scheme),
                  ] else ...[
                    _buildScreensList(scheme, text),
                    const SizedBox(height: 20),
                    _buildGenerateButton(scheme),
                  ],
                  if (_isGenerating) ...[
                    const SizedBox(height: 20),
                    _buildProgressSection(scheme, text),
                  ],
                  if (_fullPrototypeHtml != null) ...[
                    const SizedBox(height: 24),
                    _buildPreviewSection(scheme, text),
                    if (_previewMode == _PrototypePreviewMode.html) ...[
                      const SizedBox(height: 16),
                      _buildScreenNavigation(scheme, text),
                    ],
                    const SizedBox(height: 16),
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

  Widget _buildAppBar(ColorScheme scheme, TextTheme text) {
    return SliverAppBar(
      floating: true,
      pinned: true,
      expandedHeight: 140,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [scheme.primary, scheme.tertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
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
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          LucideIcons.layoutDashboard,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Project Prototype',
                              style: text.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Auto-generate all screens with navigation',
                              style: text.bodySmall?.copyWith(
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildProjectInfo(ColorScheme scheme, TextTheme text) {
    final planState = ref.watch(planningProvider);
    final plan = planState.currentPlan;

    if (plan == null) {
      return Card(
        color: scheme.errorContainer,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('No plan loaded'),
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
                Icon(LucideIcons.folder, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan.title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (plan.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                plan.description,
                style: text.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildInfoChip(
                  '${plan.requirements.length} Requirements',
                  LucideIcons.fileText,
                  scheme,
                ),
                _buildInfoChip(
                  '${plan.tasks.length} Tasks',
                  LucideIcons.listChecks,
                  scheme,
                ),
                _buildInfoChip(
                  '${plan.designNotes.length} Design Notes',
                  LucideIcons.penTool,
                  scheme,
                ),
              ],
            ),
          ],
        ),
      ),
    ).animate().fadeIn().slideY(begin: 0.1);
  }

  Widget _buildInfoChip(String label, IconData icon, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleSection(ColorScheme scheme, TextTheme text) {
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
                  'AI Design System',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LucideIcons.wand2,
                          size: 12, color: Colors.amber.shade700),
                      const SizedBox(width: 4),
                      Text(
                        'AI Decides',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_aiDesignSystem == null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: scheme.outline.withValues(alpha: 0.2),
                    style: BorderStyle.solid,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(LucideIcons.palette,
                        color: scheme.onSurfaceVariant, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Smart Design Selection',
                            style: text.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'AI will analyze your project and choose the perfect colors, style, and typography based on your app\'s purpose.',
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Show AI-decided design
              _buildAIDesignPreview(scheme, text),
            ],
          ],
        ),
      ),
    ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.1);
  }

  Widget _buildAIDesignPreview(ColorScheme scheme, TextTheme text) {
    final design = _aiDesignSystem!;

    Color parseColor(String hex) {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {
        return scheme.primary;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Color palette preview
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                parseColor(design.primaryColor),
                parseColor(design.secondaryColor),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.palette, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  design.style.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              // Color dots
              ...[
                design.primaryColor,
                design.secondaryColor,
                design.accentColor
              ].map(
                (c) => Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: parseColor(c),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Design reasoning
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.lightbulb,
                  size: 16, color: Colors.amber.shade600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  design.reasoning,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Design specs
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildDesignChip(
                'Font: ${design.fontFamily}', LucideIcons.type, scheme),
            _buildDesignChip(
                'Radius: ${design.borderRadius}', LucideIcons.square, scheme),
            _buildDesignChip(
                'Shadow: ${design.shadowStyle}', LucideIcons.layers, scheme),
          ],
        ),
      ],
    );
  }

  Widget _buildDesignChip(String label, IconData icon, ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: scheme.onSurface),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyzeButton(ColorScheme scheme) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _isAnalyzing ? null : _analyzeProject,
        icon: _isAnalyzing
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : const Icon(LucideIcons.scan),
        label: Text(
            _isAnalyzing ? 'Analyzing Project...' : 'Analyze & Plan Screens'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).scale();
  }

  Widget _buildScreensList(ColorScheme scheme, TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.layers, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Screens to Generate (${_screens.length})',
                  style:
                      text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _analyzeProject,
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  label: const Text('Re-analyze'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...List.generate(_screens.length, (index) {
              final screen = _screens[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: screen.isGenerated
                      ? Colors.green.withValues(alpha: 0.1)
                      : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: screen.isGenerated
                        ? Colors.green.withValues(alpha: 0.3)
                        : scheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: screen.isGenerated
                            ? Colors.green
                            : scheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: screen.isGenerated
                            ? const Icon(LucideIcons.check,
                                color: Colors.white, size: 16)
                            : Text(
                                '${index + 1}',
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            screen.name,
                            style: text.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            screen.description,
                            style: text.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);
  }

  Widget _buildGenerateButton(ColorScheme scheme) {
    final allGenerated = _screens.every((s) => s.isGenerated);
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton.icon(
        onPressed: _isGenerating ? null : _generateFullPrototype,
        icon: _isGenerating
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onPrimary,
                ),
              )
            : Icon(allGenerated ? LucideIcons.refreshCw : LucideIcons.wand2),
        label: Text(_isGenerating
            ? 'Generating...'
            : allGenerated
                ? 'Regenerate All Screens'
                : 'Generate Full Prototype'),
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    ).animate().fadeIn(delay: 300.ms).scale();
  }

  Widget _buildProgressSection(ColorScheme scheme, TextTheme text) {
    return Card(
      color: scheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _generationStatus,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  '${(_generationProgress * 100).toInt()}%',
                  style: text.titleMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _generationProgress,
                minHeight: 8,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn();
  }

  Widget _buildDeviceSelector(ColorScheme scheme, TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(LucideIcons.smartphone, color: scheme.primary, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Device Preview',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Orientation toggle
                if (_selectedDevice != DeviceFrame.responsive)
                  IconButton(
                    onPressed: () =>
                        setState(() => _isLandscape = !_isLandscape),
                    icon: Icon(
                      _isLandscape
                          ? LucideIcons.smartphone
                          : LucideIcons.tablet,
                      size: 18,
                    ),
                    tooltip: _isLandscape ? 'Portrait' : 'Landscape',
                    style: IconButton.styleFrom(
                      backgroundColor:
                          scheme.primaryContainer.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: DeviceFrame.values.length,
                itemBuilder: (context, index) {
                  final device = DeviceFrame.values[index];
                  final isSelected = device == _selectedDevice;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      avatar: Icon(device.icon, size: 14),
                      label: Text(device.name,
                          style: const TextStyle(fontSize: 11)),
                      selected: isSelected,
                      onSelected: (_) =>
                          setState(() => _selectedDevice = device),
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : scheme.onSurface,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewSection(ColorScheme scheme, TextTheme text) {
    // Calculate device dimensions
    double? deviceWidth = _selectedDevice.width;
    double? deviceHeight = _selectedDevice.height;

    if (_isLandscape && deviceWidth != null && deviceHeight != null) {
      final temp = deviceWidth;
      deviceWidth = deviceHeight;
      deviceHeight = temp;
    }

    // Scale to fit screen
    final screenWidth = MediaQuery.of(context).size.width - 32;
    double scale = 1.0;
    double previewWidth = screenWidth;
    double previewHeight = 600;

    if (deviceWidth != null && deviceHeight != null) {
      // Calculate scale to fit
      final widthScale =
          (screenWidth - 40) / deviceWidth; // 40 for device frame padding
      final heightScale = 600 / deviceHeight;
      scale = widthScale < heightScale ? widthScale : heightScale;
      if (scale > 1) scale = 1; // Don't scale up

      previewWidth = deviceWidth * scale + 40;
      previewHeight =
          deviceHeight * scale + 80; // Extra for notch/home indicator
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(LucideIcons.monitor, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              _generatedDesignDocument != null
                  ? 'Interactive Prototype Preview'
                  : 'Interactive Prototype',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _previewMode == _PrototypePreviewMode.engine
                    ? scheme.primary.withValues(alpha: 0.1)
                    : _webViewReady
                        ? Colors.green.withValues(alpha: 0.1)
                        : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _previewMode == _PrototypePreviewMode.engine
                          ? scheme.primary
                          : _webViewReady
                              ? Colors.green
                              : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _previewMode == _PrototypePreviewMode.engine
                        ? 'Structured'
                        : _webViewReady
                            ? 'Live'
                            : 'Loading...',
                    style: TextStyle(
                      color: _previewMode == _PrototypePreviewMode.engine
                          ? scheme.primary
                          : _webViewReady
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
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
                selected: _previewMode == _PrototypePreviewMode.html,
                onSelected: (_) {
                  setState(() => _previewMode = _PrototypePreviewMode.html);
                },
              ),
              ChoiceChip(
                label: const Text('Engine'),
                selected: _previewMode == _PrototypePreviewMode.engine,
                onSelected: (_) {
                  setState(() => _previewMode = _PrototypePreviewMode.engine);
                },
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // Device selector
        _buildDeviceSelector(scheme, text),
        const SizedBox(height: 12),
        // Device frame preview
        Center(
          child: Screenshot(
            controller: _screenshotController,
            child: _selectedDevice == DeviceFrame.responsive
                ? Container(
                    height: 600,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.2)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildPreviewCanvas(),
                  )
                : _buildDeviceFrame(scheme, previewWidth, previewHeight,
                    deviceWidth, deviceHeight, scale),
          ),
        ),
        if (_previewMode == _PrototypePreviewMode.engine &&
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

  Widget _buildDeviceFrame(
      ColorScheme scheme,
      double frameWidth,
      double frameHeight,
      double? deviceWidth,
      double? deviceHeight,
      double scale) {
    final isPhone = _selectedDevice.name.contains('iPhone') ||
        _selectedDevice.name.contains('Pixel') ||
        _selectedDevice.name.contains('Galaxy');

    return Container(
      width: frameWidth,
      height: frameHeight,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(isPhone ? 40 : 20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      padding: EdgeInsets.all(isPhone ? 12 : 8),
      child: Column(
        children: [
          // Notch/Dynamic Island for phones
          if (isPhone) ...[
            Container(
              width: 120,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            const SizedBox(height: 4),
          ],
          // Screen
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(isPhone ? 28 : 12),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildPreviewCanvas(),
            ),
          ),
          // Home indicator for phones
          if (isPhone) ...[
            const SizedBox(height: 8),
            Container(
              width: 134,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildWebView() {
    if (_webViewController == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: _webViewController!),
        if (!_webViewReady)
          Container(
            color: Colors.white,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading preview...'),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPreviewCanvas() {
    if (_previewMode == _PrototypePreviewMode.engine &&
        _generatedDesignDocument != null) {
      return DesignEnginePreview(
        document: _generatedDesignDocument!,
        selectedScreenId: _selectedDesignScreenId,
        selectedNodeId: _selectedDesignNodeId,
        onScreenSelected: _handleEngineScreenSelected,
        onNodeSelected: _handleEngineNodeSelected,
      );
    }
    return _buildWebView();
  }

  Widget _buildScreenNavigation(ColorScheme scheme, TextTheme text) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Navigate Screens',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // Refresh button to reload current screen
                IconButton(
                  onPressed: () {
                    if (_fullPrototypeHtml != null) {
                      setState(() => _webViewReady = false);
                      _webViewController
                          ?.loadHtmlString(_fullPrototypeHtml!)
                          .then((_) {
                        Future.delayed(const Duration(milliseconds: 500), () {
                          _navigateToScreen(_currentScreen);
                        });
                      });
                    }
                  },
                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                  tooltip: 'Reload prototype',
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHighest,
                    padding: const EdgeInsets.all(8),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _screens.length,
                itemBuilder: (context, index) {
                  final screen = _screens[index];
                  final isActive = screen.id == _currentScreen;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(screen.name),
                      selected: isActive,
                      onSelected: (_) {
                        setState(() => _currentScreen = screen.id);
                        _navigateToScreen(screen.id);
                      },
                      selectedColor: scheme.primary,
                      labelStyle: TextStyle(
                        color: isActive ? Colors.white : scheme.onSurface,
                        fontSize: 12,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
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
            label: const Text('Screenshot'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _exportHtml,
            icon: const Icon(LucideIcons.download),
            label: const Text('Export'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveAsDesignNote,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(LucideIcons.save),
            label: const Text('Save'),
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
      _currentScreen = screenId;
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

    _syncPrototypeHtmlFromDocument(updatedDocument, activeScreenId: screenId);
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
    final plan = ref.read(planningProvider).currentPlan;
    if (document == null || screen == null || node == null) return;

    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 2,
      feature: 'project_prototype_section_regenerate',
    );
    if (!hasCredits) return;

    setState(() => _isRegeneratingSection = true);

    try {
      final prompt = _buildPrototypeNodeRegenerationPrompt(
        plan: plan,
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

      await _syncPrototypeHtmlFromDocument(
        updatedDocument,
        activeScreenId: screen.id,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Prototype section regenerated and synced to the HTML preview.',
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

  Future<void> _syncPrototypeHtmlFromDocument(
    DesignDocument document, {
    String? activeScreenId,
  }) async {
    final screenId = activeScreenId ?? _currentScreen;
    final html = DesignDocumentHtmlBuilder.build(
      document,
      title: document.title,
      initialScreenId: screenId,
      mobilePrototype: true,
    );

    if (!mounted) return;

    setState(() {
      _generatedDesignDocument = document;
      _fullPrototypeHtml = html;
      _currentScreen = screenId;
      _webViewReady = false;
    });

    await _webViewController?.loadHtmlString(html);
    await Future.delayed(const Duration(milliseconds: 150));
    _navigateToScreen(screenId);
  }

  /// Analyze project requirements and determine screens to generate
  Future<void> _analyzeProject() async {
    final planState = ref.read(planningProvider);
    final plan = planState.currentPlan;

    if (plan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No plan loaded')),
      );
      return;
    }

    // Check credits
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * 3,
      feature: 'project_prototype_analyze',
    );
    if (!hasCredits) return;

    setState(() {
      _isAnalyzing = true;
      _screens = [];
      _aiDesignSystem = null;
    });

    try {
      // First, get AI to decide the design system
      final designPrompt =
          '''You are a professional UI/UX designer. Analyze this project and decide the PERFECT design system.

**Project:** ${plan.title}
**Description:** ${plan.description}

**Requirements:**
${plan.requirements.map((r) => '- ${r.title}: ${r.description}').join('\n')}

Based on the project's PURPOSE and TARGET AUDIENCE, decide:

1. **Style** - Choose ONE: modern, minimal, glassmorphism, dark, gradient, corporate, playful, elegant, bold, tech
2. **Colors** - Pick colors that match the project's mood and industry
3. **Typography** - Choose appropriate font style
4. **Visual elements** - Border radius, shadows, etc.

RESPOND IN THIS EXACT FORMAT (one per line):
STYLE: [style name]
PRIMARY: [hex color like #6366F1]
SECONDARY: [hex color]
ACCENT: [hex color for CTAs/highlights]
BACKGROUND: [hex color]
TEXT: [hex color]
CARD: [hex color]
FONT: [font name like Inter, Poppins, Roboto]
RADIUS: [like 8px, 12px, 16px, 24px]
SHADOW: [soft, medium, strong, none]
REASONING: [1 sentence explaining why these choices fit the project]

Examples:
- Healthcare app → calming blues/greens, soft shadows, rounded corners
- Finance app → professional blues/grays, sharp corners, minimal
- Social app → vibrant gradients, playful, bold colors
- E-commerce → clean whites, accent colors for CTAs
- Gaming → dark theme, neon accents, bold typography''';

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(designPrompt, style: ChatStyle.standard);

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      final designResponse = aiState.lastResponse ?? '';
      final designSystem = _AIDesignSystem.fromResponse(designResponse);

      setState(() {
        _aiDesignSystem = designSystem;
      });

      // Now analyze screens
      final screenPrompt =
          '''Analyze this project and identify all the screens/pages needed for a complete application prototype.

**Project:** ${plan.title}
**Description:** ${plan.description}

**Requirements:**
${plan.requirements.map((r) => '- ${r.title}: ${r.description}').join('\n')}

**Tasks:**
${plan.tasks.map((t) => '- ${t.title}').join('\n')}

**Design Notes:**
${plan.designNotes.map((d) => '- ${d.content.length > 100 ? d.content.substring(0, 100) : d.content}...').join('\n')}

Based on this project, list ALL screens needed for a complete prototype. For each screen provide:
1. A unique ID (lowercase, no spaces, e.g., "home", "login", "dashboard")
2. Screen name (human readable)
3. Brief description of what the screen contains

Format your response EXACTLY like this (one screen per line):
SCREEN|id|Name|Description

Example:
SCREEN|home|Home|Landing page with hero section and feature highlights
SCREEN|login|Login|User authentication with email and password
SCREEN|dashboard|Dashboard|Main user dashboard with stats and recent activity

List 5-10 screens that would make a complete prototype.''';

      await aiNotifier.generateContent(screenPrompt, style: ChatStyle.standard);

      final screenState = ref.read(aiProvider);
      if (screenState.error != null) {
        throw Exception(screenState.error);
      }

      final response = screenState.lastResponse ?? '';
      final parsedScreens = _parseScreensFromResponse(response);

      if (parsedScreens.isEmpty) {
        // Fallback to default screens
        parsedScreens.addAll([
          _ScreenDefinition(
            id: 'home',
            name: 'Home',
            description: 'Landing page with hero section',
          ),
          _ScreenDefinition(
            id: 'login',
            name: 'Login',
            description: 'User authentication screen',
          ),
          _ScreenDefinition(
            id: 'dashboard',
            name: 'Dashboard',
            description: 'Main user dashboard',
          ),
          _ScreenDefinition(
            id: 'settings',
            name: 'Settings',
            description: 'User settings and preferences',
          ),
        ]);
      }

      setState(() {
        _screens = parsedScreens;
        _screensAnalyzed = true;
        _isAnalyzing = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
        setState(() => _isAnalyzing = false);
      }
    }
  }

  List<_ScreenDefinition> _parseScreensFromResponse(String response) {
    final screens = <_ScreenDefinition>[];
    final lines = response.split('\n');

    for (final line in lines) {
      if (line.trim().startsWith('SCREEN|')) {
        final parts = line.trim().split('|');
        if (parts.length >= 4) {
          screens.add(_ScreenDefinition(
            id: parts[1].trim(),
            name: parts[2].trim(),
            description: parts[3].trim(),
          ));
        }
      }
    }

    return screens;
  }

  /// Generate the full prototype with all screens
  Future<void> _generateFullPrototype() async {
    if (_screens.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please analyze the project first')),
      );
      return;
    }

    // Check credits (more credits for full prototype)
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.chatMessage * (_screens.length + 2),
      feature: 'project_prototype_generate',
    );
    if (!hasCredits) return;

    setState(() {
      _isGenerating = true;
      _generationProgress = 0;
      _generationStatus = 'Preparing prototype generation...';
      _generatedDesignDocument = null;
      _previewMode = _PrototypePreviewMode.html;
      _selectedDesignScreenId = null;
      _selectedDesignNodeId = null;
      // Reset all screens to not generated
      _screens = _screens.map((s) => s.copyWith(isGenerated: false)).toList();
    });

    try {
      final planState = ref.read(planningProvider);
      final plan = planState.currentPlan;

      // Build the full prototype prompt using AI design system
      final prompt = _buildFullPrototypePrompt(plan);

      setState(() {
        _generationProgress = 0.1;
        _generationStatus = 'Generating all screens...';
      });

      final aiNotifier = ref.read(aiProvider.notifier);
      await aiNotifier.generateContent(prompt, style: ChatStyle.standard);

      final aiState = ref.read(aiProvider);
      if (aiState.error != null) {
        throw Exception(aiState.error);
      }

      setState(() {
        _generationProgress = 0.8;
        _generationStatus = 'Processing prototype package...';
      });

      final response = aiState.lastResponse ?? '';
      final structuredResponse = _extractStructuredPrototypeResponse(
        response,
        plan,
      );
      final html = structuredResponse.html;

      if (html.isNotEmpty) {
        setState(() {
          _fullPrototypeHtml = html;
          _generatedDesignDocument = structuredResponse.document;
          _generationProgress = 0.9;
          _generationStatus = 'Loading preview...';
          // Mark all screens as generated
          _screens =
              _screens.map((s) => s.copyWith(isGenerated: true)).toList();
          _currentScreen = _screens.first.id;
          _webViewReady = false;
          if (structuredResponse.document != null) {
            _previewMode = _PrototypePreviewMode.engine;
            _seedSelectionFromDocument(structuredResponse.document);
          }
        });

        await _webViewController?.loadHtmlString(html);

        // Wait for page to load then navigate to first screen
        await Future.delayed(const Duration(milliseconds: 800));
        _navigateToScreen(_screens.first.id);

        setState(() {
          _generationProgress = 1.0;
          _generationStatus = 'Complete!';
        });

        await Future.delayed(const Duration(milliseconds: 300));
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

  String _buildFullPrototypePrompt(dynamic plan) {
    // Use AI design system
    final design = _aiDesignSystem ??
        _AIDesignSystem(
          style: 'modern',
          primaryColor: '#6366F1',
          secondaryColor: '#8B5CF6',
          accentColor: '#F59E0B',
          backgroundColor: '#F8FAFC',
          textColor: '#1E293B',
          cardColor: '#FFFFFF',
          fontFamily: 'Inter',
          borderRadius: '16px',
          shadowStyle: 'soft',
          reasoning: 'Default professional design',
        );

    // Build screen divs template with placeholder content
    final screenDivs = _screens.toList().asMap().entries.map((entry) {
      final index = entry.key;
      final s = entry.value;
      return '''
    <!-- ${s.name} Screen -->
    <div id="${s.id}" class="screen${index == 0 ? ' active' : ''}">
      <header class="app-header">
        <div class="header-content">
          <h1>${s.name}</h1>
        </div>
      </header>
      <main class="screen-content">
        <!-- GENERATE_CONTENT_FOR: ${s.description} -->
      </main>
    </div>''';
    }).join('\n');

    // Build bottom nav items
    final navItems = _screens.take(5).toList().asMap().entries.map((entry) {
      final index = entry.key;
      final s = entry.value;
      final icons = {
        'home': '🏠',
        'dashboard': '📊',
        'profile': '👤',
        'settings': '⚙️',
        'search': '🔍',
        'notifications': '🔔',
        'messages': '💬',
        'menu': '☰',
        'login': '🔐',
        'register': '📝',
        'cart': '🛒',
        'favorites': '❤️',
        'analytics': '📈',
        'calendar': '📅',
        'tasks': '✅',
        'feed': '📰',
      };
      final icon = icons[s.id.toLowerCase()] ?? '📱';
      return '''<a href="#" data-screen="${s.id}" onclick="navigateTo('${s.id}'); return false;"${index == 0 ? ' class="active"' : ''}>
          <span class="nav-icon">$icon</span>
          <span class="nav-label">${s.name}</span>
        </a>''';
    }).join('\n        ');

    // Determine shadow style
    String shadowCSS;
    switch (design.shadowStyle) {
      case 'strong':
        shadowCSS = '0 10px 40px rgba(0,0,0,0.15)';
        break;
      case 'medium':
        shadowCSS = '0 4px 20px rgba(0,0,0,0.1)';
        break;
      case 'none':
        shadowCSS = 'none';
        break;
      default:
        shadowCSS = '0 2px 12px rgba(0,0,0,0.06)';
    }

    return '''Generate a PROFESSIONAL mobile app prototype package with polished UI.

**Project:** ${plan?.title ?? 'Project'}
**Description:** ${plan?.description ?? ''}

**AI-SELECTED DESIGN:**
- Style: ${design.style}
- Primary: ${design.primaryColor}
- Secondary: ${design.secondaryColor}
- Accent: ${design.accentColor}
- Font: ${design.fontFamily}

**SCREENS (${_screens.length}):**
${_screens.toList().asMap().entries.map((e) => '${e.key + 1}. ${e.value.id}: ${e.value.name} - ${e.value.description}').join('\n')}

**REQUIREMENTS:**
1. Generate ALL ${_screens.length} screens with REAL content
2. Replace each <!-- GENERATE_CONTENT_FOR: ... --> with rich UI
3. Use realistic data (names, numbers, text)
4. Use the CSS classes provided
5. Navigation: navigateTo('screenId')

Return EXACTLY two tagged sections and nothing else:

[[NOTECLAW_DESIGN_SPEC_JSON]]
{valid JSON}
[[/NOTECLAW_DESIGN_SPEC_JSON]]
[[NOTECLAW_HTML]]
<!DOCTYPE html>...full html...
</html>
[[/NOTECLAW_HTML]]

**JSON Rules:**
- The JSON root must contain: schemaVersion, title, summary, theme, screens
- theme fields: style, primaryColor, secondaryColor, accentColor, backgroundColor, surfaceColor, textColor, radius
- screens must contain exactly ${_screens.length} entries
- preserve these screen ids and names exactly:
${_screens.map((screen) => '- ${screen.id}: ${screen.name}').join('\n')}
- each screen must contain: id, name, description, nodes
- supported node types only: hero, stats_row, card_list, feature_grid, action_bar, form, timeline, quote, content, cta
- each node may contain: id, type, title, subtitle, body, label, value, icon, variant, items
- each item may contain: title, subtitle, label, value, meta, icon, tags
- the structured spec should reflect the same UI/content as the HTML prototype

**HTML Template:**

<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, viewport-fit=cover">
  <title>${plan?.title ?? 'App'}</title>
  <style>
    :root {
      --primary: ${design.primaryColor};
      --secondary: ${design.secondaryColor};
      --accent: ${design.accentColor};
      --bg: ${design.backgroundColor};
      --text: ${design.textColor};
      --card: ${design.cardColor};
      --radius: ${design.borderRadius};
      --shadow: $shadowCSS;
    }
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { 
      font-family: '${design.fontFamily}', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: var(--bg); color: var(--text);
      min-height: 100vh; overflow-x: hidden;
      -webkit-font-smoothing: antialiased;
    }
    .screen { display: none; flex-direction: column; min-height: 100vh; padding-bottom: 90px; animation: fadeIn 0.3s ease; }
    .screen.active { display: flex; }
    @keyframes fadeIn { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: translateY(0); } }
    .app-header { 
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white; padding: 20px; padding-top: max(20px, env(safe-area-inset-top));
      position: sticky; top: 0; z-index: 100;
    }
    .app-header h1 { font-size: 24px; font-weight: 700; }
    .header-content { display: flex; align-items: center; justify-content: space-between; }
    .screen-content { flex: 1; padding: 20px; overflow-y: auto; }
    .bottom-nav {
      position: fixed; bottom: 0; left: 0; right: 0; background: var(--card);
      display: flex; justify-content: space-around; padding: 10px 0;
      padding-bottom: max(14px, env(safe-area-inset-bottom));
      box-shadow: 0 -4px 20px rgba(0,0,0,0.08); z-index: 1000;
    }
    .bottom-nav a {
      display: flex; flex-direction: column; align-items: center;
      text-decoration: none; color: #94A3B8; font-size: 10px; font-weight: 500;
      padding: 8px 16px; border-radius: 12px; transition: all 0.2s ease;
    }
    .bottom-nav a.active { color: var(--primary); background: rgba(99,102,241,0.1); }
    .nav-icon { font-size: 24px; margin-bottom: 4px; }
    .nav-label { font-size: 11px; font-weight: 600; }
    .card { 
      background: var(--card); border-radius: var(--radius); padding: 20px;
      margin-bottom: 16px; box-shadow: var(--shadow);
    }
    .card-title { font-size: 16px; font-weight: 600; margin-bottom: 8px; }
    .card-subtitle { font-size: 13px; color: #64748B; }
    .btn { 
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      color: white; border: none; padding: 16px 28px; border-radius: var(--radius);
      font-size: 15px; font-weight: 600; width: 100%; cursor: pointer;
    }
    .btn-outline { background: transparent; border: 2px solid var(--primary); color: var(--primary); }
    .btn-accent { background: var(--accent); }
    .input-group { margin-bottom: 16px; }
    .input-label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 8px; }
    .input { 
      width: 100%; padding: 16px; border: 2px solid #E2E8F0; border-radius: var(--radius);
      font-size: 15px; background: var(--card);
    }
    .input:focus { outline: none; border-color: var(--primary); }
    .list-item { display: flex; align-items: center; padding: 16px 0; border-bottom: 1px solid #F1F5F9; }
    .list-item:last-child { border-bottom: none; }
    .avatar { 
      width: 48px; height: 48px; border-radius: 50%;
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      display: flex; align-items: center; justify-content: center;
      font-size: 18px; color: white; font-weight: 600; margin-right: 14px;
    }
    .avatar-sm { width: 36px; height: 36px; font-size: 14px; }
    .avatar-lg { width: 64px; height: 64px; font-size: 24px; }
    .stats-grid { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
    .stat-card { background: var(--card); border-radius: var(--radius); padding: 20px; text-align: center; box-shadow: var(--shadow); }
    .stat-value { 
      font-size: 28px; font-weight: 700;
      background: linear-gradient(135deg, var(--primary), var(--secondary));
      -webkit-background-clip: text; -webkit-text-fill-color: transparent;
    }
    .stat-label { font-size: 12px; color: #64748B; margin-top: 4px; }
    .section-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
    .section-title { font-size: 18px; font-weight: 700; }
    .section-link { font-size: 13px; color: var(--primary); font-weight: 600; text-decoration: none; }
    .chip { display: inline-flex; padding: 6px 12px; background: rgba(99,102,241,0.1); color: var(--primary); border-radius: 20px; font-size: 12px; font-weight: 600; margin-right: 8px; margin-bottom: 8px; }
    .chip-success { background: rgba(16,185,129,0.1); color: #10B981; }
    .chip-warning { background: rgba(245,158,11,0.1); color: #F59E0B; }
    .progress-bar { height: 8px; background: #E2E8F0; border-radius: 4px; overflow: hidden; }
    .progress-fill { height: 100%; background: linear-gradient(90deg, var(--primary), var(--secondary)); border-radius: 4px; }
    .empty-state { text-align: center; padding: 40px 20px; }
    .empty-icon { font-size: 48px; margin-bottom: 16px; }
    h2 { font-size: 18px; font-weight: 700; margin-bottom: 16px; }
    h3 { font-size: 16px; font-weight: 600; margin-bottom: 12px; }
    p { color: #64748B; line-height: 1.6; font-size: 14px; }
    .text-primary { color: var(--primary); }
    .text-muted { color: #94A3B8; }
    .mb-8 { margin-bottom: 8px; }
    .mb-16 { margin-bottom: 16px; }
    .mb-24 { margin-bottom: 24px; }
    .mt-16 { margin-top: 16px; }
    .flex { display: flex; }
    .items-center { align-items: center; }
    .justify-between { justify-content: space-between; }
    .gap-8 { gap: 8px; }
    .gap-12 { gap: 12px; }
    .flex-1 { flex: 1; }
    .grid-2 { display: grid; grid-template-columns: repeat(2, 1fr); gap: 12px; }
    .text-center { text-align: center; }
    .font-bold { font-weight: 700; }
    .hero { padding: 30px 20px; text-align: center; background: linear-gradient(135deg, var(--primary), var(--secondary)); color: white; border-radius: var(--radius); margin-bottom: 20px; }
    .hero h2 { color: white; margin-bottom: 8px; }
    .hero p { color: rgba(255,255,255,0.9); }
  </style>
</head>
<body>
$screenDivs

  <nav class="bottom-nav">
    $navItems
  </nav>

  <script>
    function navigateTo(screenId) {
      document.querySelectorAll('.screen').forEach(s => {
        s.classList.remove('active');
        s.style.display = 'none';
      });
      const target = document.getElementById(screenId);
      if (target) {
        target.classList.add('active');
        target.style.display = 'flex';
      }
      document.querySelectorAll('.bottom-nav a').forEach(a => {
        a.classList.remove('active');
        if (a.getAttribute('data-screen') === screenId) a.classList.add('active');
      });
      window.scrollTo(0, 0);
    }
    document.addEventListener('DOMContentLoaded', () => navigateTo('${_screens.first.id}'));
  </script>
</body>
</html>

**TASK:** Replace <!-- GENERATE_CONTENT_FOR: ... --> with REAL UI content using the CSS classes and make the HTML match the JSON screen spec.''';
  }

  String _extractHtmlFromResponse(String response) {
    // Try to find HTML content
    var html = response;

    // Remove markdown code blocks if present
    if (html.contains('```html')) {
      final start = html.indexOf('```html') + 7;
      final end = html.lastIndexOf('```');
      if (end > start) {
        html = html.substring(start, end);
      }
    } else if (html.contains('```')) {
      final start = html.indexOf('```') + 3;
      final end = html.lastIndexOf('```');
      if (end > start) {
        html = html.substring(start, end);
      }
    }

    // Find DOCTYPE or html tag
    final doctypeIndex = html.toLowerCase().indexOf('<!doctype');
    final htmlIndex = html.toLowerCase().indexOf('<html');
    final startIndex =
        doctypeIndex >= 0 ? doctypeIndex : (htmlIndex >= 0 ? htmlIndex : -1);

    if (startIndex >= 0) {
      html = html.substring(startIndex);
    }

    // Find closing html tag
    final endIndex = html.toLowerCase().lastIndexOf('</html>');
    if (endIndex >= 0) {
      html = html.substring(0, endIndex + 7);
    }

    return html.trim();
  }

  _StructuredPrototypeResponse _extractStructuredPrototypeResponse(
    String response,
    dynamic plan,
  ) {
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

    document ??= _buildFallbackPrototypeDocument(plan);

    final html = _extractHtmlFromResponse(
      htmlBlock != null && htmlBlock.trim().isNotEmpty ? htmlBlock : response,
    );

    return _StructuredPrototypeResponse(
      html: html,
      document: document,
    );
  }

  String? _extractTaggedBlock(String text, String startTag, String endTag) {
    final startIndex = text.indexOf(startTag);
    final endIndex = text.indexOf(endTag);
    if (startIndex == -1 || endIndex == -1 || endIndex <= startIndex) {
      return null;
    }
    return text.substring(startIndex + startTag.length, endIndex).trim();
  }

  DesignDocument _buildFallbackPrototypeDocument(dynamic plan) {
    final title = plan?.title?.toString() ?? 'Generated Prototype';
    final summary = plan?.description?.toString() ?? '';

    return DesignDocument(
      schemaVersion: 1,
      title: title,
      summary: summary,
      theme: _buildPrototypeTheme(),
      screens: _screens.asMap().entries.map((entry) {
        final index = entry.key;
        final screen = entry.value;
        return DesignScreenSpec(
          id: screen.id,
          name: screen.name,
          description: screen.description,
          nodes: [
            DesignNodeSpec(
              id: '${screen.id}_hero',
              type: 'hero',
              title: screen.name,
              subtitle: screen.description,
              body: summary.isNotEmpty
                  ? 'Designed as part of $title.'
                  : 'Structured fallback preview for ${screen.name}.',
              label: index == 0 ? 'Primary Screen' : 'Prototype Screen',
              value: '',
              icon: '',
              variant: '',
              items: [
                DesignNodeItem(
                  title: index == 0 ? 'Open Screen' : 'View Details',
                  subtitle: '',
                  label: '',
                  value: '',
                  meta: '',
                  icon: '',
                  tags: const [],
                ),
                const DesignNodeItem(
                  title: 'Next Step',
                  subtitle: '',
                  label: '',
                  value: '',
                  meta: '',
                  icon: '',
                  tags: [],
                ),
              ],
              children: const [],
              props: const {},
            ),
            DesignNodeSpec(
              id: '${screen.id}_content',
              type: index == 0 ? 'feature_grid' : 'content',
              title: index == 0 ? 'Core Areas' : 'Screen Purpose',
              subtitle: '',
              body: index == 0 ? '' : screen.description,
              label: '',
              value: '',
              icon: '',
              variant: '',
              items: index == 0
                  ? _screens
                      .take(4)
                      .map(
                        (item) => DesignNodeItem(
                          title: item.name,
                          subtitle: item.description,
                          label: '',
                          value: '',
                          meta: '',
                          icon: '',
                          tags: const [],
                        ),
                      )
                      .toList()
                  : [
                      DesignNodeItem(
                        title: 'Goal',
                        subtitle: screen.description,
                        label: '',
                        value: '',
                        meta: '',
                        icon: '',
                        tags: const [],
                      ),
                    ],
              children: const [],
              props: const {},
            ),
          ],
        );
      }).toList(),
    );
  }

  DesignThemeSpec _buildPrototypeTheme() {
    final design = _aiDesignSystem;
    return DesignThemeSpec(
      style: design?.style ?? 'modern',
      primaryColor: design?.primaryColor ?? '#6366F1',
      secondaryColor: design?.secondaryColor ?? '#8B5CF6',
      accentColor: design?.accentColor ?? '#F59E0B',
      backgroundColor: design?.backgroundColor ?? '#F8FAFC',
      surfaceColor: design?.cardColor ?? '#FFFFFF',
      textColor: design?.textColor ?? '#1E293B',
      radius: _parseRadiusValue(design?.borderRadius),
    );
  }

  double _parseRadiusValue(String? value) {
    if (value == null || value.trim().isEmpty) return 16;
    final parsed = double.tryParse(value.replaceAll('px', '').trim());
    return parsed ?? 16;
  }

  String _buildPrototypeNodeRegenerationPrompt({
    required dynamic plan,
    required DesignDocument document,
    required DesignScreenSpec screen,
    required DesignNodeSpec node,
  }) {
    final projectTitle = plan?.title?.toString() ?? 'Project';
    final projectDescription = plan?.description?.toString() ?? '';
    final screenSummary = _screens
        .map((item) => '- ${item.id}: ${item.name} - ${item.description}')
        .join('\n');

    return '''Rewrite one structured node for a mobile app prototype.

**Project:** $projectTitle
**Description:** $projectDescription

**Theme JSON:**
${jsonEncode(document.theme.toJson())}

**Prototype Screens:**
$screenSummary

**Selected Screen JSON:**
${jsonEncode(screen.toJson())}

**Current Node JSON:**
${jsonEncode(node.toJson())}

**Task:**
- Rewrite ONLY the selected node to feel more realistic, polished, and product-ready
- Preserve the same node `id`
- Preserve the same node `type`
- Keep the content aligned with the selected screen and overall project
- You may improve: title, subtitle, body, label, value, icon, variant, items, props
- If the node uses items, return realistic items that fit the prototype context

Return ONLY one valid JSON object for the rewritten node.
Do not include markdown, explanations, or code fences.''';
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
      final image = await _screenshotController.capture();
      if (image != null) {
        setState(() => _screenshot = image);

        // Save to file
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${directory.path}/prototype_$timestamp.png');
        await file.writeAsBytes(image);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(LucideIcons.check, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Screenshot saved!'),
                ],
              ),
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

  Future<void> _exportHtml() async {
    if (_fullPrototypeHtml == null) return;

    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${directory.path}/prototype_$timestamp.html');
      await file.writeAsString(_fullPrototypeHtml!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Exported to: ${file.path}'),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _saveAsDesignNote() async {
    if (_fullPrototypeHtml == null) return;

    setState(() => _isSaving = true);

    try {
      String screenshotPath = '';

      // Save screenshot if captured
      if (_screenshot != null) {
        final directory = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        screenshotPath = '${directory.path}/prototype_$timestamp.png';
        final file = File(screenshotPath);
        await file.writeAsBytes(_screenshot!);
      }

      // Build screen list for the note
      final screenList = _screens
          .map((s) => '- **${s.name}** (${s.id}): ${s.description}')
          .join('\n');

      const codeBlockStart = '```html';
      const codeBlockEnd = '```';
      final designStyle = _aiDesignSystem?.style ?? 'modern';
      final designColors = _aiDesignSystem != null
          ? '${_aiDesignSystem!.primaryColor}, ${_aiDesignSystem!.secondaryColor}, ${_aiDesignSystem!.accentColor}'
          : 'AI-selected';
      final designContent = '''## 🎨 Full Project Prototype

**Type:** Interactive Multi-Screen Prototype
**Style:** $designStyle
**Colors:** $designColors
**Generated:** ${DateTime.now().toIso8601String()}
**Screens:** ${_screens.length}

### Screens Included:
$screenList

${screenshotPath.isNotEmpty ? '''
### Preview Screenshot
![Prototype Preview](file://$screenshotPath)
''' : ''}

### Interactive HTML Prototype
$codeBlockStart
$_fullPrototypeHtml
$codeBlockEnd

---
*This is a fully interactive prototype. Open the HTML file in a browser to navigate between screens.*
''';

      final planning = ref.read(planningProvider.notifier);
      final generatedAt = DateTime.now().toIso8601String();
      final designDocumentJson = _generatedDesignDocument?.toJson();

      final designNote = await planning.createDesignNote(
        content: designContent,
        requirementIds: [],
      );
      final designArtifact = await planning.createDesignArtifact(
        name: 'Interactive Prototype',
        artifactType: DesignArtifactType.prototype,
        status: DesignArtifactStatus.ready,
        source: DesignArtifactSource.aiGenerated,
        schemaVersion: designDocumentJson != null ? 2 : 1,
        rootData: {
          'format': designDocumentJson != null ? 'structured_html' : 'html',
          'html': _fullPrototypeHtml,
          if (designDocumentJson != null) 'document': designDocumentJson,
          'screens': _screens
              .map(
                (screen) => {
                  'id': screen.id,
                  'name': screen.name,
                  'description': screen.description,
                  'isGenerated': screen.isGenerated,
                  if (screen.html != null) 'html': screen.html,
                },
              )
              .toList(),
          'designSystem': {
            'style': _aiDesignSystem?.style,
            'primaryColor': _aiDesignSystem?.primaryColor,
            'secondaryColor': _aiDesignSystem?.secondaryColor,
            'accentColor': _aiDesignSystem?.accentColor,
            'backgroundColor': _aiDesignSystem?.backgroundColor,
            'textColor': _aiDesignSystem?.textColor,
            'cardColor': _aiDesignSystem?.cardColor,
            'fontFamily': _aiDesignSystem?.fontFamily,
            'borderRadius': _aiDesignSystem?.borderRadius,
            'shadowStyle': _aiDesignSystem?.shadowStyle,
            'reasoning': _aiDesignSystem?.reasoning,
          },
        },
        metadata: {
          'generatedAt': generatedAt,
          'screenCount': _screens.length,
          'screenshotPath': screenshotPath,
          'hasStructuredPreview': designDocumentJson != null,
        },
        changeSummary: designDocumentJson != null
            ? 'Initial AI-generated interactive prototype with structured screen spec'
            : 'Initial AI-generated interactive prototype',
      );

      if (designNote == null && designArtifact == null) {
        throw Exception('Failed to save prototype outputs');
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
                        ? 'Prototype saved with ${_screens.length} screens.'
                        : 'Prototype saved partially. Check plan outputs.',
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
