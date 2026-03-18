import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/custom_auth_service.dart';

final globalCredentialsServiceProvider =
    Provider<GlobalCredentialsService>((ref) {
  return GlobalCredentialsService(ref);
});

/// Service for managing global API keys - now uses .env and secure storage
/// API keys are no longer stored in database, they're managed by backend
class GlobalCredentialsService {
  final Ref ref;
  static const _storage = FlutterSecureStorage();

  // Fixed encryption key for global credentials
  static const String _encryptionSecret = 'notebook_llm_global_secret_key_2024';

  GlobalCredentialsService(this.ref);

  // Generate encryption key from fixed secret + user id
  encrypt.Key _getEncryptionKey(String userId) {
    final hash = sha256.convert(utf8.encode('$_encryptionSecret$userId'));
    return encrypt.Key(Uint8List.fromList(hash.bytes));
  }

  // Encrypt API key for local storage
  String _encryptValue(String value, String userId) {
    final key = _getEncryptionKey(userId);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));
    final encrypted = encrypter.encrypt(value, iv: iv);
    return base64Encode(iv.bytes + encrypted.bytes);
  }

  // Decrypt API key
  String _decryptValue(String encryptedValue, String userId) {
    try {
      final key = _getEncryptionKey(userId);

      if (!_isValidBase64(encryptedValue) || encryptedValue.length < 32) {
        return encryptedValue;
      }

      final combined = base64Decode(encryptedValue);
      if (combined.length < 17) {
        return encryptedValue;
      }

      final iv = encrypt.IV(Uint8List.fromList(combined.sublist(0, 16)));
      final encryptedBytes = Uint8List.fromList(combined.sublist(16));

      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted =
          encrypter.decrypt(encrypt.Encrypted(encryptedBytes), iv: iv);

      return decrypted;
    } catch (e) {
      return encryptedValue;
    }
  }

  bool _isValidBase64(String value) {
    try {
      if (value.length % 4 != 0) return false;
      base64Decode(value);
      return true;
    } catch (_) {
      return false;
    }
  }

  // Store encrypted API key in secure storage
  Future<void> storeApiKey({
    required String service,
    required String apiKey,
    String? description,
  }) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) throw Exception('User not logged in');

    final encryptedKey = _encryptValue(apiKey, user.uid);
    await _storage.write(
      key: 'user_${user.uid}_$service',
      value: encryptedKey,
    );
  }

  // Retrieve API key for signed-in user only
  Future<String?> getApiKey(String service) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) return null;

    final stored = await _storage.read(key: 'user_${user.uid}_$service');
    if (stored != null && stored.isNotEmpty) {
      return _decryptValue(stored, user.uid);
    }

    return null;
  }

  // Delete API key from secure storage
  Future<void> deleteApiKey(String service) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) return;
    await _storage.delete(key: 'user_${user.uid}_$service');
  }

  // List all stored services
  Future<List<Map<String, dynamic>>> listServices() async {
    // Return list of known services
    return [
      {'service_name': 'gemini', 'description': 'Gemini API Key'},
      {'service_name': 'openrouter', 'description': 'OpenRouter API Key'},
      {'service_name': 'elevenlabs', 'description': 'ElevenLabs API Key'},
      {'service_name': 'serper', 'description': 'Serper API Key'},
      {'service_name': 'murf', 'description': 'Murf API Key'},
    ];
  }

  // Migrate all API keys from .env to secure storage
  Future<void> migrateFromEnv(Map<String, String> envKeys) async {
    for (final entry in envKeys.entries) {
      if (entry.value.isNotEmpty) {
        await storeApiKey(
          service: entry.key.toLowerCase().replaceAll('_api_key', ''),
          apiKey: entry.value,
          description: '${entry.key} API Key',
        );
      }
    }
  }
}
