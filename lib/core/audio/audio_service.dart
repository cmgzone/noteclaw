import 'package:audio_service/audio_service.dart';
import 'audio_handler.dart';

Future<AudioHandler> initAudioService() async {
  return await AudioService.init(
    builder: () => AudioPlayerHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.noteclaw.audio',
      androidNotificationChannelName: 'NoteClaw Audio',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
}
