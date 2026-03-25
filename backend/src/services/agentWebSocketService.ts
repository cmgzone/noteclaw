/**
 * Agent WebSocket Service
 * Provides real-time bidirectional communication between the app and coding agents.
 * 
 * This service manages WebSocket connections for instant message delivery.
 */

import { WebSocket, WebSocketServer } from 'ws';
import { IncomingMessage } from 'http';
import { parse } from 'url';
import jwt from 'jsonwebtoken';
import pool from '../config/database.js';
import { getJwtSecret } from '../config/secrets.js';
import {
  agentSessionService,
  type AgentSession,
} from './agentSessionService.js';
import { githubWebhookBuilder } from './githubWebhookBuilder.js';
import { TOKEN_PREFIX, tokenService } from './tokenService.js';
import {
  ImageAttachmentPayload,
  type WebhookPayload,
  webhookService,
} from './webhookService.js';
import {
  sourceConversationService,
  type SourceMessage,
} from './sourceConversationService.js';

// ==================== INTERFACES ====================

interface AgentConnection {
  ws: WebSocket;
  agentSessionId: string;
  userId: string;
  agentIdentifier: string;
  connectedAt: Date;
  lastPing: Date;
}

interface WebSocketMessage {
  type: 'followup_message' | 'ping' | 'pong' | 'subscribe' | 'unsubscribe' | 'response';
  payload?: any;
  messageId?: string;
}

interface FollowupPayload extends WebhookPayload {
  messageId: string;
  githubContext?: Record<string, unknown>;
}

// ==================== SERVICE CLASS ====================

class AgentWebSocketService {
  private wss: WebSocketServer | null = null;
  private connections: Map<string, AgentConnection> = new Map(); // sessionId -> connection
  private pingInterval: NodeJS.Timeout | null = null;

  /**
   * Initialize the WebSocket server
   */
  initialize(server: any): void {
    this.wss = new WebSocketServer({ 
      server,
      path: '/ws/agent',
    });

    this.wss.on('error', (error) => {
      console.error('Agent WebSocket server error:', error);
    });

    this.wss.on('connection', this.handleConnection.bind(this));

    // Start ping interval to keep connections alive
    this.pingInterval = setInterval(() => {
      this.pingAllConnections();
    }, 30000); // Ping every 30 seconds

    console.log('🔌 Agent WebSocket service initialized');
  }

  /**
   * Handle new WebSocket connection
   */
  private async handleConnection(ws: WebSocket, req: IncomingMessage): Promise<void> {
    const url = parse(req.url || '', true);
    const token = url.query.token as string;
    const requestedSessionId =
      typeof url.query.sessionId === 'string' ? url.query.sessionId.trim() : '';
    const requestedAgentIdentifier =
      typeof url.query.agentIdentifier === 'string'
        ? url.query.agentIdentifier.trim()
        : '';

    // Authenticate the connection
    if (!token) {
      ws.close(4001, 'Missing authentication token');
      return;
    }

    try {
      const auth = await this.verifyConnectionAuth(token);
      if (!auth) {
        ws.close(4002, 'Invalid authentication token');
        return;
      }

      let session: AgentSession | null = null;
      if (requestedSessionId) {
        session = await agentSessionService.getSession(requestedSessionId);
        if (!session || session.userId !== auth.userId) {
          ws.close(4003, 'Invalid agent session');
          return;
        }
      } else if (requestedAgentIdentifier) {
        session = await agentSessionService.getSessionByAgent(
          auth.userId,
          requestedAgentIdentifier,
        );
        if (!session) {
          ws.close(4003, 'Agent session not found for this identifier');
          return;
        }
      } else {
        ws.close(4003, 'sessionId or agentIdentifier is required');
        return;
      }

      const sessionId = session.id;
      const agentIdentifier = session.agentIdentifier;
      const existingConnection = this.connections.get(sessionId);
      if (existingConnection && existingConnection.ws !== ws) {
        existingConnection.ws.close(4005, 'Superseded by a newer connection');
      }

      // Store the connection
      const connection: AgentConnection = {
        ws,
        agentSessionId: sessionId,
        userId: auth.userId,
        agentIdentifier,
        connectedAt: new Date(),
        lastPing: new Date(),
      };

      this.connections.set(sessionId, connection);
      await agentSessionService.updateActivity(sessionId).catch((error) => {
        console.error(`[Agent WS] Failed to update activity for ${sessionId}:`, error);
      });

      console.log(`🔌 Agent connected: ${agentIdentifier} (session: ${sessionId})`);

      // Set up message handler
      ws.on('message', (data) => this.handleMessage(sessionId, data));

      // Set up close handler
      ws.on('close', () => {
        this.handleDisconnect(sessionId, ws);
      });

      // Set up error handler
      ws.on('error', (error) => {
        console.error(`WebSocket error for session ${sessionId}:`, error);
      });

      // Send welcome message
      this.sendToAgent(sessionId, {
        type: 'subscribe',
        payload: {
          sessionId,
          agentIdentifier,
          message: 'Connected to NoteClaw WebSocket',
          timestamp: new Date().toISOString(),
        },
      });

      await this.deliverPendingFollowups(sessionId, auth.userId);

    } catch (error) {
      console.error('WebSocket authentication error:', error);
      ws.close(4000, 'Authentication failed');
    }
  }

  private async verifyConnectionAuth(
    token: string,
  ): Promise<{ userId: string; authMethod: 'api_token' | 'jwt' } | null> {
    if (token.startsWith(TOKEN_PREFIX)) {
      const result = await tokenService.validateToken(token);
      if (!result.valid || !result.userId) {
        return null;
      }

      return {
        userId: result.userId,
        authMethod: 'api_token',
      };
    }

    try {
      const decoded = jwt.verify(token, getJwtSecret()) as { userId?: string };
      if (!decoded.userId) {
        return null;
      }

      return {
        userId: decoded.userId,
        authMethod: 'jwt',
      };
    } catch {
      return null;
    }
  }

  /**
   * Handle incoming WebSocket message
   */
  private async handleMessage(sessionId: string, data: any): Promise<void> {
    try {
      const message: WebSocketMessage = JSON.parse(data.toString());

      switch (message.type) {
        case 'pong':
          // Update last ping time
          const conn = this.connections.get(sessionId);
          if (conn) {
            conn.lastPing = new Date();
          }
          break;

        case 'response':
          // Agent is responding to a user message
          await this.handleAgentResponse(sessionId, message);
          break;

        default:
          console.log(`Unknown message type: ${message.type}`);
      }
    } catch (error) {
      console.error('Error handling WebSocket message:', error);
    }
  }

  /**
   * Handle agent response to a user message
   */
  private async handleAgentResponse(sessionId: string, message: WebSocketMessage): Promise<void> {
    const { messageId, payload } = message;

    if (!messageId || !payload?.response) {
      return;
    }

    try {
      const sourceResult = await pool.query(
        `SELECT sc.source_id
         FROM source_conversations sc
         JOIN conversation_messages cm ON cm.conversation_id = sc.id
         WHERE cm.id = $1
         LIMIT 1`,
        [messageId]
      );

      if (sourceResult.rows.length === 0) {
        console.warn(`[Agent WS] Could not resolve source for message ${messageId}`);
        return;
      }

      await sourceConversationService.addMessage(
        sourceResult.rows[0].source_id,
        'agent',
        payload.response,
        {
          agentSessionId: sessionId,
          metadata: {
            inReplyTo: messageId,
            codeUpdate: payload.codeUpdate,
            deliveredViaWebSocket: true,
          },
        }
      );

      // Mark the original message as read
      await pool.query(
        `UPDATE conversation_messages SET is_read = true WHERE id = $1`,
        [messageId]
      );

      // If there's a code update, update the source
      if (payload.codeUpdate?.code) {
        await pool.query(
          `UPDATE sources
           SET content = $1,
               metadata = jsonb_set(
                 COALESCE(metadata, '{}')::jsonb,
                 '{lastCodeUpdate}',
                 $2::jsonb
               ),
               updated_at = NOW()
           WHERE id = $3`,
          [
            payload.codeUpdate.code,
            JSON.stringify({
              description: payload.codeUpdate.description,
              updatedAt: new Date().toISOString(),
            }),
            sourceResult.rows[0].source_id,
          ]
        );
      }

      console.log(`✅ Agent response stored for message ${messageId}`);
      await agentSessionService.updateActivity(sessionId).catch((activityError) => {
        console.error(`[Agent WS] Failed to update activity for ${sessionId}:`, activityError);
      });
    } catch (error) {
      console.error('Error storing agent response:', error);
    }
  }

  private async deliverPendingFollowups(
    sessionId: string,
    userId: string,
  ): Promise<void> {
    try {
      const pendingMessages =
        await sourceConversationService.getPendingUserMessages(sessionId);

      if (pendingMessages.length === 0) {
        return;
      }

      let deliveredCount = 0;
      for (const pendingMessage of pendingMessages) {
        const payload = await this.buildFollowupPayload(pendingMessage, userId);
        if (!payload) {
          continue;
        }

        const sent = this.sendToAgent(sessionId, {
          type: 'followup_message',
          messageId: pendingMessage.id,
          payload,
        });

        if (!sent) {
          break;
        }

        deliveredCount += 1;
      }

      if (deliveredCount > 0) {
        console.log(
          `[Agent WS] Replayed ${deliveredCount} pending follow-up(s) for session ${sessionId}`,
        );
      }
    } catch (error) {
      console.error(`[Agent WS] Failed to deliver pending follow-ups for ${sessionId}:`, error);
    }
  }

  private async buildFollowupPayload(
    message: SourceMessage,
    userId: string,
  ): Promise<FollowupPayload | null> {
    const sourceResult = await pool.query(
      `SELECT type, metadata FROM sources WHERE id = $1 LIMIT 1`,
      [message.sourceId],
    );

    if (sourceResult.rows.length === 0) {
      return null;
    }

    const source = sourceResult.rows[0];
    const metadata =
      typeof source.metadata === 'string'
        ? JSON.parse(source.metadata)
        : (source.metadata || {});
    const imageAttachments = Array.isArray(message.metadata?.imageAttachments)
      ? (message.metadata.imageAttachments as ImageAttachmentPayload[])
      : undefined;
    const conversation = await sourceConversationService.getConversation(
      message.sourceId,
    );
    const conversationHistory = conversation?.messages ?? [message];
    const isGitHubSource = source.type === 'github' || metadata.type === 'github';

    const basePayload = isGitHubSource
      ? await githubWebhookBuilder.buildPayload({
          sourceId: message.sourceId,
          message: message.content,
          conversationHistory,
          imageAttachments,
          userId,
        })
      : await webhookService.buildPayload(
          message.sourceId,
          message.content,
          conversationHistory,
          userId,
          imageAttachments,
        );

    return {
      ...basePayload,
      messageId: message.id,
    };
  }

  private handleDisconnect(sessionId: string, ws?: WebSocket): void {
    const connection = this.connections.get(sessionId);
    if (!connection) {
      return;
    }

    if (ws && connection.ws !== ws) {
      return;
    }

    this.connections.delete(sessionId);
    console.log(
      `🔌 Agent disconnected: ${connection.agentIdentifier} (session: ${sessionId})`,
    );
  }

  /**
   * Send a message to a connected agent
   */
  sendToAgent(sessionId: string, message: WebSocketMessage): boolean {
    const connection = this.connections.get(sessionId);
    
    if (!connection || connection.ws.readyState !== WebSocket.OPEN) {
      return false;
    }

    try {
      connection.ws.send(JSON.stringify(message));
      return true;
    } catch (error) {
      console.error(`Error sending to agent ${sessionId}:`, error);
      return false;
    }
  }

  /**
   * Send a follow-up message to an agent
   */
  async sendFollowupToAgent(
    sessionId: string,
    payload: FollowupPayload
  ): Promise<boolean> {
    const sent = this.sendToAgent(sessionId, {
      type: 'followup_message',
      messageId: payload.messageId,
      payload,
    });

    if (sent) {
      await agentSessionService.updateActivity(sessionId).catch((error) => {
        console.error(`[Agent WS] Failed to update activity for ${sessionId}:`, error);
      });
    }

    return sent;
  }

  /**
   * Check if an agent is connected via WebSocket
   */
  isAgentConnected(sessionId: string): boolean {
    const connection = this.connections.get(sessionId);
    return connection !== undefined && connection.ws.readyState === WebSocket.OPEN;
  }

  /**
   * Get all connected agent sessions for a user
   */
  getConnectedAgents(userId: string): string[] {
    const sessions: string[] = [];
    
    this.connections.forEach((conn, sessionId) => {
      if (conn.userId === userId && conn.ws.readyState === WebSocket.OPEN) {
        sessions.push(sessionId);
      }
    });

    return sessions;
  }

  /**
   * Ping all connections to keep them alive
   */
  private pingAllConnections(): void {
    const now = new Date();
    const timeout = 60000; // 60 seconds timeout

    this.connections.forEach((conn, sessionId) => {
      // Check if connection is stale
      if (now.getTime() - conn.lastPing.getTime() > timeout) {
        console.log(`Closing stale connection: ${sessionId}`);
        conn.ws.close(4004, 'Connection timeout');
        this.connections.delete(sessionId);
        return;
      }

      // Send ping
      if (conn.ws.readyState === WebSocket.OPEN) {
        this.sendToAgent(sessionId, { type: 'ping' });
      }
    });
  }

  /**
   * Get connection statistics
   */
  getStats(): { totalConnections: number; connectionsByAgent: Record<string, number> } {
    const connectionsByAgent: Record<string, number> = {};

    this.connections.forEach((conn) => {
      connectionsByAgent[conn.agentIdentifier] = 
        (connectionsByAgent[conn.agentIdentifier] || 0) + 1;
    });

    return {
      totalConnections: this.connections.size,
      connectionsByAgent,
    };
  }

  /**
   * Shutdown the WebSocket service
   */
  shutdown(): void {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
    }

    this.connections.forEach((conn) => {
      conn.ws.close(1001, 'Server shutting down');
    });

    this.connections.clear();

    if (this.wss) {
      this.wss.close();
    }

    console.log('🔌 Agent WebSocket service shut down');
  }
}

// Export singleton instance
export const agentWebSocketService = new AgentWebSocketService();

export default agentWebSocketService;
