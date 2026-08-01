import crypto from 'crypto';
import pool from '../config/database.js';
import { getAppSettingValueWithEnvironmentFallback } from './appSettingsService.js';

export const DEFAULT_PLAY_TEST_OPT_IN_URL = 'https://play.google.com/apps/testing/com.note.claw';

export const PLAY_TESTER_STATUSES = [
    'invited',
    'authorized',
    'active',
    'declined',
] as const;

export type PlayTesterStatus = typeof PLAY_TESTER_STATUSES[number];
export type PlayTesterCopyMode = 'group' | 'individual';

type PlayTesterRow = {
    id: string;
    email: string;
    display_name: string | null;
    status: PlayTesterStatus;
    invite_email_sent: boolean;
    invite_email_sent_at: Date | string | null;
    joined_at: Date | string;
    last_requested_at: Date | string;
    request_count: number;
    copied_to_play: boolean;
    copied_at: Date | string | null;
    copy_mode: PlayTesterCopyMode | null;
    copy_batch_id: string | null;
    notes: string | null;
    updated_at: Date | string;
};

export type PlayTester = {
    id: string;
    email: string;
    displayName: string | null;
    status: PlayTesterStatus;
    inviteEmailSent: boolean;
    inviteEmailSentAt: Date | string | null;
    joinedAt: Date | string;
    lastRequestedAt: Date | string;
    requestCount: number;
    copiedToPlay: boolean;
    copiedAt: Date | string | null;
    copyMode: PlayTesterCopyMode | null;
    copyBatchId: string | null;
    notes: string | null;
    updatedAt: Date | string;
};

export type PlayTestingSettings = {
    optInUrl: string;
    groupUrl: string | null;
    feedbackEmail: string | null;
};

let ensureTablePromise: Promise<void> | null = null;

function mapPlayTester(row: PlayTesterRow): PlayTester {
    return {
        id: row.id,
        email: row.email,
        displayName: row.display_name,
        status: row.status,
        inviteEmailSent: row.invite_email_sent,
        inviteEmailSentAt: row.invite_email_sent_at,
        joinedAt: row.joined_at,
        lastRequestedAt: row.last_requested_at,
        requestCount: Number(row.request_count || 0),
        copiedToPlay: row.copied_to_play,
        copiedAt: row.copied_at,
        copyMode: row.copy_mode,
        copyBatchId: row.copy_batch_id,
        notes: row.notes,
        updatedAt: row.updated_at,
    };
}

function normalizeHttpsUrl(value: string | null, fallback: string | null): string | null {
    const candidate = value?.trim() || fallback;
    if (!candidate) return null;

    try {
        const parsed = new URL(candidate);
        return parsed.protocol === 'https:' ? parsed.toString() : fallback;
    } catch {
        return fallback;
    }
}

export function isPlayTesterStatus(value: unknown): value is PlayTesterStatus {
    return typeof value === 'string' && PLAY_TESTER_STATUSES.includes(value as PlayTesterStatus);
}

export function ensurePlayTesterTable(): Promise<void> {
    if (!ensureTablePromise) {
        ensureTablePromise = (async () => {
            await pool.query(`
                CREATE TABLE IF NOT EXISTS play_testers (
                    id UUID PRIMARY KEY,
                    email TEXT NOT NULL,
                    display_name TEXT,
                    status TEXT NOT NULL DEFAULT 'invited',
                    invite_email_sent BOOLEAN NOT NULL DEFAULT FALSE,
                    invite_email_sent_at TIMESTAMPTZ,
                    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    last_requested_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                    request_count INTEGER NOT NULL DEFAULT 1,
                    copied_to_play BOOLEAN NOT NULL DEFAULT FALSE,
                    copied_at TIMESTAMPTZ,
                    copy_mode TEXT,
                    copy_batch_id UUID,
                    notes TEXT,
                    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
                )
            `);
            await pool.query(`
                ALTER TABLE play_testers
                    ADD COLUMN IF NOT EXISTS copied_to_play BOOLEAN NOT NULL DEFAULT FALSE,
                    ADD COLUMN IF NOT EXISTS copied_at TIMESTAMPTZ,
                    ADD COLUMN IF NOT EXISTS copy_mode TEXT,
                    ADD COLUMN IF NOT EXISTS copy_batch_id UUID
            `);
            await pool.query(`
                CREATE UNIQUE INDEX IF NOT EXISTS play_testers_email_lower_unique
                ON play_testers (LOWER(email))
            `);
            await pool.query(`
                CREATE INDEX IF NOT EXISTS play_testers_status_joined_index
                ON play_testers (status, joined_at DESC)
            `);
        })().catch((error) => {
            ensureTablePromise = null;
            throw error;
        });
    }

    return ensureTablePromise;
}

export async function getPlayTestingSettings(): Promise<PlayTestingSettings> {
    const [storedOptInUrl, storedGroupUrl, storedFeedbackEmail] = await Promise.all([
        getAppSettingValueWithEnvironmentFallback('play_test_opt_in_url'),
        getAppSettingValueWithEnvironmentFallback('play_test_group_url'),
        getAppSettingValueWithEnvironmentFallback('play_test_feedback_email'),
    ]);

    return {
        optInUrl: normalizeHttpsUrl(storedOptInUrl, DEFAULT_PLAY_TEST_OPT_IN_URL)
            || DEFAULT_PLAY_TEST_OPT_IN_URL,
        groupUrl: normalizeHttpsUrl(storedGroupUrl, null),
        feedbackEmail: storedFeedbackEmail?.trim() || null,
    };
}

export async function joinPlayTestingProgram(params: {
    email: string;
    displayName?: string | null;
}): Promise<{ tester: PlayTester; shouldSendInvite: boolean }> {
    await ensurePlayTesterTable();

    const existing = await pool.query<PlayTesterRow>(
        `SELECT * FROM play_testers WHERE LOWER(email) = LOWER($1) LIMIT 1`,
        [params.email],
    );

    if (existing.rows.length > 0) {
        const current = existing.rows[0];
        const lastSentAt = current.invite_email_sent_at
            ? new Date(current.invite_email_sent_at).getTime()
            : 0;
        const shouldSendInvite = !lastSentAt || Date.now() - lastSentAt >= 5 * 60 * 1000;
        const updated = await pool.query<PlayTesterRow>(
            `UPDATE play_testers
             SET display_name = COALESCE(NULLIF($2, ''), display_name),
                 last_requested_at = NOW(),
                 request_count = request_count + 1,
                 updated_at = NOW()
             WHERE id = $1
             RETURNING *`,
            [current.id, params.displayName?.trim() || null],
        );
        return { tester: mapPlayTester(updated.rows[0]), shouldSendInvite };
    }

    const created = await pool.query<PlayTesterRow>(
        `INSERT INTO play_testers (id, email, display_name)
         VALUES ($1, $2, $3)
         RETURNING *`,
        [crypto.randomUUID(), params.email, params.displayName?.trim() || null],
    );

    return { tester: mapPlayTester(created.rows[0]), shouldSendInvite: true };
}

export async function markPlayTesterInviteSent(
    testerId: string,
    sent: boolean,
): Promise<void> {
    await ensurePlayTesterTable();
    await pool.query(
        `UPDATE play_testers
         SET invite_email_sent = $2,
             invite_email_sent_at = CASE WHEN $2 THEN NOW() ELSE invite_email_sent_at END,
             updated_at = NOW()
         WHERE id = $1`,
        [testerId, sent],
    );
}

export async function getPlayTesterById(testerId: string): Promise<PlayTester | null> {
    await ensurePlayTesterTable();
    const result = await pool.query<PlayTesterRow>(
        'SELECT * FROM play_testers WHERE id = $1 LIMIT 1',
        [testerId],
    );
    return result.rows[0] ? mapPlayTester(result.rows[0]) : null;
}

export async function listPlayTesters(params: {
    search?: string;
    status?: PlayTesterStatus | null;
    copied?: boolean | null;
    limit?: number;
    offset?: number;
}): Promise<{
    testers: PlayTester[];
    total: number;
    statusCounts: Record<string, number>;
    copyCounts: { copied: number; uncopied: number };
}> {
    await ensurePlayTesterTable();

    const search = params.search?.trim() || '';
    const values: unknown[] = [];
    const clauses: string[] = [];

    if (search) {
        values.push(`%${search}%`);
        clauses.push(`(email ILIKE $${values.length} OR COALESCE(display_name, '') ILIKE $${values.length})`);
    }
    if (params.status) {
        values.push(params.status);
        clauses.push(`status = $${values.length}`);
    }
    if (typeof params.copied === 'boolean') {
        values.push(params.copied);
        clauses.push(`copied_to_play = $${values.length}`);
    }

    const where = clauses.length > 0 ? `WHERE ${clauses.join(' AND ')}` : '';
    const limit = Math.min(Math.max(params.limit || 100, 1), 500);
    const offset = Math.max(params.offset || 0, 0);
    values.push(limit, offset);

    const [rows, count, statusCounts, copyCounts] = await Promise.all([
        pool.query<PlayTesterRow>(
            `SELECT * FROM play_testers
             ${where}
             ORDER BY joined_at DESC
             LIMIT $${values.length - 1} OFFSET $${values.length}`,
            values,
        ),
        pool.query<{ total: string }>(
            `SELECT COUNT(*)::text AS total FROM play_testers ${where}`,
            values.slice(0, values.length - 2),
        ),
        pool.query<{ status: string; count: string }>(
            `SELECT status, COUNT(*)::text AS count
             FROM play_testers
             GROUP BY status`,
        ),
        pool.query<{ copied: string; uncopied: string }>(`
            SELECT
                COUNT(*) FILTER (WHERE copied_to_play)::text AS copied,
                COUNT(*) FILTER (WHERE NOT copied_to_play)::text AS uncopied
            FROM play_testers
        `),
    ]);

    return {
        testers: rows.rows.map(mapPlayTester),
        total: Number(count.rows[0]?.total || 0),
        statusCounts: Object.fromEntries(
            statusCounts.rows.map((row) => [row.status, Number(row.count || 0)]),
        ),
        copyCounts: {
            copied: Number(copyCounts.rows[0]?.copied || 0),
            uncopied: Number(copyCounts.rows[0]?.uncopied || 0),
        },
    };
}

export async function markPlayTestersCopied(params: {
    ids: string[];
    mode: PlayTesterCopyMode;
}): Promise<{ updated: number; batchId: string }> {
    await ensurePlayTesterTable();

    const batchId = crypto.randomUUID();
    const result = await pool.query<{ id: string }>(
        `UPDATE play_testers
         SET copied_to_play = TRUE,
             copied_at = NOW(),
             copy_mode = $2,
             copy_batch_id = $3,
             updated_at = NOW()
         WHERE id = ANY($1::uuid[])
         RETURNING id`,
        [params.ids, params.mode, batchId],
    );

    return { updated: result.rowCount || 0, batchId };
}

export async function updatePlayTester(params: {
    id: string;
    status: PlayTesterStatus;
    notes?: string | null;
}): Promise<PlayTester | null> {
    await ensurePlayTesterTable();
    const result = await pool.query<PlayTesterRow>(
        `UPDATE play_testers
         SET status = $2,
             notes = CASE WHEN $3::text IS NULL THEN notes ELSE $3 END,
             updated_at = NOW()
         WHERE id = $1
         RETURNING *`,
        [params.id, params.status, params.notes === undefined ? null : params.notes],
    );
    return result.rows[0] ? mapPlayTester(result.rows[0]) : null;
}
