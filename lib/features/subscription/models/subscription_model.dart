import 'dart:developer' as developer;

class SubscriptionModel {
  final String id;
  final String userId;
  final String planId;
  final String planName;
  final int currentCredits;
  final int creditsConsumedThisMonth;
  final DateTime? lastRenewalDate;
  final DateTime? nextRenewalDate;
  final String status; // active, suspended, cancelled
  final int creditsPerMonth;
  final double planPrice;
  final bool isFreePlan;
  final Map<String, bool> featureAccess;
  final int? notesLimit;
  final int? mcpSourcesLimit;
  final int mcpSourcesUsed;
  final int? mcpTokensLimit;
  final int mcpTokensUsed;
  final int? mcpApiCallsPerDay;
  final int mcpApiCallsUsedToday;
  final bool mcpEnabled;

  SubscriptionModel({
    required this.id,
    required this.userId,
    required this.planId,
    required this.planName,
    required this.currentCredits,
    required this.creditsConsumedThisMonth,
    this.lastRenewalDate,
    this.nextRenewalDate,
    required this.status,
    required this.creditsPerMonth,
    required this.planPrice,
    required this.isFreePlan,
    required this.featureAccess,
    this.notesLimit,
    this.mcpSourcesLimit,
    this.mcpSourcesUsed = 0,
    this.mcpTokensLimit,
    this.mcpTokensUsed = 0,
    this.mcpApiCallsPerDay,
    this.mcpApiCallsUsedToday = 0,
    this.mcpEnabled = true,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    developer.log('[SUB_MODEL] Parsing JSON: $json', name: 'SubscriptionModel');

    try {
      final isFreePlan = _parseBool(json['is_free_plan']) ?? false;
      final model = SubscriptionModel(
        id: _parseString(json['id']) ?? '',
        userId: _parseString(json['user_id']) ?? '',
        planId: _parseString(json['plan_id']) ?? '',
        planName: _parseString(json['plan_name']) ?? 'Free Plan',
        currentCredits: _parseInt(json['current_credits']) ?? 0,
        creditsConsumedThisMonth:
            _parseInt(json['credits_consumed_this_month']) ?? 0,
        lastRenewalDate: _parseDate(json['last_renewal_date']),
        nextRenewalDate: _parseDate(json['next_renewal_date']),
        status: _parseString(json['status']) ?? 'active',
        creditsPerMonth: _parseInt(json['credits_per_month']) ?? 30,
        planPrice: _parseDouble(json['plan_price']) ?? 0.0,
        isFreePlan: isFreePlan,
        featureAccess: _parseFeatureAccess(
          json['feature_access'],
          isFreePlan: isFreePlan,
        ),
        notesLimit: _parseInt(json['notes_limit']),
        mcpSourcesLimit: _parseInt(json['mcp_sources_limit']),
        mcpSourcesUsed: _parseInt(json['mcp_sources_used']) ?? 0,
        mcpTokensLimit: _parseInt(json['mcp_tokens_limit']),
        mcpTokensUsed: _parseInt(json['mcp_tokens_used']) ?? 0,
        mcpApiCallsPerDay: _parseInt(json['mcp_api_calls_per_day']),
        mcpApiCallsUsedToday: _parseInt(json['mcp_api_calls_used_today']) ?? 0,
        mcpEnabled: _parseBool(json['mcp_enabled']) ?? true,
      );

      developer.log(
          '[SUB_MODEL] Parsed successfully: ${model.planName}, credits: ${model.currentCredits}',
          name: 'SubscriptionModel');
      return model;
    } catch (e, stack) {
      developer.log('[SUB_MODEL] Error parsing: $e',
          name: 'SubscriptionModel', error: e, stackTrace: stack);
      rethrow;
    }
  }

  static String? _parseString(dynamic value) {
    if (value == null) return null;
    return value.toString();
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    if (value is int) return value != 0;
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static Map<String, bool> _parseFeatureAccess(
    dynamic value, {
    required bool isFreePlan,
  }) {
    const keys = [
      'memory_bank',
      'notebook_chat',
      'websocket_collaboration',
      'code_review',
      'web_search',
      'deep_research',
      'research_save_to_notebook',
      'image_generation',
      'video_generation',
    ];
    final fallback = !isFreePlan;
    final source = value is Map ? value : const {};
    final access = {
      for (final key in keys)
        key: source[key] is bool ? source[key] as bool : fallback,
    };
    access['memory_bank'] = true;
    access['notebook_chat'] = true;
    access['websocket_collaboration'] = true;
    return access;
  }

  bool canAccess(String feature) => featureAccess[feature] == true;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'plan_id': planId,
      'plan_name': planName,
      'current_credits': currentCredits,
      'credits_consumed_this_month': creditsConsumedThisMonth,
      'last_renewal_date': lastRenewalDate?.toIso8601String(),
      'next_renewal_date': nextRenewalDate?.toIso8601String(),
      'status': status,
      'credits_per_month': creditsPerMonth,
      'plan_price': planPrice,
      'is_free_plan': isFreePlan,
      'feature_access': featureAccess,
      'notes_limit': notesLimit,
      'mcp_sources_limit': mcpSourcesLimit,
      'mcp_sources_used': mcpSourcesUsed,
      'mcp_tokens_limit': mcpTokensLimit,
      'mcp_tokens_used': mcpTokensUsed,
      'mcp_api_calls_per_day': mcpApiCallsPerDay,
      'mcp_api_calls_used_today': mcpApiCallsUsedToday,
      'mcp_enabled': mcpEnabled,
    };
  }

  SubscriptionModel copyWith({
    String? id,
    String? userId,
    String? planId,
    String? planName,
    int? currentCredits,
    int? creditsConsumedThisMonth,
    DateTime? lastRenewalDate,
    DateTime? nextRenewalDate,
    String? status,
    int? creditsPerMonth,
    double? planPrice,
    bool? isFreePlan,
    Map<String, bool>? featureAccess,
    int? notesLimit,
    int? mcpSourcesLimit,
    int? mcpSourcesUsed,
    int? mcpTokensLimit,
    int? mcpTokensUsed,
    int? mcpApiCallsPerDay,
    int? mcpApiCallsUsedToday,
    bool? mcpEnabled,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      planId: planId ?? this.planId,
      planName: planName ?? this.planName,
      currentCredits: currentCredits ?? this.currentCredits,
      creditsConsumedThisMonth:
          creditsConsumedThisMonth ?? this.creditsConsumedThisMonth,
      lastRenewalDate: lastRenewalDate ?? this.lastRenewalDate,
      nextRenewalDate: nextRenewalDate ?? this.nextRenewalDate,
      status: status ?? this.status,
      creditsPerMonth: creditsPerMonth ?? this.creditsPerMonth,
      planPrice: planPrice ?? this.planPrice,
      isFreePlan: isFreePlan ?? this.isFreePlan,
      featureAccess: featureAccess ?? this.featureAccess,
      notesLimit: notesLimit ?? this.notesLimit,
      mcpSourcesLimit: mcpSourcesLimit ?? this.mcpSourcesLimit,
      mcpSourcesUsed: mcpSourcesUsed ?? this.mcpSourcesUsed,
      mcpTokensLimit: mcpTokensLimit ?? this.mcpTokensLimit,
      mcpTokensUsed: mcpTokensUsed ?? this.mcpTokensUsed,
      mcpApiCallsPerDay: mcpApiCallsPerDay ?? this.mcpApiCallsPerDay,
      mcpApiCallsUsedToday: mcpApiCallsUsedToday ?? this.mcpApiCallsUsedToday,
      mcpEnabled: mcpEnabled ?? this.mcpEnabled,
    );
  }
}
