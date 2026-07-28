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
