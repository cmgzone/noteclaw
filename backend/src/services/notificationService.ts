import pool from '../config/database.js';

export type NotificationType = 
  | 'message' 
  | 'friend_request' 
  | 'achievement' 
  | 'group_invite' 
  | 'group_message' 
  | 'study_reminder' 
  | 'system';

export interface Notification {
  id: string;
  userId: string;
  type: NotificationType;
  title: string;
  body?: string;
  data?: Record<string, any>;
  isRead: boolean;
  readAt?: Date;
  actionUrl?: string;
  senderId?: string;
  senderUsername?: string;
  senderAvatarUrl?: string;
  createdAt: Date;
}

export interface NotificationSettings {
  messagesEnabled: boolean;
  friendRequestsEnabled: boolean;
  achievementsEnabled: boolean;
  groupInvitesEnabled: boolean;
  groupMessagesEnabled: boolean;
  studyRemindersEnabled: boolean;
  systemEnabled: boolean;
  emailNotifications: boolean;
  pushNotifications: boolean;
  quietHoursStart?: string;
  quietHoursEnd?: string;
}

export interface CreateNotificationParams {
  userId: string;
  type: NotificationType;
  title: string;
  body?: string;
  data?: Record<string, any>;
  actionUrl?: string;
  senderId?: string;
}

class NotificationService {
  // Check if user has notifications enabled for this type
  async isNotificationEnabled(userId: string, type: NotificationType): Promise<boolean> {
    const settings = await this.getSettings(userId);
    const typeMap: Record<NotificationType, keyof NotificationSettings> = {
      message: 'messagesEnabled',
      friend_request: 'friendRequestsEnabled',
      achievement: 'achievementsEnabled',
      group_invite: 'groupInvitesEnabled',
      group_message: 'groupMessagesEnabled',
      study_reminder: 'studyRemindersEnabled',
      system: 'systemEnabled',
    };
    return settings[typeMap[type]] as boolean;
  }

  // Create a notification
  async create(params: CreateNotificationParams): Promise<Notification | null> {
    const { userId, type, title, body, data, actionUrl, senderId } = params;

    // Check if enabled
    const enabled = await this.isNotificationEnabled(userId, type);
    if (!enabled) return null;

    const result = await pool.query(`
      INSERT INTO notifications (user_id, type, title, body, data, action_url, sender_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING *
    `, [userId, type, title, body, data || {}, actionUrl, senderId]);

    return this.mapNotification(result.rows[0]);
  }

  // Get notifications for a user
  async getForUser(
    userId: string, 
    options?: { limit?: number; offset?: number; unreadOnly?: boolean }
  ): Promise<{ notifications: Notification[]; total: number; unreadCount: number }> {
    const limit = Math.min(options?.limit || 50, 100);
    const offset = options?.offset || 0;

    let query = `
      SELECT n.*, u.display_name as sender_username, u.avatar_url as sender_avatar_url
      FROM notifications n
      LEFT JOIN users u ON u.id = n.sender_id
      WHERE n.user_id = $1
    `;
    const params: any[] = [userId];

    if (options?.unreadOnly) {
      query += ` AND n.is_read = FALSE`;
    }

    query += ` ORDER BY n.created_at DESC LIMIT $2 OFFSET $3`;
    params.push(limit, offset);

    const [notifs, countResult, unreadResult] = await Promise.all([
      pool.query(query, params),
      pool.query('SELECT COUNT(*) FROM notifications WHERE user_id = $1', [userId]),
      pool.query('SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = FALSE', [userId])
    ]);

    return {
      notifications: notifs.rows.map(r => this.mapNotification(r)),
      total: parseInt(countResult.rows[0].count),
      unreadCount: parseInt(unreadResult.rows[0].count)
    };
  }

  // Mark notification as read
  async markAsRead(notificationId: string, userId: string): Promise<boolean> {
    const result = await pool.query(`
      UPDATE notifications 
      SET is_read = TRUE, read_at = NOW()
      WHERE id = $1 AND user_id = $2
      RETURNING id
    `, [notificationId, userId]);
    return result.rows.length > 0;
  }

  // Mark all as read
  async markAllAsRead(userId: string): Promise<number> {
    const result = await pool.query(`
      UPDATE notifications 
      SET is_read = TRUE, read_at = NOW()
      WHERE user_id = $1 AND is_read = FALSE
    `, [userId]);
    return result.rowCount || 0;
  }

  // Delete notification
  async delete(notificationId: string, userId: string): Promise<boolean> {
    const result = await pool.query(
      'DELETE FROM notifications WHERE id = $1 AND user_id = $2 RETURNING id',
      [notificationId, userId]
    );
    return result.rows.length > 0;
  }

  // Get unread count
  async getUnreadCount(userId: string): Promise<number> {
    const result = await pool.query(
      'SELECT COUNT(*) FROM notifications WHERE user_id = $1 AND is_read = FALSE',
      [userId]
    );
    return parseInt(result.rows[0].count);
  }

  // Get/create settings
  async getSettings(userId: string): Promise<NotificationSettings> {
    let result = await pool.query(
      'SELECT * FROM notification_settings WHERE user_id = $1',
      [userId]
    );

    if (result.rows.length === 0) {
      result = await pool.query(`
        INSERT INTO notification_settings (user_id)
        VALUES ($1)
        RETURNING *
      `, [userId]);
    }

    const r = result.rows[0];
    return {
      messagesEnabled: r.messages_enabled,
      friendRequestsEnabled: r.friend_requests_enabled,
      achievementsEnabled: r.achievements_enabled,
      groupInvitesEnabled: r.group_invites_enabled,
      groupMessagesEnabled: r.group_messages_enabled,
      studyRemindersEnabled: r.study_reminders_enabled,
      systemEnabled: r.system_enabled,
      emailNotifications: r.email_notifications,
      pushNotifications: r.push_notifications,
      quietHoursStart: r.quiet_hours_start,
      quietHoursEnd: r.quiet_hours_end,
    };
  }

  // Update settings
  async updateSettings(userId: string, settings: Partial<NotificationSettings>): Promise<NotificationSettings> {
    const updates: string[] = [];
    const values: any[] = [userId];
    let paramIndex = 2;

    const fieldMap: Record<string, string> = {
      messagesEnabled: 'messages_enabled',
      friendRequestsEnabled: 'friend_requests_enabled',
      achievementsEnabled: 'achievements_enabled',
      groupInvitesEnabled: 'group_invites_enabled',
      groupMessagesEnabled: 'group_messages_enabled',
      studyRemindersEnabled: 'study_reminders_enabled',
      systemEnabled: 'system_enabled',
      emailNotifications: 'email_notifications',
      pushNotifications: 'push_notifications',
      quietHoursStart: 'quiet_hours_start',
      quietHoursEnd: 'quiet_hours_end',
    };

    for (const [key, dbField] of Object.entries(fieldMap)) {
      if (key in settings) {
        updates.push(`${dbField} = $${paramIndex}`);
        values.push((settings as any)[key]);
        paramIndex++;
      }
    }

    if (updates.length > 0) {
      await pool.query(`
        INSERT INTO notification_settings (user_id) VALUES ($1)
        ON CONFLICT (user_id) DO UPDATE SET ${updates.join(', ')}, updated_at = NOW()
      `, values);
    }

    return this.getSettings(userId);
  }

  // Helper notification creators
  async notifyNewMessage(recipientId: string, senderId: string, senderName: string): Promise<Notification | null> {
    return this.create({
      userId: recipientId,
      type: 'message',
      title: 'New Message',
      body: `${senderName} sent you a message`,
      senderId,
      actionUrl: `/social/chat/${senderId}`,
    });
  }

  async notifyFriendRequest(recipientId: string, senderId: string, senderName: string): Promise<Notification | null> {
    return this.create({
      userId: recipientId,
      type: 'friend_request',
      title: 'Friend Request',
      body: `${senderName} wants to be your friend`,
      senderId,
      actionUrl: '/social/friends',
    });
  }

  async notifyAchievement(userId: string, achievementTitle: string, xpReward: number): Promise<Notification | null> {
    return this.create({
      userId,
      type: 'achievement',
      title: 'Achievement Unlocked! 🏆',
      body: `You earned "${achievementTitle}" (+${xpReward} XP)`,
      actionUrl: '/gamification/achievements',
      data: { achievementTitle, xpReward },
    });
  }

  async notifyGroupInvite(recipientId: string, groupId: string, groupName: string, inviterId: string): Promise<Notification | null> {
    return this.create({
      userId: recipientId,
      type: 'group_invite',
      title: 'Group Invitation',
      body: `You've been invited to join "${groupName}"`,
      senderId: inviterId,
      actionUrl: `/social/groups/${groupId}`,
      data: { groupId, groupName },
    });
  }

  async notifyGroupMessage(recipientId: string, groupId: string, groupName: string, senderId: string, senderName: string): Promise<Notification | null> {
    return this.create({
      userId: recipientId,
      type: 'group_message',
      title: groupName,
      body: `${senderName} sent a message`,
      senderId,
      actionUrl: `/social/group/${groupId}/chat`,
      data: { groupId, groupName },
    });
  }

  // Admin notification methods
  async sendSystemNotification(
    userIds: string[], 
    title: string, 
    body?: string, 
    actionUrl?: string,
    data?: Record<string, any>,
    type: NotificationType = 'system'
  ): Promise<{ sent: number; failed: number }> {
    let sent = 0;
    let failed = 0;

    for (const userId of userIds) {
      try {
        const notification = await this.create({
          userId,
          type,
          title,
          body,
          actionUrl,
          data,
        });
        if (notification) sent++;
        else failed++;
      } catch (error) {
        console.error(`Failed to send notification to user ${userId}:`, error);
        failed++;
      }
    }

    return { sent, failed };
  }

  async sendBroadcastNotification(
    title: string, 
    body?: string, 
    actionUrl?: string,
    data?: Record<string, any>,
    type: NotificationType = 'system'
  ): Promise<{ sent: number; failed: number }> {
    // Get all active users
    const result = await pool.query('SELECT id FROM users WHERE is_active = TRUE');
    const userIds = result.rows.map(row => row.id);
    
    return this.sendSystemNotification(userIds, title, body, actionUrl, data, type);
  }

  async getNotificationStats(): Promise<{
    totalNotifications: number;
    unreadNotifications: number;
    notificationsByType: Record<string, number>;
    recentNotifications: Array<{
      id: string;
      title: string;
      type: string;
      recipientEmail: string;
      createdAt: Date;
      isRead: boolean;
    }>;
  }> {
    const [totalResult, unreadResult, typeResult, recentResult] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM notifications'),
      pool.query('SELECT COUNT(*) FROM notifications WHERE is_read = FALSE'),
      pool.query(`
        SELECT type, COUNT(*) as count 
        FROM notifications 
        GROUP BY type 
        ORDER BY count DESC
      `),
      pool.query(`
        SELECT n.id, n.title, n.type, n.created_at, n.is_read, u.email as recipient_email
        FROM notifications n
        JOIN users u ON u.id = n.user_id
        ORDER BY n.created_at DESC
        LIMIT 20
      `)
    ]);

    const notificationsByType: Record<string, number> = {};
    typeResult.rows.forEach(row => {
      notificationsByType[row.type] = parseInt(row.count);
    });

    return {
      totalNotifications: parseInt(totalResult.rows[0].count),
      unreadNotifications: parseInt(unreadResult.rows[0].count),
      notificationsByType,
      recentNotifications: recentResult.rows.map(row => ({
        id: row.id,
        title: row.title,
        type: row.type,
        recipientEmail: row.recipient_email,
        createdAt: row.created_at,
        isRead: row.is_read,
      })),
    };
  }

  private mapNotification(row: any): Notification {
    return {
      id: row.id,
      userId: row.user_id,
      type: row.type,
      title: row.title,
      body: row.body,
      data: row.data,
      isRead: row.is_read,
      readAt: row.read_at,
      actionUrl: row.action_url,
      senderId: row.sender_id,
      senderUsername: row.sender_username,
      senderAvatarUrl: row.sender_avatar_url,
      createdAt: row.created_at,
    };
  }
}

export const notificationService = new NotificationService();
