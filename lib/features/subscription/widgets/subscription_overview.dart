import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../models/subscription_model.dart';
import '../providers/subscription_provider.dart';

class SubscriptionBalanceButton extends ConsumerWidget {
  const SubscriptionBalanceButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(userSubscriptionProvider);
    final label = subscription.when(
      data: (value) => value == null ? 'Plans' : '${value.currentCredits}',
      loading: () => '—',
      error: (_, __) => 'Plans',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: TextButton.icon(
        onPressed: () => context.push('/subscription'),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        icon: const Icon(LucideIcons.coins, size: 16),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class SubscriptionOverviewCard extends ConsumerWidget {
  const SubscriptionOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(userSubscriptionProvider);
    return subscription.when(
      loading: () => const _SubscriptionLoadingCard(),
      error: (_, __) => const _SubscriptionErrorCard(),
      data: (value) => _SubscriptionDataCard(subscription: value),
    );
  }
}

class _SubscriptionDataCard extends StatelessWidget {
  const _SubscriptionDataCard({required this.subscription});

  final SubscriptionModel? subscription;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final value = subscription;
    final actionLabel =
        value == null || value.isFreePlan ? 'Upgrade plan' : 'Manage plan';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.13),
            scheme.tertiary.withValues(alpha: 0.09),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.24)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  LucideIcons.creditCard,
                  color: scheme.primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value?.planName ?? 'Choose a NoteClaw plan',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value == null
                          ? 'Compare plans and activate agent memory.'
                          : '${value.currentCredits} credits available · '
                              '${value.creditsPerMonth} added each month',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    if (value != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${_limitLabel(value.mcpApiCallsPerDay)} tool calls/day'
                        ' · ${_limitLabel(value.mcpTokensLimit)} agent tokens',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final action = FilledButton.icon(
            onPressed: () => context.push('/subscription'),
            icon: Icon(
              value == null || value.isFreePlan
                  ? LucideIcons.sparkles
                  : LucideIcons.settings2,
              size: 16,
            ),
            label: Text(actionLabel),
          );

          if (constraints.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                details,
                const SizedBox(height: 15),
                action,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 18),
              action,
            ],
          );
        },
      ),
    );
  }

  static String _limitLabel(int? value) => value == null ? 'Managed' : '$value';
}

class _SubscriptionLoadingCard extends StatelessWidget {
  const _SubscriptionLoadingCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text('Loading plan and credit balance…'),
        ],
      ),
    );
  }
}

class _SubscriptionErrorCard extends StatelessWidget {
  const _SubscriptionErrorCard();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push('/subscription'),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(LucideIcons.creditCard, color: scheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Open Subscription & Credits to check your plan.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 18),
          ],
        ),
      ),
    );
  }
}
