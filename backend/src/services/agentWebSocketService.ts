/**
 * Live transport for NoteClaw memory agents.
 *
 * MCP remains the command surface for opening sessions and reading/writing
 * memory. WebSocket supplies presence, keep-alives, and immediate memory-change
 * notifications without polling.
 */

import { IncomingMessage } from 'http';
import { randomUUID } from 'crypto';
import jwt from 'jsonwebtoken';
import { parse } from 'url';
import { WebSocket, type WebSocketServer } from 'ws';

import pool from '../config/database.js';
import { getJwtSecret } from '../config/secrets.js';
import {
  agentSessionService,
  type AgentSession,
} from './agentSessionService.js';
import { userHasPlanFeature } from './planFeatureService.js';
import { sourceConversationService } from './sourceConversationService.js';
import { TOKEN_PREFIX, tokenService } from './tokenService.js';
import { createPathWebSocketServer } from './webSocketUpgradeRouter.js';

interface AgentConnection {
  connectionId: string;
  ws: WebSocket;
  agentSessionId: string;
  userId: string;
  agentIdentifier: string;
  clientIdentifier: string;
  connectedAt: Date;
  lastPong: Date;
}

interface WebSocketMessage {
  type: string;
  payload?: unknown;
  messageId?: string;
}

class AgentWebSocketService {
  private wss: WebSocketServer | null = null;
  private readonly connections = new Map<
    string,
    Map<string, AgentConnection>
  >();
  private pingInterval: NodeJS.Timeout | null = null;

  initialize(server: any): void {
    this.wss = createPathWebSocketServer(server, '/ws/agent');

    this.wss.on('error', (error) => {
      console.error('Agent WebSocket server error:', error);
    });
    this.wss.on('connection', (ws, request) => {
      void this.handleConnection(ws, request);
    });

    this.pingInterval = setInterval(() => {
      this.pingAllConnections();
    }, 30_000);

    console.log('Agent memory WebSocket service initialized');
  }

  private async handleConnection(
    ws: WebSocket,
    request: IncomingMessage,
  ): Promise<void> {
    const url = parse(request.url || '', true);
    const token = typeof url.query.token === 'string' ? url.query.token : '';
    const requestedSessionId =
      typeof url.query.sessionId === 'string'
        ? url.query.sessionId.trim()
        : '';
    const requestedAgentIdentifier =
      typeof url.query.agentIdentifier === 'string'
        ? url.query.agentIdentifier.trim()
        : '';
    const requestedClientIdentifier =
      typeof url.query.clientIdentifier === 'string'
        ? url.query.clientIdentifier.trim()
        : '';

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
      const websocketAccess = await userHasPlanFeature(
        auth.userId,
        'websocket_collaboration',
      );
      if (!websocketAccess.allowed) {
        ws.close(4004, 'WebSocket collaboration is not included in this plan');
        return;
      }

      const boundSessionId =
        auth.authMethod === 'api_token' &&
        typeof auth.tokenMetadata?.boundAgentSessionId === 'string'
          ? auth.tokenMetadata.boundAgentSessionId
          : '';
      if (auth.authMethod === 'api_token' && !boundSessionId) {
        ws.close(
          4005,
          'Open the memory session with MCP before connecting WebSocket',
        );
        return;
      }

      const session = await this.resolveSession(
        auth.userId,
        requestedSessionId || boundSessionId,
        requestedAgentIdentifier,
      );
      if (!session) {
        ws.close(4003, 'Memory session not found');
        return;
      }
      if (auth.authMethod === 'api_token') {
        if (boundSessionId !== session.id) {
          ws.close(4003, 'This token belongs to another agent session');
          return;
        }
      }

      const connectionId = randomUUID();
      const registeredClientIdentifier =
        typeof session.metadata?.lastMcpClientName === 'string'
          ? session.metadata.lastMcpClientName.trim()
          : typeof session.metadata?.clientName === 'string'
            ? session.metadata.clientName.trim()
            : '';
      const clientIdentifier =
        requestedClientIdentifier ||
        registeredClientIdentifier ||
        session.agentName ||
        `client:${connectionId}`;
      const sessionConnections =
        this.connections.get(session.id) || new Map<string, AgentConnection>();
      const connection: AgentConnection = {
        connectionId,
        ws,
        agentSessionId: session.id,
        userId: auth.userId,
        agentIdentifier: session.agentIdentifier,
        clientIdentifier,
        connectedAt: new Date(),
        lastPong: new Date(),
      };
      sessionConnections.set(connectionId, connection);
      this.connections.set(session.id, sessionConnections);

      await agentSessionService.updateActivity(session.id).catch((error) => {
        console.error(
          `[Agent WS] Failed to update activity for ${session.id}:`,
          error,
        );
      });

      ws.on('message', (data) => {
        void this.handleMessage(session.id, connectionId, data);
      });
      ws.on('close', () =>
        this.handleDisconnect(session.id, connectionId, ws),
      );
      ws.on('error', (error) => {
        console.error(
          `WebSocket error for memory session ${session.id} (${clientIdentifier}):`,
          error,
        );
      });

      this.sendToConnection(connection, {
        type: 'memory_ready',
        payload: {
          sessionId: session.id,
          agentIdentifier: session.agentIdentifier,
          clientIdentifier,
          connectionId,
          connectedClients: sessionConnections.size,
          message: 'Connected to NoteClaw Memory',
          timestamp: new Date().toISOString(),
        },
      });

      this.sendToAgent(session.id, {
        type: 'agent_joined',
        payload: {
          sessionId: session.id,
          clientIdentifier,
          connectionId,
          connectedClients: sessionConnections.size,
          timestamp: new Date().toISOString(),
        },
      });
    } catch (error) {
      console.error('WebSocket authentication error:', error);
      ws.close(4000, 'Authentication failed');
    }
  }

  private async resolveSession(
    userId: string,
    sessionId: string,
    agentIdentifier: string,
  ): Promise<AgentSession | null> {
    if (sessionId) {
      const session = await agentSessionService.getSession(sessionId);
      return session?.userId === userId ? session : null;
    }

    if (agentIdentifier) {
      return agentSessionService.getSessionByAgent(userId, agentIdentifier);
    }

    return null;
  }

  private async verifyConnectionAuth(
    token: string,
  ): Promise<{
    userId: string;
    authMethod: 'jwt' | 'api_token';
    tokenMetadata?: Record<string, any>;
  } | null> {
    if (token.startsWith(TOKEN_PREFIX)) {
      const result = await tokenService.validateToken(token);
      return result.valid && result.userId
        ? {
            userId: result.userId,
            authMethod: 'api_token',
            tokenMetadata: result.metadata || {},
          }
        : null;
    }

    try {
      const decoded = jwt.verify(token, getJwtSecret()) as { userId?: string };
      return decoded.userId
        ? { userId: decoded.userId, authMethod: 'jwt' }
        : null;
    } catch {
      return null;
    }
  }

  private async handleMessage(
    sessionId: string,
    connectionId: string,
    data: WebSocket.RawData,
  ): Promise<void> {
    const connection = this.connections.get(sessionId)?.get(connectionId);
    if (!connection) {
      return;
    }

    let message: WebSocketMessage;
    try {
      message = JSON.parse(data.toString()) as WebSocketMessage;
    } catch {
      this.sendToConnection(connection, {
        type: 'error',
        payload: {
          code: 'invalid_json',
          message: 'WebSocket messages must be valid JSON.',
        },
      });
      return;
    }

    try {
      if (message.type === 'pong') {
        connection.lastPong = new Date();
        return;
      }

      if (message.type === 'ping') {
        this.sendToConnection(connection, {
          type: 'pong',
          payload: { timestamp: new Date().toISOString() },
        });
        return;
      }

      if (message.type === 'followup_response') {
        await this.handleFollowupResponse(connection, message);
        return;
      }

      this.sendToConnection(connection, {
        type: 'error',
        payload: {
          code: 'unsupported_message',
          message:
            'Memory commands use MCP tools. WebSocket accepts ping, pong, and followup_response.',
        },
      });
    } catch (error) {
      console.error(
        `[Agent WS] Failed to handle ${message.type} for ${sessionId}:`,
        error,
      );
      this.sendToConnection(connection, {
        type: 'error',
        messageId: message.messageId,
        payload: {
          code: 'message_processing_failed',
          message: 'The WebSocket message could not be processed.',
        },
      });
    }
  }

  private async handleFollowupResponse(
    connection: AgentConnection,
    message: WebSocketMessage,
  ): Promise<void> {
    const payload =
      message.payload && typeof message.payload === 'object'
        ? message.payload as Record<string, any>
        : {};
    const messageId =
      (typeof message.messageId === 'string' ? message.messageId : '')
      || (typeof payload.messageId === 'string' ? payload.messageId : '');
    const response =
      typeof payload.response === 'string' ? payload.response.trim() : '';
    const codeUpdate =
      payload.codeUpdate && typeof payload.codeUpdate === 'object'
        ? payload.codeUpdate as Record<string, any>
        : null;

    if (!messageId || !response) {
      this.sendToConnection(connection, {
        type: 'error',
        messageId: messageId || undefined,
        payload: {
          code: 'invalid_followup_response',
          message:
            'followup_response requires messageId and payload.response.',
        },
      });
      return;
    }

    const originalResult = await pool.query(
      `SELECT cm.role, sc.source_id, sc.agent_session_id, s.type AS source_type
       FROM conversation_messages cm
       JOIN source_conversations sc ON sc.id = cm.conversation_id
       JOIN sources s ON s.id = sc.source_id
       JOIN notebooks n ON n.id = s.notebook_id
       WHERE cm.id = $1
         AND sc.agent_session_id = $2
         AND n.user_id = $3`,
      [messageId, connection.agentSessionId, connection.userId],
    );
    if (originalResult.rows.length === 0) {
      this.sendToConnection(connection, {
        type: 'error',
        messageId,
        payload: {
          code: 'followup_not_found',
          message: 'The chat message was not found for this agent session.',
        },
      });
      return;
    }

    const original = originalResult.rows[0];
    if (original.role !== 'user') {
      this.sendToConnection(connection, {
        type: 'error',
        messageId,
        payload: {
          code: 'invalid_followup_target',
          message: 'Agents can only respond to user messages.',
        },
      });
      return;
    }

    const agentMessage = await sourceConversationService.addMessage(
      original.source_id,
      'agent',
      response,
      {
        agentSessionId: connection.agentSessionId,
        metadata: {
          codeUpdate,
          inReplyTo: messageId,
          deliveredViaWebSocket: true,
          clientIdentifier: connection.clientIdentifier,
        },
      },
    );
    await sourceConversationService.markMessagesAsRead([messageId]);

    let codeUpdated = false;
    if (
      original.source_type !== 'agent_chat'
      && typeof codeUpdate?.code === 'string'
      && codeUpdate.code.length > 0
    ) {
      await pool.query(
        `UPDATE sources
         SET content = $1,
             metadata = jsonb_set(
               COALESCE(metadata, '{}')::jsonb,
               '{lastCodeUpdate}',
               $2::jsonb
             ),
             updated_at = NOW()
         WHERE id = $3 AND user_id = $4`,
        [
          codeUpdate.code,
          JSON.stringify({
            description: codeUpdate.description,
            updatedAt: new Date().toISOString(),
          }),
          original.source_id,
          connection.userId,
        ],
      );
      codeUpdated = true;
    }

    this.sendToConnection(connection, {
      type: 'followup_response_accepted',
      messageId,
      payload: {
        messageId,
        agentMessage,
        codeUpdated,
        timestamp: new Date().toISOString(),
      },
    });
  }

  notifyMemoryChanged(
    sessionId: string,
    payload: Record<string, unknown>,
  ): boolean {
    return this.sendToAgent(sessionId, {
      type: 'memory_changed',
      payload: {
        ...payload,
        timestamp: new Date().toISOString(),
      },
    });
  }

  notifyMemoryCompacted(
    sessionId: string,
    payload: Record<string, unknown>,
  ): boolean {
    return this.sendToAgent(sessionId, {
      type: 'memory_compacted',
      payload: {
        ...payload,
        timestamp: new Date().toISOString(),
      },
    });
  }

  sendToAgent(sessionId: string, message: WebSocketMessage): boolean {
    const sessionConnections = this.connections.get(sessionId);
    if (!sessionConnections) {
      return false;
    }

    let delivered = false;
    for (const connection of sessionConnections.values()) {
      delivered = this.sendToConnection(connection, message) || delivered;
    }
    return delivered;
  }

  /**
   * Delivers a user chat turn immediately to every live client in the session.
   */
  async sendFollowupToAgent(
    sessionId: string,
    payload: Record<string, any>,
  ): Promise<boolean> {
    return this.sendToAgent(sessionId, {
      type: 'followup_message',
      messageId: payload.messageId,
      payload,
    });
  }

  isAgentConnected(sessionId: string): boolean {
    return this.getConnectionCount(sessionId) > 0;
  }

  getConnectionCount(sessionId: string): number {
    const sessionConnections = this.connections.get(sessionId);
    if (!sessionConnections) {
      return 0;
    }

    return [...sessionConnections.values()].filter(
      (connection) => connection.ws.readyState === WebSocket.OPEN,
    ).length;
  }

  getConnectedClients(sessionId: string): string[] {
    const sessionConnections = this.connections.get(sessionId);
    if (!sessionConnections) {
      return [];
    }

    return [
      ...new Set(
        [...sessionConnections.values()]
          .filter((connection) => connection.ws.readyState === WebSocket.OPEN)
          .map((connection) => connection.clientIdentifier),
      ),
    ].sort();
  }

  getConnectedAgents(userId: string): string[] {
    return [...this.connections.entries()]
      .filter(
        ([, sessionConnections]) =>
          [...sessionConnections.values()].some(
            (connection) =>
              connection.userId === userId &&
              connection.ws.readyState === WebSocket.OPEN,
          ),
      )
      .map(([sessionId]) => sessionId);
  }

  getStats(): {
    totalConnections: number;
    connectionsByAgent: Record<string, number>;
  } {
    const connectionsByAgent: Record<string, number> = {};
    let totalConnections = 0;
    for (const sessionConnections of this.connections.values()) {
      for (const connection of sessionConnections.values()) {
        if (connection.ws.readyState !== WebSocket.OPEN) {
          continue;
        }
        totalConnections += 1;
        connectionsByAgent[connection.agentIdentifier] =
          (connectionsByAgent[connection.agentIdentifier] || 0) + 1;
      }
    }

    return {
      totalConnections,
      connectionsByAgent,
    };
  }

  private sendToConnection(
    connection: AgentConnection,
    message: WebSocketMessage,
  ): boolean {
    if (connection.ws.readyState !== WebSocket.OPEN) {
      return false;
    }

    try {
      connection.ws.send(JSON.stringify(message));
      return true;
    } catch (error) {
      console.error(
        `Failed to send WebSocket event to ${connection.agentSessionId} (${connection.clientIdentifier}):`,
        error,
      );
      return false;
    }
  }

  private handleDisconnect(
    sessionId: string,
    connectionId: string,
    socket: WebSocket,
  ): void {
    const sessionConnections = this.connections.get(sessionId);
    const connection = sessionConnections?.get(connectionId);
    if (!sessionConnections || !connection || connection.ws !== socket) {
      return;
    }

    sessionConnections.delete(connectionId);
    if (sessionConnections.size === 0) {
      this.connections.delete(sessionId);
    }

    this.sendToAgent(sessionId, {
      type: 'agent_left',
      payload: {
        sessionId,
        clientIdentifier: connection.clientIdentifier,
        connectionId,
        connectedClients: sessionConnections.size,
        timestamp: new Date().toISOString(),
      },
    });
  }

  private removeTimedOutConnection(
    sessionId: string,
    connection: AgentConnection,
  ): void {
    connection.ws.close(4004, 'Connection timeout');
    this.handleDisconnect(sessionId, connection.connectionId, connection.ws);
  }

  private pingAllConnections(): void {
    const now = Date.now();
    for (const [sessionId, sessionConnections] of this.connections.entries()) {
      for (const connection of [...sessionConnections.values()]) {
        if (now - connection.lastPong.getTime() > 60_000) {
          this.removeTimedOutConnection(sessionId, connection);
          continue;
        }

        this.sendToConnection(connection, {
          type: 'ping',
          payload: { timestamp: new Date().toISOString() },
        });
      }
    }
  }

  shutdown(): void {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }

    for (const sessionConnections of this.connections.values()) {
      for (const connection of sessionConnections.values()) {
        connection.ws.close(1001, 'Server shutting down');
      }
    }
    this.connections.clear();
    this.wss?.close();
    this.wss = null;
  }
}

export const agentWebSocketService = new AgentWebSocketService();
export default agentWebSocketService;
