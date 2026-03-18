import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;
import 'gemini_config.dart';

class GeminiImageService {
  final String apiKey;

  GeminiImageService({String? apiKey}) : apiKey = apiKey ?? GeminiConfig.apiKey;

  /// Generate an image using Nano Banana API
  Future<String> generateImage(String prompt,
      {String? model, String? provider}) async {
    try {
      if (apiKey.isEmpty) {
        throw Exception('Missing API key.');
      }

      if (provider == 'openrouter') {
        if (model == null || model.isEmpty) {
          throw Exception(
              'No image model selected. Please select an AI model with image generation capabilities in Settings.');
        }
        return _generateImageOpenRouter(prompt, model);
      }

      // Default to placeholder for Gemini until specialized Imagen API is implemented
      // or if using Nano Banana (removing Nano Banana as it appears broken/fake)
      debugPrint(
          '[GeminiImageService] Gemini Image Gen not fully implemented. Using placeholder.');
      return _generatePlaceholderImage(prompt);

      /* 
      // Legacy Nano Banana implementation removed
      */
    } catch (e) {
      debugPrint(
          '[GeminiImageService] Image generation failed: $e. Using placeholder.');
      return _generatePlaceholderImage(prompt);
    }
  }

  /// Generate image using OpenRouter's chat completions with image-capable models
  /// IMPORTANT: Must use models with "image" in output_modalities AND set modalities parameter
  /// Compatible models: google/gemini-2.0-flash-exp:free, google/gemini-2.5-flash-preview, etc.
  Future<String> _generateImageOpenRouter(String prompt, String model) async {
    try {
      // Use the provided model directly (trusting user selection)
      final imageModel = model;

      debugPrint(
          '[GeminiImageService] Generating image with model: $imageModel');

      final response = await http.post(
        Uri.parse('https://openrouter.ai/api/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'HTTP-Referer': 'https://noteclaw.app',
          'X-Title': 'NoteClaw',
        },
        body: jsonEncode({
          'model': imageModel,
          'messages': [
            {
              'role': 'user',
              'content': prompt,
            }
          ],
          // CRITICAL: Must specify modalities to enable image generation
          'modalities': ['image', 'text'],
          // Optional: Configure image output
          'image_config': {
            'aspect_ratio': '1:1',
          },
          'max_tokens': 4096,
        }),
      );

      debugPrint(
          '[GeminiImageService] Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint(
            '[GeminiImageService] Response: ${response.body.substring(0, (response.body.length > 500 ? 500 : response.body.length))}...');

        // Check for images array in the response (OpenRouter format)
        final message = data['choices']?[0]?['message'];
        if (message != null) {
          // Check for images array (new OpenRouter format)
          final images = message['images'] as List?;
          if (images != null && images.isNotEmpty) {
            final imageUrl = images[0]['image_url']?['url'];
            if (imageUrl != null) {
              debugPrint('[GeminiImageService] Found image in images array');
              return imageUrl;
            }
          }

          // Check content for multipart response
          final content = message['content'];
          if (content is List) {
            for (final part in content) {
              if (part['type'] == 'image_url') {
                final url = part['image_url']?['url'];
                if (url != null) {
                  debugPrint(
                      '[GeminiImageService] Found image in content array');
                  return url;
                }
              }
            }
          }

          // Check if content is a string with embedded image data
          if (content is String) {
            // Look for base64 image data
            final base64Regex =
                RegExp(r'data:image/[^;]+;base64,[A-Za-z0-9+/=]+');
            final base64Match = base64Regex.firstMatch(content);
            if (base64Match != null) {
              debugPrint('[GeminiImageService] Found base64 image in content');
              return base64Match.group(0)!;
            }

            // Look for image URLs in the response
            final urlRegex = RegExp(
                r'https?://[^\s\)\"]+\.(png|jpg|jpeg|gif|webp)',
                caseSensitive: false);
            final match = urlRegex.firstMatch(content);
            if (match != null) {
              debugPrint('[GeminiImageService] Found image URL in content');
              return match.group(0)!;
            }
          }
        }

        debugPrint('[GeminiImageService] Model response did not contain image. '
            'Make sure the model supports image generation (has "image" in output_modalities). '
            'Using placeholder.');
        return _generatePlaceholderImage(prompt);
      }

      final errorBody = response.body;
      debugPrint('OpenRouter Image Error: ${response.statusCode} $errorBody');

      // Check for specific errors
      if (errorBody.contains('credits') || errorBody.contains('quota')) {
        throw Exception(
            'OpenRouter credits exhausted. Please add credits to your account.');
      }

      if (errorBody.contains('modalities') ||
          errorBody.contains('not supported')) {
        throw Exception('This model does not support image generation. '
            'Please select a model with image output capability like google/gemini-2.0-flash-exp:free');
      }

      throw Exception('OpenRouter Image Generation failed: $errorBody');
    } catch (e) {
      debugPrint('OpenRouter generation error: $e');
      rethrow;
    }
  }

  /// Analyze an image using Gemini's vision capabilities
  Future<String> analyzeImage(Uint8List imageBytes, String prompt,
      {required String model}) async {
    try {
      if (apiKey.isEmpty) {
        throw Exception('Missing GEMINI_API_KEY');
      }

      final genModel = GenerativeModel(
        model: model,
        apiKey: apiKey,
      );

      final content = [
        Content.multi([
          TextPart(prompt),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await genModel.generateContent(content);
      return response.text ?? 'No analysis available';
    } catch (e) {
      throw Exception('Failed to analyze image: $e');
    }
  }

  /// Generate placeholder image as base64 (simple colored square with text)
  String _generatePlaceholderImage(String prompt) {
    final truncatedPrompt =
        prompt.length > 50 ? '${prompt.substring(0, 50)}...' : prompt;
    final svg = '''
<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">
  <rect width="400" height="400" fill="#9333EA"/>
  <text x="50%" y="50%" font-size="16" fill="white" text-anchor="middle" dominant-baseline="middle">
    $truncatedPrompt
  </text>
</svg>
''';
    final bytes = utf8.encode(svg);
    final base64Svg = base64Encode(bytes);
    return 'data:image/svg+xml;base64,$base64Svg';
  }

  /// Generate an image with custom parameters
  Future<String> generateImageWithOptions({
    required String prompt,
    String aspectRatio = '1:1',
    int sampleCount = 1,
    String safetyLevel = 'block_some',
  }) async {
    return await generateImage(prompt);
  }
}
