import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/custom_auth_service.dart';
import '../../../core/security/global_credentials_service.dart';

import '../providers/subscription_provider.dart';
import '../services/google_play_billing_service.dart';
import '../services/subscription_service.dart';
import '../services/paypal_service.dart';
import '../services/stripe_service.dart';
import '../services/credit_manager.dart';
import '../models/credit_package_model.dart';

// PayPal Service Provider
final paypalServiceProvider = Provider<PayPalService>((ref) {
  final subscriptionService = ref.watch(subscriptionServiceProvider);
  return PayPalService(subscriptionService);
});

// Stripe Service Provider
final stripeServiceProvider = Provider<StripeService>((ref) {
  final subscriptionService = ref.watch(subscriptionServiceProvider);
  final credentialsService = ref.watch(globalCredentialsServiceProvider);
  return StripeService(subscriptionService, credentialsService);
});

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _paypalInitialized = false;
  bool _stripeInitialized = false;
  bool _googlePlayInitialized = false;

  bool get _usesGooglePlayBilling =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _initPaymentServices();
  }

  Future<void> _initPaymentServices() async {
    if (_usesGooglePlayBilling) {
      try {
        await ref.read(googlePlayBillingServiceProvider).initialize();
        if (mounted) {
          setState(() => _googlePlayInitialized = true);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _googlePlayInitialized = false);
        }
      }
      return;
    }

    // Initialize PayPal
    final paypal = ref.read(paypalServiceProvider);
    await paypal.initialize();

    // Initialize Stripe
    final stripe = ref.read(stripeServiceProvider);
    await stripe.initialize();

    if (mounted) {
      setState(() {
        _paypalInitialized = true;
        _stripeInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscription = ref.watch(userSubscriptionProvider);
    final packages = ref.watch(creditPackagesProvider);
    final googlePlayCatalog =
        _usesGooglePlayBilling ? ref.watch(googlePlayCatalogProvider) : null;
    final authState = ref.watch(customAuthStateProvider);
    final user = authState.user;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription & Credits'),
        elevation: 0,
      ),
      body: subscription.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error'),
        ),
        data: (subscriptionData) {
          if (subscriptionData == null) {
            // Try to create subscription for user
            return _NoSubscriptionView(
              onRetry: () async {
                final userId = user?.uid;
                if (userId != null) {
                  final service = ref.read(subscriptionServiceProvider);
                  await service.createSubscriptionForUser(userId);
                  ref.invalidate(userSubscriptionProvider);
                }
              },
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(userSubscriptionProvider);
              ref.invalidate(creditPackagesProvider);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Credit Balance Card
                  _CreditBalanceCard(
                    currentCredits: subscriptionData.currentCredits,
                    creditsPerMonth: subscriptionData.creditsPerMonth,
                    nextRenewalDate: subscriptionData.nextRenewalDate,
                  ),

                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _CreditUsageCard(),
                  ),

                  const SizedBox(height: 24),

                  // Current Plan
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _CurrentPlanCard(
                      planName: subscriptionData.planName,
                      planPrice: subscriptionData.planPrice,
                      creditsPerMonth: subscriptionData.creditsPerMonth,
                      status: subscriptionData.status,
                      isFreePlan: subscriptionData.isFreePlan,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Available Plans Section
                  _AvailablePlansSection(
                    currentPlanId: subscriptionData.planId,
                    userId: user?.uid,
                  ),

                  const SizedBox(height: 32),

                  // Buy More Credits
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Buy More Credits',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Credit Packages
                  packages.when(
                    loading: () => const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    error: (error, stack) => Center(
                      child: Text('Error loading packages: $error'),
                    ),
                    data: (packageList) {
                      if (packageList.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(
                            child: Text('No packages available'),
                          ),
                        );
                      }

                      final playCatalog = googlePlayCatalog?.valueOrNull;
                      final playCanPurchase = !_usesGooglePlayBilling ||
                          (_googlePlayInitialized &&
                              playCatalog?.canPurchase == true);

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_usesGooglePlayBilling &&
                                googlePlayCatalog != null &&
                                googlePlayCatalog.hasError)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  'Google Play products are not ready yet: ${googlePlayCatalog.error}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            if (_usesGooglePlayBilling)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  playCanPurchase
                                      ? 'Android purchases are processed securely with Google Play.'
                                      : 'Google Play products are still loading or not configured yet.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.7),
                                      ),
                                ),
                              ),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: packageList
                                  .map((pkg) => _CreditPackageCard(
                                        package: pkg,
                                        purchaseEnabled: _usesGooglePlayBilling
                                            ? playCanPurchase &&
                                                pkg.googlePlayProductId !=
                                                    null &&
                                                playCatalog?.productDetailsById[pkg
                                                        .googlePlayProductId!] !=
                                                    null
                                            : (_paypalInitialized &&
                                                    ref
                                                        .read(
                                                            paypalServiceProvider)
                                                        .isConfigured) ||
                                                (_stripeInitialized &&
                                                    ref
                                                        .read(
                                                            stripeServiceProvider)
                                                        .isConfigured),
                                        priceLabel: _usesGooglePlayBilling
                                            ? (pkg.googlePlayProductId == null
                                                    ? null
                                                    : playCatalog
                                                        ?.productDetailsById[pkg
                                                            .googlePlayProductId!]
                                                        ?.price) ??
                                                '\$${pkg.price.toStringAsFixed(2)}'
                                            : '\$${pkg.price.toStringAsFixed(2)}',
                                        buttonLabel: _usesGooglePlayBilling
                                            ? 'Buy with Play'
                                            : 'Buy',
                                        onPurchase: () {
                                          if (user != null) {
                                            _purchasePackage(
                                                context, pkg, user.uid);
                                          }
                                        },
                                      ))
                                  .toList(),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Transaction History
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (user != null) {
                          _showTransactionHistory(context, ref, user.uid);
                        }
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('View Transaction History'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _purchasePackage(
      BuildContext context, CreditPackageModel package, String userId) {
    if (_usesGooglePlayBilling) {
      _processGooglePlayPackagePayment(context, package, userId);
      return;
    }

    final paypal = ref.read(paypalServiceProvider);
    final stripe = ref.read(stripeServiceProvider);

    final paypalAvailable = paypal.isConfigured && _paypalInitialized;
    final stripeAvailable = stripe.isConfigured && _stripeInitialized;

    if (!paypalAvailable && !stripeAvailable) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment Not Available'),
          content: const Text(
            'No payment methods have been configured yet. Please contact the administrator.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Show payment method selection dialog
    _showPaymentMethodDialog(
      context,
      package: package,
      userId: userId,
      paypalAvailable: paypalAvailable,
      stripeAvailable: stripeAvailable,
    );
  }

  Future<void> _processGooglePlayPackagePayment(
    BuildContext context,
    CreditPackageModel package,
    String userId,
  ) async {
    try {
      final billing = ref.read(googlePlayBillingServiceProvider);
      final result = await billing.purchaseCreditPackage(
        package: package,
        userId: userId,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.alreadyProcessed
                ? '${package.credits} credits were already applied to your account.'
                : 'Successfully purchased ${package.credits} credits with Google Play!',
          ),
          backgroundColor: Colors.green,
        ),
      );
      ref.invalidate(userSubscriptionProvider);
      ref.invalidate(transactionHistoryProvider(userId));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Google Play purchase failed: $error'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showPaymentMethodDialog(
    BuildContext context, {
    required CreditPackageModel package,
    required String userId,
    required bool paypalAvailable,
    required bool stripeAvailable,
  }) {
    final scheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Payment Method',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Purchase ${package.credits} credits for \$${package.price.toStringAsFixed(2)}',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
              ),
              const SizedBox(height: 24),
              if (stripeAvailable)
                _PaymentMethodTile(
                  icon: Icons.credit_card,
                  title: 'Credit/Debit Card',
                  subtitle: 'Pay securely with Stripe',
                  color: const Color(0xFF635BFF),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processStripePayment(context, package, userId);
                  },
                ),
              if (stripeAvailable && paypalAvailable) const SizedBox(height: 12),
              if (paypalAvailable)
                _PaymentMethodTile(
                  icon: Icons.account_balance_wallet,
                  title: 'PayPal',
                  subtitle: 'Pay with your PayPal account',
                  color: const Color(0xFF003087),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processPayPalPayment(context, package, userId);
                  },
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _processStripePayment(
      BuildContext context, CreditPackageModel package, String userId) {
    final stripe = ref.read(stripeServiceProvider);

    stripe.purchasePackage(
      context: context,
      package: package,
      userId: userId,
      onSuccess: (transactionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purchased ${package.credits} credits!'),
            backgroundColor: Colors.green,
          ),
        );
        ref.invalidate(userSubscriptionProvider);
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  void _processPayPalPayment(
      BuildContext context, CreditPackageModel package, String userId) {
    final paypal = ref.read(paypalServiceProvider);

    paypal.purchasePackage(
      context: context,
      package: package,
      userId: userId,
      onSuccess: (transactionId) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully purchased ${package.credits} credits!'),
            backgroundColor: Colors.green,
          ),
        );
        // Refresh subscription data
        ref.invalidate(userSubscriptionProvider);
      },
      onError: (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Purchase failed: $error'),
            backgroundColor: Colors.red,
          ),
        );
      },
    );
  }

  void _showTransactionHistory(
      BuildContext context, WidgetRef ref, String userId) {
    final transactions = ref.watch(transactionHistoryProvider(userId));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: transactions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
              data: (txList) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Transaction History',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: txList.isEmpty
                          ? const Center(child: Text('No transactions yet'))
                          : ListView.builder(
                              controller: scrollController,
                              itemCount: txList.length,
                              itemBuilder: (context, index) {
                                final tx = txList[index];
                                return ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: tx.isCredit
                                        ? Colors.green.shade100
                                        : Colors.red.shade100,
                                    child: Icon(
                                      tx.isCredit ? Icons.add : Icons.remove,
                                      color: tx.isCredit
                                          ? Colors.green.shade700
                                          : Colors.red.shade700,
                                    ),
                                  ),
                                  title: Text(
                                      tx.description ?? tx.transactionType),
                                  subtitle: Text(
                                    _formatDate(tx.createdAt),
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 12,
                                    ),
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${tx.isCredit ? '+' : ''}${tx.amount}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: tx.isCredit
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                          fontSize: 16,
                                        ),
                                      ),
                                      Text(
                                        'Balance: ${tx.balanceAfter}',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}

class _CreditUsageCard extends StatelessWidget {
  const _CreditUsageCard();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const costs = <(String, String)>[
      ('Notebook chat', '${CreditCosts.notebookChat} cr'),
      ('Web search', '${CreditCosts.webSearch} cr'),
      ('Code review', '${CreditCosts.codeReview} cr'),
      ('Deep research', '${CreditCosts.deepResearch} cr'),
      ('Deep depth', '${CreditCosts.deepResearch * 2} cr'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How credits are used',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Only model-powered work consumes credits. Memory storage, retrieval, live collaboration, and saving research are free. Failed operations are refunded.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: costs
                .map(
                  (item) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${item.$1} · ${item.$2}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _CreditBalanceCard extends StatelessWidget {
  final int currentCredits;
  final int creditsPerMonth;
  final DateTime? nextRenewalDate;

  const _CreditBalanceCard({
    required this.currentCredits,
    required this.creditsPerMonth,
    this.nextRenewalDate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available Credits',
            style: TextStyle(
              color: scheme.onPrimary.withValues(alpha: 0.8),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentCredits.toString(),
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (nextRenewalDate != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.refresh,
                    size: 14,
                    color: scheme.onPrimary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '+$creditsPerMonth credits ${_formatRenewalDate(nextRenewalDate!)}',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _formatRenewalDate(DateTime date) {
    final now = DateTime.now();
    final difference = date.difference(now).inDays;

    if (difference == 0) return 'today';
    if (difference == 1) return 'tomorrow';
    return 'in $difference days';
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final String planName;
  final double planPrice;
  final int creditsPerMonth;
  final String status;
  final bool isFreePlan;

  const _CurrentPlanCard({
    required this.planName,
    required this.planPrice,
    required this.creditsPerMonth,
    required this.status,
    required this.isFreePlan,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isFree = isFreePlan;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Current Plan',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        isFree ? Colors.green.shade100 : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isFree ? 'FREE' : 'PREMIUM',
                    style: TextStyle(
                      color:
                          isFree ? Colors.green.shade700 : Colors.blue.shade700,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              planName,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!isFree) ...[
                  Text(
                    '\$${planPrice.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '/month',
                    style: TextStyle(
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  '$creditsPerMonth credits/mo',
                  style: TextStyle(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditPackageCard extends StatelessWidget {
  final CreditPackageModel package;
  final bool purchaseEnabled;
  final String priceLabel;
  final String buttonLabel;
  final VoidCallback onPurchase;

  const _CreditPackageCard({
    required this.package,
    required this.purchaseEnabled,
    required this.priceLabel,
    required this.buttonLabel,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
      child: Container(
        width: (MediaQuery.of(context).size.width - 48) / 2,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              package.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${package.credits} credits',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              priceLabel,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '\$${package.pricePerCredit.toStringAsFixed(4)}/credit',
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: purchaseEnabled ? onPurchase : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.payment, size: 18),
                    const SizedBox(width: 6),
                    Text(buttonLabel),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _PaymentMethodTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.72),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: scheme.onSurface.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSubscriptionView extends StatefulWidget {
  final Future<void> Function() onRetry;

  const _NoSubscriptionView({required this.onRetry});

  @override
  State<_NoSubscriptionView> createState() => _NoSubscriptionViewState();
}

class _NoSubscriptionViewState extends State<_NoSubscriptionView> {
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _autoCreateSubscription();
  }

  Future<void> _autoCreateSubscription() async {
    setState(() => _loading = true);
    try {
      await widget.onRetry();
    } catch (e) {
      // Ignore errors, will show retry button
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Setting up your subscription...'),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.credit_card_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No subscription found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'We couldn\'t find or create a subscription for your account.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _autoCreateSubscription,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailablePlansSection extends ConsumerWidget {
  final String currentPlanId;
  final String? userId;

  const _AvailablePlansSection({
    required this.currentPlanId,
    this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plansAsync = ref.watch(subscriptionPlansProvider);
    final googlePlayCatalog =
        supportsGooglePlayBilling ? ref.watch(googlePlayCatalogProvider) : null;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Available Plans',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => ref.invalidate(subscriptionPlansProvider),
                tooltip: 'Refresh plans',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        plansAsync.when(
          loading: () => const SizedBox(
            height: 200,
            child: Center(
              child: CircularProgressIndicator(),
            ),
          ),
          error: (error, stack) => Container(
            height: 100,
            padding: const EdgeInsets.all(16),
            alignment: Alignment.center,
            child: Text('Error loading plans: $error',
                style: const TextStyle(color: Colors.red)),
          ),
          data: (plans) {
            if (plans.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text('No plans available'),
                ),
              );
            }

            String? currentPlanProductId;
            for (final plan in plans) {
              if (plan['id'].toString() == currentPlanId) {
                currentPlanProductId =
                    plan['google_play_product_id'] as String?;
                break;
              }
            }
            final playCatalog = googlePlayCatalog?.valueOrNull;
            final canUseGooglePlay =
                !supportsGooglePlayBilling || playCatalog?.canPurchase == true;

            return SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: plans.length,
                itemBuilder: (context, index) {
                  final plan = plans[index];
                  final planId = plan['id'].toString();
                  final isCurrentPlan = planId == currentPlanId;
                  final isFree = (plan['is_free_plan'] as bool?) ?? false;

                  // Safely parse credits
                  int creditsPerMonth = 0;
                  if (plan['credits_per_month'] is int) {
                    creditsPerMonth = plan['credits_per_month'] as int;
                  } else if (plan['credits_per_month'] is String) {
                    creditsPerMonth =
                        int.tryParse(plan['credits_per_month']) ?? 0;
                  }

                  // Safely parse price
                  double price = 0.0;
                  if (plan['price'] is num) {
                    price = (plan['price'] as num).toDouble();
                  } else if (plan['price'] is String) {
                    price = double.tryParse(plan['price']) ?? 0.0;
                  }
                  final playProductId =
                      plan['google_play_product_id'] as String?;
                  final playStorePrice = playProductId == null
                      ? null
                      : playCatalog?.productDetailsById[playProductId]?.price;
                  final displayPrice = supportsGooglePlayBilling
                      ? playStorePrice ?? '\$${price.toStringAsFixed(2)}/mo'
                      : '\$${price.toStringAsFixed(2)}/mo';

                  return Container(
                    width: 180,
                    margin: const EdgeInsets.only(right: 12),
                    child: Card(
                      elevation: isCurrentPlan ? 4 : 1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: isCurrentPlan
                              ? scheme.primary
                              : scheme.outline.withValues(alpha: 0.2),
                          width: isCurrentPlan ? 2 : 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    plan['name'] as String? ?? 'Plan',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isCurrentPlan)
                                  Icon(
                                    Icons.check_circle,
                                    color: scheme.primary,
                                    size: 20,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$creditsPerMonth',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: scheme.primary,
                              ),
                            ),
                            Text(
                              'credits/month',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              isFree ? 'FREE' : displayPrice,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isFree ? Colors.green : scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (isCurrentPlan)
                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Current',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )
                            else if (!isFree)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: supportsGooglePlayBilling &&
                                          !canUseGooglePlay
                                      ? null
                                      : () => _showUpgradeDialog(
                                            context,
                                            ref,
                                            plan,
                                            price,
                                            creditsPerMonth,
                                            userId,
                                            currentPlanProductId,
                                          ),
                                  style: ElevatedButton.styleFrom(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  child: Text(
                                    supportsGooglePlayBilling
                                        ? 'Upgrade with Play'
                                        : 'Upgrade',
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }

  void _showUpgradeDialog(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> plan,
    double price,
    int creditsPerMonth,
    String? userId,
    String? currentPlanProductId,
  ) {
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to upgrade')),
      );
      return;
    }

    final scheme = Theme.of(context).colorScheme;
    final planId = plan['id'].toString();
    final planName = plan['name'] as String? ?? 'Plan';
    final playProductId = plan['google_play_product_id'] as String?;
    final playCatalog =
        supportsGooglePlayBilling ? ref.read(googlePlayCatalogProvider) : null;
    final playPrice = playProductId == null
        ? null
        : playCatalog?.valueOrNull?.productDetailsById[playProductId]?.price;

    showModalBottomSheet(
      context: context,
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Upgrade to $planName',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Credits per month'),
                        Text(
                          '$creditsPerMonth',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Price'),
                        Text(
                          playPrice ?? '\$${price.toStringAsFixed(2)}/month',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (supportsGooglePlayBilling) ...[
                Text(
                  'Billing Provider',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _PaymentMethodTile(
                  icon: Icons.play_circle_fill_rounded,
                  title: 'Google Play',
                  subtitle:
                      'Purchase and manage this plan through Google Play',
                  color: const Color(0xFF34A853),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processGooglePlayUpgrade(
                      context,
                      ref,
                      plan,
                      userId,
                      currentPlanProductId,
                    );
                  },
                ),
              ] else ...[
                Text(
                  'Select Payment Method',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _PaymentMethodTile(
                  icon: Icons.credit_card,
                  title: 'Credit/Debit Card',
                  subtitle: 'Pay securely with Stripe',
                  color: const Color(0xFF635BFF),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processStripeUpgrade(context, ref, planId, price, userId);
                  },
                ),
                const SizedBox(height: 12),
                _PaymentMethodTile(
                  icon: Icons.account_balance_wallet,
                  title: 'PayPal',
                  subtitle: 'Pay with your PayPal account',
                  color: const Color(0xFF003087),
                  onTap: () {
                    Navigator.pop(ctx);
                    _processPayPalUpgrade(context, ref, planId, price, userId);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processGooglePlayUpgrade(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> plan,
    String userId,
    String? currentPlanProductId,
  ) async {
    try {
      final billing = ref.read(googlePlayBillingServiceProvider);
      await billing.purchaseSubscription(
        plan: plan,
        userId: userId,
        currentPlanProductId: currentPlanProductId,
      );

      if (!context.mounted) return;
      ref.invalidate(userSubscriptionProvider);
      ref.invalidate(subscriptionPlansProvider);
      ref.invalidate(transactionHistoryProvider(userId));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully upgraded to ${plan['name'] ?? 'your new plan'} with Google Play!',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upgrade failed: $error')),
      );
    }
  }

  Future<void> _processStripeUpgrade(
    BuildContext context,
    WidgetRef ref,
    String planId,
    double price,
    String userId,
  ) async {
    final stripe = ref.read(stripeServiceProvider);

    if (!stripe.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stripe is not configured')),
      );
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Process payment
      final transactionId = await stripe.processPayment(
        context: context,
        planId: planId,
        amount: price,
        currency: 'USD',
        description: 'Plan Upgrade',
      );

      if (context.mounted) Navigator.pop(context); // Close loading

      if (transactionId != null) {
        // Upgrade the plan
        final service = ref.read(subscriptionServiceProvider);
        await service.upgradePlan(
          userId: userId,
          newPlanId: planId,
          paymentTransactionId: transactionId,
        );

        ref.invalidate(userSubscriptionProvider);
        ref.invalidate(subscriptionPlansProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully upgraded your plan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upgrade failed: $e')),
        );
      }
    }
  }

  Future<void> _processPayPalUpgrade(
    BuildContext context,
    WidgetRef ref,
    String planId,
    double price,
    String userId,
  ) async {
    final paypal = ref.read(paypalServiceProvider);

    if (!paypal.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PayPal is not configured')),
      );
      return;
    }

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      // Process payment
      final transactionId = await paypal.processPayment(
        context: context,
        amount: price,
        currency: 'USD',
        description: 'Plan Upgrade',
      );

      if (context.mounted) Navigator.pop(context); // Close loading

      if (transactionId != null) {
        // Upgrade the plan
        final service = ref.read(subscriptionServiceProvider);
        await service.upgradePlan(
          userId: userId,
          newPlanId: planId,
          paymentTransactionId: transactionId,
        );

        ref.invalidate(userSubscriptionProvider);
        ref.invalidate(subscriptionPlansProvider);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Successfully upgraded your plan!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Close loading if still open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upgrade failed: $e')),
        );
      }
    }
  }
}
