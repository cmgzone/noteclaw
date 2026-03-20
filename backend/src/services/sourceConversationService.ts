/**
 * Source Conversation Service
 * Manages chat threads on sources for bidirectional communication with coding agents.
 * 
 * Requirements: 3.2, 3.3, 3.5
 */

import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { sourceConversationWebSocketService } from './sourceConversationWebSocketService.js';

// ==================== INTERFACES ====================

export interface SourceMessage {
  id: string;
  conversationId: string;
  sourceId: string;
  role: 'user' | 'agent';
  content: string;
  metadata: Record<string, any>;
  isRead: boolean;
  createdAt: Date;
}

export interface SourceConversation {
  id: string;
  sourceId: string;
  agentSessionId: string | null;
  messages: SourceMessage[];
  createdAt: Date;
  lastMessageAt: Date | null;
}

export interface AddMessageOptions {
  metadata?: Record<string, any>;
  agentSessionId?: string;
}

// ==================== SERVICE CLASS ====================

class SourceConversationService {
  /**
   * Add a message to a source conversation.
   * Creates the conversation if it doesn't exist.
   * Implements Requirement 3.5 - maintain conversation history.
   * 
   * @param sourceId - The source ID
   * @param role - 'user' or 'agent'
   * @param content - The message content
   * @param options - Optional metadata
   * @returns The created SourceMessage
   */
  async addMessage(
    sourceId: string,
    role: 'user' | 'agent',
    content: string,
    options: AddMessageOptions = {}
  ): Promise<SourceMessage> {
    const { metadata = {}, agentSessionId } = options;

    // Get or create conversation for this source
    const conversation = await this.getOrCreateConversation(sourceId, agentSessionId);

    // Create the message
    const messageId = uuidv4();
    const result = await pool.query(
      `INSERT INTO conversation_messages 
       (id, conversation_id, role, content, metadata, is_read, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW())
       RETURNING *`,
      [messageId, conversation.id, role, content, JSON.stringify(metadata), role === 'agent']
    );

    const message = this.mapRowToMessage(result.rows[0], sourceId);
    sourceConversationWebSocketService.broadcastMessage(message);
    return message;
  }

  /**
   * Get a conversation for a source with all messages.
   * Implements Requirement 3.5 - maintain conversation history.
   * 
   * @param sourceId - The source ID
   * @returns The SourceConversation with messages, or null if no conversation exists
   */
  async getConversation(sourceId: string): Promise<SourceConversation | null> {
    // Get the conversation
    const convResult = await pool.query(
      `SELECT * FROM source_conversations WHERE source_id = $1`,
      [sourceId]
    );

    if (convResult.rows.length === 0) {
      return null;
    }

    const convRow = convResult.rows[0];

    // Get all messages for this conversation
    const messagesResult = await pool.query(
      `SELECT * FROM conversation_messages 
       WHERE conversation_id = $1 
       ORDER BY created_at ASC`,
      [convRow.id]
    );

    const messages = messagesResult.rows.map(row => this.mapRowToMessage(row, sourceId));

    // Calculate last message timestamp
    const lastMessageAt = messages.length > 0 
      ? messages[messages.length - 1].createdAt 
      : null;

    return {
      id: convRow.id,
      sourceId: convRow.source_id,
      agentSessionId: convRow.agent_session_id,
      messages,
      createdAt: new Date(convRow.created_at),
      lastMessageAt,
    };
  }

  /**
   * Get pending (unread) user messages for an agent session.
   * Used by agents to poll for new messages (Requirement 3.2).
   * 
   * @param agentSessionId - The agent session ID
   * @returns Array of unread user messages
   */
  async getPendingUserMessages(agentSessionId: string): Promise<SourceMessage[]> {
    const result = await pool.query(
      `SELECT cm.*, sc.source_id
       FROM conversation_messages cm
       JOIN source_conversations sc ON cm.conversation_id = sc.id
       WHERE sc.agent_session_id = $1 
         AND cm.role = 'user' 
         AND cm.is_read = false
       ORDER BY cm.created_at ASC`,
      [agentSessionId]
    );

    return result.rows.map(row => this.mapRowToMessage(row, row.source_id));
  }

  /**
   * Mark messages as read.
   * 
   * @param messageIds - Array of message IDs to mark as read
   */
  async markMessagesAsRead(messageIds: string[]): Promise<void> {
    if (messageIds.length === 0) return;

    await pool.query(
      `UPDATE conversation_messages SET is_read = true WHERE id = ANY($1)`,
      [messageIds]
    );
  }

  /**
   * Mark all messages in a conversation as read.
   * 
   * @param conversationId - The conversation ID
   */
  async markConversationAsRead(conversationId: string): Promise<void> {
    await pool.query(
      `UPDATE conversation_messages SET is_read = true WHERE conversation_id = $1`,
      [conversationId]
    );
  }

  /**
   * Get or create a conversation for a source.
   * 
   * @param sourceId - The source ID
   * @param agentSessionId - Optional agent session ID to associate
   * @returns The existing or new conversation
   */
  async getOrCreateConversation(
    sourceId: string,
    agentSessionId?: string
  ): Promise<{ id: string; sourceId: string; agentSessionId: string | null }> {
    // Try to get existing conversation
    const existing = await pool.query(
      `SELECT id, source_id, agent_session_id FROM source_conversations WHERE source_id = $1`,
      [sourceId]
    );

    if (existing.rows.length > 0) {
      const row = existing.rows[0];
      
      // Update agent session ID if provided and not already set
      if (agentSessionId && !row.agent_session_id) {
        await pool.query(
          `UPDATE source_conversations SET agent_session_id = $1 WHERE id = $2`,
          [agentSessionId, row.id]
        );
        row.agent_session_id = agentSessionId;
      }
      
      return {
        id: row.id,
        sourceId: row.source_id,
        agentSessionId: row.agent_session_id,
      };
    }

    // Create new conversation
    const conversationId = uuidv4();
    
    // First, try to get agent session ID from source metadata if not provided
    let sessionId = agentSessionId;
    if (!sessionId) {
      const sourceResult = await pool.query(
        `SELECT s.metadata, n.agent_session_id
         FROM sources s
         LEFT JOIN notebooks n ON s.notebook_id = n.id
         WHERE s.id = $1`,
        [sourceId]
      );
      if (sourceResult.rows.length > 0) {
        const row = sourceResult.rows[0];
        const metadata = typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {});
        sessionId = metadata?.agentSessionId || row.agent_session_id;
      }
    }

    const result = await pool.query(
      `INSERT INTO source_conversations (id, source_id, agent_session_id, created_at)
       VALUES ($1, $2, $3, NOW())
       RETURNING id, source_id, agent_session_id`,
      [conversationId, sourceId, sessionId || null]
    );

    const row = result.rows[0];
    return {
      id: row.id,
      sourceId: row.source_id,
      agentSessionId: row.agent_session_id,
    };
  }

  /**
   * Delete a conversation and all its messages.
   * 
   * @param sourceId - The source ID
   * @returns true if deleted, false if not found
   */
  async deleteConversation(sourceId: string): Promise<boolean> {
    const result = await pool.query(
      `DELETE FROM source_conversations WHERE source_id = $1 RETURNING id`,
      [sourceId]
    );

    return result.rows.length > 0;
  }

  /**
   * Get message count for a conversation.
   * 
   * @param sourceId - The source ID
   * @returns The number of messages
   */
  async getMessageCount(sourceId: string): Promise<number> {
    const result = await pool.query(
      `SELECT COUNT(*) as count 
       FROM conversation_messages cm
       JOIN source_conversations sc ON cm.conversation_id = sc.id
       WHERE sc.source_id = $1`,
      [sourceId]
    );

    return parseInt(result.rows[0].count, 10);
  }

  /**
   * Get unread message count for a conversation.
   * 
   * @param sourceId - The source ID
   * @returns The number of unread messages
   */
  async getUnreadCount(sourceId: string): Promise<number> {
    const result = await pool.query(
      `SELECT COUNT(*) as count 
       FROM conversation_messages cm
       JOIN source_conversations sc ON cm.conversation_id = sc.id
       WHERE sc.source_id = $1 AND cm.is_read = false`,
      [sourceId]
    );

    return parseInt(result.rows[0].count, 10);
  }

  /**
   * Map a database row to a SourceMessage object.
   */
  private mapRowToMessage(row: any, sourceId: string): SourceMessage {
    return {
      id: row.id,
      conversationId: row.conversation_id,
      sourceId,
      role: row.role as 'user' | 'agent',
      content: row.content,
      metadata: typeof row.metadata === 'string' ? JSON.parse(row.metadata) : (row.metadata || {}),
      isRead: row.is_read ?? false,
      createdAt: new Date(row.created_at),
    };
  }
}

// Export singleton instance
export const sourceConversationService = new SourceConversationService();
export default sourceConversationService;
