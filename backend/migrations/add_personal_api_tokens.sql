-- Migration: Add Personal API Tokens Support
-- Enables users to generate long-lived API tokens for authenticating third-party coding agents
-- Requirements: 1.1, 1.3, 3.1, 4.1, 4.5

-- ==================== API TOKENS TABLE ====================
-- Stores personal API tokens for user authentication
-- Requirements: 1.1, 1.3, 4.1

CREATE TABLE IF NOT EXISTS api_tokens (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  token_prefix TEXT NOT NULL,       -- First 9 chars (e.g., "nclaw_abc")
  token_suffix TEXT NOT NULL,       -- Last 4 chars for display
  expires_at TIMESTAMPTZ,
  last_used_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  CONSTRAINT valid_token_prefix CHECK (token_prefix LIKE 'nclaw_%')
);

-- ==================== TOKEN USAGE LOGS TABLE ====================
-- Audit trail for security - logs all token usage
-- Requirements: 4.5

CREATE TABLE IF NOT EXISTS token_usage_logs (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  token_id TEXT NOT NULL REFERENCES api_tokens(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL,
  ip_address TEXT,
  user_agent TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==================== INDEXES FOR PERFORMANCE ====================
-- Requirements: 3.1

-- Index for looking up tokens by user
CREATE INDEX IF NOT EXISTS idx_api_tokens_user ON api_tokens(user_id);

-- Index for validating tokens by hash (critical for auth performance)
CREATE INDEX IF NOT EXISTS idx_api_tokens_hash ON api_tokens(token_hash);

-- Partial index for active (non-revoked) tokens per user
CREATE INDEX IF NOT EXISTS idx_api_tokens_active ON api_tokens(user_id) 
  WHERE revoked_at IS NULL;

-- Indexes for token usage logs
CREATE INDEX IF NOT EXISTS idx_token_usage_token ON token_usage_logs(token_id);
CREATE INDEX IF NOT EXISTS idx_token_usage_time ON token_usage_logs(created_at);

SELECT 'Personal API tokens tables created successfully!' as status;
