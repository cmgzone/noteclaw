import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/auth/custom_auth_service.dart';
import '../../../theme/app_theme.dart';
import '../providers/subscription_provider.dart';
import '../services/subscription_service.dart';

const String kHasSelectedPackagePref = 'has_selected_package';

class PlanSelectionScreen extends ConsumerStatefulWidget {
  const PlanSelectionScreen({super.key});

  @override
  ConsumerState<PlanSelectionScreen> createState() => _PlanSelectionScreenState();
}

class _PlanSelectionScreenState extends ConsumerState<PlanSelectionScreen> {
  String? _selectedPlanId;
  bool _submitting = false;

  Future<void> _markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kHasSelectedPackagePref, true);
  }

  Future<void> _continueWithPlan(Map<String, dynamic> plan) async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final auth = ref.read(customAuthStateProvider);
      final user = auth.user;
      if (user == null) throw Exception('Not authenticated');

      final subSvc = ref.read(subscriptionServiceProvider);
      await subSvc.createSubscriptionForUser(user.uid);

      await _markCompleted();

      final isFree = (plan['is_free_plan'] as bool?) ?? false;
      if (!mounted) return;
      if (isFree) {
        context.go('/home');
      } else {
        context.go('/subscription');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _continueWithoutPlan() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await _markCompleted();
      if (!mounted) return;
      context.go('/home');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plansAsync = ref.watch(subscriptionPlansProvider);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: scheme.onSurface),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.surface,
              scheme.surfaceContainerLowest,
            ],
          ),
        ),
        child: plansAsync.when(
          loading: () => Center(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Loading plans...',
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.7),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPrimaryButton(
                      label: 'Continue',
                      onTap: _continueWithoutPlan,
                    ),
                  ],
                ),
              ),
            ),
          ),
          error: (err, _) => Center(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Failed to load plans',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      err.toString(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildPrimaryButton(
                      label: 'Continue',
                      onTap: _continueWithoutPlan,
                    ),
                  ],
                ),
              ),
            ),
          ),
          data: (plans) {
            if (plans.isEmpty) {
              return Center(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No plans available right now',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'You can continue and choose a plan later.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _buildPrimaryButton(
                          label: 'Continue',
                          onTap: _continueWithoutPlan,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            _selectedPlanId ??= _pickDefaultPlanId(plans);

            final selectedPlan = plans.firstWhere(
              (p) => p['id'].toString() == _selectedPlanId,
              orElse: () => plans.first,
            );
            final isFree = (selectedPlan['is_free_plan'] as bool?) ?? false;

            return Stack(
              children: [
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.premiumGradient.colors.first
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -50,
                  left: -100,
                  child: Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.premiumGradient.colors.last
                          .withValues(alpha: 0.15),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 16),
                        child: Column(
                          children: [
                            ShaderMask(
                              shaderCallback: (bounds) =>
                                  AppTheme.premiumGradient.createShader(bounds),
                              child: const Text(
                                'Choose Your Plan',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Unlock the full potential of your AI assistant. You can switch plans at any time.',
                              style: TextStyle(
                                fontSize: 15,
                                color: scheme.onSurface.withValues(alpha: 0.7),
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 8),
                          itemCount: plans.length,
                          itemBuilder: (context, index) {
                            final plan = plans[index];
                            return _buildPlanCard(plan, context);
                          },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.92),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, -5),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: _buildPrimaryButton(
                            label: isFree
                                ? 'Get Started'
                                : 'Continue to Payment',
                            onTap: () => _continueWithPlan(selectedPlan),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPrimaryButton({
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: InkWell(
        onTap: _submitting ? null : onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: AppTheme.premiumGradient,
          ),
          child: Center(
            child: _submitting
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard(Map<String, dynamic> plan, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final planId = plan['id'].toString();
    final name = plan['name']?.toString() ?? 'Plan';
    final desc = plan['description']?.toString() ?? '';
    final price = _parsePrice(plan['price']);
    final isFree = (plan['is_free_plan'] as bool?) ?? false;
    final notesLimit = _parseInt(plan['notes_limit']);
    final mcpSources = _parseInt(plan['mcp_sources_limit']);
    final mcpTokens = _parseInt(plan['mcp_tokens_limit']);
    final mcpCalls = _parseInt(plan['mcp_api_calls_per_day']);

    final isSelected = _selectedPlanId == planId;
    final borderGradient = isSelected ? AppTheme.premiumGradient : null;
    final isPremium = !isFree;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: borderGradient,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppTheme.premiumGradient.colors.first.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ],
            ),
            padding: EdgeInsets.all(isSelected ? 2 : 1), // Gradient border width
            child: Material(
              color: isSelected
                  ? (Theme.of(context).brightness == Brightness.dark
                      ? scheme.surfaceContainer.withValues(alpha: 0.9)
                      : Colors.white)
                  : scheme.surfaceContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => setState(() => _selectedPlanId = planId),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? scheme.primary : scheme.onSurface,
                                  ),
                                ),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    desc,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            height: 24,
                            width: 24,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.transparent : scheme.outline,
                                width: 2,
                              ),
                              gradient: isSelected ? AppTheme.premiumGradient : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 16, color: Colors.white)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isFree ? 'Free' : '\$${price.toStringAsFixed(isPremium && price % 1 == 0 ? 0 : 2)}',
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (!isFree)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4, left: 4),
                              child: Text(
                                '/month',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurface.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Divider(color: scheme.outline.withValues(alpha: 0.2)),
                      const SizedBox(height: 12),
                      if (notesLimit != null) _buildFeatureRow('Up to $notesLimit notes', scheme),
                      if (mcpSources != null) _buildFeatureRow('$mcpSources MCP sources', scheme),
                      if (mcpTokens != null) _buildFeatureRow('$mcpTokens MCP tokens/req', scheme),
                      if (mcpCalls != null) _buildFeatureRow('$mcpCalls API calls per day', scheme),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (isPremium)
            Positioned(
              top: -12,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: AppTheme.premiumGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.premiumGradient.colors.first.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Recommended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(String text, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 14,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _pickDefaultPlanId(List<Map<String, dynamic>> plans) {
    for (final p in plans) {
      final isFree = (p['is_free_plan'] as bool?) ?? false;
      if (isFree) return p['id'].toString();
    }
    return plans.first['id'].toString();
  }

  double _parsePrice(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
