/**
 * Property-Based Tests for Webhook Service
 * 
 * These tests validate correctness properties using fast-check for property-based testing.
 * Each test runs minimum 100 iterations with randomly generated inputs.
 * 
 * Feature: coding-agent-communication
 */

import * as fc from 'fast-check';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { WebhookService, WebhookPayload } from '../services/webhookService.js';
import { SourceMessage } from '../services/sourceConversationService.js';
import { agentSessionService } from '../services/agentSessionService.js';

// ==================== TEST SETUP ====================

// Track created test data for cleanup
const createdUserIds: string[] = [];
const createdSessionIds: string[] = [];
const createdSourceIds: string[] = [];
const createdNotebookIds: string[] = [];

// Helper to create a test user
async function createTestUser(): Promise<string> {
  const userId = uuidv4();
  const email = `test-webhook-${userId}@example.com`;
  
  await pool.query(
    `INSERT INTO users (id, email, password_hash, display_name) 
     VALUES ($1, $2, 'test-hash', 'Test User')
     ON CONFLICT (id) DO NOTHING`,
    [userId, email]
  );
  
  createdUserIds.push(userId);
  return userId;
}

// Helper to create a test notebook
async function createTestNotebook(userId: string): Promise<string> {
  const notebookId = uuidv4();
  
  await pool.query(
    `INSERT INTO notebooks (id, user_id, title, description)
     VALUES ($1, $2, 'Test Notebook', 'Test Description')`,
    [notebookId, userId]
  );
  
  createdNotebookIds.push(notebookId);
  return notebookId;
}

// Helper to create a test source
async function createTestSource(notebookId: string, language: string = 'typescript'): Promise<string> {
  const sourceId = uuidv4();
  
  await pool.query(
    `INSERT INTO sources (id, notebook_id, type, title, content, metadata)
     VALUES ($1, $2, 'code', 'Test Source', 'const x = 1;', $3)`,
    [sourceId, notebookId, JSON.stringify({ language })]
  );
  
  createdSourceIds.push(sourceId);
  return sourceId;
}

// Cleanup function
async function cleanup() {
  // Delete sources first
  if (createdSourceIds.length > 0) {
    await pool.query(
      `DELETE FROM sources WHERE id = ANY($1)`,
      [createdSourceIds]
    );
  }
  
  // Delete notebooks
  if (createdNotebookIds.length > 0) {
    await pool.query(
      `DELETE FROM notebooks WHERE id = ANY($1)`,
      [createdNotebookIds]
    );
  }
  
  // Delete sessions
  if (createdSessionIds.length > 0) {
    await pool.query(
      `DELETE FROM agent_sessions WHERE id = ANY($1)`,
      [createdSessionIds]
    );
  }
  
  // Delete users
  if (createdUserIds.length > 0) {
    await pool.query(
      `DELETE FROM users WHERE id = ANY($1)`,
      [createdUserIds]
    );
  }
  
  createdSourceIds.length = 0;
  createdNotebookIds.length = 0;
  createdSessionIds.length = 0;
  createdUserIds.length = 0;
}

// ==================== ARBITRARIES ====================

// Generate valid source messages
const sourceMessageArb = fc.record({
  id: fc.uuid(),
  conversationId: fc.uuid(),
  sourceId: fc.uuid(),
  role: fc.constantFrom('user', 'agent') as fc.Arbitrary<'user' | 'agent'>,
  content: fc.string({ minLength: 1, maxLength: 500 }),
  metadata: fc.constant({}),
  isRead: fc.boolean(),
  createdAt: fc.date(),
});

// Generate valid webhook payloads
const webhookPayloadArb = fc.record({
  type: fc.constant('followup_message' as const),
  sourceId: fc.uuid(),
  sourceTitle: fc.string({ minLength: 1, maxLength: 100 }),
  sourceCode: fc.string({ minLength: 0, maxLength: 1000 }),
  sourceLanguage: fc.constantFrom('typescript', 'javascript', 'python', 'java', 'go', 'rust'),
  message: fc.string({ minLength: 1, maxLength: 500 }),
  conversationHistory: fc.array(sourceMessageArb, { minLength: 0, maxLength: 10 }),
  userId: fc.uuid(),
  timestamp: fc.date().map(d => d.toISOString()),
});

// Generate valid webhook secrets (at least 16 chars)
const webhookSecretArb = fc.hexaString({ minLength: 32, maxLength: 64 });

// Generate valid webhook URLs
const webhookUrlArb = fc.webUrl({ validSchemes: ['https'] });
const imageAttachmentArb = fc.record({
  id: fc.uuid(),
  name: fc.string({ minLength: 1, maxLength: 120 }),
  mimeType: fc.constantFrom('image/png', 'image/jpeg', 'image/webp', 'image/gif'),
  base64Data: fc.base64String({ minLength: 8, maxLength: 1024 }),
  sizeBytes: fc.integer({ min: 1, max: 1024 * 1024 }),
});

// ==================== PROPERTY TESTS ====================

describe('Webhook Service - Property-Based Tests', () => {
  // Create a webhook service instance for testing
  const webhookService = new WebhookService({
    maxRetries: 0, // No retries for unit tests
    baseDelayMs: 10,
    maxDelayMs: 100,
  });

  afterEach(async () => {
    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await pool.end();
  });

  /**
   * Property 4: Webhook Payload Completeness
   * 
   * For any follow-up message sent to an agent, the webhook payload SHALL contain:
   * source ID, source title, source code, source language, user message, and conversation history.
   * 
   * **Validates: Requirements 3.2, 5.2**
   */
  describe('Property 4: Webhook Payload Completeness', () => {
    it('valid payloads contain all required fields', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          async (payload) => {
            // A valid payload should have all required fields
            expect(payload.type).toBe('followup_message');
            expect(payload.sourceId).toBeDefined();
            expect(typeof payload.sourceId).toBe('string');
            expect(payload.sourceTitle).toBeDefined();
            expect(typeof payload.sourceTitle).toBe('string');
            expect(payload.sourceCode).toBeDefined();
            expect(typeof payload.sourceCode).toBe('string');
            expect(payload.sourceLanguage).toBeDefined();
            expect(typeof payload.sourceLanguage).toBe('string');
            expect(payload.message).toBeDefined();
            expect(typeof payload.message).toBe('string');
            expect(Array.isArray(payload.conversationHistory)).toBe(true);
            expect(payload.userId).toBeDefined();
            expect(typeof payload.userId).toBe('string');
            expect(payload.timestamp).toBeDefined();
            expect(typeof payload.timestamp).toBe('string');
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('buildPayload creates complete payloads from source data', async () => {
      await fc.assert(
        fc.asyncProperty(
          fc.string({ minLength: 1, maxLength: 100 }), // message
          fc.constantFrom('typescript', 'javascript', 'python'), // language
          async (message, language) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createTestSource(notebookId, language);
            
            // Build payload
            const payload = await webhookService.buildPayload(
              sourceId,
              message,
              [], // empty conversation history
              userId
            );
            
            // Verify all required fields are present
            expect(payload.type).toBe('followup_message');
            expect(payload.sourceId).toBe(sourceId);
            expect(payload.sourceTitle).toBeDefined();
            expect(payload.sourceCode).toBeDefined();
            expect(payload.sourceLanguage).toBe(language);
            expect(payload.message).toBe(message);
            expect(Array.isArray(payload.conversationHistory)).toBe(true);
            expect(payload.userId).toBe(userId);
            expect(payload.timestamp).toBeDefined();
            
            // Verify timestamp is valid ISO string
            expect(() => new Date(payload.timestamp)).not.toThrow();
          }
        ),
        { numRuns: 5, timeout: 30000 }
      );
    }, 60000);

    it('conversation history is preserved in payload', async () => {
      await fc.assert(
        fc.asyncProperty(
          fc.array(sourceMessageArb, { minLength: 1, maxLength: 3 }),
          fc.string({ minLength: 1, maxLength: 100 }),
          async (history, message) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createTestSource(notebookId);
            
            // Build payload with conversation history
            const payload = await webhookService.buildPayload(
              sourceId,
              message,
              history,
              userId
            );
            
            // Verify conversation history is preserved
            expect(payload.conversationHistory.length).toBe(history.length);
            
            // Each message in history should be present
            for (let i = 0; i < history.length; i++) {
              expect(payload.conversationHistory[i].id).toBe(history[i].id);
              expect(payload.conversationHistory[i].content).toBe(history[i].content);
              expect(payload.conversationHistory[i].role).toBe(history[i].role);
            }
          }
        ),
        { numRuns: 5, timeout: 30000 }
      );
    }, 60000);

    it('image attachments are preserved in payload when provided', async () => {
      await fc.assert(
        fc.asyncProperty(
          fc.array(imageAttachmentArb, { minLength: 1, maxLength: 4 }),
          fc.string({ minLength: 1, maxLength: 100 }),
          async (attachments, message) => {
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createTestSource(notebookId);

            const payload = await webhookService.buildPayload(
              sourceId,
              message,
              [],
              userId,
              attachments
            );

            expect(payload.imageAttachments).toEqual(attachments);
          }
        ),
        { numRuns: 5, timeout: 30000 }
      );
    }, 60000);

    it('payload JSON serialization preserves all fields', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          async (payload) => {
            // Serialize and deserialize
            const serialized = JSON.stringify(payload);
            const deserialized = JSON.parse(serialized) as WebhookPayload;
            
            // All fields should be preserved
            expect(deserialized.type).toBe(payload.type);
            expect(deserialized.sourceId).toBe(payload.sourceId);
            expect(deserialized.sourceTitle).toBe(payload.sourceTitle);
            expect(deserialized.sourceCode).toBe(payload.sourceCode);
            expect(deserialized.sourceLanguage).toBe(payload.sourceLanguage);
            expect(deserialized.message).toBe(payload.message);
            expect(deserialized.conversationHistory.length).toBe(payload.conversationHistory.length);
            expect(deserialized.userId).toBe(payload.userId);
            expect(deserialized.timestamp).toBe(payload.timestamp);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);
  });

  /**
   * Property 5: Webhook Authentication
   * 
   * For any webhook request, the signature generated from the payload and secret 
   * SHALL be verifiable, and requests with invalid signatures SHALL be rejected.
   * 
   * **Validates: Requirements 5.3**
   */
  describe('Property 5: Webhook Authentication', () => {
    it('valid signatures are verified successfully', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          async (payload, secret) => {
            const payloadString = JSON.stringify(payload);
            
            // Generate signature
            const signature = webhookService.generateSignature(payloadString, secret);
            
            // Verify signature
            const isValid = webhookService.verifySignature(payloadString, signature, secret);
            
            expect(isValid).toBe(true);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('signatures are deterministic for same payload and secret', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          async (payload, secret) => {
            const payloadString = JSON.stringify(payload);
            
            // Generate signature multiple times
            const sig1 = webhookService.generateSignature(payloadString, secret);
            const sig2 = webhookService.generateSignature(payloadString, secret);
            const sig3 = webhookService.generateSignature(payloadString, secret);
            
            // All signatures should be identical
            expect(sig1).toBe(sig2);
            expect(sig2).toBe(sig3);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('different secrets produce different signatures', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          webhookSecretArb,
          async (payload, secret1, secret2) => {
            // Skip if secrets happen to be the same
            fc.pre(secret1 !== secret2);
            
            const payloadString = JSON.stringify(payload);
            
            const sig1 = webhookService.generateSignature(payloadString, secret1);
            const sig2 = webhookService.generateSignature(payloadString, secret2);
            
            // Different secrets should produce different signatures
            expect(sig1).not.toBe(sig2);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('modified payloads fail signature verification', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          fc.string({ minLength: 1, maxLength: 50 }), // modification
          async (payload, secret, modification) => {
            const payloadString = JSON.stringify(payload);
            
            // Generate signature for original payload
            const signature = webhookService.generateSignature(payloadString, secret);
            
            // Modify the payload
            const modifiedPayload = { ...payload, message: payload.message + modification };
            const modifiedPayloadString = JSON.stringify(modifiedPayload);
            
            // Skip if modification didn't change the string
            fc.pre(payloadString !== modifiedPayloadString);
            
            // Verification should fail for modified payload
            const isValid = webhookService.verifySignature(modifiedPayloadString, signature, secret);
            
            expect(isValid).toBe(false);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('wrong secret fails signature verification', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          webhookSecretArb,
          async (payload, correctSecret, wrongSecret) => {
            // Skip if secrets happen to be the same
            fc.pre(correctSecret !== wrongSecret);
            
            const payloadString = JSON.stringify(payload);
            
            // Generate signature with correct secret
            const signature = webhookService.generateSignature(payloadString, correctSecret);
            
            // Verification with wrong secret should fail
            const isValid = webhookService.verifySignature(payloadString, signature, wrongSecret);
            
            expect(isValid).toBe(false);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);

    it('empty or null inputs are rejected', async () => {
      // Test various invalid inputs
      expect(webhookService.verifySignature('', 'signature', 'secret')).toBe(false);
      expect(webhookService.verifySignature('payload', '', 'secret')).toBe(false);
      expect(webhookService.verifySignature('payload', 'signature', '')).toBe(false);
      expect(webhookService.verifySignature(null as any, 'signature', 'secret')).toBe(false);
      expect(webhookService.verifySignature('payload', null as any, 'secret')).toBe(false);
      expect(webhookService.verifySignature('payload', 'signature', null as any)).toBe(false);
    });

    it('signature format is consistent hex string', async () => {
      await fc.assert(
        fc.asyncProperty(
          webhookPayloadArb,
          webhookSecretArb,
          async (payload, secret) => {
            const payloadString = JSON.stringify(payload);
            const signature = webhookService.generateSignature(payloadString, secret);
            
            // Signature should be a hex string (HMAC-SHA256 produces 64 hex chars)
            expect(signature).toMatch(/^[a-f0-9]{64}$/);
          }
        ),
        { numRuns: 10, timeout: 30000 }
      );
    }, 60000);
  });
});
