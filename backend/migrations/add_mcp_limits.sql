-- Migration: Add MCP Plan Limits
-- Allows admin to configure MCP usage limits per subscription plan

-- ==================== MCP SETTINGS TABLE ====================
-- Global MCP configuration settings
CREATE TABLE IF NOT EXISTS mcp_settings (
  id TEXT PRIMARY KEY DEFAULT 'default',
  free_sources_limit INTEGER NOT NULL DEFAULT 10,
  free_tokens_limit INTEGER NOT NULL DEFAULT 3,
  free_api_calls_per_day INTEGER NOT NULL DEFAULT 100,
  premium_sources_limit INTEGER NOT NULL DEFAULT 1000,
  premium_tokens_limit INTEGER NOT NULL DEFAULT 10,
  premium_api_calls_per_day INTEGER NOT NULL DEFAULT 10000,
  is_mcp_enabled BOOLEAN NOT NULL DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by UUID REFERENCES users(id) ON DELETE SET NULL
);

-- Insert default settings
INSERT INTO mcp_settings (id, free_sources_limit, free_tokens_limit, free_api_calls_per_day, premium_sources_limit, premium_tokens_limit, premium_api_calls_per_day)
VALUES ('default', 10, 3, 100, 1000, 10, 10000)
ON CONFLICT (id) DO NOTHING;

-- ==================== USER MCP USAGE TABLE ====================
-- Track per-user MCP usage for quota enforcement
CREATE TABLE IF NOT EXISTS user_mcp_usage (
  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  sources_count INTEGER NOT NULL DEFAULT 0,
  api_calls_today INTEGER NOT NULL DEFAULT 0,
  last_api_call_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_user_mcp_usage_user ON user_mcp_usage(user_id);

SELECT 'MCP limits tables created successfully!' as status;
