import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/auth/custom_auth_service.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/premium_button.dart';
import '../../theme/app_theme.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  final String token;

  const EmailVerificationScreen({super.key, required this.token});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  bool _isLoading = true;
  bool _isVerified = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _verifyEmail();
  }

  Future<void> _verifyEmail() async {
    try {
      await ref.read(customAuthServiceProvider).verifyEmail(widget.token);
      ref.read(customAuthStateProvider.notifier).clearPendingVerification();
      setState(() {
        _isVerified = true;
        _isLoading = false;
      });
      // Refresh auth state
      ref.invalidate(customAuthStateProvider);
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to verify email. The link may have expired.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.premiumGradient,
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: _buildContent(Theme.of(context)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_isLoading) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Colors.white),
          const SizedBox(height: 24),
          Text(
            'Verifying your email...',
            style: theme.textTheme.titleMedium,
          ),
        ],
      );
    }

    if (_isVerified) {
      final authState = ref.watch(customAuthStateProvider);
      final nextRoute = authState.isAuthenticated ? '/home' : '/login';
      final nextLabel =
          authState.isAuthenticated ? 'Continue to App' : 'Continue to Login';

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: const Icon(LucideIcons.checkCircle,
                size: 64, color: Colors.green),
          ),
          const SizedBox(height: 24),
          Text('Email Verified!', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Your email has been successfully verified. You now have full access to all features.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          PremiumButton(
            onPressed: () => context.go(nextRoute),
            label: nextLabel,
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          ),
          child:
              const Icon(LucideIcons.alertCircle, size: 64, color: Colors.red),
        ),
        const SizedBox(height: 24),
        Text('Verification Failed', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          _error ?? 'An error occurred during verification.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        PremiumButton(
          onPressed: () => context.go('/login'),
          label: 'Back to Login',
          isSecondary: true, // Use secondary style for failure backing out
        ),
      ],
    );
  }
}
