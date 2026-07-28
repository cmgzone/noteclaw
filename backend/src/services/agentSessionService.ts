/**
 * Agent Session Service
 * Manages the lifecycle of agent connections between users and third-party coding agents.
 * 
 * Requirements: 1.1, 1.2, 1.3, 4.2
 */

import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';

// ==================== INTERFACES ====================

export interface AgentConfig {
  agentName: string;
  agentIdentifier: string;
  webhookUrl?: string;
  webhookSecret?: string;
  metadata?: Record<string, any>;
}

export interface AgentSession {
  id: string;
  userId: string;
  agentName: string;
  agentIdentifier: string;
  webhookUrl?: string;
  webhookSecret?: string;
  notebookId?: string;
  status: 'active' | 'expired' | 'disconnected';
  lastActivity: Date;
  createdAt: Date;
  metadata: Record<string, any>;
}

// ==================== SERVICE CLASS ====================

class AgentSessionService {
  /**
   * Create a new agent session or return existing one for the same agent/user combination.
   * Implements idempotent behavior per Requirement 1.3.
   * 
   * @param userId - The user's ID
   * @param agentConfig - Configuration for the agent
   * @returns The created or existing AgentSession
   */
  async createSession(userId: string, agentConfig: AgentConfig): Promise<AgentSession> {
    const { agentName, agentIdentifier, webhookUrl, webhookSecret, metadata = {} } = agentConfig;

    // Check for existing session (idempotent - Requirement 1.3)
    const existingSession = await this.getSessionByAgent(userId, agentIdentifier);
    if (existingSession) {
      // Update activity and return existing session
      await this.updateActivity(existingSession.id);
      
      // If session was disconnected/expired, reactivate it
      if (existingSession.status !== 'active') {
        await pool.query(
          `UPDATE agent_sessions SET status = 'active', last_activity = NOW() WHERE id = $1`,
          [existingSession.id]
        );
        existingSession.status = 'active';
      }
      
      return existingSession;
    }

    // Create new session
    const sessionId = uuidv4();
    const result = await pool.query(
      `INSERT INTO agent_sessions 
       (id, user_id, agent_name, agent_identifier, webhook_url, webhook_secret, status, metadata, last_activity, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, 'active', $7, NOW(), NOW())
       ON CONFLICT (user_id, agent_identifier)
       DO UPDATE SET
         agent_name = EXCLUDED.agent_name,
         webhook_url = COALESCE(EXCLUDED.webhook_url, agent_sessions.webhook_url),
         webhook_secret = COALESCE(EXCLUDED.webhook_secret, agent_sessions.webhook_secret),
         status = 'active',
         metadata = COALESCE(agent_sessions.metadata, '{}'::jsonb) || EXCLUDED.metadata,
         last_activity = NOW()
       RETURNING *`,
      [sessionId, userId, agentName, agentIdentifier, webhookUrl, webhookSecret, JSON.stringify(metadata)]
    );

    return this.mapRowToSession(result.rows[0]);
  }

  /**
   * Get a session by its ID.
   * 
   * @param sessionId - The session ID
   * @returns The AgentSession or null if not found
   */
  async getSession(sessionId: string): Promise<AgentSession | null> {
    const result = await pool.query(
      `SELECT * FROM agent_sessions WHERE id = $1`,
      [sessionId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToSession(result.rows[0]);
  }

  /**
   * Get a session by user ID and agent identifier.
   * Used for idempotent session creation (Requirement 1.3).
   * 
   * @param userId - The user's ID
   * @param agentIdentifier - The unique agent identifier
   * @returns The AgentSession or null if not found
   */
  async getSessionByAgent(userId: string, agentIdentifier: string): Promise<AgentSession | null> {
    const result = await pool.query(
      `SELECT * FROM agent_sessions WHERE user_id = $1 AND agent_identifier = $2`,
      [userId, agentIdentifier]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToSession(result.rows[0]);
  }

  /**
   * Get all sessions for a user.
   * Supports multiple simultaneous agent connections (Requirement 4.4).
   * 
   * @param userId - The user's ID
   * @returns Array of AgentSessions
   */
  async getSessionsByUser(userId: string): Promise<AgentSession[]> {
    const result = await pool.query(
      `SELECT * FROM agent_sessions WHERE user_id = $1 ORDER BY created_at DESC`,
      [userId]
    );

    return result.rows.map(row => this.mapRowToSession(row));
  }

  /**
   * Update the last activity timestamp for a session.
   * Used to track session activity (Requirement 4.2).
   * 
   * @param sessionId - The session ID
   */
  async updateActivity(sessionId: string): Promise<void> {
    await pool.query(
      `UPDATE agent_sessions SET last_activity = NOW() WHERE id = $1`,
      [sessionId]
    );
  }

  /**
   * Expire a session, marking it as expired.
   * Expired sessions can be reactivated (Requirement 4.2).
   * 
   * @param sessionId - The session ID
   */
  async expireSession(sessionId: string): Promise<void> {
    await pool.query(
      `UPDATE agent_sessions SET status = 'expired', last_activity = NOW() WHERE id = $1`,
      [sessionId]
    );
  }

  /**
   * Disconnect a session, marking it as disconnected.
   * Disconnected sessions preserve data but stop routing messages (Requirement 4.3).
   * 
   * @param sessionId - The session ID
   */
  async disconnectSession(sessionId: string): Promise<void> {
    await pool.query(
      `UPDATE agent_sessions SET status = 'disconnected', last_activity = NOW() WHERE id = $1`,
      [sessionId]
    );
  }

  /**
   * Link a notebook to a session.
   * 
   * @param sessionId - The session ID
   * @param notebookId - The notebook ID to link
   */
  async linkNotebook(sessionId: string, notebookId: string): Promise<void> {
    await pool.query(
      `UPDATE agent_sessions SET notebook_id = $1, last_activity = NOW() WHERE id = $2`,
      [notebookId, sessionId]
    );
  }

  /**
   * Delete a session completely.
   * 
   * @param sessionId - The session ID
   */
  async deleteSession(sessionId: string): Promise<void> {
    await pool.query(
      `DELETE FROM agent_sessions WHERE id = $1`,
      [sessionId]
    );
  }

  /**
   * Map a database row to an AgentSession object.
   */
  private mapRowToSession(row: any): AgentSession {
    return {
      id: row.id,
      userId: row.user_id,
      agentName: row.agent_name,
      agentIdentifier: row.agent_identifier,
      webhookUrl: row.webhook_url,
      webhookSecret: row.webhook_secret,
      notebookId: row.notebook_id,
      status: row.status,
      lastActivity: new Date(row.last_activity),
      createdAt: new Date(row.created_at),
      metadata: typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}),
    };
  }
}

// Export singleton instance
export const agentSessionService = new AgentSessionService();
export default agentSessionService;
