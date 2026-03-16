import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/ai/gemini_image_service.dart';
import '../../../core/security/global_credentials_service.dart';
import '../models/ebook_project.dart';
import '../models/ebook_chapter.dart';
import '../../../core/ai/ai_settings_service.dart';

class DesignerAgent {
  final Ref ref;

  DesignerAgent(this.ref);

  Future<GeminiImageService> _getImageService(
      {required String? providerOverride}) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final provider = providerOverride ?? settings.provider;
    final creds = ref.read(globalCredentialsServiceProvider);

    String? apiKey;
    if (provider == 'openrouter') {
      apiKey = await creds.getApiKey('openrouter');
    } else {
      apiKey = await creds.getApiKey('gemini');
    }

    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('API key not found for $provider');
    }
    return GeminiImageService(apiKey: apiKey);
  }

  Future<String> generateCoverArt(EbookProject project) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final imageService =
        await _getImageService(providerOverride: settings.provider);

    final prompt = '''
Book cover design for a book titled "${project.title}".
Topic: ${project.topic}
Style: Professional, modern, minimalist, high quality, 4k.
Primary color: ${project.branding.primaryColorValue.toRadixString(16)}
''';

    return await imageService.generateImage(prompt,
        provider: settings.provider, model: settings.model);
  }

  Future<String> generateChapterIllustration(
      EbookChapter chapter, String style) async {
    final settings = await AISettingsService.getSettingsWithDefault(ref.read);
    final imageService =
        await _getImageService(providerOverride: settings.provider);

    // Safely get content preview
    final contentPreview = chapter.content.isEmpty
        ? chapter.title
        : chapter.content.substring(0, chapter.content.length.clamp(0, 100));

    final prompt = '''
Illustration for a book chapter titled "${chapter.title}".
Context: $contentPreview...
Style: $style, consistent, professional.
''';

    return await imageService.generateImage(prompt,
        provider: settings.provider, model: settings.model);
  }
}

final designerAgentProvider =
    Provider<DesignerAgent>((ref) => DesignerAgent(ref));
