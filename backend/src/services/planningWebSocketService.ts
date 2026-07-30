/**
 * Planning WebSocket Service
 * 
 * Provides real-time bidirectional communication for Planning Mode.
 * Enables instant updates when tasks are modified by agents or users.
 * 
 * Requirements: 6.1, 6.2 - Real-time synchronization
 */

import { WebSocket, WebSocketServer } from 'ws';
import { IncomingMessage } from 'http';
import jwt from 'jsonwebtoken';
import { parse } from 'url';
import pool from '../config/database.js';
import { getJwtSecret } from '../config/secrets.js';
import { TOKEN_PREFIX, tokenService } from './tokenService.js';

// ==================== INTERFACES ====================

interface PlanningConnection {
  ws: WebSocket;
  userId: string;
  planIds: Set<string>; // Plans this connection is subscribed to
  connectedAt: Date;
  lastPing: Date;
}

interface WebSocketMessage {
  type: 'subscribe' | 'unsubscribe' | 'ping' | 'pong' | 
        'task_updated' | 'task_created' | 'task_deleted' | 
        'plan_updated' | 'agent_output';
  payload?: any;
}

// ==================== SERVICE CLASS ====================

class PlanningWebSocketService {
  private wss: WebSocketServer | null = null;
  private connections: Map<string, PlanningConnection> = new Map(); // connectionId -> connection
  private userConnections: Map<string, Set<string>> = new Map(); // userId -> Set<connectionId>
  private planSubscriptions: Map<string, Set<string>> = new Map(); // planId -> Set<connectionId>
  private pingInterval: NodeJS.Timeout | null = null;
  private connectionCounter = 0;

  /**
   * Initialize the WebSocket server
   */
  initialize(server: any): void {
    this.wss = new WebSocketServer({ 
      server,
      path: '/ws/planning',
    });

    this.wss.on('error', (error) => {
      console.error('Planning WebSocket server error:', error);
    });

    this.wss.on('connection', (ws, req) => this.handleConnection(ws, req));

    // Set up ping interval to keep connections alive
    this.pingInterval = setInterval(() => {
      this.pingAllConnections();
    }, 30000); // Ping every 30 seconds

    console.log('📋 Planning WebSocket service initialized');
  }

  /**
   * Handle new WebSocket connection
   */
  private async handleConnection(ws: WebSocket, req: IncomingMessage): Promise<void> {
    const url = parse(req.url || '', true);
    const token = url.query.token as string;

    if (!token) {
      ws.close(4001, 'Authentication token required');
      return;
    }

    try {
      // Verify token and get user ID
      const userId = await this.verifyToken(token);
      if (!userId) {
        ws.close(4002, 'Invalid or expired token');
        return;
      }

      // Generate unique connection ID
      const connectionId = `planning_${++this.connectionCounter}_${Date.now()}`;

      // Store connection
      const connection: PlanningConnection = {
        ws,
        userId,
        planIds: new Set(),
        connectedAt: new Date(),
        lastPing: new Date(),
      };
      this.connections.set(connectionId, connection);

      // Track user connections
      if (!this.userConnections.has(userId)) {
        this.userConnections.set(userId, new Set());
      }
      this.userConnections.get(userId)!.add(connectionId);

      // Set up message handler
      ws.on('message', (data) => this.handleMessage(connectionId, data));

      // Set up close handler
      ws.on('close', () => this.handleDisconnect(connectionId));

      // Set up error handler
      ws.on('error', (error) => {
        console.error(`Planning WebSocket error for connection ${connectionId}:`, error);
      });

      // Send welcome message
      this.sendToConnection(connectionId, {
        type: 'pong',
        payload: {
          connectionId,
          message: 'Connected to Planning WebSocket',
          timestamp: new Date().toISOString(),
        },
      });

      console.log(`[Planning WS] User ${userId} connected (${connectionId})`);

    } catch (error) {
      console.error('Planning WebSocket authentication error:', error);
      ws.close(4000, 'Authentication failed');
    }
  }

  /**
   * Verify authentication token
   */
  private async verifyToken(token: string): Promise<string | null> {
    if (token.startsWith(TOKEN_PREFIX)) {
      try {
        const result = await tokenService.validateToken(token);
        return result.valid ? (result.userId ?? null) : null;
      } catch (error) {
        console.error('Planning WebSocket API token verification error:', error);
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

  /**
   * Handle incoming WebSocket message
   */
  private async handleMessage(connectionId: string, data: any): Promise<void> {
    const connection = this.connections.get(connectionId);
    if (!connection) return;

    try {
      const message: WebSocketMessage = JSON.parse(data.toString());

      switch (message.type) {
        case 'ping':
          connection.lastPing = new Date();
          this.sendToConnection(connectionId, { type: 'pong' });
          break;

        case 'subscribe':
          await this.handleSubscribe(connectionId, message.payload);
          break;

        case 'unsubscribe':
          this.handleUnsubscribe(connectionId, message.payload);
          break;

        default:
          console.log(`[Planning WS] Unknown message type: ${message.type}`);
      }
    } catch (error) {
      console.error('Error handling Planning WebSocket message:', error);
    }
  }

  /**
   * Handle plan subscription
   */
  private async handleSubscribe(connectionId: string, payload: any): Promise<void> {
    const connection = this.connections.get(connectionId);
    if (!connection || !payload?.planId) return;

    const { planId } = payload;

    // Verify user has access to the plan
    const hasAccess = await this.verifyPlanAccess(connection.userId, planId);
    if (!hasAccess) {
      this.sendToConnection(connectionId, {
        type: 'plan_updated',
        payload: { error: 'Access denied to plan', planId },
      });
      return;
    }

    // Add to subscriptions
    connection.planIds.add(planId);
    
    if (!this.planSubscriptions.has(planId)) {
      this.planSubscriptions.set(planId, new Set());
    }
    this.planSubscriptions.get(planId)!.add(connectionId);

    console.log(`[Planning WS] Connection ${connectionId} subscribed to plan ${planId}`);
  }

  /**
   * Handle plan unsubscription
   */
  private handleUnsubscribe(connectionId: string, payload: any): void {
    const connection = this.connections.get(connectionId);
    if (!connection || !payload?.planId) return;

    const { planId } = payload;

    connection.planIds.delete(planId);
    this.planSubscriptions.get(planId)?.delete(connectionId);

    console.log(`[Planning WS] Connection ${connectionId} unsubscribed from plan ${planId}`);
  }

  /**
   * Verify user has access to a plan
   */
  private async verifyPlanAccess(userId: string, planId: string): Promise<boolean> {
    try {
      const result = await pool.query(
        `SELECT id FROM plans WHERE id = $1 AND user_id = $2`,
        [planId, userId]
      );
      return result.rows.length > 0;
    } catch (error) {
      console.error('Plan access verification error:', error);
      return false;
    }
  }

  /**
   * Handle connection disconnect
   */
  private handleDisconnect(connectionId: string): void {
    const connection = this.connections.get(connectionId);
    if (!connection) return;

    // Remove from user connections
    this.userConnections.get(connection.userId)?.delete(connectionId);
    if (this.userConnections.get(connection.userId)?.size === 0) {
      this.userConnections.delete(connection.userId);
    }

    // Remove from plan subscriptions
    for (const planId of connection.planIds) {
      this.planSubscriptions.get(planId)?.delete(connectionId);
      if (this.planSubscriptions.get(planId)?.size === 0) {
        this.planSubscriptions.delete(planId);
      }
    }

    // Remove connection
    this.connections.delete(connectionId);

    console.log(`[Planning WS] Connection ${connectionId} disconnected`);
  }

  /**
   * Ping all connections to keep them alive
   */
  private pingAllConnections(): void {
    const now = new Date();
    const timeout = 60000; // 60 seconds timeout

    for (const [connectionId, connection] of this.connections) {
      // Check if connection is stale
      if (now.getTime() - connection.lastPing.getTime() > timeout) {
        console.log(`[Planning WS] Closing stale connection ${connectionId}`);
        connection.ws.close(4003, 'Connection timeout');
        this.handleDisconnect(connectionId);
        continue;
      }

      // Send ping
      if (connection.ws.readyState === WebSocket.OPEN) {
        this.sendToConnection(connectionId, { type: 'ping' });
      }
    }
  }

  /**
   * Send message to a specific connection
   */
  private sendToConnection(connectionId: string, message: WebSocketMessage): boolean {
    const connection = this.connections.get(connectionId);
    if (!connection || connection.ws.readyState !== WebSocket.OPEN) {
      return false;
    }

    try {
      connection.ws.send(JSON.stringify(message));
      return true;
    } catch (error) {
      console.error(`Error sending to connection ${connectionId}:`, error);
      return false;
    }
  }

  // ==================== PUBLIC BROADCAST METHODS ====================

  /**
   * Broadcast task update to all subscribers of a plan
   * Implements Requirement 6.1: Reflect changes within 5 seconds
   */
  broadcastTaskUpdate(planId: string, task: any): void {
    const subscribers = this.planSubscriptions.get(planId);
    if (!subscribers || subscribers.size === 0) return;

    const message: WebSocketMessage = {
      type: 'task_updated',
      payload: task,
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, message);
    }

    console.log(`[Planning WS] Broadcast task_updated to ${subscribers.size} subscribers for plan ${planId}`);
  }

  /**
   * Broadcast task creation to all subscribers of a plan
   */
  broadcastTaskCreated(planId: string, task: any): void {
    const subscribers = this.planSubscriptions.get(planId);
    if (!subscribers || subscribers.size === 0) return;

    const message: WebSocketMessage = {
      type: 'task_created',
      payload: task,
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, message);
    }

    console.log(`[Planning WS] Broadcast task_created to ${subscribers.size} subscribers for plan ${planId}`);
  }

  /**
   * Broadcast task deletion to all subscribers of a plan
   */
  broadcastTaskDeleted(planId: string, taskId: string): void {
    const subscribers = this.planSubscriptions.get(planId);
    if (!subscribers || subscribers.size === 0) return;

    const message: WebSocketMessage = {
      type: 'task_deleted',
      payload: { planId, taskId },
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, message);
    }

    console.log(`[Planning WS] Broadcast task_deleted to ${subscribers.size} subscribers for plan ${planId}`);
  }

  /**
   * Broadcast plan update to all subscribers
   */
  broadcastPlanUpdate(planId: string, plan: any): void {
    const subscribers = this.planSubscriptions.get(planId);
    if (!subscribers || subscribers.size === 0) return;

    const message: WebSocketMessage = {
      type: 'plan_updated',
      payload: plan,
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, message);
    }

    console.log(`[Planning WS] Broadcast plan_updated to ${subscribers.size} subscribers for plan ${planId}`);
  }

  /**
   * Broadcast agent output to all subscribers of a plan
   * Implements Requirement 6.2: Display agent comments/outputs
   */
  broadcastAgentOutput(planId: string, output: any): void {
    const subscribers = this.planSubscriptions.get(planId);
    if (!subscribers || subscribers.size === 0) return;

    const message: WebSocketMessage = {
      type: 'agent_output',
      payload: output,
    };

    for (const connectionId of subscribers) {
      this.sendToConnection(connectionId, message);
    }

    console.log(`[Planning WS] Broadcast agent_output to ${subscribers.size} subscribers for plan ${planId}`);
  }

  /**
   * Send message to all connections for a specific user
   */
  sendToUser(userId: string, message: WebSocketMessage): void {
    const connectionIds = this.userConnections.get(userId);
    if (!connectionIds) return;

    for (const connectionId of connectionIds) {
      this.sendToConnection(connectionId, message);
    }
  }

  /**
   * Get connection statistics
   */
  getStats(): { totalConnections: number; totalUsers: number; totalPlanSubscriptions: number } {
    return {
      totalConnections: this.connections.size,
      totalUsers: this.userConnections.size,
      totalPlanSubscriptions: this.planSubscriptions.size,
    };
  }

  /**
   * Shutdown the WebSocket service
   */
  shutdown(): void {
    if (this.pingInterval) {
      clearInterval(this.pingInterval);
      this.pingInterval = null;
    }

    for (const [connectionId, connection] of this.connections) {
      connection.ws.close(1001, 'Server shutting down');
    }

    this.connections.clear();
    this.userConnections.clear();
    this.planSubscriptions.clear();

    if (this.wss) {
      this.wss.close();
      this.wss = null;
    }

    console.log('📋 Planning WebSocket service shut down');
  }
}

// Export singleton instance
export const planningWebSocketService = new PlanningWebSocketService();
export default planningWebSocketService;
