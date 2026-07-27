/**
 * Agent Notebook Service
 * Handles creation and management of agent-specific notebooks.
 * 
 * Requirements: 1.1, 1.2, 1.3, 4.3
 */

import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { AgentSession, agentSessionService } from './agentSessionService.js';

// ==================== INTERFACES ====================

export interface AgentNotebook {
  id: string;
  userId: string;
  title: string;
  description: string | null;
  coverImage: string | null;
  agentSessionId: string | null;
  isAgentNotebook: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateNotebookOptions {
  title?: string;
  description?: string;
  coverImage?: string;
}

// ==================== SERVICE CLASS ====================

class AgentNotebookService {
  /**
   * Create a new agent notebook or return existing one for the same agent session.
   * Implements idempotent behavior per Requirement 1.3.
   * 
   * @param userId - The user's ID
   * @param agentSession - The agent session to associate with the notebook
   * @param options - Optional notebook customization
   * @returns The created or existing AgentNotebook
   */
  async createOrGetNotebook(
    userId: string,
    agentSession: AgentSession,
    options: CreateNotebookOptions = {}
  ): Promise<AgentNotebook> {
    // Check if notebook already exists for this agent session (idempotent - Requirement 1.3)
    if (agentSession.notebookId) {
      const existingNotebook = await this.getNotebookById(agentSession.notebookId);
      if (existingNotebook && existingNotebook.userId === userId) {
        return existingNotebook;
      }
    }

    // Check for existing notebook by agent session ID
    const existingBySession = await this.getNotebookByAgentSession(agentSession.id);
    if (existingBySession && existingBySession.userId === userId) {
      // Link the notebook to the session if not already linked
      if (!agentSession.notebookId) {
        await agentSessionService.linkNotebook(agentSession.id, existingBySession.id);
      }
      return existingBySession;
    }

    // Check for existing notebook by project / title for this user BEFORE creating a new one
    const requestedTitle = options.title;
    if (requestedTitle && requestedTitle.trim().length > 0) {
      const existingByTitle = await this.findNotebookByTitle(userId, requestedTitle);
      if (existingByTitle) {
        if (!agentSession.notebookId) {
          await agentSessionService.linkNotebook(agentSession.id, existingByTitle.id);
        }
        return existingByTitle;
      }
    }

    // Create new notebook with agent metadata (Requirements 1.1, 1.2)
    const notebookId = uuidv4();
    const title = options.title || `${agentSession.agentName} Notebook`;
    const description = options.description || `Code verified by ${agentSession.agentName}`;

    const result = await pool.query(
      `INSERT INTO notebooks 
       (id, user_id, title, description, cover_image, is_agent_notebook, agent_session_id, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, true, $6, NOW(), NOW())
       RETURNING *`,
      [notebookId, userId, title, description, options.coverImage || null, agentSession.id]
    );

    // Link the notebook to the agent session
    await agentSessionService.linkNotebook(agentSession.id, notebookId);

    // Update user stats
    await pool.query(
      `INSERT INTO user_stats (user_id, notebooks_created) 
       VALUES ($1, 1)
       ON CONFLICT (user_id) 
       DO UPDATE SET notebooks_created = user_stats.notebooks_created + 1, updated_at = NOW()`,
      [userId]
    );

    return this.mapRowToNotebook(result.rows[0]);
  }

  /**
   * Get all agent notebooks for a user.
   * Supports viewing all connected agents (Requirement 4.1).
   * 
   * @param userId - The user's ID
   * @returns Array of AgentNotebooks with agent session info
   */
  async getAgentNotebooks(userId: string): Promise<AgentNotebook[]> {
    const result = await pool.query(
      `SELECT n.*, 
              (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count,
              a.agent_name, a.agent_identifier, a.status as agent_status
       FROM notebooks n
       LEFT JOIN agent_sessions a ON n.agent_session_id = a.id
       WHERE n.user_id = $1 AND n.is_agent_notebook = true
       ORDER BY n.updated_at DESC`,
      [userId]
    );

    return result.rows.map(row => this.mapRowToNotebook(row));
  }

  /**
   * Get a notebook by its ID.
   * 
   * @param notebookId - The notebook ID
   * @returns The AgentNotebook or null if not found
   */
  async getNotebookById(notebookId: string): Promise<AgentNotebook | null> {
    const result = await pool.query(
      `SELECT * FROM notebooks WHERE id = $1`,
      [notebookId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToNotebook(result.rows[0]);
  }

  /**
   * Get a notebook by agent session ID.
   * Used for idempotent notebook creation (Requirement 1.3).
   * 
   * @param agentSessionId - The agent session ID
   * @returns The AgentNotebook or null if not found
   */
  async getNotebookByAgentSession(agentSessionId: string): Promise<AgentNotebook | null> {
    const result = await pool.query(
      `SELECT * FROM notebooks WHERE agent_session_id = $1`,
      [agentSessionId]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToNotebook(result.rows[0]);
  }

  /**
   * Delete an agent notebook.
   * Also disconnects the associated agent session (Requirement 4.3).
   * 
   * @param notebookId - The notebook ID
   * @param userId - The user's ID (for authorization)
   * @returns true if deleted, false if not found
   */
  async deleteNotebook(notebookId: string, userId: string): Promise<boolean> {
    // First, get the notebook to check ownership and get agent session ID
    const notebook = await this.getNotebookById(notebookId);
    
    if (!notebook || notebook.userId !== userId) {
      return false;
    }

    // Disconnect the agent session if it exists (Requirement 4.3)
    if (notebook.agentSessionId) {
      await agentSessionService.disconnectSession(notebook.agentSessionId);
    }

    // Delete the notebook (cascades to sources)
    const result = await pool.query(
      `DELETE FROM notebooks WHERE id = $1 AND user_id = $2 RETURNING id`,
      [notebookId, userId]
    );

    return result.rows.length > 0;
  }

  /**
   * Update notebook metadata.
   * 
   * @param notebookId - The notebook ID
   * @param userId - The user's ID (for authorization)
   * @param updates - Fields to update
   * @returns The updated notebook or null if not found
   */
  async updateNotebook(
    notebookId: string,
    userId: string,
    updates: Partial<Pick<AgentNotebook, 'title' | 'description' | 'coverImage'>>
  ): Promise<AgentNotebook | null> {
    const setClauses: string[] = [];
    const values: any[] = [];
    let paramIndex = 1;

    if (updates.title !== undefined) {
      setClauses.push(`title = $${paramIndex++}`);
      values.push(updates.title);
    }
    if (updates.description !== undefined) {
      setClauses.push(`description = $${paramIndex++}`);
      values.push(updates.description);
    }
    if (updates.coverImage !== undefined) {
      setClauses.push(`cover_image = $${paramIndex++}`);
      values.push(updates.coverImage);
    }

    if (setClauses.length === 0) {
      return this.getNotebookById(notebookId);
    }

    setClauses.push('updated_at = NOW()');
    values.push(notebookId, userId);

    const result = await pool.query(
      `UPDATE notebooks SET ${setClauses.join(', ')} 
       WHERE id = $${paramIndex++} AND user_id = $${paramIndex}
       RETURNING *`,
      values
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToNotebook(result.rows[0]);
  }

  /**
   * Search for an existing notebook by user ID and title/project keyword.
   */
  async findNotebookByTitle(userId: string, title: string): Promise<AgentNotebook | null> {
    const cleanTitle = title.trim();
    if (!cleanTitle) return null;

    const result = await pool.query(
      `SELECT * FROM notebooks
       WHERE user_id = $1 AND (LOWER(title) = LOWER($2) OR LOWER(title) LIKE LOWER($3))
       ORDER BY updated_at DESC LIMIT 1`,
      [userId, cleanTitle, `%${cleanTitle}%`]
    );

    if (result.rows.length === 0) {
      return null;
    }

    return this.mapRowToNotebook(result.rows[0]);
  }

  /**
   * Map a database row to an AgentNotebook object.
   */
  private mapRowToNotebook(row: any): AgentNotebook {
    return {
      id: row.id,
      userId: row.user_id,
      title: row.title,
      description: row.description,
      coverImage: row.cover_image,
      agentSessionId: row.agent_session_id,
      isAgentNotebook: row.is_agent_notebook ?? false,
      createdAt: new Date(row.created_at),
      updatedAt: new Date(row.updated_at),
    };
  }
}

// Export singleton instance
export const agentNotebookService = new AgentNotebookService();
export default agentNotebookService;
