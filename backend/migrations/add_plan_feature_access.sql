-- Configurable feature entitlements for subscription plans.
-- Defaults preserve the paid memory-bank product: free starts disabled and
-- paid plans start enabled. Admins can override every feature per plan.

ALTER TABLE subscription_plans
ADD COLUMN IF NOT EXISTS feature_access JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE user_subscriptions
ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active';

UPDATE subscription_plans
SET feature_access = CASE
  WHEN is_free_plan THEN
    '{
      "memory_bank": false,
      "notebook_chat": false,
      "websocket_collaboration": false,
      "code_review": false,
      "web_search": false,
      "deep_research": false,
      "research_save_to_notebook": false
    }'::jsonb
  ELSE
    '{
      "memory_bank": true,
      "notebook_chat": true,
      "websocket_collaboration": true,
      "code_review": true,
      "web_search": true,
      "deep_research": true,
      "research_save_to_notebook": true
    }'::jsonb
END
WHERE feature_access = '{}'::jsonb;
