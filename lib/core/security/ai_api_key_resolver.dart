import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credentials_service.dart';
import 'global_credentials_service.dart';

final aiApiKeyResolverProvider = Provider<AIApiKeyResolver>((ref) {
  return AIApiKeyResolver(ref);
});

enum AIApiKeySource {
  user,
  app,
  none,
}

class ResolvedAIApiKey {
  const ResolvedAIApiKey({
    required this.service,
    required this.source,
    this.apiKey,
  });

  final String service;
  final AIApiKeySource source;
  final String? apiKey;

  bool get hasKey => (apiKey ?? '').trim().isNotEmpty;

  String get sourceLabel {
    switch (source) {
      case AIApiKeySource.user:
        return 'Your API key';
      case AIApiKeySource.app:
        return 'App API key';
      case AIApiKeySource.none:
        return 'No API key';
    }
  }
}

class AIApiKeyResolver {
  AIApiKeyResolver(this.ref);

  final Ref ref;

  Future<ResolvedAIApiKey> resolveForProvider(String provider) async {
    final service = provider.trim().toLowerCase() == 'openrouter'
        ? 'openrouter'
        : 'gemini';
    return resolveForService(service);
  }

  Future<ResolvedAIApiKey> resolveForService(String service) async {
    final normalizedService = service.trim().toLowerCase();
    final userCredentials = ref.read(credentialsServiceProvider);
    final userKey =
        (await userCredentials.getApiKey(normalizedService) ?? '').trim();
    if (userKey.isNotEmpty) {
      return ResolvedAIApiKey(
        service: normalizedService,
        source: AIApiKeySource.user,
        apiKey: userKey,
      );
    }

    final globalCredentials = ref.read(globalCredentialsServiceProvider);
    final appKey =
        (await globalCredentials.getApiKey(normalizedService) ?? '').trim();
    if (appKey.isNotEmpty) {
      return ResolvedAIApiKey(
        service: normalizedService,
        source: AIApiKeySource.app,
        apiKey: appKey,
      );
    }

    return ResolvedAIApiKey(
      service: normalizedService,
      source: AIApiKeySource.none,
    );
  }
}
