import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../ui/widgets/app_network_image.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/message.dart';
import '../chat/chat_provider.dart';
import '../chat/stream_provider.dart';
import '../sources/source_detail_screen.dart';
import '../notebook/notebook_provider.dart';
import 'package:go_router/go_router.dart';
import '../../core/ai/ai_provider.dart';
import '../../core/api/api_service.dart';
import '../sources/source_provider.dart';
import '../../core/extensions/color_compat.dart';
//
import '../../theme/motion.dart';
import '../../core/audio/voice_service.dart';
import 'context_usage_widget.dart';
import 'github_action_detector.dart';
import '../github/github_issue_dialog.dart';
import '../custom_agents/custom_agents_provider.dart';

class EnhancedChatScreen extends ConsumerStatefulWidget {
  const EnhancedChatScreen({super.key});

  @override
  ConsumerState<EnhancedChatScreen> createState() => _EnhancedChatScreenState();
}

class _EnhancedChatScreenState extends ConsumerState<EnhancedChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _showAIWriting = false;
  String _writingMode = 'notes';
  final AudioPlayer _player = AudioPlayer();
  final AudioRecorder _recorder = AudioRecorder();
  bool _recording = false;
  bool _isDeepSearchEnabled = false;
  bool _isWebBrowsingEnabled = false; // New: Web browsing mode

  // Image attachment
  final ImagePicker _imagePicker = ImagePicker();
  XFile? _selectedImage;
  Uint8List? _selectedImageBytes;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    try {
      // Capture image data before clearing
      final imageBytes = _selectedImageBytes;
      final imagePath = _selectedImage?.path;

      // Send message immediately - credits will be consumed after AI responds
      ref.read(chatProvider.notifier).send(
            text.isNotEmpty ? text : 'Analyze this image',
            useDeepSearch: _isDeepSearchEnabled,
            useWebBrowsing: _isWebBrowsingEnabled,
            imagePath: imagePath,
            imageBytes: imageBytes,
          );

      _controller.clear();
      setState(() {
        _selectedImage = null;
        _selectedImageBytes = null;
      });

      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Failed to send message: ${e.toString().split(':').last.trim()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _takePhoto() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedImage = image;
          _selectedImageBytes = bytes;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to take photo: $e')),
      );
    }
  }

  void _removeSelectedImage() {
    setState(() {
      _selectedImage = null;
      _selectedImageBytes = null;
    });
  }

  Future<void> _playTTS(String text) async {
    try {
      // Get current speed setting if available, otherwise default to 1.0
      // We need to read the provider. Since this is a ConsumerState, we can read it.
      // However, voiceSettingsProvider is in enhanced_voice_mode_screen.dart.
      // We should probably move it to a shared location or just use a default here.
      // For now, let's just use 1.0 or try to read it if we import it.
      // Better yet, let's just use 1.0 for chat screen TTS for now.
      await ref.read(voiceServiceProvider).speak(text, speed: 1.0);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TTS Error: $e')),
      );
    }
  }

  Future<void> _toggleRecord() async {
    try {
      if (!_recording) {
        setState(() => _recording = true);
        await ref.read(voiceServiceProvider).listen(
          onResult: (text) {
            setState(() {
              _controller.text = text;
            });
          },
          onDone: (text) {
            setState(() {
              _recording = false;
              _controller.text = text;
            });
          },
        );
      } else {
        await ref.read(voiceServiceProvider).stopListening();
        setState(() => _recording = false);
      }
    } catch (e) {
      setState(() => _recording = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice input error: $e')),
      );
    }
  }

  void _showAIWritingDialog() {
    final scheme = Theme.of(context).colorScheme;
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Icon(Icons.auto_awesome, color: scheme.tertiary),
              const SizedBox(width: 12),
              const Text('AI Writing Assistant'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What would you like me to write?',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 16),

              // Writing mode selection
              Row(
                children: [
                  _WritingModeChip(
                    label: 'Notes',
                    icon: LucideIcons.fileText,
                    selected: _writingMode == 'notes',
                    onTap: () => setState(() => _writingMode = 'notes'),
                  ),
                  const SizedBox(width: 8),
                  _WritingModeChip(
                    label: 'Summary',
                    icon: LucideIcons.clipboardList,
                    selected: _writingMode == 'summary',
                    onTap: () => setState(() => _writingMode = 'summary'),
                  ),
                  const SizedBox(width: 8),
                  _WritingModeChip(
                    label: 'Report',
                    icon: LucideIcons.fileStack,
                    selected: _writingMode == 'report',
                    onTap: () => setState(() => _writingMode = 'report'),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  hintText: _getHintText(),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  filled: true,
                  fillColor: scheme.surface,
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Text(
                'AI will analyze your sources and create content.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.secondaryText,
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () {
                final prompt = controller.text.trim();
                if (prompt.isNotEmpty) {
                  Navigator.pop(context);
                  _performAIWriting(prompt);
                }
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Generate'),
            ),
          ],
        ),
      ),
    ).then((_) => controller.dispose());
  }

  String _getHintText() {
    switch (_writingMode) {
      case 'notes':
        return 'e.g., "Create detailed notes about climate change impacts"';
      case 'summary':
        return 'e.g., "Summarize the key findings from all sources"';
      case 'report':
        return 'e.g., "Generate a comprehensive research report"';
      default:
        return 'Enter your writing request...';
    }
  }

  void _performAIWriting(String userPrompt) async {
    final sources = ref.read(sourceProvider);
    final sourceContext =
        sources.map((s) => '${s.title}: ${s.content}').toList();

    String enhancedPrompt = '';
    switch (_writingMode) {
      case 'notes':
        enhancedPrompt =
            '''Based on these sources, create detailed and comprehensive notes about: $userPrompt

Please organize the notes with:
- Clear headings and subheadings
- Key points and important details
- Relevant examples and evidence from the sources
- Action items or key takeaways

Sources to analyze:''';
        break;
      case 'summary':
        enhancedPrompt =
            '''Based on these sources, create a comprehensive summary: $userPrompt

Please provide:
- Executive summary of key findings
- Main themes and patterns across sources
- Important statistics or data points
- Conclusions and implications

Sources to summarize:''';
        break;
      case 'report':
        enhancedPrompt =
            '''Based on these sources, generate a professional research report about: $userPrompt

Please structure the report with:
- Introduction and background
- Methodology and approach
- Key findings and analysis
- Supporting evidence and examples
- Conclusions and recommendations
- References to source materials

Sources to analyze:''';
        break;
    }

    enhancedPrompt += '\n\n${sourceContext.join('\n\n')}';

    setState(() => _showAIWriting = true);

    try {
      await ref.read(aiProvider.notifier).generateContent(enhancedPrompt);

      // Add the AI response as a message
      if (ref.read(aiProvider).lastResponse != null) {
        final aiResponse = ref.read(aiProvider).lastResponse!;
        ref.read(chatProvider.notifier).addAIMessage(aiResponse);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI writing failed: $e')),
      );
    } finally {
      setState(() => _showAIWriting = false);
      Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
    }
  }

  Future<void> _handleCreateNotebookProposal(String title) async {
    // Show loading feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('Creating notebook "$title"...'),
          duration: const Duration(seconds: 1)),
    );

    try {
      // 1. Create Notebook
      final notebookId =
          await ref.read(notebookProvider.notifier).addNotebook(title);

      if (notebookId != null) {
        // 2. Capture Chat History
        final messages = ref.read(chatProvider);
        final historyText = messages
            .map((m) => '${m.isUser ? "User" : "AI"}: ${m.text}')
            .join('\n\n');

        // 3. Add as Source
        await ref.read(apiServiceProvider).createSource(
              notebookId: notebookId,
              type: 'text',
              title: 'Original Chat History',
              content: historyText,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Notebook created! Opening...')),
          );
          // 4. Navigate
          context.push('/notebook/$notebookId');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create notebook.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showExportDialog() {
    final scheme = Theme.of(context).colorScheme;
    final messages = ref.read(chatProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Icon(Icons.download_outlined, color: scheme.primary),
            const SizedBox(width: 12),
            const Text('Export Chat'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose export format:',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 16),
            _ExportOptionTile(
              icon: LucideIcons.fileText,
              title: 'Markdown',
              subtitle: 'Formatted text with structure',
              color: Colors.blue,
              onTap: () => _exportAsMarkdown(messages),
            ),
            const SizedBox(height: 8),
            _ExportOptionTile(
              icon: LucideIcons.file,
              title: 'Plain Text',
              subtitle: 'Simple text format',
              color: Colors.green,
              onTap: () => _exportAsText(messages),
            ),
            const SizedBox(height: 8),
            _ExportOptionTile(
              icon: LucideIcons.fileStack,
              title: 'JSON',
              subtitle: 'Structured data format',
              color: Colors.purple,
              onTap: () => _exportAsJSON(messages),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _exportAsMarkdown(List<Message> messages) {
    Navigator.pop(context);
    String markdown = '# Chat Conversation\n\n';
    markdown += 'Exported on ${DateTime.now().toString()}\n\n';
    markdown += '## Messages (${messages.length})\n\n';

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      markdown += '### ${message.isUser ? 'User' : 'AI'}\n';
      markdown +=
          '- **Time**: ${message.timestamp.toString().split(' ')[1].split('.')[0]}\n';
      markdown += '\n${message.text}\n\n';
      markdown += '---\n\n';
    }

    Share.share(markdown, subject: 'Chat Conversation - Markdown Export');
  }

  void _exportAsText(List<Message> messages) {
    Navigator.pop(context);
    String text = 'Chat Conversation\n';
    text += '=' * 20 + '\n';
    text += 'Exported on ${DateTime.now().toString()}\n\n';
    text += 'Messages (${messages.length}):\n\n';

    for (int i = 0; i < messages.length; i++) {
      final message = messages[i];
      text +=
          '${message.isUser ? "User" : "AI"} (${message.timestamp.toString().split(' ')[1].split('.')[0]}):\n';
      text += '${message.text}\n\n';
    }

    Share.share(text, subject: 'Chat Conversation - Text Export');
  }

  void _exportAsJSON(List<Message> messages) {
    Navigator.pop(context);
    final data = {
      'exportDate': DateTime.now().toIso8601String(),
      'messageCount': messages.length,
      'messages': messages
          .map((m) => {
                'role': m.isUser ? 'user' : 'assistant',
                'content': m.text,
                'timestamp': m.timestamp.toIso8601String(),
                'citations': m.citations.map((c) => c.snippet).toList(),
              })
          .toList(),
    };

    final jsonString = const JsonEncoder.withIndent('  ').convert(data);
    Share.share(jsonString, subject: 'Chat Conversation - JSON Export');
  }

  void _showVoiceSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Voice Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Google TTS (Free)'),
              subtitle: const Text('Standard device voice'),
              onTap: () {
                ref
                    .read(voiceServiceProvider)
                    .setTtsProvider(TtsProvider.google);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Google Cloud TTS'),
              subtitle: const Text('High quality neural voices'),
              onTap: () {
                ref
                    .read(voiceServiceProvider)
                    .setTtsProvider(TtsProvider.googleCloud);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('ElevenLabs'),
              subtitle: const Text('Ultra realistic AI voices'),
              onTap: () {
                ref
                    .read(voiceServiceProvider)
                    .setTtsProvider(TtsProvider.elevenlabs);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Murf.ai (New)'),
              subtitle: const Text('Studio quality Gen 2 voices'),
              onTap: () {
                ref.read(voiceServiceProvider).setTtsProvider(TtsProvider.murf);
                Navigator.pop(context);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final customAgentsState = ref.watch(customAgentsProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    String? selectedAgentName;
    final selectedAgentId = customAgentsState.selectedAgentId;
    if (selectedAgentId != null) {
      for (final agent in customAgentsState.agents) {
        if (agent.id == selectedAgentId) {
          selectedAgentName = agent.name;
          break;
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(selectedAgentName == null
            ? 'AI Chat'
            : 'AI Chat • $selectedAgentName'),
        actions: [
          // Context usage indicator
          GestureDetector(
            onTap: () => showContextUsageDialog(context),
            child: const ContextUsageIndicator(compact: true),
          ).animate().fadeIn(duration: Motion.short),
          const SizedBox(width: 8),
          // AI Writing Assistant
          IconButton(
            onPressed: _showAIWritingDialog,
            icon: const Icon(Icons.auto_awesome),
            tooltip: 'AI Writing Assistant',
          ).animate().scale(duration: Motion.short, delay: Motion.short),

          // Export chat
          IconButton(
            onPressed: _showExportDialog,
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export chat',
          ).animate().scale(duration: Motion.short, delay: Motion.medium),
          IconButton(
            onPressed: () => context.push('/custom-agents'),
            icon: const Icon(Icons.smart_toy_outlined),
            tooltip: 'Custom agents',
          ).animate().scale(duration: Motion.short, delay: Motion.medium),
          Consumer(builder: (context, ref, _) {
            return IconButton(
              onPressed: () async {
                // Voice settings
                // We can show a dialog or bottom sheet here to select voice/provider
                // For now, just show a simple dialog
                _showVoiceSettings();
              },
              icon: const Icon(Icons.volume_up),
              tooltip: 'Voice settings',
            ).animate().scale(duration: Motion.short, delay: Motion.long);
          }),
        ],
      ),
      body: Column(
        children: [
          // AI Writing Status
          if (_showAIWriting)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.tertiary.withValues(alpha: 0.1),
                    scheme.primary.withValues(alpha: 0.05),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outline.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  const CircularProgressIndicator(strokeWidth: 2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI is writing content...',
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Analyzing sources and generating $_writingMode',
                          style: text.bodyMedium?.copyWith(
                            color: scheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
                .animate()
                .slide(begin: const Offset(0, -1), duration: Motion.medium)
                .fadeIn(duration: Motion.medium),

          // Messages list
          Expanded(
            child: messages.isEmpty
                ? _EmptyChatView(scheme: scheme, text: text)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return _MessageBubble(
                        message: message,
                        isLast: index == messages.length - 1,
                        onAcceptProposal: _handleCreateNotebookProposal,
                      )
                          .animate()
                          .slide(
                              begin: const Offset(0, 0.3),
                              duration: Motion.short)
                          .fadeIn(
                            duration: Motion.short,
                            delay: Duration(
                                milliseconds: index * Motion.baseStagger),
                          );
                    },
                  ),
          ),

          Consumer(builder: (context, ref, _) {
            final tokens = ref.watch(streamProvider);
            final isStreaming = tokens.isNotEmpty &&
                tokens.last.map(
                  text: (_) => true,
                  citation: (_) => true,
                  done: (_) => false,
                );
            return isStreaming
                ? const _TypingWave().animate().fadeIn(duration: Motion.short)
                : const SizedBox.shrink();
          }),

          // Input area
          SafeArea(
            top: false,
            child: _ChatInputArea(
              controller: _controller,
              onSend: _sendMessage,
              onChanged: (text) {},
              onMic: _toggleRecord,
              isDeepSearchEnabled: _isDeepSearchEnabled,
              onToggleDeepSearch: () =>
                  setState(() => _isDeepSearchEnabled = !_isDeepSearchEnabled),
              isWebBrowsingEnabled: _isWebBrowsingEnabled,
              onToggleWebBrowsing: () => setState(
                  () => _isWebBrowsingEnabled = !_isWebBrowsingEnabled),
              onPickImage: _pickImage,
              onTakePhoto: _takePhoto,
              selectedImage: _selectedImage,
              onRemoveImage: _removeSelectedImage,
              isRecording: _recording,
            ),
          ),
        ],
      ),
    );
  }
}

class _WritingModeChip extends StatelessWidget {
  const _WritingModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.tertiary.withValues(alpha: 0.2)
              : scheme.surfaceContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? scheme.tertiary
                : scheme.outline.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selected
                    ? scheme.tertiary
                    : scheme.onSurface.withValues(alpha: 0.7)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? scheme.tertiary
                    : scheme.onSurface.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.isLast,
    this.onAcceptProposal,
  });

  final Message message;
  final bool isLast;

  final Function(String)? onAcceptProposal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;
    final state = context.findAncestorStateOfType<_EnhancedChatScreenState>();

    // Parse proposal
    final notebookProposalRegex = RegExp(r'\[\[PROPOSE_NOTEBOOK:\s*(.*?)\]\]');
    final match = notebookProposalRegex.firstMatch(message.text);
    String? proposalTitle;
    String displayContent = message.text;

    if (match != null) {
      proposalTitle = match.group(1)?.trim();
      displayContent =
          message.text.replaceAll(notebookProposalRegex, '').trim();
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Deep search indicator for AI responses
            if (!isUser && message.isDeepSearch)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.public, size: 12, color: scheme.tertiary),
                    const SizedBox(width: 4),
                    Text(
                      message.isWebBrowsing ? '🌐 Web Browsing' : 'Web Search',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            // Web browsing status indicator
            if (!isUser &&
                message.isWebBrowsing &&
                message.webBrowsingStatus != null &&
                !message.webBrowsingStatus!.contains('Complete'))
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        message.webBrowsingStatus!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                        ),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
            // Web browsing screenshots
            if (!isUser && message.webBrowsingScreenshots.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                height: 80,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: message.webBrowsingScreenshots.length,
                  itemBuilder: (context, index) {
                    final screenshotUrl = message.webBrowsingScreenshots[index];
                    return GestureDetector(
                      onTap: () => _showFullScreenshot(context, screenshotUrl),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: AppNetworkImage(
                                imageUrl: screenshotUrl,
                                width: 120,
                                height: 80,
                                fit: BoxFit.cover,
                                placeholder: (_) => Container(
                                  width: 120,
                                  height: 80,
                                  color: scheme.surfaceContainerHighest,
                                  child: const CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                                errorWidget: (_) => Container(
                                  width: 120,
                                  height: 80,
                                  color: scheme.surfaceContainerHighest,
                                  child: Icon(Icons.broken_image,
                                      color: scheme.outline),
                                ),
                              ),
                            ),
                            // Expand icon overlay
                            Positioned(
                              right: 4,
                              bottom: 4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.fullscreen,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .scale(delay: Duration(milliseconds: index * 100));
                  },
                ),
              ),
            // Web browsing sources
            if (!isUser && message.webBrowsingSources.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: message.webBrowsingSources.take(3).map((url) {
                    final domain = Uri.tryParse(url)?.host ?? url;
                    return Chip(
                      avatar: CircleAvatar(
                        backgroundColor: Colors.transparent,
                        child: Image.network(
                          'https://www.google.com/s2/favicons?domain=$domain&sz=32',
                          width: 16,
                          height: 16,
                          errorBuilder: (_, __, ___) => Icon(Icons.language,
                              size: 14, color: scheme.onSurfaceVariant),
                        ),
                      ),
                      label: Text(domain, style: const TextStyle(fontSize: 10)),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),
              ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser ? scheme.primary : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(20).copyWith(
                  bottomLeft: isUser ? const Radius.circular(20) : Radius.zero,
                  bottomRight: isUser ? Radius.zero : const Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show attached image if present
                  if (message.imageUrl != null && isUser)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(message.imageUrl!),
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            color: Colors.grey[300],
                            child: const Center(
                              child: Icon(Icons.broken_image),
                            ),
                          ),
                        ),
                      ),
                    ),
                  _AnimatedMessageText(
                    text: displayContent,
                    citations: message.citations,
                    isUser: isUser,
                    isLast: isLast,
                  ),
                  if (proposalTitle != null && !isUser) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: scheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.book, size: 16, color: scheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Proposal: Create Notebook',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: scheme.primary,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '"$proposalTitle"',
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                if (onAcceptProposal != null) {
                                  onAcceptProposal!(proposalTitle!);
                                }
                              },
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('Create & Save Chat'),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (!isUser) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => state?._playTTS(displayContent),
                          icon: const Icon(Icons.volume_up, size: 18),
                          tooltip: 'Play voice',
                        ),
                      ],
                    ),
                    // GitHub action buttons for AI responses
                    // Requirements: 6.1, 6.2
                    GitHubActionButtons(
                      messageText: displayContent,
                      onCreateIssue: () {
                        // Show issue creation dialog
                        final issueSuggestion =
                            GitHubActionDetector.detectIssueSuggestion(
                                displayContent);
                        if (issueSuggestion != null) {
                          showGitHubIssueDialog(
                            context,
                            ref,
                            title: issueSuggestion.title,
                            body: issueSuggestion.body,
                          );
                        }
                      },
                      onCopyCode: (code, language) {
                        // Code is already copied by the button, just log for analytics
                        debugPrint('Code copied: $language');
                      },
                    ),
                  ],
                  if (message.citations.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: message.citations.take(4).map((c) {
                        final chipColor =
                            (isUser ? scheme.onPrimary : scheme.onSurface)
                                .withValues(alpha: 0.1);
                        final textColor =
                            (isUser ? scheme.onPrimary : scheme.onSurface)
                                .withValues(alpha: 0.8);
                        String chunkLabel = '';
                        final idxMarker = c.id.lastIndexOf('_c');
                        if (idxMarker >= 0 && idxMarker + 2 < c.id.length) {
                          final numPart = c.id.substring(idxMarker + 2);
                          chunkLabel = '#$numPart';
                        }
                        String sourceTitle = '';
                        final sources = ref.read(sourceProvider);
                        final src =
                            sources.where((s) => s.id == c.sourceId).toList();
                        if (src.isNotEmpty) sourceTitle = src.first.title;
                        return GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => SourceDetailScreen(
                                    sourceId: c.sourceId,
                                    highlightChunkId: c.id,
                                    highlightSnippet: c.snippet)),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: chipColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: textColor.withValues(alpha: 0.2),
                                  width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(LucideIcons.fileText,
                                    size: 12, color: textColor),
                                const SizedBox(width: 4),
                                Text(
                                  '${chunkLabel.isNotEmpty ? '$chunkLabel ' : ''}${sourceTitle.isNotEmpty ? '· $sourceTitle · ' : ''}${c.snippet.length > 24 ? '${c.snippet.substring(0, 24)}…' : c.snippet}',
                                  style:
                                      TextStyle(fontSize: 11, color: textColor),
                                ),
                              ],
                            ),
                          ).animate().scale(duration: Motion.short),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: () {
                        final c = message.citations.first;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SourceDetailScreen(
                              sourceId: c.sourceId,
                              highlightChunkId: c.id,
                              highlightSnippet: c.snippet,
                            ),
                          ),
                        );
                      },
                      child: const Text('View all matches'),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(message.timestamp),
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullScreenshot(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 200,
                        height: 200,
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      );
                    },
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.black54,
                      child: const Icon(Icons.broken_image,
                          color: Colors.white, size: 48),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class _AnimatedMessageText extends ConsumerWidget {
  const _AnimatedMessageText(
      {required this.text,
      required this.citations,
      required this.isUser,
      required this.isLast});
  final String text;
  final List<Citation> citations;
  final bool isUser;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = isUser ? scheme.onPrimary : scheme.onSurface;

    // Basic markdown styling
    final styleSheet = MarkdownStyleSheet(
      p: TextStyle(color: textColor, fontSize: 15, height: 1.5),
      h1: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 24),
      h2: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 20),
      h3: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
      h4: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 16),
      h5: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 14),
      h6: TextStyle(
          color: textColor, fontWeight: FontWeight.bold, fontSize: 12),
      strong: TextStyle(color: textColor, fontWeight: FontWeight.bold),
      em: TextStyle(color: textColor, fontStyle: FontStyle.italic),
      code: TextStyle(
        color: isUser ? scheme.onPrimary : scheme.primary,
        backgroundColor:
            isUser ? Colors.black12 : scheme.surfaceContainerHighest,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: isUser ? Colors.black12 : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: TextStyle(
          color: textColor.withValues(alpha: 0.8), fontStyle: FontStyle.italic),
      blockquoteDecoration: BoxDecoration(
        border: Border(
            left:
                BorderSide(color: textColor.withValues(alpha: 0.5), width: 4)),
      ),
      listBullet: TextStyle(color: textColor),
    );

    return MarkdownBody(
      data: text,
      selectable: true,
      styleSheet: styleSheet,
      onTapLink: (text, href, title) async {
        if (href != null) {
          final uri = Uri.tryParse(href);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri);
          }
        }
      },
    ).animate().fadeIn(duration: Motion.short);
  }
}

class _TypingWave extends StatelessWidget {
  const _TypingWave();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          return Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                  begin: const Offset(0.8, 0.8),
                  end: const Offset(1, 1),
                  duration: Motion.short,
                  delay: Duration(milliseconds: i * 120))
              .fadeIn(
                  duration: Motion.short,
                  delay: Duration(milliseconds: i * 120));
        }),
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView({
    required this.scheme,
    required this.text,
  });

  final ColorScheme scheme;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  scheme.primary.withValues(alpha: 0.1),
                  scheme.tertiary.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(60),
            ),
            child: Icon(
              LucideIcons.messageCircle,
              size: 60,
              color: scheme.primary.withValues(alpha: 0.5),
            ),
          ).animate().scale(duration: 800.ms).fadeIn(),
          const SizedBox(height: 24),
          Text(
            'Start a conversation',
            style: text.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ).animate().slide(begin: const Offset(0, 0.2)).fadeIn(),
          const SizedBox(height: 8),
          Text(
            'Ask questions about your research sources',
            style: text.bodyLarge?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          )
              .animate()
              .slide(begin: const Offset(0, 0.2), delay: 100.ms)
              .fadeIn(),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              // Show example prompts
              _showExamplePrompts(context);
            },
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Example Prompts'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ).animate().scale(delay: 300.ms),
        ],
      ),
    );
  }

  void _showExamplePrompts(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        title: Row(
          children: [
            Icon(Icons.lightbulb_outline, color: scheme.primary),
            const SizedBox(width: 12),
            const Text('Example Prompts'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ExamplePromptTile(
              prompt: 'Summarize the key findings from all sources',
              description: 'Get a comprehensive overview of your research',
            ),
            SizedBox(height: 8),
            _ExamplePromptTile(
              prompt: 'What are the main themes across these sources?',
              description: 'Identify common patterns and themes',
            ),
            SizedBox(height: 8),
            _ExamplePromptTile(
              prompt: 'Compare and contrast the different viewpoints',
              description: 'Analyze different perspectives on the topic',
            ),
            SizedBox(height: 8),
            _ExamplePromptTile(
              prompt: 'What questions remain unanswered?',
              description: 'Identify gaps in the current research',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _ExamplePromptTile extends StatelessWidget {
  const _ExamplePromptTile({
    required this.prompt,
    required this.description,
  });

  final String prompt;
  final String description;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListTile(
      onTap: () {
        Navigator.pop(context);
        // This would need to be connected to the parent widget's controller
      },
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.chat_bubble_outline,
          size: 16,
          color: scheme.primary,
        ),
      ),
      title: Text(
        prompt,
        style: const TextStyle(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        description,
        style: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      tileColor: scheme.surface.withValues(alpha: 0.5),
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  const _ExportOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      tileColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
    );
  }
}

class _ChatInputArea extends StatelessWidget {
  const _ChatInputArea({
    required this.controller,
    required this.onSend,
    required this.onChanged,
    required this.onMic,
    required this.isDeepSearchEnabled,
    required this.onToggleDeepSearch,
    required this.isWebBrowsingEnabled,
    required this.onToggleWebBrowsing,
    required this.onPickImage,
    required this.onTakePhoto,
    this.selectedImage,
    this.onRemoveImage,
    this.isRecording = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(String) onChanged;
  final VoidCallback onMic;
  final bool isDeepSearchEnabled;
  final VoidCallback onToggleDeepSearch;
  final bool isWebBrowsingEnabled;
  final VoidCallback onToggleWebBrowsing;
  final VoidCallback onPickImage;
  final VoidCallback onTakePhoto;
  final XFile? selectedImage;
  final VoidCallback? onRemoveImage;
  final bool isRecording;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Web Browsing indicator
              if (isWebBrowsingEnabled)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.orange.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language, size: 16, color: Colors.orange),
                      SizedBox(width: 6),
                      Text(
                        '🌐 Web Browsing - AI will search & show screenshots',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.2),

              // Deep Search indicator
              if (isDeepSearchEnabled && !isWebBrowsingEnabled)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public, size: 16, color: scheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Deep Search enabled - will search the web',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(begin: 0.2),

              // Image preview
              if (selectedImage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(selectedImage!.path),
                          height: 100,
                          width: 100,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: onRemoveImage,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ).animate().scale(duration: Motion.short),

              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Image picker button
                          PopupMenuButton<String>(
                            icon: Icon(
                              LucideIcons.image,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                              size: 20,
                            ),
                            tooltip: 'Add image',
                            onSelected: (value) {
                              if (value == 'gallery') {
                                onPickImage();
                              } else if (value == 'camera') {
                                onTakePhoto();
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'gallery',
                                child: Row(
                                  children: [
                                    Icon(LucideIcons.image,
                                        size: 18, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    const Text('From Gallery'),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'camera',
                                child: Row(
                                  children: [
                                    Icon(LucideIcons.camera,
                                        size: 18, color: scheme.primary),
                                    const SizedBox(width: 8),
                                    const Text('Take Photo'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Deep search toggle
                          IconButton(
                            onPressed: onToggleDeepSearch,
                            icon: Icon(
                              Icons.public,
                              color: isDeepSearchEnabled
                                  ? scheme.primary
                                  : scheme.onSurface.withValues(alpha: 0.5),
                              size: 20,
                            ),
                            tooltip: isDeepSearchEnabled
                                ? 'Deep Search ON'
                                : 'Enable Deep Search',
                          ),
                          // Web browsing toggle
                          IconButton(
                            onPressed: onToggleWebBrowsing,
                            icon: Icon(
                              Icons.language,
                              color: isWebBrowsingEnabled
                                  ? Colors.orange
                                  : scheme.onSurface.withValues(alpha: 0.5),
                              size: 20,
                            ),
                            tooltip: isWebBrowsingEnabled
                                ? 'Web Browsing ON'
                                : 'Enable Web Browsing (with screenshots)',
                          ),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              onChanged: onChanged,
                              decoration: InputDecoration(
                                hintText: selectedImage != null
                                    ? 'Ask about this image...'
                                    : 'Ask about your research...',
                                hintStyle: TextStyle(
                                  color:
                                      scheme.onSurface.withValues(alpha: 0.5),
                                ),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => onSend(),
                            ),
                          ),
                          // Send button
                          IconButton(
                            onPressed: onSend,
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.send,
                                color: scheme.onPrimary,
                                size: 18,
                              ),
                            ),
                          ),
                          // Mic button
                          IconButton(
                            onPressed: onMic,
                            icon: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color:
                                    isRecording ? Colors.red : scheme.secondary,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                isRecording ? Icons.stop : Icons.mic,
                                color: scheme.onSecondary,
                                size: 18,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
