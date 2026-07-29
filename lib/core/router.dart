import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/custom_login_screen.dart';
import '../features/auth/email_verification_required_screen.dart';
import '../features/auth/email_verification_screen.dart';
import '../features/auth/password_reset_screen.dart';
import '../features/auth/terms_of_service_screen.dart';
import '../features/chat/memory_chat_screen.dart';
import '../features/code_review/code_review_screen.dart';
import '../features/fact_check/fact_check_screen.dart';
import '../features/github/github_connect_screen.dart';
import '../features/home/memory_dashboard_screen.dart';
import '../features/memory/memory_notebook_screen.dart';
import '../features/search/web_search_screen.dart';
import '../features/settings/agent_connections_screen.dart';
import '../features/settings/account_settings_screen.dart';
import '../features/settings/privacy_policy_screen.dart';
import '../features/subscription/screens/paid_access_gate.dart';
import '../features/subscription/screens/subscription_screen.dart';
import 'auth/custom_auth_guard.dart';
import 'error/not_found_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

String getInitialLocation() {
  if (kIsWeb) {
    final browserPath = Uri.base.path;
    final isDeepLink = browserPath.isNotEmpty &&
        browserPath != '/' &&
        !browserPath.endsWith('index.html');
    if (isDeepLink) {
      return browserPath;
    }
  }
  return '/home';
}

GoRouter createRouter(ProviderContainer container) {
  final authNotifier = CustomAuthChangeNotifier(container);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: getInitialLocation(),
    refreshListenable: authNotifier,
    redirect: createCustomAuthRedirect(container),
    errorBuilder: (context, state) => NotFoundScreen(state: state),
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(
        path: '/home',
        name: 'memory-bank',
        pageBuilder: (context, state) => buildTransitionPage(
          child: const PaidAccessGate(
            child: MemoryDashboardScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/agents',
        name: 'agent-hub',
        pageBuilder: (context, state) => buildTransitionPage(
          child: const PaidAccessGate(
            child: AgentConnectionsScreen(),
          ),
        ),
      ),
      GoRoute(path: '/agent-connections', redirect: (_, __) => '/agents'),
      GoRoute(
        path: '/memory-chat',
        name: 'memory-chat',
        pageBuilder: (context, state) => buildTransitionPage(
          child: const PaidAccessGate(
            child: MemoryChatScreen(),
          ),
        ),
      ),
      GoRoute(path: '/chat', redirect: (_, __) => '/memory-chat'),
      GoRoute(
        path: '/research',
        name: 'deep-research',
        pageBuilder: (context, state) => buildTransitionPage(
          child: const PaidAccessGate(
            child: WebSearchScreen(initialDeepResearch: true),
          ),
        ),
      ),
      GoRoute(
        path: '/fact-check',
        name: 'fact-check',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const FactCheckScreen()),
      ),
      GoRoute(
        path: '/code-review',
        name: 'code-review',
        pageBuilder: (context, state) => buildTransitionPage(
          child: const PaidAccessGate(
            child: CodeReviewScreen(),
          ),
        ),
      ),
      GoRoute(
        path: '/github',
        name: 'github',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const GitHubConnectScreen()),
      ),
      GoRoute(
        path: '/settings/account',
        name: 'account-settings',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const AccountSettingsScreen()),
      ),
      GoRoute(
        path: '/subscription',
        name: 'subscription',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const SubscriptionScreen()),
      ),
      GoRoute(path: '/plan-selection', redirect: (_, __) => '/subscription'),
      GoRoute(
        path: '/memory-notebooks/:notebookId',
        name: 'memory-notebook',
        pageBuilder: (context, state) => buildTransitionPage(
          child: PaidAccessGate(
            child: MemoryNotebookScreen(
              notebookId: state.pathParameters['notebookId'] ?? '',
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/memory-notebooks/:notebookId/chat',
        name: 'notebook-memory-chat',
        pageBuilder: (context, state) => buildTransitionPage(
          child: PaidAccessGate(
            child: MemoryChatScreen(
              initialNotebookId: state.pathParameters['notebookId'],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const CustomLoginScreen()),
      ),
      GoRoute(
        path: '/password-reset/:token',
        name: 'password-reset',
        pageBuilder: (context, state) => buildTransitionPage(
          child: PasswordResetScreen(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/verify-email-required',
        name: 'verify-email-required',
        pageBuilder: (context, state) => buildTransitionPage(
          child: EmailVerificationRequiredScreen(
            email: state.uri.queryParameters['email'] ?? '',
            emailSent:
                (state.uri.queryParameters['sent'] ?? '').toLowerCase() ==
                    'true',
          ),
        ),
      ),
      GoRoute(
        path: '/verify-email/:token',
        name: 'verify-email',
        pageBuilder: (context, state) => buildTransitionPage(
          child: EmailVerificationScreen(
            token: state.pathParameters['token'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/privacy-policy',
        name: 'privacy-policy',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: '/terms-of-service',
        name: 'terms-of-service',
        pageBuilder: (context, state) =>
            buildTransitionPage(child: const TermsOfServiceScreen()),
      ),
    ],
  );
}

CustomTransitionPage<void> buildTransitionPage({
  required Widget child,
  LocalKey? key,
}) {
  return CustomTransitionPage<void>(
    key: key,
    child: child,
    transitionDuration: const Duration(milliseconds: 180),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      );
    },
  );
}
