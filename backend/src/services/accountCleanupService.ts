import type { PoolClient } from 'pg';

const isSafeSqlIdentifier = (value: string): boolean => /^[a-z_][a-z0-9_]*$/i.test(value);

const quoteSqlIdentifier = (value: string): string => {
    if (!isSafeSqlIdentifier(value)) {
        throw new Error(`Unsafe SQL identifier: ${value}`);
    }
    return `"${value}"`;
};

async function tableHasColumn(
    client: PoolClient,
    tableName: string,
    columnName: string,
): Promise<boolean> {
    const result = await client.query(`
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1 AND column_name = $2
        LIMIT 1
    `, [tableName, columnName]);

    return result.rows.length > 0;
}

async function deleteRowsByUserIdIfTableExists(
    client: PoolClient,
    tableName: string,
    userId: string,
): Promise<void> {
    if (!(await tableHasColumn(client, tableName, 'user_id'))) {
        return;
    }

    await client.query(
        `DELETE FROM ${quoteSqlIdentifier(tableName)} WHERE user_id = $1`,
        [userId],
    );
}

export async function cleanupTextUserTablesForDeletedAccount(
    client: PoolClient,
    userId: string,
): Promise<void> {
    if (await tableHasColumn(client, 'api_tokens', 'user_id')) {
        if (await tableHasColumn(client, 'token_usage_logs', 'token_id')) {
            await client.query(
                'DELETE FROM token_usage_logs WHERE token_id IN (SELECT id FROM api_tokens WHERE user_id = $1)',
                [userId],
            );
        }

        await client.query('DELETE FROM api_tokens WHERE user_id = $1', [userId]);
    }

    const directDeleteTables = [
        'file_audit_logs',
        'gmail_connections',
        'agent_memory_entries',
        'agent_sessions',
        'media_uploads',
        'research_jobs',
        'agent_skills',
        'user_ai_models',
    ];

    for (const tableName of directDeleteTables) {
        await deleteRowsByUserIdIfTableExists(client, tableName, userId);
    }
}
