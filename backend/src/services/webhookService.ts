/**
 * Webhook Service
 * Handles communication with third-party coding agents via webhooks.
 * 
 * Requirements: 5.1, 5.2, 5.3, 5.4, 3.4
 */

import crypto from 'crypto';
import pool from '../config/database.js';
import { agentSessionService, AgentSession } from './agentSessionService.js';
import { SourceMessage } from './sourceConversationService.js';

// ==================== INTERFACES ====================

export interface WebhookPayload {
  type: 'followup_message';
  sourceId: string;
  sourceTitle: string;
  sourceCode: string;
  sourceLanguage: string;
  message: string;
  conversationHistory: SourceMessage[];
  imageAttachments?: ImageAttachmentPayload[];
  userId: string;
  timestamp: string;
}

export interface ImageAttachmentPayload {
  id: string;
  name: string;
  mimeType: string;
  base64Data: string;
  sizeBytes: number;
}

export interface WebhookResponse {
  success: boolean;
  response?: string;
  codeUpdate?: {
    code: string;
    description: string;
  };
  error?: string;
}

export interface WebhookConfig {
  url: string;
  secret: string;
}

export interface RetryConfig {
  maxRetries: number;
  baseDelayMs: number;
  maxDelayMs: number;
}

// Default retry configuration with exponential backoff
const DEFAULT_RETRY_CONFIG: RetryConfig = {
  maxRetries: 5,
  baseDelayMs: 1000,  // 1 second
  maxDelayMs: 16000,  // 16 seconds max
};

// ==================== SERVICE CLASS ====================

class WebhookService {
  private retryConfig: RetryConfig;

  constructor(retryConfig: RetryConfig = DEFAULT_RETRY_CONFIG) {
    this.retryConfig = retryConfig;
  }

  /**
   * Register a webhook endpoint for an agent session.
   * Implements Requirement 5.1 - accept webhook URL for receiving follow-up messages.
   * 
   * @param sessionId - The agent session ID
   * @param url - The webhook URL
   * @param secret - The shared secret for authentication
   */
  async registerWebhook(sessionId: string, url: string, secret: string): Promise<void> {
    // Validate URL format
    if (!this.isValidWebhookUrl(url)) {
      throw new Error('Invalid webhook URL. Must be a valid HTTPS URL.');
    }

    // Validate secret
    if (!secret || secret.length < 16) {
      throw new Error('Webhook secret must be at least 16 characters.');
    }

    // Update the session with webhook configuration
    await pool.query(
      `UPDATE agent_sessions 
       SET webhook_url = $1, webhook_secret = $2, last_activity = NOW() 
       WHERE id = $3`,
      [url, secret, sessionId]
    );
  }

  /**
   * Send a follow-up message to the agent's webhook endpoint.
   * Implements Requirements 3.2, 5.2 - route messages to webhook with complete payload.
   * Implements Requirement 3.4 - retry with exponential backoff on failure.
   * 
   * @param sessionId - The agent session ID
   * @param payload - The webhook payload
   * @returns The webhook response
   */
  async sendFollowup(sessionId: string, payload: WebhookPayload): Promise<WebhookResponse> {
    // Get session with webhook configuration
    const session = await agentSessionService.getSession(sessionId);
    
    if (!session) {
      return { success: false, error: 'Session not found' };
    }

    if (session.status === 'disconnected') {
      return { success: false, error: 'Session is disconnected' };
    }

    if (!session.webhookUrl || !session.webhookSecret) {
      return { success: false, error: 'Webhook not configured for this session' };
    }

    // Validate payload completeness (Requirement 5.2)
    const validationError = this.validatePayload(payload);
    if (validationError) {
      return { success: false, error: validationError };
    }

    // Send with retry logic
    return this.sendWithRetry(session.webhookUrl, session.webhookSecret, payload);
  }

  /**
   * Verify a webhook signature.
   * Implements Requirement 5.3 - authenticate webhook requests using shared secret.
   * 
   * @param payload - The raw payload string
   * @param signature - The signature to verify
   * @param secret - The shared secret
   * @returns true if signature is valid, false otherwise
   */
  verifySignature(payload: string, signature: string, secret: string): boolean {
    if (!payload || !signature || !secret) {
      return false;
    }

    const expectedSignature = this.generateSignature(payload, secret);
    
    // Use timing-safe comparison to prevent timing attacks
    try {
      return crypto.timingSafeEqual(
        Buffer.from(signature),
        Buffer.from(expectedSignature)
      );
    } catch {
      // Buffers have different lengths
      return false;
    }
  }

  /**
   * Generate a signature for a payload.
   * Uses HMAC-SHA256 for secure signing.
   * 
   * @param payload - The payload to sign
   * @param secret - The shared secret
   * @returns The hex-encoded signature
   */
  generateSignature(payload: string, secret: string): string {
    return crypto
      .createHmac('sha256', secret)
      .update(payload)
      .digest('hex');
  }

  /**
   * Build a complete webhook payload from source and message data.
   * Ensures all required fields are present (Requirement 5.2).
   * 
   * @param sourceId - The source ID
   * @param message - The user's message
   * @param conversationHistory - Previous messages in the conversation
   * @param userId - The user's ID
   * @returns A complete WebhookPayload
   */
  async buildPayload(
    sourceId: string,
    message: string,
    conversationHistory: SourceMessage[],
    userId: string,
    imageAttachments?: ImageAttachmentPayload[]
  ): Promise<WebhookPayload> {
    // Get source details
    const sourceResult = await pool.query(
      `SELECT title, content, metadata FROM sources WHERE id = $1`,
      [sourceId]
    );

    if (sourceResult.rows.length === 0) {
      throw new Error('Source not found');
    }

    const source = sourceResult.rows[0];
    const metadata = typeof source.metadata === 'string' 
      ? JSON.parse(source.metadata) 
      : (source.metadata || {});

    return {
      type: 'followup_message',
      sourceId,
      sourceTitle: source.title || 'Untitled',
      sourceCode: source.content || '',
      sourceLanguage: metadata.language || 'unknown',
      message,
      conversationHistory,
      ...(imageAttachments && imageAttachments.length > 0 && { imageAttachments }),
      userId,
      timestamp: new Date().toISOString(),
    };
  }

  /**
   * Get webhook configuration for a session.
   * 
   * @param sessionId - The agent session ID
   * @returns The webhook config or null if not configured
   */
  async getWebhookConfig(sessionId: string): Promise<WebhookConfig | null> {
    const session = await agentSessionService.getSession(sessionId);
    
    if (!session || !session.webhookUrl || !session.webhookSecret) {
      return null;
    }

    return {
      url: session.webhookUrl,
      secret: session.webhookSecret,
    };
  }

  /**
   * Check if a webhook is configured and reachable.
   * 
   * @param sessionId - The agent session ID
   * @returns true if webhook is configured, false otherwise
   */
  async isWebhookConfigured(sessionId: string): Promise<boolean> {
    const config = await this.getWebhookConfig(sessionId);
    return config !== null;
  }

  // ==================== PRIVATE METHODS ====================

  /**
   * Send a webhook request with exponential backoff retry logic.
   * Implements Requirement 3.4 - retry with exponential backoff.
   * 
   * @param url - The webhook URL
   * @param secret - The shared secret
   * @param payload - The payload to send
   * @returns The webhook response
   */
  private async sendWithRetry(
    url: string,
    secret: string,
    payload: WebhookPayload
  ): Promise<WebhookResponse> {
    const payloadString = JSON.stringify(payload);
    const signature = this.generateSignature(payloadString, secret);

    let lastError: Error | null = null;
    
    for (let attempt = 0; attempt <= this.retryConfig.maxRetries; attempt++) {
      try {
        const response = await this.sendRequest(url, payloadString, signature);
        
        // Success
        if (response.success) {
          return response;
        }

        // 4xx errors - don't retry (client error)
        if (response.statusCode && response.statusCode >= 400 && response.statusCode < 500) {
          return {
            success: false,
            error: `Client error: ${response.statusCode} - ${response.error}`,
          };
        }

        // 5xx errors - retry
        lastError = new Error(response.error || 'Server error');
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
      }

      // Calculate delay with exponential backoff
      if (attempt < this.retryConfig.maxRetries) {
        const delay = Math.min(
          this.retryConfig.baseDelayMs * Math.pow(2, attempt),
          this.retryConfig.maxDelayMs
        );
        await this.sleep(delay);
      }
    }

    return {
      success: false,
      error: `Failed after ${this.retryConfig.maxRetries + 1} attempts: ${lastError?.message}`,
    };
  }

  /**
   * Send a single HTTP request to the webhook endpoint.
   * 
   * @param url - The webhook URL
   * @param payload - The JSON payload string
   * @param signature - The HMAC signature
   * @returns The response with status code
   */
  private async sendRequest(
    url: string,
    payload: string,
    signature: string
  ): Promise<WebhookResponse & { statusCode?: number }> {
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Webhook-Signature': signature,
          'X-Webhook-Timestamp': new Date().toISOString(),
        },
        body: payload,
        signal: AbortSignal.timeout(30000), // 30 second timeout
      });

      const statusCode = response.status;

      if (!response.ok) {
        const errorText = await response.text().catch(() => 'Unknown error');
        return {
          success: false,
          error: errorText,
          statusCode,
        };
      }

      // Parse response
      const data = await response.json().catch(() => ({})) as {
        response?: string;
        codeUpdate?: { code: string; description: string };
      };
      
      return {
        success: true,
        response: data.response,
        codeUpdate: data.codeUpdate,
        statusCode,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Request failed';
      return {
        success: false,
        error: message,
      };
    }
  }

  /**
   * Validate that a webhook payload contains all required fields.
   * Implements Requirement 5.2 - payload completeness.
   * 
   * @param payload - The payload to validate
   * @returns Error message if invalid, null if valid
   */
  private validatePayload(payload: WebhookPayload): string | null {
    if (!payload.sourceId) {
      return 'Missing required field: sourceId';
    }
    if (!payload.sourceTitle) {
      return 'Missing required field: sourceTitle';
    }
    if (payload.sourceCode === undefined || payload.sourceCode === null) {
      return 'Missing required field: sourceCode';
    }
    if (!payload.sourceLanguage) {
      return 'Missing required field: sourceLanguage';
    }
    if (!payload.message) {
      return 'Missing required field: message';
    }
    if (!Array.isArray(payload.conversationHistory)) {
      return 'Missing required field: conversationHistory';
    }
    if (!payload.userId) {
      return 'Missing required field: userId';
    }
    if (!payload.timestamp) {
      return 'Missing required field: timestamp';
    }
    if (payload.type !== 'followup_message') {
      return 'Invalid payload type';
    }
    return null;
  }

  /**
   * Validate that a URL is a valid HTTPS webhook URL.
   * 
   * @param url - The URL to validate
   * @returns true if valid, false otherwise
   */
  private isValidWebhookUrl(url: string): boolean {
    try {
      const parsed = new URL(url);
      return parsed.protocol === 'https:';
    } catch {
      return false;
    }
  }

  /**
   * Sleep for a specified duration.
   * 
   * @param ms - Milliseconds to sleep
   */
  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Export singleton instance
export const webhookService = new WebhookService();

// Export class for testing with custom config
export { WebhookService };

export default webhookService;
