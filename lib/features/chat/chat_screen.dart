import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'chat_provider.dart';
import 'deep_research_message_card.dart';
import 'message.dart';
import 'citation_drawer.dart';
import '../../core/audio/voice_service.dart';
import '../../core/theme/theme_provider.dart';
import '../../ui/components/glass_container.dart';
import '../../theme/app_theme.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('AI Chat'),
        flexibleSpace: GlassContainer(
          borderRadius: BorderRadius.zero,
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.7),
          border: Border(
              bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.1))),
          child: Container(),
        ),
        actions: [
          Consumer(builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            return IconButton(
              icon: Icon(
                  mode == ThemeMode.dark ? LucideIcons.moon : LucideIcons.sun),
              tooltip: mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
              onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            );
          }),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(LucideIcons.quote),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Citations',
            ),
          ),
        ],
      ),
      endDrawer: const CitationDrawer(),
      body: Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
              Theme.of(context).colorScheme.surface,
              Theme.of(context).colorScheme.surfaceContainer,
            ])),
        child: Column(
          children: [
            SizedBox(
                height: kToolbarHeight +
                    MediaQuery.of(context)
                        .padding
                        .top), // Spacer for transparent app bar
            const _SourceFilters(),
            Expanded(child: _MessagesList(ref: ref, text: text)),
            const _PromptBar(),
          ],
        ),
      ),
    );
  }
}

class _SourceFilters extends StatelessWidget {
  const _SourceFilters();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
          children: [
        const _PremiumFilterChip(
            label: 'All sources', icon: LucideIcons.layers, selected: true),
        const SizedBox(width: 8),
        const _PremiumFilterChip(label: 'Drive', icon: LucideIcons.hardDrive),
        const SizedBox(width: 8),
        const _PremiumFilterChip(label: 'PDF', icon: LucideIcons.fileText),
        const SizedBox(width: 8),
        const _PremiumFilterChip(label: 'Web', icon: LucideIcons.globe),
      ].animate(interval: 50.ms).fadeIn().slideX(begin: 0.1)),
    );
  }
}

class _PremiumFilterChip extends StatelessWidget {
  const _PremiumFilterChip(
      {required this.label, this.icon, this.selected = false});
  final String label;
  final IconData? icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color:
              selected ? scheme.primary : scheme.outline.withValues(alpha: 0.3),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                )
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 14,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessagesList extends StatelessWidget {
  const _MessagesList({required this.ref, required this.text});
  final WidgetRef ref;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);

    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.messageSquareDashed,
                size: 64,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text("Start a conversation",
                style: text.titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.outline)),
          ],
        ).animate().fadeIn(),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final m = messages[index];
        return _MessageBubble(message: m)
            .animate()
            .fadeIn(duration: 400.ms)
            .slideY(begin: 0.1, curve: Curves.easeOut);
      },
    );
  }
}

class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({required this.message});
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.isUser;

    if (!isUser && message.isDeepSearch) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.92,
          ),
          child: DeepResearchMessageCard(
            message: message,
            onSpeak: () async {
              await ref
                  .read(voiceServiceProvider)
                  .speak(message.text, interrupt: true);
            },
          ),
        ),
      );
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: isUser
                ? scheme.primary.withValues(alpha: 0.9)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft:
                  isUser ? const Radius.circular(20) : const Radius.circular(4),
              bottomRight:
                  isUser ? const Radius.circular(4) : const Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              )
            ],
            border: !isUser
                ? Border.all(color: scheme.outline.withValues(alpha: 0.1))
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    color: isUser ? Colors.white : scheme.onSurface,
                    height: 1.5,
                  ),
                ),
                if (!isUser) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            try {
                              await ref
                                  .read(voiceServiceProvider)
                                  .speak(message.text, interrupt: true);
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('TTS error: $e')),
                              );
                            }
                          },
                          onLongPress: () async {
                            await ref.read(voiceServiceProvider).stopSpeaking();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: scheme.surface.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: scheme.outline.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Icon(
                              LucideIcons.volume2,
                              size: 16,
                              color: scheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (message.citations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isUser
                          ? Colors.white.withValues(alpha: 0.2)
                          : scheme.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(LucideIcons.quote,
                          color: isUser ? Colors.white : scheme.primary,
                          size: 14),
                      const SizedBox(width: 6),
                      Text('${message.citations.length} Citations',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isUser ? Colors.white : scheme.primary)),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromptBar extends ConsumerStatefulWidget {
  const _PromptBar();

  @override
  ConsumerState<_PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends ConsumerState<_PromptBar> {
  final TextEditingController _controller = TextEditingController();
  bool _isListening = false;
  double _soundLevel = 0.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _setControllerText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> _startVoiceInput() async {
    setState(() {
      _isListening = true;
      _soundLevel = 0.0;
    });

    try {
      await ref.read(voiceServiceProvider).listen(
        onResult: (text) {
          if (!mounted) return;
          _setControllerText(text);
        },
        onDone: (text) {
          if (!mounted) return;
          setState(() => _isListening = false);
          final finalText = text.trim();
          if (finalText.isEmpty) return;
          ref.read(chatProvider.notifier).send(finalText);
          _controller.clear();
        },
        onSoundLevel: (level) {
          if (!mounted) return;
          setState(() => _soundLevel = level);
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice input error: $e')),
      );
    }
  }

  Future<void> _stopVoiceInput() async {
    try {
      final transcript = await ref.read(voiceServiceProvider).stopListening();
      if (!mounted) return;
      setState(() => _isListening = false);
      final text = transcript.trim();
      if (text.isEmpty) return;
      _setControllerText(text);
      ref.read(chatProvider.notifier).send(text);
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isListening = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to stop voice input: $e')),
      );
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _stopVoiceInput();
    } else {
      await _startVoiceInput();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassContainer(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      border:
          Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.1))),
      child: SafeArea(
        // SafeArea handles bottom padding automatically
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Row(children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.2)),
                ),
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Ask about your sources...',
                    border: InputBorder.none,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    isDense: true,
                  ),
                  style: TextStyle(color: scheme.onSurface),
                  minLines: 1,
                  maxLines: 4,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Transform.scale(
              scale: 1 + (_soundLevel * 0.18),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? scheme.error.withValues(alpha: 0.9)
                      : scheme.surface.withValues(alpha: 0.5),
                  border:
                      Border.all(color: scheme.outline.withValues(alpha: 0.2)),
                ),
                child: IconButton(
                  onPressed: _toggleVoiceInput,
                  icon: Icon(
                    _isListening ? Icons.stop : LucideIcons.mic,
                    color: _isListening ? scheme.onError : scheme.onSurface,
                    size: 20,
                  ),
                  tooltip: _isListening ? 'Stop voice input' : 'Voice input',
                ),
              ).animate(key: ValueKey(_isListening)).scale(duration: 200.ms),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: const BoxDecoration(
                gradient: AppTheme.premiumGradient,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: () {
                  final text = _controller.text.trim();
                  if (text.isEmpty) return;
                  ref.read(chatProvider.notifier).send(text);
                  _controller.clear();
                },
                icon:
                    const Icon(LucideIcons.send, color: Colors.white, size: 20),
                tooltip: 'Send',
              ),
            ).animate().scale(delay: 200.ms),
          ]),
        ),
      ),
    );
  }
}
