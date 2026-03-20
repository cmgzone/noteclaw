import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Provider for Google TTS service
final googleTtsServiceProvider = Provider<GoogleTtsService>((ref) {
  return GoogleTtsService();
});

class GoogleTtsService {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;

  // Available voices (these are standard Google TTS voices)
  static const Map<String, String> voices = {
    // Standard Voices (Reliable, Offline)
    'en-US-Standard-A': 'Standard Female 1',
    'en-US-Standard-B': 'Standard Male 1',
    'en-US-Standard-C': 'Standard Female 2',
    'en-US-Standard-D': 'Standard Male 2',

    // Wavenet Voices (High Quality)
    'en-US-Wavenet-A': 'Wavenet Female 1 (Premium)',
    'en-US-Wavenet-B': 'Wavenet Male 1 (Premium)',
    'en-US-Wavenet-C': 'Wavenet Female 2 (Premium)',
    'en-US-Wavenet-D': 'Wavenet Male 2 (Premium)',
    'en-US-Wavenet-E': 'Wavenet Female 3 (Premium)',
    'en-US-Wavenet-F': 'Wavenet Female 4 (Premium)',
    'en-US-Wavenet-G': 'Wavenet Female 5 (Premium)',
    'en-US-Wavenet-H': 'Wavenet Female 6 (Premium)',
    'en-US-Wavenet-I': 'Wavenet Male 3 (Premium)',
    'en-US-Wavenet-J': 'Wavenet Male 4 (Premium)',

    // Neural2 / Studio / Journey (Ultra Premium - if available)
    'en-US-Neural2-A': 'Neural2 Female (Ultra)',
    'en-US-Neural2-D': 'Neural2 Male (Ultra)',
    'en-US-Studio-M': 'Studio Male (Ultra)',
    'en-US-Studio-O': 'Studio Female (Ultra)',
    'en-US-Journey-D': 'Journey Male (Ultra)',
    'en-US-Journey-F': 'Journey Female (Ultra)',
  };

  GoogleTtsService() {
    _initialize();
  }

  Future<void> _initialize() async {
    if (!_isInitialized) {
      try {
        // Set up TTS configuration
        await _flutterTts.setLanguage('en-US');
        await _flutterTts.setSpeechRate(0.5); // Normal speed
        await _flutterTts.setVolume(1.0);
        await _flutterTts.setPitch(1.0);
        await _flutterTts.awaitSpeakCompletion(true);

        // Set up handlers
        _flutterTts.setStartHandler(() {
          debugPrint('Google TTS: Started speaking');
        });

        _flutterTts.setCompletionHandler(() {
          debugPrint('Google TTS: Completed speaking');
        });

        _flutterTts.setErrorHandler((msg) {
          final normalized = msg.toString().toLowerCase();
          final isInterrupted = normalized.contains('interrupted') ||
              normalized.contains('canceled') ||
              normalized.contains('cancelled') ||
              normalized.contains('speechsynthesiserrorevent');

          if (isInterrupted) {
            debugPrint('Google TTS: Speech interrupted');
            return;
          }

          debugPrint('Google TTS Error: $msg');
        });

        _isInitialized = true;
        debugPrint('Google TTS initialized successfully');
      } catch (e) {
        debugPrint('Failed to initialize Google TTS: $e');
      }
    }
  }

  /// Speak the given text using Google TTS
  Future<void> speak(
    String text, {
    String? voiceName,
    double? speechRate,
    double? pitch,
    double? volume,
  }) async {
    if (!_isInitialized) {
      await _initialize();
    }

    try {
      // Stop any current speech
      await stop();

      // Configure speech parameters
      if (speechRate != null) {
        await _flutterTts.setSpeechRate(speechRate);
      }
      if (pitch != null) {
        await _flutterTts.setPitch(pitch);
      }
      if (volume != null) {
        await _flutterTts.setVolume(volume);
      }

      // Set voice if specified
      if (voiceName != null) {
        await _setVoice(voiceName);
      }

      // Speak
      await _flutterTts.speak(text);
    } catch (e) {
      debugPrint('Google TTS speak error: $e');
      rethrow;
    }
  }

  /// Set specific voice
  Future<void> _setVoice(String voiceName) async {
    try {
      // flutter_tts uses setVoice with a map
      // The format varies by platform
      if (defaultTargetPlatform == TargetPlatform.android) {
        // On Android, we can set the voice by name
        await _flutterTts.setVoice({'name': voiceName, 'locale': 'en-US'});
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        // On iOS, voice setting is different
        await _flutterTts.setVoice({'name': voiceName, 'locale': 'en-US'});
      }
    } catch (e) {
      debugPrint('Failed to set voice: $e');
      // Continue with default voice if setting fails
    }
  }

  /// Stop current speech
  Future<void> stop() async {
    try {
      await _flutterTts.stop();
    } catch (e) {
      debugPrint('Google TTS stop error: $e');
    }
  }

  /// Pause current speech
  Future<void> pause() async {
    try {
      await _flutterTts.pause();
    } catch (e) {
      debugPrint('Google TTS pause error: $e');
    }
  }

  /// Get available voices from the device
  Future<List<Map<String, String>>> getAvailableVoices() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices is List) {
        return voices
            .where((voice) =>
                voice['locale']?.toString().startsWith('en') ?? false)
            .map((voice) => {
                  'name': voice['name']?.toString() ?? '',
                  'locale': voice['locale']?.toString() ?? '',
                })
            .toList();
      }
    } catch (e) {
      debugPrint('Failed to get voices: $e');
    }

    // Return default voices list
    return GoogleTtsService.voices.entries
        .map((e) => {'name': e.key, 'displayName': e.value})
        .toList();
  }

  /// Get available languages
  Future<List<String>> getLanguages() async {
    try {
      final languages = await _flutterTts.getLanguages;
      if (languages is List) {
        return languages.map((lang) => lang.toString()).toList();
      }
    } catch (e) {
      debugPrint('Failed to get languages: $e');
    }
    return ['en-US'];
  }

  /// Set language
  Future<void> setLanguage(String language) async {
    try {
      await _flutterTts.setLanguage(language);
    } catch (e) {
      debugPrint('Failed to set language: $e');
    }
  }

  /// Check if TTS is speaking
  Future<bool> isSpeaking() async {
    try {
      return await _flutterTts.awaitSpeakCompletion(false);
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
