import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/auth/custom_auth_service.dart';
import '../models/subscription_model.dart';
import '../providers/subscription_provider.dart';

class PaidAccessGate extends ConsumerWidget {
  const PaidAccessGate({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(userSubscriptionProvider);
    return subscription.when(
      loading: () => const _SubscriptionLoading(),
      error: (_, __) => _SubscriptionRequired(
        onRetry: () => ref.invalidate(userSubscriptionProvider),
      ),
      data: (value) {
        if (_hasMemoryAccess(value)) return child;
        return _SubscriptionRequired(
          subscription: value,
          onRetry: () => ref.invalidate(userSubscriptionProvider),
        );
      },
    );
  }

  bool _hasMemoryAccess(SubscriptionModel? subscription) {
    if (subscription == null) return false;
    return subscription.status.toLowerCase() == 'active' &&
        subscription.canAccess('memory_bank');
  }
}

class _SubscriptionLoading extends StatelessWidget {
  const _SubscriptionLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

class _SubscriptionRequired extends ConsumerWidget {
  const _SubscriptionRequired({
    required this.onRetry,
    this.subscription,
  });

  final SubscriptionModel? subscription;
  final VoidCallback onRetry;

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    await ref.read(customAuthStateProvider.notifier).signOut();
    if (context.mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 20,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                LucideIcons.brainCircuit,
                color: scheme.onPrimary,
                size: 20,
              ),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NoteClaw',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  'AGENT MEMORY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/settings/account'),
            tooltip: 'Account settings',
            icon: const Icon(LucideIcons.settings, size: 19),
          ),
          IconButton(
            onPressed: onRetry,
            tooltip: 'Check subscription again',
            icon: const Icon(LucideIcons.refreshCw, size: 19),
          ),
          IconButton(
            onPressed: () => _signOut(context, ref),
            tooltip: 'Sign out',
            icon: const Icon(LucideIcons.logOut, size: 19),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 48),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      LucideIcons.shieldCheck,
                      color: scheme.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Subscribe to open your memory bank',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.7,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Choose a plan that includes durable agent memory. Plan '
                    'features are controlled by your NoteClaw administrator.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.55,
                        ),
                  ),
                  if (subscription != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Current plan: ${subscription!.planName}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  _BenefitGrid(scheme: scheme),
                  const SizedBox(height: 24),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FilledButton.icon(
                          onPressed: () => context.go('/subscription'),
                          icon: const Icon(LucideIcons.creditCard, size: 18),
                          label: const Text('View subscription plans'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('I’ve already subscribed'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Cancel anytime. Agent data remains private to your account.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 480
                ? 2
                : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        const benefits = [
          (
            LucideIcons.database,
            'Durable memory',
            'Restore settings and project context after agent updates.',
          ),
          (
            LucideIcons.radio,
            'Shared sessions',
            'Keep multiple agents synchronized over WebSocket.',
          ),
          (
            LucideIcons.code2,
            'Code review',
            'Give connected agents a focused review before shipping.',
          ),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: benefits
              .map(
                (benefit) => SizedBox(
                  width: width,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(benefit.$1, color: scheme.primary, size: 21),
                        const SizedBox(height: 13),
                        Text(
                          benefit.$2,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          benefit.$3,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.45,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}
