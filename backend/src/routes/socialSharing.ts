import express, { type Response } from 'express';
import { authenticateToken, optionalAuth, type AuthRequest } from '../middleware/auth.js';
import { socialSharingService } from '../services/socialSharingService.js';

const router = express.Router();

function incrementReturnedViewCount(content: Record<string, any> | null | undefined, recorded: boolean) {
  if (!content || !recorded) return;

  const currentValue = Number(content.view_count ?? 0);
  content.view_count = Number.isFinite(currentValue) ? currentValue + 1 : 1;
}

// =====================================================
// Share Content to Social Feed
// =====================================================
router.post('/share', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { contentType, contentId, caption, isPublic } = req.body;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    if (!['notebook', 'plan', 'ebook'].includes(contentType)) {
      return res.status(400).json({ error: 'contentType must be notebook, plan, or ebook' });
    }

    const shared = await socialSharingService.shareContent({
      userId,
      contentType,
      contentId,
      caption,
      isPublic
    });

    res.json({ success: true, shared });
  } catch (error: any) {
    console.error('Share content error:', error);
    res.status(500).json({ error: error.message || 'Failed to share content' });
  }
});

// =====================================================
// Get Social Feed (Shared Content)
// =====================================================
router.get('/feed', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { limit, offset, contentType } = req.query;

    const feed = await socialSharingService.getSocialFeed(userId, {
      limit: limit ? parseInt(limit as string) : 20,
      offset: offset ? parseInt(offset as string) : 0,
      contentType: contentType as 'notebook' | 'plan' | 'ebook' | 'all' | undefined
    });

    res.json({ success: true, feed });
  } catch (error: any) {
    console.error('Get social feed error:', error);
    res.status(500).json({ error: 'Failed to get social feed' });
  }
});

// =====================================================
// Discover Public Notebooks
// =====================================================
router.get('/discover/notebooks', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { limit, offset, search, category, sortBy } = req.query;

    const notebooks = await socialSharingService.discoverNotebooks(userId, {
      limit: limit ? parseInt(limit as string) : 20,
      offset: offset ? parseInt(offset as string) : 0,
      search: search as string,
      category: category as string,
      sortBy: sortBy as 'recent' | 'popular' | 'views'
    });

    res.json({ success: true, notebooks });
  } catch (error: any) {
    console.error('Discover notebooks error:', error);
    res.status(500).json({ error: 'Failed to discover notebooks' });
  }
});

// =====================================================
// Discover Public Plans
// =====================================================
router.get('/discover/plans', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { limit, offset, search, status, sortBy } = req.query;

    const plans = await socialSharingService.discoverPlans(userId, {
      limit: limit ? parseInt(limit as string) : 20,
      offset: offset ? parseInt(offset as string) : 0,
      search: search as string,
      status: status as string,
      sortBy: sortBy as 'recent' | 'popular' | 'views'
    });

    res.json({ success: true, plans });
  } catch (error: any) {
    console.error('Discover plans error:', error);
    res.status(500).json({ error: 'Failed to discover plans' });
  }
});

// =====================================================
// Discover Public Ebooks
// =====================================================
router.get('/discover/ebooks', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { limit, offset, search, sortBy } = req.query;

    const ebooks = await socialSharingService.discoverEbooks(userId, {
      limit: limit ? parseInt(limit as string) : 20,
      offset: offset ? parseInt(offset as string) : 0,
      search: search as string,
      sortBy: sortBy as 'recent' | 'popular' | 'views'
    });

    res.json({ success: true, ebooks });
  } catch (error: any) {
    console.error('Discover ebooks error:', error);
    res.status(500).json({ error: 'Failed to discover ebooks' });
  }
});

// =====================================================
// Set Notebook Public/Private
// =====================================================
router.patch('/notebooks/:id/visibility', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const { isPublic } = req.body;

    if (typeof isPublic !== 'boolean') {
      return res.status(400).json({ error: 'isPublic must be a boolean' });
    }

    await socialSharingService.setNotebookPublic(id, userId, isPublic);
    res.json({ success: true, isPublic });
  } catch (error: any) {
    console.error('Set notebook visibility error:', error);
    res.status(500).json({ error: error.message || 'Failed to update visibility' });
  }
});

// =====================================================
// Set Notebook Lock
// =====================================================
router.patch('/notebooks/:id/lock', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const { isLocked } = req.body;

    if (typeof isLocked !== 'boolean') {
      return res.status(400).json({ error: 'isLocked must be a boolean' });
    }

    await socialSharingService.setNotebookLocked(id, userId, isLocked);
    res.json({ success: true, isLocked });
  } catch (error: any) {
    console.error('Set notebook lock error:', error);
    res.status(500).json({ error: error.message || 'Failed to update lock status' });
  }
});

// =====================================================
// Set Plan Public/Private
// =====================================================
router.patch('/plans/:id/visibility', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { id } = req.params;
    const { isPublic } = req.body;

    if (typeof isPublic !== 'boolean') {
      return res.status(400).json({ error: 'isPublic must be a boolean' });
    }

    await socialSharingService.setPlanPublic(id, userId, isPublic);
    res.json({ success: true, isPublic });
  } catch (error: any) {
    console.error('Set plan visibility error:', error);
    res.status(500).json({ error: error.message || 'Failed to update visibility' });
  }
});

// =====================================================
// Record View
// =====================================================
router.post('/view', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    const { contentType, contentId } = req.body;
    const viewerIp = req.ip;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    const recorded = await socialSharingService.recordView(contentType, contentId, userId, viewerIp);
    res.json({ success: true, recorded });
  } catch (error: any) {
    console.error('Record view error:', error);
    res.status(500).json({ error: 'Failed to record view' });
  }
});

// =====================================================
// Get View Stats
// =====================================================
router.get('/stats/:contentType/:contentId', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const { contentType, contentId } = req.params;

    const stats = await socialSharingService.getViewStats(contentType, contentId);
    res.json({ success: true, stats });
  } catch (error: any) {
    console.error('Get view stats error:', error);
    res.status(500).json({ error: 'Failed to get view stats' });
  }
});

// =====================================================
// Like Content
// =====================================================
router.post('/like', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { contentType, contentId } = req.body;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    await socialSharingService.likeContent(contentType, contentId, userId);
    res.json({ success: true });
  } catch (error: any) {
    console.error('Like content error:', error);
    res.status(500).json({ error: 'Failed to like content' });
  }
});

// =====================================================
// Unlike Content
// =====================================================
router.delete('/like', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { contentType, contentId } = req.body;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    await socialSharingService.unlikeContent(contentType, contentId, userId);
    res.json({ success: true });
  } catch (error: any) {
    console.error('Unlike content error:', error);
    res.status(500).json({ error: 'Failed to unlike content' });
  }
});

// =====================================================
// Save Content (Bookmark)
// =====================================================
router.post('/save', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { contentType, contentId } = req.body;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    await socialSharingService.saveContent(contentType, contentId, userId);
    res.json({ success: true });
  } catch (error: any) {
    console.error('Save content error:', error);
    res.status(500).json({ error: 'Failed to save content' });
  }
});

// =====================================================
// Unsave Content
// =====================================================
router.delete('/save', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { contentType, contentId } = req.body;

    if (!contentType || !contentId) {
      return res.status(400).json({ error: 'contentType and contentId are required' });
    }

    await socialSharingService.unsaveContent(contentType, contentId, userId);
    res.json({ success: true });
  } catch (error: any) {
    console.error('Unsave content error:', error);
    res.status(500).json({ error: 'Failed to unsave content' });
  }
});

// =====================================================
// Get Saved Content
// =====================================================
router.get('/saved', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const { limit, offset, contentType } = req.query;

    const saved = await socialSharingService.getSavedContent(userId, {
      limit: limit ? parseInt(limit as string) : 20,
      offset: offset ? parseInt(offset as string) : 0,
      contentType: contentType as string
    });

    res.json({ success: true, saved });
  } catch (error: any) {
    console.error('Get saved content error:', error);
    res.status(500).json({ error: 'Failed to get saved content' });
  }
});

// =====================================================
// Get User Content Stats
// =====================================================
router.get('/my-stats', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized' });

    const stats = await socialSharingService.getUserContentStats(userId);
    res.json({ success: true, stats });
  } catch (error: any) {
    console.error('Get user stats error:', error);
    res.status(500).json({ error: 'Failed to get user stats' });
  }
});

// =====================================================
// Get Public Notebook Details with Sources
// =====================================================
router.get('/public/notebooks/:id', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const viewerId = req.userId; // Optional - user may not be logged in

    const details = await socialSharingService.getPublicNotebookDetails(id, viewerId);
    
    if (!details) {
      return res.status(404).json({ error: 'Notebook not found or not public' });
    }

    const recorded = await socialSharingService.recordView('notebook', id, viewerId, req.ip);
    incrementReturnedViewCount(details.notebook, recorded);

    res.json({ success: true, ...details });
  } catch (error: any) {
    console.error('Get public notebook details error:', error);
    res.status(500).json({ error: 'Failed to get notebook details' });
  }
});

// =====================================================
// Get Public Source Details
// =====================================================
router.get('/public/sources/:id', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const viewerId = req.userId;

    const source = await socialSharingService.getPublicSourceDetails(id, viewerId);
    
    if (!source) {
      return res.status(404).json({ error: 'Source not found or not public' });
    }

    res.json({ success: true, source });
  } catch (error: any) {
    console.error('Get public source details error:', error);
    res.status(500).json({ error: 'Failed to get source details' });
  }
});

// =====================================================
// Fork Notebook (Copy to User's Account)
// =====================================================
router.post('/fork/notebook/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized - login required to fork' });

    const { id } = req.params;
    const { newTitle, includeSources } = req.body;

    const result = await socialSharingService.forkNotebook(id, userId, {
      newTitle,
      includeSources: includeSources !== false // Default to true
    });

    res.json({ 
      success: true, 
      notebook: result.notebook,
      sourcesCopied: result.sourcesCopied,
      message: `Notebook forked successfully with ${result.sourcesCopied} sources`
    });
  } catch (error: any) {
    console.error('Fork notebook error:', error);
    res.status(500).json({ error: error.message || 'Failed to fork notebook' });
  }
});

// =====================================================
// Get Public Ebook Details with Chapters
// =====================================================
router.get('/public/ebooks/:id', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const viewerId = req.userId;

    const details = await socialSharingService.getPublicEbookDetails(id, viewerId);

    if (!details) {
      return res.status(404).json({ error: 'Ebook not found or not public' });
    }

    const recorded = await socialSharingService.recordView('ebook', id, viewerId, req.ip);
    incrementReturnedViewCount(details.ebook, recorded);

    res.json({ success: true, ...details });
  } catch (error: any) {
    console.error('Get public ebook details error:', error);
    res.status(500).json({ error: 'Failed to get ebook details' });
  }
});

// =====================================================
// Fork Ebook (Copy to User's Account)
// =====================================================
router.post('/fork/ebook/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized - login required to fork' });

    const { id } = req.params;
    const { newTitle } = req.body;

    const result = await socialSharingService.forkEbook(id, userId, {
      newTitle
    });

    res.json({
      success: true,
      ebook: result.ebook,
      chapters: result.chapters,
      chaptersCopied: result.chaptersCopied,
      message: `Ebook forked successfully with ${result.chaptersCopied} chapters`
    });
  } catch (error: any) {
    console.error('Fork ebook error:', error);
    res.status(500).json({ error: error.message || 'Failed to fork ebook' });
  }
});

// =====================================================
// Get Public Plan Details with Requirements and Tasks
// =====================================================
router.get('/public/plans/:id', optionalAuth, async (req: AuthRequest, res: Response) => {
  try {
    const { id } = req.params;
    const viewerId = req.userId;

    const details = await socialSharingService.getPublicPlanDetails(id, viewerId);
    
    if (!details) {
      return res.status(404).json({ error: 'Plan not found or not public' });
    }

    const recorded = await socialSharingService.recordView('plan', id, viewerId, req.ip);
    incrementReturnedViewCount(details.plan, recorded);

    res.json({ success: true, ...details });
  } catch (error: any) {
    console.error('Get public plan details error:', error);
    res.status(500).json({ error: 'Failed to get plan details' });
  }
});

// =====================================================
// Fork Plan (Copy to User's Account)
// =====================================================
router.post('/fork/plan/:id', authenticateToken, async (req: AuthRequest, res: Response) => {
  try {
    const userId = req.userId;
    if (!userId) return res.status(401).json({ error: 'Unauthorized - login required to fork' });

    const { id } = req.params;
    const { newTitle, includeRequirements, includeTasks, includeDesignNotes } = req.body;

    const result = await socialSharingService.forkPlan(id, userId, {
      newTitle,
      includeRequirements: includeRequirements !== false,
      includeTasks: includeTasks !== false,
      includeDesignNotes: includeDesignNotes !== false
    });

    res.json({ 
      success: true, 
      plan: result.plan,
      requirementsCopied: result.requirementsCopied,
      tasksCopied: result.tasksCopied,
      designNotesCopied: result.designNotesCopied,
      message: `Plan forked successfully with ${result.requirementsCopied} requirements, ${result.tasksCopied} tasks, and ${result.designNotesCopied} design notes`
    });
  } catch (error: any) {
    console.error('Fork plan error:', error);
    res.status(500).json({ error: error.message || 'Failed to fork plan' });
  }
});

export default router;
