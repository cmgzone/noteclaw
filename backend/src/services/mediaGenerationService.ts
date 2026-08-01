import axios from 'axios';
import pool from '../config/database.js';
import bunnyService from './bunnyService.js';
import { decryptSecretAllowLegacy } from './secretEncryptionService.js';
import { getAppSettingValue } from './appSettingsService.js';
import {
    ALIBABA_TOKEN_PLAN_PROVIDER,
    getAlibabaTokenPlanApiKey,
} from './alibabaTokenPlanService.js';
import {
    consumeCredits,
    getFeatureCreditCost,
    refundCredits,
    type MeteredCreditFeature,
} from './creditService.js';

export type MediaGenerationKind = 'image' | 'video';
export type MediaGenerationStatus = 'pending' | 'processing' | 'completed' | 'failed';

export interface MediaGenerationRecord {
    id: string;
    userId: string;
    kind: MediaGenerationKind;
    provider: string;
    model: string;
    prompt: string;
    status: MediaGenerationStatus;
    providerTaskId?: string | null;
    providerResultUrl?: string | null;
    publicUrl?: string | null;
    downloadUrl: string;
    contentType?: string | null;
    filename?: string | null;
    error?: string | null;
    creditsCharged: number;
    createdAt: string;
    updatedAt: string;
}

interface StartGenerationInput {
    kind: MediaGenerationKind;
    prompt: string;
    model?: string;
    provider?: string;
    size?: string;
    duration?: number;
}

const MODEL_STUDIO_PROVIDER = 'alibaba_model_studio';
const TOKEN_PLAN_MEDIA_BASE_URL = 'https://token-plan.ap-southeast-1.maas.aliyuncs.com';
const DEFAULT_IMAGE_MODEL = 'wan2.7-image';
const DEFAULT_VIDEO_MODEL = 'wan2.7-t2v';
const DEFAULT_TOKEN_PLAN_IMAGE_MODEL = 'qwen-image-2.0';
const DEFAULT_TOKEN_PLAN_VIDEO_MODEL = 'happyhorse-1.1-t2v';
const MAX_STORED_MEDIA_BYTES = 150 * 1024 * 1024;
type AlibabaMediaProvider = typeof MODEL_STUDIO_PROVIDER | typeof ALIBABA_TOKEN_PLAN_PROVIDER;

function providerErrorMessage(error: unknown): string {
    if (axios.isAxiosError(error)) {
        const body = error.response?.data as any;
        return body?.message || body?.code || body?.error?.message || error.message;
    }
    return error instanceof Error ? error.message : String(error);
}

async function getProviderConfig(provider: AlibabaMediaProvider): Promise<{ apiKey: string; baseUrl: string }> {
    if (provider === ALIBABA_TOKEN_PLAN_PROVIDER) {
        return {
            apiKey: await getAlibabaTokenPlanApiKey(),
            baseUrl: TOKEN_PLAN_MEDIA_BASE_URL,
        };
    }

    const keyResult = await pool.query(
        'SELECT encrypted_value FROM api_keys WHERE service_name = $1 LIMIT 1',
        [MODEL_STUDIO_PROVIDER],
    );
    const storedKey = keyResult.rows[0]?.encrypted_value
        ? decryptSecretAllowLegacy(keyResult.rows[0].encrypted_value).trim()
        : '';
    const apiKey = storedKey || process.env.ALIBABA_MODEL_STUDIO_API_KEY?.trim() || '';
    if (!apiKey || !apiKey.startsWith('sk-') || apiKey.startsWith('sk-sp-')) {
        throw new Error('Alibaba Model Studio API key is not configured. Add a standard sk- key as alibaba_model_studio in Admin Settings.');
    }

    const storedBaseUrl = (await getAppSettingValue('alibaba_model_studio_base_url'))?.trim();
    const baseUrl = (storedBaseUrl || process.env.ALIBABA_MODEL_STUDIO_BASE_URL || '').trim().replace(/\/+$/, '');
    if (!/^https:\/\/[a-z0-9.-]+$/i.test(baseUrl)) {
        throw new Error('Alibaba Model Studio base URL is not configured. Set the Singapore workspace URL in Admin Settings.');
    }
    return { apiKey, baseUrl };
}

function normalizeRequestedProvider(provider?: string): AlibabaMediaProvider | null {
    const normalized = provider?.trim().toLowerCase();
    if (!normalized) return null;
    if (normalized === MODEL_STUDIO_PROVIDER || normalized === ALIBABA_TOKEN_PLAN_PROVIDER) {
        return normalized;
    }
    throw new Error('Unsupported Alibaba media provider.');
}

async function resolveProvider(
    kind: MediaGenerationKind,
    model: string,
    requested?: string,
): Promise<AlibabaMediaProvider> {
    const explicit = normalizeRequestedProvider(requested);
    if (explicit) return explicit;

    const catalog = await pool.query<{ provider: string }>(
        `SELECT provider
         FROM ai_models
         WHERE model_id = $1
           AND is_active = TRUE
           AND capabilities ? $2
           AND provider IN ($3, $4)
         ORDER BY CASE provider WHEN $3 THEN 0 ELSE 1 END
         LIMIT 1`,
        [model, kind, ALIBABA_TOKEN_PLAN_PROVIDER, MODEL_STUDIO_PROVIDER],
    );
    const catalogProvider = normalizeRequestedProvider(catalog.rows[0]?.provider);
    return catalogProvider || MODEL_STUDIO_PROVIDER;
}

function resolveModel(
    kind: MediaGenerationKind,
    requested?: string,
    requestedProvider?: AlibabaMediaProvider | null,
): string {
    const model = requested?.trim();
    if (model && model.length <= 200 && /^[a-zA-Z0-9._:/-]+$/.test(model)) return model;
    if (requestedProvider === ALIBABA_TOKEN_PLAN_PROVIDER) {
        return kind === 'image' ? DEFAULT_TOKEN_PLAN_IMAGE_MODEL : DEFAULT_TOKEN_PLAN_VIDEO_MODEL;
    }
    return kind === 'image' ? DEFAULT_IMAGE_MODEL : DEFAULT_VIDEO_MODEL;
}

function normalizeSize(kind: MediaGenerationKind, requested?: string): string {
    const fallback = kind === 'image' ? '1024*1024' : '1280*720';
    const size = (requested || fallback).replace('x', '*').trim();
    return /^\d{2,5}\*\d{2,5}$/.test(size) ? size : fallback;
}

function tokenPlanVideoParameters(size: string, duration: number) {
    const [width, height] = size.split('*').map(Number);
    const ratio = width > height ? '16:9' : height > width ? '9:16' : '1:1';
    const shortestEdge = Math.min(width, height);
    const resolution = shortestEdge >= 1080 ? '1080P' : shortestEdge >= 720 ? '720P' : '480P';
    return { resolution, ratio, duration };
}

function extractImageUrl(payload: any): string | null {
    const content = payload?.output?.choices?.[0]?.message?.content;
    if (Array.isArray(content)) {
        for (const item of content) {
            if (typeof item?.image === 'string') return item.image;
            if (typeof item?.image_url === 'string') return item.image_url;
        }
    }
    return payload?.output?.results?.[0]?.url || payload?.output?.url || null;
}

function extractVideoUrl(payload: any): string | null {
    return payload?.output?.video_url
        || payload?.output?.results?.[0]?.url
        || payload?.output?.results?.[0]?.video_url
        || null;
}

function serialize(row: any): MediaGenerationRecord {
    return {
        id: row.id,
        userId: row.user_id,
        kind: row.kind,
        provider: row.provider,
        model: row.model,
        prompt: row.prompt,
        status: row.status,
        providerTaskId: row.provider_task_id,
        providerResultUrl: row.provider_result_url,
        publicUrl: row.public_url,
        downloadUrl: `/api/generation/${row.id}/download`,
        contentType: row.content_type,
        filename: row.filename,
        error: row.error,
        creditsCharged: Number(row.credits_charged || 0),
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    };
}

async function persistRemoteMedia(id: string, userId: string, kind: MediaGenerationKind, remoteUrl: string): Promise<void> {
    const parsedUrl = new URL(remoteUrl);
    const trustedHost = parsedUrl.hostname === 'aliyuncs.com'
        || parsedUrl.hostname.endsWith('.aliyuncs.com')
        || parsedUrl.hostname === 'alicdn.com'
        || parsedUrl.hostname.endsWith('.alicdn.com');
    if (parsedUrl.protocol !== 'https:' || !trustedHost) {
        throw new Error('Alibaba returned an untrusted media download URL.');
    }
    const response = await axios.get<ArrayBuffer>(remoteUrl, {
        responseType: 'arraybuffer',
        timeout: kind === 'video' ? 180000 : 60000,
        maxContentLength: MAX_STORED_MEDIA_BYTES,
        maxBodyLength: MAX_STORED_MEDIA_BYTES,
    });
    const buffer = Buffer.from(response.data);
    if (buffer.length === 0 || buffer.length > MAX_STORED_MEDIA_BYTES) {
        throw new Error('Generated media exceeded the storage limit.');
    }

    const contentType = String(response.headers['content-type'] || (kind === 'image' ? 'image/png' : 'video/mp4')).split(';')[0];
    const extension = contentType.includes('jpeg') ? 'jpg'
        : contentType.includes('webp') ? 'webp'
            : kind === 'image' ? 'png' : 'mp4';
    const filename = `noteclaw-${kind}-${id}.${extension}`;
    let storagePath: string | null = null;
    let publicUrl: string | null = null;
    let mediaData: Buffer | null = buffer;

    if (bunnyService.isConfigured()) {
        const path = bunnyService.generatePath(userId, filename, kind);
        const upload = await bunnyService.upload(buffer, path);
        if (upload.success) {
            storagePath = upload.path || path;
            publicUrl = upload.cdnUrl || null;
            mediaData = null;
        }
    }

    await pool.query(
        `UPDATE media_generations
         SET status = 'completed', provider_result_url = $2, public_url = $3,
             storage_path = $4, media_data = $5, content_type = $6,
             filename = $7, updated_at = NOW(), completed_at = NOW()
         WHERE id = $1`,
        [id, remoteUrl, publicUrl, storagePath, mediaData, contentType, filename],
    );
}

async function markFailedAndRefund(id: string, error: unknown): Promise<void> {
    const client = await pool.connect();
    let refund: { userId: string; amount: number; feature: string } | null = null;
    try {
        await client.query('BEGIN');
        const result = await client.query(
            `SELECT user_id, kind, credits_charged, credits_refunded
             FROM media_generations WHERE id = $1 FOR UPDATE`,
            [id],
        );
        if (result.rows.length === 0) {
            await client.query('ROLLBACK');
            return;
        }
        const row = result.rows[0];
        const amount = Number(row.credits_charged || 0);
        const shouldRefund = !row.credits_refunded && amount > 0;
        await client.query(
            `UPDATE media_generations
             SET status = 'failed', error = $2,
                 credits_refunded = CASE WHEN $3 THEN TRUE ELSE credits_refunded END,
                 updated_at = NOW()
             WHERE id = $1`,
            [id, providerErrorMessage(error).slice(0, 2000), shouldRefund],
        );
        await client.query('COMMIT');

        if (shouldRefund) {
            refund = { userId: row.user_id, amount, feature: `${row.kind}_generation` };
            await refundCredits(refund.userId, refund.amount, refund.feature, {
                generationId: id,
                reason: providerErrorMessage(error),
            });
        }
    } catch (failure) {
        await client.query('ROLLBACK').catch(() => undefined);
        if (refund) {
            await pool.query(
                'UPDATE media_generations SET credits_refunded = FALSE, updated_at = NOW() WHERE id = $1',
                [id],
            ).catch(() => undefined);
        }
        console.error('[MediaGeneration] Failed to mark/refund generation:', failure);
    } finally {
        client.release();
    }
}

async function pollVideoUntilFinished(
    id: string,
    providerTaskId: string,
    provider: AlibabaMediaProvider,
    attempts = 80,
): Promise<void> {
    const { apiKey, baseUrl } = await getProviderConfig(provider);
    for (let attempt = 0; attempt < attempts; attempt += 1) {
        const response = await axios.get(`${baseUrl}/api/v1/tasks/${encodeURIComponent(providerTaskId)}`, {
            timeout: 30000,
            headers: { Authorization: `Bearer ${apiKey}` },
        });
        const status = String(response.data?.output?.task_status || '').toUpperCase();
        if (status === 'SUCCEEDED') {
            const url = extractVideoUrl(response.data);
            if (!url) throw new Error('Alibaba completed the video task without a download URL.');
            await persistRemoteMedia(id, (await pool.query('SELECT user_id FROM media_generations WHERE id = $1', [id])).rows[0].user_id, 'video', url);
            return;
        }
        if (status === 'FAILED' || status === 'CANCELED' || status === 'UNKNOWN') {
            throw new Error(response.data?.output?.message || `Alibaba video task ${status.toLowerCase()}.`);
        }
        if (attempt < attempts - 1) {
            await new Promise((resolve) => setTimeout(resolve, 15000));
        }
    }
    throw new Error('Alibaba video generation timed out.');
}

export async function startMediaGeneration(userId: string, input: StartGenerationInput): Promise<MediaGenerationRecord> {
    const prompt = input.prompt?.trim();
    if (!prompt || prompt.length > 5000) throw new Error('Prompt must contain between 1 and 5000 characters.');
    const requestedProvider = normalizeRequestedProvider(input.provider);
    const model = resolveModel(input.kind, input.model, requestedProvider);
    const provider = await resolveProvider(input.kind, model, input.provider);
    const feature = `${input.kind}_generation` as MeteredCreditFeature;
    const credits = await getFeatureCreditCost(feature);
    const charge = await consumeCredits(userId, credits, feature, {
        model,
        provider,
        kind: input.kind,
    });
    if (!charge.success) {
        const error = new Error(charge.error || 'Unable to deduct generation credits') as Error & { status?: number };
        error.status = charge.error === 'Insufficient credits' ? 402 : 400;
        throw error;
    }

    const inserted = await pool.query(
        `INSERT INTO media_generations
         (user_id, kind, provider, model, prompt, status, credits_charged, parameters)
         VALUES ($1, $2, $3, $4, $5, 'processing', $6, $7)
         RETURNING *`,
        [userId, input.kind, provider, model, prompt, credits, JSON.stringify({ size: input.size, duration: input.duration })],
    ).catch(async (error) => {
        if (credits > 0) await refundCredits(userId, credits, feature, { reason: 'generation record failed' });
        throw error;
    });
    const id = inserted.rows[0].id;

    try {
        const { apiKey, baseUrl } = await getProviderConfig(provider);
        if (input.kind === 'image') {
            const response = await axios.post(
                `${baseUrl}/api/v1/services/aigc/multimodal-generation/generation`,
                {
                    model,
                    input: { messages: [{ role: 'user', content: [{ text: prompt }] }] },
                    parameters: { size: normalizeSize('image', input.size) },
                },
                { timeout: 180000, headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' } },
            );
            const url = extractImageUrl(response.data);
            if (!url) throw new Error('Alibaba returned no generated image URL.');
            await persistRemoteMedia(id, userId, 'image', url);
        } else {
            const duration = Number.isInteger(input.duration) && Number(input.duration) >= 2 && Number(input.duration) <= 15
                ? Number(input.duration)
                : 5;
            const normalizedVideoSize = normalizeSize('video', input.size);
            const parameters = provider === ALIBABA_TOKEN_PLAN_PROVIDER
                ? tokenPlanVideoParameters(normalizedVideoSize, duration)
                : {
                    size: normalizedVideoSize,
                    duration,
                    prompt_extend: true,
                };
            const response = await axios.post(
                `${baseUrl}/api/v1/services/aigc/video-generation/video-synthesis`,
                {
                    model,
                    input: { prompt },
                    parameters,
                },
                {
                    timeout: 60000,
                    headers: {
                        Authorization: `Bearer ${apiKey}`,
                        'Content-Type': 'application/json',
                        'X-DashScope-Async': 'enable',
                    },
                },
            );
            const taskId = response.data?.output?.task_id;
            if (typeof taskId !== 'string' || !taskId) throw new Error('Alibaba returned no video task ID.');
            await pool.query(
                'UPDATE media_generations SET provider_task_id = $2, updated_at = NOW() WHERE id = $1',
                [id, taskId],
            );
            setImmediate(() => pollVideoUntilFinished(id, taskId, provider).catch((error) => markFailedAndRefund(id, error)));
        }
    } catch (error) {
        await markFailedAndRefund(id, error);
        throw error;
    }

    return getMediaGeneration(userId, id, false) as Promise<MediaGenerationRecord>;
}

export async function getMediaGeneration(userId: string, id: string, refresh = true): Promise<MediaGenerationRecord | null> {
    let result = await pool.query('SELECT * FROM media_generations WHERE id = $1 AND user_id = $2', [id, userId]);
    if (result.rows.length === 0) return null;
    const row = result.rows[0];
    if (refresh && row.kind === 'video' && row.status === 'processing' && row.provider_task_id) {
        try {
            await pollVideoUntilFinished(
                id,
                row.provider_task_id,
                normalizeRequestedProvider(row.provider) || MODEL_STUDIO_PROVIDER,
                1,
            );
        } catch (error) {
            const message = providerErrorMessage(error);
            if (!message.includes('timed out')) await markFailedAndRefund(id, error);
        }
        result = await pool.query('SELECT * FROM media_generations WHERE id = $1 AND user_id = $2', [id, userId]);
    }
    return serialize(result.rows[0]);
}

export async function listMediaGenerations(userId: string, limit = 50): Promise<MediaGenerationRecord[]> {
    const result = await pool.query(
        'SELECT * FROM media_generations WHERE user_id = $1 ORDER BY created_at DESC LIMIT $2',
        [userId, Math.min(Math.max(limit, 1), 100)],
    );
    return result.rows.map(serialize);
}

export async function getMediaGenerationDownload(userId: string, id: string): Promise<any | null> {
    const result = await pool.query(
        `SELECT id, status, public_url, provider_result_url, storage_path,
                media_data, content_type, filename
         FROM media_generations WHERE id = $1 AND user_id = $2`,
        [id, userId],
    );
    return result.rows[0] || null;
}
