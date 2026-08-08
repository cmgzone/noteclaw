-- Migration: Add MCP User Limits Overrides
-- Allows admins to override per-user MCP quota (sources/tokens/api calls per day)

CREATE TABLE IF NOT EXISTS mcp_user_limits (
  user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  sources_limit_override INTEGER,
  tokens_limit_override INTEGER,
  api_calls_per_day_override INTEGER,
  is_mcp_enabled_override BOOLEAN,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  updated_by TEXT REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_mcp_user_limits_updated_at ON mcp_user_limits(updated_at DESC);
