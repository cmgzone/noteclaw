CREATE TABLE IF NOT EXISTS agent_memory_entries (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  agent_session_id TEXT NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
  namespace TEXT NOT NULL,
  memory JSONB NOT NULL DEFAULT '{}',
  version INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(agent_session_id, namespace)
);

CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_user ON agent_memory_entries(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_session ON agent_memory_entries(agent_session_id);
CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_namespace ON agent_memory_entries(namespace);
CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_updated ON agent_memory_entries(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_memory_gin ON agent_memory_entries USING GIN(memory);
