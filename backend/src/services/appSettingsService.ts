import pool, { queryWithRetry } from '../config/database.js';
import {
    DEFAULT_PRIVACY_POLICY_MARKDOWN,
    DEFAULT_TERMS_OF_SERVICE_MARKDOWN,
} from '../content/legalDocuments.js';

async function runAppSettingsQuery(queryText: string, params?: unknown[]) {
    return queryWithRetry(() => pool.query(queryText, params));
}

async function getAppSettingsColumns(): Promise<Set<string>> {
    const result = await runAppSettingsQuery(`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'app_settings'
    `);

    return new Set(result.rows.map((row: { column_name: string }) => row.column_name));
}

type AppSettingDocumentKey = 'privacy_policy' | 'terms_of_service';

function isTransientDatabaseError(error: unknown): boolean {
    if (!error || typeof error !== 'object') {
        return false;
    }

    const code = 'code' in error ? String((error as { code?: unknown }).code ?? '') : '';
    return ['ECONNRESET', 'ETIMEDOUT', 'ENOTFOUND'].includes(code);
}

function assertAppSettingsContentColumns(columns: Set<string>) {
    if (!columns.has('value') && !columns.has('content')) {
        throw new Error('app_settings is missing both value and content columns');
    }
}

async function getAppSettingContent(settingKey: AppSettingDocumentKey): Promise<string | null> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    const query = hasValue && hasContent
        ? 'SELECT COALESCE(NULLIF(value, \'\'), content) AS content FROM app_settings WHERE key = $1'
        : hasValue
            ? 'SELECT value AS content FROM app_settings WHERE key = $1'
            : 'SELECT content AS content FROM app_settings WHERE key = $1';

    const result = await runAppSettingsQuery(query, [settingKey]);
    return result.rows[0]?.content ?? null;
}

async function getRawAppSettingContent(settingKey: string): Promise<string | null> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    const query = hasValue && hasContent
        ? 'SELECT COALESCE(NULLIF(value, \'\'), content) AS content FROM app_settings WHERE key = $1'
        : hasValue
            ? 'SELECT value AS content FROM app_settings WHERE key = $1'
            : 'SELECT content AS content FROM app_settings WHERE key = $1';

    const result = await runAppSettingsQuery(query, [settingKey]);
    return result.rows[0]?.content ?? null;
}

async function setAppSettingContent(settingKey: AppSettingDocumentKey, content: string): Promise<void> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    if (hasValue && hasContent) {
        await runAppSettingsQuery(`
            INSERT INTO app_settings (key, value, content, updated_at)
            VALUES ($1, $2, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, content = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    if (hasValue) {
        await runAppSettingsQuery(`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    await runAppSettingsQuery(`
        INSERT INTO app_settings (key, content, updated_at)
        VALUES ($1, $2, CURRENT_TIMESTAMP)
        ON CONFLICT (key)
        DO UPDATE SET content = $2, updated_at = CURRENT_TIMESTAMP
    `, [settingKey, content]);
}

async function setRawAppSettingContent(settingKey: string, content: string): Promise<void> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    if (hasValue && hasContent) {
        await runAppSettingsQuery(`
            INSERT INTO app_settings (key, value, content, updated_at)
            VALUES ($1, $2, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, content = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    if (hasValue) {
        await runAppSettingsQuery(`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    await runAppSettingsQuery(`
        INSERT INTO app_settings (key, content, updated_at)
        VALUES ($1, $2, CURRENT_TIMESTAMP)
        ON CONFLICT (key)
        DO UPDATE SET content = $2, updated_at = CURRENT_TIMESTAMP
    `, [settingKey, content]);
}

export async function getAppSettingValue(settingKey: string): Promise<string | null> {
    const content = await getRawAppSettingContent(settingKey);
    return typeof content === 'string' ? content : null;
}

const APP_SETTING_ENVIRONMENT_FALLBACKS: Record<string, readonly string[]> = {
    resend_from_email: ['SMTP_FROM_EMAIL', 'RESEND_FROM_EMAIL'],
    resend_from_name: ['SMTP_FROM_NAME', 'RESEND_FROM_NAME'],
    resend_reply_to_email: ['SMTP_REPLY_TO_EMAIL', 'RESEND_REPLY_TO_EMAIL'],
    public_app_url: ['PUBLIC_APP_URL', 'WEB_APP_URL'],
    require_email_verification: ['REQUIRE_EMAIL_VERIFICATION'],
    play_test_opt_in_url: ['PLAY_TEST_OPT_IN_URL'],
    play_test_group_url: ['PLAY_TEST_GROUP_URL'],
    play_test_feedback_email: ['PLAY_TEST_FEEDBACK_EMAIL', 'SMTP_REPLY_TO_EMAIL'],
};

export async function getAppSettingValueWithEnvironmentFallback(
    settingKey: string,
): Promise<string | null> {
    const storedValue = (await getAppSettingValue(settingKey))?.trim();
    if (storedValue) {
        return storedValue;
    }

    const environmentKeys = APP_SETTING_ENVIRONMENT_FALLBACKS[settingKey] ?? [];
    for (const environmentKey of environmentKeys) {
        const value = process.env[environmentKey]?.trim();
        if (value) {
            return value;
        }
    }

    return null;
}

export async function getBooleanAppSetting(
    settingKey: string,
    fallback = false,
): Promise<boolean> {
    const storedValue = (await getAppSettingValue(settingKey))?.trim();
    const environmentValue = process.env[settingKey.toUpperCase()]?.trim();
    const value = (storedValue || environmentValue)?.toLowerCase();
    if (!value) {
        return fallback;
    }

    if (['true', '1', 'yes', 'on'].includes(value)) {
        return true;
    }

    if (['false', '0', 'no', 'off'].includes(value)) {
        return false;
    }

    return fallback;
}

export async function setAppSettingValue(settingKey: string, value: string): Promise<void> {
    await setRawAppSettingContent(settingKey, value);
}

export async function getAllAppSettings(): Promise<Record<string, string>> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    const query = hasValue && hasContent
        ? 'SELECT key, COALESCE(NULLIF(value, \'\'), content, \'\') AS content FROM app_settings ORDER BY key'
        : hasValue
            ? 'SELECT key, COALESCE(value, \'\') AS content FROM app_settings ORDER BY key'
            : 'SELECT key, COALESCE(content, \'\') AS content FROM app_settings ORDER BY key';

    const result = await runAppSettingsQuery(query);
    return result.rows.reduce((acc: Record<string, string>, row: { key: string; content: string | null }) => {
        acc[row.key] = row.content ?? '';
        return acc;
    }, {});
}

export async function getPrivacyPolicyContent(): Promise<string> {
    try {
        const content = (await getAppSettingContent('privacy_policy'))?.trim();
        return content || DEFAULT_PRIVACY_POLICY_MARKDOWN;
    } catch (error) {
        if (isTransientDatabaseError(error)) {
            return DEFAULT_PRIVACY_POLICY_MARKDOWN;
        }
        throw error;
    }
}

export async function setPrivacyPolicyContent(content: string): Promise<void> {
    await setAppSettingContent('privacy_policy', content);
}

export async function getTermsOfServiceContent(): Promise<string> {
    try {
        const content = (await getAppSettingContent('terms_of_service'))?.trim();
        return content || DEFAULT_TERMS_OF_SERVICE_MARKDOWN;
    } catch (error) {
        if (isTransientDatabaseError(error)) {
            return DEFAULT_TERMS_OF_SERVICE_MARKDOWN;
        }
        throw error;
    }
}

export async function setTermsOfServiceContent(content: string): Promise<void> {
    await setAppSettingContent('terms_of_service', content);
}
