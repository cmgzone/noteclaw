import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../security/credentials_service.dart';

// Custom exception for insufficient credits
class InsufficientCreditsException implements Exception {
  final String message;
  final int required;
  final int available;

  InsufficientCreditsException({
    required this.message,
    required this.required,
    required this.available,
  });

  @override
  String toString() => message;
}

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService(ref);
});

class ApiService {
  final Ref ref;
  static const String _defaultApiBaseUrl = 'https://noteclaw.onrender.com/api/';
  static const Duration _defaultChatTimeout = Duration(seconds: 120);

  static String _normalizeBaseUrl(String url) {
    final trimmed = url.trim();
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }

  static String _resolveBaseUrl() {
    final envUrl = dotenv.env['API_BASE_URL'];
    if (envUrl != null && envUrl.trim().isNotEmpty) {
      return _normalizeBaseUrl(envUrl);
    }

    // Default to the hosted backend so debug builds also work on physical
    // devices. Local development can still override this via API_BASE_URL.
    return _defaultApiBaseUrl;
  }

  String get baseUrl => _dio.options.baseUrl;
  static const String _tokenKey = 'auth_token';
  static const String _refreshTokenKey = 'refresh_token';
  static const String _tokenBackupKey = 'auth_token_backup';
  static const String _refreshTokenBackupKey = 'refresh_token_backup';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  late final Dio _dio;
  String? _token;
  String? _refreshToken;
  Completer<bool>? _refreshCompleter;

  ApiService(this.ref) {
    final resolvedBaseUrl = _resolveBaseUrl();
    developer.log('[API] Using base URL: $resolvedBaseUrl',
        name: 'ApiService');
    _dio = Dio(BaseOptions(
      baseUrl: resolvedBaseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 60),
      responseType: ResponseType.json,
    ));
    _setupInterceptors();
  }

  void _setupInterceptors() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        developer.log('[API] ${options.method} ${options.path}',
            name: 'ApiService');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        developer.log(
            '[API] Response ${response.statusCode} for ${response.requestOptions.path}',
            name: 'ApiService');
        return handler.next(response);
      },
      onError: (DioException e, handler) async {
        developer.log(
            '[API] Error ${e.type} for ${e.requestOptions.path}: ${e.message} (Status: ${e.response?.statusCode})',
            name: 'ApiService');

        // Handle 401 Unauthorized - attempt token refresh
        if (e.response?.statusCode == 401 &&
            !e.requestOptions.path.contains('/auth/refresh') &&
            !e.requestOptions.path.contains('/auth/login')) {
          final refreshToken = await getRefreshToken();
          bool refreshed = false;
          if (refreshToken != null) {
            final currentCompleter = _refreshCompleter;
            if (currentCompleter != null) {
              refreshed = await currentCompleter.future;
            } else {
              final newCompleter = Completer<bool>();
              _refreshCompleter = newCompleter;
              try {
                developer.log(
                    '[API] Access token expired, attempting refresh...',
                    name: 'ApiService');
                refreshed = await refreshAccessToken();
                newCompleter.complete(refreshed);
              } catch (refreshError) {
                newCompleter.complete(false);
                developer.log('[API] Token refresh failed: $refreshError',
                    name: 'ApiService');
              } finally {
                _refreshCompleter = null;
              }
            }

            if (refreshed) {
              final newToken = await getToken();
              final options = e.requestOptions;
              options.headers['Authorization'] = 'Bearer $newToken';

              final response = await _dio.fetch(options);
              return handler.resolve(response);
            }
          }

          if ((e.requestOptions.extra['clearTokenOn401'] ?? true) &&
              !refreshed) {
            await clearTokens();
          }
        }

        return handler.next(e);
      },
    ));
  }

  // ============ TOKEN MANAGEMENT ============

  Future<String?> getToken() async {
    if (_token != null) return _token;
    try {
      final storedToken = await _storage.read(key: _tokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        _token = storedToken;
        return _token;
      }
      final prefs = await SharedPreferences.getInstance();
      final backupToken = prefs.getString(_tokenBackupKey);
      if (backupToken != null && backupToken.isNotEmpty) {
        _token = backupToken;
        try {
          await _storage.write(key: _tokenKey, value: backupToken);
        } catch (_) {}
        return _token;
      }
    } catch (e) {
      developer.log('[API] Error getting token: $e', name: 'ApiService');
    }
    return null;
  }

  Future<String?> getRefreshToken() async {
    if (_refreshToken != null) return _refreshToken;
    try {
      final storedToken = await _storage.read(key: _refreshTokenKey);
      if (storedToken != null && storedToken.isNotEmpty) {
        _refreshToken = storedToken;
        return _refreshToken;
      }
      final prefs = await SharedPreferences.getInstance();
      final backupToken = prefs.getString(_refreshTokenBackupKey);
      if (backupToken != null && backupToken.isNotEmpty) {
        _refreshToken = backupToken;
        try {
          await _storage.write(key: _refreshTokenKey, value: backupToken);
        } catch (_) {}
        return _refreshToken;
      }
    } catch (e) {
      developer.log('[API] Error getting refresh token: $e',
          name: 'ApiService');
    }
    return null;
  }

  Future<void> setTokens(String accessToken, String refreshToken) async {
    _token = accessToken;
    _refreshToken = refreshToken;
    try {
      await _storage.write(key: _tokenKey, value: accessToken);
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenBackupKey, accessToken);
      await prefs.setString(_refreshTokenBackupKey, refreshToken);
    } catch (e) {
      developer.log('[API] Error storing tokens: $e', name: 'ApiService');
    }
  }

  Future<void> clearTokens() async {
    _token = null;
    _refreshToken = null;
    try {
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenBackupKey);
      await prefs.remove(_refreshTokenBackupKey);
    } catch (e) {
      developer.log('[API] Error clearing tokens: $e', name: 'ApiService');
    }
  }

  Future<bool> refreshAccessToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return false;

      final response = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
        options: Options(extra: {'clearTokenOn401': false}),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final newAccessToken = response.data['accessToken'];
        if (newAccessToken != null) {
          _token = newAccessToken;
          await _storage.write(key: _tokenKey, value: newAccessToken);
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(_tokenBackupKey, newAccessToken);
          developer.log('[API] Access token refreshed successfully',
              name: 'ApiService');
          return true;
        }
      }
    } catch (e) {
      if (e is DioException) {
        // Only clear tokens if refresh token is invalid/expired
        final status = e.response?.statusCode;
        if (status == 401) {
          developer.log('[API] Refresh token invalid/expired. Clearing tokens.',
              name: 'ApiService');
          await clearTokens();
        } else if (_isConnectionError(e) ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout) {
          developer.log(
              '[API] Network error during refresh – will keep tokens and retry later',
              name: 'ApiService');
        } else {
          developer.log('[API] Unexpected refresh error: ${e.message}',
              name: 'ApiService');
        }
      } else {
        developer.log('[API] Non-network refresh error: $e',
            name: 'ApiService');
      }
    }
    return false;
  }

  // ============ GENERIC METHODS ============

  Future<T> get<T>(String endpoint,
      {Map<String, dynamic>? queryParameters,
      Options? options,
      int retries = 2}) async {
    try {
      final response = await _dio.get(_normalizeEndpoint(endpoint),
          queryParameters: queryParameters, options: options);
      return _handleResponse<T>(response);
    } catch (e) {
      if (retries > 0 && _isConnectionError(e)) {
        developer.log(
            '[API] Connection error for $endpoint, retrying... ($retries retries left)',
            name: 'ApiService');
        await Future.delayed(const Duration(seconds: 1));
        return get<T>(endpoint,
            queryParameters: queryParameters,
            options: options,
            retries: retries - 1);
      }
      throw _handleError(e);
    }
  }

  bool _isConnectionError(dynamic error) {
    return error is DioException &&
        (error.type == DioExceptionType.connectionError ||
            error.type == DioExceptionType.connectionTimeout ||
            error.type == DioExceptionType.receiveTimeout ||
            error.type == DioExceptionType.sendTimeout);
  }

  String _normalizeEndpoint(String endpoint) {
    return endpoint.startsWith('/') ? endpoint.substring(1) : endpoint;
  }

  Future<T> post<T>(String endpoint, dynamic data, {Options? options}) async {
    try {
      final response = await _dio.post(_normalizeEndpoint(endpoint),
          data: data, options: options);
      return _handleResponse<T>(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Like [post] but allows overriding the receive/send timeouts for
  /// long-running requests such as source ingestion.
  Future<T> postWithTimeout<T>(
    String endpoint,
    dynamic data, {
    Options? options,
    Duration receiveTimeout = const Duration(seconds: 60),
    Duration sendTimeout = const Duration(seconds: 60),
  }) async {
    try {
      final requestOptions = options?.copyWith(
            receiveTimeout: receiveTimeout,
            sendTimeout: sendTimeout,
          ) ??
          Options(
            receiveTimeout: receiveTimeout,
            sendTimeout: sendTimeout,
          );
      final response = await _dio.post(_normalizeEndpoint(endpoint),
          data: data, options: requestOptions);
      return _handleResponse<T>(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> put<T>(String endpoint, dynamic data, {Options? options}) async {
    try {
      final response = await _dio.put(_normalizeEndpoint(endpoint),
          data: data, options: options);
      return _handleResponse<T>(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> patch<T>(String endpoint, dynamic data, {Options? options}) async {
    try {
      final response = await _dio.patch(_normalizeEndpoint(endpoint),
          data: data, options: options);
      return _handleResponse<T>(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<T> delete<T>(String endpoint, {dynamic data, Options? options}) async {
    try {
      final response = await _dio.delete(_normalizeEndpoint(endpoint),
          data: data, options: options);
      return _handleResponse<T>(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  T _handleResponse<T>(Response response) {
    if (response.data is Map<String, dynamic>) {
      return response.data as T;
    } else if (response.data is List) {
      return {'items': response.data} as T;
    }
    return response.data as T;
  }

  Exception _handleError(dynamic error) {
    if (error is DioException) {
      if (error.response?.data is Map<String, dynamic>) {
        final body = error.response?.data as Map<String, dynamic>;
        final message = body['message'] ?? body['error'] ?? 'Unknown error';
        return Exception(message);
      }
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return Exception('Connection timed out.');
        case DioExceptionType.connectionError:
          return Exception('No internet connection.');
        default:
          return Exception('Network error: ${error.message}');
      }
    }
    return Exception('Unexpected error: $error');
  }

  // ============ AUTH ============

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final response = await post<Map<String, dynamic>>('/auth/signup', {
      'email': email,
      'password': password,
      if (displayName != null) 'displayName': displayName,
    });
    if (response['accessToken'] != null && response['refreshToken'] != null) {
      await setTokens(response['accessToken'], response['refreshToken']);
    } else if (response['token'] != null) {
      // Fallback for old API response format
      await setTokens(response['token'], response['refreshToken'] ?? '');
    }
    return response;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    final response = await post<Map<String, dynamic>>('/auth/login', {
      'email': email,
      'password': password,
      'rememberMe': rememberMe,
    });
    if (response['accessToken'] != null && response['refreshToken'] != null) {
      await setTokens(response['accessToken'], response['refreshToken']);
    } else if (response['token'] != null) {
      // Fallback for old API response format
      await setTokens(response['token'], response['refreshToken'] ?? '');
    }
    return response;
  }

  Future<Map<String, dynamic>> getCurrentUser(
      {bool clearTokenOn401 = true}) async {
    return await get<Map<String, dynamic>>('/auth/me',
        options: Options(extra: {'clearTokenOn401': clearTokenOn401}));
  }

  Future<void> requestPasswordReset(String email) async {
    await post('/auth/forgot-password', {'email': email});
  }

  Future<void> resetPassword(String token, String newPassword) async {
    await post('/auth/reset-password', {
      'token': token,
      'newPassword': newPassword,
    });
  }

  Future<void> deleteAccount(String password) async {
    await post('/auth/delete-account', {'password': password});
  }

  Future<void> updateProfile(
      {String? displayName, String? avatarUrl, String? coverUrl}) async {
    await put('/auth/profile', {
      if (displayName != null) 'displayName': displayName,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
      if (coverUrl != null) 'coverUrl': coverUrl,
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await post('/auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> verifyTwoFactor(String code) async {
    await post('/auth/2fa/verify', {'code': code});
  }

  Future<void> enableTwoFactor() async {
    await post('/auth/2fa/enable', {});
  }

  Future<void> disableTwoFactor(String password) async {
    await post('/auth/2fa/disable', {'password': password});
  }

  Future<void> resendTwoFactorCode(String userId) async {
    await post('/auth/2fa/resend', {'userId': userId});
  }

  Future<void> resendVerification() async {
    await post('/auth/verify/resend', {});
  }

  Future<void> verifyEmail(String token) async {
    await post('/auth/verify', {'token': token});
  }

  // ============ API TOKENS ============

  Future<List<Map<String, dynamic>>> listApiTokens() async {
    final response = await get<Map<String, dynamic>>('/auth/tokens');
    return List<Map<String, dynamic>>.from(response['tokens'] ?? []);
  }

  Future<Map<String, dynamic>> generateApiToken({
    required String name,
    DateTime? expiresAt,
  }) async {
    return await post<Map<String, dynamic>>('/auth/tokens', {
      'name': name,
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
    });
  }

  Future<void> revokeApiToken(String tokenId) async {
    await delete('/auth/tokens/$tokenId');
  }

  Future<Map<String, dynamic>> getMcpStats() async {
    return await get<Map<String, dynamic>>('/auth/mcp/stats');
  }

  Future<List<Map<String, dynamic>>> getMcpUsage({int limit = 20}) async {
    final response = await get<Map<String, dynamic>>(
      '/auth/mcp/usage',
      queryParameters: {'limit': limit},
    );
    return List<Map<String, dynamic>>.from(response['usage'] ?? []);
  }

  // ============ NOTEBOOKS ============

  Future<List<Map<String, dynamic>>> getNotebooks() async {
    final response = await get<Map<String, dynamic>>('/notebooks');
    return List<Map<String, dynamic>>.from(response['notebooks'] ?? []);
  }

  Future<Map<String, dynamic>> getNotebook(String id) async {
    final response = await get<Map<String, dynamic>>('/notebooks/$id');
    return response['notebook'];
  }

  Future<Map<String, dynamic>> createNotebook({
    required String title,
    String? description,
    String? coverImage,
    String? category,
  }) async {
    final response = await post<Map<String, dynamic>>('/notebooks', {
      'title': title,
      if (description != null) 'description': description,
      if (coverImage != null) 'coverImage': coverImage,
      if (category != null) 'category': category,
    });
    return response['notebook'];
  }

  Future<Map<String, dynamic>> updateNotebook(
    String id, {
    String? title,
    String? description,
    String? coverImage,
    String? category,
  }) async {
    final response = await put<Map<String, dynamic>>('/notebooks/$id', {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (coverImage != null) 'coverImage': coverImage,
      if (category != null) 'category': category,
    });
    return response['notebook'];
  }

  Future<void> deleteNotebook(String id) async {
    await delete('/notebooks/$id');
  }

  Future<Map<String, dynamic>> getNotebookAnalytics(String notebookId) async {
    return await get<Map<String, dynamic>>('/notebooks/$notebookId/analytics');
  }

  // ============ AGENTS ============

  Future<List<Map<String, dynamic>>> getAgentNotebooks() async {
    final response = await get<Map<String, dynamic>>('/coding-agent/notebooks');
    return List<Map<String, dynamic>>.from(response['notebooks'] ?? []);
  }

  Future<void> disconnectAgent(String sessionId) async {
    await post('/coding-agent/sessions/$sessionId/disconnect', {});
  }

  Future<List<Map<String, dynamic>>> getAgentMemories() async {
    final response =
        await get<Map<String, dynamic>>('/coding-agent/memory/sessions');
    return List<Map<String, dynamic>>.from(response['agents'] ?? []);
  }

  Future<Map<String, dynamic>> getAgentMemory({
    String? agentSessionId,
    String? agentIdentifier,
    String namespace = 'default',
  }) async {
    if ((agentSessionId == null || agentSessionId.isEmpty) &&
        (agentIdentifier == null || agentIdentifier.isEmpty)) {
      throw Exception(
          'getAgentMemory requires agentSessionId or agentIdentifier');
    }

    final params = <String, String>{
      'namespace': namespace,
      if (agentSessionId != null && agentSessionId.isNotEmpty)
        'agentSessionId': agentSessionId,
      if (agentIdentifier != null && agentIdentifier.isNotEmpty)
        'agentIdentifier': agentIdentifier,
    };

    final query = Uri(queryParameters: params).query;
    return await get<Map<String, dynamic>>('/coding-agent/memory?$query');
  }

  // ============ SOURCES ============

  Future<List<Map<String, dynamic>>> getSourcesForNotebook(
      String notebookId) async {
    final response =
        await get<Map<String, dynamic>>('/sources/notebook/$notebookId');
    return List<Map<String, dynamic>>.from(response['sources'] ?? []);
  }

  Future<Map<String, dynamic>> getSource(String id) async {
    final response = await get<Map<String, dynamic>>('/sources/$id');
    return response['source'];
  }

  Future<Map<String, dynamic>> createSource({
    required String notebookId,
    required String type,
    required String title,
    String? content,
    String? url,
    String? imageUrl,
  }) async {
    final response = await post<Map<String, dynamic>>('/sources', {
      'notebookId': notebookId,
      'type': type,
      'title': title,
      if (content != null) 'content': content,
      if (url != null) 'url': url,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
    return response['source'];
  }

  Future<Map<String, dynamic>> updateSource(
    String id, {
    String? title,
    String? content,
    String? url,
  }) async {
    final response = await put<Map<String, dynamic>>('/sources/$id', {
      if (title != null) 'title': title,
      if (content != null) 'content': content,
      if (url != null) 'url': url,
    });
    return response['source'];
  }

  Future<void> deleteSource(String id) async {
    await delete('/sources/$id');
  }

  Future<List<Map<String, dynamic>>> searchSources(String query,
      {int limit = 20}) async {
    final response = await post<Map<String, dynamic>>('/sources/search', {
      'query': query,
      'limit': limit,
    });
    return List<Map<String, dynamic>>.from(response['sources'] ?? []);
  }

  Future<int> bulkDeleteSources(List<String> ids) async {
    final response =
        await post<Map<String, dynamic>>('/sources/bulk/delete', {'ids': ids});
    return response['count'] as int? ?? 0;
  }

  Future<int> bulkMoveSources(List<String> ids, String targetNotebookId) async {
    final response = await post<Map<String, dynamic>>('/sources/bulk/move', {
      'ids': ids,
      'targetNotebookId': targetNotebookId,
    });
    return response['count'] as int? ?? 0;
  }

  Future<bool> sourceHasChunks(String sourceId) async {
    final token = await getToken();
    if (token == null) return false;
    try {
      final response =
          await get<Map<String, dynamic>>('/chunks/source/$sourceId');
      final chunks = response['chunks'] as List?;
      return chunks != null && chunks.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRelatedSources(String sourceId) async {
    final response =
        await get<Map<String, dynamic>>('/sources/$sourceId/related');
    return List<Map<String, dynamic>>.from(response['sources'] ?? []);
  }

  // ============ SOURCE CONVERSATIONS ============

  Future<Map<String, dynamic>> getSourceConversation(String sourceId) async {
    return await get<Map<String, dynamic>>(
        '/coding-agent/conversations/$sourceId');
  }

  Future<Map<String, dynamic>> sendFollowupMessage(
    String sourceId,
    String message, {
    Map<String, dynamic>? githubContext,
    List<Map<String, dynamic>>? imageAttachments,
  }) async {
    return await post<Map<String, dynamic>>('/coding-agent/followups/send', {
      'sourceId': sourceId,
      'message': message,
      if (githubContext != null) 'githubContext': githubContext,
      if (imageAttachments != null && imageAttachments.isNotEmpty)
        'imageAttachments': imageAttachments,
    });
  }

  // ============ TAGS ============

  Future<List<Map<String, dynamic>>> getTags() async {
    final response = await get<Map<String, dynamic>>('/tags');
    return List<Map<String, dynamic>>.from(response['tags'] ?? []);
  }

  Future<Map<String, dynamic>> createTag({
    required String name,
    required String color,
  }) async {
    final response = await post<Map<String, dynamic>>('/tags', {
      'name': name,
      'color': color,
    });
    return response['tag'];
  }

  Future<void> deleteTag(String id) async {
    await delete('/tags/$id');
  }

  Future<void> addTagToSource(String sourceId, String tagId) async {
    await post('/sources/$sourceId/tags', {'tagId': tagId});
  }

  Future<void> removeTagFromSource(String sourceId, String tagId) async {
    await delete('/sources/$sourceId/tags/$tagId');
  }

  Future<List<Map<String, dynamic>>> getPopularTags({int limit = 10}) async {
    final response = await get<Map<String, dynamic>>('/tags/popular',
        queryParameters: {'limit': limit});
    return List<Map<String, dynamic>>.from(response['tags'] ?? []);
  }

  Future<int> bulkAddTagsToSources(
      List<String> sourceIds, List<String> tagIds) async {
    final response = await post<Map<String, dynamic>>(
        '/tags/bulk/add', {'sourceIds': sourceIds, 'tagIds': tagIds});
    return response['count'] as int? ?? 0;
  }

  Future<int> bulkRemoveTagsFromSources(
      List<String> sourceIds, List<String> tagIds) async {
    final response = await post<Map<String, dynamic>>(
        '/tags/bulk/remove', {'sourceIds': sourceIds, 'tagIds': tagIds});
    return response['count'] as int? ?? 0;
  }

  // ============ CHUNKS ============

  Future<List<Map<String, dynamic>>> getChunksForSource(String sourceId) async {
    final response =
        await get<Map<String, dynamic>>('/chunks/source/$sourceId');
    return List<Map<String, dynamic>>.from(response['chunks'] ?? []);
  }

  Future<void> createChunksBulk(
      String sourceId, List<Map<String, dynamic>> chunks) async {
    await post('/chunks/bulk', {'sourceId': sourceId, 'chunks': chunks});
  }

  // ============ CHAT ============

  Future<List<Map<String, dynamic>>> getChatHistory(
      {String? notebookId}) async {
    final path = notebookId != null
        ? '/ai/chat/history?notebookId=$notebookId'
        : '/ai/chat/history';
    final response = await get<Map<String, dynamic>>(path);
    return List<Map<String, dynamic>>.from(response['messages'] ?? []);
  }

  Future<Map<String, dynamic>> saveChatMessage({
    String? notebookId,
    required String role,
    required String content,
    Map<String, dynamic>? metadata,
  }) async {
    return await post<Map<String, dynamic>>('/ai/chat/message', {
      'notebookId': notebookId,
      'role': role,
      'content': content,
      if (metadata != null) 'metadata': metadata,
    });
  }

  // ============ AI ============

  Future<String?> _getByokKeyForProvider(
      {required String provider, String? model}) async {
    try {
      // Prefer model-derived provider when available.
      final normalizedModel = (model ?? '').trim().toLowerCase();
      final normalizedProvider = provider.trim().toLowerCase();

      final service = (() {
        if (normalizedModel.startsWith('gemini')) return 'gemini';
        if (normalizedModel.contains('/') ||
            normalizedModel.startsWith('gpt-') ||
            normalizedModel.startsWith('claude-') ||
            normalizedModel.startsWith('meta-')) {
          return 'openrouter';
        }

        if (normalizedProvider == 'openrouter' ||
            normalizedProvider == 'openai' ||
            normalizedProvider == 'anthropic') {
          return 'openrouter';
        }

        return 'gemini';
      })();

      final creds = ref.read(credentialsServiceProvider);
      final key = await creds.getApiKey(service);
      final trimmed = (key ?? '').trim();
      return trimmed.isEmpty ? null : trimmed;
    } catch (_) {
      return null;
    }
  }

  Future<String> chatWithAI({
    required List<Map<String, dynamic>> messages,
    String provider = 'gemini',
    String? model,
    Duration receiveTimeout = _defaultChatTimeout,
    Duration sendTimeout = _defaultChatTimeout,
  }) async {
    final byokKey =
        await _getByokKeyForProvider(provider: provider, model: model);
    final response = await postWithTimeout<Map<String, dynamic>>(
      '/ai/chat',
      {
        'messages': messages,
        'provider': provider,
        if (model != null) 'model': model,
      },
      receiveTimeout: receiveTimeout,
      sendTimeout: sendTimeout,
      options: byokKey != null
          ? Options(headers: {'X-User-Api-Key': byokKey})
          : null,
    );
    return response['response'];
  }

  Future<String> chatWithVision({
    required List<Map<String, dynamic>> messages,
    required String imageBase64,
    String? provider,
    String? model,
  }) async {
    final byokKey = provider != null
        ? await _getByokKeyForProvider(provider: provider, model: model)
        : null;
    final response = await post<Map<String, dynamic>>(
      '/ai/vision',
      {
        'messages': messages,
        'imageBase64': imageBase64,
        if (provider != null) 'provider': provider,
        if (model != null) 'model': model,
      },
      options: byokKey != null
          ? Options(headers: {'X-User-Api-Key': byokKey})
          : null,
    );
    return response['response'];
  }

  Stream<String> chatWithAIStream({
    required List<Map<String, dynamic>> messages,
    String provider = 'gemini',
    String? model,
    bool useDeepSearch = false,
    bool hasImage = false,
  }) async* {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');
    try {
      final byokKey =
          await _getByokKeyForProvider(provider: provider, model: model);
      final response = await _dio.post(
        _normalizeEndpoint('/ai/chat/stream'),
        data: {
          'messages': messages,
          'provider': provider,
          if (model != null) 'model': model,
          'useDeepSearch': useDeepSearch,
        },
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: _defaultChatTimeout,
          sendTimeout: _defaultChatTimeout,
          extra: {'clearTokenOn401': false},
          headers: {
            'Accept': 'text/event-stream',
            'Cache-Control': 'no-cache',
            'Connection': 'keep-alive',
            if (byokKey != null) 'X-User-Api-Key': byokKey,
          },
        ),
      );
      final rawStream = response.data.stream;
      String buffer = '';

      if (rawStream is Stream<Uint8List>) {
        await for (final chunk in rawStream) {
          final text = utf8.decode(chunk, allowMalformed: true);
          buffer += text;
          final lines = buffer.split('\n');
          buffer = lines.last;
          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();
              if (data == '[DONE]') return;
              if (data.startsWith('{')) {
                Map<String, dynamic> json;
                try {
                  json = jsonDecode(data);
                } catch (_) {
                  yield data;
                  continue;
                }
                final err = json['error'];
                if (err != null && err.toString().isNotEmpty) {
                  throw Exception(err.toString());
                }
                final content = json['content'] ?? json['text'];
                if (content != null && content.toString().isNotEmpty) {
                  yield content.toString();
                }
              } else {
                yield data;
              }
            }
          }
        }
      } else if (rawStream is Stream<List<int>>) {
        await for (final bytes in rawStream) {
          final text = utf8.decode(bytes, allowMalformed: true);
          buffer += text;
          final lines = buffer.split('\n');
          buffer = lines.last;
          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();
              if (data == '[DONE]') return;
              if (data.startsWith('{')) {
                Map<String, dynamic> json;
                try {
                  json = jsonDecode(data);
                } catch (_) {
                  yield data;
                  continue;
                }
                final err = json['error'];
                if (err != null && err.toString().isNotEmpty) {
                  throw Exception(err.toString());
                }
                final content = json['content'] ?? json['text'];
                if (content != null && content.toString().isNotEmpty) {
                  yield content.toString();
                }
              } else {
                yield data;
              }
            }
          }
        }
      } else if (rawStream is Stream<String>) {
        await for (final chunk in rawStream) {
          buffer += chunk;
          final lines = buffer.split('\n');
          buffer = lines.last;
          for (int i = 0; i < lines.length - 1; i++) {
            final line = lines[i].trim();
            if (line.isEmpty) continue;
            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();
              if (data == '[DONE]') return;
              if (data.startsWith('{')) {
                Map<String, dynamic> json;
                try {
                  json = jsonDecode(data);
                } catch (_) {
                  yield data;
                  continue;
                }
                final err = json['error'];
                if (err != null && err.toString().isNotEmpty) {
                  throw Exception(err.toString());
                }
                final content = json['content'] ?? json['text'];
                if (content != null && content.toString().isNotEmpty) {
                  yield content.toString();
                }
              } else {
                yield data;
              }
            }
          }
        }
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  Stream<Map<String, dynamic>> performDeepResearchStream({
    required String query,
    String? notebookId,
    required String depth,
    required String template,
    bool? includeImages,
    bool useNotebookContext = false,
    String? provider,
    String? model,
  }) async* {
    final token = await getToken();
    if (token == null) throw Exception('Not authenticated');
    try {
      final response = await _dio.post(
        _normalizeEndpoint('/research/stream'),
        data: {
          'query': query,
          'depth': depth,
          'template': template,
          if (notebookId != null && notebookId.isNotEmpty)
            'notebookId': notebookId,
          if (includeImages != null) 'includeImages': includeImages,
          'useNotebookContext': useNotebookContext,
          if (provider != null && provider.isNotEmpty) 'provider': provider,
          if (model != null && model.isNotEmpty) 'model': model,
        },
        options: Options(
          responseType: ResponseType.stream,
          headers: {'Accept': 'text/event-stream'},
        ),
      );

      // Get the response stream
      final responseStream = response.data.stream as Stream<Uint8List>;

      // Buffer to accumulate incomplete lines
      String buffer = '';

      await for (final chunk in responseStream) {
        // Decode bytes to string
        final text = utf8.decode(chunk, allowMalformed: true);
        buffer += text;

        // Process complete lines
        final lines = buffer.split('\n');
        buffer = lines.last; // Keep incomplete line in buffer

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;

          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') break;

            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              yield json;
            } catch (e) {
              debugPrint('[ApiService] Error decoding research event: $e');
              debugPrint('[ApiService] Data: $data');
            }
          }
        }
      }
    } catch (e) {
      throw _handleError(e);
    }
  }

  // ============ AI MODELS ============

  Future<List<Map<String, dynamic>>> getAIModels() async {
    final response = await get<Map<String, dynamic>>('/ai/models');
    return List<Map<String, dynamic>>.from(response['models'] ?? []);
  }

  Future<Map<String, dynamic>> getDefaultAIModel() async {
    final response = await get<Map<String, dynamic>>('/ai/models/default');
    return Map<String, dynamic>.from(response['model'] ?? {});
  }

  Future<Map<String, dynamic>> addAIModel(Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/ai/models', data);
  }

  Future<Map<String, dynamic>> updateAIModel(
      String id, Map<String, dynamic> data) async {
    return await put<Map<String, dynamic>>('/ai/models/$id', data);
  }

  Future<void> deleteAIModel(String id) async {
    await delete('/ai/models/$id');
  }

  Future<List<Map<String, dynamic>>> getPersonalAIModels() async {
    final response = await get<Map<String, dynamic>>('/ai/models/personal');
    return List<Map<String, dynamic>>.from(response['models'] ?? []);
  }

  Future<Map<String, dynamic>> addPersonalAIModel(
      Map<String, dynamic> data) async {
    final response =
        await post<Map<String, dynamic>>('/ai/models/personal', data);
    return Map<String, dynamic>.from(response['model'] ?? {});
  }

  Future<Map<String, dynamic>> updatePersonalAIModel(
      String id, Map<String, dynamic> data) async {
    final response =
        await put<Map<String, dynamic>>('/ai/models/personal/$id', data);
    return Map<String, dynamic>.from(response['model'] ?? {});
  }

  Future<void> deletePersonalAIModel(String id) async {
    await delete('/ai/models/personal/$id');
  }

  // ============ SEARCH PROXY ============

  Future<Map<String, dynamic>> searchProxy(
    String query, {
    int limit = 10,
    String? type,
    int? num,
    int? page,
  }) async {
    return await post<Map<String, dynamic>>('/search/proxy', {
      'query': query,
      'limit': limit,
      if (type != null) 'type': type,
      if (num != null) 'num': num,
      if (page != null) 'page': page,
    });
  }

  // ============ VOICE MODELS ============

  Future<List<Map<String, dynamic>>> getVoiceModels() async {
    final response = await get<Map<String, dynamic>>('/voice/models');
    return List<Map<String, dynamic>>.from(response['models'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getVoiceModelsByProvider(
      String provider) async {
    final response = await get<Map<String, dynamic>>('/voice/models/$provider');
    return List<Map<String, dynamic>>.from(response['models'] ?? []);
  }

  // ============ AUDIO OVERVIEWS ============

  Future<List<Map<String, dynamic>>> getAudioOverviews() async {
    final response =
        await get<Map<String, dynamic>>('/features/audio/overviews');
    return List<Map<String, dynamic>>.from(response['overviews'] ?? []);
  }

  Future<Map<String, dynamic>> saveAudioOverview(
      Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/features/audio/overviews', data);
  }

  Future<void> deleteAudioOverview(String id) async {
    await delete('/features/audio/overviews/$id');
  }

  // ============ MEDIA ============

  Future<Uint8List?> getMediaBytes(String sourceId) async {
    try {
      final response = await _dio.get(
        _normalizeEndpoint('/media/$sourceId'),
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>> uploadMediaDirect({
    required String base64Data,
    required String filename,
    String? type,
  }) async {
    return await post<Map<String, dynamic>>('/media/upload-direct', {
      'mediaData': base64Data,
      'filename': filename,
      if (type != null) 'type': type,
    });
  }

  Future<int> getMediaSizeStats() async {
    final response = await get<Map<String, dynamic>>('/media/stats');
    return response['totalSize'] as int? ?? 0;
  }

  // ============ SUBSCRIPTIONS ============

  Future<Map<String, dynamic>?> getSubscription() async {
    try {
      final response = await get<Map<String, dynamic>>('/subscriptions/me');
      return response['subscription'];
    } catch (e) {
      if (e.toString().contains('404')) return null;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getCreditPackages() async {
    final response = await get<Map<String, dynamic>>('/subscriptions/packages');
    return List<Map<String, dynamic>>.from(response['packages'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getTransactionHistory(
      {int limit = 50}) async {
    final response = await get<Map<String, dynamic>>(
        '/subscriptions/transactions',
        queryParameters: {'limit': limit});
    return List<Map<String, dynamic>>.from(response['transactions'] ?? []);
  }

  Future<Map<String, dynamic>> consumeCredits({
    required int amount,
    required String feature,
    Map<String, dynamic>? metadata,
  }) async {
    return await post<Map<String, dynamic>>('/subscriptions/consume', {
      'amount': amount,
      'feature': feature,
      if (metadata != null) 'metadata': metadata,
    });
  }

  Future<Map<String, dynamic>> getCreditBalance() async {
    return await get<Map<String, dynamic>>('/subscriptions/credits');
  }

  Future<Map<String, dynamic>> addCredits({
    required int amount,
    required String packageId,
    required String transactionId,
    String paymentMethod = 'paypal',
  }) async {
    return await post<Map<String, dynamic>>('/subscriptions/add-credits', {
      'amount': amount,
      'packageId': packageId,
      'transactionId': transactionId,
      'paymentMethod': paymentMethod,
    });
  }

  Future<Map<String, dynamic>> createStripePaymentIntent({
    String? packageId,
    double? amount,
    String currency = 'USD',
    String? description,
  }) async {
    return await post<Map<String, dynamic>>(
      '/subscriptions/create-payment-intent',
      {
        if (packageId != null) 'packageId': packageId,
        if (amount != null) 'amount': amount,
        'currency': currency,
        if (description != null) 'description': description,
      },
    );
  }

  Future<List<Map<String, dynamic>>> getAdminPlans() async {
    final response = await get<Map<String, dynamic>>('/subscriptions/plans');
    return List<Map<String, dynamic>>.from(response['plans'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getSubscriptionPlans() async {
    final response = await get<Map<String, dynamic>>('/subscriptions/plans');
    return List<Map<String, dynamic>>.from(response['plans'] ?? []);
  }

  Future<void> createSubscription() async {
    await post('/subscriptions/create', {});
  }

  Future<Map<String, dynamic>> upgradePlan({
    required String planId,
    required String transactionId,
  }) async {
    return await post<Map<String, dynamic>>('/subscriptions/upgrade', {
      'planId': planId,
      'transactionId': transactionId,
    });
  }

  // ============ SHARING ============

  Future<Map<String, dynamic>> createShareToken(
    String notebookId, {
    String? accessLevel,
    DateTime? expiresAt,
    int? expiresInDays,
  }) async {
    return await post<Map<String, dynamic>>('/sharing/create', {
      'notebookId': notebookId,
      if (accessLevel != null) 'accessLevel': accessLevel,
      if (expiresAt != null) 'expiresAt': expiresAt.toIso8601String(),
      if (expiresInDays != null) 'expiresInDays': expiresInDays,
    });
  }

  Future<Map<String, dynamic>> validateShareToken(String token) async {
    return await get<Map<String, dynamic>>('/sharing/validate/$token');
  }

  Future<List<Map<String, dynamic>>> listShares(String notebookId) async {
    final response =
        await get<Map<String, dynamic>>('/sharing/notebook/$notebookId');
    return List<Map<String, dynamic>>.from(response['shares'] ?? []);
  }

  Future<bool> revokeShare(String notebookId, String token) async {
    final response = await post<Map<String, dynamic>>('/sharing/revoke', {
      'notebookId': notebookId,
      'token': token,
    });
    return response['success'] as bool? ?? false;
  }

  // ============ GAMIFICATION ============

  Future<Map<String, dynamic>> getGamificationStats() async {
    return await get<Map<String, dynamic>>('/gamification/stats');
  }

  Future<Map<String, dynamic>> getUserStats() async {
    return await get<Map<String, dynamic>>('/gamification/user-stats');
  }

  Future<List<Map<String, dynamic>>> getAchievements() async {
    final response =
        await get<Map<String, dynamic>>('/gamification/achievements');
    return List<Map<String, dynamic>>.from(response['achievements'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getDailyChallenges() async {
    final response =
        await get<Map<String, dynamic>>('/gamification/challenges');
    return List<Map<String, dynamic>>.from(response['challenges'] ?? []);
  }

  Future<Map<String, dynamic>> trackActivity({
    required String type,
    String? field,
    dynamic value,
    int? xpEarned,
    int? increment,
    Map<String, dynamic>? metadata,
  }) async {
    return await post<Map<String, dynamic>>('/gamification/track', {
      'type': type,
      if (field != null) 'field': field,
      if (value != null) 'value': value,
      if (xpEarned != null) 'xpEarned': xpEarned,
      if (increment != null) 'increment': increment,
      if (metadata != null) 'metadata': metadata,
    });
  }

  Future<void> updateAchievementProgress({
    required String achievementId,
    required int value,
    bool isUnlocked = false,
  }) async {
    await post('/gamification/achievements/progress', {
      'achievementId': achievementId,
      'value': value,
      'isUnlocked': isUnlocked,
    });
  }

  Future<void> batchUpdateChallenges(List<Map<String, dynamic>> updates) async {
    await post('/gamification/challenges/batch', {'updates': updates});
  }

  // ============ FLASHCARDS ============

  Future<List<Map<String, dynamic>>> getFlashcardDecks() async {
    final response = await get<Map<String, dynamic>>('/study/flashcards/decks');
    return List<Map<String, dynamic>>.from(response['decks'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getFlashcardsForDeck(String deckId) async {
    final response =
        await get<Map<String, dynamic>>('/study/flashcards/decks/$deckId');
    return List<Map<String, dynamic>>.from(response['flashcards'] ?? []);
  }

  Future<Map<String, dynamic>> createFlashcardDeck({
    required String title,
    required String notebookId,
    String? sourceId,
    List<Map<String, dynamic>>? cards,
  }) async {
    final data = {
      'title': title,
      'notebookId': notebookId,
      if (sourceId != null) 'sourceId': sourceId,
      if (cards != null) 'cards': cards,
    };
    final response =
        await post<Map<String, dynamic>>('/study/flashcards/decks', data);
    return response['deck'] ?? response;
  }

  Future<void> deleteFlashcardDeck(String deckId) async {
    await delete('/study/flashcards/decks/$deckId');
  }

  Future<void> updateFlashcardProgress({
    required String cardId,
    required bool wasCorrect,
  }) async {
    await post(
        '/study/flashcards/$cardId/progress', {'wasCorrect': wasCorrect});
  }

  // ============ QUIZZES ============

  Future<List<Map<String, dynamic>>> getQuizzes() async {
    final response = await get<Map<String, dynamic>>('/study/quizzes');
    return List<Map<String, dynamic>>.from(response['quizzes'] ?? []);
  }

  Future<Map<String, dynamic>> createQuiz({
    required String title,
    required String notebookId,
    String? sourceId,
    List<Map<String, dynamic>>? questions,
  }) async {
    final data = {
      'title': title,
      'notebookId': notebookId,
      if (sourceId != null) 'sourceId': sourceId,
      if (questions != null) 'questions': questions,
    };
    return await post<Map<String, dynamic>>('/study/quizzes', data);
  }

  Future<void> deleteQuiz(String quizId) async {
    await delete('/study/quizzes/$quizId');
  }

  Future<void> recordQuizAttempt(
      {required String quizId, required int score, required int total}) async {
    await post(
        '/study/quizzes/$quizId/attempt', {'score': score, 'total': total});
  }

  // ============ MIND MAPS ============

  Future<List<Map<String, dynamic>>> getMindMaps() async {
    final response = await get<Map<String, dynamic>>('/study/mindmaps');
    return List<Map<String, dynamic>>.from(response['mindMaps'] ?? []);
  }

  Future<Map<String, dynamic>> saveMindMap({
    String? id,
    required String title,
    required String notebookId,
    String? sourceId,
    required Map<String, dynamic> rootNode,
    String? textContent,
  }) async {
    final data = {
      if (id != null) 'id': id,
      'title': title,
      'notebookId': notebookId,
      if (sourceId != null) 'sourceId': sourceId,
      'rootNode': rootNode,
      if (textContent != null) 'textContent': textContent,
    };
    return await post<Map<String, dynamic>>('/study/mindmaps', data);
  }

  // ============ INFOGRAPHICS ============

  Future<List<Map<String, dynamic>>> getInfographics() async {
    final response = await get<Map<String, dynamic>>('/study/infographics');
    return List<Map<String, dynamic>>.from(response['infographics'] ?? []);
  }

  Future<Map<String, dynamic>> saveInfographic({
    required String title,
    required String notebookId,
    String? sourceId,
    String? imageUrl,
    String? imageBase64,
    String? style,
  }) async {
    final data = {
      'title': title,
      'notebookId': notebookId,
      if (sourceId != null) 'sourceId': sourceId,
      if (imageUrl != null) 'imageUrl': imageUrl,
      if (imageBase64 != null) 'imageBase64': imageBase64,
      if (style != null) 'style': style,
    };
    return await post<Map<String, dynamic>>('/study/infographics', data);
  }

  // ============ TUTOR SESSIONS ============

  Future<List<Map<String, dynamic>>> getTutorSessions() async {
    final response = await get<Map<String, dynamic>>('/study/tutor/sessions');
    return List<Map<String, dynamic>>.from(response['sessions'] ?? []);
  }

  Future<Map<String, dynamic>> createTutorSession(
      Map<String, dynamic> data) async {
    final response =
        await post<Map<String, dynamic>>('/study/tutor/sessions', data);
    return response['session'];
  }

  Future<void> deleteTutorSession(String id) async {
    await delete('/study/tutor/sessions/$id');
  }

  // ============ EBOOKS ============

  Future<List<Map<String, dynamic>>> getEbookProjects() async {
    final response = await get<Map<String, dynamic>>('/ebooks');
    return List<Map<String, dynamic>>.from(response['projects'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getEbookChapters(String projectId) async {
    final response =
        await get<Map<String, dynamic>>('/ebooks/$projectId/chapters');
    return List<Map<String, dynamic>>.from(response['chapters'] ?? []);
  }

  Future<Map<String, dynamic>> saveEbookProject({
    String? id,
    required String title,
    required String topic,
    String? targetAudience,
    Map<String, dynamic>? branding,
    String? selectedModel,
    String? notebookId,
    String? status,
    String? coverImage,
  }) async {
    final data = {
      if (id != null && id.isNotEmpty) 'id': id,
      'title': title,
      'topic': topic,
      if (targetAudience != null) 'targetAudience': targetAudience,
      if (branding != null) 'branding': branding,
      if (selectedModel != null) 'selectedModel': selectedModel,
      if (notebookId != null && notebookId.isNotEmpty) 'notebookId': notebookId,
      if (status != null && status.isNotEmpty) 'status': status,
      if (coverImage != null && coverImage.isNotEmpty) 'coverImage': coverImage,
    };
    return await post<Map<String, dynamic>>('/ebooks', data);
  }

  Future<void> syncEbookChapters({
    required String projectId,
    required List<Map<String, dynamic>> chapters,
  }) async {
    await post('/ebooks/$projectId/chapters/batch', {'chapters': chapters});
  }

  Future<void> deleteEbookProject(String projectId) async {
    await delete('/ebooks/$projectId');
  }

  // ============ STORIES ============

  Future<List<Map<String, dynamic>>> getStories() async {
    final response = await get<Map<String, dynamic>>('/stories');
    return List<Map<String, dynamic>>.from(response['stories'] ?? []);
  }

  Future<Map<String, dynamic>> createStory(Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/stories', data);
  }

  Future<void> deleteStory(String storyId) async {
    await delete('/stories/$storyId');
  }

  // ============ LANGUAGE LEARNING ============

  Future<List<Map<String, dynamic>>> getLanguageSessions() async {
    final response = await get<Map<String, dynamic>>('/language/sessions');
    return List<Map<String, dynamic>>.from(response['sessions'] ?? []);
  }

  Future<Map<String, dynamic>> createLanguageSession(
      Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/language/sessions', data);
  }

  Future<void> deleteLanguageSession(String sessionId) async {
    await delete('/language/sessions/$sessionId');
  }

  // ============ MEAL PLANNER ============

  Future<List<Map<String, dynamic>>> getMealPlans() async {
    final response = await get<Map<String, dynamic>>('/meals/plans');
    return List<Map<String, dynamic>>.from(response['plans'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getSavedMeals() async {
    final response = await get<Map<String, dynamic>>('/meals/saved');
    return List<Map<String, dynamic>>.from(response['meals'] ?? []);
  }

  Future<Map<String, dynamic>> saveMealPlan(Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/meals/plans', data);
  }

  Future<Map<String, dynamic>> saveMeal(Map<String, dynamic> data) async {
    return await post<Map<String, dynamic>>('/meals/saved', data);
  }

  Future<void> deleteSavedMeal(String mealId) async {
    await delete('/meals/saved/$mealId');
  }

  // ============ AGENT SKILLS ============

  Future<List<Map<String, dynamic>>> getAgentSkills() async {
    final response = await get<Map<String, dynamic>>('/agent-skills');
    return List<Map<String, dynamic>>.from(response['skills'] ?? []);
  }

  Future<Map<String, dynamic>> createAgentSkill({
    required String name,
    required String content,
    String? description,
    Map<String, dynamic>? parameters,
  }) async {
    final data = {
      'name': name,
      'content': content,
      if (description != null) 'description': description,
      if (parameters != null) 'parameters': parameters,
    };
    return await post<Map<String, dynamic>>('/agent-skills', data);
  }

  Future<Map<String, dynamic>> updateAgentSkill(
    String id, {
    String? name,
    String? content,
    String? description,
    Map<String, dynamic>? parameters,
    bool? isActive,
  }) async {
    final data = {
      if (name != null) 'name': name,
      if (content != null) 'content': content,
      if (description != null) 'description': description,
      if (parameters != null) 'parameters': parameters,
      if (isActive != null) 'isActive': isActive,
    };
    return await put<Map<String, dynamic>>('/agent-skills/$id', data);
  }

  Future<void> deleteAgentSkill(String id) async {
    await delete('/agent-skills/$id');
  }

  Future<List<Map<String, dynamic>>> getAgentSkillsCatalog({
    String? query,
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await get<Map<String, dynamic>>(
      '/agent-skills/catalog',
      queryParameters: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'limit': limit,
        'offset': offset,
      },
    );
    return List<Map<String, dynamic>>.from(response['catalog'] ?? []);
  }

  Future<Map<String, dynamic>> installAgentSkillFromCatalog(
    String catalogId, {
    String? nameOverride,
  }) async {
    final data = <String, dynamic>{
      if (nameOverride != null && nameOverride.trim().isNotEmpty)
        'name': nameOverride.trim(),
    };
    return await post<Map<String, dynamic>>(
      '/agent-skills/install/$catalogId',
      data,
    );
  }

  // ============ ONBOARDING ============

  Future<List<Map<String, dynamic>>> getOnboardingScreens() async {
    final response = await get<Map<String, dynamic>>('/admin/onboarding');
    return List<Map<String, dynamic>>.from(response['screens'] ?? []);
  }

  // ============ PRIVACY POLICY ============

  Future<String> getPrivacyPolicy() async {
    final response = await get<Map<String, dynamic>>('/auth/privacy-policy');
    return response['content'] as String? ?? '';
  }
}
