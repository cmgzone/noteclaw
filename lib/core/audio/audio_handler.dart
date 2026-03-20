import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
//

class AudioPlayerHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  var _playlist = ConcatenatingAudioSource(children: []);

  AudioPlayerHandler() {
    _loadEmptyPlaylist();
    _notifyAudioHandlerAboutPlaybackEvents();
    _listenToPlaybackState();
    _listenToCurrentPosition();
    _listenToBufferedPosition();
    _listenToTotalDuration();
    _listenToSequenceState();
  }

  Future<void> _loadEmptyPlaylist() async {
    try {
      await _player.setAudioSource(_playlist);
    } catch (e) {
      // ignore
    }
  }

  void _notifyAudioHandlerAboutPlaybackEvents() {
    _player.playbackEventStream.listen((PlaybackEvent event) {
      final playing = _player.playing;
      playbackState.add(playbackState.value.copyWith(
        controls: [
          MediaControl.rewind,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.fastForward, // Stop vs Next?
        ],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: const {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
        playing: playing,
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: event.currentIndex,
      ));
    });
  }

  void _listenToPlaybackState() {
    _player.playerStateStream.listen((state) {
      _notifyAudioHandlerAboutPlaybackEvents();
    });
  }

  void _listenToCurrentPosition() {
    _player.positionStream.listen((position) {
      final oldState = playbackState.value;
      playbackState.add(oldState.copyWith(updatePosition: position));
    });
  }

  void _listenToBufferedPosition() {
    _player.bufferedPositionStream.listen((bufferedPosition) {
      final oldState = playbackState.value;
      playbackState.add(oldState.copyWith(bufferedPosition: bufferedPosition));
    });
  }

  void _listenToTotalDuration() {
    _player.durationStream.listen((totalDuration) {
      if (mediaItem.value != null && totalDuration != null) {
        mediaItem.add(mediaItem.value!.copyWith(duration: totalDuration));
      }
    });
  }

  void _listenToSequenceState() {
    _player.sequenceStateStream.listen((SequenceState? sequenceState) {
      final sequence = sequenceState?.sequence;
      if (sequence == null || sequence.isEmpty) return;
      final items = sequence.map((source) => source.tag as MediaItem).toList();
      queue.add(items);
      mediaItem.add(sequenceState?.currentSource?.tag as MediaItem?);
    });
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    await playbackState.firstWhere(
        (state) => state.processingState == AudioProcessingState.idle);
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (_player.hasNext) {
      await _player.seekToNext();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (_player.hasPrevious) {
      await _player.seekToPrevious();
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    // 1. Define audio sources
    final audioSources = queue.map((item) {
      return AudioSource.uri(
        _toPlaybackUri(item.id), // We treat ID as the URL for simplicity
        tag: item,
      );
    }).toList();

    // 2. Create playlist
    _playlist = ConcatenatingAudioSource(children: audioSources);

    // 3. Set source (this resets playback, suitable for "Play All" or new context)
    // For seamless appending, we would use _playlist.add(), but here we replace context.
    await _player.setAudioSource(_playlist);

    // 4. Update queue stream (redundant if listening to sequence, but good for immediate update)
    this.queue.add(queue);
  }

  // Helper to jump to specific index in the new queue immediately
  Future<void> playAtIndex(int index) async {
    if (index >= 0 && index < _playlist.length) {
      await _player.seek(Duration.zero, index: index);
      play();
    }
  }

  @override
  Future<dynamic> customAction(String name,
      [Map<String, dynamic>? extras]) async {
    if (name == 'setUrl') {
      final url = extras?['url']?.toString();
      if (url == null || url.isEmpty) {
        return null;
      }

      final item = MediaItem(
        id: url,
        title: extras?['title']?.toString() ?? 'Audio Overview',
        artist: 'NoteClaw',
        extras: extras == null ? null : Map<String, dynamic>.from(extras),
      );

      final audioSource = AudioSource.uri(
        _toPlaybackUri(url),
        tag: item,
      );

      _playlist = ConcatenatingAudioSource(children: [audioSource]);
      await _player.setAudioSource(_playlist);
      queue.add([item]);
      mediaItem.add(item);
      return null;
    }

    if (name == 'setQueue') {
      // Expects 'items' (List<MediaItem encoded maps>?) or handle in provider
      // Simpler to define updateQueue in the abstract class if we could, but base doesn't have it.
      // We will cast to AudioPlayerHandler in provider to call updateQueue.
      return null;
    }
    return super.customAction(name, extras);
  }

  Uri _toPlaybackUri(String source) {
    final parsed = Uri.tryParse(source);
    if (parsed != null && parsed.scheme.isNotEmpty) {
      return parsed;
    }

    return Uri.file(source, windows: Platform.isWindows);
  }
}
