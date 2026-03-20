import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const _fallbackPublicAppUrl = 'https://noteclaw.app';

String buildPublicShareLink(String path) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  final baseUrl = _resolvePublicAppUrl();
  return Uri.parse(baseUrl).resolve(normalizedPath).toString();
}

String _resolvePublicAppUrl() {
  if (kIsWeb) {
    return Uri.base.origin;
  }

  final envUrl =
      dotenv.env['APP_BASE_URL'] ?? dotenv.env['PUBLIC_APP_URL'] ?? '';
  if (envUrl.trim().isNotEmpty) {
    return _normalizeBaseUrl(envUrl);
  }

  return _fallbackPublicAppUrl;
}

String _normalizeBaseUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return _fallbackPublicAppUrl;
  }
  return trimmed.endsWith('/') ? trimmed : '$trimmed/';
}
