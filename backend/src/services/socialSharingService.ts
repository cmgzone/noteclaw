import pool from '../config/database.js';
import { v4 as uuidv4 } from 'uuid';
import { activityFeedService } from './activityFeedService.js';

export interface SharedContent {
  id: string;
  userId: string;
  contentType: 'notebook' | 'plan' | 'ebook';
  contentId: string;
  caption?: string;
  isPublic: boolean;
  viewCount: number;
  createdAt: Date;
  // Joined fields
  username?: string;
  avatarUrl?: string;
  contentTitle?: string;
  contentDescription?: string;
  likeCount?: number;
  saveCount?: number;
  userLiked?: boolean;
  userSaved?: boolean;
}

export interface DiscoverableNotebook {
  id: string;
  userId: string;
  title: string;
  description?: string;
  coverImage?: string;
  category?: string;
  sourceCount: number;
  viewCount: number;
  shareCount: number;
  isPublic: boolean;
  isLocked: boolean;
  createdAt: Date;
  username?: string;
  avatarUrl?: string;
  likeCount?: number;
  userLiked?: boolean;
}

export interface DiscoverablePlan {
  id: string;
  userId: string;
  title: string;
  description?: string;
  status: string;
  viewCount: number;
  shareCount: number;
  isPublic: boolean;
  taskCount: number;
  completionPercentage: number;
  createdAt: Date;
  username?: string;
  avatarUrl?: string;
  likeCount?: number;
  userLiked?: boolean;
}

export interface DiscoverableEbook {
  id: string;
  userId: string;
  title: string;
  topic?: string;
  targetAudience?: string;
  coverImage?: string;
  chapterCount: number;
  viewCount: number;
  shareCount: number;
  isPublic: boolean;
  createdAt: Date;
  username?: string;
  avatarUrl?: string;
  likeCount?: number;
  userLiked?: boolean;
}

export const socialSharingService = {
  // =====================================================
  // Share Content to Social Feed
  // =====================================================
  async shareContent(data: {
    userId: string;
    contentType: 'notebook' | 'plan' | 'ebook';
    contentId: string;
    caption?: string;
    isPublic?: boolean;
  }): Promise<SharedContent> {
    const { userId, contentType, contentId, caption, isPublic = true } = data;

    // Verify ownership
    const ownershipCheck = contentType === 'notebook'
      ? await pool.query(
          'SELECT id, title FROM notebooks WHERE id = $1 AND user_id = $2',
          [contentId, userId]
        )
      : contentType === 'plan'
          ? await pool.query(
              'SELECT id, title FROM plans WHERE id = $1 AND user_id = $2',
              [contentId, userId]
            )
          : await pool.query(
              `SELECT id, title
               FROM ebook_projects
               WHERE id::text = $1 AND user_id = $2 AND status = 'completed'`,
              [contentId, userId]
            );

    if (ownershipCheck.rows.length === 0) {
      throw new Error(`${contentType} not found or not owned by user`);
    }

    const contentTitle = ownershipCheck.rows[0].title;

    // Create shared content entry
    const id = uuidv4();
    const result = await pool.query(`
      INSERT INTO shared_content (id, user_id, content_type, content_id, caption, is_public)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING *
    `, [id, userId, contentType, contentId, caption, isPublic]);

    // Update share count AND set is_public on original content
    // This makes the content discoverable in the discover feed
    if (contentType === 'notebook') {
      await pool.query(
        'UPDATE notebooks SET share_count = share_count + 1, is_public = $2, updated_at = NOW() WHERE id = $1',
        [contentId, isPublic]
      );
    } else if (contentType === 'plan') {
      await pool.query(
        'UPDATE plans SET share_count = share_count + 1, is_public = $2, updated_at = NOW() WHERE id = $1',
        [contentId, isPublic]
      );
    } else {
      await pool.query(
        'UPDATE ebook_projects SET share_count = share_count + 1, is_public = $2, updated_at = NOW() WHERE id::text = $1',
        [contentId, isPublic]
      );
    }

    // Log activity
    await activityFeedService.createActivity({
      userId,
      activityType: 'content_shared',
      title: `Shared ${contentType}: ${contentTitle}`,
      description: caption,
      referenceId: result.rows[0].id,
      referenceType: 'shared_content',
      metadata: { contentType, contentId, contentTitle },
      isPublic
    });

    return result.rows[0];
  },

  // =====================================================
  // Get Social Feed (Shared Content)
  // =====================================================
  async getSocialFeed(userId: string, options: {
    limit?: number;
    offset?: number;
    contentType?: 'notebook' | 'plan' | 'ebook' | 'all';
  } = {}): Promise<SharedContent[]> {
    const { limit = 20, offset = 0, contentType = 'all' } = options;

    const result = await pool.query(`
      SELECT 
        sc.*,
        u.display_name as username,
        u.avatar_url,
        CASE 
          WHEN sc.content_type = 'notebook' THEN (SELECT title FROM notebooks WHERE id = sc.content_id::text)
          WHEN sc.content_type = 'plan' THEN (SELECT title FROM plans WHERE id = sc.content_id)
          WHEN sc.content_type = 'ebook' THEN (SELECT title FROM ebook_projects WHERE id::text = sc.content_id::text)
        END as content_title,
        CASE 
          WHEN sc.content_type = 'notebook' THEN (SELECT description FROM notebooks WHERE id = sc.content_id::text)
          WHEN sc.content_type = 'plan' THEN (SELECT description FROM plans WHERE id = sc.content_id)
          WHEN sc.content_type = 'ebook' THEN (SELECT topic FROM ebook_projects WHERE id::text = sc.content_id::text)
        END as content_description,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'shared_content' AND content_id = sc.id) as like_count,
        (SELECT COUNT(*) FROM content_saves WHERE content_type = 'shared_content' AND content_id = sc.id) as save_count,
        EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'shared_content' AND content_id = sc.id AND user_id = $1) as user_liked,
        EXISTS(SELECT 1 FROM content_saves WHERE content_type = 'shared_content' AND content_id = sc.id AND user_id = $1) as user_saved
      FROM shared_content sc
      JOIN users u ON u.id = sc.user_id
      WHERE sc.is_public = true
        ${contentType !== 'all' ? 'AND sc.content_type = $4' : ''}
      ORDER BY sc.created_at DESC
      LIMIT $2 OFFSET $3
    `, contentType !== 'all'
      ? [userId, limit, offset, contentType]
      : [userId, limit, offset]
    );

    return result.rows;
  },

  // =====================================================
  // Discover Public Notebooks
  // =====================================================
  async discoverNotebooks(userId: string, options: {
    limit?: number;
    offset?: number;
    search?: string;
    category?: string;
    sortBy?: 'recent' | 'popular' | 'views';
  } = {}): Promise<DiscoverableNotebook[]> {
    const { limit = 20, offset = 0, search, category, sortBy = 'recent' } = options;

    let orderBy = 'n.created_at DESC';
    if (sortBy === 'popular') orderBy = 'like_count DESC, n.view_count DESC';
    if (sortBy === 'views') orderBy = 'n.view_count DESC';

    const params: any[] = [userId, limit, offset];
    let paramIndex = 4;
    let whereClause = 'WHERE n.is_public = true AND n.is_locked = false';

    if (search) {
      whereClause += ` AND (n.title ILIKE $${paramIndex} OR n.description ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    if (category) {
      whereClause += ` AND n.category = $${paramIndex}`;
      params.push(category);
      paramIndex++;
    }

    const result = await pool.query(`
      SELECT 
        n.*,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'notebook' AND content_id::text = n.id) as like_count,
        EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'notebook' AND content_id::text = n.id AND user_id = $1) as user_liked
      FROM notebooks n
      JOIN users u ON u.id = n.user_id
      ${whereClause}
      ORDER BY ${orderBy}
      LIMIT $2 OFFSET $3
    `, params);

    return result.rows;
  },

  // =====================================================
  // Discover Public Plans
  // =====================================================
  async discoverPlans(userId: string, options: {
    limit?: number;
    offset?: number;
    search?: string;
    status?: string;
    sortBy?: 'recent' | 'popular' | 'views';
  } = {}): Promise<DiscoverablePlan[]> {
    const { limit = 20, offset = 0, search, status, sortBy = 'recent' } = options;

    let orderBy = 'p.created_at DESC';
    if (sortBy === 'popular') orderBy = 'like_count DESC, p.view_count DESC';
    if (sortBy === 'views') orderBy = 'p.view_count DESC';

    const params: any[] = [userId, limit, offset];
    let paramIndex = 4;
    let whereClause = 'WHERE p.is_public = true';

    if (search) {
      whereClause += ` AND (p.title ILIKE $${paramIndex} OR p.description ILIKE $${paramIndex})`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    if (status) {
      whereClause += ` AND p.status = $${paramIndex}`;
      params.push(status);
      paramIndex++;
    }

    const result = await pool.query(`
      SELECT 
        p.id, p.user_id, p.title, p.description, p.status, 
        p.view_count, p.share_count, p.is_public, p.created_at,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM plan_tasks WHERE plan_id = p.id) as task_count,
        (SELECT COALESCE(
          ROUND(COUNT(*) FILTER (WHERE status = 'completed')::numeric / NULLIF(COUNT(*), 0) * 100),
          0
        ) FROM plan_tasks WHERE plan_id = p.id) as completion_percentage,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'plan' AND content_id = p.id) as like_count,
        EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'plan' AND content_id = p.id AND user_id = $1) as user_liked
      FROM plans p
      JOIN users u ON u.id = p.user_id
      ${whereClause}
      ORDER BY ${orderBy}
      LIMIT $2 OFFSET $3
    `, params);

    return result.rows;
  },

  // =====================================================
  // Discover Public Ebooks
  // =====================================================
  async discoverEbooks(userId: string, options: {
    limit?: number;
    offset?: number;
    search?: string;
    sortBy?: 'recent' | 'popular' | 'views';
  } = {}): Promise<DiscoverableEbook[]> {
    const { limit = 20, offset = 0, search, sortBy = 'recent' } = options;

    let orderBy = 'ep.created_at DESC';
    if (sortBy === 'popular') orderBy = 'like_count DESC, ep.view_count DESC';
    if (sortBy === 'views') orderBy = 'ep.view_count DESC';

    const params: any[] = [userId, limit, offset];
    let paramIndex = 4;
    let whereClause = `WHERE ep.is_public = true AND ep.status = 'completed'`;

    if (search) {
      whereClause += ` AND (
        ep.title ILIKE $${paramIndex}
        OR ep.topic ILIKE $${paramIndex}
        OR ep.target_audience ILIKE $${paramIndex}
      )`;
      params.push(`%${search}%`);
      paramIndex++;
    }

    const result = await pool.query(`
      SELECT
        ep.id,
        ep.user_id,
        ep.title,
        ep.topic,
        ep.target_audience,
        ep.cover_image,
        ep.view_count,
        ep.share_count,
        ep.is_public,
        ep.created_at,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM ebook_chapters WHERE project_id::text = ep.id::text) as chapter_count,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'ebook' AND content_id::text = ep.id::text) as like_count,
        EXISTS(
          SELECT 1
          FROM content_likes
          WHERE content_type = 'ebook'
            AND content_id::text = ep.id::text
            AND user_id = $1
        ) as user_liked
      FROM ebook_projects ep
      JOIN users u ON u.id = ep.user_id
      ${whereClause}
      ORDER BY ${orderBy}
      LIMIT $2 OFFSET $3
    `, params);

    return result.rows;
  },

  // =====================================================
  // Toggle Notebook Public/Private
  // =====================================================
  async setNotebookPublic(notebookId: string, userId: string, isPublic: boolean): Promise<void> {
    const result = await pool.query(
      'UPDATE notebooks SET is_public = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3 RETURNING id',
      [isPublic, notebookId, userId]
    );
    if (result.rows.length === 0) {
      throw new Error('Notebook not found or not owned by user');
    }
  },

  // =====================================================
  // Toggle Notebook Lock
  // =====================================================
  async setNotebookLocked(notebookId: string, userId: string, isLocked: boolean): Promise<void> {
    const result = await pool.query(
      'UPDATE notebooks SET is_locked = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3 RETURNING id',
      [isLocked, notebookId, userId]
    );
    if (result.rows.length === 0) {
      throw new Error('Notebook not found or not owned by user');
    }
  },

  // =====================================================
  // Toggle Plan Public/Private
  // =====================================================
  async setPlanPublic(planId: string, userId: string, isPublic: boolean): Promise<void> {
    const result = await pool.query(
      'UPDATE plans SET is_public = $1, updated_at = NOW() WHERE id = $2 AND user_id = $3 RETURNING id',
      [isPublic, planId, userId]
    );
    if (result.rows.length === 0) {
      throw new Error('Plan not found or not owned by user');
    }
  },

  // =====================================================
  // Record View
  // =====================================================
  async recordView(contentType: string, contentId: string, viewerId?: string, viewerIp?: string): Promise<boolean> {
    const normalizedViewerId = typeof viewerId === 'string' && viewerId.trim().length > 0
      ? viewerId.trim()
      : null;

    let inserted = false;

    if (normalizedViewerId) {
      const insertResult = await pool.query(`
        INSERT INTO content_views (content_type, content_id, viewer_id, viewer_ip)
        VALUES ($1, $2::uuid, $3, $4)
        ON CONFLICT DO NOTHING
        RETURNING id
      `, [contentType, contentId, normalizedViewerId, viewerIp ?? null]);

      inserted = insertResult.rows.length > 0;
    } else {
      const insertResult = await pool.query(`
        INSERT INTO content_views (content_type, content_id, viewer_id, viewer_ip)
        VALUES ($1, $2::uuid, NULL, $3)
        RETURNING id
      `, [contentType, contentId, viewerIp ?? null]);

      inserted = insertResult.rows.length > 0;
    }

    if (!inserted) {
      return false;
    }

    if (contentType === 'notebook') {
      await pool.query(
        'UPDATE notebooks SET view_count = view_count + 1 WHERE id = $1::uuid',
        [contentId]
      );
    } else if (contentType === 'plan') {
      await pool.query(
        'UPDATE plans SET view_count = view_count + 1 WHERE id = $1::uuid',
        [contentId]
      );
    } else if (contentType === 'ebook') {
      await pool.query(
        'UPDATE ebook_projects SET view_count = view_count + 1 WHERE id = $1::uuid',
        [contentId]
      );
    } else if (contentType === 'shared_content') {
      await pool.query(
        'UPDATE shared_content SET view_count = view_count + 1 WHERE id = $1::uuid',
        [contentId]
      );
    } else {
      throw new Error(`Unsupported content type for view tracking: ${contentType}`);
    }

    return true;
  },

  // =====================================================
  // Get View Stats
  // =====================================================
  async getViewStats(contentType: string, contentId: string): Promise<{
    totalViews: number;
    uniqueViewers: number;
    recentViews: number;
  }> {
    const result = await pool.query(`
      SELECT 
        COUNT(*) as total_views,
        COUNT(DISTINCT viewer_id) as unique_viewers,
        COUNT(*) FILTER (WHERE viewed_at > NOW() - INTERVAL '7 days') as recent_views
      FROM content_views
      WHERE content_type = $1 AND content_id = $2
    `, [contentType, contentId]);

    return {
      totalViews: parseInt(result.rows[0]?.total_views) || 0,
      uniqueViewers: parseInt(result.rows[0]?.unique_viewers) || 0,
      recentViews: parseInt(result.rows[0]?.recent_views) || 0
    };
  },

  // =====================================================
  // Like Content
  // =====================================================
  async likeContent(contentType: string, contentId: string, userId: string): Promise<void> {
    const id = uuidv4();
    await pool.query(`
      INSERT INTO content_likes (id, content_type, content_id, user_id)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (content_type, content_id, user_id) DO NOTHING
    `, [id, contentType, contentId, userId]);
  },

  // =====================================================
  // Unlike Content
  // =====================================================
  async unlikeContent(contentType: string, contentId: string, userId: string): Promise<void> {
    await pool.query(
      'DELETE FROM content_likes WHERE content_type = $1 AND content_id = $2 AND user_id = $3',
      [contentType, contentId, userId]
    );
  },

  // =====================================================
  // Save Content (Bookmark)
  // =====================================================
  async saveContent(contentType: string, contentId: string, userId: string): Promise<void> {
    const id = uuidv4();
    await pool.query(`
      INSERT INTO content_saves (id, content_type, content_id, user_id)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (content_type, content_id, user_id) DO NOTHING
    `, [id, contentType, contentId, userId]);
  },

  // =====================================================
  // Unsave Content
  // =====================================================
  async unsaveContent(contentType: string, contentId: string, userId: string): Promise<void> {
    await pool.query(
      'DELETE FROM content_saves WHERE content_type = $1 AND content_id = $2 AND user_id = $3',
      [contentType, contentId, userId]
    );
  },

  // =====================================================
  // Get User's Saved Content
  // =====================================================
  async getSavedContent(userId: string, options: {
    limit?: number;
    offset?: number;
    contentType?: string;
  } = {}): Promise<any[]> {
    const { limit = 20, offset = 0, contentType } = options;

    const result = await pool.query(`
      SELECT 
        cs.*,
        CASE 
          WHEN cs.content_type = 'notebook' THEN (SELECT title FROM notebooks WHERE id = cs.content_id::text)
          WHEN cs.content_type = 'plan' THEN (SELECT title FROM plans WHERE id = cs.content_id)
          WHEN cs.content_type = 'ebook' THEN (SELECT title FROM ebook_projects WHERE id::text = cs.content_id::text)
          WHEN cs.content_type = 'shared_content' THEN (SELECT caption FROM shared_content WHERE id = cs.content_id)
        END as content_title,
        CASE 
          WHEN cs.content_type = 'notebook' THEN (SELECT user_id FROM notebooks WHERE id = cs.content_id::text)
          WHEN cs.content_type = 'plan' THEN (SELECT user_id FROM plans WHERE id = cs.content_id)
          WHEN cs.content_type = 'ebook' THEN (SELECT user_id FROM ebook_projects WHERE id::text = cs.content_id::text)
          WHEN cs.content_type = 'shared_content' THEN (SELECT user_id FROM shared_content WHERE id = cs.content_id)
        END as owner_id
      FROM content_saves cs
      WHERE cs.user_id = $1
        ${contentType ? 'AND cs.content_type = $4' : ''}
      ORDER BY cs.created_at DESC
      LIMIT $2 OFFSET $3
    `, contentType ? [userId, limit, offset, contentType] : [userId, limit, offset]);

    return result.rows;
  },

  // =====================================================
  // Get User's Own Content Stats
  // =====================================================
  async getUserContentStats(userId: string): Promise<{
    totalNotebooks: number;
    publicNotebooks: number;
    totalPlans: number;
    publicPlans: number;
    totalViews: number;
    totalLikes: number;
    totalShares: number;
  }> {
    const result = await pool.query(`
      SELECT 
        (SELECT COUNT(*) FROM notebooks WHERE user_id = $1) as total_notebooks,
        (SELECT COUNT(*) FROM notebooks WHERE user_id = $1 AND is_public = true) as public_notebooks,
        (SELECT COUNT(*) FROM plans WHERE user_id = $1) as total_plans,
        (SELECT COUNT(*) FROM plans WHERE user_id = $1 AND is_public = true) as public_plans,
        (SELECT COALESCE(SUM(view_count), 0) FROM notebooks WHERE user_id = $1) +
        (SELECT COALESCE(SUM(view_count), 0) FROM plans WHERE user_id = $1) +
        (SELECT COALESCE(SUM(view_count), 0) FROM ebook_projects WHERE user_id = $1) as total_views,
        (SELECT COUNT(*) FROM content_likes cl 
         JOIN notebooks n ON cl.content_id::text = n.id AND cl.content_type = 'notebook' 
         WHERE n.user_id = $1) +
        (SELECT COUNT(*) FROM content_likes cl 
         JOIN plans p ON cl.content_id = p.id AND cl.content_type = 'plan' 
         WHERE p.user_id = $1) +
        (SELECT COUNT(*) FROM content_likes cl 
         JOIN ebook_projects ep ON cl.content_id::text = ep.id::text AND cl.content_type = 'ebook' 
         WHERE ep.user_id = $1) as total_likes,
        (SELECT COALESCE(SUM(share_count), 0) FROM notebooks WHERE user_id = $1) +
        (SELECT COALESCE(SUM(share_count), 0) FROM plans WHERE user_id = $1) +
        (SELECT COALESCE(SUM(share_count), 0) FROM ebook_projects WHERE user_id = $1) as total_shares
    `, [userId]);

    const row = result.rows[0];
    return {
      totalNotebooks: parseInt(row?.total_notebooks) || 0,
      publicNotebooks: parseInt(row?.public_notebooks) || 0,
      totalPlans: parseInt(row?.total_plans) || 0,
      publicPlans: parseInt(row?.public_plans) || 0,
      totalViews: parseInt(row?.total_views) || 0,
      totalLikes: parseInt(row?.total_likes) || 0,
      totalShares: parseInt(row?.total_shares) || 0
    };
  },

  // =====================================================
  // Get Public Notebook Details with Sources
  // =====================================================
  async getPublicNotebookDetails(notebookId: string, viewerId?: string): Promise<{
    notebook: any;
    sources: any[];
    owner: any;
  } | null> {
    // Get notebook details
    const notebookResult = await pool.query(`
      SELECT 
        n.*,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM sources WHERE notebook_id = n.id) as source_count,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'notebook' AND content_id::text = n.id) as like_count,
        ${viewerId ? `EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'notebook' AND content_id::text = n.id AND user_id = $2) as user_liked` : 'false as user_liked'}
      FROM notebooks n
      JOIN users u ON u.id = n.user_id
      WHERE n.id = $1 AND n.is_public = true AND n.is_locked = false
    `, viewerId ? [notebookId, viewerId] : [notebookId]);

    if (notebookResult.rows.length === 0) {
      return null;
    }

    const notebook = notebookResult.rows[0];

    // Get sources (without full content for privacy, just metadata)
    const sourcesResult = await pool.query(`
      SELECT 
        id, notebook_id, title, type, created_at, 
        CASE 
          WHEN type = 'text' THEN LEFT(content, 500) || CASE WHEN LENGTH(content) > 500 THEN '...' ELSE '' END
          ELSE NULL 
        END as content_preview,
        summary,
        metadata
      FROM sources
      WHERE notebook_id = $1
      ORDER BY created_at DESC
    `, [notebookId]);

    return {
      notebook,
      sources: sourcesResult.rows,
      owner: {
        id: notebook.user_id,
        username: notebook.username,
        avatarUrl: notebook.avatar_url
      }
    };
  },

  // =====================================================
  // Get Public Source Details
  // =====================================================
  async getPublicSourceDetails(sourceId: string, viewerId?: string): Promise<any | null> {
    const result = await pool.query(`
      SELECT 
        s.*,
        n.title as notebook_title,
        n.is_public as notebook_is_public,
        n.is_locked as notebook_is_locked,
        u.display_name as owner_username,
        u.avatar_url as owner_avatar
      FROM sources s
      JOIN notebooks n ON n.id = s.notebook_id
      JOIN users u ON u.id = n.user_id
      WHERE s.id = $1 AND n.is_public = true AND n.is_locked = false
    `, [sourceId]);

    if (result.rows.length === 0) {
      return null;
    }

    return result.rows[0];
  },

  // =====================================================
  // Get Public Ebook Details with Chapters
  // =====================================================
  async getPublicEbookDetails(ebookId: string, viewerId?: string): Promise<{
    ebook: any;
    chapters: any[];
    owner: any;
  } | null> {
    const ebookResult = await pool.query(`
      SELECT 
        ep.*,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM ebook_chapters WHERE project_id = ep.id) as chapter_count,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'ebook' AND content_id::text = ep.id::text) as like_count,
        ${viewerId ? `EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'ebook' AND content_id::text = ep.id::text AND user_id = $2) as user_liked` : 'false as user_liked'}
      FROM ebook_projects ep
      JOIN users u ON u.id = ep.user_id
      WHERE ep.id::text = $1 AND ep.is_public = true AND ep.status = 'completed'
    `, viewerId ? [ebookId, viewerId] : [ebookId]);

    if (ebookResult.rows.length === 0) {
      return null;
    }

    const ebook = ebookResult.rows[0];

    const chaptersResult = await pool.query(`
      SELECT id, project_id, title, content, chapter_order, status, created_at, updated_at
      FROM ebook_chapters
      WHERE project_id::text = $1
      ORDER BY chapter_order ASC
    `, [ebookId]);

    return {
      ebook,
      chapters: chaptersResult.rows,
      owner: {
        id: ebook.user_id,
        username: ebook.username,
        avatarUrl: ebook.avatar_url
      }
    };
  },

  // =====================================================
  // Fork Notebook (Copy to User's Account)
  // =====================================================
  async forkNotebook(notebookId: string, userId: string, options: {
    newTitle?: string;
    includeSources?: boolean;
  } = {}): Promise<{ notebook: any; sourcesCopied: number }> {
    const { newTitle, includeSources = true } = options;

    // Get original notebook
    const originalResult = await pool.query(`
      SELECT n.*, u.display_name as original_owner
      FROM notebooks n
      JOIN users u ON u.id = n.user_id
      WHERE n.id = $1 AND n.is_public = true AND n.is_locked = false
    `, [notebookId]);

    if (originalResult.rows.length === 0) {
      throw new Error('Notebook not found or not available for forking');
    }

    const original = originalResult.rows[0];

    // Create new notebook
    const title = newTitle || `${original.title} (Fork)`;
    const description = `Forked from ${original.original_owner}'s notebook: ${original.title}`;

    const newNotebookId = uuidv4();
    const newNotebookResult = await pool.query(`
      INSERT INTO notebooks (id, user_id, title, description, category, is_public)
      VALUES ($1, $2, $3, $4, $5, false)
      RETURNING *
    `, [
      newNotebookId,
      userId,
      title,
      description,
      original.category
    ]);

    const newNotebook = newNotebookResult.rows[0];
    let sourcesCopied = 0;

    // Copy sources if requested
    if (includeSources) {
      const sourcesResult = await pool.query(`
        SELECT * FROM sources WHERE notebook_id = $1
      `, [notebookId]);

      for (const source of sourcesResult.rows) {
        // Handle metadata - it might be null, a string, or an object
        let sourceMetadata = {};
        if (source.metadata) {
          if (typeof source.metadata === 'string') {
            try {
              sourceMetadata = JSON.parse(source.metadata);
            } catch {
              sourceMetadata = {};
            }
          } else if (typeof source.metadata === 'object') {
            sourceMetadata = source.metadata;
          }
        }

        const newSourceId = uuidv4();
        await pool.query(`
          INSERT INTO sources (id, notebook_id, title, type, content, summary, url, metadata, user_id)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
        `, [
          newSourceId,
          newNotebook.id,
          source.title,
          source.type,
          source.content,
          source.summary,
          source.url,
          JSON.stringify({
            ...sourceMetadata,
            forkedFrom: source.id,
            originalNotebookId: notebookId
          }),
          userId
        ]);
        sourcesCopied++;
      }
    }

    // Log activity
    await activityFeedService.createActivity({
      userId,
      activityType: 'notebook_forked',
      title: `Forked notebook: ${original.title}`,
      description: `Created "${title}" from ${original.original_owner}'s notebook`,
      referenceId: newNotebook.id,
      referenceType: 'notebook',
      metadata: {
        originalNotebookId: notebookId,
        originalOwner: original.user_id,
        sourcesCopied
      },
      isPublic: false
    });

    return { notebook: newNotebook, sourcesCopied };
  },

  // =====================================================
  // Fork Ebook (Copy to User's Account)
  // =====================================================
  async forkEbook(ebookId: string, userId: string, options: {
    newTitle?: string;
  } = {}): Promise<{ ebook: any; chaptersCopied: number; chapters: any[] }> {
    const { newTitle } = options;

    const originalResult = await pool.query(`
      SELECT ep.*, u.display_name as original_owner
      FROM ebook_projects ep
      JOIN users u ON u.id = ep.user_id
      WHERE ep.id::text = $1 AND ep.is_public = true AND ep.status = 'completed'
    `, [ebookId]);

    if (originalResult.rows.length === 0) {
      throw new Error('Ebook not found or not available for forking');
    }

    const original = originalResult.rows[0];
    const title = newTitle || `${original.title} (Fork)`;

    const newEbookId = uuidv4();
    const newEbookResult = await pool.query(`
      INSERT INTO ebook_projects (
        id, user_id, notebook_id, title, topic, target_audience, branding,
        selected_model, status, cover_image, is_public
      )
      VALUES ($1, $2, NULL, $3, $4, $5, $6, $7, 'completed', $8, false)
      RETURNING *
    `, [
      newEbookId,
      userId,
      title,
      original.topic,
      original.target_audience,
      original.branding
        ? (typeof original.branding === 'string'
            ? original.branding
            : JSON.stringify(original.branding))
        : null,
      original.selected_model,
      original.cover_image
    ]);

    const chaptersResult = await pool.query(`
      SELECT * FROM ebook_chapters
      WHERE project_id::text = $1
      ORDER BY chapter_order ASC
    `, [ebookId]);

    const copiedChapters: any[] = [];
    for (const chapter of chaptersResult.rows) {
      const newChapterId = uuidv4();
      const insertedChapter = await pool.query(`
        INSERT INTO ebook_chapters (id, project_id, title, content, chapter_order, status)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING *
      `, [
        newChapterId,
        newEbookId,
        chapter.title,
        chapter.content,
        chapter.chapter_order,
        chapter.status || 'completed'
      ]);
      copiedChapters.push(insertedChapter.rows[0]);
    }

    await activityFeedService.createActivity({
      userId,
      activityType: 'ebook_created',
      title: `Forked ebook: ${original.title}`,
      description: `Created "${title}" from ${original.original_owner}'s ebook`,
      referenceId: newEbookId,
      referenceType: 'ebook',
      metadata: {
        originalEbookId: ebookId,
        originalOwner: original.user_id,
        chaptersCopied: copiedChapters.length
      },
      isPublic: false
    });

    return {
      ebook: newEbookResult.rows[0],
      chaptersCopied: copiedChapters.length,
      chapters: copiedChapters
    };
  },

  // =====================================================
  // Get Public Plan Details with Requirements and Tasks
  // =====================================================
  async getPublicPlanDetails(planId: string, viewerId?: string): Promise<{
    plan: any;
    requirements: any[];
    tasks: any[];
    designNotes: any[];
    owner: any;
  } | null> {
    // Get plan details
    const planResult = await pool.query(`
      SELECT 
        p.*,
        u.display_name as username,
        u.avatar_url,
        (SELECT COUNT(*) FROM plan_tasks WHERE plan_id = p.id) as task_count,
        (SELECT COUNT(*) FROM plan_tasks WHERE plan_id = p.id AND status = 'completed') as completed_task_count,
        (SELECT COUNT(*) FROM plan_requirements WHERE plan_id = p.id) as requirement_count,
        (SELECT COUNT(*) FROM content_likes WHERE content_type = 'plan' AND content_id = p.id) as like_count,
        ${viewerId ? `EXISTS(SELECT 1 FROM content_likes WHERE content_type = 'plan' AND content_id = p.id AND user_id = $2) as user_liked` : 'false as user_liked'}
      FROM plans p
      JOIN users u ON u.id = p.user_id
      WHERE p.id = $1 AND p.is_public = true
    `, viewerId ? [planId, viewerId] : [planId]);

    if (planResult.rows.length === 0) {
      return null;
    }

    const plan = planResult.rows[0];

    // Get requirements
    const requirementsResult = await pool.query(`
      SELECT id, plan_id, title, description, ears_pattern, acceptance_criteria, created_at
      FROM plan_requirements
      WHERE plan_id = $1
      ORDER BY created_at ASC
    `, [planId]);

    // Get tasks (hierarchical)
    const tasksResult = await pool.query(`
      SELECT id, plan_id, parent_task_id, title, description, status, priority, created_at
      FROM plan_tasks
      WHERE plan_id = $1
      ORDER BY created_at ASC
    `, [planId]);

    // Get design notes (without sensitive implementation details)
    const designNotesResult = await pool.query(`
      SELECT id, plan_id, content, requirement_ids, created_at
      FROM plan_design_notes
      WHERE plan_id = $1
      ORDER BY created_at ASC
    `, [planId]);

    return {
      plan,
      requirements: requirementsResult.rows,
      tasks: tasksResult.rows,
      designNotes: designNotesResult.rows,
      owner: {
        id: plan.user_id,
        username: plan.username,
        avatarUrl: plan.avatar_url
      }
    };
  },

  // =====================================================
  // Fork Plan (Copy to User's Account)
  // =====================================================
  async forkPlan(planId: string, userId: string, options: {
    newTitle?: string;
    includeRequirements?: boolean;
    includeTasks?: boolean;
    includeDesignNotes?: boolean;
  } = {}): Promise<{
    plan: any;
    requirementsCopied: number;
    tasksCopied: number;
    designNotesCopied: number;
  }> {
    const {
      newTitle,
      includeRequirements = true,
      includeTasks = true,
      includeDesignNotes = true
    } = options;

    // Get original plan
    const originalResult = await pool.query(`
      SELECT p.*, u.display_name as original_owner
      FROM plans p
      JOIN users u ON u.id = p.user_id
      WHERE p.id = $1 AND p.is_public = true
    `, [planId]);

    if (originalResult.rows.length === 0) {
      throw new Error('Plan not found or not available for forking');
    }

    const original = originalResult.rows[0];

    // Create new plan
    const title = newTitle || `${original.title} (Fork)`;
    const description = `Forked from ${original.original_owner}'s plan: ${original.title}\n\n${original.description || ''}`;

    const newPlanId = uuidv4();
    const newPlanResult = await pool.query(`
      INSERT INTO plans (id, user_id, title, description, status, is_public, metadata)
      VALUES ($1, $2, $3, $4, 'draft', false, $5)
      RETURNING *
    `, [
      newPlanId,
      userId,
      title,
      description,
      JSON.stringify({
        forkedFrom: planId,
        originalOwner: original.user_id,
        originalTitle: original.title,
        forkedAt: new Date().toISOString()
      })
    ]);

    const newPlan = newPlanResult.rows[0];
    let requirementsCopied = 0;
    let tasksCopied = 0;
    let designNotesCopied = 0;

    // Map old requirement IDs to new ones for design notes
    const requirementIdMap: Record<string, string> = {};

    // Copy requirements if requested
    if (includeRequirements) {
      const requirementsResult = await pool.query(`
        SELECT * FROM plan_requirements WHERE plan_id = $1
      `, [planId]);

      for (const req of requirementsResult.rows) {
        let acceptanceCriteria = req.acceptance_criteria;

        // Handle potential malformed JSON in database
        if (typeof acceptanceCriteria === 'string') {
          try {
            acceptanceCriteria = JSON.parse(acceptanceCriteria);
          } catch (e) {
            console.warn('Failed to parse (or re-parse) acceptance_criteria during fork:', e);
            acceptanceCriteria = [];
          }
        }

        // Ensure it's a valid object/array (postgres pg-node usually returns object for jsonb)
        if (!acceptanceCriteria) {
          acceptanceCriteria = [];
        }

        const newReqId = uuidv4();
        const newReqResult = await pool.query(`
          INSERT INTO plan_requirements (id, plan_id, title, description, ears_pattern, acceptance_criteria)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id
        `, [
          newReqId,
          newPlan.id,
          req.title,
          req.description,
          req.ears_pattern,
          JSON.stringify(acceptanceCriteria) // Explicitly stringify to ensure valid JSON string is passed
        ]);
        requirementIdMap[req.id] = newReqResult.rows[0].id;
        requirementsCopied++;
      }
    }

    // Map old task IDs to new ones for parent references
    const taskIdMap: Record<string, string> = {};

    // Copy tasks if requested (need to handle parent-child relationships)
    if (includeTasks) {
      const tasksResult = await pool.query(`
        SELECT * FROM plan_tasks WHERE plan_id = $1 ORDER BY created_at ASC
      `, [planId]);

      // First pass: create all tasks without parent references
      for (const task of tasksResult.rows) {
        const newTaskId = uuidv4();
        const newTaskResult = await pool.query(`
          INSERT INTO plan_tasks (id, plan_id, title, description, status, priority)
          VALUES ($1, $2, $3, $4, 'not_started', $5)
          RETURNING id
        `, [
          newTaskId,
          newPlan.id,
          task.title,
          task.description,
          task.priority
        ]);
        taskIdMap[task.id] = newTaskResult.rows[0].id;
        tasksCopied++;
      }

      // Second pass: update parent references
      for (const task of tasksResult.rows) {
        if (task.parent_task_id && taskIdMap[task.parent_task_id]) {
          await pool.query(`
            UPDATE plan_tasks SET parent_task_id = $1 WHERE id = $2
          `, [taskIdMap[task.parent_task_id], taskIdMap[task.id]]);
        }
      }
    }

    // Copy design notes if requested
    if (includeDesignNotes) {
      const designNotesResult = await pool.query(`
        SELECT * FROM plan_design_notes WHERE plan_id = $1
      `, [planId]);

      for (const note of designNotesResult.rows) {
        // Map old requirement IDs to new ones
        let newRequirementIds: string[] = [];
        if (note.requirement_ids && Array.isArray(note.requirement_ids)) {
          newRequirementIds = note.requirement_ids
            .map((oldId: string) => requirementIdMap[oldId])
            .filter((id: string | undefined) => id !== undefined);
        }

        // Format as PostgreSQL array literal for UUID[] column
        const pgArrayLiteral = newRequirementIds.length > 0
          ? `{${newRequirementIds.join(',')}}`
          : '{}';

        const newNoteId = uuidv4();
        await pool.query(`
          INSERT INTO plan_design_notes (id, plan_id, content, requirement_ids)
          VALUES ($1, $2, $3, $4::uuid[])
        `, [
          newNoteId,
          newPlan.id,
          note.content,
          pgArrayLiteral
        ]);
        designNotesCopied++;
      }
    }

    // Log activity
    await activityFeedService.createActivity({
      userId,
      activityType: 'plan_forked',
      title: `Forked plan: ${original.title}`,
      description: `Created "${title}" from ${original.original_owner}'s plan`,
      referenceId: newPlan.id,
      referenceType: 'plan',
      metadata: {
        originalPlanId: planId,
        originalOwner: original.user_id,
        requirementsCopied,
        tasksCopied,
        designNotesCopied
      },
      isPublic: false
    });

    return { plan: newPlan, requirementsCopied, tasksCopied, designNotesCopied };
  }
};
