import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/custom_auth_service.dart';
import '../services/subscription_service.dart';
import '../services/google_play_billing_service.dart';
import '../models/subscription_model.dart';
import '../models/credit_package_model.dart';
import '../models/credit_transaction_model.dart';

// Current User Subscription Provider
final userSubscriptionProvider =
    StreamProvider<SubscriptionModel?>((ref) async* {
  final authState = ref.watch(customAuthStateProvider);
  final user = authState.user;

  if (user == null) {
    developer.log('[SUB] No user logged in (authState: ${authState.status})',
        name: 'SubscriptionProvider');
    yield null;
    return;
  }

  final service = ref.watch(subscriptionServiceProvider);
  final userId = user.uid;
  developer.log('[SUB] Fetching subscription for user: $userId (${user.email})',
      name: 'SubscriptionProvider');

  // Initial fetch
  try {
    final subscription = await service.getUserSubscription(userId);
    developer.log(
        '[SUB] Got subscription: ${subscription?.planName ?? "null"}, credits: ${subscription?.currentCredits ?? 0}',
        name: 'SubscriptionProvider');
    yield subscription;
  } catch (e, stack) {
    developer.log('[SUB] Error fetching subscription: $e',
        name: 'SubscriptionProvider', error: e, stackTrace: stack);
    yield null;
  }

  // Refresh every 30 seconds
  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    final currentAuthState = ref.read(customAuthStateProvider);
    final currentUser = currentAuthState.user;
    if (currentUser == null) return;
    try {
      final subscription = await service.getUserSubscription(currentUser.uid);
      developer.log(
          '[SUB] Refreshed subscription: ${subscription?.currentCredits ?? 0} credits',
          name: 'SubscriptionProvider');
      yield subscription;
    } catch (e) {
      developer.log('[SUB] Error refreshing subscription: $e',
          name: 'SubscriptionProvider');
    }
  }
});

// Credit Balance Provider (simplified access)
final creditBalanceProvider = Provider<int>((ref) {
  final subscriptionAsync = ref.watch(userSubscriptionProvider);

  // Return the actual credits if loaded, otherwise return a high number
  // to avoid blocking users while subscription is loading
  return subscriptionAsync.when(
    data: (subscription) => subscription?.currentCredits ?? 0,
    loading: () => 999999, // Don't block while loading
    error: (_, __) => 0,
  );
});

// Provider that indicates if subscription is still loading
final isSubscriptionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(userSubscriptionProvider).isLoading;
});

// Active Credit Packages Provider
final creditPackagesProvider =
    FutureProvider<List<CreditPackageModel>>((ref) async {
  final service = ref.watch(subscriptionServiceProvider);
  return await service.getActivePackages();
});

// Transaction History Provider
final transactionHistoryProvider =
    FutureProvider.family<List<CreditTransactionModel>, String>(
        (ref, userId) async {
  final service = ref.watch(subscriptionServiceProvider);
  return await service.getTransactionHistory(userId);
});

// Check if user has enough credits
final hasEnoughCreditsProvider =
    FutureProvider.family<bool, int>((ref, required) async {
  final authState = ref.watch(customAuthStateProvider);
  final user = authState.user;
  if (user == null) return false;

  final service = ref.watch(subscriptionServiceProvider);
  return await service.hasEnoughCredits(user.uid, required);
});

// Available subscription plans. Refresh periodically so pricing, features,
// and quotas changed by an administrator appear without restarting the app.
final subscriptionPlansProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) async* {
  final service = ref.watch(subscriptionServiceProvider);
  yield await service.getPublicPlans();

  await for (final _ in Stream.periodic(const Duration(seconds: 30))) {
    yield await service.getPublicPlans();
  }
});

final googlePlayCatalogProvider =
    FutureProvider<GooglePlayBillingCatalog>((ref) async {
  final billing = ref.watch(googlePlayBillingServiceProvider);
  final plans = await ref.watch(subscriptionPlansProvider.future);
  final packages = await ref.watch(creditPackagesProvider.future);
  return billing.loadCatalog(plans: plans, packages: packages);
});
