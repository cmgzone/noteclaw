import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/audio/audio_playback_provider.dart';
import 'audio_player_sheet.dart';

class MiniAudioPlayer extends ConsumerWidget {
  const MiniAudioPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playbackState = ref.watch(audioPlaybackProvider);
    final overview = playbackState.currentOverview;

    // Use a simpler check: if there is a current overview, show the player.
    // The previous logic might have cleared it on stop, which is fine.
    if (overview == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Dismissible(
      key: const Key('mini_player'),
      direction: DismissDirection.down,
      onDismissed: (_) {
        ref.read(audioPlaybackProvider.notifier).stop();
      },
      child: GestureDetector(
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            backgroundColor: Colors.transparent,
            builder: (_) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: AudioPlayerSheet(overview: overview),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          height: 64,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Artwork placeholder
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: Icon(LucideIcons.headphones,
                    color: scheme.onPrimaryContainer, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      overview.title,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'NoteClaw',
                      style: text.labelSmall?.copyWith(
                        color: scheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  ref.read(audioPlaybackProvider.notifier).skipToPrevious();
                },
                icon: const Icon(LucideIcons.skipBack, size: 20),
              ),
              IconButton(
                onPressed: () {
                  if (playbackState.isPlaying) {
                    ref.read(audioPlaybackProvider.notifier).pause();
                  } else {
                    ref.read(audioPlaybackProvider.notifier).play(overview);
                  }
                },
                icon: Icon(
                  playbackState.isPlaying
                      ? LucideIcons.pause
                      : LucideIcons.play,
                ),
              ),
              IconButton(
                onPressed: () {
                  ref.read(audioPlaybackProvider.notifier).skipToNext();
                },
                icon: const Icon(LucideIcons.skipForward, size: 20),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
