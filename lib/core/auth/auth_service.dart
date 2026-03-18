import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:noteclaw/core/api/api_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref.read(apiServiceProvider));
});

final currentUserProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

final isAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});

class AuthService {
  final ApiService _apiService;

  AuthService(this._apiService);

  /// Sign up a new user
  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final response = await _apiService.signup(
        email: email,
        password: password,
        displayName: displayName,
      );

      if (response['success'] == true && response['user'] != null) {
        return response['user'];
      } else {
        throw Exception('Signup failed');
      }
    } catch (e) {
      throw Exception('Signup error: $e');
    }
  }

  /// Login existing user
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final response = await _apiService.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (response['success'] == true && response['user'] != null) {
        return response['user'];
      } else {
        throw Exception('Login failed');
      }
    } catch (e) {
      throw Exception('Login error: $e');
    }
  }

  /// Get current user from backend
  Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final response = await _apiService.getCurrentUser(clearTokenOn401: false);

      if (response['success'] == true && response['user'] != null) {
        return response['user'];
      } else {
        throw Exception('Failed to get user info');
      }
    } catch (e) {
      throw Exception('Get user error: $e');
    }
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return false;

      // Try to get current user to verify token is valid
      await _apiService.getCurrentUser(clearTokenOn401: false);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Logout user
  Future<void> logout() async {
    await _apiService.clearTokens();
  }

  /// Initialize auth state
  Future<Map<String, dynamic>?> initializeAuth() async {
    try {
      final token = await _apiService.getToken();
      if (token == null) return null;

      return await getCurrentUser();
    } catch (e) {
      // Don't clear token on error - could be temporary network issue
      // Let the user stay logged in with cached data
      return null;
    }
  }
}
