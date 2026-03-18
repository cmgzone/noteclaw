/**
 * GitHub Webhook Builder Service
 * Extends webhook payloads with GitHub-specific context for follow-up messages.
 * 
 * Requirements: 4.2
 */

import pool from '../config/database.js';
import { ImageAttachmentPayload, WebhookPayload } from './webhookService.js';
import { SourceMessage } from './sourceConversationService.js';
import { GitHubSourceMetadata } from './githubSourceService.js';

// ==================== INTERFACES ====================

/**
 * Extended webhook payload with GitHub context
 * Implements Requirement 4.2 - include current file content in webhook payload
 */
export interface GitHubWebhookPayload extends WebhookPayload {
  githubContext: {
    owner: string;
    repo: string;
    path: string;
    branch: string;
    currentContent: string;
    language: string;
    commitSha: string;
    githubUrl: string;
    repoStructure?: string[];
  };
}

export interface BuildGitHubPayloadParams {
  sourceId: string;
  message: string;
  conversationHistory: SourceMessage[];
  imageAttachments?: ImageAttachmentPayload[];
  userId: string;
  includeRepoStructure?: boolean;
}

// ==================== SERVICE CLASS ====================

class GitHubWebhookBuilder {
  /**
   * Check if a source is a GitHub source
   * 
   * @param sourceId - The source ID to check
   * @returns true if the source is a GitHub source
   */
  async isGitHubSource(sourceId: string): Promise<boolean> {
    const result = await pool.query(
      `SELECT type, metadata FROM sources WHERE id = $1`,
      [sourceId]
    );

    if (result.rows.length === 0) {
      return false;
    }

    const source = result.rows[0];
    const metadata = typeof source.metadata === 'string'
      ? JSON.parse(source.metadata)
      : (source.metadata || {});

    return source.type === 'github' || metadata.type === 'github';
  }

  /**
   * Build a webhook payload with GitHub context
   * Implements Requirement 4.2 - include current file content, owner, repo, path, branch
   * 
   * @param params - Parameters for building the payload
   * @returns A GitHubWebhookPayload with full GitHub context
   */
  async buildPayload(params: BuildGitHubPayloadParams): Promise<GitHubWebhookPayload> {
    const {
      sourceId,
      message,
      conversationHistory,
      imageAttachments,
      userId,
      includeRepoStructure = false,
    } = params;

    // Get source details
    const sourceResult = await pool.query(
      `SELECT title, content, metadata, type FROM sources WHERE id = $1`,
      [sourceId]
    );

    if (sourceResult.rows.length === 0) {
      throw new Error('Source not found');
    }

    const source = sourceResult.rows[0];
    const metadata = typeof source.metadata === 'string'
      ? JSON.parse(source.metadata)
      : (source.metadata || {}) as GitHubSourceMetadata;

    // Verify this is a GitHub source
    if (source.type !== 'github' && metadata.type !== 'github') {
      throw new Error('Source is not a GitHub source');
    }

    // Build GitHub context
    const githubContext: GitHubWebhookPayload['githubContext'] = {
      owner: metadata.owner,
      repo: metadata.repo,
      path: metadata.path,
      branch: metadata.branch,
      currentContent: source.content || '',
      language: metadata.language || 'unknown',
      commitSha: metadata.commitSha,
      githubUrl: metadata.githubUrl || `https://github.com/${metadata.owner}/${metadata.repo}/blob/${metadata.branch}/${metadata.path}`,
    };

    // Optionally include repository structure
    if (includeRepoStructure) {
      const repoStructure = await this.getRepoStructure(userId, metadata.owner, metadata.repo);
      if (repoStructure.length > 0) {
        githubContext.repoStructure = repoStructure;
      }
    }

    // Build the complete payload
    const payload: GitHubWebhookPayload = {
      type: 'followup_message',
      sourceId,
      sourceTitle: source.title || `${metadata.repo}/${metadata.path}`,
      sourceCode: source.content || '',
      sourceLanguage: metadata.language || 'unknown',
      message,
      conversationHistory,
      ...(imageAttachments && imageAttachments.length > 0 && { imageAttachments }),
      userId,
      timestamp: new Date().toISOString(),
      githubContext,
    };

    return payload;
  }

  /**
   * Include fresh file content in an existing payload
   * Fetches the latest content from the database
   * 
   * @param payload - The existing payload to enhance
   * @returns The payload with updated file content
   */
  async includeFileContent(payload: GitHubWebhookPayload): Promise<GitHubWebhookPayload> {
    // Get the latest source content
    const sourceResult = await pool.query(
      `SELECT content, metadata FROM sources WHERE id = $1`,
      [payload.sourceId]
    );

    if (sourceResult.rows.length === 0) {
      return payload;
    }

    const source = sourceResult.rows[0];
    const content = source.content || '';
    const metadata = typeof source.metadata === 'string'
      ? JSON.parse(source.metadata)
      : (source.metadata || {});

    // Update the payload with fresh content
    return {
      ...payload,
      sourceCode: content,
      githubContext: {
        ...payload.githubContext,
        currentContent: content,
        commitSha: metadata.commitSha || payload.githubContext.commitSha,
      },
    };
  }

  /**
   * Get repository structure for context
   * Returns a list of file paths in the repository
   * 
   * @param userId - The user ID
   * @param owner - Repository owner
   * @param repo - Repository name
   * @returns Array of file paths
   */
  private async getRepoStructure(userId: string, owner: string, repo: string): Promise<string[]> {
    // Get all GitHub sources from this repo for this user
    const result = await pool.query(
      `SELECT DISTINCT metadata->>'path' as path
       FROM sources s
       INNER JOIN notebooks n ON s.notebook_id = n.id
       WHERE n.user_id = $1 
         AND s.type = 'github'
         AND s.metadata->>'owner' = $2
         AND s.metadata->>'repo' = $3
       ORDER BY path`,
      [userId, owner, repo]
    );

    return result.rows.map(row => row.path).filter(Boolean);
  }

  /**
   * Validate that a GitHub webhook payload contains all required fields
   * 
   * @param payload - The payload to validate
   * @returns Error message if invalid, null if valid
   */
  validatePayload(payload: GitHubWebhookPayload): string | null {
    // Validate base webhook fields
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

    // Validate GitHub context
    if (!payload.githubContext) {
      return 'Missing required field: githubContext';
    }
    if (!payload.githubContext.owner) {
      return 'Missing required field: githubContext.owner';
    }
    if (!payload.githubContext.repo) {
      return 'Missing required field: githubContext.repo';
    }
    if (!payload.githubContext.path) {
      return 'Missing required field: githubContext.path';
    }
    if (!payload.githubContext.branch) {
      return 'Missing required field: githubContext.branch';
    }
    if (payload.githubContext.currentContent === undefined || payload.githubContext.currentContent === null) {
      return 'Missing required field: githubContext.currentContent';
    }
    if (!payload.githubContext.language) {
      return 'Missing required field: githubContext.language';
    }

    return null;
  }
}

// Export singleton instance
export const githubWebhookBuilder = new GitHubWebhookBuilder();

// Export class for testing
export { GitHubWebhookBuilder };

export default githubWebhookBuilder;
