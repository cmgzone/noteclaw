import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_service.dart';

// ============================================================================
// ENUMS & CONSTANTS
// ============================================================================

enum AuthStatus { initial, authenticated, unauthenticated, loading, error }

enum TokenType { access, refresh, passwordReset, emailVerification, twoFactor }

class AuthConstants {
  static const int accessTokenExpiryMinutes = 15;
  static const int refreshTokenExpiryDays = 30;
  static const int passwordResetExpiryMinutes = 30;
  static const int emailVerificationExpiryHours = 24;
  static const int twoFactorCodeExpiryMinutes = 5;
  static const int maxLoginAttempts = 5;
  static const int lockoutDurationMinutes = 15;
  static const int minPasswordLength = 8;
  static const int sessionHistoryLimit = 10;
}

// ============================================================================
// MODELS
// ============================================================================

class AppUser {
  final String uid;
  final String email;
  final String? displayName;
  final DateTime createdAt;
  final bool emailVerified;
  final bool twoFactorEnabled;
  final String? avatarUrl;
  final String? coverUrl;

  const AppUser({
    required this.uid,
    required this.email,
    this.displayName,
    required this.createdAt,
    this.emailVerified = false,
    this.twoFactorEnabled = false,
    this.avatarUrl,
    this.coverUrl,
  });

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: (map['id'] ?? map['uid']) as String,
      email: map['email'] as String,
      displayName: (map['displayName'] ?? map['display_name']) as String?,
      createdAt: _parseDateTime(map['createdAt'] ?? map['created_at']),
      emailVerified:
          (map['emailVerified'] ?? map['email_verified']) as bool? ?? false,
      twoFactorEnabled:
          (map['twoFactorEnabled'] ?? map['two_factor_enabled']) as bool? ??
              false,
      avatarUrl: (map['avatarUrl'] ?? map['avatar_url']) as String?,
      coverUrl: (map['coverUrl'] ?? map['cover_url']) as String?,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }

  Map<String, dynamic> toMap() => {
        'id': uid,
        'email': email,
        'display_name': displayName,
        'created_at': createdAt.toIso8601String(),
        'email_verified': emailVerified,
        'two_factor_enabled': twoFactorEnabled,
        'avatar_url': avatarUrl,
        'cover_url': coverUrl,
      };

  AppUser copyWith({
    String? displayName,
    bool? emailVerified,
    bool? twoFactorEnabled,
    String? avatarUrl,
    String? coverUrl,
  }) {
    return AppUser(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt,
      emailVerified: emailVerified ?? this.emailVerified,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverUrl: coverUrl ?? this.coverUrl,
    );
  }
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpiry;
  final DateTime refreshTokenExpiry;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpiry,
    required this.refreshTokenExpiry,
  });

  bool get isAccessTokenExpired => DateTime.now().isAfter(accessTokenExpiry);
  bool get isRefreshTokenExpired => DateTime.now().isAfter(refreshTokenExpiry);

  Map<String, dynamic> toMap() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'access_token_expiry': accessTokenExpiry.toIso8601String(),
        'refresh_token_expiry': refreshTokenExpiry.toIso8601String(),
      };

  factory AuthTokens.fromMap(Map<String, dynamic> map) {
    return AuthTokens(
      accessToken: map['access_token'] as String,
      refreshToken: map['refresh_token'] as String,
      accessTokenExpiry: DateTime.parse(map['access_token_expiry'] as String),
      refreshTokenExpiry: DateTime.parse(map['refresh_token_expiry'] as String),
    );
  }
}

class AuthSession {
  final String sessionId;
  final String userId;
  final String deviceInfo;
  final String? ipAddress;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final bool isCurrent;

  const AuthSession({
    required this.sessionId,
    required this.userId,
    required this.deviceInfo,
    this.ipAddress,
    required this.createdAt,
    required this.lastActiveAt,
    this.isCurrent = false,
  });

  factory AuthSession.fromMap(Map<String, dynamic> map,
      {bool isCurrent = false}) {
    return AuthSession(
      sessionId: map['id'] as String,
      userId: map['user_id'] as String,
      deviceInfo: map['device_info'] as String? ?? 'Unknown',
      ipAddress: map['ip_address'] as String?,
      createdAt: AppUser._parseDateTime(map['created_at']),
      lastActiveAt: AppUser._parseDateTime(map['last_active_at']),
      isCurrent: isCurrent,
    );
  }
}

class AuthState {
  final AuthStatus status;
  final AppUser? user;
  final String? error;
  final bool requiresTwoFactor;
  final String? pendingUserId;
  final String? pendingVerificationEmail;
  final bool verificationEmailSent;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.error,
    this.requiresTwoFactor = false,
    this.pendingUserId,
    this.pendingVerificationEmail,
    this.verificationEmailSent = false,
  });

  bool get isAuthenticated => status == AuthStatus.authenticated;
  bool get isLoading =>
      status == AuthStatus.loading || status == AuthStatus.initial;
  bool get requiresEmailVerification =>
      (pendingVerificationEmail?.isNotEmpty ?? false);

  AuthState copyWith({
    AuthStatus? status,
    AppUser? user,
    String? error,
    bool? requiresTwoFactor,
    String? pendingUserId,
    String? pendingVerificationEmail,
    bool? verificationEmailSent,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: error,
      requiresTwoFactor: requiresTwoFactor ?? this.requiresTwoFactor,
      pendingUserId: pendingUserId ?? this.pendingUserId,
      pendingVerificationEmail:
          pendingVerificationEmail ?? this.pendingVerificationEmail,
      verificationEmailSent:
          verificationEmailSent ?? this.verificationEmailSent,
    );
  }
}

class PasswordStrength {
  final int score; // 0-4
  final String label;
  final List<String> suggestions;

  const PasswordStrength({
    required this.score,
    required this.label,
    required this.suggestions,
  });

  bool get isStrong => score >= 3;
}

class AuditLogEntry {
  final String id;
  final String userId;
  final String action;
  final String? details;
  final String? ipAddress;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.id,
    required this.userId,
    required this.action,
    this.details,
    this.ipAddress,
    required this.timestamp,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      action: map['action'] as String,
      details: map['details'] as String?,
      ipAddress: map['ip_address'] as String?,
      timestamp: AppUser._parseDateTime(map['created_at']),
    );
  }
}

// ============================================================================
// PROVIDERS
// ============================================================================

final customAuthServiceProvider = Provider<CustomAuthService>((ref) {
  return CustomAuthService(ref);
});

final customAuthStateProvider =
    StateNotifierProvider<CustomAuthNotifier, AuthState>((ref) {
  return CustomAuthNotifier(ref);
});

final legacyUserProvider = Provider<AppUser?>((ref) {
  return ref.watch(customAuthStateProvider).user;
});

final legacyIsAuthenticatedProvider = Provider<bool>((ref) {
  return ref.watch(customAuthStateProvider).isAuthenticated;
});

// ============================================================================
// CUSTOM AUTH SERVICE
// ============================================================================

class CustomAuthService {
  final Ref _ref;

  // Secure storage instance - use consistent configuration across the app
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _userDataKey = 'auth_user_data';
  static const _userDataBackupKey =
      'auth_user_data_backup'; // Backup in SharedPreferences

  CustomAuthService(this._ref);

  ApiService get _api => _ref.read(apiServiceProvider);

  // ============================================================================
  // PASSWORD UTILITIES
  // ============================================================================

  PasswordStrength checkPasswordStrength(String password) {
    int score = 0;
    final suggestions = <String>[];

    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (password.length < 8) suggestions.add('Use at least 8 characters');

    if (RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    } else {
      suggestions.add('Add lowercase letters');
    }

    if (RegExp(r'[A-Z]').hasMatch(password)) {
      score++;
    } else {
      suggestions.add('Add uppercase letters');
    }

    if (RegExp(r'[0-9]').hasMatch(password)) {
      score++;
    } else {
      suggestions.add('Add numbers');
    }

    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) {
      score++;
    } else {
      suggestions.add('Add special characters');
    }

    // Common patterns to avoid
    if (RegExp(r'(.)\1{2,}').hasMatch(password)) {
      score--;
      suggestions.add('Avoid repeated characters');
    }
    if (RegExp(r'(012|123|234|345|456|567|678|789|890)').hasMatch(password)) {
      score--;
      suggestions.add('Avoid sequential numbers');
    }

    score = score.clamp(0, 4);

    final labels = ['Very Weak', 'Weak', 'Fair', 'Strong', 'Very Strong'];
    return PasswordStrength(
      score: score,
      label: labels[score],
      suggestions: suggestions,
    );
  }

  // ============================================================================
  // SIGN UP
  // ============================================================================

  Future<AppUser> signUp({
    required String email,
    required String password,
    String? displayName,
    bool sendVerificationEmail = true,
  }) async {
    try {
      final strength = checkPasswordStrength(password);
      if (!strength.isStrong) {
        throw AuthException(
            'Password is too weak: ${strength.suggestions.join(", ")}');
      }

      final response = await _api.signup(
          email: email, password: password, displayName: displayName);

      if (response['requiresEmailVerification'] == true &&
          response['user'] != null) {
        final pendingUser = AppUser.fromMap(response['user']);
        await _api.clearTokens();
        throw AuthEmailVerificationRequiredException(
          pendingUser.email,
          emailSent: response['verificationEmailSent'] == true,
          message: response['message'] as String? ??
              'Please verify your email before continuing.',
        );
      }

      if (response['success'] == true && response['user'] != null) {
        final user = AppUser.fromMap(response['user']);
        await _cacheUser(user);
        return user;
      } else {
        throw AuthException(response['error'] ?? 'Sign up failed');
      }
    } on EmailVerificationRequiredException catch (e) {
      throw AuthEmailVerificationRequiredException(
        e.email,
        emailSent: e.emailSent,
        message: e.message,
      );
    } catch (e) {
      developer.log('Sign up error: $e', name: 'CustomAuthService');
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // SIGN IN
  // ============================================================================

  Future<AuthResult> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
    String? deviceInfo,
  }) async {
    try {
      final response = await _api.login(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (response['success'] == true && response['user'] != null) {
        final user = AppUser.fromMap(response['user']);
        await _cacheUser(user);

        return AuthResult(success: true, user: user);
      } else {
        throw AuthException(response['error'] ?? 'Sign in failed');
      }
    } on EmailVerificationRequiredException catch (e) {
      throw AuthEmailVerificationRequiredException(
        e.email,
        emailSent: e.emailSent,
        message: e.message,
      );
    } catch (e) {
      developer.log('Sign in error: $e', name: 'CustomAuthService');
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // TWO-FACTOR AUTHENTICATION
  // ============================================================================

  Future<AppUser> verifyTwoFactorCode(String userId, String code) async {
    try {
      await _api.verifyTwoFactor(code);
      // Refresh user profile to ensure state is consistent
      final user = await getCurrentUser();
      if (user == null) throw AuthException('Failed to retrieve user profile');
      return user;
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> enableTwoFactor(String userId) async {
    try {
      await _api.enableTwoFactor();
      // Update local state
      final user = await getCurrentUser();
      if (user != null) {
        await _cacheUser(user.copyWith(twoFactorEnabled: true));
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> disableTwoFactor(String userId, String password) async {
    try {
      await _api.disableTwoFactor(password);
      // Update local state
      final user = await getCurrentUser();
      if (user != null) {
        await _cacheUser(user.copyWith(twoFactorEnabled: false));
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> resendTwoFactorCode(String userId) async {
    try {
      await _api.resendTwoFactorCode(userId);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // EMAIL VERIFICATION
  // ============================================================================

  Future<void> sendEmailVerification(String userId, {String? email}) async {
    try {
      await _api.resendVerification(email: email);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> verifyEmail(String token) async {
    try {
      await _api.verifyEmail(token);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // PASSWORD RESET
  // ============================================================================

  Future<void> requestPasswordReset(String email) async {
    try {
      await _api.requestPasswordReset(email);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> resetPassword(String token, String newPassword) async {
    try {
      await _api.resetPassword(token, newPassword);
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await _api.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // SESSION MANAGEMENT
  // ============================================================================

  Future<AuthTokens?> refreshTokens() async {
    try {
      developer.log('Attempting to refresh token', name: 'CustomAuthService');
      final success = await _api.refreshAccessToken();

      if (success) {
        final accessToken = await _api.getToken();
        final refreshToken = await _api.getRefreshToken();

        if (accessToken != null && refreshToken != null) {
          return AuthTokens(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessTokenExpiry: DateTime.now().add(const Duration(minutes: 15)),
            refreshTokenExpiry: DateTime.now().add(const Duration(days: 30)),
          );
        }
      }
      return null;
    } catch (e) {
      developer.log('Token refresh error: $e', name: 'CustomAuthService');
      return null;
    }
  }

  Future<List<AuthSession>> getActiveSessions(String userId) async {
    return [];
  }

  Future<void> revokeSession(String sessionId) async {}

  Future<void> revokeAllOtherSessions(String userId) async {}

  // ============================================================================
  // SIGN OUT & ACCOUNT MANAGEMENT
  // ============================================================================

  Future<void> signOut() async {
    await _api.clearTokens();
    await _clearCachedUser();
    developer.log('User signed out, tokens cleared', name: 'CustomAuthService');
  }

  Future<AppUser?> getCurrentUser({bool clearTokenOn401 = true}) async {
    String? userData;
    try {
      // First try to read from cache
      userData = await _secureStorage.read(key: _userDataKey);
      developer.log('getCurrentUser: cached data exists=${userData != null}',
          name: 'CustomAuthService');

      // Try to refresh from API (pass clearTokenOn401 flag)
      final response =
          await _api.getCurrentUser(clearTokenOn401: clearTokenOn401);
      developer.log(
          'getCurrentUser: API response success=${response['success']}',
          name: 'CustomAuthService');

      if (response['success'] == true && response['user'] != null) {
        final user = AppUser.fromMap(response['user']);
        await _cacheUser(user);
        developer.log('getCurrentUser: refreshed user from API: ${user.email}',
            name: 'CustomAuthService');
        return user;
      }

      // API didn't return user, try cache
      if (userData != null) {
        try {
          final map = jsonDecode(userData);
          final user = AppUser.fromMap(map);
          developer.log('getCurrentUser: using cached user: ${user.email}',
              name: 'CustomAuthService');
          return user;
        } catch (e) {
          developer.log('getCurrentUser: failed to parse cached user: $e',
              name: 'CustomAuthService');
        }
      }

      return null;
    } catch (e) {
      if (e is EmailVerificationRequiredException) {
        developer.log(
            'getCurrentUser: email verification required for ${e.email}',
            name: 'CustomAuthService');
        await _api.clearTokens();
        await _clearCachedUser();
        throw AuthEmailVerificationRequiredException(
          e.email,
          emailSent: e.emailSent,
          message: e.message,
        );
      }
      developer.log('getCurrentUser: API error: $e', name: 'CustomAuthService');
      // On API error, fall back to cached user
      if (userData != null) {
        try {
          final map = jsonDecode(userData);
          final user = AppUser.fromMap(map);
          developer.log(
              'getCurrentUser: using cached user after error: ${user.email}',
              name: 'CustomAuthService');
          return user;
        } catch (parseError) {
          developer.log(
              'getCurrentUser: failed to parse cached user: $parseError',
              name: 'CustomAuthService');
        }
      }
      return null;
    }
  }

  Future<void> _cacheUser(AppUser user) async {
    final userData = jsonEncode(user.toMap());

    // Save to secure storage
    try {
      await _secureStorage.write(key: _userDataKey, value: userData);
      developer.log('_cacheUser: cached user ${user.email} in secure storage',
          name: 'CustomAuthService');
    } catch (e) {
      developer.log('_cacheUser: secure storage error: $e',
          name: 'CustomAuthService');
    }

    // Also save to SharedPreferences as backup
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userDataBackupKey, userData);
      developer.log(
          '_cacheUser: cached user ${user.email} in SharedPreferences backup',
          name: 'CustomAuthService');
    } catch (e) {
      developer.log('_cacheUser: SharedPreferences error: $e',
          name: 'CustomAuthService');
    }
  }

  Future<void> _clearCachedUser() async {
    try {
      await _secureStorage.delete(key: _userDataKey);
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userDataBackupKey);
    } catch (_) {}
  }

  /// Get cached user without making API call - tries secure storage first, then SharedPreferences
  Future<AppUser?> getCachedUser() async {
    // Try secure storage first
    try {
      final userData = await _secureStorage.read(key: _userDataKey);
      if (userData != null && userData.isNotEmpty) {
        final map = jsonDecode(userData);
        final user = AppUser.fromMap(map);
        developer.log(
            'getCachedUser: found user ${user.email} in secure storage',
            name: 'CustomAuthService');
        return user;
      }
    } catch (e) {
      developer.log('getCachedUser: secure storage error: $e',
          name: 'CustomAuthService');
    }

    // Fallback to SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      final userData = prefs.getString(_userDataBackupKey);
      if (userData != null && userData.isNotEmpty) {
        final map = jsonDecode(userData);
        final user = AppUser.fromMap(map);
        developer.log(
            'getCachedUser: found user ${user.email} in SharedPreferences backup',
            name: 'CustomAuthService');
        // Try to restore to secure storage
        try {
          await _secureStorage.write(key: _userDataKey, value: userData);
        } catch (_) {}
        return user;
      }
    } catch (e) {
      developer.log('getCachedUser: SharedPreferences error: $e',
          name: 'CustomAuthService');
    }

    developer.log('getCachedUser: no cached user found',
        name: 'CustomAuthService');
    return null;
  }

  Future<bool> isSessionValid() async {
    final token = await _api.getToken();
    developer.log('isSessionValid: token exists=${token != null}',
        name: 'CustomAuthService');
    return token != null;
  }

  Future<void> updateProfile({
    required String userId,
    String? displayName,
    String? avatarUrl,
    String? coverUrl,
  }) async {
    try {
      await _api.updateProfile(
        displayName: displayName,
        avatarUrl: avatarUrl,
        coverUrl: coverUrl,
      );
      // Update local state
      final user = await getCurrentUser();
      if (user != null) {
        await _cacheUser(user.copyWith(
          displayName: displayName,
          avatarUrl: avatarUrl,
          coverUrl: coverUrl,
        ));
      }
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  Future<void> deleteAccount(String userId, String password) async {
    try {
      await _api.deleteAccount(password);
      await signOut();
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException(e.toString());
    }
  }

  // ============================================================================
  // AUDIT LOGGING
  // ============================================================================

  Future<List<AuditLogEntry>> getAuditLogs(String userId,
      {int limit = 50}) async {
    return [];
  }
}

// ============================================================================
// AUTH RESULT
// ============================================================================

class AuthResult {
  final bool success;
  final AppUser? user;
  final bool requiresTwoFactor;
  final String? pendingUserId;
  final String? error;

  const AuthResult({
    required this.success,
    this.user,
    this.requiresTwoFactor = false,
    this.pendingUserId,
    this.error,
  });
}

// ============================================================================
// AUTH NOTIFIER
// ============================================================================

class CustomAuthNotifier extends StateNotifier<AuthState> {
  final Ref _ref;
  Timer? _tokenRefreshTimer;

  CustomAuthNotifier(this._ref) : super(const AuthState()) {
    _init();
  }

  CustomAuthService get _authService => _ref.read(customAuthServiceProvider);
  ApiService get _apiService => _ref.read(apiServiceProvider);

  Future<void> _init() async {
    state = state.copyWith(status: AuthStatus.loading);
    developer.log('Auth init: starting...', name: 'CustomAuthNotifier');

    try {
      // First check if we have a stored token - directly from API service
      final token = await _apiService.getToken();
      final hasToken = token != null && token.isNotEmpty;
      developer.log(
          'Auth init: hasToken=$hasToken, tokenLength=${token?.length ?? 0}',
          name: 'CustomAuthNotifier');

      if (hasToken) {
        // First try to get cached user (fast, offline-capable)
        final cachedUser = await _authService.getCachedUser();
        developer.log('Auth init: cachedUser=${cachedUser?.email}',
            name: 'CustomAuthNotifier');

        if (cachedUser != null) {
          if (!cachedUser.emailVerified) {
            developer.log(
                'Auth init: cached user is unverified, confirming with API before authenticating',
                name: 'CustomAuthNotifier');
            try {
              final verifiedUser =
                  await _authService.getCurrentUser(clearTokenOn401: false);
              if (verifiedUser != null) {
                state = AuthState(
                    status: AuthStatus.authenticated, user: verifiedUser);
                developer.log(
                    'Auth init: confirmed cached unverified user against API ${verifiedUser.email}',
                    name: 'CustomAuthNotifier');
                return;
              }
            } on AuthEmailVerificationRequiredException catch (e) {
              await _authService.signOut();
              state = AuthState(
                status: AuthStatus.unauthenticated,
                error: e.message,
                pendingVerificationEmail: e.email,
                verificationEmailSent: e.emailSent,
              );
              return;
            } catch (e) {
              developer.log(
                  'Auth init: unable to verify cached unverified user, keeping session signed out: $e',
                  name: 'CustomAuthNotifier');
              await _authService.signOut();
              state = const AuthState(status: AuthStatus.unauthenticated);
              return;
            }
          }

          // Immediately authenticate with cached user
          state = AuthState(status: AuthStatus.authenticated, user: cachedUser);
          developer.log(
              'Auth init: ✅ authenticated with cached user ${cachedUser.email} (uid: ${cachedUser.uid})',
              name: 'CustomAuthNotifier');

          // Then try to refresh from API in background (don't await)
          _refreshUserInBackground();
          return;
        }

        // No cached user, try API
        developer.log('Auth init: no cached user, trying API...',
            name: 'CustomAuthNotifier');
        final user = await _authService.getCurrentUser(clearTokenOn401: false);
        developer.log('Auth init: user from API=${user?.email}',
            name: 'CustomAuthNotifier');

        if (user != null) {
          state = AuthState(status: AuthStatus.authenticated, user: user);
          developer.log(
              'Auth init: ✅ authenticated as ${user.email} (uid: ${user.uid})',
              name: 'CustomAuthNotifier');
          return;
        }

        // Token exists but couldn't get user - this is unusual
        developer.log(
            'Auth init: ⚠️ WARNING - token exists but no user data available',
            name: 'CustomAuthNotifier');
      }

      // No valid session
      developer.log('Auth init: ❌ no valid session, unauthenticated',
          name: 'CustomAuthNotifier');
      state = const AuthState(status: AuthStatus.unauthenticated);
    } catch (e) {
      developer.log('Auth init error: $e', name: 'CustomAuthNotifier');
      // On error, try to use cached user if available
      try {
        final cachedUser = await _authService.getCachedUser();
        if (cachedUser != null && cachedUser.emailVerified) {
          developer.log(
              'Auth init: using cached user after error ${cachedUser.email}',
              name: 'CustomAuthNotifier');
          state = AuthState(status: AuthStatus.authenticated, user: cachedUser);
          return;
        }
      } catch (_) {}
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  /// Refresh user data from API in background without affecting auth state
  Future<void> _refreshUserInBackground() async {
    try {
      final user = await _authService.getCurrentUser(clearTokenOn401: false);
      if (user != null && state.isAuthenticated) {
        state = AuthState(status: AuthStatus.authenticated, user: user);
        developer.log('Auth: refreshed user in background ${user.email}',
            name: 'CustomAuthNotifier');
      }
    } on AuthEmailVerificationRequiredException catch (e) {
      developer.log(
          'Auth: signing out unverified user after refresh requirement ${e.email}',
          name: 'CustomAuthNotifier');
      await _authService.signOut();
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.message,
        pendingVerificationEmail: e.email,
        verificationEmailSent: e.emailSent,
      );
    } catch (e) {
      // Silently ignore background refresh errors - user stays logged in with cached data
      developer.log('Auth: background refresh failed (ignored): $e',
          name: 'CustomAuthNotifier');
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final user = await _authService.signUp(
        email: email,
        password: password,
        displayName: displayName,
      );
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on AuthEmailVerificationRequiredException catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.message,
        pendingVerificationEmail: e.email,
        verificationEmailSent: e.emailSent,
      );
      rethrow;
    } on AuthException catch (e) {
      state = AuthState(status: AuthStatus.error, error: e.message);
      rethrow;
    } catch (e) {
      state =
          const AuthState(status: AuthStatus.error, error: 'Sign up failed');
      rethrow;
    }
  }

  Future<void> signIn({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    state = state.copyWith(status: AuthStatus.loading);

    try {
      final result = await _authService.signIn(
        email: email,
        password: password,
        rememberMe: rememberMe,
      );

      if (result.requiresTwoFactor) {
        state = AuthState(
          status: AuthStatus.unauthenticated,
          requiresTwoFactor: true,
          pendingUserId: result.pendingUserId,
        );
      } else if (result.success && result.user != null) {
        state = AuthState(status: AuthStatus.authenticated, user: result.user);
      }
    } on AuthEmailVerificationRequiredException catch (e) {
      state = AuthState(
        status: AuthStatus.unauthenticated,
        error: e.message,
        pendingVerificationEmail: e.email,
        verificationEmailSent: e.emailSent,
      );
      rethrow;
    } on AuthException catch (e) {
      state = AuthState(status: AuthStatus.error, error: e.message);
      rethrow;
    } catch (e) {
      state =
          const AuthState(status: AuthStatus.error, error: 'Sign in failed');
      rethrow;
    }
  }

  Future<void> verifyTwoFactor(String code) async {
    if (state.pendingUserId == null) {
      throw AuthException('No pending authentication');
    }

    state = state.copyWith(status: AuthStatus.loading);

    try {
      final user =
          await _authService.verifyTwoFactorCode(state.pendingUserId!, code);
      state = AuthState(status: AuthStatus.authenticated, user: user);
    } on AuthException catch (e) {
      state = state.copyWith(status: AuthStatus.error, error: e.message);
      rethrow;
    }
  }

  Future<void> signOut() async {
    _tokenRefreshTimer?.cancel();
    await _authService.signOut();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearPendingVerification() {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> refresh() async {
    await _init();
  }

  @override
  void dispose() {
    _tokenRefreshTimer?.cancel();
    super.dispose();
  }
}

// ============================================================================
// AUTH EXCEPTION
// ============================================================================

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthEmailVerificationRequiredException extends AuthException {
  final String email;
  final bool emailSent;

  AuthEmailVerificationRequiredException(
    this.email, {
    String message = 'Please verify your email before continuing.',
    this.emailSent = false,
  }) : super(message);
}
