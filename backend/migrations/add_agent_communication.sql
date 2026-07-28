-- Migration: Add Agent Communication Support
-- Enables bidirectional communication between users and third-party coding agents
-- Requirements: 3.5, 4.1, 4.4

-- ==================== AGENT SESSIONS TABLE ====================
-- Tracks agent connections and their configurations
-- Requirements: 4.1, 4.4

CREATE TABLE IF NOT EXISTS agent_sessions (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  agent_name TEXT NOT NULL,
  agent_identifier TEXT NOT NULL,
  webhook_url TEXT,
  webhook_secret TEXT,
  notebook_id TEXT REFERENCES notebooks(id) ON DELETE SET NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'expired', 'disconnected')),
  last_activity TIMESTAMPTZ DEFAULT NOW(),
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, agent_identifier)
);

-- ==================== SOURCE CONVERSATIONS TABLE ====================
-- Links sources to their conversation threads
-- Requirements: 3.5

CREATE TABLE IF NOT EXISTS source_conversations (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  source_id TEXT NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
  agent_session_id TEXT REFERENCES agent_sessions(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(source_id)
);

-- ==================== CONVERSATION MESSAGES TABLE ====================
-- Stores individual messages in source conversations
-- Requirements: 3.5

CREATE TABLE IF NOT EXISTS conversation_messages (
  id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
  conversation_id TEXT NOT NULL REFERENCES source_conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'agent')),
  content TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==================== INDEXES FOR PERFORMANCE ====================
-- Requirements: 4.4

CREATE INDEX IF NOT EXISTS idx_agent_sessions_user ON agent_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_status ON agent_sessions(status);
CREATE INDEX IF NOT EXISTS idx_agent_sessions_agent_identifier ON agent_sessions(agent_identifier);
CREATE INDEX IF NOT EXISTS idx_source_conversations_source ON source_conversations(source_id);
CREATE INDEX IF NOT EXISTS idx_source_conversations_agent_session ON source_conversations(agent_session_id);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_conversation ON conversation_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_conversation_messages_unread ON conversation_messages(conversation_id, is_read) WHERE is_read = false;
CREATE INDEX IF NOT EXISTS idx_conversation_messages_created ON conversation_messages(created_at);

-- ==================== ADD AGENT NOTEBOOK SUPPORT ====================
-- Add columns to notebooks table for agent notebook identification
-- Requirements: 1.4

ALTER TABLE notebooks ADD COLUMN IF NOT EXISTS is_agent_notebook BOOLEAN DEFAULT false;
ALTER TABLE notebooks ADD COLUMN IF NOT EXISTS agent_session_id TEXT REFERENCES agent_sessions(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS agent_notebook_access (
  user_id TEXT NOT NULL,
  agent_session_id TEXT NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
  notebook_id TEXT NOT NULL,
  can_read BOOLEAN NOT NULL DEFAULT TRUE,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  revoked_at TIMESTAMPTZ,
  PRIMARY KEY (agent_session_id, notebook_id)
);

CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_user
ON agent_notebook_access(user_id);

CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_active
ON agent_notebook_access(agent_session_id, notebook_id)
WHERE revoked_at IS NULL AND can_read = TRUE;

-- Create index for agent notebooks
CREATE INDEX IF NOT EXISTS idx_notebooks_agent ON notebooks(is_agent_notebook) WHERE is_agent_notebook = true;

SELECT 'Agent communication tables created successfully!' as status;
