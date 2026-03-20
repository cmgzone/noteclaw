import pool from '../config/database.js';
import { friendService } from './friendService.js';

export type LeaderboardPeriod = 'daily' | 'weekly' | 'monthly' | 'all_time';
export type LeaderboardMetric = 'xp' | 'quizzes' | 'flashcards' | 'study_time' | 'streak';

export interface LeaderboardEntry {
  rank: number;
  userId: string;
  username: string;
  avatarUrl?: string;
  score: number;
  isFriend?: boolean;
  isCurrentUser?: boolean;
}

export const leaderboardService = {
  async getGlobalLeaderboard(
    period: LeaderboardPeriod = 'weekly',
    metric: LeaderboardMetric = 'xp',
    limit = 50
  ): Promise<LeaderboardEntry[]> {
    const periodStart = this.getPeriodStart(period);
    const metricColumn = this.getMetricColumn(metric);

    const result = await pool.query(`
      SELECT 
        u.id as user_id,
        u.display_name as username,
        u.avatar_url,
        COALESCE(SUM(ls.${metricColumn}), 0) as score
      FROM users u
      LEFT JOIN leaderboard_snapshots ls ON ls.user_id = u.id 
        AND ls.period_start >= $1
      GROUP BY u.id, u.display_name, u.avatar_url
      HAVING COALESCE(SUM(ls.${metricColumn}), 0) > 0
      ORDER BY score DESC
      LIMIT $2
    `, [periodStart, limit]);

    return result.rows.map((row, index) => ({
      rank: index + 1,
      userId: row.user_id,
      username: row.username,
      avatarUrl: row.avatar_url,
      score: parseInt(row.score)
    }));
  },

  async getFriendsLeaderboard(
    userId: string,
    period: LeaderboardPeriod = 'weekly',
    metric: LeaderboardMetric = 'xp',
    limit = 50
  ): Promise<LeaderboardEntry[]> {
    const friendIds = await friendService.getFriendIds(userId);
    const allUserIds = [userId, ...friendIds];
    const periodStart = this.getPeriodStart(period);
    const metricColumn = this.getMetricColumn(metric);

    const result = await pool.query(`
      SELECT 
        u.id as user_id,
        u.display_name as username,
        u.avatar_url,
        COALESCE(SUM(ls.${metricColumn}), 0) as score
      FROM users u
      LEFT JOIN leaderboard_snapshots ls ON ls.user_id = u.id 
        AND ls.period_start >= $2
      WHERE u.id = ANY($1)
      GROUP BY u.id, u.display_name, u.avatar_url
      ORDER BY score DESC
      LIMIT $3
    `, [allUserIds, periodStart, limit]);

    return result.rows.map((row, index) => ({
      rank: index + 1,
      userId: row.user_id,
      username: row.username,
      avatarUrl: row.avatar_url,
      score: parseInt(row.score),
      isFriend: row.user_id !== userId,
      isCurrentUser: row.user_id === userId
    }));
  },


  async getUserRank(
    userId: string,
    period: LeaderboardPeriod = 'weekly',
    metric: LeaderboardMetric = 'xp',
    scopedUserIds?: string[]
  ): Promise<{ rank: number; score: number; totalUsers: number }> {
    const periodStart = this.getPeriodStart(period);
    const metricColumn = this.getMetricColumn(metric);
    const scopeClause = scopedUserIds?.length ? 'WHERE u.id = ANY($3)' : '';
    const queryParams = scopedUserIds?.length
      ? [userId, periodStart, scopedUserIds]
      : [userId, periodStart];

    const result = await pool.query(`
      WITH user_scores AS (
        SELECT 
          u.id,
          COALESCE(SUM(ls.${metricColumn}), 0) as score
        FROM users u
        LEFT JOIN leaderboard_snapshots ls ON ls.user_id = u.id 
          AND ls.period_start >= $2
        ${scopeClause}
        GROUP BY u.id
      ),
      ranked AS (
        SELECT id, score, RANK() OVER (ORDER BY score DESC) as rank
        FROM user_scores
        WHERE score > 0
      )
      SELECT rank, score, (SELECT COUNT(*) FROM ranked) as total_users
      FROM ranked
      WHERE id = $1
    `, queryParams);

    if (result.rows.length === 0) {
      return { rank: 0, score: 0, totalUsers: 0 };
    }

    return {
      rank: parseInt(result.rows[0].rank),
      score: parseInt(result.rows[0].score),
      totalUsers: parseInt(result.rows[0].total_users)
    };
  },

  async updateUserStats(userId: string, stats: {
    xpEarned?: number;
    quizzesCompleted?: number;
    flashcardsReviewed?: number;
    studyMinutes?: number;
    streakDays?: number;
  }) {
    const today = new Date().toISOString().split('T')[0];
    
    await pool.query(`
      INSERT INTO leaderboard_snapshots (user_id, period_type, period_start, xp_earned, quizzes_completed, flashcards_reviewed, study_minutes, streak_days)
      VALUES ($1, 'daily', $2, $3, $4, $5, $6, $7)
      ON CONFLICT (user_id, period_type, period_start)
      DO UPDATE SET
        xp_earned = leaderboard_snapshots.xp_earned + COALESCE($3, 0),
        quizzes_completed = leaderboard_snapshots.quizzes_completed + COALESCE($4, 0),
        flashcards_reviewed = leaderboard_snapshots.flashcards_reviewed + COALESCE($5, 0),
        study_minutes = leaderboard_snapshots.study_minutes + COALESCE($6, 0),
        streak_days = COALESCE($7, leaderboard_snapshots.streak_days),
        updated_at = NOW()
    `, [userId, today, stats.xpEarned || 0, stats.quizzesCompleted || 0, stats.flashcardsReviewed || 0, stats.studyMinutes || 0, stats.streakDays]);
  },

  getPeriodStart(period: LeaderboardPeriod): string {
    const now = new Date();
    switch (period) {
      case 'daily':
        return now.toISOString().split('T')[0];
      case 'weekly':
        const weekStart = new Date(now);
        weekStart.setDate(now.getDate() - now.getDay());
        return weekStart.toISOString().split('T')[0];
      case 'monthly':
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`;
      case 'all_time':
        return '2020-01-01';
      default:
        return now.toISOString().split('T')[0];
    }
  },

  getMetricColumn(metric: LeaderboardMetric): string {
    switch (metric) {
      case 'xp': return 'xp_earned';
      case 'quizzes': return 'quizzes_completed';
      case 'flashcards': return 'flashcards_reviewed';
      case 'study_time': return 'study_minutes';
      case 'streak': return 'streak_days';
      default: return 'xp_earned';
    }
  }
};
