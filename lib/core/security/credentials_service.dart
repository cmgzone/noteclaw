import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/custom_auth_service.dart';

final credentialsServiceProvider = Provider<CredentialsService>((ref) {
  return CredentialsService(ref);
});

/// User-specific credentials service using secure storage
class CredentialsService {
  final Ref ref;
  static const _storage = FlutterSecureStorage();

  CredentialsService(this.ref);

  // Generate encryption key from user ID
  encrypt.Key _getEncryptionKey(String userId) {
    final hash =
        sha256.convert(utf8.encode('${userId}notebook_llm_secret_salt'));
    return encrypt.Key(Uint8List.fromList(hash.bytes));
  }

  // Encrypt API key
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
      final combined = base64Decode(encryptedValue);

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

  bool _looksLikeEncryptedBlob(String value) {
    final trimmed = value.trim();
    if (trimmed.length < 48 || trimmed.length % 4 != 0) {
      return false;
    }

    final base64Pattern = RegExp(r'^[A-Za-z0-9+/=]+$');
    if (!base64Pattern.hasMatch(trimmed)) {
      return false;
    }

    try {
      final decoded = base64Decode(trimmed);
      return decoded.length >= 32;
    } catch (_) {
      return false;
    }
  }

  // Store encrypted API key in secure storage
  Future<void> storeApiKey({
    required String service,
    required String apiKey,
  }) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) throw Exception('User not logged in');

    final userId = user.uid;
    final encryptedKey = _encryptValue(apiKey, userId);
    await _storage.write(key: 'user_${userId}_$service', value: encryptedKey);
  }

  // Retrieve and decrypt API key from secure storage
  Future<String?> getApiKey(String service) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) return null;

    final userId = user.uid;
    final stored = await _storage.read(key: 'user_${userId}_$service');
    if (stored == null || stored.isEmpty) return null;

    final decrypted = _decryptValue(stored, userId).trim();
    if (decrypted.isEmpty) {
      return null;
    }

    if (decrypted == stored && _looksLikeEncryptedBlob(stored)) {
      return null;
    }

    return decrypted;
  }

  // Delete API key
  Future<void> deleteApiKey(String service) async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) return;

    final userId = user.uid;
    await _storage.delete(key: 'user_${userId}_$service');
  }

  // List all stored services for user
  Future<List<String>> listServices() async {
    final authState = ref.read(customAuthStateProvider);
    final user = authState.user;
    if (user == null) return [];

    // FlutterSecureStorage doesn't have a list method, so we check known services
    final services = <String>[];
    final knownServices = [
      'gemini',
      'openrouter',
      'elevenlabs',
      'serper',
      'murf'
    ];

    final userId = user.uid;
    for (final service in knownServices) {
      final stored = await _storage.read(key: 'user_${userId}_$service');
      if (stored != null && stored.isNotEmpty) {
        services.add(service);
      }
    }

    return services;
  }
}
