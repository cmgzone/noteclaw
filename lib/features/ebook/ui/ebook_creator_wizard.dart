import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import '../models/ebook_project.dart';
import '../models/branding_config.dart';
import '../agents/ebook_orchestrator.dart';
import 'ebook_generation_view.dart';
import '../../notebook/notebook_provider.dart';
import '../ebook_provider.dart';

import '../../../core/ai/ai_models_provider.dart';
import '../../../core/ai/ai_settings_service.dart';
import '../../subscription/services/credit_manager.dart';

class EbookCreatorWizard extends ConsumerStatefulWidget {
  const EbookCreatorWizard({super.key});

  @override
  ConsumerState<EbookCreatorWizard> createState() => _EbookCreatorWizardState();
}

class _EbookCreatorWizardState extends ConsumerState<EbookCreatorWizard> {
  static const Uuid _uuid = Uuid();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _topicController = TextEditingController();
  final _audienceController = TextEditingController();
  final _authorController = TextEditingController();

  Color _selectedColor = const Color(0xFF2196F3);
  String _selectedModel = '';
  String? _selectedNotebookId;
  int _currentStep = 0;

  // Deep Research settings
  bool _useDeepResearch = false;
  ImageSourceType _imageSource = ImageSourceType.aiGenerated;

  @override
  void initState() {
    super.initState();
    _loadGlobalAISettings();
  }

  Future<void> _loadGlobalAISettings() async {
    final settings =
        await AISettingsService.getSettingsWithDefault(ref.read);
    final globalModel = settings.model;
    if (globalModel != null && globalModel.isNotEmpty && mounted) {
      setState(() => _selectedModel = globalModel);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Ebook'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Stepper(
          currentStep: _currentStep,
          onStepContinue: _onStepContinue,
          onStepCancel: _onStepCancel,
          controlsBuilder: (context, details) {
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Row(
                children: [
                  FilledButton(
                    onPressed: details.onStepContinue,
                    child: Text(_currentStep == 3 ? 'Start Magic' : 'Next'),
                  ),
                  if (_currentStep > 0) ...[
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: details.onStepCancel,
                      child: const Text('Back'),
                    ),
                  ],
                ],
              ),
            );
          },
          steps: [
            Step(
              title: const Text('Concept'),
              content: Column(
                children: [
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Book Title',
                      hintText: 'e.g., The Future of AI',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _topicController,
                    decoration: const InputDecoration(
                      labelText: 'Topic / Subject',
                      hintText: 'What is this book about?',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _audienceController,
                    decoration: const InputDecoration(
                      labelText: 'Target Audience',
                      hintText: 'e.g., Beginners, Experts, Students',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => v?.isEmpty == true ? 'Required' : null,
                  ),
                ],
              ),
              isActive: _currentStep >= 0,
            ),
            Step(
              title: const Text('Context (Optional)'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select a Notebook to ground your ebook in your own sources.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Consumer(
                    builder: (context, ref, child) {
                      final notebooks = ref.watch(notebookProvider);

                      if (notebooks.isEmpty) {
                        return const Text(
                            'No notebooks found. Create one in the Home screen.');
                      }

                      return DropdownButtonFormField<String>(
                        initialValue: _selectedNotebookId,
                        decoration: const InputDecoration(
                          labelText: 'Select Notebook',
                          border: OutlineInputBorder(),
                        ),
                        style: TextStyle(color: scheme.onSurface),
                        dropdownColor: scheme.surfaceContainer,
                        items: [
                          DropdownMenuItem(
                            value: null,
                            child: Text(
                              'None (Use AI Knowledge only)',
                              style: TextStyle(color: scheme.onSurface),
                            ),
                          ),
                          ...notebooks.map((n) => DropdownMenuItem(
                                value: n.id,
                                child: Text(
                                  n.title,
                                  style: TextStyle(color: scheme.onSurface),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedNotebookId = v),
                        selectedItemBuilder: (context) {
                          return [
                            Text(
                              'None (Use AI Knowledge only)',
                              style: TextStyle(color: scheme.onSurface),
                            ),
                            ...notebooks.map((n) => Text(
                                  n.title,
                                  style: TextStyle(color: scheme.onSurface),
                                  overflow: TextOverflow.ellipsis,
                                )),
                          ];
                        },
                      );
                    },
                  ),
                ],
              ),
              isActive: _currentStep >= 1,
            ),
            Step(
              title: const Text('Branding'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _authorController,
                    decoration: const InputDecoration(
                      labelText: 'Author Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('Primary Color', style: text.titleSmall),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      Colors.blue,
                      Colors.red,
                      Colors.green,
                      Colors.orange,
                      Colors.purple,
                      Colors.teal,
                      Colors.pink,
                      Colors.indigo,
                    ].map((color) {
                      final isSelected =
                          _selectedColor.toARGB32() == color.toARGB32();
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = color),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(color: scheme.primary, width: 3)
                                : null,
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              isActive: _currentStep >= 2,
            ),
            Step(
              title: const Text('Research Mode'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Deep Research Toggle
                  Container(
                    decoration: BoxDecoration(
                      color: _useDeepResearch
                          ? scheme.primaryContainer.withValues(alpha: 0.3)
                          : scheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _useDeepResearch
                            ? scheme.primary.withValues(alpha: 0.5)
                            : scheme.outline.withValues(alpha: 0.2),
                        width: _useDeepResearch ? 2 : 1,
                      ),
                    ),
                    child: SwitchListTile(
                      title: Text(
                        'Enable Deep Research',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: _useDeepResearch
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                      subtitle: const Text(
                        'Search the web for comprehensive, up-to-date information on your topic',
                      ),
                      value: _useDeepResearch,
                      onChanged: (value) {
                        setState(() => _useDeepResearch = value);
                      },
                      secondary: Icon(
                        LucideIcons.globe,
                        color: _useDeepResearch
                            ? scheme.primary
                            : scheme.onSurface,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Image Source Selection
                  Text('Image Source', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Choose how images are generated for your ebook',
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // AI Generated Option
                  _buildImageSourceOption(
                    scheme: scheme,
                    text: text,
                    icon: LucideIcons.sparkles,
                    title: 'AI Generated',
                    subtitle: 'Create unique images using Gemini AI',
                    value: ImageSourceType.aiGenerated,
                    groupValue: _imageSource,
                    onChanged: (v) => setState(() => _imageSource = v!),
                  ),
                  const SizedBox(height: 8),

                  // Web Search Option
                  _buildImageSourceOption(
                    scheme: scheme,
                    text: text,
                    icon: LucideIcons.search,
                    title: 'Web Search',
                    subtitle: 'Find relevant images from the web',
                    value: ImageSourceType.webSearch,
                    groupValue: _imageSource,
                    onChanged: (v) => setState(() => _imageSource = v!),
                    enabled: _useDeepResearch,
                  ),
                  const SizedBox(height: 8),

                  // Both Option
                  _buildImageSourceOption(
                    scheme: scheme,
                    text: text,
                    icon: LucideIcons.layers,
                    title: 'Both',
                    subtitle: 'Use AI for cover, web images for chapters',
                    value: ImageSourceType.both,
                    groupValue: _imageSource,
                    onChanged: (v) => setState(() => _imageSource = v!),
                    enabled: _useDeepResearch,
                  ),

                  if (!_useDeepResearch &&
                      _imageSource != ImageSourceType.aiGenerated) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(LucideIcons.info, size: 16, color: scheme.error),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Web search images require Deep Research to be enabled',
                              style:
                                  text.bodySmall?.copyWith(color: scheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              isActive: _currentStep >= 3,
            ),
            Step(
              title: const Text('AI Configuration'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select AI Model', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final modelsAsync = ref.watch(availableModelsProvider);
                      return modelsAsync.when(
                        loading: () => const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                        error: (e, s) => Center(child: Text('Error: $e')),
                        data: (models) {
                          final allModels = models.entries
                              .expand((entry) => entry.value)
                              .toList();

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                initialValue: _selectedModel.isEmpty &&
                                        allModels.isNotEmpty
                                    ? allModels.first.id
                                    : _selectedModel,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  helperText:
                                      'Select the AI model for generation',
                                ),
                                style: TextStyle(color: scheme.onSurface),
                                dropdownColor: scheme.surfaceContainer,
                                items: allModels
                                    .map((m) => DropdownMenuItem(
                                          value: m.id,
                                          child: Text(
                                            '${m.name}${m.provider != 'gemini' ? ' (${m.provider})' : ''}',
                                            style: TextStyle(
                                                color: scheme.onSurface),
                                          ),
                                        ))
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedModel = v!),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Models with "/" use OpenRouter. Others use Gemini API directly.',
                                style: text.bodySmall?.copyWith(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.bot, color: scheme.primary),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Ready to Deploy Agents',
                                style: text.titleSmall?.copyWith(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _useDeepResearch
                                    ? '• Deep Research Agent\n• Research Agent\n• Content Agent\n• Designer Agent'
                                    : '• Research Agent\n• Content Agent\n• Designer Agent',
                                style: text.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              isActive: _currentStep >= 4,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required ColorScheme scheme,
    required TextTheme text,
    required IconData icon,
    required String title,
    required String subtitle,
    required ImageSourceType value,
    required ImageSourceType groupValue,
    required ValueChanged<ImageSourceType?> onChanged,
    bool enabled = true,
  }) {
    final isSelected = value == groupValue;
    final effectiveEnabled = enabled || value == ImageSourceType.aiGenerated;

    return Opacity(
      opacity: effectiveEnabled ? 1.0 : 0.5,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outline.withValues(alpha: 0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: effectiveEnabled ? () => onChanged(value) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                // Selection indicator (replaces deprecated Radio)
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? scheme.primary : scheme.outline,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: scheme.primary,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Icon(icon,
                    size: 20,
                    color: isSelected ? scheme.primary : scheme.onSurface),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected ? scheme.primary : scheme.onSurface,
                        ),
                      ),
                      Text(subtitle, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onStepContinue() {
    if (_currentStep < 4) {
      if (_currentStep == 0 && !_formKey.currentState!.validate()) return;
      // Auto-select AI generated if deep research is disabled
      if (_currentStep == 3 &&
          !_useDeepResearch &&
          _imageSource != ImageSourceType.aiGenerated) {
        setState(() => _imageSource = ImageSourceType.aiGenerated);
      }
      setState(() => _currentStep++);
    } else {
      _startGeneration();
    }
  }

  void _onStepCancel() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      context.pop();
    }
  }

  Future<void> _startGeneration() async {
    final project = EbookProject(
      id: _uuid.v4(),
      title: _titleController.text,
      topic: _topicController.text,
      targetAudience: _audienceController.text,
      branding: BrandingConfig(
        primaryColorValue: _selectedColor.toARGB32(),
        authorName: _authorController.text,
      ),
      selectedModel: _selectedModel,
      notebookId: _selectedNotebookId,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      // Deep Research settings
      useDeepResearch: _useDeepResearch,
      imageSource: _imageSource,
    );

    final savedDraft = await ref.read(ebookProvider.notifier).addEbook(project);
    if (!savedDraft) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to save your ebook draft to the library.'),
        ),
      );
      return;
    }

    // Check and consume credits for ebook generation after the draft exists
    final hasCredits = await ref.tryUseCredits(
      context: context,
      amount: CreditCosts.ebookGeneration,
      feature: 'ebook_generation',
    );
    if (!hasCredits) return;

    // Initialize orchestrator
    ref.read(ebookOrchestratorProvider.notifier).setProject(project);

    // Navigate to generation view
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EbookGenerationView()),
      );
    }

    // Start the magic
    ref.read(ebookOrchestratorProvider.notifier).startGeneration(project);
  }
}
