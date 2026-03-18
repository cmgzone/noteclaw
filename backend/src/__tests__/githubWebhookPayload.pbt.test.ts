/**
 * Property-Based Tests for GitHub Webhook Payload Completeness
 * 
 * Feature: github-mcp-integration
 * Property 7: GitHub Webhook Payload Completeness
 * 
 * For any follow-up message about a GitHub source, the webhook payload SHALL include:
 * sourceId, current file content, owner, repo, path, branch, and language.
 * 
 * **Validates: Requirements 4.2**
 */

import * as fc from 'fast-check';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { GitHubWebhookBuilder, GitHubWebhookPayload } from '../services/githubWebhookBuilder.js';
import { SourceMessage } from '../services/sourceConversationService.js';

// ==================== TEST SETUP ====================

// Track created test data for cleanup
const createdUserIds: string[] = [];
const createdNotebookIds: string[] = [];
const createdSourceIds: string[] = [];

// Helper to create a test user
async function createTestUser(): Promise<string> {
  const userId = uuidv4();
  const email = `test-gh-webhook-${userId}@example.com`;
  
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


// Helper to create a GitHub source
async function createGitHubSource(
  notebookId: string,
  userId: string,
  params: {
    owner: string;
    repo: string;
    path: string;
    branch: string;
    language: string;
    content: string;
  }
): Promise<string> {
  const sourceId = uuidv4();
  const { owner, repo, path, branch, language, content } = params;
  
  const metadata = {
    type: 'github',
    owner,
    repo,
    path,
    branch,
    commitSha: `sha-${uuidv4().substring(0, 8)}`,
    language,
    size: content.length,
    lastFetchedAt: new Date().toISOString(),
    githubUrl: `https://github.com/${owner}/${repo}/blob/${branch}/${path}`,
  };
  
  await pool.query(
    `INSERT INTO sources (id, notebook_id, user_id, type, title, content, metadata, created_at, updated_at)
     VALUES ($1, $2, $3, 'github', $4, $5, $6, NOW(), NOW())`,
    [sourceId, notebookId, userId, `${repo}/${path}`, content, JSON.stringify(metadata)]
  );
  
  createdSourceIds.push(sourceId);
  return sourceId;
}

// Cleanup function
async function cleanup() {
  if (createdSourceIds.length > 0) {
    await pool.query(`DELETE FROM sources WHERE id = ANY($1)`, [createdSourceIds]);
  }
  if (createdNotebookIds.length > 0) {
    await pool.query(`DELETE FROM notebooks WHERE id = ANY($1)`, [createdNotebookIds]);
  }
  if (createdUserIds.length > 0) {
    await pool.query(`DELETE FROM users WHERE id = ANY($1)`, [createdUserIds]);
  }
  createdSourceIds.length = 0;
  createdNotebookIds.length = 0;
  createdUserIds.length = 0;
}


// ==================== ARBITRARIES ====================

// Generate valid GitHub owner names (alphanumeric with hyphens)
const ownerArb = fc.stringOf(
  fc.constantFrom(...'abcdefghijklmnopqrstuvwxyz0123456789-'.split('')),
  { minLength: 1, maxLength: 20 }
).filter(s => !s.startsWith('-') && !s.endsWith('-'));

// Generate valid repository names
const repoArb = fc.stringOf(
  fc.constantFrom(...'abcdefghijklmnopqrstuvwxyz0123456789-_.'.split('')),
  { minLength: 1, maxLength: 30 }
).filter(s => !s.startsWith('-') && !s.startsWith('.'));

// Generate valid file paths
const filePathArb = fc.array(
  fc.stringOf(fc.constantFrom(...'abcdefghijklmnopqrstuvwxyz0123456789-_'.split('')), { minLength: 1, maxLength: 15 }),
  { minLength: 1, maxLength: 4 }
).chain(parts => {
  const extensions = ['ts', 'js', 'py', 'dart', 'java', 'go', 'rs', 'md'];
  return fc.constantFrom(...extensions).map(ext => parts.join('/') + '.' + ext);
});

// Generate valid branch names
const branchArb = fc.constantFrom('main', 'master', 'develop', 'feature/test', 'release/v1');

// Generate programming languages
const languageArb = fc.constantFrom('typescript', 'javascript', 'python', 'dart', 'java', 'go', 'rust', 'markdown');

// Generate code content
const codeContentArb = fc.string({ minLength: 10, maxLength: 500 });

// Generate user messages
const messageArb = fc.string({ minLength: 1, maxLength: 200 });

// Generate source messages for conversation history
const sourceMessageArb = fc.record({
  id: fc.uuid(),
  conversationId: fc.uuid(),
  sourceId: fc.uuid(),
  role: fc.constantFrom('user', 'agent') as fc.Arbitrary<'user' | 'agent'>,
  content: fc.string({ minLength: 1, maxLength: 200 }),
  metadata: fc.constant({}),
  isRead: fc.boolean(),
  createdAt: fc.date(),
});
const imageAttachmentArb = fc.record({
  id: fc.uuid(),
  name: fc.string({ minLength: 1, maxLength: 120 }),
  mimeType: fc.constantFrom('image/png', 'image/jpeg', 'image/webp', 'image/gif'),
  base64Data: fc.base64String({ minLength: 8, maxLength: 1024 }),
  sizeBytes: fc.integer({ min: 1, max: 1024 * 1024 }),
});


// ==================== PROPERTY TESTS ====================

describe('GitHub Webhook Payload - Property-Based Tests', () => {
  const webhookBuilder = new GitHubWebhookBuilder();

  afterEach(async () => {
    await cleanup();
  });

  afterAll(async () => {
    await cleanup();
    await pool.end();
  });

  /**
   * Property 7: GitHub Webhook Payload Completeness
   * 
   * For any follow-up message about a GitHub source, the webhook payload SHALL include:
   * sourceId, current file content, owner, repo, path, branch, and language.
   * 
   * **Validates: Requirements 4.2**
   */
  describe('Property 7: GitHub Webhook Payload Completeness', () => {
    it('payload contains all required GitHub context fields', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          async (owner, repo, path, branch, language, content, message) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            // Build payload
            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: [],
              userId,
            });

            // Verify all required fields are present
            expect(payload.sourceId).toBe(sourceId);
            expect(payload.message).toBe(message);
            expect(payload.userId).toBe(userId);
            expect(payload.type).toBe('followup_message');
            expect(payload.timestamp).toBeDefined();

            // Verify GitHub context fields (Requirement 4.2)
            expect(payload.githubContext).toBeDefined();
            expect(payload.githubContext.owner).toBe(owner);
            expect(payload.githubContext.repo).toBe(repo);
            expect(payload.githubContext.path).toBe(path);
            expect(payload.githubContext.branch).toBe(branch);
            expect(payload.githubContext.language).toBe(language);
            expect(payload.githubContext.currentContent).toBe(content);
            expect(payload.githubContext.githubUrl).toContain(owner);
            expect(payload.githubContext.githubUrl).toContain(repo);
          }
        ),
        { numRuns: 10, timeout: 60000 }
      );
    }, 120000);


    it('payload validation correctly identifies complete payloads', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          async (owner, repo, path, branch, language, content, message) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            // Build payload
            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: [],
              userId,
            });

            // Validate payload - should pass for complete payloads
            const validationError = webhookBuilder.validatePayload(payload);
            expect(validationError).toBeNull();
          }
        ),
        { numRuns: 10, timeout: 60000 }
      );
    }, 120000);

    it('conversation history is preserved in payload', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          fc.array(sourceMessageArb, { minLength: 1, maxLength: 5 }),
          async (owner, repo, path, branch, language, content, message, history) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            // Build payload with conversation history
            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: history,
              userId,
            });

            // Verify conversation history is preserved
            expect(payload.conversationHistory.length).toBe(history.length);
            for (let i = 0; i < history.length; i++) {
              expect(payload.conversationHistory[i].id).toBe(history[i].id);
              expect(payload.conversationHistory[i].content).toBe(history[i].content);
              expect(payload.conversationHistory[i].role).toBe(history[i].role);
            }
          }
        ),
        { numRuns: 5, timeout: 60000 }
      );
    }, 120000);

    it('image attachments are preserved in github payload', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          fc.array(imageAttachmentArb, { minLength: 1, maxLength: 4 }),
          async (owner, repo, path, branch, language, content, message, attachments) => {
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: [],
              imageAttachments: attachments,
              userId,
            });

            expect(payload.imageAttachments).toEqual(attachments);
          }
        ),
        { numRuns: 5, timeout: 60000 }
      );
    }, 120000);


    it('includeFileContent updates payload with fresh content', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          async (owner, repo, path, branch, language, content, message) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            // Build initial payload
            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: [],
              userId,
            });

            // Include file content (should return same content since no update)
            const updatedPayload = await webhookBuilder.includeFileContent(payload);

            // Verify content is present
            expect(updatedPayload.sourceCode).toBe(content);
            expect(updatedPayload.githubContext.currentContent).toBe(content);
          }
        ),
        { numRuns: 5, timeout: 60000 }
      );
    }, 120000);

    it('payload JSON serialization preserves all GitHub context fields', async () => {
      await fc.assert(
        fc.asyncProperty(
          ownerArb,
          repoArb,
          filePathArb,
          branchArb,
          languageArb,
          codeContentArb,
          messageArb,
          async (owner, repo, path, branch, language, content, message) => {
            // Create test data
            const userId = await createTestUser();
            const notebookId = await createTestNotebook(userId);
            const sourceId = await createGitHubSource(notebookId, userId, {
              owner, repo, path, branch, language, content,
            });

            // Build payload
            const payload = await webhookBuilder.buildPayload({
              sourceId,
              message,
              conversationHistory: [],
              userId,
            });

            // Serialize and deserialize
            const serialized = JSON.stringify(payload);
            const deserialized = JSON.parse(serialized) as GitHubWebhookPayload;

            // Verify all fields are preserved
            expect(deserialized.sourceId).toBe(payload.sourceId);
            expect(deserialized.message).toBe(payload.message);
            expect(deserialized.githubContext.owner).toBe(payload.githubContext.owner);
            expect(deserialized.githubContext.repo).toBe(payload.githubContext.repo);
            expect(deserialized.githubContext.path).toBe(payload.githubContext.path);
            expect(deserialized.githubContext.branch).toBe(payload.githubContext.branch);
            expect(deserialized.githubContext.language).toBe(payload.githubContext.language);
            expect(deserialized.githubContext.currentContent).toBe(payload.githubContext.currentContent);
          }
        ),
        { numRuns: 5, timeout: 60000 }
      );
    }, 120000);
  });


  /**
   * Additional validation tests for incomplete payloads
   */
  describe('Payload Validation', () => {
    it('rejects payloads missing required base fields', () => {
      const incompletePayloads: Partial<GitHubWebhookPayload>[] = [
        { type: 'followup_message' }, // missing sourceId
        { type: 'followup_message', sourceId: 'test' }, // missing sourceTitle
        { type: 'followup_message', sourceId: 'test', sourceTitle: 'Test' }, // missing sourceCode
      ];

      for (const payload of incompletePayloads) {
        const error = webhookBuilder.validatePayload(payload as GitHubWebhookPayload);
        expect(error).not.toBeNull();
      }
    });

    it('rejects payloads missing GitHub context', () => {
      const payloadWithoutGitHubContext: GitHubWebhookPayload = {
        type: 'followup_message',
        sourceId: 'test-id',
        sourceTitle: 'Test Source',
        sourceCode: 'const x = 1;',
        sourceLanguage: 'typescript',
        message: 'Test message',
        conversationHistory: [],
        userId: 'user-id',
        timestamp: new Date().toISOString(),
        githubContext: undefined as any,
      };

      const error = webhookBuilder.validatePayload(payloadWithoutGitHubContext);
      expect(error).toBe('Missing required field: githubContext');
    });

    it('rejects payloads with incomplete GitHub context', () => {
      const basePayload = {
        type: 'followup_message' as const,
        sourceId: 'test-id',
        sourceTitle: 'Test Source',
        sourceCode: 'const x = 1;',
        sourceLanguage: 'typescript',
        message: 'Test message',
        conversationHistory: [],
        userId: 'user-id',
        timestamp: new Date().toISOString(),
      };

      // Missing owner
      const missingOwner: GitHubWebhookPayload = {
        ...basePayload,
        githubContext: {
          owner: '',
          repo: 'test-repo',
          path: 'src/index.ts',
          branch: 'main',
          currentContent: 'const x = 1;',
          language: 'typescript',
          commitSha: 'abc123',
          githubUrl: 'https://github.com/test/test-repo',
        },
      };
      expect(webhookBuilder.validatePayload(missingOwner)).toBe('Missing required field: githubContext.owner');

      // Missing repo
      const missingRepo: GitHubWebhookPayload = {
        ...basePayload,
        githubContext: {
          owner: 'test-owner',
          repo: '',
          path: 'src/index.ts',
          branch: 'main',
          currentContent: 'const x = 1;',
          language: 'typescript',
          commitSha: 'abc123',
          githubUrl: 'https://github.com/test/test-repo',
        },
      };
      expect(webhookBuilder.validatePayload(missingRepo)).toBe('Missing required field: githubContext.repo');
    });
  });

  /**
   * Test isGitHubSource detection
   */
  describe('GitHub Source Detection', () => {
    it('correctly identifies GitHub sources', async () => {
      const userId = await createTestUser();
      const notebookId = await createTestNotebook(userId);
      const sourceId = await createGitHubSource(notebookId, userId, {
        owner: 'test-owner',
        repo: 'test-repo',
        path: 'src/index.ts',
        branch: 'main',
        language: 'typescript',
        content: 'const x = 1;',
      });

      const isGitHub = await webhookBuilder.isGitHubSource(sourceId);
      expect(isGitHub).toBe(true);
    });

    it('returns false for non-existent sources', async () => {
      const isGitHub = await webhookBuilder.isGitHubSource(uuidv4());
      expect(isGitHub).toBe(false);
    });
  });
});
