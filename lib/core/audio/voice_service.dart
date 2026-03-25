import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:just_audio/just_audio.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'elevenlabs_service.dart';
import 'google_tts_service.dart';
import 'google_cloud_tts_service.dart';
import 'deepgram_websocket_service.dart';

import 'murf_service.dart';

enum TtsProvider { elevenlabs, google, googleCloud, murf }

enum SttProvider { device, deepgram }

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final elevenLabs = ref.read(elevenLabsServiceProvider);
  final googleTts = ref.read(googleTtsServiceProvider);
  final googleCloudTts = ref.read(googleCloudTtsServiceProvider);
  final murfService = ref.read(murfServiceProvider);
  final deepgramWs = ref.read(deepgramWebSocketProvider);
  return VoiceService(
      elevenLabs, googleTts, googleCloudTts, murfService, deepgramWs);
});

class VoiceService {
  final ElevenLabsService _elevenLabsService;
  final GoogleTtsService _googleTtsService;
  final GoogleCloudTtsService _googleCloudTtsService;
  final MurfService _murfService;
  final DeepgramWebSocketService _deepgramService;
  final SpeechToText _speechToText = SpeechToText();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isInitialized = false;
  TtsProvider _currentProvider = TtsProvider.google; // Default to free option
  SttProvider _currentSttProvider = SttProvider.device; // Default to device STT

  // Store accumulated text for Deepgram (so stopListening can return it)
  String _deepgramAccumulatedText = '';
  Timer? _deepgramSilenceTimer;
  Function(String)? _deepgramOnDone;

  VoiceService(
    this._elevenLabsService,
    this._googleTtsService,
    this._googleCloudTtsService,
    this._murfService,
    this._deepgramService,
  ) {
    _loadTtsProvider();
    _loadSttProvider();
  }

  Future<void> _loadSttProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerStr = prefs.getString('stt_provider') ?? 'device';
      _currentSttProvider =
          providerStr == 'deepgram' ? SttProvider.deepgram : SttProvider.device;
    } catch (e) {
      debugPrint('Failed to load STT provider: $e');
    }
  }

  Future<void> setSttProvider(SttProvider provider) async {
    _currentSttProvider = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('stt_provider',
          provider == SttProvider.deepgram ? 'deepgram' : 'device');
    } catch (e) {
      debugPrint('Failed to save STT provider: $e');
    }
  }

  SttProvider get currentSttProvider => _currentSttProvider;

  Future<void> _loadTtsProvider() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerStr = prefs.getString('tts_provider') ?? 'google';
      if (providerStr == 'elevenlabs') {
        _currentProvider = TtsProvider.elevenlabs;
      } else if (providerStr == 'google_cloud') {
        _currentProvider = TtsProvider.googleCloud;
      } else if (providerStr == 'murf') {
        _currentProvider = TtsProvider.murf;
      } else {
        _currentProvider = TtsProvider.google;
      }
    } catch (e) {
      debugPrint('Failed to load TTS provider: $e');
    }
  }

  Future<void> setTtsProvider(TtsProvider provider) async {
    _currentProvider = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      String providerStr = 'google';
      if (provider == TtsProvider.elevenlabs) providerStr = 'elevenlabs';
      if (provider == TtsProvider.googleCloud) providerStr = 'google_cloud';
      if (provider == TtsProvider.murf) providerStr = 'murf';

      await prefs.setString('tts_provider', providerStr);
    } catch (e) {
      debugPrint('Failed to save TTS provider: $e');
    }
  }

  TtsProvider get currentProvider => _currentProvider;

  Future<bool> initialize() async {
    if (!_isInitialized) {
      _isInitialized = await _speechToText.initialize(
        onError: (e) => debugPrint('STT Error: $e'),
        onStatus: (s) => debugPrint('STT Status: $s'),
      );
    }
    return _isInitialized;
  }

  String _lastRecognizedText = '';
  bool _hasProcessedFinalResult = false; // Prevent duplicate processing

  // Audio level from speech recognition (0.0 - 1.0)
  double _currentAudioLevel = 0.0;
  double get currentAudioLevel => _currentAudioLevel;

  Future<void> listen({
    required Function(String) onResult,
    required Function(String) onDone,
    Function(double)? onSoundLevel,
    String language = 'en',
    bool detectLanguage = false,
  }) async {
    // Use Deepgram WebSocket for faster transcription if selected
    if (_currentSttProvider == SttProvider.deepgram) {
      await _listenWithDeepgram(
        onResult: onResult,
        onDone: onDone,
        language: language,
        detectLanguage: detectLanguage,
      );
      return;
    }

    // Fallback to device speech recognition
    await _listenWithDevice(
      onResult: onResult,
      onDone: onDone,
      onSoundLevel: onSoundLevel,
    );
  }

  Future<void> _listenWithDeepgram({
    required Function(String) onResult,
    required Function(String) onDone,
    String language = 'en',
    bool detectLanguage = false,
  }) async {
    final hasPermission = await _deepgramService.initialize();
    if (!hasPermission) {
      throw Exception('Microphone permission denied');
    }

    _deepgramAccumulatedText = '';
    _deepgramOnDone = onDone;

    // Auto-stop after silence (user stopped speaking)
    void resetSilenceTimer() {
      _deepgramSilenceTimer?.cancel();
      _deepgramSilenceTimer = Timer(const Duration(seconds: 2), () {
        // User stopped speaking for 2 seconds, process the result
        if (_deepgramAccumulatedText.trim().isNotEmpty) {
          debugPrint(
              'Deepgram: Silence detected, processing: $_deepgramAccumulatedText');
          final textToProcess = _deepgramAccumulatedText.trim();
          _deepgramAccumulatedText = '';
          _deepgramOnDone?.call(textToProcess);
        }
      });
    }

    await _deepgramService.startListening(
      onResult: (text, isFinal) {
        if (isFinal && text.isNotEmpty) {
          _deepgramAccumulatedText += ' $text';
          onResult(_deepgramAccumulatedText.trim());
          resetSilenceTimer();
        } else if (!isFinal && text.isNotEmpty) {
          // Show interim results
          onResult('$_deepgramAccumulatedText $text'.trim());
          resetSilenceTimer();
        }
      },
      onErrorCallback: (error) {
        debugPrint('Deepgram error: $error');
        _deepgramSilenceTimer?.cancel();
      },
      language: language,
      detectLanguage: detectLanguage,
      interimResults: true,
    );
  }

  Future<void> _listenWithDevice({
    required Function(String) onResult,
    required Function(String) onDone,
    Function(double)? onSoundLevel,
  }) async {
    if (!_isInitialized) await initialize();

    _lastRecognizedText = '';
    _currentAudioLevel = 0.0;
    _hasProcessedFinalResult = false;

    if (_speechToText.isAvailable) {
      await _speechToText.listen(
        onResult: (result) {
          final text = result.recognizedWords;
          // Always store the latest recognized text
          if (text.isNotEmpty) {
            _lastRecognizedText = text;
          }
          onResult(text);
          if (result.finalResult && !_hasProcessedFinalResult) {
            _hasProcessedFinalResult = true;
            // Use the stored text to ensure we don't lose it
            final finalText = text.isNotEmpty ? text : _lastRecognizedText;
            if (finalText.isNotEmpty) {
              onDone(finalText);
            }
          }
        },
        onSoundLevelChange: (level) {
          // Normalize sound level (typically -2 to 10 dB range) to 0.0 - 1.0
          _currentAudioLevel = ((level + 2) / 12).clamp(0.0, 1.0);
          onSoundLevel?.call(_currentAudioLevel);
        },
        listenFor: const Duration(seconds: 60), // Increased from 30s
        pauseFor: const Duration(
            seconds: 5), // Increased from 3s for better pause tolerance
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false, // Don't cancel on error, try to recover
          listenMode: ListenMode.dictation,
        ),
      );

      // Set up a listener for when speech stops (status changes)
      // Only use this as a fallback if finalResult wasn't triggered
      _speechToText.statusListener = (status) {
        debugPrint('STT Status changed: $status');
        if ((status == 'done' || status == 'notListening') &&
            !_hasProcessedFinalResult) {
          // If we have text that wasn't sent via finalResult, send it now
          if (_lastRecognizedText.isNotEmpty) {
            _hasProcessedFinalResult = true;
            final textToSend = _lastRecognizedText;
            _lastRecognizedText = ''; // Clear to prevent duplicate sends
            // Small delay to ensure we don't conflict with finalResult callback
            Future.delayed(const Duration(milliseconds: 200), () {
              if (textToSend.isNotEmpty && !_speechToText.isListening) {
                onDone(textToSend);
              }
            });
          }
        }
      };
    } else {
      debugPrint('Speech recognition not available on this device');
      throw Exception(
          'Speech recognition not available. Please ensure Google app is installed and microphone is working.');
    }
  }

  Future<String> stopListening() async {
    // Stop Deepgram if it's listening
    if (_deepgramService.isListening) {
      _deepgramSilenceTimer?.cancel();
      // Return accumulated text from our local storage (more reliable)
      final transcript = _deepgramAccumulatedText.trim().isNotEmpty
          ? _deepgramAccumulatedText.trim()
          : _deepgramService.fullTranscript;
      _deepgramAccumulatedText = '';
      _deepgramOnDone = null;
      await _deepgramService.stopListening();
      return transcript;
    }

    // Stop device speech recognition
    final capturedText = _lastRecognizedText;
    _hasProcessedFinalResult = true; // Prevent any pending callbacks
    await _speechToText.stop();
    _lastRecognizedText = ''; // Clear after stopping
    return capturedText; // Return the last recognized text
  }

  /// Get the current recognized text without stopping
  String get currentRecognizedText => _deepgramService.isListening
      ? '${_deepgramService.fullTranscript} ${_deepgramService.interimTranscript}'
          .trim()
      : _lastRecognizedText;

  /// Check if currently listening (either provider)
  bool get isListening =>
      _speechToText.isListening || _deepgramService.isListening;

  /// Sanitize text for TTS - removes symbols and formatting that sound unprofessional.
  static String sanitizeTextForTts(String text) {
    String cleaned = text;

    // Decode common HTML entities before stripping markup.
    cleaned = cleaned.replaceAll('&nbsp;', ' ');
    cleaned = cleaned.replaceAll('&amp;', ' and ');
    cleaned = cleaned.replaceAll('&quot;', '"');
    cleaned = cleaned.replaceAll('&#39;', '\'');
    cleaned = cleaned.replaceAll('&lt;', ' less than ');
    cleaned = cleaned.replaceAll('&gt;', ' greater than ');
    cleaned = cleaned.replaceAll('&mdash;', ', ');
    cleaned = cleaned.replaceAll('&ndash;', ', ');

    // Remove HTML tags.
    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ');

    // Remove markdown code blocks (```code```)
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), ' code block ');

    // Remove inline code (`code`)
    cleaned = cleaned.replaceAll(RegExp(r'`[^`]+`'), ' code ');

    // Remove markdown headers (# ## ### etc)
    cleaned = cleaned.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');

    // Remove markdown bold/italic (**text**, *text*, __text__, _text_)
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '');
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
    cleaned =
        cleaned.replaceAllMapped(RegExp(r'_([^_]+)_'), (m) => m.group(1) ?? '');

    // Remove markdown images before links so image syntax does not leave behind stray punctuation.
    cleaned = cleaned.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'!\[[^\]]*\]\[[^\]]*\]'), ' ');

    // Remove markdown links [text](url) -> just text
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]+\)'), (m) => m.group(1) ?? '');

    // Remove reference-style links and footnotes.
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\[[^\]]*\]'), (m) => m.group(1) ?? '');
    cleaned = cleaned.replaceAll(RegExp(r'\[\^[^\]]+\]'), ' ');

    // Remove URLs
    cleaned = cleaned.replaceAll(RegExp(r'https?://[^\s]+'), ' link ');

    // Remove markdown table separators and convert table pipes into short pauses.
    cleaned = cleaned.replaceAll(
        RegExp(r'^\s*\|?[:\- ]+\|[:\-\| ]*$', multiLine: true), '');
    cleaned = cleaned.replaceAll('|', ', ');

    // Remove bullet points and list markers
    cleaned =
        cleaned.replaceAll(RegExp(r'^[\s]*[-*•]\s*', multiLine: true), '');
    cleaned =
        cleaned.replaceAll(RegExp(r'^[\s]*\d+\.\s*', multiLine: true), '');

    // Convert currency symbols to words (must have at least 1 digit after symbol)
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'\$(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'),
        (m) => '${m.group(1)} dollars');
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'€(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'),
        (m) => '${m.group(1)} euros');
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'£(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'),
        (m) => '${m.group(1)} pounds');

    // Remove standalone currency and special symbols (not followed by digits)
    cleaned = cleaned.replaceAll(RegExp(r'[\$€£¥₹](?!\d)'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'[#@&\\<>{}[\]^~]'), ' ');

    // Convert dashes to natural pauses (remove them, TTS handles pauses naturally)
    cleaned = cleaned.replaceAll('--', ', '); // Double dash to comma pause
    cleaned = cleaned.replaceAll('—', ', '); // Em-dash to comma pause
    cleaned = cleaned.replaceAll('–', ', '); // En-dash to comma pause
    cleaned = cleaned.replaceAll(' - ', ', '); // Spaced dash to comma pause

    // Convert common symbols to words
    cleaned = cleaned.replaceAll(' & ', ' and ');
    cleaned = cleaned.replaceAll(' + ', ' plus ');
    cleaned = cleaned.replaceAll(' = ', ' equals ');
    cleaned = cleaned.replaceAll(' -> ', ' to ');
    cleaned = cleaned.replaceAll(' => ', ' results in ');
    cleaned = cleaned.replaceAll(' / ', ' or ');
    cleaned = cleaned.replaceAll(' % ', ' percent ');
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'(?<=[A-Za-z0-9])/(?=[A-Za-z0-9])'), (_) => ' or ');

    // Handle percentages (50%)
    cleaned = cleaned.replaceAllMapped(
        RegExp(r'(\d+)%'), (m) => '${m.group(1)} percent');

    // Remove symbol-heavy lines and stray decorative glyphs that sound bad in TTS.
    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s\W_]{3,}$', multiLine: true),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'[•▪◦●○■□◆◇▶►✓✔✗✘※©®™§¶†‡¤¢]'),
      ' ',
    );

    // Remove excessive punctuation
    cleaned = cleaned.replaceAll(RegExp(r'[!]{2,}'), '!');
    cleaned = cleaned.replaceAll(RegExp(r'[?]{2,}'), '?');
    cleaned = cleaned.replaceAll(RegExp(r'[.]{3,}'), '...');
    cleaned = cleaned.replaceAll(RegExp(r',{2,}'), ',');

    // Remove emoji (basic range)
    cleaned = cleaned.replaceAll(
        RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true), ' ');

    // Clean up multiple spaces and newlines
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r' *([,.;!?]) *'), r'$1 ');

    // Trim and clean
    cleaned = cleaned.trim();

    return cleaned;
  }

  static String sanitizeNarrationText(String text) {
    String cleaned = _normalizeTtsArtifacts(text);

    cleaned = cleaned.replaceAll('&nbsp;', ' ');
    cleaned = cleaned.replaceAll('&amp;', ' and ');
    cleaned = cleaned.replaceAll('&quot;', '"');
    cleaned = cleaned.replaceAll('&#39;', '\'');
    cleaned = cleaned.replaceAll('&lt;', ' less than ');
    cleaned = cleaned.replaceAll('&gt;', ' greater than ');
    cleaned = cleaned.replaceAll('&mdash;', ', ');
    cleaned = cleaned.replaceAll('&ndash;', ', ');

    cleaned = cleaned.replaceAll(RegExp(r'<[^>]+>'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'```[\s\S]*?```'), ' code block ');
    cleaned = cleaned.replaceAll(RegExp(r'`[^`]+`'), ' code ');
    cleaned = cleaned.replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*>+\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(
      RegExp(r'^\s*[-*+]\s+\[[ xX]\]\s*', multiLine: true),
      '',
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*\*([^*]+)\*\*'),
      (m) => m.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\*([^*]+)\*'),
      (m) => m.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'__([^_]+)__'),
      (m) => m.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'_([^_]+)_'),
      (m) => m.group(1) ?? '',
    );

    cleaned = cleaned.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]+\)'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'!\[[^\]]*\]\[[^\]]*\]'), ' ');
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\([^)]+\)'),
      (m) => m.group(1) ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\[[^\]]*\]'),
      (m) => m.group(1) ?? '',
    );
    cleaned = cleaned.replaceAll(RegExp(r'\[\^[^\]]+\]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'(?<!\w)\[\d{1,3}\](?!\w)'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'https?://[^\s]+'), ' link ');

    cleaned = cleaned.replaceAll(
      RegExp(r'^\s*\|?[:\- ]+\|[:\-\| ]*$', multiLine: true),
      '',
    );
    cleaned = cleaned.replaceAll('|', ', ');

    cleaned = cleaned.replaceAll(
      RegExp('^[\\s]*[-*+\\u2022]\\s*', multiLine: true),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s]*\d+\.\s*', multiLine: true),
      '',
    );

    cleaned = cleaned.replaceAllMapped(
      RegExp(r'\$(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'),
      (m) => '${m.group(1)} dollars',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp('\u20AC(\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?)'),
      (m) => '${m.group(1)} euros',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp('\u00A3(\\d{1,3}(?:,\\d{3})*(?:\\.\\d{2})?)'),
      (m) => '${m.group(1)} pounds',
    );

    cleaned = cleaned.replaceAll(
      RegExp('[\$\u20AC\u00A3\u00A5\u20B9](?!\\d)'),
      ' ',
    );
    cleaned = cleaned.replaceAll(RegExp(r'[#@&\\<>{}\[\]^~]'), ' ');

    cleaned = cleaned.replaceAll('--', ', ');
    cleaned = cleaned.replaceAll('\u2014', ', ');
    cleaned = cleaned.replaceAll('\u2013', ', ');
    cleaned = cleaned.replaceAll(' - ', ', ');
    cleaned = cleaned.replaceAll(' & ', ' and ');
    cleaned = cleaned.replaceAll(' + ', ' plus ');
    cleaned = cleaned.replaceAll(' = ', ' equals ');
    cleaned = cleaned.replaceAll(' -> ', ' to ');
    cleaned = cleaned.replaceAll(' => ', ' results in ');
    cleaned = cleaned.replaceAll(' / ', ' or ');
    cleaned = cleaned.replaceAll(' % ', ' percent ');
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(?<=[A-Za-z0-9])/(?=[A-Za-z0-9])'),
      (_) => ' or ',
    );
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'(\d+)%'),
      (m) => '${m.group(1)} percent',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        r'^\s*(?:note|warning|important|tip|fyi|heads up)\s*[:\-]\s+',
        caseSensitive: false,
        multiLine: true,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'^\s*(?:[^\x00-\x7F]{1,8}\s*)+(?=[A-Za-z0-9])', multiLine: true),
      '',
    );

    cleaned = cleaned.replaceAll(
      RegExp(r'^[\s\W_]{3,}$', multiLine: true),
      ' ',
    );
    cleaned = cleaned.replaceAll(
      RegExp(
        '[\u2022\u25AA\u25E6\u25CF\u25CB\u25A0\u25A1\u25C6\u25C7\u25B6'
        '\u25BA\u2713\u2714\u2717\u2718\u203B\u00A9\u00AE\u2122\u00A7'
        '\u00B6\u2020\u2021\u00A4\u00A2]',
      ),
      ' ',
    );

    cleaned = cleaned.replaceAll(RegExp(r'[!]{2,}'), '!');
    cleaned = cleaned.replaceAll(RegExp(r'[?]{2,}'), '?');
    cleaned = cleaned.replaceAll(RegExp(r'[.]{3,}'), '...');
    cleaned = cleaned.replaceAll(RegExp(r',{2,}'), ',');
    cleaned = cleaned.replaceAll(
      RegExp(r'[\u{1F300}-\u{1F9FF}]', unicode: true),
      ' ',
    );

    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    cleaned = cleaned.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r' *([,.;!?]) *'), r'$1 ');
    cleaned = cleaned.replaceAll(RegExp(r' *\n *'), '\n');

    return cleaned.trim();
  }

  static String _normalizeTtsArtifacts(String text) {
    String cleaned = text;

    const replacements = <String, String>{
      '\u00A0': ' ',
      '\u200B': ' ',
      '\u200C': ' ',
      '\u200D': ' ',
      '\u2060': ' ',
      '\uFE0F': ' ',
      '\u00C2': ' ',
      '\u00E2\u20AC\u2122': '\'',
      '\u00E2\u20AC\u02DC': '\'',
      '\u00E2\u20AC\u0153': '"',
      '\u00E2\u20AC\u009D': '"',
      '\u00E2\u20AC\u00A6': '...',
      '\u00E2\u20AC\u0094': ', ',
      '\u00E2\u20AC\u0093': ', ',
      '\u00E2\u20AC\u00A2': ' ',
      '\u00E2\u0161\u00A0\u00EF\u00B8\u008F': ' ',
    };

    replacements.forEach((pattern, replacement) {
      cleaned = cleaned.replaceAll(pattern, replacement);
    });

    return cleaned;
  }

  Future<void> speak(String text,
      {double speed = 1.0, bool interrupt = false}) async {
    try {
      // Sanitize text for professional TTS output
      final cleanedText = sanitizeNarrationText(text);

      // Skip empty text
      if (cleanedText.trim().isEmpty) {
        debugPrint('TTS: Skipping empty text');
        return;
      }

      // Interrupt previous speech if requested
      if (interrupt) {
        await stopSpeaking();
      }

      final prefs = await SharedPreferences.getInstance();

      if (_currentProvider == TtsProvider.google) {
        // Use Google TTS (native, free)
        // With awaitSpeakCompletion(true), this should wait for speech to complete
        final voiceName = prefs.getString('google_tts_voice');
        await _googleTtsService.speak(cleanedText,
            voiceName: voiceName, speechRate: speed * 0.5);
        // Wait for TTS to complete - flutter_tts with awaitSpeakCompletion should handle this
        // but we add a completer-based wait for reliability
        await _waitForGoogleTtsCompletion();
      } else if (_currentProvider == TtsProvider.googleCloud) {
        // Use Google Cloud TTS (Paid API)
        if (!interrupt) await _audioPlayer.stop(); // Ensure minimal state reset

        final voiceId = prefs.getString('google_cloud_tts_voice');
        final audioBytes = await _googleCloudTtsService.synthesize(
          cleanedText,
          voiceId: voiceId ?? 'en-US-Journey-F',
          speed: speed,
        );

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/tts_cloud_temp.mp3');
        await tempFile.writeAsBytes(audioBytes);

        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.play();

        // Wait for audio playback to complete
        await _waitForAudioCompletion();
      } else if (_currentProvider == TtsProvider.murf) {
        // Use Murf.ai (Studio quality)
        if (!interrupt) await _audioPlayer.stop();

        final voiceId = prefs.getString('tts_murf_voice');
        final audioBytes = await _murfService.generateSpeech(
          cleanedText,
          voiceId: voiceId ?? 'en-US-natalie',
        );

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/tts_murf_temp.mp3');
        await tempFile.writeAsBytes(audioBytes);

        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.setSpeed(speed);
        await _audioPlayer.play();

        await _waitForAudioCompletion();
      } else {
        // Use ElevenLabs (premium, cloud-based)
        if (!interrupt) await _audioPlayer.stop();

        final voiceId = prefs.getString('tts_voice');
        final modelId = prefs.getString('tts_model');

        final audioBytes = await _elevenLabsService.streamAudio(
          cleanedText,
          voiceId: voiceId ?? 'EXAVITQu4vr4xnSDxMaL',
          model: modelId ?? ElevenLabsService.freeModel,
        );

        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/tts_temp.mp3');
        await tempFile.writeAsBytes(audioBytes);

        await _audioPlayer.setFilePath(tempFile.path);
        await _audioPlayer.setSpeed(speed); // Apply speed control
        await _audioPlayer.play();

        // Wait for audio playback to complete
        await _waitForAudioCompletion();
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
      rethrow;
    }
  }

  /// Wait for just_audio player to complete playback
  Future<void> _waitForAudioCompletion() async {
    try {
      // Listen for playback completion OR stop (idle)
      await _audioPlayer.playerStateStream
          .firstWhere(
            (state) =>
                state.processingState == ProcessingState.completed ||
                state.processingState == ProcessingState.idle,
          )
          .timeout(
            const Duration(minutes: 5),
            onTimeout: () => _audioPlayer.playerState,
          );
    } catch (e) {
      debugPrint('Error waiting for audio completion: $e');
    }
  }

  /// Wait for Google TTS to complete speaking
  Future<void> _waitForGoogleTtsCompletion() async {
    // flutter_tts with awaitSpeakCompletion(true) should block until speech is done
    // Add a small buffer to ensure everything is synced
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<void> stopSpeaking() async {
    await _audioPlayer.stop();
    await _googleTtsService.stop();
  }
}
