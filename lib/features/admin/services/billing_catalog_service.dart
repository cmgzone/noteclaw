import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_service.dart';

final billingCatalogServiceProvider = Provider<BillingCatalogService>((ref) {
  return BillingCatalogService(ref);
});

class AdminSubscriptionPlan {
  final String id;
  final String name;
  final String? description;
  final int creditsPerMonth;
  final double price;
  final bool isActive;
  final bool isFreePlan;
  final String? googlePlayProductId;
  final int subscriberCount;

  const AdminSubscriptionPlan({
    required this.id,
    required this.name,
    this.description,
    required this.creditsPerMonth,
    required this.price,
    required this.isActive,
    required this.isFreePlan,
    this.googlePlayProductId,
    required this.subscriberCount,
  });

  factory AdminSubscriptionPlan.fromMap(Map<String, dynamic> map) {
    return AdminSubscriptionPlan(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString(),
      creditsPerMonth: _asInt(map['credits_per_month']) ?? 0,
      price: _asDouble(map['price']) ?? 0,
      isActive: map['is_active'] as bool? ?? true,
      isFreePlan: map['is_free_plan'] as bool? ?? false,
      googlePlayProductId: map['google_play_product_id']?.toString(),
      subscriberCount: _asInt(map['subscriber_count']) ?? 0,
    );
  }
}

class AdminCreditPackage {
  final String id;
  final String name;
  final int credits;
  final double price;
  final bool isActive;
  final String? googlePlayProductId;

  const AdminCreditPackage({
    required this.id,
    required this.name,
    required this.credits,
    required this.price,
    required this.isActive,
    this.googlePlayProductId,
  });

  factory AdminCreditPackage.fromMap(Map<String, dynamic> map) {
    return AdminCreditPackage(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      credits: _asInt(map['credits']) ?? 0,
      price: _asDouble(map['price']) ?? 0,
      isActive: map['is_active'] as bool? ?? true,
      googlePlayProductId: map['google_play_product_id']?.toString(),
    );
  }
}

class BillingCatalogService {
  final Ref ref;

  BillingCatalogService(this.ref);

  ApiService get _api => ref.read(apiServiceProvider);

  Future<List<AdminSubscriptionPlan>> listPlans() async {
    final result = await _api.getAdminSubscriptionPlans();
    return result.map(AdminSubscriptionPlan.fromMap).toList();
  }

  Future<AdminSubscriptionPlan> createPlan({
    required String name,
    String? description,
    required int creditsPerMonth,
    required double price,
    required bool isActive,
    required bool isFreePlan,
    String? googlePlayProductId,
  }) async {
    final result = await _api.createAdminSubscriptionPlan({
      'name': name,
      'description': description,
      'creditsPerMonth': creditsPerMonth,
      'price': price,
      'isActive': isActive,
      'isFreePlan': isFreePlan,
      'googlePlayProductId': googlePlayProductId,
    });
    return AdminSubscriptionPlan.fromMap(result);
  }

  Future<AdminSubscriptionPlan> updatePlan({
    required String id,
    required String name,
    String? description,
    required int creditsPerMonth,
    required double price,
    required bool isActive,
    required bool isFreePlan,
    String? googlePlayProductId,
  }) async {
    final result = await _api.updateAdminSubscriptionPlan(id, {
      'name': name,
      'description': description,
      'creditsPerMonth': creditsPerMonth,
      'price': price,
      'isActive': isActive,
      'isFreePlan': isFreePlan,
      'googlePlayProductId': googlePlayProductId,
    });
    return AdminSubscriptionPlan.fromMap(result);
  }

  Future<void> deletePlan(String id) async {
    await _api.deleteAdminSubscriptionPlan(id);
  }

  Future<List<AdminCreditPackage>> listPackages() async {
    final result = await _api.getAdminCreditPackages();
    return result.map(AdminCreditPackage.fromMap).toList();
  }

  Future<AdminCreditPackage> createPackage({
    required String name,
    required int credits,
    required double price,
    required bool isActive,
    String? googlePlayProductId,
  }) async {
    final result = await _api.createAdminCreditPackage({
      'name': name,
      'credits': credits,
      'price': price,
      'isActive': isActive,
      'googlePlayProductId': googlePlayProductId,
    });
    return AdminCreditPackage.fromMap(result);
  }

  Future<AdminCreditPackage> updatePackage({
    required String id,
    required String name,
    required int credits,
    required double price,
    required bool isActive,
    String? googlePlayProductId,
  }) async {
    final result = await _api.updateAdminCreditPackage(id, {
      'name': name,
      'credits': credits,
      'price': price,
      'isActive': isActive,
      'googlePlayProductId': googlePlayProductId,
    });
    return AdminCreditPackage.fromMap(result);
  }

  Future<void> deletePackage(String id) async {
    await _api.deleteAdminCreditPackage(id);
  }
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

double? _asDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
