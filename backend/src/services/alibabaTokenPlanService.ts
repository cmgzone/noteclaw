import axios from 'axios';
import pool from '../config/database.js';
import { decryptSecretAllowLegacy } from './secretEncryptionService.js';
import type { ChatMessage } from './aiService.js';

export const ALIBABA_TOKEN_PLAN_PROVIDER = 'alibaba_token_plan';
export const ALIBABA_TOKEN_PLAN_BASE_URL =
    'https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1';

type AlibabaModelPayload = {
    data?: Array<string | { id?: unknown }>;
};

function normalizeMessages(messages: ChatMessage[]) {
    return messages.map((message) => ({
        role: message.role === 'model' ? 'assistant' : message.role,
        content: message.content,
    }));
}

function providerErrorMessage(error: unknown): string {
    if (axios.isAxiosError(error)) {
        const body = error.response?.data as {
            error?: { message?: string };
            message?: string;
            code?: string;
        } | undefined;
        const message = body?.error?.message || body?.message || error.message;
        const code = body?.code ? `${body.code}: ` : '';
        return `${code}${message}`;
    }
    return error instanceof Error ? error.message : 'Unknown provider error';
}

export function parseAlibabaTokenPlanModelIds(payload: unknown): string[] {
    const data = (payload as AlibabaModelPayload | null)?.data;
    if (!Array.isArray(data)) return [];

    return [...new Set(
        data
            .map((item) => {
                if (typeof item === 'string') return item.trim();
                return typeof item?.id === 'string' ? item.id.trim() : '';
            })
            .filter((id) => id.length > 0 && id.length <= 200),
    )].sort((left, right) => left.localeCompare(right));
}

export function formatAlibabaModelName(modelId: string): string {
    return modelId
        .replace(/[-_.]+/g, ' ')
        .replace(/\b\w/g, (character) => character.toUpperCase());
}

export function validateAlibabaTokenPlanApiKey(apiKey: string): string {
    const normalized = apiKey.trim();
    if (!normalized.startsWith('sk-sp-')) {
        throw new Error('Alibaba Token Plan API keys must start with sk-sp-.');
    }
    return normalized;
}

export async function fetchAlibabaTokenPlanModels(apiKey: string): Promise<string[]> {
    const normalizedKey = validateAlibabaTokenPlanApiKey(apiKey);

    try {
        const response = await axios.get(`${ALIBABA_TOKEN_PLAN_BASE_URL}/models`, {
            timeout: 20000,
            headers: {
                Authorization: `Bearer ${normalizedKey}`,
                Accept: 'application/json',
            },
        });
        const modelIds = parseAlibabaTokenPlanModelIds(response.data);
        if (modelIds.length === 0) {
            throw new Error('Alibaba returned an empty model list for this Token Plan key.');
        }
        return modelIds;
    } catch (error) {
        if (error instanceof Error && error.message.includes('empty model list')) {
            throw error;
        }
        throw new Error(`Alibaba Token Plan model discovery failed: ${providerErrorMessage(error)}`);
    }
}

export async function syncAlibabaTokenPlanModels(modelIds: string[]): Promise<{
    synced: number;
    disabled: number;
}> {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');
        const disabledResult = await client.query(
            `UPDATE ai_models
             SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
             WHERE provider = $1 AND is_active = TRUE`,
            [ALIBABA_TOKEN_PLAN_PROVIDER],
        );

        for (const modelId of modelIds) {
            const updated = await client.query(
                `UPDATE ai_models
                 SET name = $3,
                     description = $4,
                     is_active = TRUE,
                     updated_at = CURRENT_TIMESTAMP
                 WHERE provider = $1 AND model_id = $2
                 RETURNING id`,
                [
                    ALIBABA_TOKEN_PLAN_PROVIDER,
                    modelId,
                    formatAlibabaModelName(modelId),
                    'Fetched from Alibaba Cloud Model Studio Token Plan (Singapore).',
                ],
            );

            if (updated.rows.length === 0) {
                await client.query(
                    `INSERT INTO ai_models (
                        name, model_id, provider, description,
                        cost_input, cost_output, context_window,
                        is_active, is_premium, is_default
                     ) VALUES ($1, $2, $3, $4, 0, 0, 0, TRUE, FALSE, FALSE)`,
                    [
                        formatAlibabaModelName(modelId),
                        modelId,
                        ALIBABA_TOKEN_PLAN_PROVIDER,
                        'Fetched from Alibaba Cloud Model Studio Token Plan (Singapore).',
                    ],
                );
            }
        }

        await client.query('COMMIT');
        return {
            synced: modelIds.length,
            disabled: disabledResult.rowCount || 0,
        };
    } catch (error) {
        await client.query('ROLLBACK');
        throw error;
    } finally {
        client.release();
    }
}

export async function getAlibabaTokenPlanApiKey(): Promise<string> {
    const stored = await pool.query<{ encrypted_value: string }>(
        `SELECT encrypted_value
         FROM api_keys
         WHERE service_name = $1
         LIMIT 1`,
        [ALIBABA_TOKEN_PLAN_PROVIDER],
    );

    if (stored.rows[0]?.encrypted_value) {
        return validateAlibabaTokenPlanApiKey(
            decryptSecretAllowLegacy(stored.rows[0].encrypted_value),
        );
    }

    const environmentKey = process.env.ALIBABA_TOKEN_PLAN_API_KEY?.trim() || '';
    if (environmentKey) return validateAlibabaTokenPlanApiKey(environmentKey);

    throw new Error('Alibaba Token Plan API key is not configured in the admin settings.');
}

export async function generateWithAlibabaTokenPlan(
    messages: ChatMessage[],
    model: string,
    maxTokens = 4096,
    apiKeyOverride?: string,
): Promise<string> {
    const apiKey = apiKeyOverride?.trim()
        ? validateAlibabaTokenPlanApiKey(apiKeyOverride)
        : await getAlibabaTokenPlanApiKey();

    try {
        const response = await axios.post(
            `${ALIBABA_TOKEN_PLAN_BASE_URL}/chat/completions`,
            {
                model,
                messages: normalizeMessages(messages),
                max_tokens: maxTokens,
            },
            {
                timeout: 120000,
                headers: {
                    Authorization: `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                },
            },
        );

        const content = response.data?.choices?.[0]?.message?.content;
        if (typeof content !== 'string' || content.length === 0) {
            throw new Error('Alibaba returned no message content.');
        }
        return content;
    } catch (error) {
        throw new Error(`Alibaba Token Plan API error: ${providerErrorMessage(error)}`);
    }
}

export async function* streamWithAlibabaTokenPlan(
    messages: ChatMessage[],
    model: string,
    maxTokens = 4096,
    apiKeyOverride?: string,
): AsyncGenerator<string> {
    const apiKey = apiKeyOverride?.trim()
        ? validateAlibabaTokenPlanApiKey(apiKeyOverride)
        : await getAlibabaTokenPlanApiKey();

    try {
        const response = await axios.post(
            `${ALIBABA_TOKEN_PLAN_BASE_URL}/chat/completions`,
            {
                model,
                messages: normalizeMessages(messages),
                max_tokens: maxTokens,
                stream: true,
            },
            {
                timeout: 120000,
                responseType: 'stream',
                headers: {
                    Authorization: `Bearer ${apiKey}`,
                    'Content-Type': 'application/json',
                    Accept: 'text/event-stream',
                },
            },
        );

        let buffer = '';
        for await (const chunk of response.data) {
            buffer += chunk.toString();
            const lines = buffer.split('\n');
            buffer = lines.pop() || '';

            for (const rawLine of lines) {
                const line = rawLine.trim();
                if (!line.startsWith('data:')) continue;
                const data = line.slice(5).trim();
                if (!data || data === '[DONE]') continue;

                try {
                    const parsed = JSON.parse(data);
                    const content = parsed?.choices?.[0]?.delta?.content;
                    if (typeof content === 'string' && content.length > 0) {
                        yield content;
                    }
                } catch {
                    // A partial JSON record remains buffered until the next chunk.
                }
            }
        }
    } catch (error) {
        throw new Error(`Alibaba Token Plan streaming error: ${providerErrorMessage(error)}`);
    }
}
