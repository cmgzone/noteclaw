import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/core/auth/custom_auth_service.dart';

void main() {
  group('CustomAuthService password strength', () {
    test('weak password returns not strong', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(customAuthServiceProvider);
      final strength = service.checkPasswordStrength('1234');

      expect(strength.isStrong, isFalse);
      expect(strength.suggestions, isNotEmpty);
    });

    test('strong password returns strong', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(customAuthServiceProvider);
      final strength = service.checkPasswordStrength('Aa1!Aa1!Bb2@');

      expect(strength.isStrong, isTrue);
      expect(strength.score, greaterThanOrEqualTo(3));
    });
  });

  group('Auth model parsing', () {
    test('AppUser.fromMap supports snake_case fields', () {
      final user = AppUser.fromMap({
        'id': 'u1',
        'email': 'user@example.com',
        'display_name': 'User',
        'created_at': '2026-01-01T00:00:00.000Z',
        'email_verified': true,
        'two_factor_enabled': true,
        'avatar_url': 'https://example.com/avatar.png',
        'cover_url': 'https://example.com/cover.png',
      });

      expect(user.uid, 'u1');
      expect(user.email, 'user@example.com');
      expect(user.displayName, 'User');
      expect(user.createdAt, DateTime.parse('2026-01-01T00:00:00.000Z'));
      expect(user.emailVerified, isTrue);
      expect(user.twoFactorEnabled, isTrue);
      expect(user.avatarUrl, 'https://example.com/avatar.png');
      expect(user.coverUrl, 'https://example.com/cover.png');
    });

    test('AuthTokens expiry flags react to time boundaries', () {
      final now = DateTime.now();
      final tokens = AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessTokenExpiry: now.subtract(const Duration(seconds: 1)),
        refreshTokenExpiry: now.add(const Duration(days: 1)),
      );

      expect(tokens.isAccessTokenExpired, isTrue);
      expect(tokens.isRefreshTokenExpired, isFalse);
    });
  });
}
