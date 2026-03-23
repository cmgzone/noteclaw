import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_service.dart';
import '../models/subscription_model.dart';
import '../models/credit_package_model.dart';
import '../models/credit_transaction_model.dart';

final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService(ref);
});

class SubscriptionService {
  final Ref ref;

  SubscriptionService(this.ref);

  ApiService get _api => ref.read(apiServiceProvider);

  Future<Map<String, dynamic>> getPaymentConfig() async {
    return await _api.get<Map<String, dynamic>>('/subscriptions/payment-config');
  }

  Future<Map<String, dynamic>> createStripePaymentIntent({
    String? packageId,
    String? planId,
    double? amount,
    String currency = 'USD',
    String? description,
  }) async {
    return await _api.createStripePaymentIntent(
      packageId: packageId,
      planId: planId,
      amount: amount,
      currency: currency,
      description: description,
    );
  }

  /// Fetch user's current subscription
  Future<SubscriptionModel?> getUserSubscription(String userId) async {
    try {
      developer.log('[SUB_SVC] Calling getSubscription API...',
          name: 'SubscriptionService');
      final result = await _api.getSubscription();
      developer.log('[SUB_SVC] API response: $result',
          name: 'SubscriptionService');
      if (result == null) {
        developer.log('[SUB_SVC] Result is null', name: 'SubscriptionService');
        return null;
      }
      final model = SubscriptionModel.fromJson(result);
      developer.log(
          '[SUB_SVC] Parsed model: ${model.planName}, credits: ${model.currentCredits}',
          name: 'SubscriptionService');
      return model;
    } catch (e, stack) {
      developer.log('[SUB_SVC] Error: $e',
          name: 'SubscriptionService', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Get all active credit packages
  Future<List<CreditPackageModel>> getActivePackages() async {
    final result = await _api.getCreditPackages();
    return result.map((json) => CreditPackageModel.fromJson(json)).toList();
  }

  /// Get credit transaction history
  Future<List<CreditTransactionModel>> getTransactionHistory(
    String userId, {
    int limit = 50,
  }) async {
    final result = await _api.getTransactionHistory(limit: limit);
    return result.map((json) => CreditTransactionModel.fromJson(json)).toList();
  }

  /// Consume credits for a feature
  Future<bool> consumeCredits({
    required String userId,
    required int amount,
    required String feature,
    Map<String, dynamic>? metadata,
  }) async {
    final result = await _api.consumeCredits(
      amount: amount,
      feature: feature,
      metadata: metadata,
    );
    return result['success'] == true;
  }

  /// Check if user has enough credits
  Future<bool> hasEnoughCredits(String userId, int required) async {
    final balance = await getCreditBalance(userId);
    return balance >= required;
  }

  /// Get current credit balance
  Future<int> getCreditBalance(String userId) async {
    final result = await _api.getCreditBalance();
    return result['credits'] as int? ?? 0;
  }

  /// Add credits after purchase
  Future<bool> addCredits({
    required String userId,
    required int amount,
    required String packageId,
    required String transactionId,
    String paymentMethod = 'paypal',
  }) async {
    final result = await _api.addCredits(
      amount: amount,
      packageId: packageId,
      transactionId: transactionId,
      paymentMethod: paymentMethod,
    );
    return result['success'] == true;
  }

  Future<Map<String, dynamic>> verifyGooglePlayPurchase({
    required String purchaseType,
    required String internalId,
    required String productId,
    required String purchaseToken,
    String? purchaseId,
  }) async {
    return await _api.verifyGooglePlayPurchase(
      purchaseType: purchaseType,
      internalId: internalId,
      productId: productId,
      purchaseToken: purchaseToken,
      purchaseId: purchaseId,
    );
  }

  /// Check and renew subscription if needed
  Future<void> checkAndRenewSubscription(String userId) async {
    // Backend handles renewal automatically
    await getUserSubscription(userId);
  }

  /// Get all subscription plans
  Future<List<Map<String, dynamic>>> getAllPlans() async {
    return await _api.getAdminPlans();
  }

  /// Get active subscription plans (for mobile app)
  Future<List<Map<String, dynamic>>> getPublicPlans() async {
    return await _api.getSubscriptionPlans();
  }

  /// Create a new subscription for a user (if they don't have one)
  Future<void> createSubscriptionForUser(String userId) async {
    await _api.createSubscription();
  }

  /// Upgrade user to a new plan
  Future<bool> upgradePlan({
    required String userId,
    required String newPlanId,
    required String paymentTransactionId,
  }) async {
    final result = await _api.upgradePlan(
      planId: newPlanId,
      transactionId: paymentTransactionId,
    );
    return result['success'] == true;
  }

  /// Get a specific plan by ID
  Future<Map<String, dynamic>?> getPlanById(String planId) async {
    final plans = await getPublicPlans();
    try {
      return plans.firstWhere((p) => p['id'] == planId);
    } catch (e) {
      return null;
    }
  }
}
