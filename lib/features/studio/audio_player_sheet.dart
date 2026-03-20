import 'dart:async';
import 'dart:math';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:audio_service/audio_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:path_provider/path_provider.dart';

import 'audio_overview.dart';
import 'audio_overview_provider.dart';
import '../../core/audio/audio_playback_provider.dart';
import '../../core/audio/audio_cache.dart';

class AudioPlayerSheet extends ConsumerWidget {
  const AudioPlayerSheet({super.key, required this.overview});
  final AudioOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    // Access overviews from the new state object
    final overviews = ref.watch(audioOverviewProvider).overviews;
    final playback = ref.watch(audioPlaybackProvider);
    final audioHandler = ref.watch(audioHandlerProvider);

    final isPlaying = playback.isPlaying && playback.currentUrl == overview.url;
    final currentIndex = overviews.indexWhere((a) => a.id == overview.id);
    final hasPrev = currentIndex > 0;
    final hasNext = currentIndex >= 0 && currentIndex < overviews.length - 1;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surface,
            scheme.surfaceContainer,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 48,
              height: 5,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(LucideIcons.chevronDown),
                style: IconButton.styleFrom(
                  backgroundColor:
                      scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  foregroundColor: scheme.onSurface,
                ),
              ),
              Expanded(
                child: Text(
                  'NOW PLAYING',
                  style: text.labelMedium?.copyWith(
                    color: scheme.secondary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                onPressed: () {
                  ref
                      .read(audioOverviewProvider.notifier)
                      .toggleOffline(overview);
                  if (!overview.isOffline) {
                    ref.read(audioCacheProvider.notifier).cache(overview);
                  } else {
                    ref.read(audioCacheProvider.notifier).remove(overview);
                  }
                },
                icon: Icon(
                  overview.isOffline
                      ? LucideIcons.checkCircle
                      : LucideIcons.download,
                  color: overview.isOffline ? scheme.primary : scheme.onSurface,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Artwork & Visuals
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primaryContainer,
                    scheme.tertiaryContainer,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.2),
                    blurRadius: 30,
                    offset: const Offset(0, 15),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(LucideIcons.headphones,
                      size: 120,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.3)),
                  if (isPlaying)
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(48.0),
                        child:
                            _CircularWaveform(color: scheme.onPrimaryContainer),
                      ),
                    ),
                ],
              ),
            ),
          )
              .animate()
              .fadeIn()
              .scale(duration: 400.ms, curve: Curves.easeOutBack),

          const SizedBox(height: 32),

          // Title Section
          Column(
            children: [
              Text(
                overview.title,
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  height: 1.2,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                'Custom Podcast',
                style: text.titleMedium?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Progress Bar
          _ProgressBar(
            audioHandler: audioHandler,
            duration: overview.duration,
          ),

          const SizedBox(height: 16),

          // Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 28,
                onPressed: hasPrev
                    ? () {
                        // Use skipToPrevious for queue-aware navigation
                        ref
                            .read(audioPlaybackProvider.notifier)
                            .skipToPrevious();
                      }
                    : null,
                icon: const Icon(LucideIcons.skipBack),
                color: scheme.onSurface,
              ),

              // Rewind 15s
              IconButton(
                iconSize: 24,
                onPressed: () {
                  final current = audioHandler.playbackState.value.position;
                  audioHandler.seek(current - const Duration(seconds: 15));
                },
                icon: const Icon(LucideIcons.rotateCcw),
                color: scheme.secondary,
              ),

              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [scheme.primary, scheme.tertiary],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: IconButton(
                  iconSize: 32,
                  color: Colors.white,
                  onPressed: () {
                    if (isPlaying) {
                      ref.read(audioPlaybackProvider.notifier).pause();
                    } else {
                      // Pass the full queue context when playing directly
                      ref.read(audioPlaybackProvider.notifier).play(
                            overview,
                            queue: overviews,
                          );
                    }
                  },
                  icon: Icon(isPlaying ? LucideIcons.pause : LucideIcons.play),
                ),
              ),

              IconButton(
                iconSize: 24,
                onPressed: () {
                  final current = audioHandler.playbackState.value.position;
                  audioHandler.seek(current + const Duration(seconds: 30));
                },
                icon: const Icon(LucideIcons.rotateCw),
                color: scheme.secondary,
              ),

              IconButton(
                iconSize: 28,
                onPressed: hasNext
                    ? () {
                        // Use skipToNext for queue-aware navigation
                        ref.read(audioPlaybackProvider.notifier).skipToNext();
                      }
                    : null,
                icon: const Icon(LucideIcons.skipForward),
                color: scheme.onSurface,
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 24,
            children: [
              _ActionButton(
                icon: LucideIcons.share2,
                label: 'Share',
                onTap: () async {
                  try {
                    // Share the actual audio file
                    final file = XFile(overview.url);
                    await Share.shareXFiles(
                      [file],
                      text: overview.title,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Share failed: $e')),
                      );
                    }
                  }
                },
              ),
              _ActionButton(
                icon: LucideIcons.download,
                label: 'Save',
                onTap: () => _saveToDownloads(context, overview),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// Save audio file without requiring legacy storage permission prompts
  Future<void> _saveToDownloads(
      BuildContext context, AudioOverview overview) async {
    try {
      final sourceFile = await _resolveSourceFile(overview.url);
      if (sourceFile == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audio file not found')),
          );
        }
        return;
      }

      final saveDir = await _resolveSaveDirectory();
      if (saveDir == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not access a save location')),
          );
        }
        return;
      }
      await saveDir.create(recursive: true);

      // Create safe filename
      final safeTitle = overview.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\- ]'), '')
          .replaceAll(' ', '_');
      final extension = p.extension(sourceFile.path).isNotEmpty
          ? p.extension(sourceFile.path)
          : '.mp3';
      final baseName = '${safeTitle}_${overview.id}';
      var fileName = '$baseName$extension';
      var destPath = p.join(saveDir.path, fileName);
      var suffix = 1;
      while (await File(destPath).exists()) {
        fileName = '${baseName}_$suffix$extension';
        destPath = p.join(saveDir.path, fileName);
        suffix++;
      }

      // Copy file
      await sourceFile.copy(destPath);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved to ${_saveLocationLabel(saveDir)}: $fileName',
            ),
            action: SnackBarAction(
              label: 'Share',
              onPressed: () {
                Share.shareXFiles([XFile(destPath)], text: 'Open audio file');
              },
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<File?> _resolveSourceFile(String sourceUrl) async {
    final uri = Uri.tryParse(sourceUrl);
    final resolvedPath =
        uri != null && uri.scheme == 'file'
            ? uri.toFilePath(windows: Platform.isWindows)
            : sourceUrl;
    final file = File(resolvedPath);
    return await file.exists() ? file : null;
  }

  Future<Directory?> _resolveSaveDirectory() async {
    if (Platform.isAndroid) {
      final externalDownloads =
          await getExternalStorageDirectories(type: StorageDirectory.downloads);
      if (externalDownloads != null && externalDownloads.isNotEmpty) {
        return Directory(p.join(externalDownloads.first.path, 'NoteClaw'));
      }

      final externalMusic =
          await getExternalStorageDirectories(type: StorageDirectory.music);
      if (externalMusic != null && externalMusic.isNotEmpty) {
        return Directory(p.join(externalMusic.first.path, 'NoteClaw'));
      }

      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        return Directory(p.join(externalDir.path, 'NoteClaw'));
      }
    }

    final downloadsDir = await getDownloadsDirectory();
    if (downloadsDir != null) {
      return Directory(p.join(downloadsDir.path, 'NoteClaw'));
    }

    final docsDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(docsDir.path, 'NoteClaw'));
  }

  String _saveLocationLabel(Directory directory) {
    final normalizedPath = directory.path.toLowerCase();
    if (normalizedPath.contains('download')) {
      return 'Downloads';
    }
    return 'NoteClaw storage';
  }
}

class _ProgressBar extends StatelessWidget {
  final AudioHandler audioHandler;
  final Duration duration;

  const _ProgressBar({
    required this.audioHandler,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return StreamBuilder<MediaState>(
      stream: _mediaStateStream,
      builder: (context, snapshot) {
        final mediaState = snapshot.data;
        final position = mediaState?.position ?? Duration.zero;
        var maxDuration = duration;

        if (position > maxDuration) {
          maxDuration = position;
        }

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                activeTrackColor: scheme.primary,
                inactiveTrackColor: scheme.surfaceContainerHighest,
                thumbColor: scheme.primary,
                overlayColor: scheme.primary.withValues(alpha: 0.1),
              ),
              child: Slider(
                value: position.inMilliseconds
                    .toDouble()
                    .clamp(0, maxDuration.inMilliseconds.toDouble()),
                max: maxDuration.inMilliseconds.toDouble(),
                onChanged: (value) {
                  audioHandler.seek(Duration(milliseconds: value.round()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position),
                      style: text.bodySmall?.copyWith(
                          color: scheme.secondary,
                          fontFeatures: [const FontFeature.tabularFigures()])),
                  Text(_formatDuration(maxDuration),
                      style: text.bodySmall?.copyWith(
                          color: scheme.secondary,
                          fontFeatures: [const FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Stream<MediaState> get _mediaStateStream {
    return AudioService.position.map((position) {
      return MediaState(position, audioHandler.playbackState.value);
    });
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }
}

class MediaState {
  final Duration position;
  final PlaybackState playbackState;
  MediaState(this.position, this.playbackState);
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ],
        ),
      ),
    );
  }
}

class _CircularWaveform extends StatefulWidget {
  final Color color;
  const _CircularWaveform({required this.color});

  @override
  State<_CircularWaveform> createState() => _CircularWaveformState();
}

class _CircularWaveformState extends State<_CircularWaveform>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _WavePainter(
            color: widget.color.withValues(alpha: 0.5),
            animationValue: _controller.value,
          ),
          child: Container(),
        );
      },
    );
  }
}

class _WavePainter extends CustomPainter {
  final Color color;
  final double animationValue;

  _WavePainter({required this.color, required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < 3; i++) {
      final currentRadius = radius * ((animationValue + i * 0.3) % 1.0);
      final opacity = 1.0 - ((animationValue + i * 0.3) % 1.0);
      paint.color = color.withValues(alpha: opacity * 0.5);
      canvas.drawCircle(center, currentRadius, paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => true;
}
