import pool from '../config/database.js';
import { generateWithGemini, generateWithOpenRouter, ChatMessage } from './aiService.js';
import { mcpUserSettingsService } from './mcpUserSettingsService.js';
import { GoogleGenerativeAI } from '@google/generative-ai';
import axios from 'axios';
import { githubService } from './githubService.js';

// Initialize Gemini
const genAI = process.env.GEMINI_API_KEY
  ? new GoogleGenerativeAI(process.env.GEMINI_API_KEY)
  : null;

const openRouterApiKey = process.env.OPENROUTER_API_KEY || null;

export interface AIModel {
  id: string;
  name: string;
  model_id: string;
  provider: 'gemini' | 'openrouter';
  description: string;
  is_active: boolean;
  is_premium: boolean;
}

export interface CodeReviewIssue {
  id: string;
  severity: 'error' | 'warning' | 'info';
  category: 'security' | 'performance' | 'style' | 'logic' | 'best-practice';
  message: string;
  line?: number;
  column?: number;
  suggestion?: string;
  codeExample?: string;
}

export interface CodeReview {
  id: string;
  userId: string;
  code: string;
  language: string;
  reviewType: string;
  score: number;
  summary: string;
  issues: CodeReviewIssue[];
  suggestions: string[];
  context?: string;
  relatedFilesUsed?: string[];
  createdAt: Date;
}

export interface GitHubContextOptions {
  owner: string;
  repo: string;
  branch?: string;
  maxFiles?: number;
  maxFileSize?: number;
}

export interface RelatedFile {
  path: string;
  content: string;
  language: string;
}

export interface ReviewComparisonResult {
  originalScore: number;
  updatedScore: number;
  improvement: number;
  resolvedIssues: CodeReviewIssue[];
  newIssues: CodeReviewIssue[];
  summary: string;
}

class CodeReviewService {
  /**
   * Extract imports/dependencies from code based on language
   */
  private extractImports(code: string, language: string): string[] {
    const imports: string[] = [];

    switch (language.toLowerCase()) {
      case 'typescript':
      case 'javascript':
      case 'tsx':
      case 'jsx':
        // ES6 imports: import X from './path' or import { X } from './path'
        const esImports = code.matchAll(/import\s+(?:[\w{},\s*]+\s+from\s+)?['"]([^'"]+)['"]/g);
        for (const match of esImports) {
          if (match[1] && !match[1].startsWith('@') && !match[1].includes('node_modules')) {
            imports.push(match[1]);
          }
        }
        // require statements
        const requires = code.matchAll(/require\s*\(\s*['"]([^'"]+)['"]\s*\)/g);
        for (const match of requires) {
          if (match[1] && !match[1].startsWith('@') && !match[1].includes('node_modules')) {
            imports.push(match[1]);
          }
        }
        break;

      case 'python':
        // from X import Y or import X
        const pyImports = code.matchAll(/(?:from\s+(\S+)\s+import|import\s+(\S+))/g);
        for (const match of pyImports) {
          const importPath = match[1] || match[2];
          if (importPath && !importPath.includes('.')) {
            // Relative imports
            imports.push(importPath.replace(/\./g, '/') + '.py');
          }
        }
        break;

      case 'dart':
        // import 'package:X' or import 'X.dart'
        const dartImports = code.matchAll(/import\s+['"]([^'"]+)['"]/g);
        for (const match of dartImports) {
          if (match[1] && !match[1].startsWith('package:') && !match[1].startsWith('dart:')) {
            imports.push(match[1]);
          }
        }
        break;

      case 'java':
      case 'kotlin':
        // import com.example.Class
        const javaImports = code.matchAll(/import\s+([\w.]+)/g);
        for (const match of javaImports) {
          if (match[1] && !match[1].startsWith('java.') && !match[1].startsWith('javax.')) {
            imports.push(match[1].replace(/\./g, '/') + (language === 'kotlin' ? '.kt' : '.java'));
          }
        }
        break;

      case 'go':
        // import "path/to/package"
        const goImports = code.matchAll(/import\s+(?:\(\s*)?["']([^"']+)["']/g);
        for (const match of goImports) {
          if (match[1] && !match[1].includes('github.com') && !match[1].includes('/')) {
            imports.push(match[1]);
          }
        }
        break;

      case 'rust':
        // use crate::module or mod module
        const rustImports = code.matchAll(/(?:use\s+crate::(\w+)|mod\s+(\w+))/g);
        for (const match of rustImports) {
          const mod = match[1] || match[2];
          if (mod) imports.push(mod + '.rs');
        }
        break;
    }

    return [...new Set(imports)]; // Remove duplicates
  }

  /**
   * Resolve import path to actual file path
   */
  private resolveImportPath(importPath: string, language: string, currentFilePath?: string): string {
    // Remove leading ./ or ../
    let resolved = importPath.replace(/^\.\//, '').replace(/^\.\.\//, '');

    // Add extension if missing
    const extensions: Record<string, string[]> = {
      typescript: ['.ts', '.tsx', '/index.ts', '/index.tsx'],
      javascript: ['.js', '.jsx', '/index.js', '/index.jsx'],
      tsx: ['.tsx', '.ts', '/index.tsx', '/index.ts'],
      jsx: ['.jsx', '.js', '/index.jsx', '/index.js'],
    };

    const langExtensions = extensions[language.toLowerCase()];
    if (langExtensions && !langExtensions.some(ext => resolved.endsWith(ext))) {
      // Return base path, we'll try multiple extensions when fetching
      return resolved;
    }

    return resolved;
  }

  /**
   * Fetch related files from GitHub based on imports
   */
  async fetchGitHubContext(
    userId: string,
    code: string,
    language: string,
    options: GitHubContextOptions
  ): Promise<RelatedFile[]> {
    const relatedFiles: RelatedFile[] = [];
    const imports = this.extractImports(code, language);

    if (imports.length === 0) {
      console.log('[Code Review] No imports detected in code');
      return relatedFiles;
    }

    console.log(`[Code Review] Detected ${imports.length} imports:`, imports);

    const maxFiles = options.maxFiles || 5;
    const maxFileSize = options.maxFileSize || 50000; // 50KB max per file

    // Get repo tree to find matching files
    let repoTree: Array<{ path: string; type: string; size?: number }> = [];
    try {
      repoTree = await githubService.getRepoTree(userId, options.owner, options.repo, options.branch);
    } catch (error: any) {
      console.log('[Code Review] Failed to get repo tree:', error.message);
      return relatedFiles;
    }

    // Find matching files for each import
    const filesToFetch: string[] = [];
    const extensions = ['', '.ts', '.tsx', '.js', '.jsx', '/index.ts', '/index.tsx', '/index.js', '/index.jsx'];

    for (const importPath of imports) {
      if (filesToFetch.length >= maxFiles) break;

      const resolved = this.resolveImportPath(importPath, language);

      // Try to find matching file in repo tree
      for (const ext of extensions) {
        const possiblePath = resolved + ext;
        const match = repoTree.find(item =>
          item.type === 'blob' &&
          (item.path === possiblePath ||
            item.path.endsWith('/' + possiblePath) ||
            item.path.includes(resolved))
        );

        if (match && match.size && match.size < maxFileSize) {
          if (!filesToFetch.includes(match.path)) {
            filesToFetch.push(match.path);
            break;
          }
        }
      }
    }

    console.log(`[Code Review] Fetching ${filesToFetch.length} related files:`, filesToFetch);

    // Fetch file contents
    for (const filePath of filesToFetch) {
      try {
        const fileContent = await githubService.getFileContent(
          userId,
          options.owner,
          options.repo,
          filePath,
          options.branch
        );

        if (fileContent.content) {
          relatedFiles.push({
            path: filePath,
            content: fileContent.content,
            language: this.detectLanguage(filePath),
          });
        }
      } catch (error: any) {
        console.log(`[Code Review] Failed to fetch ${filePath}:`, error.message);
      }
    }

    return relatedFiles;
  }

  /**
   * Detect language from file extension
   */
  private detectLanguage(filePath: string): string {
    const ext = filePath.split('.').pop()?.toLowerCase();
    const langMap: Record<string, string> = {
      ts: 'typescript',
      tsx: 'typescript',
      js: 'javascript',
      jsx: 'javascript',
      py: 'python',
      dart: 'dart',
      java: 'java',
      kt: 'kotlin',
      go: 'go',
      rs: 'rust',
      rb: 'ruby',
      php: 'php',
      cs: 'csharp',
      cpp: 'cpp',
      c: 'c',
      swift: 'swift',
    };
    return langMap[ext || ''] || ext || 'text';
  }

  /**
   * Get a specific model by ID from the database
   */
  private async getModel(modelId: string): Promise<AIModel | null> {
    try {
      const result = await pool.query(
        `SELECT id, name, model_id, provider, description, is_active, is_premium 
         FROM ai_models 
         WHERE model_id = $1 AND is_active = true`,
        [modelId]
      );
      return result.rows[0] || null;
    } catch (error) {
      console.error('Error fetching model:', error);
      return null;
    }
  }

  /**
   * Get the default model for code review (first active model, prefer Gemini)
   */
  private async getDefaultModel(): Promise<AIModel | null> {
    try {
      const result = await pool.query(
        `SELECT id, name, model_id, provider, description, is_active, is_premium 
         FROM ai_models 
         WHERE is_active = true 
         ORDER BY 
           CASE WHEN provider = 'gemini' THEN 0 ELSE 1 END,
           name
         LIMIT 1`
      );
      return result.rows[0] || null;
    } catch (error) {
      console.error('Error fetching default model:', error);
      return null;
    }
  }

  /**
   * Generate content using the specified model or fallback
   */
  private async generateWithModel(
    prompt: string,
    modelId?: string
  ): Promise<{ text: string; provider: 'gemini' | 'openrouter'; modelName?: string }> {
    // If a specific model is requested, try to use it
    if (modelId) {
      const model = await this.getModel(modelId);
      if (model) {
        try {
          if (model.provider === 'gemini' && genAI) {
            const genModel = genAI.getGenerativeModel({ model: model.model_id });
            const result = await genModel.generateContent(prompt);
            return { text: result.response.text(), provider: 'gemini', modelName: model.name };
          } else if (model.provider === 'openrouter' && openRouterApiKey) {
            const response = await axios.post(
              'https://openrouter.ai/api/v1/chat/completions',
              {
                model: model.model_id,
                messages: [{ role: 'user', content: prompt }],
                max_tokens: 4096,
              },
              {
                timeout: 120000,
                headers: {
                  'Authorization': `Bearer ${openRouterApiKey}`,
                  'Content-Type': 'application/json',
                  'HTTP-Referer': 'https://noteclaw.app',
                  'X-Title': 'NoteClaw Code Review'
                }
              }
            );
            return { text: response.data.choices[0].message.content, provider: 'openrouter', modelName: model.name };
          }
        } catch (error: any) {
          console.log(`[Code Review] Selected model ${model.name} failed, falling back:`, error.message);
        }
      }
    }

    // Try getting the default model from database first
    const defaultModel = await this.getDefaultModel();
    if (defaultModel) {
      try {
        if (defaultModel.provider === 'gemini' && genAI) {
          const genModel = genAI.getGenerativeModel({ model: defaultModel.model_id });
          const result = await genModel.generateContent(prompt);
          return { text: result.response.text(), provider: 'gemini', modelName: defaultModel.name };
        } else if (defaultModel.provider === 'openrouter' && openRouterApiKey) {
          const response = await axios.post(
            'https://openrouter.ai/api/v1/chat/completions',
            {
              model: defaultModel.model_id,
              messages: [{ role: 'user', content: prompt }],
              max_tokens: 4096,
            },
            {
              timeout: 120000,
              headers: {
                'Authorization': `Bearer ${openRouterApiKey}`,
                'Content-Type': 'application/json',
                'HTTP-Referer': 'https://noteclaw.app',
                'X-Title': 'NoteClaw Code Review'
              }
            }
          );
          return { text: response.data.choices[0].message.content, provider: 'openrouter', modelName: defaultModel.name };
        }
      } catch (error: any) {
        console.log(`[Code Review] Default model ${defaultModel.name} failed, using direct API fallback:`, error.message);
      }
    }

    // Fallback to direct Gemini API if available
    if (genAI) {
      try {
        const messages: ChatMessage[] = [{ role: 'user', content: prompt }];
        const text = await generateWithGemini(messages);
        return { text, provider: 'gemini', modelName: 'Gemini (Direct)' };
      } catch (error: any) {
        console.log('[Code Review] Gemini failed, trying OpenRouter:', error.message);
      }
    }

    // Fallback to OpenRouter
    if (openRouterApiKey) {
      try {
        const messages: ChatMessage[] = [{ role: 'user', content: prompt }];
        const text = await generateWithOpenRouter(messages);
        return { text, provider: 'openrouter', modelName: 'OpenRouter (Fallback)' };
      } catch (error: any) {
        console.log('[Code Review] OpenRouter also failed:', error.message);
        throw error;
      }
    }

    throw new Error('No AI provider available for code review');
  }

  async reviewCode(
    userId: string,
    code: string,
    language: string,
    reviewType: string = 'comprehensive',
    context?: string,
    saveReview: boolean = true,
    githubContext?: GitHubContextOptions
  ): Promise<CodeReview> {
    // Get user's preferred AI model for code analysis
    let modelId: string | null = null;
    try {
      modelId = await mcpUserSettingsService.getCodeAnalysisModelId(userId);
      if (modelId) {
        console.log(`[Code Review] Using user's preferred model: ${modelId}`);
      }
    } catch (error) {
      console.log('[Code Review] Could not get user model preference, using default');
    }

    // Fetch related files from GitHub if context options provided
    let relatedFiles: RelatedFile[] = [];
    if (githubContext) {
      try {
        relatedFiles = await this.fetchGitHubContext(userId, code, language, githubContext);
        console.log(`[Code Review] Fetched ${relatedFiles.length} related files for context`);
      } catch (error: any) {
        console.log('[Code Review] Failed to fetch GitHub context:', error.message);
      }
    }

    // Generate AI review with user's preferred model and context
    const reviewResult = await this.generateAIReview(code, language, reviewType, context, modelId || undefined, relatedFiles);

    if (saveReview) {
      // Save to database
      const result = await pool.query(
        `INSERT INTO code_reviews (user_id, code, language, review_type, score, summary, issues, suggestions, context, related_files_used)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
         RETURNING *`,
        [userId, code, language, reviewType, reviewResult.score, reviewResult.summary,
          JSON.stringify(reviewResult.issues), JSON.stringify(reviewResult.suggestions), context,
          relatedFiles.length > 0 ? JSON.stringify(relatedFiles.map(f => f.path)) : null]
      );

      return this.mapRowToReview(result.rows[0]);
    }

    return {
      id: 'temp-' + Date.now(),
      userId,
      code,
      language,
      reviewType,
      ...reviewResult,
      relatedFilesUsed: relatedFiles.map(f => f.path),
      createdAt: new Date(),
    };
  }

  private async generateAIReview(
    code: string,
    language: string,
    reviewType: string,
    context?: string,
    modelId?: string,
    relatedFiles?: RelatedFile[]
  ): Promise<{ score: number; summary: string; issues: CodeReviewIssue[]; suggestions: string[]; modelUsed?: string }> {
    const focusAreas = {
      comprehensive: 'security, performance, readability, best practices, and potential bugs',
      security: 'security vulnerabilities, injection risks, authentication issues, and data exposure',
      performance: 'performance bottlenecks, memory leaks, inefficient algorithms, and optimization opportunities',
      readability: 'code clarity, naming conventions, documentation, and maintainability',
    };

    // Build related files context
    let relatedFilesContext = '';
    if (relatedFiles && relatedFiles.length > 0) {
      relatedFilesContext = `\n\n## Related Files (for context)
The following files are imported/used by the code being reviewed. Use them to understand the full context:

${relatedFiles.map(f => `### ${f.path}
\`\`\`${f.language}
${f.content.slice(0, 3000)}${f.content.length > 3000 ? '\n// ... (truncated)' : ''}
\`\`\``).join('\n\n')}
`;
    }

    const prompt = `You are an expert code reviewer. Analyze the following ${language} code and provide a detailed review.

Focus on: ${focusAreas[reviewType as keyof typeof focusAreas] || focusAreas.comprehensive}
${context ? `Context: ${context}` : ''}
${relatedFiles && relatedFiles.length > 0 ? `\nThis review is CONTEXT-AWARE. You have access to ${relatedFiles.length} related file(s) that this code imports or depends on. Use this context to:
- Verify correct usage of imported functions/classes
- Check for type mismatches with imported modules
- Identify potential integration issues
- Understand the broader codebase patterns` : ''}
${relatedFilesContext}

## Code to Review:
\`\`\`${language}
${code}
\`\`\`

Respond with a JSON object in this exact format:
{
  "score": <number 0-100>,
  "summary": "<brief overview of code quality${relatedFiles && relatedFiles.length > 0 ? ', including how well it integrates with related files' : ''}>",
  "issues": [
    {
      "id": "<unique-id>",
      "severity": "error|warning|info",
      "category": "security|performance|style|logic|best-practice|integration",
      "message": "<description of the issue>",
      "line": <line number if applicable>,
      "suggestion": "<how to fix>",
      "codeExample": "<corrected code snippet if applicable>"
    }
  ],
  "suggestions": ["<general improvement suggestion>"]
}

Be thorough but fair. Score guidelines:
- 90-100: Excellent, production-ready code
- 70-89: Good code with minor issues
- 50-69: Acceptable but needs improvement
- 30-49: Significant issues need addressing
- 0-29: Major problems, needs rewrite
${relatedFiles && relatedFiles.length > 0 ? '\nNote: Include "integration" category for issues related to how this code interacts with the imported files.' : ''}`;

    try {
      const { text: response, provider, modelName } = await this.generateWithModel(prompt, modelId);
      console.log(`[Code Review] Generated review using ${modelName || provider}${relatedFiles?.length ? ` with ${relatedFiles.length} context files` : ''}`);

      // Parse JSON from response
      const jsonMatch = response.match(/\{[\s\S]*\}/);
      if (jsonMatch) {
        const parsed = JSON.parse(jsonMatch[0]);
        return {
          score: Math.min(100, Math.max(0, parsed.score || 50)),
          summary: parsed.summary || 'Review completed',
          issues: (parsed.issues || []).map((issue: any, idx: number) => ({
            id: issue.id || `issue-${idx}`,
            severity: issue.severity || 'info',
            category: issue.category || 'best-practice',
            message: issue.message || '',
            line: issue.line,
            column: issue.column,
            suggestion: issue.suggestion,
            codeExample: issue.codeExample,
          })),
          suggestions: parsed.suggestions || [],
          modelUsed: modelName || provider,
        };
      }
    } catch (error) {
      console.error('AI review generation failed:', error);
    }

    // Fallback response
    return {
      score: 50,
      summary: 'Unable to generate detailed review. Please try again.',
      issues: [],
      suggestions: ['Consider running the review again for detailed analysis'],
    };
  }

  async getReviewHistory(
    userId: string,
    options: { language?: string; limit?: number; minScore?: number; maxScore?: number }
  ): Promise<CodeReview[]> {
    let query = `SELECT * FROM code_reviews WHERE user_id = $1`;
    const params: any[] = [userId];
    let paramIndex = 2;

    if (options.language) {
      query += ` AND language = $${paramIndex++}`;
      params.push(options.language);
    }
    if (options.minScore !== undefined) {
      query += ` AND score >= $${paramIndex++}`;
      params.push(options.minScore);
    }
    if (options.maxScore !== undefined) {
      query += ` AND score <= $${paramIndex++}`;
      params.push(options.maxScore);
    }

    query += ` ORDER BY created_at DESC LIMIT $${paramIndex}`;
    params.push(options.limit || 20);

    const result = await pool.query(query, params);
    return result.rows.map(this.mapRowToReview);
  }

  async getReviewById(reviewId: string, userId: string): Promise<CodeReview | null> {
    const result = await pool.query(
      `SELECT * FROM code_reviews WHERE id = $1 AND user_id = $2`,
      [reviewId, userId]
    );
    return result.rows[0] ? this.mapRowToReview(result.rows[0]) : null;
  }

  async compareCodeVersions(
    userId: string,
    originalCode: string,
    updatedCode: string,
    language: string,
    context?: string
  ): Promise<ReviewComparisonResult> {
    // Review both versions
    const [originalReview, updatedReview] = await Promise.all([
      this.reviewCode(userId, originalCode, language, 'comprehensive', context, false),
      this.reviewCode(userId, updatedCode, language, 'comprehensive', context, false),
    ]);

    // Find resolved and new issues
    const originalIssueMessages = new Set(originalReview.issues.map(i => i.message));
    const updatedIssueMessages = new Set(updatedReview.issues.map(i => i.message));

    const resolvedIssues = originalReview.issues.filter(i => !updatedIssueMessages.has(i.message));
    const newIssues = updatedReview.issues.filter(i => !originalIssueMessages.has(i.message));

    const improvement = updatedReview.score - originalReview.score;

    // Generate comparison summary
    let summary = '';
    if (improvement > 0) {
      summary = `Code quality improved by ${improvement} points. ${resolvedIssues.length} issues were resolved.`;
    } else if (improvement < 0) {
      summary = `Code quality decreased by ${Math.abs(improvement)} points. ${newIssues.length} new issues were introduced.`;
    } else {
      summary = `Code quality remained the same. ${resolvedIssues.length} issues resolved, ${newIssues.length} new issues.`;
    }

    // Save comparison
    await pool.query(
      `INSERT INTO code_review_comparisons 
       (user_id, original_code, updated_code, language, original_score, updated_score, improvement, resolved_issues, new_issues, summary)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)`,
      [userId, originalCode, updatedCode, language, originalReview.score, updatedReview.score,
        improvement, JSON.stringify(resolvedIssues), JSON.stringify(newIssues), summary]
    );

    return {
      originalScore: originalReview.score,
      updatedScore: updatedReview.score,
      improvement,
      resolvedIssues,
      newIssues,
      summary,
    };
  }

  private mapRowToReview(row: any): CodeReview {
    return {
      id: row.id,
      userId: row.user_id,
      code: row.code,
      language: row.language,
      reviewType: row.review_type,
      score: row.score,
      summary: row.summary,
      issues: typeof row.issues === 'string' ? JSON.parse(row.issues) : row.issues,
      suggestions: typeof row.suggestions === 'string' ? JSON.parse(row.suggestions) : row.suggestions,
      context: row.context,
      relatedFilesUsed: row.related_files_used
        ? (typeof row.related_files_used === 'string' ? JSON.parse(row.related_files_used) : row.related_files_used)
        : undefined,
      createdAt: row.created_at,
    };
  }
}

export const codeReviewService = new CodeReviewService();
