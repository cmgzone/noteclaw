import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_service/audio_service.dart';
import 'background_audio_service.dart';
import 'audio_cache.dart';
import 'audio_handler.dart';
import '../../features/studio/audio_overview.dart';

final backgroundAudioProvider = Provider((ref) => BackgroundAudioService());

final audioPlaybackProvider =
    StateNotifierProvider<AudioPlaybackNotifier, AudioPlaybackState>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final cache = ref.watch(audioCacheProvider.notifier);
  return AudioPlaybackNotifier(handler, cache);
});

final audioHandlerProvider = Provider<AudioHandler>(
    (ref) => throw UnimplementedError('Override in main'));

class AudioPlaybackState {
  final bool isPlaying;
  final String? currentUrl;
  final AudioOverview? currentOverview;

  AudioPlaybackState(
      {this.isPlaying = false, this.currentUrl, this.currentOverview});

  AudioPlaybackState copyWith(
      {bool? isPlaying, String? currentUrl, AudioOverview? currentOverview}) {
    return AudioPlaybackState(
      isPlaying: isPlaying ?? this.isPlaying,
      currentUrl: currentUrl ?? this.currentUrl,
      currentOverview: currentOverview ?? this.currentOverview,
    );
  }
}

class AudioPlaybackNotifier extends StateNotifier<AudioPlaybackState> {
  final AudioHandler _handler;
  final AudioCacheNotifier _cache;

  AudioPlaybackNotifier(this._handler, this._cache)
      : super(AudioPlaybackState()) {
    _initStreams();
  }

  void _initStreams() {
    // Listen to playback state
    _handler.playbackState.listen((playbackState) {
      final isPlaying = playbackState.playing;
      if (state.isPlaying != isPlaying) {
        state = state.copyWith(isPlaying: isPlaying);
      }
    });

    // Listen to media item changes (queue advancement)
    _handler.mediaItem.listen((mediaItem) {
      if (mediaItem != null && mediaItem.extras != null) {
        try {
          // Reconstruct AudioOverview from extras if present
          if (mediaItem.extras!.containsKey('overview_json')) {
            final json = jsonDecode(mediaItem.extras!['overview_json']);
            final overview = AudioOverview.fromJson(json);

            if (state.currentOverview?.id != overview.id) {
              state = state.copyWith(
                currentUrl: overview.url,
                currentOverview: overview,
              );
            }
          }
        } catch (e) {
          // Fallback or ignore
        }
      }
    });
  }

  Future<void> play(AudioOverview overview,
      {List<AudioOverview>? queue}) async {
    if (!overview.isOffline) {
      // We don't await this to start playing faster
      _cache.cache(overview);
    }

    // If a queue is provided, update the handler's queue
    if (queue != null && queue.isNotEmpty && _handler is AudioPlayerHandler) {
      final mediaItems = queue.map((item) => _mapToMediaItem(item)).toList();
      await _handler.updateQueue(mediaItems);

      // Find index of the requested item
      final index = queue.indexWhere((i) => i.id == overview.id);
      if (index != -1) {
        await _handler.playAtIndex(index);
      } else {
        await _handler.play();
      }
    } else {
      // Single item fallback
      await _handler.customAction('setUrl', {'url': overview.url});
      await _handler.play();
    }

    // State is updated via streams, but we can optimistically set it here too
    state = state.copyWith(
        isPlaying: true, currentUrl: overview.url, currentOverview: overview);
  }

  Future<void> pause() async {
    await _handler.pause();
    // state updated via stream
  }

  Future<void> stop() async {
    await _handler.stop();
    // state updated via stream
  }

  Future<void> skipToNext() async {
    await _handler.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _handler.skipToPrevious();
  }

  MediaItem _mapToMediaItem(AudioOverview overview) {
    return MediaItem(
      id: overview.url, // Using URL as ID for just_audio convenience
      title: overview.title,
      artist: 'NoteClaw',
      duration: overview.duration,
      artUri: null, // Could generate a placeholder URI or use app icon
      extras: {
        'overview_json': jsonEncode(overview.toJson()),
        'id': overview.id, // Original ID
      },
    );
  }
}
