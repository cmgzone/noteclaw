import pool from '../config/database.js';

export interface AgentTopicGrant {
  notebookId: string;
  title: string;
  description: string | null;
  isAgentNotebook: boolean;
  sourceCount: number;
  canRead: boolean;
  grantedAt: string;
}

let topicAccessSchemaPromise: Promise<void> | null = null;

export async function ensureAgentTopicAccessReady(): Promise<void> {
  if (!topicAccessSchemaPromise) {
    topicAccessSchemaPromise = (async () => {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS agent_notebook_access (
          user_id TEXT NOT NULL,
          agent_session_id TEXT NOT NULL
            REFERENCES agent_sessions(id) ON DELETE CASCADE,
          notebook_id UUID NOT NULL
            REFERENCES notebooks(id) ON DELETE CASCADE,
          can_read BOOLEAN NOT NULL DEFAULT TRUE,
          granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          revoked_at TIMESTAMPTZ,
          PRIMARY KEY (agent_session_id, notebook_id)
        )
      `);
      await pool.query(`
        CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_user
        ON agent_notebook_access(user_id)
      `);
      await pool.query(`
        CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_active
        ON agent_notebook_access(agent_session_id, notebook_id)
        WHERE revoked_at IS NULL AND can_read = TRUE
      `);

      // Existing agents start with their own notebook only. A revoked row is
      // retained, so a deliberate "no topics" choice is not recreated later.
      await pool.query(`
        INSERT INTO agent_notebook_access (
          user_id,
          agent_session_id,
          notebook_id,
          can_read
        )
        SELECT
          a.user_id,
          a.id,
          n.id,
          TRUE
        FROM agent_sessions a
        JOIN notebooks n ON n.id::text = a.notebook_id
        WHERE NOT EXISTS (
          SELECT 1
          FROM agent_notebook_access access
          WHERE access.agent_session_id = a.id
        )
        ON CONFLICT (agent_session_id, notebook_id) DO NOTHING
      `);
    })().catch((error) => {
      topicAccessSchemaPromise = null;
      throw error;
    });
  }

  await topicAccessSchemaPromise;
}

export async function grantDefaultAgentTopic(
  userId: string,
  agentSessionId: string,
  notebookId: string,
): Promise<void> {
  await ensureAgentTopicAccessReady();
  await pool.query(
    `INSERT INTO agent_notebook_access (
       user_id,
       agent_session_id,
       notebook_id,
       can_read,
       granted_at,
       revoked_at
     )
     VALUES ($1, $2, $3, TRUE, NOW(), NULL)
     ON CONFLICT (agent_session_id, notebook_id)
     DO UPDATE SET
       can_read = TRUE,
       granted_at = NOW(),
       revoked_at = NULL`,
    [userId, agentSessionId, notebookId],
  );
}

export async function replaceAgentTopicGrants(
  userId: string,
  agentSessionId: string,
  notebookIds: string[],
): Promise<AgentTopicGrant[]> {
  await ensureAgentTopicAccessReady();
  const normalizedIds = [...new Set(
    notebookIds
      .filter((value) => typeof value === 'string')
      .map((value) => value.trim())
      .filter(Boolean),
  )];
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    const sessionResult = await client.query(
      `SELECT id
       FROM agent_sessions
       WHERE id = $1 AND user_id = $2
       FOR UPDATE`,
      [agentSessionId, userId],
    );
    if (sessionResult.rows.length === 0) {
      throw new Error('Agent session not found');
    }

    if (normalizedIds.length > 0) {
      const ownedResult = await client.query(
        `SELECT id::text AS id
         FROM notebooks
         WHERE user_id = $1 AND id::text = ANY($2::text[])`,
        [userId, normalizedIds],
      );
      if (ownedResult.rows.length !== normalizedIds.length) {
        throw new Error('One or more topics do not belong to this account');
      }
    }

    await client.query(
      `UPDATE agent_notebook_access
       SET revoked_at = NOW()
       WHERE user_id = $1 AND agent_session_id = $2`,
      [userId, agentSessionId],
    );

    for (const notebookId of normalizedIds) {
      await client.query(
        `INSERT INTO agent_notebook_access (
           user_id,
           agent_session_id,
           notebook_id,
           can_read,
           granted_at,
           revoked_at
         )
         VALUES ($1, $2, $3, TRUE, NOW(), NULL)
         ON CONFLICT (agent_session_id, notebook_id)
         DO UPDATE SET
           can_read = TRUE,
           granted_at = NOW(),
           revoked_at = NULL`,
        [userId, agentSessionId, notebookId],
      );
    }

    await client.query('COMMIT');
    return listGrantedAgentTopics(userId, agentSessionId);
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally {
    client.release();
  }
}

export async function listGrantedAgentTopics(
  userId: string,
  agentSessionId: string,
): Promise<AgentTopicGrant[]> {
  await ensureAgentTopicAccessReady();
  const result = await pool.query(
    `SELECT
       n.id,
       n.title,
       n.description,
       n.is_agent_notebook,
       access.can_read,
       access.granted_at,
       COUNT(s.id)::int AS source_count
     FROM agent_notebook_access access
     JOIN notebooks n ON n.id::text = access.notebook_id::text
     LEFT JOIN sources s
       ON s.notebook_id = n.id AND s.type <> 'agent_chat'
     WHERE access.user_id = $1
       AND access.agent_session_id = $2
       AND access.revoked_at IS NULL
       AND access.can_read = TRUE
     GROUP BY
       n.id,
       n.title,
       n.description,
       n.is_agent_notebook,
       access.can_read,
       access.granted_at
     ORDER BY n.updated_at DESC, n.title ASC`,
    [userId, agentSessionId],
  );

  return result.rows.map((row) => ({
    notebookId: row.id,
    title: row.title,
    description: row.description,
    isAgentNotebook: row.is_agent_notebook === true,
    sourceCount: Number(row.source_count || 0),
    canRead: row.can_read === true,
    grantedAt: new Date(row.granted_at).toISOString(),
  }));
}

export async function listAgentTopicAccessMatrix(userId: string) {
  await ensureAgentTopicAccessReady();
  const [agentsResult, topicsResult] = await Promise.all([
    pool.query(
      `SELECT id, agent_name, agent_identifier, status, notebook_id, metadata
       FROM agent_sessions
       WHERE user_id = $1
       ORDER BY last_activity DESC`,
      [userId],
    ),
    pool.query(
      `SELECT
         n.id,
         n.title,
         n.description,
         n.is_agent_notebook,
         n.agent_session_id,
         COUNT(s.id)::int AS source_count
       FROM notebooks n
       LEFT JOIN sources s
         ON s.notebook_id = n.id AND s.type <> 'agent_chat'
       WHERE n.user_id = $1
       GROUP BY n.id
       ORDER BY n.updated_at DESC, n.title ASC`,
      [userId],
    ),
  ]);

  const grantsResult = await pool.query(
    `SELECT agent_session_id, notebook_id
     FROM agent_notebook_access
     WHERE user_id = $1
       AND revoked_at IS NULL
       AND can_read = TRUE`,
    [userId],
  );
  const grantKeys = new Set(
    grantsResult.rows.map(
      (row) => `${row.agent_session_id}:${row.notebook_id}`,
    ),
  );

  return {
    agents: agentsResult.rows.map((row) => {
      const metadata =
        typeof row.metadata === 'string'
          ? JSON.parse(row.metadata)
          : row.metadata || {};
      return {
        id: row.id,
        agentName: row.agent_name,
        mcpClientName:
          metadata.lastMcpClientName || metadata.clientName || null,
        agentIdentifier: row.agent_identifier,
        status: row.status,
        defaultNotebookId: row.notebook_id,
      };
    }),
    topics: topicsResult.rows.map((row) => ({
      id: row.id,
      title: row.title,
      description: row.description,
      isAgentNotebook: row.is_agent_notebook === true,
      sourceCount: Number(row.source_count || 0),
      ownerAgentSessionId: row.agent_session_id,
    })),
    grants: agentsResult.rows.flatMap((agent) =>
      topicsResult.rows
        .filter((topic) => grantKeys.has(`${agent.id}:${topic.id}`))
        .map((topic) => ({
          agentSessionId: agent.id,
          notebookId: topic.id,
          canRead: true,
        })),
    ),
  };
}

export async function agentCanReadTopic(
  userId: string,
  agentSessionId: string,
  notebookId: string,
): Promise<boolean> {
  await ensureAgentTopicAccessReady();
  const result = await pool.query(
    `SELECT 1
     FROM agent_notebook_access access
     JOIN agent_sessions agent ON agent.id = access.agent_session_id
     JOIN notebooks notebook ON notebook.id::text = access.notebook_id::text
     WHERE access.user_id = $1
       AND access.agent_session_id = $2
       AND access.notebook_id::text = $3
       AND access.revoked_at IS NULL
       AND access.can_read = TRUE
       AND agent.user_id = $1
       AND notebook.user_id::text = $1
     LIMIT 1`,
    [userId, agentSessionId, notebookId],
  );
  return result.rows.length > 0;
}

export async function getGrantedTopicContext(
  userId: string,
  agentSessionId: string,
  notebookId: string,
) {
  if (!(await agentCanReadTopic(userId, agentSessionId, notebookId))) {
    return null;
  }

  return getOwnedTopicContext(userId, notebookId);
}

export async function getOwnedTopicContext(
  userId: string,
  notebookId: string,
) {
  await ensureAgentTopicAccessReady();
  const notebookResult = await pool.query(
    `SELECT id, title, description, agent_session_id, updated_at
     FROM notebooks
     WHERE id::text = $1 AND user_id = $2`,
    [notebookId, userId],
  );
  if (notebookResult.rows.length === 0) return null;
  const notebook = notebookResult.rows[0];

  const [sourcesResult, memoryResult] = await Promise.all([
    pool.query(
      `SELECT id, type, title, content, url, metadata, updated_at
       FROM sources
       WHERE notebook_id::text = $1
         AND type <> 'agent_chat'
       ORDER BY updated_at DESC
       LIMIT 100`,
      [notebookId],
    ),
    notebook.agent_session_id
      ? pool.query(
          `SELECT namespace, memory, version, updated_at
           FROM agent_memory_entries
           WHERE user_id = $1 AND agent_session_id = $2
           ORDER BY updated_at DESC`,
          [userId, notebook.agent_session_id],
        )
      : Promise.resolve({ rows: [] as any[] }),
  ]);

  let remainingCharacters = 100_000;
  const sources = sourcesResult.rows.map((row) => {
    const content = String(row.content || '');
    const allowedLength = Math.max(0, Math.min(20_000, remainingCharacters));
    const clippedContent = content.slice(0, allowedLength);
    remainingCharacters -= clippedContent.length;
    return {
      id: row.id,
      type: row.type,
      title: row.title,
      content: clippedContent,
      truncated: clippedContent.length < content.length,
      url: row.url,
      metadata:
        typeof row.metadata === 'string'
          ? JSON.parse(row.metadata)
          : row.metadata || {},
      updatedAt: row.updated_at,
    };
  });

  return {
    topic: {
      id: notebook.id,
      title: notebook.title,
      description: notebook.description,
      updatedAt: notebook.updated_at,
    },
    sources,
    memories: memoryResult.rows.map((row) => ({
      namespace: row.namespace,
      memory:
        typeof row.memory === 'string' ? JSON.parse(row.memory) : row.memory,
      version: Number(row.version || 0),
      updatedAt: row.updated_at,
    })),
  };
}
