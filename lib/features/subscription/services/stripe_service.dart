import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import '../models/credit_package_model.dart';
import 'subscription_service.dart';

class StripeService {
  final SubscriptionService _subscriptionService;

  String? _publishableKey;
  bool _testMode = true;
  bool _initialized = false;

  StripeService(this._subscriptionService, dynamic _);

  /// Initialize Stripe with credentials from backend
  Future<void> initialize() async {
    try {
      developer.log('Stripe: Fetching config from backend...',
          name: 'StripeService');

      final data = await _subscriptionService.getPaymentConfig();
      final stripeConfig = data['config']?['stripe'];

      if (stripeConfig != null) {
        _initialized = false;
        _publishableKey = stripeConfig['publishableKey'];
        _testMode = stripeConfig['testMode'] ?? true;

        if (stripeConfig['configured'] == true &&
            _publishableKey != null &&
            _publishableKey!.isNotEmpty) {
          Stripe.publishableKey = _publishableKey!;
          await Stripe.instance.applySettings();
          _initialized = true;
        }

        developer.log(
          'Stripe initialized from backend: publishableKey=${_publishableKey != null && _publishableKey!.isNotEmpty}, testMode=$_testMode',
          name: 'StripeService',
        );
      } else {
        developer.log('Stripe: No config in response', name: 'StripeService');
      }
    } catch (e) {
      developer.log('Failed to initialize Stripe: $e', name: 'StripeService');
    }
  }

  bool get isConfigured => _initialized;

  Future<Map<String, dynamic>?> _createPaymentIntent({
    String? packageId,
    double? amount,
    required String currency,
    String? description,
  }) async {
    try {
      if (packageId == null && amount == null) return null;

      final result = await _subscriptionService.createStripePaymentIntent(
        packageId: packageId,
        amount: amount,
        currency: currency,
        description: description,
      );
      if (result['success'] == true) {
        return result;
      }
      return null;
    } catch (e) {
      developer.log('Error creating payment intent: $e', name: 'StripeService');
      return null;
    }
  }

  /// Process payment for a credit package
  Future<void> purchasePackage({
    required BuildContext context,
    required CreditPackageModel package,
    required String userId,
    required Function(String transactionId) onSuccess,
    required Function(String error) onError,
  }) async {
    if (!isConfigured) {
      onError(
          'Stripe is not configured. Please add credentials in admin panel.');
      return;
    }

    // Capture theme color before async operations
    final primaryColor = Theme.of(context).colorScheme.primary;

    try {
      // Create payment intent
      final paymentIntent = await _createPaymentIntent(
        currency: 'USD',
        packageId: package.id,
        description: 'Credit purchase',
      );

      if (paymentIntent == null) {
        onError('Failed to create payment. Please try again.');
        return;
      }

      final clientSecret = paymentIntent['clientSecret'] as String;

      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'NoteClaw',
          style: ThemeMode.system,
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: primaryColor,
            ),
            shapes: const PaymentSheetShape(
              borderRadius: 12,
            ),
          ),
        ),
      );

      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      // Payment successful - add credits
      final paymentIntentId = paymentIntent['paymentIntentId'] as String;

      final success = await _subscriptionService.addCredits(
        userId: userId,
        amount: package.credits,
        packageId: package.id,
        transactionId: paymentIntentId,
        paymentMethod: 'stripe',
      );

      if (success) {
        onSuccess(paymentIntentId);
      } else {
        onError('Payment succeeded but failed to add credits');
      }
    } on StripeException catch (e) {
      developer.log('Stripe error: ${e.error.message}', name: 'StripeService');

      if (e.error.code == FailureCode.Canceled) {
        onError('Payment was cancelled');
      } else {
        onError(e.error.message ?? 'Payment failed');
      }
    } catch (e) {
      developer.log('Payment error: $e', name: 'StripeService');
      onError('An unexpected error occurred: $e');
    }
  }

  /// Process a generic payment (for plan upgrades)
  Future<bool> processPayment({
    required BuildContext context,
    required double amount,
    required String currency,
    required String description,
  }) async {
    if (!isConfigured) {
      throw Exception('Stripe is not configured');
    }

    final primaryColor = Theme.of(context).colorScheme.primary;

    try {
      // Create payment intent
      final paymentIntent = await _createPaymentIntent(
        currency: currency,
        amount: amount,
        description: description,
      );

      if (paymentIntent == null) {
        throw Exception('Failed to create payment intent');
      }

      final clientSecret = paymentIntent['clientSecret'] as String;

      // Initialize payment sheet
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'NoteClaw',
          style: ThemeMode.system,
          appearance: PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(
              primary: primaryColor,
            ),
            shapes: const PaymentSheetShape(
              borderRadius: 12,
            ),
          ),
        ),
      );

      // Present payment sheet
      await Stripe.instance.presentPaymentSheet();

      return true;
    } on StripeException catch (e) {
      developer.log('Stripe error: ${e.error.message}', name: 'StripeService');
      if (e.error.code == FailureCode.Canceled) {
        return false;
      }
      throw Exception(e.error.message ?? 'Payment failed');
    }
  }
}
