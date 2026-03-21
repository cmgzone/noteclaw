import pool from '../config/database.js';
import {
    DEFAULT_PRIVACY_POLICY_MARKDOWN,
    DEFAULT_TERMS_OF_SERVICE_MARKDOWN,
} from '../content/legalDocuments.js';

async function getAppSettingsColumns(): Promise<Set<string>> {
    const result = await pool.query(`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'app_settings'
    `);

    return new Set(result.rows.map((row: { column_name: string }) => row.column_name));
}

type AppSettingDocumentKey = 'privacy_policy' | 'terms_of_service';

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

    const result = await pool.query(query, [settingKey]);
    return result.rows[0]?.content ?? null;
}

async function setAppSettingContent(settingKey: AppSettingDocumentKey, content: string): Promise<void> {
    const columns = await getAppSettingsColumns();
    assertAppSettingsContentColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    if (hasValue && hasContent) {
        await pool.query(`
            INSERT INTO app_settings (key, value, content, updated_at)
            VALUES ($1, $2, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, content = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    if (hasValue) {
        await pool.query(`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ($1, $2, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $2, updated_at = CURRENT_TIMESTAMP
        `, [settingKey, content]);
        return;
    }

    await pool.query(`
        INSERT INTO app_settings (key, content, updated_at)
        VALUES ($1, $2, CURRENT_TIMESTAMP)
        ON CONFLICT (key)
        DO UPDATE SET content = $2, updated_at = CURRENT_TIMESTAMP
    `, [settingKey, content]);
}

export async function getPrivacyPolicyContent(): Promise<string> {
    const content = (await getAppSettingContent('privacy_policy'))?.trim();
    return content || DEFAULT_PRIVACY_POLICY_MARKDOWN;
}

export async function setPrivacyPolicyContent(content: string): Promise<void> {
    await setAppSettingContent('privacy_policy', content);
}

export async function getTermsOfServiceContent(): Promise<string> {
    const content = (await getAppSettingContent('terms_of_service'))?.trim();
    return content || DEFAULT_TERMS_OF_SERVICE_MARKDOWN;
}

export async function setTermsOfServiceContent(content: string): Promise<void> {
    await setAppSettingContent('terms_of_service', content);
}
