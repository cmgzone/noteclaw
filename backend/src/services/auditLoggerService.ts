/**
 * Audit Logger Service
 * 
 * Logs all GitHub API interactions for audit purposes.
 * Implements Requirements 7.3 from the GitHub-MCP Integration spec.
 * 
 * Feature: github-mcp-integration
 */

import pool from '../config/database.js';

/**
 * Valid GitHub audit actions
 */
export type GitHubAuditAction = 
  | 'list_repos' 
  | 'get_file' 
  | 'search' 
  | 'create_issue' 
  | 'add_source' 
  | 'add_repo_sources'
  | 'import_repo_notebook'
  | 'analyze_repo' 
  | 'get_tree'
  | 'github_disconnect'
  | 'refresh_source'
  | 'check_updates'
  | 'reanalyze_source';

/**
 * GitHub audit log entry
 */
export interface GitHubAuditLog {
  id: string;
  userId: string;
  action: GitHubAuditAction;
  owner?: string;
  repo?: string;
  path?: string;
  agentSessionId?: string;
  success: boolean;
  errorMessage?: string;
  requestMetadata?: Record<string, any>;
  createdAt: Date;
}

/**
 * Parameters for creating an audit log entry
 */
export interface CreateAuditLogParams {
  userId: string;
  action: GitHubAuditAction;
  owner?: string;
  repo?: string;
  path?: string;
  agentSessionId?: string;
  success?: boolean;
  errorMessage?: string;
  requestMetadata?: Record<string, any>;
}

/**
 * Query options for retrieving audit logs
 */
export interface AuditQueryOptions {
  action?: GitHubAuditAction;
  owner?: string;
  repo?: string;
  success?: boolean;
  startDate?: Date;
  endDate?: Date;
  limit?: number;
  offset?: number;
}

/**
 * Paginated audit log result
 */
export interface PaginatedAuditLogs {
  logs: GitHubAuditLog[];
  total: number;
  limit: number;
  offset: number;
  hasMore: boolean;
}

/**
 * Audit Logger Service
 * 
 * Provides methods to log and query GitHub API interactions.
 */
class AuditLoggerService {
  /**
   * Log a GitHub API interaction
   * 
   * @param entry - The audit log entry to create
   * @returns The created audit log entry
   */
  async log(entry: CreateAuditLogParams): Promise<GitHubAuditLog> {
    const {
      userId,
      action,
      owner,
      repo,
      path,
      agentSessionId,
      success = true,
      errorMessage,
      requestMetadata = {},
    } = entry;

    const result = await pool.query(
      `INSERT INTO github_audit_logs 
       (user_id, action, owner, repo, path, agent_session_id, success, error_message, request_metadata)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [
        userId,
        action,
        owner || null,
        repo || null,
        path || null,
        agentSessionId || null,
        success,
        errorMessage || null,
        JSON.stringify(requestMetadata),
      ]
    );

    return this.mapRow(result.rows[0]);
  }

  /**
   * Get audit logs for a specific user with pagination and filtering
   * 
   * @param userId - The user ID to get logs for
   * @param options - Query options for filtering and pagination
   * @returns Paginated audit logs
   */
  async getLogsForUser(
    userId: string,
    options: AuditQueryOptions = {}
  ): Promise<PaginatedAuditLogs> {
    const {
      action,
      owner,
      repo,
      success,
      startDate,
      endDate,
      limit = 50,
      offset = 0,
    } = options;

    // Build WHERE clause dynamically
    const conditions: string[] = ['user_id = $1'];
    const params: any[] = [userId];
    let paramIndex = 2;

    if (action) {
      conditions.push(`action = $${paramIndex}`);
      params.push(action);
      paramIndex++;
    }

    if (owner) {
      conditions.push(`owner = $${paramIndex}`);
      params.push(owner);
      paramIndex++;
    }

    if (repo) {
      conditions.push(`repo = $${paramIndex}`);
      params.push(repo);
      paramIndex++;
    }

    if (success !== undefined) {
      conditions.push(`success = $${paramIndex}`);
      params.push(success);
      paramIndex++;
    }

    if (startDate) {
      conditions.push(`created_at >= $${paramIndex}`);
      params.push(startDate);
      paramIndex++;
    }

    if (endDate) {
      conditions.push(`created_at <= $${paramIndex}`);
      params.push(endDate);
      paramIndex++;
    }

    const whereClause = conditions.join(' AND ');

    // Get total count
    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM github_audit_logs WHERE ${whereClause}`,
      params
    );
    const total = parseInt(countResult.rows[0].total, 10);

    // Get paginated results
    const logsResult = await pool.query(
      `SELECT * FROM github_audit_logs 
       WHERE ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
      [...params, limit, offset]
    );

    const logs = logsResult.rows.map(row => this.mapRow(row));

    return {
      logs,
      total,
      limit,
      offset,
      hasMore: offset + logs.length < total,
    };
  }

  /**
   * Get a single audit log by ID
   * 
   * @param logId - The audit log ID
   * @returns The audit log entry or null if not found
   */
  async getLogById(logId: string): Promise<GitHubAuditLog | null> {
    const result = await pool.query(
      'SELECT * FROM github_audit_logs WHERE id = $1',
      [logId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRow(result.rows[0]);
  }

  /**
   * Get audit logs for a specific repository
   * 
   * @param owner - Repository owner
   * @param repo - Repository name
   * @param options - Query options
   * @returns Paginated audit logs
   */
  async getLogsForRepo(
    owner: string,
    repo: string,
    options: Omit<AuditQueryOptions, 'owner' | 'repo'> = {}
  ): Promise<PaginatedAuditLogs> {
    const {
      action,
      success,
      startDate,
      endDate,
      limit = 50,
      offset = 0,
    } = options;

    const conditions: string[] = ['owner = $1', 'repo = $2'];
    const params: any[] = [owner, repo];
    let paramIndex = 3;

    if (action) {
      conditions.push(`action = $${paramIndex}`);
      params.push(action);
      paramIndex++;
    }

    if (success !== undefined) {
      conditions.push(`success = $${paramIndex}`);
      params.push(success);
      paramIndex++;
    }

    if (startDate) {
      conditions.push(`created_at >= $${paramIndex}`);
      params.push(startDate);
      paramIndex++;
    }

    if (endDate) {
      conditions.push(`created_at <= $${paramIndex}`);
      params.push(endDate);
      paramIndex++;
    }

    const whereClause = conditions.join(' AND ');

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM github_audit_logs WHERE ${whereClause}`,
      params
    );
    const total = parseInt(countResult.rows[0].total, 10);

    const logsResult = await pool.query(
      `SELECT * FROM github_audit_logs 
       WHERE ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
      [...params, limit, offset]
    );

    const logs = logsResult.rows.map(row => this.mapRow(row));

    return {
      logs,
      total,
      limit,
      offset,
      hasMore: offset + logs.length < total,
    };
  }

  /**
   * Get audit logs for a specific agent session
   * 
   * @param agentSessionId - The agent session ID
   * @param options - Query options
   * @returns Paginated audit logs
   */
  async getLogsForAgentSession(
    agentSessionId: string,
    options: Omit<AuditQueryOptions, 'agentSessionId'> = {}
  ): Promise<PaginatedAuditLogs> {
    const {
      action,
      owner,
      repo,
      success,
      startDate,
      endDate,
      limit = 50,
      offset = 0,
    } = options;

    const conditions: string[] = ['agent_session_id = $1'];
    const params: any[] = [agentSessionId];
    let paramIndex = 2;

    if (action) {
      conditions.push(`action = $${paramIndex}`);
      params.push(action);
      paramIndex++;
    }

    if (owner) {
      conditions.push(`owner = $${paramIndex}`);
      params.push(owner);
      paramIndex++;
    }

    if (repo) {
      conditions.push(`repo = $${paramIndex}`);
      params.push(repo);
      paramIndex++;
    }

    if (success !== undefined) {
      conditions.push(`success = $${paramIndex}`);
      params.push(success);
      paramIndex++;
    }

    if (startDate) {
      conditions.push(`created_at >= $${paramIndex}`);
      params.push(startDate);
      paramIndex++;
    }

    if (endDate) {
      conditions.push(`created_at <= $${paramIndex}`);
      params.push(endDate);
      paramIndex++;
    }

    const whereClause = conditions.join(' AND ');

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM github_audit_logs WHERE ${whereClause}`,
      params
    );
    const total = parseInt(countResult.rows[0].total, 10);

    const logsResult = await pool.query(
      `SELECT * FROM github_audit_logs 
       WHERE ${whereClause}
       ORDER BY created_at DESC
       LIMIT $${paramIndex} OFFSET $${paramIndex + 1}`,
      [...params, limit, offset]
    );

    const logs = logsResult.rows.map(row => this.mapRow(row));

    return {
      logs,
      total,
      limit,
      offset,
      hasMore: offset + logs.length < total,
    };
  }

  /**
   * Delete old audit logs (for cleanup/retention)
   * 
   * @param olderThan - Delete logs older than this date
   * @returns Number of deleted logs
   */
  async deleteOldLogs(olderThan: Date): Promise<number> {
    const result = await pool.query(
      'DELETE FROM github_audit_logs WHERE created_at < $1',
      [olderThan]
    );

    return result.rowCount || 0;
  }

  /**
   * Map database row to GitHubAuditLog interface
   */
  private mapRow(row: any): GitHubAuditLog {
    return {
      id: row.id,
      userId: row.user_id,
      action: row.action as GitHubAuditAction,
      owner: row.owner || undefined,
      repo: row.repo || undefined,
      path: row.path || undefined,
      agentSessionId: row.agent_session_id || undefined,
      success: row.success,
      errorMessage: row.error_message || undefined,
      requestMetadata: row.request_metadata || {},
      createdAt: new Date(row.created_at),
    };
  }
}

export const auditLoggerService = new AuditLoggerService();
export default auditLoggerService;
