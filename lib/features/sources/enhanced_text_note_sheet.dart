import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import 'source_provider.dart';
import 'source.dart';
import '../../core/ai/ai_settings_service.dart';
import '../../core/api/api_service.dart';

/// AI Writing Tools available for text notes
enum AIWritingTool {
  improve('Improve Writing', Icons.auto_fix_high, 'Enhance clarity and flow'),
  grammar('Fix Grammar', Icons.spellcheck, 'Correct grammar and spelling'),
  summarize('Summarize', Icons.compress, 'Create a concise summary'),
  expand('Expand', Icons.expand, 'Add more detail and depth'),
  simplify('Simplify', Icons.lightbulb_outline, 'Make it easier to understand'),
  professional('Professional Tone', Icons.business, 'Formal business style'),
  casual('Casual Tone', Icons.emoji_emotions, 'Friendly conversational style'),
  bullets(
      'To Bullet Points', Icons.format_list_bulleted, 'Convert to bullet list'),
  translate('Translate', Icons.translate, 'Translate to another language'),
  custom('Custom Prompt', Icons.edit_note, 'Your own AI instruction');

  final String label;
  final IconData icon;
  final String description;
  const AIWritingTool(this.label, this.icon, this.description);
}

class EnhancedTextNoteSheet extends ConsumerStatefulWidget {
  final String? notebookId;
  final Source? existingSource; // For edit mode

  const EnhancedTextNoteSheet({
    super.key,
    this.notebookId,
    this.existingSource,
  });

  @override
  ConsumerState<EnhancedTextNoteSheet> createState() =>
      _EnhancedTextNoteSheetState();
}

class _EnhancedTextNoteSheetState extends ConsumerState<EnhancedTextNoteSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  final TextEditingController _customPromptController = TextEditingController();

  bool _isSubmitting = false;
  bool _isProcessingAI = false;
  bool _isListening = false;
  String _partialSpeech = '';

  // Speech to text
  final SpeechToText _speech = SpeechToText();
  bool _speechAvailable = false;

  // Undo/Redo stack
  final List<String> _undoStack = [];
  final List<String> _redoStack = [];

  // Word count
  int _wordCount = 0;
  int _charCount = 0;

  // Selected text for AI operations
  String? _selectedText;

  late AnimationController _pulseController;

  bool get isEditMode => widget.existingSource != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.existingSource?.title ?? '',
    );
    _contentController = TextEditingController(
      text: widget.existingSource?.content ?? '',
    );

    _contentController.addListener(_updateCounts);
    _updateCounts();

    _initSpeech();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  Future<void> _initSpeech() async {
    _speechAvailable = await _speech.initialize(
      onError: (error) => debugPrint('Speech error: $error'),
      onStatus: (status) => debugPrint('Speech status: $status'),
    );
    if (mounted) setState(() {});
  }

  void _updateCounts() {
    final text = _contentController.text;
    setState(() {
      _charCount = text.length;
      _wordCount =
          text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    });
  }

  void _saveToUndoStack() {
    _undoStack.add(_contentController.text);
    _redoStack.clear();
    if (_undoStack.length > 50) _undoStack.removeAt(0);
  }

  void _undo() {
    if (_undoStack.isNotEmpty) {
      _redoStack.add(_contentController.text);
      _contentController.text = _undoStack.removeLast();
      _contentController.selection = TextSelection.collapsed(
        offset: _contentController.text.length,
      );
    }
  }

  void _redo() {
    if (_redoStack.isNotEmpty) {
      _undoStack.add(_contentController.text);
      _contentController.text = _redoStack.removeLast();
      _contentController.selection = TextSelection.collapsed(
        offset: _contentController.text.length,
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _customPromptController.dispose();
    _pulseController.dispose();
    _speech.stop();
    super.dispose();
  }

  // Voice dictation
  Future<void> _toggleVoiceInput() async {
    if (!_speechAvailable) {
      _showSnackBar('Speech recognition not available', isError: true);
      return;
    }

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    } else {
      _saveToUndoStack();
      setState(() {
        _isListening = true;
        _partialSpeech = '';
      });

      await _speech.listen(
        onResult: (SpeechRecognitionResult result) {
          setState(() {
            _partialSpeech = result.recognizedWords;
            if (result.finalResult) {
              final currentText = _contentController.text;
              final newText = currentText.isEmpty
                  ? result.recognizedWords
                  : '$currentText ${result.recognizedWords}';
              _contentController.text = newText;
              _contentController.selection = TextSelection.collapsed(
                offset: newText.length,
              );
              _partialSpeech = '';
            }
          });
        },
        listenFor: const Duration(seconds: 60),
        pauseFor: const Duration(seconds: 3),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          autoPunctuation: true,
        ),
      );
    }
  }

  // Helper to call AI with proper settings via Backend Proxy
  Future<String> _callAI(String prompt) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final model = settings.model;

    if (model == null || model.isEmpty) {
      throw Exception(
          'No AI model selected. Please configure a model in settings.');
    }

    debugPrint(
        '[EnhancedTextNote] Using AI provider: ${settings.provider}, model: $model');

    // Use Backend Proxy for all AI calls (uses Admin's API keys)
    final apiService = ref.read(apiServiceProvider);
    final messages = [
      {'role': 'user', 'content': prompt}
    ];

    return await apiService.chatWithAI(
      messages: messages,
      provider: settings.provider,
      model: model,
      billingFeature: 'chat_message',
    );
  }

  // AI Writing Tools
  Future<void> _applyAITool(AIWritingTool tool) async {
    final textToProcess = _selectedText ?? _contentController.text;

    if (textToProcess.trim().isEmpty) {
      _showSnackBar('Please enter some text first', isError: true);
      return;
    }

    if (tool == AIWritingTool.custom) {
      _showCustomPromptDialog(textToProcess);
      return;
    }

    if (tool == AIWritingTool.translate) {
      _showTranslateDialog(textToProcess);
      return;
    }

    _saveToUndoStack();
    setState(() => _isProcessingAI = true);

    try {
      final prompt = _buildPrompt(tool, textToProcess);
      final result = await _callAI(prompt);
      _applyResult(result.trim());
      _showSnackBar('${tool.label} applied successfully');
    } catch (e) {
      _showSnackBar('AI processing failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  String _buildPrompt(AIWritingTool tool, String text) {
    switch (tool) {
      case AIWritingTool.improve:
        return '''Improve the following text for better clarity, flow, and readability. 
Keep the same meaning and tone. Only return the improved text, no explanations.

Text:
$text''';

      case AIWritingTool.grammar:
        return '''Fix all grammar, spelling, and punctuation errors in the following text.
Keep the same meaning and style. Only return the corrected text, no explanations.

Text:
$text''';

      case AIWritingTool.summarize:
        return '''Create a concise summary of the following text.
Capture the key points in 2-3 sentences. Only return the summary, no explanations.

Text:
$text''';

      case AIWritingTool.expand:
        return '''Expand the following text with more detail, examples, and depth.
Keep the same tone and style. Only return the expanded text, no explanations.

Text:
$text''';

      case AIWritingTool.simplify:
        return '''Simplify the following text to make it easier to understand.
Use simpler words and shorter sentences. Only return the simplified text, no explanations.

Text:
$text''';

      case AIWritingTool.professional:
        return '''Rewrite the following text in a professional, formal business tone.
Keep the same meaning. Only return the rewritten text, no explanations.

Text:
$text''';

      case AIWritingTool.casual:
        return '''Rewrite the following text in a casual, friendly conversational tone.
Keep the same meaning. Only return the rewritten text, no explanations.

Text:
$text''';

      case AIWritingTool.bullets:
        return '''Convert the following text into a well-organized bullet point list.
Extract key points and organize them logically. Only return the bullet points, no explanations.

Text:
$text''';

      default:
        return text;
    }
  }

  void _applyResult(String result) {
    if (_selectedText != null) {
      // Replace only selected text
      final text = _contentController.text;
      final selection = _contentController.selection;
      final newText = text.replaceRange(selection.start, selection.end, result);
      _contentController.text = newText;
      _contentController.selection = TextSelection.collapsed(
        offset: selection.start + result.length,
      );
      _selectedText = null;
    } else {
      // Replace all content
      _contentController.text = result;
      _contentController.selection = TextSelection.collapsed(
        offset: result.length,
      );
    }
  }

  void _showCustomPromptDialog(String text) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note),
            SizedBox(width: 8),
            Text('Custom AI Prompt'),
          ],
        ),
        content: TextField(
          controller: _customPromptController,
          decoration: const InputDecoration(
            hintText: 'e.g., "Make it more persuasive" or "Add humor"',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processCustomPrompt(text, _customPromptController.text);
              _customPromptController.clear();
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _processCustomPrompt(String text, String instruction) async {
    if (instruction.trim().isEmpty) return;

    _saveToUndoStack();
    setState(() => _isProcessingAI = true);

    try {
      final prompt = '''$instruction

Apply this instruction to the following text. Only return the modified text, no explanations.

Text:
$text''';

      final result = await _callAI(prompt);
      _applyResult(result.trim());
      _showSnackBar('Custom transformation applied');
    } catch (e) {
      _showSnackBar('AI processing failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  void _showTranslateDialog(String text) {
    final languages = [
      ('Spanish', 'es'),
      ('French', 'fr'),
      ('German', 'de'),
      ('Italian', 'it'),
      ('Portuguese', 'pt'),
      ('Chinese', 'zh'),
      ('Japanese', 'ja'),
      ('Korean', 'ko'),
      ('Arabic', 'ar'),
      ('Hindi', 'hi'),
      ('Russian', 'ru'),
    ];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.translate),
            SizedBox(width: 8),
            Text('Translate To'),
          ],
        ),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: languages.length,
            itemBuilder: (_, i) => ListTile(
              title: Text(languages[i].$1),
              onTap: () {
                Navigator.pop(ctx);
                _translateText(text, languages[i].$1);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _translateText(String text, String targetLanguage) async {
    _saveToUndoStack();
    setState(() => _isProcessingAI = true);

    try {
      final prompt = '''Translate the following text to $targetLanguage.
Only return the translated text, no explanations.

Text:
$text''';

      final result = await _callAI(prompt);
      _applyResult(result.trim());
      _showSnackBar('Translated to $targetLanguage');
    } catch (e) {
      _showSnackBar('Translation failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  // Generate content from title
  Future<void> _generateFromTitle() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      _showSnackBar('Please enter a title first', isError: true);
      return;
    }

    _saveToUndoStack();
    setState(() => _isProcessingAI = true);

    try {
      final prompt = '''Write a detailed note about: "$title"

Include relevant information, key points, and useful details.
Format it nicely with paragraphs. Keep it informative and well-structured.''';

      final result = await _callAI(prompt);
      _contentController.text = result.trim();
      _showSnackBar('Content generated from title');
    } catch (e) {
      _showSnackBar('Generation failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isProcessingAI = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty || content.isEmpty) {
      _showSnackBar('Please enter both title and content', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (isEditMode) {
        await ref.read(sourceProvider.notifier).updateSource(
              sourceId: widget.existingSource!.id,
              title: title,
              content: content,
            );
      } else {
        await ref.read(sourceProvider.notifier).addSource(
              title: title,
              type: 'text',
              content: content,
              notebookId: widget.notebookId,
            );
      }

      if (!mounted) return;
      Navigator.pop(context);
      _showSnackBar(isEditMode ? 'Note updated' : 'Note added');
    } catch (e) {
      _showSnackBar('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(
                    isEditMode ? Icons.edit_note : Icons.note_add,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isEditMode ? 'Edit Note' : 'New Note',
                    style: text.titleLarge,
                  ),
                  const Spacer(),
                  // Word count
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$_wordCount words',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(),

            // Content
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title field with AI generate button
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              labelText: 'Title',
                              hintText: 'Enter note title',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              prefixIcon: const Icon(Icons.title),
                            ),
                            textInputAction: TextInputAction.next,
                            enabled: !_isSubmitting && !_isProcessingAI,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Generate content from title',
                          child: IconButton.filled(
                            onPressed:
                                _isProcessingAI ? null : _generateFromTitle,
                            icon: const Icon(Icons.auto_awesome),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // AI Tools toolbar
                    _buildAIToolbar(scheme),

                    const SizedBox(height: 12),

                    // Content field with voice input
                    Stack(
                      children: [
                        TextField(
                          controller: _contentController,
                          decoration: InputDecoration(
                            labelText: 'Content',
                            hintText: _isListening
                                ? 'Listening... speak now'
                                : 'Write your note or use voice/AI...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignLabelWithHint: true,
                            suffixIcon: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Voice input button
                                AnimatedBuilder(
                                  animation: _pulseController,
                                  builder: (context, child) => IconButton(
                                    onPressed:
                                        _speechAvailable && !_isProcessingAI
                                            ? _toggleVoiceInput
                                            : null,
                                    icon: Icon(
                                      _isListening ? Icons.mic : Icons.mic_none,
                                      color: _isListening
                                          ? Color.lerp(
                                              Colors.red,
                                              Colors.red.shade300,
                                              _pulseController.value,
                                            )
                                          : null,
                                    ),
                                    tooltip:
                                        _isListening ? 'Stop' : 'Voice input',
                                  ),
                                ),
                                // Undo/Redo
                                IconButton(
                                  onPressed:
                                      _undoStack.isNotEmpty ? _undo : null,
                                  icon: const Icon(Icons.undo, size: 20),
                                  tooltip: 'Undo',
                                ),
                                IconButton(
                                  onPressed:
                                      _redoStack.isNotEmpty ? _redo : null,
                                  icon: const Icon(Icons.redo, size: 20),
                                  tooltip: 'Redo',
                                ),
                              ],
                            ),
                          ),
                          maxLines: 12,
                          minLines: 8,
                          textInputAction: TextInputAction.newline,
                          enabled: !_isSubmitting && !_isProcessingAI,
                          onChanged: (_) {
                            // Track selection for partial AI operations
                            final selection = _contentController.selection;
                            if (selection.isValid && !selection.isCollapsed) {
                              _selectedText = _contentController.text.substring(
                                selection.start,
                                selection.end,
                              );
                            } else {
                              _selectedText = null;
                            }
                          },
                        ),

                        // Partial speech overlay
                        if (_isListening && _partialSpeech.isNotEmpty)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            right: 48,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer
                                    .withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _partialSpeech,
                                style: text.bodySmall?.copyWith(
                                  color: scheme.onPrimaryContainer,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          ),

                        // AI Processing overlay
                        if (_isProcessingAI)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: scheme.surface.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    Text(
                                      'AI is working...',
                                      style: text.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Character count
                    Text(
                      '$_charCount characters',
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.right,
                    ),

                    const SizedBox(height: 20),

                    // Submit button
                    FilledButton.icon(
                      onPressed:
                          _isSubmitting || _isProcessingAI ? null : _submit,
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(isEditMode ? Icons.save : Icons.check),
                      label: Text(
                        _isSubmitting
                            ? (isEditMode ? 'Updating...' : 'Adding...')
                            : (isEditMode ? 'Update Note' : 'Add Note'),
                      ),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAIToolbar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'AI Writing Tools',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              if (_selectedText != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Selection',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onTertiaryContainer,
                        ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: AIWritingTool.values.map((tool) {
              return Tooltip(
                message: tool.description,
                child: ActionChip(
                  avatar: Icon(tool.icon, size: 16),
                  label: Text(tool.label, style: const TextStyle(fontSize: 12)),
                  onPressed: _isProcessingAI ? null : () => _applyAITool(tool),
                  visualDensity: VisualDensity.compact,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
