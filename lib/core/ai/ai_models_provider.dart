import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'ai_model_service.dart';

final availableModelsProvider =
    FutureProvider<Map<String, List<AIModelOption>>>((ref) async {
  final List<AIModelOption> geminiModels = [];
  final List<AIModelOption> openRouterModels = [];
  final List<AIModelOption> alibabaTokenPlanModels = [];

  // Get dynamic models from DB
  try {
    final service = ref.read(aiModelServiceProvider);
    final dbModels = await service.listModels();

    for (final m in dbModels) {
      if (!m.isActive) continue;

      final option = AIModelOption(
        id: m.modelId,
        name: m.name,
        provider: m.provider,
        isPremium: m.isPremium,
        canAccess: m.canAccess,
        contextWindow: m.contextWindow > 0
            ? m.contextWindow
            : _getDefaultContextWindow(m.modelId),
      );

      if (m.provider == 'gemini') {
        geminiModels.add(option);
      } else if (m.provider == 'alibaba_token_plan') {
        alibabaTokenPlanModels.add(option);
      } else if (m.provider == 'openrouter' ||
          m.provider == 'openai' ||
          m.provider == 'anthropic') {
        openRouterModels.add(option);
      }
    }
  } catch (e) {
    debugPrint('Failed to load dynamic AI models: $e');
  }

  return {
    'gemini': geminiModels,
    'openrouter': openRouterModels,
    'alibaba_token_plan': alibabaTokenPlanModels,
  };
});

final selectedAIModelProvider = StateProvider<String>((ref) => '');

final currentAIModelIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('ai_model');
  if (saved != null && saved.isNotEmpty) return saved;

  try {
    final service = ref.read(aiModelServiceProvider);
    final defaultModel = await service.getDefaultModel();
    if (defaultModel != null && defaultModel.modelId.isNotEmpty) {
      return defaultModel.modelId;
    }
  } catch (e, st) {
    assert(() {
      debugPrint('[AIModels] Failed to load default model: $e\n$st');
      return true;
    }());
  }

  // No saved model, pick first active one from DB
  final models = await ref.watch(availableModelsProvider.future);
  final provider = prefs.getString('ai_provider') ?? 'gemini';
  final available = models[provider] ?? [];

  if (available.isNotEmpty) {
    return available.first.id;
  }

  // Last resort: empty string (indicates no models configured)
  return '';
});

/// Get default context window for known models
int _getDefaultContextWindow(String modelId) {
  final lower = modelId.toLowerCase();

  // Gemini models
  if (lower.contains('gemini-2.0') || lower.contains('gemini-2.5')) {
    return 1000000; // 1M tokens
  }
  if (lower.contains('gemini-1.5-pro')) {
    return 2000000; // 2M tokens
  }
  if (lower.contains('gemini-1.5-flash') || lower.contains('gemini-flash')) {
    return 1000000; // 1M tokens
  }
  if (lower.contains('gemini') && lower.contains('exp')) {
    return 1000000; // Experimental Gemini models
  }

  // Google Nano models (lightweight, smaller context)
  if (lower.contains('nano')) {
    return 128000; // 128K tokens - reasonable for nano models
  }

  // OpenRouter / Claude models
  if (lower.contains('claude-3.5')) {
    return 200000; // 200K tokens
  }
  if (lower.contains('claude-3')) {
    return 200000; // 200K tokens
  }
  if (lower.contains('claude')) {
    return 100000; // Older Claude models
  }

  // OpenAI GPT models
  if (lower.contains('gpt-4o')) {
    return 128000; // GPT-4o
  }
  if (lower.contains('gpt-4-turbo')) {
    return 128000; // GPT-4 Turbo
  }
  if (lower.contains('gpt-4')) {
    return 8192; // Standard GPT-4
  }
  if (lower.contains('gpt-3.5-turbo-16k')) {
    return 16000;
  }
  if (lower.contains('gpt-3.5')) {
    return 4096;
  }

  // AWS Nova models
  if (lower.contains('nova')) {
    return 300000; // 300K tokens
  }

  // Mistral models
  if (lower.contains('mistral-large')) {
    return 128000;
  }
  if (lower.contains('mistral')) {
    return 32000;
  }

  // Llama models
  if (lower.contains('llama-3.3') || lower.contains('llama-3.2')) {
    return 128000;
  }
  if (lower.contains('llama-3.1')) {
    return 128000;
  }
  if (lower.contains('llama')) {
    return 8192;
  }

  // Qwen models
  if (lower.contains('qwen')) {
    return 32000;
  }

  // DeepSeek models
  if (lower.contains('deepseek')) {
    return 64000;
  }

  // Default fallback - generous for modern models
  return 32768; // 32K tokens should handle most modern models
}

class AIModelOption {
  final String id;
  final String name;
  final String provider;
  final bool isPremium;
  final bool canAccess; // Whether current user can use this model
  final int contextWindow;

  AIModelOption({
    required this.id,
    required this.name,
    required this.provider,
    required this.isPremium,
    this.canAccess = true,
    this.contextWindow = 8192,
  });
}
