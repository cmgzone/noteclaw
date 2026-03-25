import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_paypal_payment/flutter_paypal_payment.dart';
import '../models/credit_package_model.dart';
import '../services/subscription_service.dart';

class PayPalService {
  final SubscriptionService _subscriptionService;

  String? _clientId;
  String? _secretKey;
  bool _sandboxMode = true;

  PayPalService(this._subscriptionService);

  /// Initialize PayPal with credentials from backend
  Future<void> initialize() async {
    try {
      developer.log('PayPal: Fetching config from backend...',
          name: 'PayPalService');

      final data = await _subscriptionService.getPaymentConfig();
      final paypalConfig = data['config']?['paypal'];

      if (paypalConfig != null) {
        _clientId = paypalConfig['clientId'];
        _secretKey = null;
        _sandboxMode = paypalConfig['sandboxMode'] ?? true;

        developer.log(
          'PayPal initialized from backend: clientId=${_clientId != null && _clientId!.isNotEmpty}, secretKey=${_secretKey != null && _secretKey!.isNotEmpty}, sandbox=$_sandboxMode',
          name: 'PayPalService',
        );
      } else {
        developer.log('PayPal: No config in response', name: 'PayPalService');
      }
    } catch (e) {
      developer.log('Failed to initialize PayPal: $e', name: 'PayPalService');
    }
  }

  bool get isConfigured =>
      _clientId != null &&
      _clientId!.isNotEmpty &&
      _secretKey != null &&
      _secretKey!.isNotEmpty;

  /// Process payment for a credit package
  Future<void> purchasePackage({
    required BuildContext context,
    required CreditPackageModel package,
    required String userId,
    required Function(String transactionId) onSuccess,
    required Function(String error) onError,
  }) async {
    if (!isConfigured) {
      onError('PayPal is not configured yet. Please contact support.');
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext ctx) => PaypalCheckoutView(
          sandboxMode: _sandboxMode,
          clientId: _clientId!,
          secretKey: _secretKey!,
          transactions: [
            {
              "amount": {
                "total": package.price.toStringAsFixed(2),
                "currency": "USD",
                "details": {
                  "subtotal": package.price.toStringAsFixed(2),
                  "shipping": '0',
                  "shipping_discount": 0,
                }
              },
              "description":
                  "Purchase ${package.credits} credits - ${package.name}",
              "item_list": {
                "items": [
                  {
                    "name": package.name,
                    "quantity": 1,
                    "price": package.price.toStringAsFixed(2),
                    "currency": "USD"
                  }
                ],
              }
            }
          ],
          note: "Credit purchase for ${package.name}",
          onSuccess: (Map params) async {
            developer.log('Payment successful: $params', name: 'PayPalService');

            final paymentId = params["paymentId"] as String? ??
                'paypal_${DateTime.now().millisecondsSinceEpoch}';

            try {
              // Add credits via the subscription service
              final success = await _subscriptionService.addCredits(
                userId: userId,
                amount: package.credits,
                packageId: package.id,
                transactionId: paymentId,
                paymentMethod: 'paypal',
              );

              if (ctx.mounted) {
                Navigator.pop(ctx);
                if (success) {
                  onSuccess(paymentId);
                } else {
                  onError('Failed to add credits after payment');
                }
              }
            } catch (e) {
              developer.log('Error completing purchase: $e',
                  name: 'PayPalService');
              if (ctx.mounted) {
                Navigator.pop(ctx);
                onError('Payment succeeded but failed to add credits: $e');
              }
            }
          },
          onError: (error) {
            developer.log('Payment error: $error', name: 'PayPalService');
            Navigator.pop(ctx);
            onError(error.toString());
          },
          onCancel: () {
            developer.log('Payment cancelled', name: 'PayPalService');
            Navigator.pop(ctx);
            onError('Payment was cancelled');
          },
        ),
      ),
    );
  }

  /// Process a generic payment (for plan upgrades)
  /// Returns transaction ID on success, null on failure/cancel
  Future<String?> processPayment({
    required BuildContext context,
    required double amount,
    required String currency,
    required String description,
  }) async {
    if (!isConfigured) {
      throw Exception('PayPal is not configured');
    }

    String? transactionId;
    bool completed = false;
    String? errorMessage;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => PaypalCheckoutView(
          sandboxMode: _sandboxMode,
          clientId: _clientId!,
          secretKey: _secretKey!,
          transactions: [
            {
              'amount': {
                'total': amount.toStringAsFixed(2),
                'currency': currency,
              },
              'description': description,
            }
          ],
          note: description,
          onSuccess: (data) {
            developer.log('PayPal success: $data', name: 'PayPalService');
            transactionId =
                data['id'] ?? 'paypal_${DateTime.now().millisecondsSinceEpoch}';
            completed = true;
            Navigator.pop(ctx);
          },
          onError: (error) {
            developer.log('PayPal error: $error', name: 'PayPalService');
            errorMessage = error.toString();
            Navigator.pop(ctx);
          },
          onCancel: () {
            developer.log('PayPal cancelled', name: 'PayPalService');
            Navigator.pop(ctx);
          },
        ),
      ),
    );

    if (errorMessage != null) {
      throw Exception(errorMessage);
    }

    return completed ? transactionId : null;
  }
}
