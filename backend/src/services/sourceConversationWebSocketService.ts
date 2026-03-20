/**
 * Source Conversation WebSocket Service
 *
 * Streams source follow-up conversation updates to the app UI in real time.
 */

import { IncomingMessage } from 'http';
import jwt from 'jsonwebtoken';
import { parse } from 'url';
import { WebSocket, WebSocketServer } from 'ws';
import pool from '../config/database.js';
import { getJwtSecret } from '../config/secrets.js';
import { TOKEN_PREFIX, tokenService } from './tokenService.js';
import type { SourceMessage } from './sourceConversationService.js';

interface SourceConversationConnection {
  ws: WebSocket;
  userId: string;
  sourceIds: Set<string>;
  connectedAt: Date;
  lastPing: Date;
}

interface SourceConversationSocketMessage {
  type:
    | 'subscribe'
    | 'unsubscribe'
    | 'ping'
    | 'pong'
    | 'conversation_message'
    | 'subscribed'
    | 'unsubscribed'
    | 'error';
  payload?: Record<string, unknown>;
}

class SourceConversationWebSocketService {
  private wss: WebSocketServer | null = null;
  private connections: Map<string, SourceConversationConnection> = new Map();
  private userConnections: Map<string, Set<string>> = new Map();
  private sourceSubscriptions: Map<string, Set<string>> = new Map();
  private pingInterval: NodeJS.Timeout | null = null;
  private connectionCounter = 0;

  initialize(server: any): void {
    this.wss = new WebSocketServer({
      server,
      path: '/ws/source-conversations',
    });

    this.wss.on('error', (error) => {
      console.error('Source conversation WebSocket server error:', error);
    });

    this.wss.on('connection', (ws, req) => this.handleConnection(ws, req));

    this.pingInterval = setInterval(() => {
      this.pingAllConnections();
    }, 30000);

    console.log('💬 Source conversation WebSocket service initialized');
  }

  private async handleConnection(
    ws: WebSocket,
    req: IncomingMessage,
  ): Promise<void> {
    const url = parse(req.url || '', true);
    const token = url.query.token as string | undefined;

    if (!token) {
      ws.close(4001, 'Authentication token required');
      return;
    }

    try {
      const userId = await this.verifyToken(token);
      if (!userId) {
        ws.close(4002, 'Invalid or expired token');
        return;
      }

      const connectionId = `source_${++this.connectionCounter}_${Date.now()}`;
      const connection: SourceConversationConnection = {
        ws,
        userId,
        sourceIds: new Set(),
        connectedAt: new Date(),
        lastPing: new Date(),
      };

      this.connections.set(connectionId, connection);

      if (!this.userConnections.has(userId)) {
        this.userConnections.set(userId, new Set());
      }
      this.userConnections.get(userId)!.add(connectionId);

      ws.on('message', (data) => this.handleMessage(connectionId, data));
      ws.on('close', () => this.handleDisconnect(connectionId));
      ws.on('error', (error) => {
        console.error(
          `Source conversation WebSocket error for ${connectionId}:`,
          error,
        );
      });

      this.sendToConnection(connectionId, {
        type: 'pong',
        payload: {
          connectionId,
          message: 'Connected to source conversation WebSocket',
          timestamp: new Date().toISOString(),
        },
      });

      console.log(`[Source WS] User ${userId} connected (${connectionId})`);
    } catch (error) {
      console.error('Source conversation WebSocket auth error:', error);
      ws.close(4000, 'Authentication failed');
    }
  }

  private async verifyToken(token: string): Promise<string | null> {
    if (token.startsWith(TOKEN_PREFIX)) {
      try {
        const result = await tokenService.validateToken(token);
        return result.valid ? (result.userId ?? null) : null;
      } catch (error) {
        console.error('Source WS API token verification error:', error);
        return null;
      }
    }

    try {
      const decoded = jwt.verify(token, getJwtSecret()) as {
        userId: string;
      };
      return decoded.userId;
    } catch {
      return null;
    }
  }

  private async handleMessage(connectionId: string, data: any): Promise<void> {
    const connection = this.connections.get(connectionId);
    if (!connection) return;

    try {
      const message = JSON.parse(
        data.toString(),
      ) as SourceConversationSocketMessage;

      switch (message.type) {
        case 'ping':
        case 'pong':
          connection.lastPing = new Date();
          if (message.type === 'ping') {
            this.sendToConnection(connectionId, { type: 'pong' });
          }
          break;
        case 'subscribe':
          await this.handleSubscribe(connectionId, message.payload);
          break;
        case 'unsubscribe':
          this.handleUnsubscribe(connectionId, message.payload);
          break;
        default:
          console.log(
            `[Source WS] Unknown message type from ${connectionId}: ${message.type}`,
          );
      }
    } catch (error) {
      console.error('Error handling source conversation WebSocket message:', error);
    }
  }

  private async handleSubscribe(
    connectionId: string,
    payload?: Record<string, unknown>,
  ): Promise<void> {
    const connection = this.connections.get(connectionId);
    const sourceId =
      typeof payload?.sourceId === 'string' ? payload.sourceId.trim() : '';

    if (!connection || sourceId.length === 0) {
      return;
    }

    const hasAccess = await this.verifySourceAccess(connection.userId, sourceId);
    if (!hasAccess) {
      this.sendToConnection(connectionId, {
        type: 'error',
        payload: {
          sourceId,
          message: 'Access denied to source conversation',
        },
      });
      return;
    }

    connection.sourceIds.add(sourceId);
    if (!this.sourceSubscriptions.has(sourceId)) {
      this.sourceSubscriptions.set(sourceId, new Set());
    }
    this.sourceSubscriptions.get(sourceId)!.add(connectionId);

    this.sendToConnection(connectionId, {
      type: 'subscribed',
      payload: { sourceId },
    });

    console.log(
      `[Source WS] Connection ${connectionId} subscribed to source ${sourceId}`,
    );
  }

  private handleUnsubscribe(
    connectionId: string,
    payload?: Record<string, unknown>,
  ): void {
    const connection = this.connections.get(connectionId);
    const sourceId =
      typeof payload?.sourceId === 'string' ? payload.sourceId.trim() : '';

    if (!connection || sourceId.length === 0) {
      return;
    }

    connection.sourceIds.delete(sourceId);
    const subscribers = this.sourceSubscriptions.get(sourceId);
    subscribers?.delete(connectionId);
    if (subscribers != null && subscribers.size === 0) {
      this.sourceSubscriptions.delete(sourceId);
    }

    this.sendToConnection(connectionId, {
      type: 'unsubscribed',
      payload: { sourceId },
    });

    console.log(
      `[Source WS] Connection ${connectionId} unsubscribed from source ${sourceId}`,
    );
  }

  private async verifySourceAccess(
    userId: string,
    sourceId: string,
  ): Promise<boolean> {
    try {
      const result = await pool.query(
        `SELECT id FROM sources WHERE id = $1 AND user_id = $2 LIMIT 1`,
        [sourceId, userId],
      );
      return result.rows.length > 0;
    } catch (error) {
      console.error('Source WS access check error:', error);
      return false;
    }
  }

  private handleDisconnect(connectionId: string): void {
    const connection = this.connections.get(connectionId);
    if (!connection) return;

    this.connections.delete(connectionId);

    const userConnections = this.userConnections.get(connection.userId);
    userConnections?.delete(connectionId);
    if (userConnections != null && userConnections.size === 0) {
      this.userConnections.delete(connection.userId);
    }

    for (const sourceId of connection.sourceIds) {
      const subscribers = this.sourceSubscriptions.get(sourceId);
      subscribers?.delete(connectionId);
      if (subscribers != null && subscribers.size === 0) {
        this.sourceSubscriptions.delete(sourceId);
      }
    }

    console.log(`[Source WS] User ${connection.userId} disconnected (${connectionId})`);
  }

  private sendToConnection(
    connectionId: string,
    message: SourceConversationSocketMessage,
  ): boolean {
    const connection = this.connections.get(connectionId);
    if (!connection || connection.ws.readyState !== WebSocket.OPEN) {
      return false;
    }

    try {
      connection.ws.send(JSON.stringify(message));
      return true;
    } catch (error) {
      console.error(`[Source WS] Failed to send to ${connectionId}:`, error);
      return false;
    }
  }

  broadcastMessage(message: SourceMessage): void {
    const subscribers = this.sourceSubscriptions.get(message.sourceId);
    if (subscribers == null || subscribers.size === 0) {
      return;
    }

    const payload = {
      sourceId: message.sourceId,
      message: {
        id: message.id,
        conversationId: message.conversationId,
        sourceId: message.sourceId,
        role: message.role,
        content: message.content,
        metadata: message.metadata,
        isRead: message.isRead,
        createdAt: message.createdAt.toISOString(),
      },
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, {
        type: 'conversation_message',
        payload,
      });
    }

    console.log(
      `[Source WS] Broadcast conversation_message to ${subscribers.size} subscribers for source ${message.sourceId}`,
    );
  }

  private pingAllConnections(): void {
    const now = new Date();
    const timeoutMs = 60000;

    for (const [connectionId, connection] of Array.from(
      this.connections.entries(),
    )) {
      if (now.getTime() - connection.lastPing.getTime() > timeoutMs) {
        console.log(`[Source WS] Closing stale connection ${connectionId}`);
        connection.ws.close(4004, 'Connection timeout');
        this.handleDisconnect(connectionId);
        continue;
      }

      this.sendToConnection(connectionId, { type: 'ping' });
    }
  }

  getStats() {
    return {
      totalConnections: this.connections.size,
      subscribedSources: this.sourceSubscriptions.size,
      connectedUsers: this.userConnections.size,
    };
  }
}

export const sourceConversationWebSocketService =
  new SourceConversationWebSocketService();
export default sourceConversationWebSocketService;
