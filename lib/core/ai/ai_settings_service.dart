import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/admin/services/ai_model_service.dart';
import '../security/credentials_service.dart';

typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// Centralized AI settings service - no hardcoded models
/// All model defaults come from user settings or are fetched dynamically
class AISettingsService {
  static const String _providerKey = 'ai_provider';
  static const String _modelKey = 'ai_model';

  static String _normalizeProvider(String provider) {
    if (provider == 'openrouter' ||
        provider == 'openai' ||
        provider == 'anthropic') {
      return 'openrouter';
    }
    return provider;
  }

  /// Get the user's selected AI provider
  static Future<String> getProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_providerKey) ?? 'gemini';
  }

  /// Get the user's selected AI model
  static Future<String?> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_modelKey);
  }

  /// Get the actual provider for a specific model by looking it up in the database
  /// This ensures custom models added via admin panel use the correct service
  static Future<String> getProviderForModel(
      String modelId, ProviderRead read) async {
    try {
      final service = read(aiModelServiceProvider);
      final models = await service.listModels();

      // Find the model in the database
      final model = models.where((m) => m.modelId == modelId).firstOrNull;

      if (model != null) {
        // Map the provider field to the correct service
        // openai, anthropic, and openrouter all use OpenRouterService
        if (model.provider == 'openrouter' ||
            model.provider == 'openai' ||
            model.provider == 'anthropic') {
          return 'openrouter';
        }
        return model.provider; // 'gemini' or other
      }
    } catch (e) {
      // If lookup fails, fall back to SharedPreferences
    }

    // Fallback to SharedPreferences if model not found
    return await getProvider();
  }

  /// Get provider and model together
  static Future<AISettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return AISettings(
      provider: prefs.getString(_providerKey) ?? 'gemini',
      model: prefs.getString(_modelKey),
    );
  }

  static Future<AISettings> getSettingsWithDefault(ProviderRead read) async {
    final prefs = await SharedPreferences.getInstance();
    final modelId = prefs.getString(_modelKey);

    if (modelId != null && modelId.isNotEmpty) {
      final provider = await getProviderForModel(modelId, read);
      return AISettings(
        provider: provider,
        model: modelId,
      );
    }

    try {
      final service = read(aiModelServiceProvider);
      final defaultModel = await service.getDefaultModel();
      if (defaultModel != null && defaultModel.modelId.isNotEmpty) {
        final provider = _normalizeProvider(defaultModel.provider);
        return AISettings(
          provider: provider,
          model: defaultModel.modelId,
        );
      }
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[AISettingsService] Failed to load default model: $e\n$st',
        );
        return true;
      }());
    }

    return AISettings(
      provider: prefs.getString(_providerKey) ?? 'gemini',
      model: null,
    );
  }

  /// Get settings with provider auto-detected from the model
  static Future<AISettings> getSettingsWithProviderDetection(
      ProviderRead read) async {
    final prefs = await SharedPreferences.getInstance();
    final modelId = prefs.getString(_modelKey);

    String provider;
    if (modelId != null && modelId.isNotEmpty) {
      // Auto-detect provider from model
      provider = await getProviderForModel(modelId, read);
    } else {
      // No model selected, use saved provider
      provider = prefs.getString(_providerKey) ?? 'gemini';
    }

    return AISettings(
      provider: provider,
      model: modelId,
    );
  }

  static String _resolveCredentialService({
    required String provider,
    String? modelId,
  }) {
    final normalizedProvider = provider.trim().toLowerCase();
    final normalizedModel = (modelId ?? '').trim().toLowerCase();

    if (normalizedModel.startsWith('gemini')) {
      return 'gemini';
    }

    if (normalizedModel.contains('/') ||
        normalizedModel.startsWith('gpt-') ||
        normalizedModel.startsWith('claude-') ||
        normalizedModel.startsWith('meta-')) {
      return 'openrouter';
    }

    return _normalizeProvider(normalizedProvider);
  }

  static Future<bool> shouldBypassCreditsForSelectedModel(
    ProviderRead read,
  ) async {
    final settings = await getSettingsWithDefault(read);
    return shouldBypassCreditsForModel(
      read,
      provider: settings.provider,
      modelId: settings.model,
    );
  }

  static Future<bool> shouldBypassCreditsForModel(
    ProviderRead read, {
    required String provider,
    String? modelId,
  }) async {
    final credentialService = _resolveCredentialService(
      provider: provider,
      modelId: modelId,
    );

    try {
      final credentials = read(credentialsServiceProvider);
      final apiKey =
          (await credentials.getApiKey(credentialService) ?? '').trim();
      if (apiKey.isNotEmpty) {
        return true;
      }
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[AISettingsService] Failed to read local BYOK credentials: $e\n$st',
        );
        return true;
      }());
    }

    final normalizedModelId = (modelId ?? '').trim();
    if (normalizedModelId.isEmpty) {
      return false;
    }

    try {
      final service = read(aiModelServiceProvider);
      final models = await service.listModels();
      final selectedModel =
          models
              .where((model) => model.modelId == normalizedModelId)
              .firstOrNull;

      return selectedModel?.isUserModel == true ||
          selectedModel?.hasPersonalApiKey == true;
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[AISettingsService] Failed to resolve model billing mode: $e\n$st',
        );
        return true;
      }());
    }

    return false;
  }

  /// Save AI provider
  static Future<void> setProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerKey, provider);
  }

  /// Save AI model
  static Future<void> setModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modelKey, model);
  }

  /// Get the context window for a specific model
  /// Returns a safe max_tokens value (typically 1/4 of context window, capped)
  static Future<int> getMaxTokensForModel(
      String modelId, ProviderRead read) async {
    try {
      final service = read(aiModelServiceProvider);
      final models = await service.listModels();
      final model = models.where((m) => m.modelId == modelId).firstOrNull;

      if (model != null && model.contextWindow > 0) {
        // Use 1/4 of context window for output, capped at reasonable limits
        final contextWindow = model.contextWindow;
        int maxTokens = (contextWindow / 4).floor();

        // Cap based on provider to avoid credit issues
        // Cap max output tokens to reasonable limits to prevent excessive costs/timeouts
        // but allow higher limits if the model supports it (based on context window calculation)
        // Cap max output tokens to reasonable limits (128k)
        // This allows very large context models (like 1M context) to output significant content
        if (maxTokens > 131072) maxTokens = 131072;
        if (maxTokens < 2000) maxTokens = 2000;

        return maxTokens;
      }
    } catch (e) {
      // Fallback on error
    }

    // Default fallback
    return 4000;
  }

  /// Get context window for current model
  static Future<int> getCurrentModelContextWindow(ProviderRead read) async {
    final modelId = await getModel();
    if (modelId == null || modelId.isEmpty) return 32768;

    try {
      final service = read(aiModelServiceProvider);
      final models = await service.listModels();
      final model = models.where((m) => m.modelId == modelId).firstOrNull;

      if (model != null && model.contextWindow > 0) {
        return model.contextWindow;
      }
    } catch (e) {
      // Fallback
    }

    return 32768; // Default fallback
  }

  /// Check if a model supports vision (image input)
  static bool isVisionCapable(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('gemini') ||
        lower.contains('gpt-4') ||
        lower.contains('claude') ||
        lower.contains('vision');
  }

  /// Get a vision-capable model fallback if current model doesn't support it
  static String getVisionModel(String currentModel, String provider) {
    if (isVisionCapable(currentModel)) {
      return currentModel;
    }
    // No hardcoded fallbacks - return current and let service/API handle error
    return currentModel;
  }
}

/// Provider for AI settings
final aiSettingsProvider = FutureProvider<AISettings>((ref) async {
  final settings = await AISettingsService.getSettingsWithDefault(ref.read);
  return AISettings(
    provider: settings.provider,
    model: settings.model,
  );
});

/// Selected AI model state provider (for UI)
final selectedAIModelIdProvider = StateProvider<String?>((ref) => null);

/// Selected AI provider state provider (for UI)
final selectedAIProviderProvider = StateProvider<String>((ref) => 'gemini');

class AISettings {
  final String provider;
  final String? model;

  AISettings({required this.provider, this.model});

  /// Get the effective model (with fallback if none set)
  String getEffectiveModel({String? fallback}) {
    if (model != null && model!.isNotEmpty) {
      return model!;
    }
    if (fallback != null) {
      return fallback;
    }
    // No hardcoded fallback - user must select a model
    throw Exception(
        'No AI model selected. Please configure a model in settings.');
  }
}
