import pool from '../config/database.js';

export interface McpProtocolEventInput {
  userId?: string | null;
  tokenId?: string | null;
  clientName?: string | null;
  transport: 'streamable-http' | 'stdio' | 'in-process';
  method: string;
  toolName?: string | null;
  success: boolean;
  durationMs: number;
  error?: string | null;
  details?: Record<string, unknown>;
}

let diagnosticsSchemaPromise: Promise<void> | null = null;

export function ensureMcpDiagnosticsReady(): Promise<void> {
  diagnosticsSchemaPromise ??= pool.query(`
    CREATE TABLE IF NOT EXISTS mcp_protocol_events (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id TEXT,
      token_id TEXT,
      client_name TEXT,
      transport TEXT NOT NULL,
      method TEXT NOT NULL,
      tool_name TEXT,
      success BOOLEAN NOT NULL,
      duration_ms INTEGER NOT NULL DEFAULT 0,
      error TEXT,
      details JSONB NOT NULL DEFAULT '{}'::jsonb,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `).then(async () => {
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_mcp_protocol_events_created_at
      ON mcp_protocol_events(created_at DESC)
    `);
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_mcp_protocol_events_user_id
      ON mcp_protocol_events(user_id, created_at DESC)
    `);
  }).catch((error) => {
    diagnosticsSchemaPromise = null;
    throw error;
  });
  return diagnosticsSchemaPromise;
}

export async function recordMcpProtocolEvent(
  event: McpProtocolEventInput,
): Promise<void> {
  await ensureMcpDiagnosticsReady();
  await pool.query(
    `INSERT INTO mcp_protocol_events (
       user_id, token_id, client_name, transport, method, tool_name,
       success, duration_ms, error, details
     ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::jsonb)`,
    [
      event.userId || null,
      event.tokenId || null,
      event.clientName || null,
      event.transport,
      event.method,
      event.toolName || null,
      event.success,
      Math.max(0, Math.round(event.durationMs || 0)),
      event.error?.slice(0, 2000) || null,
      JSON.stringify(event.details || {}),
    ],
  );
}

export async function getMcpDiagnostics(limit = 50) {
  await ensureMcpDiagnosticsReady();
  const safeLimit = Math.max(1, Math.min(200, Math.floor(limit)));
  const [summary, methods, tools, recent] = await Promise.all([
    pool.query(`
      SELECT
        COUNT(*)::int AS total_events,
        COUNT(*) FILTER (WHERE success)::int AS successful_events,
        COUNT(*) FILTER (WHERE NOT success)::int AS failed_events,
        COALESCE(ROUND(AVG(duration_ms)), 0)::int AS average_duration_ms,
        MAX(created_at) AS last_event_at
      FROM mcp_protocol_events
      WHERE created_at >= NOW() - INTERVAL '24 hours'
    `),
    pool.query(`
      SELECT method, COUNT(*)::int AS count,
             COUNT(*) FILTER (WHERE NOT success)::int AS failures
      FROM mcp_protocol_events
      WHERE created_at >= NOW() - INTERVAL '24 hours'
      GROUP BY method
      ORDER BY count DESC, method ASC
    `),
    pool.query(`
      SELECT tool_name, COUNT(*)::int AS count,
             COUNT(*) FILTER (WHERE NOT success)::int AS failures,
             COALESCE(ROUND(AVG(duration_ms)), 0)::int AS average_duration_ms
      FROM mcp_protocol_events
      WHERE tool_name IS NOT NULL
        AND created_at >= NOW() - INTERVAL '24 hours'
      GROUP BY tool_name
      ORDER BY count DESC, tool_name ASC
      LIMIT 25
    `),
    pool.query(
      `SELECT id, user_id, token_id, client_name, transport, method,
              tool_name, success, duration_ms, error, details, created_at
       FROM mcp_protocol_events
       ORDER BY created_at DESC
       LIMIT $1`,
      [safeLimit],
    ),
  ]);

  return {
    window: '24h',
    summary: summary.rows[0],
    methods: methods.rows,
    tools: tools.rows,
    recent: recent.rows,
  };
}
