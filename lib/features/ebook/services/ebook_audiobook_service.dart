import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/security/ai_api_key_resolver.dart';
import '../models/ebook_project.dart';

class EbookAudiobookService {
  final Ref ref;

  EbookAudiobookService(this.ref);

  Future<List<String>> generateAudiobook(EbookProject project) async {
    final resolvedKey =
        await ref.read(aiApiKeyResolverProvider).resolveForService('elevenlabs');
    final apiKey = (resolvedKey.apiKey ?? '').trim();
    if (apiKey.isEmpty) {
      throw Exception('ElevenLabs API key not found');
    }

    // Stub implementation - TTS will be implemented in future iteration
    // For now, return empty list as audiobook generation is a planned feature
    List<String> audioUrls = [];

    for (var _ in project.chapters) {
      audioUrls.add(''); // Placeholder
    }

    return audioUrls;
  }
}

final ebookAudiobookServiceProvider =
    Provider<EbookAudiobookService>((ref) => EbookAudiobookService(ref));
