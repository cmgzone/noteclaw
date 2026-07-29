import 'package:flutter_test/flutter_test.dart';
import 'package:noteclaw/features/subscription/models/subscription_model.dart';

void main() {
  group('SubscriptionModel live entitlements', () {
    test('parses effective MCP quotas and plan features', () {
      final subscription = SubscriptionModel.fromJson({
        'id': 'subscription-1',
        'user_id': 'user-1',
        'plan_id': 'plan-1',
        'plan_name': 'Pro',
        'current_credits': '720',
        'credits_consumed_this_month': 12,
        'status': 'active',
        'credits_per_month': '1000',
        'plan_price': '9.99',
        'is_free_plan': false,
        'notes_limit': '1000',
        'mcp_sources_limit': 200,
        'mcp_sources_used': '14',
        'mcp_tokens_limit': '10',
        'mcp_tokens_used': 3,
        'mcp_api_calls_per_day': '2500',
        'mcp_api_calls_used_today': 41,
        'mcp_enabled': true,
        'feature_access': {
          'memory_bank': true,
          'web_search': false,
        },
      });

      expect(subscription.notesLimit, 1000);
      expect(subscription.mcpSourcesLimit, 200);
      expect(subscription.mcpSourcesUsed, 14);
      expect(subscription.mcpTokensLimit, 10);
      expect(subscription.mcpTokensUsed, 3);
      expect(subscription.mcpApiCallsPerDay, 2500);
      expect(subscription.mcpApiCallsUsedToday, 41);
      expect(subscription.mcpEnabled, isTrue);
      expect(subscription.canAccess('memory_bank'), isTrue);
      expect(subscription.canAccess('web_search'), isFalse);
    });

    test('keeps compatibility when an older backend omits quota fields', () {
      final subscription = SubscriptionModel.fromJson({
        'id': 'subscription-2',
        'user_id': 'user-2',
        'plan_id': 'plan-2',
        'plan_name': 'Free',
        'current_credits': 50,
        'credits_consumed_this_month': 0,
        'status': 'active',
        'credits_per_month': 50,
        'plan_price': 0,
        'is_free_plan': true,
      });

      expect(subscription.notesLimit, isNull);
      expect(subscription.mcpSourcesLimit, isNull);
      expect(subscription.mcpSourcesUsed, 0);
      expect(subscription.mcpTokensLimit, isNull);
      expect(subscription.mcpApiCallsPerDay, isNull);
      expect(subscription.mcpEnabled, isTrue);
    });
  });
}
