import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/custom_auth_service.dart';
import '../../ui/components/glass_container.dart';
import '../../ui/components/premium_button.dart';
import '../../ui/components/premium_input.dart';
import '../../theme/app_theme.dart';

class CustomLoginScreen extends ConsumerStatefulWidget {
  const CustomLoginScreen({super.key});

  @override
  ConsumerState<CustomLoginScreen> createState() => _CustomLoginScreenState();
}

class _CustomLoginScreenState extends ConsumerState<CustomLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _twoFactorController = TextEditingController();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _rememberMe = false;
  bool _showTwoFactor = false;
  bool _showForgotPassword = false;
  PasswordStrength? _passwordStrength;

  static const String _hasSelectedPackagePref = 'has_selected_package';

  Future<String> _getPostAuthRoute() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSelected = prefs.getBool(_hasSelectedPackagePref) ?? false;
    return hasSelected ? '/home' : '/plan-selection';
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _twoFactorController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _checkPasswordStrength(String password) {
    if (_isSignUp && password.isNotEmpty) {
      final authService = ref.read(customAuthServiceProvider);
      setState(() {
        _passwordStrength = authService.checkPasswordStrength(password);
      });
    } else {
      setState(() => _passwordStrength = null);
    }
  }

  Future<void> _submit() async {
    if (_showTwoFactor) {
      await _verifyTwoFactor();
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authNotifier = ref.read(customAuthStateProvider.notifier);

      if (_isSignUp) {
        await authNotifier.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          displayName: _nameController.text.trim(),
        );
        if (mounted) context.go('/plan-selection');
      } else {
        await authNotifier.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          rememberMe: _rememberMe,
        );

        final state = ref.read(customAuthStateProvider);
        if (state.requiresTwoFactor) {
          setState(() => _showTwoFactor = true);
        } else {
          final dest = await _getPostAuthRoute();
          if (mounted) context.go(dest);
        }
      }
    } on AuthException catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('An error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyTwoFactor() async {
    if (_twoFactorController.text.length != 6) {
      _showError('Please enter the 6-digit code');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(customAuthStateProvider.notifier).verifyTwoFactor(
            _twoFactorController.text,
          );
      final dest = await _getPostAuthRoute();
      if (mounted) context.go(dest);
    } on AuthException catch (e) {
      _showError(e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestPasswordReset() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email address');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ref.read(customAuthServiceProvider).requestPasswordReset(email);
      _showSuccess('If an account exists, a reset link has been sent');
      setState(() => _showForgotPassword = false);
    } catch (e) {
      _showError('Failed to send reset email');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade400,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _toggleMode() {
    _animationController.reverse().then((_) {
      setState(() {
        _isSignUp = !_isSignUp;
        _passwordStrength = null;
        _formKey.currentState?.reset();
      });
      _animationController.forward();
    });
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
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _buildContent(theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_showTwoFactor) return _buildTwoFactorCard(theme);
    if (_showForgotPassword) return _buildForgotPasswordCard(theme);
    return _buildMainCard(theme);
  }

  Widget _buildMainCard(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 32),
            _buildForm(theme),
            if (!_isSignUp) ...[
              const SizedBox(height: 8),
              _buildRememberMeAndForgot(theme),
            ],
            const SizedBox(height: 24),
            PremiumButton(
              onPressed: _submit,
              label: _isSignUp ? 'Create Account' : 'Sign In',
              isLoading: _isLoading,
            ),
            const SizedBox(height: 16),
            _buildToggleMode(theme),
            const SizedBox(height: 24),
            _buildLegalLinks(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: const Icon(
            LucideIcons.bookOpenCheck, // Using lucide for modern feel
            size: 48,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'NoteClaw',
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          _isSignUp ? 'Create your account' : 'Welcome back',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Column(
        children: [
          if (_isSignUp) ...[
            PremiumInput(
              controller: _nameController,
              label: 'Full Name',
              icon: LucideIcons.user,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (_isSignUp && (value?.isEmpty ?? true)) {
                  return 'Please enter your name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],
          PremiumInput(
            controller: _emailController,
            label: 'Email',
            icon: LucideIcons.mail,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Please enter your email';
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                  .hasMatch(value!)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          PremiumInput(
            controller: _passwordController,
            label: 'Password',
            icon: LucideIcons.lock,
            obscureText: _obscurePassword,
            textInputAction:
                _isSignUp ? TextInputAction.next : TextInputAction.done,
            onChanged: _checkPasswordStrength,
            onFieldSubmitted: (_) => _isSignUp ? null : _submit(),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? LucideIcons.eye : LucideIcons.eyeOff,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
            validator: (value) {
              if (value?.isEmpty ?? true) return 'Please enter your password';
              if ((value?.length ?? 0) < 8) {
                return 'Password must be at least 8 characters';
              }
              return null;
            },
          ),
          if (_passwordStrength != null) ...[
            const SizedBox(height: 8),
            _buildPasswordStrengthIndicator(theme),
          ],
          if (_isSignUp) ...[
            const SizedBox(height: 16),
            PremiumInput(
              controller: _confirmPasswordController,
              label: 'Confirm Password',
              icon: LucideIcons.lock,
              obscureText: _obscureConfirmPassword,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword
                      ? LucideIcons.eye
                      : LucideIcons.eyeOff,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: () => setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              validator: (value) {
                if (value != _passwordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPasswordStrengthIndicator(ThemeData theme) {
    if (_passwordStrength == null) return const SizedBox.shrink();

    final strength = _passwordStrength!;
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.lightGreen,
      Colors.green
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (strength.score + 1) / 5,
                  backgroundColor:
                      theme.colorScheme.outline.withValues(alpha: 0.3),
                  valueColor: AlwaysStoppedAnimation(colors[strength.score]),
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              strength.label,
              style: TextStyle(
                color: colors[strength.score],
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        if (strength.suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            strength.suggestions.first,
            style: TextStyle(
                fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildRememberMeAndForgot(ThemeData theme) {
    return Row(
      children: [
        Theme(
          data: theme.copyWith(
              checkboxTheme: CheckboxThemeData(
            side: BorderSide(color: theme.colorScheme.onSurfaceVariant),
          )),
          child: Checkbox(
            value: _rememberMe,
            onChanged: (v) => setState(() => _rememberMe = v ?? false),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        Text('Remember me',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
        const Spacer(),
        TextButton(
          onPressed: () => setState(() => _showForgotPassword = true),
          child: Text('Forgot password?',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              )),
        ),
      ],
    );
  }

  Widget _buildToggleMode(ThemeData theme) {
    return TextButton(
      onPressed: _toggleMode,
      child: Text(
        _isSignUp
            ? 'Already have an account? Sign In'
            : "Don't have an account? Sign Up",
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.9),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildLegalLinks(ThemeData theme) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          'By continuing, you agree to our',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/privacy-policy'),
          child: Text(
            'Privacy Policy',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontSize: 11,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Text(
          'and',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 11,
          ),
        ),
        GestureDetector(
          onTap: () => context.push('/terms-of-service'),
          child: Text(
            'Terms & Conditions',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white,
              fontSize: 11,
              decoration: TextDecoration.underline,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTwoFactorCard(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.shieldCheck,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text('Two-Factor Auth', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Enter the 6-digit code sent to your email',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _twoFactorController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            style: TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                color: theme.colorScheme.onSurface),
            decoration: InputDecoration(
              counterText: '',
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.inputDecorationTheme.fillColor,
            ),
          ),
          const SizedBox(height: 24),
          PremiumButton(
            onPressed: _submit,
            label: 'Verify',
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () async {
              final state = ref.read(customAuthStateProvider);
              if (state.pendingUserId != null) {
                await ref
                    .read(customAuthServiceProvider)
                    .resendTwoFactorCode(state.pendingUserId!);
                _showSuccess('New code sent');
              }
            },
            child: const Text('Resend Code'),
          ),
          TextButton(
            onPressed: () => setState(() {
              _showTwoFactor = false;
              _twoFactorController.clear();
            }),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }

  Widget _buildForgotPasswordCard(ThemeData theme) {
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.keyRound,
              size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 24),
          Text('Reset Password', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Enter your email to receive a reset link',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          PremiumInput(
            controller: _emailController,
            label: 'Email',
            icon: LucideIcons.mail,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 24),
          PremiumButton(
            onPressed: _requestPasswordReset,
            label: 'Send Reset Link',
            isLoading: _isLoading,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() => _showForgotPassword = false),
            child: const Text('Back to Login'),
          ),
        ],
      ),
    );
  }
}
