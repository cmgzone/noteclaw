import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import {
  type ChatMessage,
  generateWithGemini,
  generateWithOpenRouter,
} from './aiService.js';
import ebookImageService, { type EbookImageSource } from './ebookImageService.js';
import { decryptSecretAllowLegacy } from './secretEncryptionService.js';

type SupportedProvider = 'gemini' | 'openrouter';
type EbookStatus = 'draft' | 'generating' | 'completed' | 'error';

interface QueueEbookGenerationInput {
  userId: string;
  ebookId?: string;
  title: string;
  topic?: string;
  targetAudience?: string;
  notebookId?: string;
  selectedModel?: string;
  branding?: Record<string, unknown>;
  chapterCount?: number;
  chapterInstructions?: string;
  generateChapterImages?: boolean;
  imageSource?: EbookImageSource;
  imageModel?: string;
  imageStyle?: string;
  createPlaceholderCover?: boolean;
}

interface PreparedEbookGeneration {
  projectId: string;
  userId: string;
  title: string;
  topic: string;
  targetAudience: string;
  notebookId?: string;
  selectedModel: string;
  provider: SupportedProvider;
  apiKey?: string;
  branding: Record<string, unknown>;
  chapterCount: number;
  chapterInstructions?: string;
  generateChapterImages: boolean;
  imageSource: EbookImageSource;
  imageModel?: string;
  imageApiKey?: string;
  imageStyle: string;
  createPlaceholderCover: boolean;
  coverImage?: string;
}

interface OutlineChapter {
  id: string;
  title: string;
  description: string;
  chapterOrder: number;
}

interface ExistingProjectRow {
  id: string;
  status: string;
}

interface StoredEbookImage {
  id: string;
  prompt: string;
  url: string;
  caption: string;
  type: string;
}

class EbookGenerationError extends Error {
  statusCode: number;

  constructor(statusCode: number, message: string) {
    super(message);
    this.statusCode = statusCode;
  }
}

class EbookGenerationService {
  private readonly activeGenerations = new Set<string>();

  async queueGeneration(input: QueueEbookGenerationInput) {
    const prepared = await this.prepareGeneration(input);
    const project = await this.upsertProject({
      projectId: prepared.projectId,
      userId: prepared.userId,
      notebookId: prepared.notebookId,
      title: prepared.title,
      topic: prepared.topic,
      targetAudience: prepared.targetAudience,
      branding: prepared.branding,
      selectedModel: prepared.selectedModel,
      status: 'generating',
      coverImage: prepared.coverImage,
    });

    this.activeGenerations.add(prepared.projectId);
    void this.runGeneration(prepared).catch((error) => {
      console.error('[EbookGeneration] Unhandled generation failure:', error);
    });

    return project;
  }

  isHttpError(error: unknown): error is EbookGenerationError {
    return error instanceof EbookGenerationError;
  }

  private async prepareGeneration(
    input: QueueEbookGenerationInput,
  ): Promise<PreparedEbookGeneration> {
    const userId = input.userId?.trim();
    const title = input.title?.trim();

    if (!userId) {
      throw new EbookGenerationError(401, 'Unauthorized');
    }

    if (!title) {
      throw new EbookGenerationError(400, 'title is required');
    }

    const notebookId = input.notebookId?.trim() || undefined;
    const existingProject = input.ebookId
      ? await this.getExistingProject(input.ebookId, userId)
      : null;
    const projectId = existingProject?.id || uuidv4();

    if (
      this.activeGenerations.has(projectId) ||
      existingProject?.status === 'generating'
    ) {
      throw new EbookGenerationError(
        409,
        'This ebook is already being generated',
      );
    }

    if (notebookId) {
      await this.assertNotebookOwnership(notebookId, userId);
    }

    const resolvedModel = await this.resolveModelForUser(
      userId,
      input.selectedModel,
    );
    const imageSource = input.imageSource || 'web';
    const resolvedImageSettings = await this.resolveImageSettingsForUser(
      userId,
      imageSource,
      input.imageModel,
      resolvedModel.model,
    );
    const branding = this.normalizeBranding(input.branding);
    const topic = input.topic?.trim() || title;
    const targetAudience = input.targetAudience?.trim() || 'General readers';
    const chapterCount = this.clampChapterCount(input.chapterCount);
    const createPlaceholderCover = input.createPlaceholderCover === true;

    return {
      projectId,
      userId,
      title,
      topic,
      targetAudience,
      notebookId,
      selectedModel: resolvedModel.model,
      provider: resolvedModel.provider,
      apiKey: resolvedModel.apiKey,
      branding,
      chapterCount,
      chapterInstructions: input.chapterInstructions?.trim() || undefined,
      generateChapterImages: input.generateChapterImages === true,
      imageSource,
      imageModel: resolvedImageSettings.imageModel,
      imageApiKey: resolvedImageSettings.imageApiKey,
      imageStyle:
        input.imageStyle?.trim() ||
        'professional, polished, cohesive book illustration',
      createPlaceholderCover,
      coverImage: undefined,
    };
  }

  private async runGeneration(prepared: PreparedEbookGeneration) {
    try {
      const coverImage = await this.resolveCoverImage(prepared);
      if (coverImage) {
        await this.updateProjectCover(
          prepared.projectId,
          prepared.userId,
          coverImage,
        );
      }

      const notebookContext = prepared.notebookId
        ? await this.getNotebookContext(prepared.notebookId, prepared.userId)
        : '';
      const researchSummary = await this.generateResearchSummary(
        prepared,
        notebookContext,
      );
      const outline = await this.generateOutline(
        prepared,
        researchSummary,
        notebookContext,
      );

      await this.replaceOutlineChapters(prepared, outline);

      for (const chapter of outline) {
        const content = await this.generateChapterContent(
          prepared,
          chapter,
          outline,
          researchSummary,
        );
        const images = prepared.generateChapterImages
          ? await this.resolveChapterImages(prepared, chapter, content)
          : [];
        await this.updateChapterContent(
          prepared.projectId,
          prepared.userId,
          chapter.id,
          content,
          'completed',
          images,
        );
      }

      await this.updateProjectStatus(
        prepared.projectId,
        prepared.userId,
        'completed',
      );
    } catch (error) {
      console.error('[EbookGeneration] Generation failed:', error);
      await this.updateProjectStatus(prepared.projectId, prepared.userId, 'error');
    } finally {
      this.activeGenerations.delete(prepared.projectId);
    }
  }

  private async resolveCoverImage(prepared: PreparedEbookGeneration) {
    const resolvedImage = await ebookImageService.resolveImage({
      prompt: this.buildCoverImagePrompt(prepared),
      queries: [
        `${prepared.title} ${prepared.topic} book cover`,
        `${prepared.topic} book cover`,
        `${prepared.topic} illustration`,
      ],
      source: prepared.imageSource,
      imageModel: prepared.imageModel,
      imageApiKey: prepared.imageApiKey,
      aspectRatio: '3:4',
    });

    if (resolvedImage) {
      return resolvedImage.url;
    }

    if (prepared.createPlaceholderCover) {
      return this.buildPlaceholderCover(
        prepared.title,
        prepared.topic,
        prepared.branding,
      );
    }

    return undefined;
  }

  private async resolveChapterImages(
    prepared: PreparedEbookGeneration,
    chapter: OutlineChapter,
    content: string,
  ): Promise<StoredEbookImage[]> {
    const prompt = this.buildChapterImagePrompt(prepared, chapter, content);
    const resolvedImage = await ebookImageService.resolveImage({
      prompt,
      queries: [
        `${chapter.title} ${prepared.topic} illustration`,
        `${chapter.title} ${prepared.topic}`,
        `${prepared.topic} ${chapter.title} diagram`,
      ],
      source: prepared.imageSource,
      imageModel: prepared.imageModel,
      imageApiKey: prepared.imageApiKey,
      aspectRatio: '1:1',
    });

    if (!resolvedImage) {
      return [];
    }

    return [
      this.buildStoredEbookImage({
        prompt,
        url: resolvedImage.url,
        caption: chapter.title,
        type: resolvedImage.source,
      }),
    ];
  }

  private async generateResearchSummary(
    prepared: PreparedEbookGeneration,
    notebookContext: string,
  ) {
    const prompt = `
You are a research agent preparing source material for an ebook.

Ebook title: ${prepared.title}
Topic: ${prepared.topic}
Target audience: ${prepared.targetAudience}

Notebook context:
${notebookContext || 'No notebook context was provided.'}

Write a focused research brief that will help an author create this ebook.
Include:
- the most important concepts the reader needs
- practical details, examples, and facts worth mentioning
- common mistakes or misconceptions to avoid
- a recommended teaching progression for the chapters

Keep it concise but information-dense. Return plain text only.
`.trim();

    return this.generateText(prepared, prompt);
  }

  private async generateOutline(
    prepared: PreparedEbookGeneration,
    researchSummary: string,
    notebookContext: string,
  ): Promise<OutlineChapter[]> {
    const prompt = `
You are an expert author and editor.

Create a chapter outline for this ebook:
- Title: ${prepared.title}
- Topic: ${prepared.topic}
- Target audience: ${prepared.targetAudience}
- Desired chapter count: ${prepared.chapterCount}

Author instructions:
${prepared.chapterInstructions || 'No extra instructions.'}

Research brief:
${this.truncate(researchSummary, 8000)}

Notebook context:
${this.truncate(notebookContext || 'No notebook context was provided.', 6000)}

Return ONLY valid JSON.
Use this schema:
{
  "chapters": [
    {
      "title": "Chapter title",
      "description": "1-3 sentence description"
    }
  ]
}

Rules:
- Return exactly ${prepared.chapterCount} chapters
- Chapters should build logically from fundamentals to more advanced material
- Titles should be clear and specific
- Descriptions should explain the teaching goal of the chapter
`.trim();

    const response = await this.generateText(prepared, prompt);
    const parsed = this.parseJsonResponse(response);

    const rawChapters = Array.isArray(parsed)
      ? parsed
      : Array.isArray(parsed?.chapters)
        ? parsed.chapters
        : [];

    const chapters = rawChapters
      .map((chapter: Record<string, unknown>, index: number) => ({
        id: uuidv4(),
        title: String(chapter.title || '').trim(),
        description: String(chapter.description || '').trim(),
        chapterOrder: index + 1,
      }))
      .filter((chapter: OutlineChapter) => chapter.title.length > 0);

    if (chapters.length === 0) {
      throw new Error('Outline generation returned no chapters');
    }

    return chapters.slice(0, prepared.chapterCount);
  }

  private async generateChapterContent(
    prepared: PreparedEbookGeneration,
    chapter: OutlineChapter,
    outline: OutlineChapter[],
    researchSummary: string,
  ) {
    const outlineText = outline
      .map(
        (item) =>
          `${item.chapterOrder}. ${item.title}: ${this.truncate(item.description, 220)}`,
      )
      .join('\n');

    const prompt = `
You are an expert nonfiction author.

Write Chapter ${chapter.chapterOrder} of the ebook "${prepared.title}".

Topic: ${prepared.topic}
Target audience: ${prepared.targetAudience}
Full outline:
${outlineText}

Current chapter:
Title: ${chapter.title}
Goal: ${chapter.description}

Research brief:
${this.truncate(researchSummary, 8000)}

Extra author instructions:
${prepared.chapterInstructions || 'No extra instructions.'}

Return Markdown only.
Requirements:
- Do not include the book title at the top
- Start with an engaging opening paragraph
- Use clear section headings
- Include concrete examples or actionable takeaways where useful
- Match the target audience's level of expertise
- End with a short transition into the next chapter when appropriate
`.trim();

    return this.generateText(prepared, prompt);
  }

  private async generateText(
    prepared: PreparedEbookGeneration,
    prompt: string,
  ): Promise<string> {
    const messages: ChatMessage[] = [{ role: 'user', content: prompt }];

    if (prepared.provider === 'openrouter') {
      return generateWithOpenRouter(
        messages,
        prepared.selectedModel,
        4096,
        prepared.apiKey,
      );
    }

    return generateWithGemini(messages, prepared.selectedModel, prepared.apiKey);
  }

  private async getExistingProject(ebookId: string, userId: string) {
    const result = await pool.query<ExistingProjectRow>(
      'SELECT id, status FROM ebook_projects WHERE id = $1 AND user_id = $2',
      [ebookId, userId],
    );

    if (result.rows.length === 0) {
      throw new EbookGenerationError(404, 'Project not found');
    }

    return result.rows[0];
  }

  private async assertNotebookOwnership(notebookId: string, userId: string) {
    const result = await pool.query(
      'SELECT id FROM notebooks WHERE id = $1 AND user_id = $2',
      [notebookId, userId],
    );

    if (result.rows.length === 0) {
      throw new EbookGenerationError(404, 'Notebook not found');
    }
  }

  private async getNotebookContext(notebookId: string, userId: string) {
    const result = await pool.query(
      `SELECT
          s.title,
          s.type,
          s.url,
          substring(COALESCE(NULLIF(s.summary, ''), s.content, '') from 1 for 2000) AS content
       FROM sources s
       JOIN notebooks n ON n.id = s.notebook_id
       WHERE n.id = $1 AND n.user_id = $2
       ORDER BY s.updated_at DESC NULLS LAST, s.created_at DESC
       LIMIT 8`,
      [notebookId, userId],
    );

    const chunks = result.rows
      .map((row: Record<string, unknown>, index: number) => {
        const title = String(row.title || `Source ${index + 1}`);
        const type = String(row.type || 'source');
        const url = row.url ? `\nURL: ${String(row.url)}` : '';
        const content = this.truncate(String(row.content || '').trim(), 1800);

        if (!content) {
          return '';
        }

        return `Source ${index + 1}: ${title} (${type})${url}\n${content}`;
      })
      .filter(Boolean);

    return chunks.join('\n\n');
  }

  private async replaceOutlineChapters(
    prepared: PreparedEbookGeneration,
    chapters: OutlineChapter[],
  ) {
    const client = await pool.connect();

    try {
      await client.query('BEGIN');
      await client.query(
        `DELETE FROM ebook_chapters
         WHERE project_id = $1
           AND EXISTS (
             SELECT 1 FROM ebook_projects ep
             WHERE ep.id = $1 AND ep.user_id = $2
           )`,
        [prepared.projectId, prepared.userId],
      );

      for (const chapter of chapters) {
        await client.query(
          `INSERT INTO ebook_chapters (
              id, project_id, title, content, chapter_order, images, status
           ) VALUES ($1, $2, $3, $4, $5, $6, $7)`,
          [
            chapter.id,
            prepared.projectId,
            chapter.title,
            chapter.description,
            chapter.chapterOrder,
            JSON.stringify([]),
            'draft',
          ],
        );
      }

      await client.query(
        'UPDATE ebook_projects SET updated_at = NOW() WHERE id = $1 AND user_id = $2',
        [prepared.projectId, prepared.userId],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  private async updateChapterContent(
    projectId: string,
    userId: string,
    chapterId: string,
    content: string,
    status: EbookStatus,
    images: StoredEbookImage[] = [],
  ) {
    await pool.query(
      `UPDATE ebook_chapters ec
       SET content = $3, status = $4, images = $5, updated_at = NOW()
       FROM ebook_projects ep
       WHERE ec.id = $1
         AND ec.project_id = ep.id
         AND ep.id = $2
         AND ep.user_id = $6`,
      [chapterId, projectId, content, status, JSON.stringify(images), userId],
    );

    await pool.query(
      'UPDATE ebook_projects SET updated_at = NOW() WHERE id = $1 AND user_id = $2',
      [projectId, userId],
    );
  }

  private async updateProjectStatus(
    projectId: string,
    userId: string,
    status: EbookStatus,
  ) {
    await pool.query(
      'UPDATE ebook_projects SET status = $3, updated_at = NOW() WHERE id = $1 AND user_id = $2',
      [projectId, userId, status],
    );
  }

  private async updateProjectCover(
    projectId: string,
    userId: string,
    coverImage: string,
  ) {
    await pool.query(
      `UPDATE ebook_projects
       SET cover_image = $3, updated_at = NOW()
       WHERE id = $1 AND user_id = $2`,
      [projectId, userId, coverImage],
    );
  }

  private buildCoverImagePrompt(prepared: PreparedEbookGeneration) {
    return `
Book cover design for "${prepared.title}".
Topic: ${prepared.topic}
Audience: ${prepared.targetAudience}
Style: ${prepared.imageStyle}, modern, publication quality, clean composition.
Primary color: ${String(prepared.branding.primary_color_value || 0xff2196f3)}
Do not include readable text in the image.
`.trim();
  }

  private buildChapterImagePrompt(
    prepared: PreparedEbookGeneration,
    chapter: OutlineChapter,
    content: string,
  ) {
    const contentPreview = this.truncate(content, 900);
    return `
Create an ebook chapter illustration.
Book topic: ${prepared.topic}
Chapter title: ${chapter.title}
Chapter goal: ${chapter.description}
Visual style: ${prepared.imageStyle}
Context:
${contentPreview}
Generate a single polished illustration with no readable text.
`.trim();
  }

  private buildStoredEbookImage(input: {
    prompt: string;
    url: string;
    caption: string;
    type: string;
  }): StoredEbookImage {
    return {
      id: uuidv4(),
      prompt: input.prompt,
      url: input.url,
      caption: input.caption,
      type: input.type,
    };
  }

  private async upsertProject(input: {
    projectId: string;
    userId: string;
    notebookId?: string;
    title: string;
    topic: string;
    targetAudience: string;
    branding: Record<string, unknown>;
    selectedModel: string;
    status: EbookStatus;
    coverImage?: string;
  }) {
    const result = await pool.query(
      `INSERT INTO ebook_projects (
          id,
          user_id,
          notebook_id,
          title,
          topic,
          target_audience,
          branding,
          selected_model,
          status,
          cover_image
       )
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       ON CONFLICT (id) DO UPDATE SET
          notebook_id = EXCLUDED.notebook_id,
          title = EXCLUDED.title,
          topic = EXCLUDED.topic,
          target_audience = EXCLUDED.target_audience,
          branding = EXCLUDED.branding,
          selected_model = EXCLUDED.selected_model,
          status = EXCLUDED.status,
          cover_image = COALESCE(EXCLUDED.cover_image, ebook_projects.cover_image),
          updated_at = NOW()
       WHERE ebook_projects.user_id = EXCLUDED.user_id
       RETURNING *`,
      [
        input.projectId,
        input.userId,
        input.notebookId ?? null,
        input.title,
        input.topic,
        input.targetAudience,
        JSON.stringify(input.branding),
        input.selectedModel,
        input.status,
        input.coverImage ?? null,
      ],
    );

    if (result.rows.length === 0) {
      throw new EbookGenerationError(404, 'Project not found');
    }

    return result.rows[0];
  }

  private async resolveModelForUser(userId: string, selectedModel?: string) {
    await this.ensureUserAIModelsTable();

    let model = selectedModel?.trim();
    let provider: SupportedProvider = 'gemini';
    let apiKey: string | undefined;

    if (!model) {
      const defaultModelResult = await pool.query(
        `SELECT model_id, provider, is_premium
         FROM ai_models
         WHERE is_default = TRUE AND is_active = TRUE
         LIMIT 1`,
      );

      if (defaultModelResult.rows.length > 0) {
        const defaultModel = defaultModelResult.rows[0];
        model = defaultModel.model_id;
        provider =
          defaultModel.provider === 'openrouter' ? 'openrouter' : 'gemini';

        if (defaultModel.is_premium) {
          const hasPremiumAccess = await this.userHasPremiumAccess(userId);
          if (!hasPremiumAccess) {
            throw new EbookGenerationError(
              403,
              'Premium model access required for ebook generation',
            );
          }
        }
      } else {
        model = 'gemini-2.0-flash';
      }
    }

    const finalModel = model || 'gemini-2.0-flash';

    const personalModelResult = await pool.query(
      `SELECT provider, encrypted_api_key
       FROM user_ai_models
       WHERE user_id = $1 AND model_id = $2 AND is_active = TRUE
       LIMIT 1`,
      [userId, finalModel],
    );

    if (personalModelResult.rows.length > 0) {
      const personalModel = personalModelResult.rows[0];
      provider = personalModel.provider === 'openrouter' ? 'openrouter' : 'gemini';
      apiKey = decryptSecretAllowLegacy(personalModel.encrypted_api_key);

      return { model: finalModel, provider, apiKey };
    }

    const modelResult = await pool.query(
      `SELECT provider, is_premium
       FROM ai_models
       WHERE model_id = $1 AND is_active = TRUE
       LIMIT 1`,
      [finalModel],
    );

    if (modelResult.rows.length > 0) {
      const row = modelResult.rows[0];
      provider = row.provider === 'openrouter' ? 'openrouter' : 'gemini';

      if (row.is_premium) {
        const hasPremiumAccess = await this.userHasPremiumAccess(userId);
        if (!hasPremiumAccess) {
          throw new EbookGenerationError(
            403,
            'Premium model access required for ebook generation',
          );
        }
      }
    } else if (this.looksLikeOpenRouterModel(finalModel)) {
      provider = 'openrouter';
    }

    return { model: finalModel, provider, apiKey };
  }

  private async resolveImageSettingsForUser(
    userId: string,
    imageSource: EbookImageSource,
    requestedImageModel?: string,
    selectedModel?: string,
  ): Promise<{ imageModel?: string; imageApiKey?: string }> {
    if (imageSource === 'web') {
      return {};
    }

    await this.ensureUserAIModelsTable();

    const modelCandidate =
      requestedImageModel?.trim() || selectedModel?.trim() || '';

    if (!modelCandidate) {
      return {};
    }

    const personalModelResult = await pool.query(
      `SELECT provider, encrypted_api_key
       FROM user_ai_models
       WHERE user_id = $1 AND model_id = $2 AND is_active = TRUE
       LIMIT 1`,
      [userId, modelCandidate],
    );

    if (personalModelResult.rows.length > 0) {
      const row = personalModelResult.rows[0];
      if (row.provider === 'openrouter') {
        return {
          imageModel: modelCandidate,
          imageApiKey: decryptSecretAllowLegacy(row.encrypted_api_key),
        };
      }

      return {};
    }

    const modelResult = await pool.query(
      `SELECT provider, is_premium
       FROM ai_models
       WHERE model_id = $1 AND is_active = TRUE
       LIMIT 1`,
      [modelCandidate],
    );

    if (modelResult.rows.length > 0) {
      const row = modelResult.rows[0];
      if (row.is_premium) {
        const hasPremiumAccess = await this.userHasPremiumAccess(userId);
        if (!hasPremiumAccess) {
          throw new EbookGenerationError(
            403,
            'Premium model access required for ebook image generation',
          );
        }
      }

      return row.provider === 'openrouter'
        ? { imageModel: modelCandidate }
        : {};
    }

    return this.looksLikeOpenRouterModel(modelCandidate)
      ? { imageModel: modelCandidate }
      : {};
  }

  private looksLikeOpenRouterModel(model: string) {
    return (
      model.includes('/') ||
      model.startsWith('openai/') ||
      model.startsWith('anthropic/') ||
      model.startsWith('deepseek/') ||
      model.startsWith('gpt-') ||
      model.startsWith('claude-') ||
      model.startsWith('meta-')
    );
  }

  private async ensureUserAIModelsTable() {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS user_ai_models (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        model_id TEXT NOT NULL,
        provider TEXT NOT NULL,
        encrypted_api_key TEXT NOT NULL,
        description TEXT,
        context_window INTEGER DEFAULT 0,
        is_active BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE(user_id, model_id)
      )
    `);
    await pool.query(
      'CREATE INDEX IF NOT EXISTS idx_user_ai_models_user_id ON user_ai_models(user_id)',
    );
  }

  private async userHasPremiumAccess(userId: string) {
    const result = await pool.query(
      `SELECT sp.is_free_plan
       FROM user_subscriptions us
       JOIN subscription_plans sp ON us.plan_id = sp.id
       WHERE us.user_id = $1`,
      [userId],
    );

    if (result.rows.length === 0) {
      return false;
    }

    return !result.rows[0].is_free_plan;
  }

  private normalizeBranding(branding?: Record<string, unknown>) {
    const primaryColorValue = this.parseColorValue(branding?.primary_color_value);

    return {
      primary_color_value: primaryColorValue,
      font_family:
        typeof branding?.font_family === 'string' && branding.font_family.trim()
          ? branding.font_family.trim()
          : 'Roboto',
      author_name:
        typeof branding?.author_name === 'string'
          ? branding.author_name.trim()
          : '',
      logo_url:
        typeof branding?.logo_url === 'string' && branding.logo_url.trim()
          ? branding.logo_url.trim()
          : null,
    };
  }

  private parseColorValue(value: unknown) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value);
    }

    if (typeof value === 'string' && value.trim()) {
      const normalized = value.trim().toLowerCase().replace(/^#/, '');
      const radixValue = normalized.startsWith('0x')
        ? Number.parseInt(normalized.slice(2), 16)
        : Number.parseInt(normalized, 16);

      if (Number.isFinite(radixValue)) {
        return radixValue;
      }
    }

    return 0xff2196f3;
  }

  private buildPlaceholderCover(
    title: string,
    topic: string,
    branding: Record<string, unknown>,
  ) {
    const rawColor =
      typeof branding.primary_color_value === 'number'
        ? branding.primary_color_value
        : 0xff2196f3;
    const hex = rawColor.toString(16).padStart(8, '0').slice(-6);
    const svg = [
      '<svg width="1200" height="1600" xmlns="http://www.w3.org/2000/svg">',
      '<defs>',
      '<linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">',
      `<stop offset="0%" stop-color="#${hex}" />`,
      '<stop offset="100%" stop-color="#111827" />',
      '</linearGradient>',
      '</defs>',
      '<rect width="1200" height="1600" fill="url(#bg)" rx="36" />',
      '<rect x="96" y="96" width="1008" height="1408" rx="28" fill="none" stroke="rgba(255,255,255,0.22)" />',
      `<text x="120" y="250" fill="#FFFFFF" font-size="60" font-family="Arial, sans-serif">${this.escapeXml(
        this.truncate(title, 70),
      )}</text>`,
      `<text x="120" y="340" fill="#E5E7EB" font-size="30" font-family="Arial, sans-serif">${this.escapeXml(
        this.truncate(topic, 95),
      )}</text>`,
      '</svg>',
    ].join('');

    return `data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}`;
  }

  private escapeXml(value: string) {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
  }

  private parseJsonResponse(raw: string) {
    const trimmed = raw.trim();
    const fencedMatch = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i);
    const jsonText = fencedMatch ? fencedMatch[1].trim() : trimmed;

    try {
      return JSON.parse(jsonText);
    } catch (_) {
      const objectMatch = jsonText.match(/\{[\s\S]*\}/);
      if (objectMatch) {
        return JSON.parse(objectMatch[0]);
      }

      const arrayMatch = jsonText.match(/\[[\s\S]*\]/);
      if (arrayMatch) {
        return JSON.parse(arrayMatch[0]);
      }

      throw new Error('Model response did not contain valid JSON');
    }
  }

  private truncate(value: string, maxLength: number) {
    if (value.length <= maxLength) {
      return value;
    }

    return `${value.slice(0, Math.max(0, maxLength - 3)).trimEnd()}...`;
  }

  private clampChapterCount(value?: number) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 6;
    }

    const rounded = Math.round(value);
    return Math.max(3, Math.min(12, rounded));
  }
}

export const ebookGenerationService = new EbookGenerationService();
export default ebookGenerationService;
