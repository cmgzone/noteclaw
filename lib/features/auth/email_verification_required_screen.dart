import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/auth/custom_auth_service.dart';
import '../../theme/app_theme.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/premium_button.dart';

class EmailVerificationRequiredScreen extends ConsumerStatefulWidget {
  final String email;
  final bool emailSent;

  const EmailVerificationRequiredScreen({
    super.key,
    required this.email,
    this.emailSent = false,
  });

  @override
  ConsumerState<EmailVerificationRequiredScreen> createState() =>
      _EmailVerificationRequiredScreenState();
}

class _EmailVerificationRequiredScreenState
    extends ConsumerState<EmailVerificationRequiredScreen> {
  bool _isSending = false;
  late bool _emailSent;

  @override
  void initState() {
    super.initState();
    _emailSent = widget.emailSent;
  }

  Future<void> _resendVerificationEmail() async {
    if (widget.email.trim().isEmpty) {
      _showSnackBar('Missing email address for resend.', Colors.red);
      return;
    }

    setState(() => _isSending = true);
    try {
      await ref
          .read(customAuthServiceProvider)
          .sendEmailVerification('', email: widget.email.trim());
      if (mounted) {
        setState(() => _emailSent = true);
      }
      _showSnackBar('Verification email sent.', Colors.green);
    } on AuthException catch (e) {
      _showSnackBar(e.message, Colors.red);
    } catch (_) {
      _showSnackBar('Failed to resend verification email.', Colors.red);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                constraints: const BoxConstraints(maxWidth: 460),
                child: GlassContainer(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          LucideIcons.mailCheck,
                          size: 60,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'Verify Your Email',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _emailSent
                            ? 'We sent a verification link to the email below. Open that link before signing in.'
                            : 'Email verification is required before you can continue. Use the button below to send a verification link.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (widget.email.trim().isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface.withValues(
                              alpha: 0.45,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.15,
                              ),
                            ),
                          ),
                          child: Text(
                            widget.email,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      PremiumButton(
                        onPressed: _isSending
                            ? null
                            : () => _resendVerificationEmail(),
                        label: 'Resend Verification Email',
                        isLoading: _isSending,
                      ),
                      const SizedBox(height: 14),
                      PremiumButton(
                        onPressed: () {
                          ref
                              .read(customAuthStateProvider.notifier)
                              .clearPendingVerification();
                          context.go('/login');
                        },
                        label: 'Back to Login',
                        isSecondary: true,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'If you do not see the message, check spam or promotions.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
