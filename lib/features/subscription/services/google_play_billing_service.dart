import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import '../models/credit_package_model.dart';
import 'subscription_service.dart';

final googlePlayBillingServiceProvider = Provider<GooglePlayBillingService>(
  (ref) {
    final service = GooglePlayBillingService(ref);
    ref.onDispose(service.dispose);
    return service;
  },
);

bool get supportsGooglePlayBilling =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class GooglePlayBillingCatalog {
  final bool isStoreAvailable;
  final bool isBackendConfigured;
  final String? packageName;
  final Map<String, ProductDetails> productDetailsById;
  final Set<String> missingProductIds;

  const GooglePlayBillingCatalog({
    required this.isStoreAvailable,
    required this.isBackendConfigured,
    required this.packageName,
    required this.productDetailsById,
    required this.missingProductIds,
  });

  bool get canPurchase =>
      isStoreAvailable && isBackendConfigured && productDetailsById.isNotEmpty;
}

class GooglePlayPurchaseResult {
  final String transactionId;
  final int? newBalance;
  final bool alreadyProcessed;

  const GooglePlayPurchaseResult({
    required this.transactionId,
    this.newBalance,
    this.alreadyProcessed = false,
  });
}

enum _PendingPurchaseType {
  subscription,
  creditPackage,
}

class _PendingGooglePlayPurchase {
  final _PendingPurchaseType type;
  final String userId;
  final String internalId;
  final String productId;
  final bool consumable;

  const _PendingGooglePlayPurchase({
    required this.type,
    required this.userId,
    required this.internalId,
    required this.productId,
    required this.consumable,
  });
}

class GooglePlayBillingService {
  final Ref ref;
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Map<String, ProductDetails> _productDetailsById = {};
  final Map<String, GooglePlayPurchaseDetails> _ownedPurchasesByProductId = {};

  bool _initialized = false;
  bool _storeAvailable = false;
  bool _backendConfigured = false;
  String? _packageName;

  Completer<GooglePlayPurchaseResult>? _purchaseCompleter;
  _PendingGooglePlayPurchase? _pendingPurchase;

  GooglePlayBillingService(this.ref);

  Future<void> initialize() async {
    if (!supportsGooglePlayBilling || _initialized) return;

    final paymentConfig =
        await ref.read(subscriptionServiceProvider).getPaymentConfig();
    final googlePlayConfig =
        paymentConfig['config']?['googlePlay'] as Map<String, dynamic>?;

    _backendConfigured = googlePlayConfig?['configured'] == true;
    _packageName = googlePlayConfig?['packageName'] as String?;
    _storeAvailable = await _inAppPurchase.isAvailable();

    _purchaseSubscription ??= _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'Google Play purchase stream error: $error',
          name: 'GooglePlayBillingService',
          error: error,
          stackTrace: stackTrace,
        );
        _completePendingPurchaseError(
          Exception('Google Play purchase stream failed: $error'),
        );
      },
    );

    _initialized = true;
  }

  Future<GooglePlayBillingCatalog> loadCatalog({
    required List<Map<String, dynamic>> plans,
    required List<CreditPackageModel> packages,
  }) async {
    await initialize();

    if (!supportsGooglePlayBilling) {
      return const GooglePlayBillingCatalog(
        isStoreAvailable: false,
        isBackendConfigured: false,
        packageName: null,
        productDetailsById: {},
        missingProductIds: {},
      );
    }

    final productIds = <String>{};
    for (final plan in plans) {
      final productId = (plan['google_play_product_id'] as String?)?.trim();
      if (productId != null && productId.isNotEmpty) {
        productIds.add(productId);
      }
    }
    for (final pkg in packages) {
      final productId = pkg.googlePlayProductId?.trim();
      if (productId != null && productId.isNotEmpty) {
        productIds.add(productId);
      }
    }

    if (!_storeAvailable || productIds.isEmpty) {
      return GooglePlayBillingCatalog(
        isStoreAvailable: _storeAvailable,
        isBackendConfigured: _backendConfigured,
        packageName: _packageName,
        productDetailsById: Map.unmodifiable(_productDetailsById),
        missingProductIds: productIds,
      );
    }

    final response = await _inAppPurchase.queryProductDetails(productIds);

    if (response.error != null) {
      throw Exception(
        'Failed to load Google Play products: ${response.error!.message}',
      );
    }

    _productDetailsById
      ..clear()
      ..addEntries(
        response.productDetails.map((product) => MapEntry(product.id, product)),
      );

    await _restorePurchasesSilently();

    return GooglePlayBillingCatalog(
      isStoreAvailable: _storeAvailable,
      isBackendConfigured: _backendConfigured,
      packageName: _packageName,
      productDetailsById: Map.unmodifiable(_productDetailsById),
      missingProductIds:
          productIds.difference(_productDetailsById.keys.toSet()),
    );
  }

  Future<GooglePlayPurchaseResult> purchaseCreditPackage({
    required CreditPackageModel package,
    required String userId,
  }) async {
    final productId = package.googlePlayProductId?.trim();
    if (productId == null || productId.isEmpty) {
      throw Exception('This credit package is not mapped to Google Play yet.');
    }

    return _startPurchase(
      pendingPurchase: _PendingGooglePlayPurchase(
        type: _PendingPurchaseType.creditPackage,
        userId: userId,
        internalId: package.id,
        productId: productId,
        consumable: true,
      ),
      starter: (productDetails) async {
        final purchaseParam = GooglePlayPurchaseParam(
          productDetails: _requireGooglePlayProductDetails(productDetails),
          applicationUserName: userId,
        );

        return _inAppPurchase.buyConsumable(
          purchaseParam: purchaseParam,
          autoConsume: false,
        );
      },
    );
  }

  Future<GooglePlayPurchaseResult> purchaseSubscription({
    required Map<String, dynamic> plan,
    required String userId,
    String? currentPlanProductId,
  }) async {
    final productId = (plan['google_play_product_id'] as String?)?.trim();
    if (productId == null || productId.isEmpty) {
      throw Exception(
          'This subscription plan is not mapped to Google Play yet.');
    }

    await _restorePurchasesSilently();

    return _startPurchase(
      pendingPurchase: _PendingGooglePlayPurchase(
        type: _PendingPurchaseType.subscription,
        userId: userId,
        internalId: plan['id'].toString(),
        productId: productId,
        consumable: false,
      ),
      starter: (productDetails) async {
        final oldPurchase = currentPlanProductId == null
            ? null
            : _ownedPurchasesByProductId[currentPlanProductId];

        final purchaseParam = GooglePlayPurchaseParam(
          productDetails: _requireGooglePlayProductDetails(productDetails),
          applicationUserName: userId,
          changeSubscriptionParam: oldPurchase == null
              ? null
              : ChangeSubscriptionParam(
                  oldPurchaseDetails: oldPurchase,
                  replacementMode: ReplacementMode.withTimeProration,
                ),
          offerToken:
              _requireGooglePlayProductDetails(productDetails).offerToken,
        );

        return _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
      },
    );
  }

  Future<void> dispose() async {
    await _purchaseSubscription?.cancel();
  }

  Future<GooglePlayPurchaseResult> _startPurchase({
    required _PendingGooglePlayPurchase pendingPurchase,
    required Future<bool> Function(ProductDetails productDetails) starter,
  }) async {
    await initialize();
    if (!_storeAvailable) {
      throw Exception('Google Play Billing is not available on this device.');
    }
    if (!_backendConfigured) {
      throw Exception(
        'Google Play Billing is not fully configured on the backend yet.',
      );
    }
    if (_purchaseCompleter != null) {
      throw Exception('Another purchase is already in progress.');
    }

    final productDetails = _productDetailsById[pendingPurchase.productId];
    if (productDetails == null) {
      throw Exception(
        'Google Play product ${pendingPurchase.productId} is not available in this build.',
      );
    }

    _pendingPurchase = pendingPurchase;
    _purchaseCompleter = Completer<GooglePlayPurchaseResult>();
    final completer = _purchaseCompleter!;

    final started = await starter(productDetails);
    if (!started) {
      _pendingPurchase = null;
      _purchaseCompleter = null;
      throw Exception('Google Play did not start the purchase flow.');
    }

    return completer.future;
  }

  Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      if (purchase is GooglePlayPurchaseDetails &&
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored)) {
        _ownedPurchasesByProductId[purchase.productID] = purchase;
      }

      final pending = _pendingPurchase;
      if (pending == null || purchase.productID != pending.productId) {
        continue;
      }

      switch (purchase.status) {
        case PurchaseStatus.pending:
          continue;
        case PurchaseStatus.error:
          _completePendingPurchaseError(
            Exception(
                purchase.error?.message ?? 'Google Play purchase failed.'),
          );
          break;
        case PurchaseStatus.canceled:
          _completePendingPurchaseError(
            Exception('Google Play purchase was cancelled.'),
          );
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verifyAndFinishPurchase(purchase, pending);
          break;
      }
    }
  }

  Future<void> _verifyAndFinishPurchase(
    PurchaseDetails purchase,
    _PendingGooglePlayPurchase pending,
  ) async {
    try {
      final verificationResult =
          await ref.read(subscriptionServiceProvider).verifyGooglePlayPurchase(
                purchaseType: pending.type == _PendingPurchaseType.subscription
                    ? 'subscription'
                    : 'credit_package',
                internalId: pending.internalId,
                productId: pending.productId,
                purchaseToken: purchase.verificationData.serverVerificationData,
                purchaseId: purchase.purchaseID,
              );

      if (pending.consumable && purchase is GooglePlayPurchaseDetails) {
        final addition = _inAppPurchase
            .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
        await addition.consumePurchase(purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }

      final completer = _purchaseCompleter;
      _purchaseCompleter = null;
      _pendingPurchase = null;
      completer?.complete(
        GooglePlayPurchaseResult(
          transactionId: verificationResult['transactionId']?.toString() ??
              purchase.purchaseID ??
              pending.productId,
          newBalance: verificationResult['newBalance'] as int?,
          alreadyProcessed: verificationResult['alreadyProcessed'] == true,
        ),
      );
    } catch (error, stackTrace) {
      developer.log(
        'Failed to verify Google Play purchase: $error',
        name: 'GooglePlayBillingService',
        error: error,
        stackTrace: stackTrace,
      );
      _completePendingPurchaseError(
        Exception('Failed to verify Google Play purchase: $error'),
      );
    }
  }

  void _completePendingPurchaseError(Exception error) {
    final completer = _purchaseCompleter;
    _purchaseCompleter = null;
    _pendingPurchase = null;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(error);
    }
  }

  GooglePlayProductDetails _requireGooglePlayProductDetails(
    ProductDetails productDetails,
  ) {
    if (productDetails is GooglePlayProductDetails) {
      return productDetails;
    }
    throw Exception(
      'This purchase is not backed by Google Play product details.',
    );
  }

  Future<void> _restorePurchasesSilently() async {
    if (!supportsGooglePlayBilling) return;

    try {
      final addition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      final response = await addition.queryPastPurchases();
      for (final purchase in response.pastPurchases) {
        _ownedPurchasesByProductId[purchase.productID] = purchase;
      }
    } catch (error, stackTrace) {
      developer.log(
        'Failed to restore existing Google Play purchases: $error',
        name: 'GooglePlayBillingService',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
