import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_service.dart';

/// Routes that don't require authentication
const publicRoutes = {
  '/onboarding',
  '/onboarding-completion',
  '/login',
  '/verify-email-required',
  '/verify-email',
  '/password-reset',
};

/// Protected route prefixes
const protectedRoutePrefixes = [
  '/home',
  '/sources',
  '/chat',
  '/search',
  '/artifact',
  '/research',
  '/settings',
  '/deploy-keys',
  '/migrate-agent-id',
  '/context-profile',
  '/elevenlabs-agent',
  '/voice-mode',
  '/visual-studio',
  '/notebook/',
];

/// Auth change notifier for GoRouter refresh
class AuthChangeNotifier extends ChangeNotifier {
  final ProviderContainer _container;
  ProviderSubscription<Map<String, dynamic>?>? _subscription;

  AuthChangeNotifier(this._container) {
    _subscription = _container.listen<Map<String, dynamic>?>(
      currentUserProvider,
      (previous, next) {
        // Notify when user changes (login/logout)
        if ((previous == null) != (next == null)) {
          notifyListeners();
        }
      },
    );
  }

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }
}

/// Check if a route requires authentication
bool isProtectedRoute(String path) {
  if (publicRoutes.contains(path)) return false;

  for (final prefix in protectedRoutePrefixes) {
    if (path.startsWith(prefix)) return true;
  }

  return false;
}

/// Create auth redirect function with container
String? Function(BuildContext?, GoRouterState) createAuthRedirect(
    ProviderContainer container) {
  return (BuildContext? context, GoRouterState state) {
    final user = container.read(currentUserProvider);
    final isAuthenticated = user != null;
    final path = state.uri.path;

    // Allow public routes
    if (publicRoutes.contains(path)) {
      // Redirect authenticated users away from login
      if (path == '/login' && isAuthenticated) {
        return '/home';
      }
      return null;
    }

    // Protect routes that need auth
    if (!isAuthenticated && isProtectedRoute(path)) {
      return '/login';
    }

    return null;
  };
}
