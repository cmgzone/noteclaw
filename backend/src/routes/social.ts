import { Router, type Response } from 'express';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { friendService, NotFoundError, ConflictError, ValidationError } from '../services/friendService.js';
import { UnauthorizedError, ForbiddenError } from '../types/errors.js';
import { studyGroupService } from '../services/studyGroupService.js';
import { activityFeedService } from '../services/activityFeedService.js';
import { leaderboardService } from '../services/leaderboardService.js';

const router = Router();

// All routes require authentication
router.use(authenticateToken);

// Helper to handle errors consistently
const handleError = (error: any, res: Response) => {
  console.error('Social API error:', error.message);
  
  if (error instanceof ValidationError) {
    return res.status(400).json({ error: error.message, code: error.code });
  }
  if (error instanceof NotFoundError) {
    return res.status(404).json({ error: error.message, code: error.code });
  }
  if (error instanceof ConflictError) {
    return res.status(409).json({ error: error.message, code: error.code });
  }
  if (error instanceof UnauthorizedError || error instanceof ForbiddenError) {
    return res.status(error.status).json({ error: error.message, code: error.code });
  }
  if (typeof error?.status === 'number') {
    return res.status(error.status).json({ error: error.message, code: error.code || 'ERROR' });
  }
  
  // Don't expose internal errors
  res.status(500).json({ error: 'An error occurred', code: 'INTERNAL_ERROR' });
};

// Validation helpers
const isValidUUID = (id: string): boolean => {
  if (!id || typeof id !== 'string') return false;
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  return uuidRegex.test(id);
};

const validateUserId = (req: AuthRequest, res: Response): string | null => {
  const userId = req.userId;
  if (!userId) {
    res.status(401).json({ error: 'Unauthorized', code: 'UNAUTHORIZED' });
    return null;
  }
  return userId;
};

// ============================================
// FRIENDS
// ============================================

// Search users
router.get('/users/search', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { q, limit } = req.query;
    if (!q || typeof q !== 'string') {
      return res.status(400).json({ error: 'Search query required', code: 'VALIDATION_ERROR' });
    }
    if (q.length < 2) {
      return res.status(400).json({ error: 'Search query must be at least 2 characters', code: 'VALIDATION_ERROR' });
    }
    
    const safeLimit = limit ? Math.min(parseInt(limit as string) || 20, 50) : 20;
    const users = await friendService.searchUsers(q, userId, safeLimit);
    res.json({ users });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Get friends list with pagination
router.get('/friends', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    console.log('[Social] Getting friends for user:', userId);
    const { limit, offset } = req.query;
    const friends = await friendService.getFriends(userId, {
      limit: limit ? Math.min(parseInt(limit as string) || 50, 100) : 50,
      offset: offset ? parseInt(offset as string) || 0 : 0
    });
    console.log('[Social] Found', friends.length, 'friends');
    res.json({ friends });
  } catch (error: any) {
    console.error('[Social] Error getting friends:', error.message);
    handleError(error, res);
  }
});

// Get pending friend requests
router.get('/friends/requests', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const [received, sent] = await Promise.all([
      friendService.getPendingRequests(userId),
      friendService.getSentRequests(userId)
    ]);
    res.json({ received, sent });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Send friend request
router.post('/friends/request', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { friendId } = req.body;
    
    // Validate friendId
    if (!friendId || typeof friendId !== 'string') {
      return res.status(400).json({ error: 'Valid friendId required', code: 'VALIDATION_ERROR' });
    }
    if (friendId === userId) {
      return res.status(400).json({ error: 'Cannot send friend request to yourself', code: 'VALIDATION_ERROR' });
    }
    
    const request = await friendService.sendFriendRequest(userId, friendId);
    res.json({ request });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Accept friend request
router.post('/friends/accept/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Request ID required', code: 'VALIDATION_ERROR' });
    }
    
    const friendship = await friendService.acceptFriendRequest(id, userId);
    res.json({ friendship });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Decline friend request
router.post('/friends/decline/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Request ID required', code: 'VALIDATION_ERROR' });
    }
    
    await friendService.declineFriendRequest(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Remove friend
router.delete('/friends/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Friendship ID required', code: 'VALIDATION_ERROR' });
    }
    
    await friendService.removeFriend(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// ============================================
// STUDY GROUPS
// ============================================

// Get pending group invitations (must be before :id routes)
router.get('/groups/invitations/pending', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const invitations = await studyGroupService.getUserPendingInvitations(userId);
    res.json({ invitations });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Discover public groups
router.get('/groups/discover', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { limit, offset, search } = req.query;
    const groups = await studyGroupService.getPublicGroups(userId, {
      limit: limit ? Math.min(parseInt(limit as string) || 20, 50) : 20,
      offset: offset ? parseInt(offset as string) || 0 : 0,
      search: search as string
    });
    res.json({ groups });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Join a public group
router.post('/groups/:id/join', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    await studyGroupService.joinPublicGroup(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Accept group invitation
router.post('/groups/invitations/:id/accept', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Invitation ID required', code: 'VALIDATION_ERROR' });
    }
    
    await studyGroupService.acceptInvitation(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Get user's groups
router.get('/groups', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    console.log('[Social] Getting groups for user:', userId);
    const groups = await studyGroupService.getUserGroups(userId);
    console.log('[Social] Found', groups.length, 'groups');
    res.json({ groups });
  } catch (error: any) {
    console.error('[Social] Error getting groups:', error.message);
    handleError(error, res);
  }
});

// Create group
router.post('/groups', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { name, description, icon, isPublic } = req.body;
    
    if (!name || typeof name !== 'string' || name.trim().length < 1) {
      return res.status(400).json({ error: 'Group name is required', code: 'VALIDATION_ERROR' });
    }
    if (name.length > 100) {
      return res.status(400).json({ error: 'Group name must be 100 characters or less', code: 'VALIDATION_ERROR' });
    }
    
    const group = await studyGroupService.createGroup({
      name: name.trim(),
      description: description?.trim(),
      icon,
      isPublic: Boolean(isPublic),
      ownerId: userId
    });
    res.json({ group });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Get group details
router.get('/groups/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    const group = await studyGroupService.getGroup(id, userId);
    if (!group) {
      return res.status(404).json({ error: 'Group not found', code: 'NOT_FOUND' });
    }
    res.json({ group });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Update group
router.put('/groups/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    const group = await studyGroupService.updateGroup(id, userId, req.body);
    res.json({ group });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Delete group
router.delete('/groups/:id', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    await studyGroupService.deleteGroup(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Get group members
router.get('/groups/:id/members', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    const members = await studyGroupService.getMembers(id);
    res.json({ members });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Update member role
router.post('/groups/:id/members/:memberId/role', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id, memberId } = req.params;
    const { role } = req.body;

    if (!id || !memberId) {
      return res.status(400).json({ error: 'Group ID and member ID required', code: 'VALIDATION_ERROR' });
    }

    const allowedRoles = ['admin', 'moderator', 'member'];
    if (!role || !allowedRoles.includes(role)) {
      return res.status(400).json({ error: 'Invalid role', code: 'VALIDATION_ERROR' });
    }

    await studyGroupService.updateMemberRole(id, userId, memberId, role);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Remove member
router.post('/groups/:id/members/:memberId/remove', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id, memberId } = req.params;
    if (!id || !memberId) {
      return res.status(400).json({ error: 'Group ID and member ID required', code: 'VALIDATION_ERROR' });
    }

    await studyGroupService.removeMember(id, userId, memberId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Ban member
router.post('/groups/:id/bans', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id } = req.params;
    const { userId: targetUserId, reason } = req.body;

    if (!id || !targetUserId) {
      return res.status(400).json({ error: 'Group ID and user ID required', code: 'VALIDATION_ERROR' });
    }

    await studyGroupService.banMember(id, userId, targetUserId, reason);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// List bans
router.get('/groups/:id/bans', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }

    const bans = await studyGroupService.listBans(id, userId);
    res.json({ bans });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Unban member
router.delete('/groups/:id/bans/:memberId', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id, memberId } = req.params;
    if (!id || !memberId) {
      return res.status(400).json({ error: 'Group ID and user ID required', code: 'VALIDATION_ERROR' });
    }

    await studyGroupService.unbanMember(id, userId, memberId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Transfer ownership
router.post('/groups/:id/transfer-ownership', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;

    const { id } = req.params;
    const { newOwnerId } = req.body;

    if (!id || !newOwnerId) {
      return res.status(400).json({ error: 'Group ID and new owner ID required', code: 'VALIDATION_ERROR' });
    }

    await studyGroupService.transferOwnership(id, userId, newOwnerId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Invite user to group
router.post('/groups/:id/invite', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    const { userId: invitedUserId } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    if (!invitedUserId || typeof invitedUserId !== 'string') {
      return res.status(400).json({ error: 'User ID to invite is required', code: 'VALIDATION_ERROR' });
    }
    if (invitedUserId === userId) {
      return res.status(400).json({ error: 'Cannot invite yourself', code: 'VALIDATION_ERROR' });
    }
    
    const invitation = await studyGroupService.inviteUser(id, invitedUserId, userId);
    res.json({ invitation });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Leave group
router.post('/groups/:id/leave', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    await studyGroupService.leaveGroup(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Study sessions
router.post('/groups/:id/sessions', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    const { title, description, scheduledAt, durationMinutes, meetingUrl } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    if (!title || typeof title !== 'string') {
      return res.status(400).json({ error: 'Session title is required', code: 'VALIDATION_ERROR' });
    }
    if (!scheduledAt) {
      return res.status(400).json({ error: 'Scheduled time is required', code: 'VALIDATION_ERROR' });
    }
    
    const session = await studyGroupService.createSession({
      groupId: id,
      title: title.trim(),
      description: description?.trim(),
      scheduledAt: new Date(scheduledAt),
      durationMinutes: Math.min(Math.max(15, durationMinutes || 60), 480), // 15min to 8hrs
      meetingUrl,
      createdBy: userId
    });
    res.json({ session });
  } catch (error: any) {
    handleError(error, res);
  }
});

router.get('/groups/:id/sessions', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    const upcoming = req.query.upcoming !== 'false';
    const sessions = await studyGroupService.getGroupSessions(id, upcoming);
    res.json({ sessions });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Share notebook with group
router.post('/groups/:id/notebooks', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    const { notebookId, permission } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    if (!notebookId || typeof notebookId !== 'string') {
      return res.status(400).json({ error: 'Notebook ID is required', code: 'VALIDATION_ERROR' });
    }
    
    const validPermissions = ['viewer', 'editor'];
    const safePermission = validPermissions.includes(permission) ? permission : 'viewer';
    
    const share = await studyGroupService.shareNotebookWithGroup(
      notebookId, id, userId, safePermission
    );
    res.json({ share });
  } catch (error: any) {
    handleError(error, res);
  }
});

router.get('/groups/:id/notebooks', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Group ID required', code: 'VALIDATION_ERROR' });
    }
    
    const notebooks = await studyGroupService.getGroupSharedNotebooks(id);
    res.json({ notebooks });
  } catch (error: any) {
    handleError(error, res);
  }
});

// ============================================
// ACTIVITY FEED
// ============================================

router.get('/feed', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { limit, offset, filter } = req.query;
    
    const safeLimit = limit ? Math.min(parseInt(limit as string) || 20, 50) : 20;
    const safeOffset = offset ? Math.max(0, parseInt(offset as string) || 0) : 0;
    
    // Only pass filter if it's a valid ActivityType, not 'all', 'friends', or 'groups'
    // Those are UI filters, not database activity_type values
    const activities = await activityFeedService.getFeed(userId, {
      limit: safeLimit,
      offset: safeOffset,
      // Don't pass filter - let the service return all activities
      // The filter param was incorrectly being used for activity_type filtering
    });
    res.json({ activities });
  } catch (error: any) {
    handleError(error, res);
  }
});

router.get('/users/:id/activities', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'User ID required', code: 'VALIDATION_ERROR' });
    }
    
    const activities = await activityFeedService.getUserActivities(id, userId);
    res.json({ activities });
  } catch (error: any) {
    handleError(error, res);
  }
});

router.post('/activities/:id/react', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    const { reactionType } = req.body;
    
    if (!id) {
      return res.status(400).json({ error: 'Activity ID required', code: 'VALIDATION_ERROR' });
    }
    
    const validReactions = ['like', 'love', 'celebrate', 'support'];
    const safeReaction = validReactions.includes(reactionType) ? reactionType : 'like';
    
    const reaction = await activityFeedService.addReaction(id, userId, safeReaction);
    res.json({ reaction });
  } catch (error: any) {
    handleError(error, res);
  }
});

router.delete('/activities/:id/react', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { id } = req.params;
    if (!id) {
      return res.status(400).json({ error: 'Activity ID required', code: 'VALIDATION_ERROR' });
    }
    
    await activityFeedService.removeReaction(id, userId);
    res.json({ success: true });
  } catch (error: any) {
    handleError(error, res);
  }
});

// Log a new activity
router.post('/activities', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { activityType, title, description, referenceId, referenceType, metadata, isPublic } = req.body;
    
    if (!activityType || typeof activityType !== 'string') {
      return res.status(400).json({ error: 'Activity type is required', code: 'VALIDATION_ERROR' });
    }
    if (!title || typeof title !== 'string') {
      return res.status(400).json({ error: 'Title is required', code: 'VALIDATION_ERROR' });
    }
    
    const activity = await activityFeedService.createActivity({
      userId,
      activityType: activityType as any,
      title: title.substring(0, 200), // Limit title length
      description: description?.substring(0, 500),
      referenceId,
      referenceType,
      metadata: metadata || {},
      isPublic: isPublic !== false // Default to public
    });
    
    res.json({ activity });
  } catch (error: any) {
    handleError(error, res);
  }
});

// ============================================
// LEADERBOARD
// ============================================

// Valid options for leaderboard
const VALID_PERIODS = ['daily', 'weekly', 'monthly', 'all_time'] as const;
const VALID_METRICS = ['xp', 'quizzes', 'flashcards', 'study_time', 'streak'] as const;
const VALID_TYPES = ['global', 'friends'] as const;

type LeaderboardPeriod = typeof VALID_PERIODS[number];
type LeaderboardMetric = typeof VALID_METRICS[number];
type LeaderboardType = typeof VALID_TYPES[number];

router.get('/leaderboard', async (req: AuthRequest, res: Response) => {
  try {
    const userId = validateUserId(req, res);
    if (!userId) return;
    
    const { type, period, metric, limit } = req.query;
    
    // Validate and sanitize inputs
    const leaderboardType: LeaderboardType = VALID_TYPES.includes(type as any) 
      ? (type as LeaderboardType) 
      : 'global';
    const leaderboardPeriod: LeaderboardPeriod = VALID_PERIODS.includes(period as any) 
      ? (period as LeaderboardPeriod) 
      : 'weekly';
    const leaderboardMetric: LeaderboardMetric = VALID_METRICS.includes(metric as any) 
      ? (metric as LeaderboardMetric) 
      : 'xp';
    
    // Clamp limit between 1 and 100
    const leaderboardLimit = limit 
      ? Math.min(Math.max(1, parseInt(limit as string) || 50), 100) 
      : 50;

    let leaderboard;
    if (leaderboardType === 'friends') {
      leaderboard = await leaderboardService.getFriendsLeaderboard(
        userId, leaderboardPeriod, leaderboardMetric, leaderboardLimit
      );
    } else {
      leaderboard = await leaderboardService.getGlobalLeaderboard(
        leaderboardPeriod, leaderboardMetric, leaderboardLimit
      );
    }

    leaderboard = leaderboard.map((entry) => ({
      ...entry,
      isCurrentUser: entry.userId === userId,
    }));

    const rankScope = leaderboardType === 'friends'
      ? [userId, ...(await friendService.getFriendIds(userId))]
      : undefined;
    const userRank = await leaderboardService.getUserRank(
      userId, leaderboardPeriod, leaderboardMetric, rankScope
    );

    res.json({ leaderboard, userRank });
  } catch (error: any) {
    handleError(error, res);
  }
});

export default router;
