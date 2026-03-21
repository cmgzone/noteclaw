import pool from '../config/database.js';

async function getAppSettingsColumns(): Promise<Set<string>> {
    const result = await pool.query(`
        SELECT column_name
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'app_settings'
    `);

    return new Set(result.rows.map((row: { column_name: string }) => row.column_name));
}

function assertPrivacyPolicyColumns(columns: Set<string>) {
    if (!columns.has('value') && !columns.has('content')) {
        throw new Error('app_settings is missing both value and content columns');
    }
}

export async function getPrivacyPolicyContent(): Promise<string | null> {
    const columns = await getAppSettingsColumns();
    assertPrivacyPolicyColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    const query = hasValue && hasContent
        ? "SELECT COALESCE(NULLIF(value, ''), content) AS content FROM app_settings WHERE key = 'privacy_policy'"
        : hasValue
            ? "SELECT value AS content FROM app_settings WHERE key = 'privacy_policy'"
            : "SELECT content AS content FROM app_settings WHERE key = 'privacy_policy'";

    const result = await pool.query(query);
    return result.rows[0]?.content ?? null;
}

export async function setPrivacyPolicyContent(content: string): Promise<void> {
    const columns = await getAppSettingsColumns();
    assertPrivacyPolicyColumns(columns);

    const hasValue = columns.has('value');
    const hasContent = columns.has('content');

    if (hasValue && hasContent) {
        await pool.query(`
            INSERT INTO app_settings (key, value, content, updated_at)
            VALUES ('privacy_policy', $1, $1, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $1, content = $1, updated_at = CURRENT_TIMESTAMP
        `, [content]);
        return;
    }

    if (hasValue) {
        await pool.query(`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ('privacy_policy', $1, CURRENT_TIMESTAMP)
            ON CONFLICT (key)
            DO UPDATE SET value = $1, updated_at = CURRENT_TIMESTAMP
        `, [content]);
        return;
    }

    await pool.query(`
        INSERT INTO app_settings (key, content, updated_at)
        VALUES ('privacy_policy', $1, CURRENT_TIMESTAMP)
        ON CONFLICT (key)
        DO UPDATE SET content = $1, updated_at = CURRENT_TIMESTAMP
    `, [content]);
}
