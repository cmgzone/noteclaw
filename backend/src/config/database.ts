import { Pool as PgPool } from 'pg';
import { Pool as NeonPool, neonConfig } from '@neondatabase/serverless';
import { readFile } from 'node:fs/promises';
import dotenv from 'dotenv';
import ws from 'ws';

dotenv.config();

// Build connection string from environment variables
const connectionString = process.env.DATABASE_URL ||
    `postgresql://${process.env.NEON_USERNAME}:${process.env.NEON_PASSWORD}@${process.env.NEON_HOST}:${process.env.NEON_PORT || 5432}/${process.env.NEON_DATABASE}?sslmode=require`;

const isNeonConnection = connectionString.includes('.neon.tech');
const shouldUseSsl =
    process.env.DATABASE_SSL === 'true' ||
    (process.env.DATABASE_SSL !== 'false' && isNeonConnection);
const shouldUseNeonServerless =
    process.env.DATABASE_USE_NEON_SERVERLESS === 'true' ||
    (process.env.DATABASE_USE_NEON_SERVERLESS !== 'false' &&
        process.env.NODE_ENV !== 'production' &&
        isNeonConnection);

const pool: PgPool = shouldUseNeonServerless
    ? (() => {
        neonConfig.webSocketConstructor = ws;
        return new NeonPool({
            connectionString,
            max: 10,
            idleTimeoutMillis: 30000,
            connectionTimeoutMillis: 30000,
            query_timeout: 60000,
        }) as unknown as PgPool;
    })()
    : new PgPool({
        connectionString,
        ssl: shouldUseSsl ? { rejectUnauthorized: false } : false,
        max: 20,
        idleTimeoutMillis: 30000,
        connectionTimeoutMillis: 60000, // Increased to 60s for Neon cold starts and heavy operations
        // Keep connections alive
        keepAlive: true,
        keepAliveInitialDelayMillis: 10000,
        // Query timeout for long-running operations
        query_timeout: 60000, // 60 seconds
    });

(globalThis as any).__noteClawPgPool = pool;

const shouldLogDbEvents = !(process.env.NODE_ENV === 'test' || process.env.JEST_WORKER_ID);
let hasLoggedDbConnect = false;

// Helper function to execute query with retry for connection issues
export async function queryWithRetry<T>(
    queryFn: () => Promise<T>,
    maxRetries: number = 3
): Promise<T> {
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
            return await queryFn();
        } catch (error: any) {
            lastError = error;
            const isConnectionError =
                error.message?.includes('Connection terminated') ||
                error.message?.includes('connection timeout') ||
                error.code === 'ENOTFOUND' ||
                error.code === 'ECONNRESET' ||
                error.code === 'ETIMEDOUT';

            if (!isConnectionError || attempt === maxRetries) {
                throw error;
            }

            if (shouldLogDbEvents) {
                console.log(`Database connection attempt ${attempt}/${maxRetries} failed, retrying...`);
            }
            await new Promise(resolve => setTimeout(resolve, 1000 * attempt));
        }
    }

    throw lastError;
}

// Test the connection
if (shouldLogDbEvents) {
    console.log(
        `🗄️ Database driver: ${shouldUseNeonServerless ? 'neon-serverless' : 'pg'}`
    );
    pool.on('connect', () => {
        if (!hasLoggedDbConnect) {
            hasLoggedDbConnect = true;
            console.log('✅ Connected to Neon database');
        }
    });
}

pool.on('error', (err) => {
    console.error('❌ Unexpected error on idle client', err);
});

// Initialize database tables
export async function initializeDatabase() {
    const client = await pool.connect();
    try {
        console.log('🔧 Initializing database tables...');

        await client.query('CREATE EXTENSION IF NOT EXISTS vector');

        // Core tables - split into smaller chunks
        await client.query(`
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                email TEXT UNIQUE NOT NULL,
                display_name TEXT,
                password_hash TEXT NOT NULL,
                password_salt TEXT,
                email_verified BOOLEAN DEFAULT false,
                two_factor_enabled BOOLEAN DEFAULT false,
                avatar_url TEXT,
                cover_url TEXT,
                role TEXT DEFAULT 'user',
                is_active BOOLEAN DEFAULT true,
                reset_token TEXT,
                reset_token_expiry TIMESTAMPTZ,
                verification_token TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS notebooks (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                description TEXT,
                cover_image TEXT,
                category TEXT DEFAULT 'General',
                is_agent_notebook BOOLEAN DEFAULT false,
                agent_session_id TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS sources (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                notebook_id UUID NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
                user_id TEXT,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                content TEXT,
                url TEXT,
                image_url TEXT,
                mime_type TEXT,
                metadata JSONB NOT NULL DEFAULT '{}',
                summary TEXT,
                media_data BYTEA,
                media_url TEXT,
                media_path TEXT,
                media_size BIGINT,
                code_analysis JSONB,
                analysis_summary TEXT,
                analysis_rating SMALLINT,
                analyzed_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Keep databases created by older NoteClaw versions compatible with
        // every current source reader. CREATE TABLE IF NOT EXISTS does not add
        // columns to an existing table, so fresh deployments upgraded from the
        // original core schema otherwise fail when memory notebooks are opened.
        await client.query(`
            ALTER TABLE sources
                ADD COLUMN IF NOT EXISTS user_id TEXT,
                ADD COLUMN IF NOT EXISTS image_url TEXT,
                ADD COLUMN IF NOT EXISTS mime_type TEXT,
                ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}',
                ADD COLUMN IF NOT EXISTS summary TEXT,
                ADD COLUMN IF NOT EXISTS media_url TEXT,
                ADD COLUMN IF NOT EXISTS media_path TEXT,
                ADD COLUMN IF NOT EXISTS media_size BIGINT,
                ADD COLUMN IF NOT EXISTS code_analysis JSONB,
                ADD COLUMN IF NOT EXISTS analysis_summary TEXT,
                ADD COLUMN IF NOT EXISTS analysis_rating SMALLINT,
                ADD COLUMN IF NOT EXISTS analyzed_at TIMESTAMPTZ;

            DO $$
            DECLARE
                source_user_id_type TEXT;
            BEGIN
                SELECT data_type
                INTO source_user_id_type
                FROM information_schema.columns
                WHERE table_schema = current_schema()
                  AND table_name = 'sources'
                  AND column_name = 'user_id';

                IF source_user_id_type = 'uuid' THEN
                    UPDATE sources s
                    SET user_id = n.user_id
                    FROM notebooks n
                    WHERE s.notebook_id = n.id
                      AND s.user_id IS NULL;
                ELSE
                    UPDATE sources s
                    SET user_id = n.user_id::text
                    FROM notebooks n
                    WHERE s.notebook_id = n.id
                      AND s.user_id IS NULL;
                END IF;
            END $$;

            CREATE INDEX IF NOT EXISTS idx_sources_user_id ON sources(user_id);
            CREATE INDEX IF NOT EXISTS idx_sources_type ON sources(type);
            CREATE INDEX IF NOT EXISTS idx_sources_mime_type ON sources(mime_type);
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS chunks (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                source_id UUID NOT NULL REFERENCES sources(id) ON DELETE CASCADE,
                content_text TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                embedding VECTOR(1536),
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS tags (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                color TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS notebook_tags (
                notebook_id UUID REFERENCES notebooks(id) ON DELETE CASCADE,
                tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
                PRIMARY KEY (notebook_id, tag_id)
            );

            CREATE TABLE IF NOT EXISTS source_tags (
                source_id UUID REFERENCES sources(id) ON DELETE CASCADE,
                tag_id UUID REFERENCES tags(id) ON DELETE CASCADE,
                PRIMARY KEY (source_id, tag_id)
            );
        `);

        // Create indexes separately
        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_notebooks_user_id ON notebooks(user_id);
            CREATE INDEX IF NOT EXISTS idx_notebooks_agent ON notebooks(is_agent_notebook) WHERE is_agent_notebook = true;
            CREATE INDEX IF NOT EXISTS idx_sources_notebook_id ON sources(notebook_id);
            CREATE INDEX IF NOT EXISTS idx_chunks_source_id ON chunks(source_id);
            CREATE INDEX IF NOT EXISTS idx_tags_user_id ON tags(user_id);
        `);

        // Subscription tables - split into smaller chunks
        await client.query(`
            CREATE TABLE IF NOT EXISTS subscription_plans (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                description TEXT,
                credits_per_month INTEGER NOT NULL,
                price DECIMAL NOT NULL,
                google_play_product_id TEXT,
                notes_limit INTEGER,
                mcp_sources_limit INTEGER,
                mcp_tokens_limit INTEGER,
                mcp_api_calls_per_day INTEGER,
                is_free_plan BOOLEAN DEFAULT false,
                is_active BOOLEAN DEFAULT true,
                features JSONB DEFAULT '[]',
                feature_access JSONB NOT NULL DEFAULT '{}',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS user_subscriptions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                plan_id UUID REFERENCES subscription_plans(id),
                current_credits INTEGER DEFAULT 0,
                credits_consumed_this_month INTEGER DEFAULT 0,
                last_renewal_date TIMESTAMPTZ,
                next_renewal_date TIMESTAMPTZ,
                status TEXT NOT NULL DEFAULT 'active',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id)
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS credit_transactions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                amount INTEGER NOT NULL,
                transaction_type TEXT NOT NULL,
                description TEXT,
                balance_after INTEGER,
                metadata JSONB,
                idempotency_key TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
            CREATE UNIQUE INDEX IF NOT EXISTS idx_credit_transactions_idempotency_key
                ON credit_transactions (idempotency_key)
                WHERE idempotency_key IS NOT NULL;

            CREATE TABLE IF NOT EXISTS credit_packages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                credits INTEGER NOT NULL,
                price DECIMAL NOT NULL,
                description TEXT,
                google_play_product_id TEXT,
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // MCP quota and preference tables must be part of the normal startup
        // schema. A fresh installation can receive an MCP request before any
        // standalone migration script has been run.
        await client.query(`
            CREATE TABLE IF NOT EXISTS mcp_settings (
                id TEXT PRIMARY KEY DEFAULT 'default',
                free_sources_limit INTEGER NOT NULL DEFAULT 10,
                free_tokens_limit INTEGER NOT NULL DEFAULT 3,
                free_api_calls_per_day INTEGER NOT NULL DEFAULT 100,
                premium_sources_limit INTEGER NOT NULL DEFAULT 1000,
                premium_tokens_limit INTEGER NOT NULL DEFAULT 10,
                premium_api_calls_per_day INTEGER NOT NULL DEFAULT 10000,
                is_mcp_enabled BOOLEAN NOT NULL DEFAULT TRUE,
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                updated_by UUID REFERENCES users(id) ON DELETE SET NULL
            );

            INSERT INTO mcp_settings (
                id,
                free_sources_limit,
                free_tokens_limit,
                free_api_calls_per_day,
                premium_sources_limit,
                premium_tokens_limit,
                premium_api_calls_per_day
            )
            VALUES ('default', 10, 3, 100, 1000, 10, 10000)
            ON CONFLICT (id) DO NOTHING;

            CREATE TABLE IF NOT EXISTS user_mcp_usage (
                user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                sources_count INTEGER NOT NULL DEFAULT 0,
                api_calls_today INTEGER NOT NULL DEFAULT 0,
                last_api_call_date DATE DEFAULT CURRENT_DATE,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS mcp_user_limits (
                user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                sources_limit_override INTEGER,
                tokens_limit_override INTEGER,
                api_calls_per_day_override INTEGER,
                is_mcp_enabled_override BOOLEAN,
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                updated_by UUID REFERENCES users(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS mcp_user_settings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
                code_analysis_model_id TEXT,
                code_analysis_enabled BOOLEAN DEFAULT TRUE,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE INDEX IF NOT EXISTS idx_user_mcp_usage_user
                ON user_mcp_usage(user_id);
            CREATE INDEX IF NOT EXISTS idx_mcp_user_limits_updated_at
                ON mcp_user_limits(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_mcp_user_settings_user_id
                ON mcp_user_settings(user_id);
        `);

        await client.query(`
            ALTER TABLE subscription_plans
                ADD COLUMN IF NOT EXISTS description TEXT;
            ALTER TABLE credit_packages
                ADD COLUMN IF NOT EXISTS description TEXT;
        `);

        const freePlanFeatures = JSON.stringify({
            memory_bank: true,
            notebook_chat: true,
            websocket_collaboration: true,
            code_review: false,
            web_search: false,
            deep_research: false,
            research_save_to_notebook: false,
        });
        const paidPlanFeatures = JSON.stringify({
            memory_bank: true,
            notebook_chat: true,
            websocket_collaboration: true,
            code_review: true,
            web_search: true,
            deep_research: true,
            research_save_to_notebook: true,
        });
        const planCount = await client.query(
            'SELECT COUNT(*)::int AS count FROM subscription_plans',
        );
        if (planCount.rows[0].count === 0) {
            await client.query(
                `INSERT INTO subscription_plans (
                    name, description, credits_per_month, price, is_free_plan,
                    google_play_product_id, notes_limit, mcp_sources_limit,
                    mcp_tokens_limit, mcp_api_calls_per_day, feature_access
                 ) VALUES
                    ('Free', 'Core memory and agent collaboration', 50, 0, TRUE,
                     NULL, 100, 10, 3, 100, $1::jsonb),
                    ('Pro', 'Advanced agent tools and research', 1000, 9.99, FALSE,
                     'noteclaw_pro_monthly', 1000, 200, 10, 2000, $2::jsonb),
                    ('Ultra', 'Highest limits for agent teams', 5000, 29.99, FALSE,
                     'noteclaw_ultra_monthly', 10000, 1000, 25, 10000, $2::jsonb)`,
                [freePlanFeatures, paidPlanFeatures],
            );
        }

        const packageCount = await client.query(
            'SELECT COUNT(*)::int AS count FROM credit_packages',
        );
        if (packageCount.rows[0].count === 0) {
            await client.query(`
                INSERT INTO credit_packages (
                    name, credits, price, google_play_product_id
                ) VALUES
                    ('Starter Pack', 100, 1.99, 'noteclaw_credits_starter'),
                    ('Value Pack', 500, 7.99, 'noteclaw_credits_value'),
                    ('Pro Pack', 2000, 24.99, 'noteclaw_credits_pro'),
                    ('Ultimate Pack', 10000, 99.99, 'noteclaw_credits_ultimate')
            `);
        }

        // Admin-managed catalog and settings tables.
        await client.query(`
            CREATE TABLE IF NOT EXISTS ai_models (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                model_id TEXT NOT NULL,
                provider TEXT NOT NULL,
                description TEXT,
                cost_input DECIMAL DEFAULT 0,
                cost_output DECIMAL DEFAULT 0,
                context_window INTEGER DEFAULT 0,
                is_active BOOLEAN DEFAULT true,
                is_premium BOOLEAN DEFAULT false,
                is_default BOOLEAN DEFAULT false,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS api_keys (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                service_name TEXT UNIQUE NOT NULL,
                encrypted_value TEXT NOT NULL,
                description TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS onboarding_screens (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                title TEXT NOT NULL,
                description TEXT,
                image_url TEXT,
                icon_name TEXT,
                sort_order INTEGER DEFAULT 0,
                order_index INTEGER DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS app_settings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                key TEXT UNIQUE NOT NULL,
                content TEXT,
                value TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS feature_credit_costs (
                feature_key TEXT PRIMARY KEY,
                credit_cost INTEGER NOT NULL CHECK (credit_cost >= 0),
                updated_by UUID REFERENCES users(id) ON DELETE SET NULL,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
        `);

        await client.query(`
            ALTER TABLE ai_models
            ADD COLUMN IF NOT EXISTS capabilities JSONB NOT NULL DEFAULT '["text"]'::jsonb
        `);
        await client.query(`
            UPDATE ai_models
            SET capabilities = CASE
                WHEN model_id ILIKE '%t2v%' OR model_id ILIKE '%i2v%' OR model_id ILIKE '%video%'
                    THEN '["video"]'::jsonb
                WHEN model_id ILIKE '%image%'
                    THEN '["image"]'::jsonb
                WHEN model_id ILIKE '%audio%' OR model_id ILIKE '%tts%' OR model_id ILIKE '%asr%'
                    THEN '["audio"]'::jsonb
                ELSE capabilities
            END,
            updated_at = NOW()
            WHERE provider = 'alibaba_token_plan'
              AND capabilities = '["text"]'::jsonb
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS research_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                query TEXT NOT NULL,
                report TEXT,
                summary TEXT,
                insights JSONB,
                source_count INTEGER DEFAULT 0,
                depth VARCHAR(20) DEFAULT 'standard',
                template VARCHAR(50) DEFAULT 'general',
                status VARCHAR(20) DEFAULT 'completed',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                completed_at TIMESTAMPTZ
            );

            CREATE TABLE IF NOT EXISTS research_sources (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                session_id UUID NOT NULL REFERENCES research_sessions(id) ON DELETE CASCADE,
                url TEXT NOT NULL,
                title TEXT,
                content TEXT,
                snippet TEXT,
                credibility VARCHAR(20) DEFAULT 'unknown',
                credibility_score INTEGER DEFAULT 60,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS research_jobs (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                query TEXT NOT NULL,
                config JSONB NOT NULL DEFAULT '{}',
                status VARCHAR(20) NOT NULL DEFAULT 'pending',
                status_message TEXT,
                progress DECIMAL(4,3) DEFAULT 0,
                session_id UUID REFERENCES research_sessions(id) ON DELETE SET NULL,
                error TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                completed_at TIMESTAMPTZ
            );

            CREATE INDEX IF NOT EXISTS idx_research_sessions_user_id ON research_sessions(user_id);
            CREATE INDEX IF NOT EXISTS idx_research_sources_session_id ON research_sources(session_id);
            CREATE INDEX IF NOT EXISTS idx_research_jobs_user_status ON research_jobs(user_id, status);
        `);

        await client.query(`
            ALTER TABLE research_sessions ADD COLUMN IF NOT EXISTS report TEXT;
            ALTER TABLE research_sessions ADD COLUMN IF NOT EXISTS depth VARCHAR(20) DEFAULT 'standard';
            ALTER TABLE research_sessions ADD COLUMN IF NOT EXISTS template VARCHAR(50) DEFAULT 'general';
            ALTER TABLE research_sessions ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'completed';
            ALTER TABLE research_sources ADD COLUMN IF NOT EXISTS snippet TEXT;
            ALTER TABLE research_sources ADD COLUMN IF NOT EXISTS credibility VARCHAR(20) DEFAULT 'unknown';
            ALTER TABLE research_sources ADD COLUMN IF NOT EXISTS credibility_score INTEGER DEFAULT 60;
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS media_generations (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                kind VARCHAR(20) NOT NULL CHECK (kind IN ('image', 'video')),
                provider TEXT NOT NULL,
                model TEXT NOT NULL,
                prompt TEXT NOT NULL,
                parameters JSONB NOT NULL DEFAULT '{}',
                status VARCHAR(20) NOT NULL DEFAULT 'pending',
                provider_task_id TEXT,
                provider_result_url TEXT,
                public_url TEXT,
                storage_path TEXT,
                media_data BYTEA,
                content_type TEXT,
                filename TEXT,
                error TEXT,
                credits_charged INTEGER NOT NULL DEFAULT 0,
                credits_refunded BOOLEAN NOT NULL DEFAULT FALSE,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                completed_at TIMESTAMPTZ
            );
            CREATE INDEX IF NOT EXISTS idx_media_generations_user_created
                ON media_generations(user_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_media_generations_task
                ON media_generations(provider_task_id);
        `);

        // Gamification tables - split into smaller chunks
        await client.query(`
            CREATE TABLE IF NOT EXISTS user_stats (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                total_xp INTEGER DEFAULT 0,
                level INTEGER DEFAULT 1,
                current_streak INTEGER DEFAULT 0,
                longest_streak INTEGER DEFAULT 0,
                notebooks_created INTEGER DEFAULT 0,
                sources_added INTEGER DEFAULT 0,
                quizzes_completed INTEGER DEFAULT 0,
                flashcards_reviewed INTEGER DEFAULT 0,
                study_time_minutes INTEGER DEFAULT 0,
                last_activity_date DATE,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS achievements (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                achievement_id TEXT NOT NULL,
                current_value INTEGER DEFAULT 0,
                is_unlocked BOOLEAN DEFAULT false,
                unlocked_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id, achievement_id)
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS daily_challenges (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT,
                target_value INTEGER NOT NULL,
                current_value INTEGER DEFAULT 0,
                is_completed BOOLEAN DEFAULT false,
                xp_reward INTEGER DEFAULT 0,
                date DATE NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id, type, date)
            );
        `);

        // Study tools tables - split into smaller chunks
        await client.query(`
            CREATE TABLE IF NOT EXISTS flashcard_decks (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS flashcards (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                deck_id UUID NOT NULL REFERENCES flashcard_decks(id) ON DELETE CASCADE,
                question TEXT NOT NULL,
                answer TEXT NOT NULL,
                difficulty TEXT DEFAULT 'medium',
                times_reviewed INTEGER DEFAULT 0,
                times_correct INTEGER DEFAULT 0,
                last_reviewed_at TIMESTAMPTZ,
                next_review_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS quizzes (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                times_attempted INTEGER DEFAULT 0,
                last_score INTEGER,
                best_score INTEGER,
                last_attempted_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS quiz_questions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                quiz_id UUID NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
                question TEXT NOT NULL,
                options JSONB NOT NULL,
                correct_option_index INTEGER NOT NULL,
                explanation TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS mind_maps (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                root_node JSONB NOT NULL,
                text_content TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS infographics (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                image_url TEXT,
                image_base64 TEXT,
                style TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // API tokens table
        await client.query(`
            CREATE TABLE IF NOT EXISTS api_tokens (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                token_hash TEXT NOT NULL UNIQUE,
                token_prefix TEXT NOT NULL,
                token_suffix TEXT NOT NULL,
                expires_at TIMESTAMPTZ,
                last_used_at TIMESTAMPTZ,
                revoked_at TIMESTAMPTZ,
                metadata JSONB DEFAULT '{}',
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS token_usage_logs (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                token_id TEXT NOT NULL,
                endpoint TEXT NOT NULL,
                ip_address TEXT,
                user_agent TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_api_tokens_user ON api_tokens(user_id);
            CREATE INDEX IF NOT EXISTS idx_api_tokens_hash ON api_tokens(token_hash);
            CREATE INDEX IF NOT EXISTS idx_api_tokens_active ON api_tokens(user_id) WHERE revoked_at IS NULL;
        `);

        console.log('✅ API tokens tables initialized');

        await client.query(`
            CREATE TABLE IF NOT EXISTS file_audit_logs (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                action TEXT NOT NULL,
                path TEXT NOT NULL,
                success BOOLEAN DEFAULT true,
                error_message TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
            CREATE INDEX IF NOT EXISTS idx_file_audit_user ON file_audit_logs(user_id);
            CREATE INDEX IF NOT EXISTS idx_file_audit_action ON file_audit_logs(action);
        `);
        await client.query(`
            CREATE TABLE IF NOT EXISTS gmail_connections (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL UNIQUE,
                email TEXT,
                access_token TEXT NOT NULL,
                refresh_token TEXT,
                scopes TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                last_used_at TIMESTAMPTZ DEFAULT NOW()
            );
            CREATE INDEX IF NOT EXISTS idx_gmail_user ON gmail_connections(user_id);
        `);

        // Agent communication tables
        await client.query(`
            CREATE TABLE IF NOT EXISTS agent_sessions (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                user_id TEXT NOT NULL,
                agent_name TEXT NOT NULL,
                agent_identifier TEXT NOT NULL,
                webhook_url TEXT,
                webhook_secret TEXT,
                notebook_id TEXT,
                status TEXT DEFAULT 'active' CHECK (status IN ('active', 'expired', 'disconnected')),
                last_activity TIMESTAMPTZ DEFAULT NOW(),
                metadata JSONB DEFAULT '{}',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id, agent_identifier)
            );
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS source_conversations (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                source_id TEXT NOT NULL,
                agent_session_id TEXT REFERENCES agent_sessions(id) ON DELETE SET NULL,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(source_id)
            );

            CREATE TABLE IF NOT EXISTS conversation_messages (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                conversation_id TEXT NOT NULL REFERENCES source_conversations(id) ON DELETE CASCADE,
                role TEXT NOT NULL CHECK (role IN ('user', 'agent')),
                content TEXT NOT NULL,
                metadata JSONB DEFAULT '{}',
                is_read BOOLEAN DEFAULT false,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_agent_sessions_user ON agent_sessions(user_id);
            CREATE INDEX IF NOT EXISTS idx_agent_sessions_status ON agent_sessions(status);
            CREATE INDEX IF NOT EXISTS idx_agent_sessions_agent_identifier ON agent_sessions(agent_identifier);
            CREATE INDEX IF NOT EXISTS idx_source_conversations_source ON source_conversations(source_id);
            CREATE INDEX IF NOT EXISTS idx_source_conversations_agent_session ON source_conversations(agent_session_id);
            CREATE INDEX IF NOT EXISTS idx_conversation_messages_conversation ON conversation_messages(conversation_id);
            CREATE INDEX IF NOT EXISTS idx_conversation_messages_unread ON conversation_messages(conversation_id, is_read) WHERE is_read = false;
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS agent_memory_entries (
                id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
                user_id TEXT NOT NULL,
                agent_session_id TEXT NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
                namespace TEXT NOT NULL,
                memory JSONB NOT NULL DEFAULT '{}',
                version INTEGER NOT NULL DEFAULT 1,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(agent_session_id, namespace)
            );

            CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_user ON agent_memory_entries(user_id);
            CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_session ON agent_memory_entries(agent_session_id);
            CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_namespace ON agent_memory_entries(namespace);
            CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_updated ON agent_memory_entries(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_agent_memory_entries_memory_gin ON agent_memory_entries USING GIN(memory);
        `);

        await client.query(`
            CREATE TABLE IF NOT EXISTS agent_notebook_access (
                user_id TEXT NOT NULL,
                agent_session_id TEXT NOT NULL REFERENCES agent_sessions(id) ON DELETE CASCADE,
                notebook_id UUID NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
                can_read BOOLEAN NOT NULL DEFAULT TRUE,
                granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
                revoked_at TIMESTAMPTZ,
                PRIMARY KEY (agent_session_id, notebook_id)
            );

            CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_user
                ON agent_notebook_access(user_id);
            CREATE INDEX IF NOT EXISTS idx_agent_notebook_access_active
                ON agent_notebook_access(agent_session_id, notebook_id)
                WHERE revoked_at IS NULL AND can_read = TRUE;
        `);

        // GitHub integration is part of the normal application surface. Keep
        // its schema in startup initialization so fresh installations do not
        // depend on manually running legacy migration scripts.
        await client.query(`
            CREATE TABLE IF NOT EXISTS github_connections (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL UNIQUE,
                github_user_id TEXT NOT NULL,
                github_username TEXT NOT NULL,
                github_email TEXT,
                github_avatar_url TEXT,
                access_token_encrypted TEXT NOT NULL,
                refresh_token_encrypted TEXT,
                token_expires_at TIMESTAMPTZ,
                scopes TEXT[] DEFAULT ARRAY['repo', 'read:user'],
                is_active BOOLEAN DEFAULT TRUE,
                last_used_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS github_repos (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                connection_id UUID NOT NULL
                    REFERENCES github_connections(id) ON DELETE CASCADE,
                github_repo_id BIGINT NOT NULL,
                full_name TEXT NOT NULL,
                name TEXT NOT NULL,
                owner TEXT NOT NULL,
                description TEXT,
                default_branch TEXT DEFAULT 'main',
                is_private BOOLEAN DEFAULT FALSE,
                is_fork BOOLEAN DEFAULT FALSE,
                language TEXT,
                stars_count INTEGER DEFAULT 0,
                forks_count INTEGER DEFAULT 0,
                size_kb INTEGER DEFAULT 0,
                html_url TEXT,
                clone_url TEXT,
                last_synced_at TIMESTAMPTZ,
                metadata JSONB DEFAULT '{}',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(connection_id, github_repo_id)
            );

            CREATE TABLE IF NOT EXISTS github_sources (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                source_id UUID NOT NULL
                    REFERENCES sources(id) ON DELETE CASCADE,
                repo_id UUID NOT NULL
                    REFERENCES github_repos(id) ON DELETE CASCADE,
                file_path TEXT NOT NULL,
                branch TEXT DEFAULT 'main',
                commit_sha TEXT,
                file_size INTEGER,
                language TEXT,
                last_synced_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(source_id)
            );

            CREATE TABLE IF NOT EXISTS github_rate_limits (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                connection_id UUID NOT NULL
                    REFERENCES github_connections(id) ON DELETE CASCADE,
                resource TEXT NOT NULL,
                limit_value INTEGER NOT NULL,
                remaining INTEGER NOT NULL,
                reset_at TIMESTAMPTZ NOT NULL,
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(connection_id, resource)
            );

            CREATE TABLE IF NOT EXISTS github_audit_logs (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                action TEXT NOT NULL,
                owner TEXT,
                repo TEXT,
                path TEXT,
                agent_session_id TEXT
                    REFERENCES agent_sessions(id) ON DELETE SET NULL,
                success BOOLEAN DEFAULT TRUE,
                error_message TEXT,
                request_metadata JSONB DEFAULT '{}',
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS github_source_cache (
                source_id UUID PRIMARY KEY
                    REFERENCES sources(id) ON DELETE CASCADE,
                owner TEXT NOT NULL,
                repo TEXT NOT NULL,
                path TEXT NOT NULL,
                branch TEXT NOT NULL,
                commit_sha TEXT NOT NULL,
                content_hash TEXT NOT NULL,
                last_checked_at TIMESTAMPTZ DEFAULT NOW(),
                last_modified_at TIMESTAMPTZ,
                UNIQUE(owner, repo, path, branch)
            );

            CREATE INDEX IF NOT EXISTS idx_github_connections_user
                ON github_connections(user_id);
            CREATE INDEX IF NOT EXISTS idx_github_repos_connection
                ON github_repos(connection_id);
            CREATE INDEX IF NOT EXISTS idx_github_repos_full_name
                ON github_repos(full_name);
            CREATE INDEX IF NOT EXISTS idx_github_sources_source
                ON github_sources(source_id);
            CREATE INDEX IF NOT EXISTS idx_github_sources_repo
                ON github_sources(repo_id);
            CREATE INDEX IF NOT EXISTS idx_github_audit_user
                ON github_audit_logs(user_id, created_at DESC);
            CREATE INDEX IF NOT EXISTS idx_github_audit_repo
                ON github_audit_logs(owner, repo);
            CREATE INDEX IF NOT EXISTS idx_github_audit_action
                ON github_audit_logs(action);
            CREATE INDEX IF NOT EXISTS idx_github_audit_agent_session
                ON github_audit_logs(agent_session_id)
                WHERE agent_session_id IS NOT NULL;
            CREATE INDEX IF NOT EXISTS idx_github_cache_stale
                ON github_source_cache(last_checked_at);
            CREATE INDEX IF NOT EXISTS idx_github_cache_repo
                ON github_source_cache(owner, repo);
        `);

        const planningMigration = await readFile(
            new URL('../../migrations/add_planning_mode.sql', import.meta.url),
            'utf8',
        );
        await client.query(planningMigration);
        console.log('Planning mode tables initialized');

        const initialAdminEmail = process.env.INITIAL_ADMIN_EMAIL?.trim().toLowerCase();
        const initialAdminPasswordHash = process.env.INITIAL_ADMIN_PASSWORD_HASH?.trim();
        if (initialAdminEmail && initialAdminPasswordHash) {
            await client.query(
                `INSERT INTO users (
                    email, display_name, password_hash, email_verified, role, is_active
                 ) VALUES ($1, 'NoteClaw Admin', $2, TRUE, 'admin', TRUE)
                 ON CONFLICT (email) DO UPDATE
                 SET password_hash = EXCLUDED.password_hash,
                     password_salt = NULL,
                     role = 'admin',
                     email_verified = TRUE,
                     is_active = TRUE,
                     updated_at = NOW()`,
                [initialAdminEmail, initialAdminPasswordHash],
            );
            console.log('✅ Initial administrator account is ready');
        }

        console.log('✅ Agent communication tables initialized');
        console.log('✅ Core tables initialized');
    } catch (error) {
        console.error('❌ Database initialization error:', error);
        throw error;
    } finally {
        client.release();
    }
}

// Call initialization
// NOTE: Commented out to prevent multiple initializations when module is imported
// initializeDatabase().catch(console.error);

export default pool;
