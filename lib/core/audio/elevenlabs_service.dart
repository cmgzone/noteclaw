import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'elevenlabs_config_secure.dart';
import '../services/overlay_bubble_service.dart';

// Provider for ElevenLabs service
final elevenLabsServiceProvider = Provider<ElevenLabsService>((ref) {
  return ElevenLabsService(ref);
});

class ElevenLabsService {
  final Ref ref;

  ElevenLabsService(this.ref);

  Future<String> get apiKey async {
    // Always fetch fresh to allow key updates during session
    final config = ref.read(elevenLabsConfigSecureProvider);
    return await config.getApiKey();
  }

  static const String baseUrl = ElevenLabsConfigSecure.baseUrl;
  static const String freeModel = ElevenLabsConfigSecure.freeModel;
  static const Map<String, String> voices = ElevenLabsConfigSecure.voices;
  static const Map<String, String> models = ElevenLabsConfigSecure.models;

  // Fallback models in order of preference
  static const List<String> _fallbackModels = [
    'eleven_multilingual_v2',
    'eleven_flash_v2_5',
    'eleven_turbo_v2_5',
    'eleven_turbo_v2',
    'eleven_flash_v2',
  ];

  Future<Uint8List> textToSpeech(
    String text, {
    String voiceId = 'EXAVITQu4vr4xnSDxMaL',
    String model = freeModel,
    double stability = 0.35,
    double similarityBoost = 0.8,
  }) async {
    final showBubble = text.length > 100;

    try {
      if (showBubble) {
        await overlayBubbleService.show(status: 'Generating Audio...');
      }

      final key = await apiKey;
      if (key.isEmpty) {
        throw Exception(
            'Missing ElevenLabs API key. Save your own key in Settings or configure an app key.');
      }

      if (showBubble) {
        await overlayBubbleService.updateStatus('Synthesizing voice...',
            progress: 30);
      }

      // Try the requested model first, then fallbacks
      final modelsToTry = [model, ..._fallbackModels.where((m) => m != model)];
      String? lastErrorBody;
      int? lastStatusCode;

      for (final tryModel in modelsToTry) {
        debugPrint('[ElevenLabs] Trying TTS with model: $tryModel');
        debugPrint('[ElevenLabs] - Voice ID: $voiceId');
        debugPrint('[ElevenLabs] - Text length: ${text.length} chars');

        final response = await http.post(
          Uri.parse('$baseUrl/text-to-speech/$voiceId'),
          headers: {
            'Content-Type': 'application/json',
            'xi-api-key': key,
          },
          body: jsonEncode({
            'text': text,
            'model_id': tryModel,
            'voice_settings': {
              'stability': stability,
              'similarity_boost': similarityBoost,
              'use_speaker_boost': true,
            }
          }),
        );

        debugPrint('[ElevenLabs] Response status: ${response.statusCode}');

        if (response.statusCode == 200) {
          if (showBubble) {
            await overlayBubbleService.updateStatus('Audio Ready! 🔊',
                progress: 100);
            await Future.delayed(const Duration(seconds: 1));
            await overlayBubbleService.hide();
          }
          return response.bodyBytes;
        } else {
          lastStatusCode = response.statusCode;
          lastErrorBody = response.body;
          debugPrint(
              '[ElevenLabs] Model $tryModel failed: ${response.statusCode} ${response.body}');
          // Try next model
          continue;
        }
      }

      // All models failed
      throw Exception(
        'All ElevenLabs models failed'
        '${lastStatusCode != null ? ' ($lastStatusCode)' : ''}'
        '${lastErrorBody != null && lastErrorBody.isNotEmpty ? ': $lastErrorBody' : '. Check your API key and quota.'}',
      );
    } catch (e) {
      if (showBubble) {
        await overlayBubbleService.updateStatus('Error: Audio Failed');
        await Future.delayed(const Duration(seconds: 2));
        await overlayBubbleService.hide();
      }
      throw Exception('Failed to generate speech: $e');
    }
  }

  /// Generate PCM audio that can be concatenated with other PCM chunks
  /// Returns raw PCM data (16-bit signed little-endian, 22050Hz mono)
  static const int pcmSampleRate = 22050;

  Future<Uint8List> textToSpeechPCM(
    String text, {
    String voiceId = 'EXAVITQu4vr4xnSDxMaL',
    String model = freeModel,
    double stability = 0.35,
    double similarityBoost = 0.8,
  }) async {
    final key = await apiKey;
    if (key.isEmpty) {
      throw Exception('Missing ELEVENLABS_API_KEY');
    }

    final modelsToTry = [model, ..._fallbackModels.where((m) => m != model)];
    String? lastErrorBody;
    int? lastStatusCode;

    for (final tryModel in modelsToTry) {
      final response = await http.post(
        Uri.parse('$baseUrl/text-to-speech/$voiceId?output_format=pcm_22050'),
        headers: {
          'Content-Type': 'application/json',
          'xi-api-key': key,
        },
        body: jsonEncode({
          'text': text,
          'model_id': tryModel,
          'voice_settings': {
            'stability': stability,
            'similarity_boost': similarityBoost,
            'use_speaker_boost': true,
          }
        }),
      );

      debugPrint(
          '[ElevenLabs PCM] Model $tryModel response: ${response.statusCode}');

      if (response.statusCode == 200) {
        return response.bodyBytes;
      }

      lastStatusCode = response.statusCode;
      lastErrorBody = response.body;
      debugPrint('[ElevenLabs PCM] Model $tryModel failed: ${response.body}');
    }

    throw Exception(
      'ElevenLabs PCM generation failed'
      '${lastStatusCode != null ? ' ($lastStatusCode)' : ''}'
      '${lastErrorBody != null && lastErrorBody.isNotEmpty ? ': $lastErrorBody' : ''}',
    );
  }

  /// Wrap raw PCM data with a WAV header to create a playable file
  static Uint8List wrapPCMWithWavHeader(Uint8List pcmData,
      {int sampleRate = pcmSampleRate}) {
    final byteRate = sampleRate * 2; // 16-bit mono = 2 bytes per sample
    final dataSize = pcmData.length;
    final fileSize =
        dataSize + 36; // Header is 44 bytes, but we exclude RIFF+size (8 bytes)

    final header = ByteData(44);

    // RIFF header
    header.setUint32(0, 0x46464952, Endian.little); // "RIFF"
    header.setUint32(4, fileSize, Endian.little); // File size - 8
    header.setUint32(8, 0x45564157, Endian.little); // "WAVE"

    // fmt sub-chunk
    header.setUint32(12, 0x20746D66, Endian.little); // "fmt "
    header.setUint32(16, 16, Endian.little); // Sub-chunk size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // Audio format (1 = PCM)
    header.setUint16(22, 1, Endian.little); // Num channels (1 = mono)
    header.setUint32(24, sampleRate, Endian.little); // Sample rate
    header.setUint32(28, byteRate, Endian.little); // Byte rate
    header.setUint16(32, 2, Endian.little); // Block align (2 for 16-bit mono)
    header.setUint16(34, 16, Endian.little); // Bits per sample

    // data sub-chunk
    header.setUint32(36, 0x61746164, Endian.little); // "data"
    header.setUint32(40, dataSize, Endian.little); // Data size

    // Combine header and PCM data
    final result = BytesBuilder();
    result.add(header.buffer.asUint8List());
    result.add(pcmData);

    return result.takeBytes();
  }

  Future<Stream<Uint8List>> textToSpeechStream(
    String text, {
    String voiceId = 'EXAVITQu4vr4xnSDxMaL',
    String model = freeModel,
    double stability = 0.5,
    double similarityBoost = 0.75,
  }) async {
    final key = await apiKey;
    if (key.isEmpty) {
      throw Exception('Missing ELEVENLABS_API_KEY');
    }

    final request = http.Request(
      'POST',
      Uri.parse('$baseUrl/text-to-speech/$voiceId/stream'),
    );

    request.headers.addAll({
      'Content-Type': 'application/json',
      'xi-api-key': key,
    });

    request.body = jsonEncode({
      'text': text,
      'model_id': model,
      'voice_settings': {
        'stability': stability,
        'similarity_boost': similarityBoost,
      }
    });

    final streamedResponse = await request.send();

    if (streamedResponse.statusCode != 200) {
      throw Exception(
          'ElevenLabs streaming failed: ${streamedResponse.statusCode}');
    }

    return streamedResponse.stream.map((bytes) => Uint8List.fromList(bytes));
  }

  Future<List<Map<String, dynamic>>> getAvailableVoices() async {
    try {
      final key = await apiKey;
      if (key.isEmpty) {
        throw Exception('Missing ELEVENLABS_API_KEY');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/voices'),
        headers: {'xi-api-key': key},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['voices']);
      } else {
        throw Exception('Failed to fetch voices');
      }
    } catch (e) {
      // Return default voices if API fails
      return voices.entries
          .map((e) => {'voice_id': e.key, 'name': e.value})
          .toList();
    }
  }

  // Convenience method for voice_service.dart
  Future<Uint8List> streamAudio(
    String text, {
    String voiceId = 'EXAVITQu4vr4xnSDxMaL',
    String model = freeModel,
  }) async {
    return await textToSpeech(text, voiceId: voiceId, model: model);
  }
}
