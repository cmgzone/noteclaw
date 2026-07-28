import pool from '../config/database.js';

export const PLAN_FEATURE_KEYS = [
  'memory_bank',
  'notebook_chat',
  'websocket_collaboration',
  'code_review',
  'web_search',
  'deep_research',
  'research_save_to_notebook',
] as const;

export type PlanFeatureKey = (typeof PLAN_FEATURE_KEYS)[number];
export type PlanFeatureAccess = Record<PlanFeatureKey, boolean>;

export const PLAN_FEATURE_LABELS: Record<PlanFeatureKey, string> = {
  memory_bank: 'Durable memory bank',
  notebook_chat: 'Chat with memory notebooks',
  websocket_collaboration: 'Shared WebSocket sessions',
  code_review: 'Agent code review',
  web_search: 'Live web search',
  deep_research: 'Deep research agent',
  research_save_to_notebook: 'Save research to notebooks',
};

let featureSchemaPromise: Promise<void> | null = null;

export function defaultPlanFeatureAccess(isFreePlan: boolean): PlanFeatureAccess {
  const enabled = !isFreePlan;
  return {
    memory_bank: true,
    notebook_chat: true,
    websocket_collaboration: true,
    code_review: enabled,
    web_search: enabled,
    deep_research: enabled,
    research_save_to_notebook: enabled,
  };
}

export function normalizePlanFeatureAccess(
  value: unknown,
  isFreePlan: boolean,
): PlanFeatureAccess {
  const normalized = defaultPlanFeatureAccess(isFreePlan);
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    return normalized;
  }

  const candidate = value as Record<string, unknown>;
  for (const key of PLAN_FEATURE_KEYS) {
    if (typeof candidate[key] === 'boolean') {
      normalized[key] = candidate[key] as boolean;
    }
  }
  return normalized;
}

export async function ensurePlanFeatureAccessReady(): Promise<void> {
  if (!featureSchemaPromise) {
    featureSchemaPromise = (async () => {
      await pool.query(`
        ALTER TABLE subscription_plans
        ADD COLUMN IF NOT EXISTS feature_access JSONB NOT NULL DEFAULT '{}'::jsonb
      `);
      await pool.query(`
        ALTER TABLE user_subscriptions
        ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'
      `);

      const plans = await pool.query(
        `SELECT id, is_free_plan, feature_access
         FROM subscription_plans`,
      );
      for (const plan of plans.rows) {
        const current =
          plan.feature_access && typeof plan.feature_access === 'object'
            ? plan.feature_access
            : {};
        const hasKnownKey = PLAN_FEATURE_KEYS.some(
          (key) => typeof current[key] === 'boolean',
        );
        if (hasKnownKey) continue;

        await pool.query(
          `UPDATE subscription_plans
           SET feature_access = $1::jsonb, updated_at = NOW()
           WHERE id = $2`,
          [
            JSON.stringify(defaultPlanFeatureAccess(plan.is_free_plan === true)),
            plan.id,
          ],
        );
      }
    })().catch((error) => {
      featureSchemaPromise = null;
      throw error;
    });
  }

  return featureSchemaPromise;
}

export interface UserPlanFeatureContext {
  planId: string | null;
  planName: string | null;
  status: string;
  isFreePlan: boolean;
  featureAccess: PlanFeatureAccess;
}

export async function getUserPlanFeatureContext(
  userId: string,
): Promise<UserPlanFeatureContext> {
  await ensurePlanFeatureAccessReady();

  const result = await pool.query(
    `SELECT
       sp.id AS plan_id,
       sp.name AS plan_name,
       sp.is_free_plan,
       sp.feature_access,
       COALESCE(us.status, 'active') AS subscription_status
     FROM user_subscriptions us
     JOIN subscription_plans sp ON sp.id = us.plan_id
     WHERE us.user_id = $1
     ORDER BY us.updated_at DESC
     LIMIT 1`,
    [userId],
  );

  if (result.rows.length === 0) {
    return {
      planId: null,
      planName: null,
      status: 'inactive',
      isFreePlan: true,
      featureAccess: defaultPlanFeatureAccess(true),
    };
  }

  const row = result.rows[0];
  return {
    planId: row.plan_id,
    planName: row.plan_name,
    status: row.subscription_status || 'active',
    isFreePlan: row.is_free_plan === true,
    featureAccess: normalizePlanFeatureAccess(
      row.feature_access,
      row.is_free_plan === true,
    ),
  };
}

export async function userHasPlanFeature(
  userId: string,
  feature: PlanFeatureKey,
): Promise<{ allowed: boolean; context: UserPlanFeatureContext }> {
  const context = await getUserPlanFeatureContext(userId);
  return {
    allowed:
      context.status.toLowerCase() === 'active'
      && context.featureAccess[feature] === true,
    context,
  };
}
