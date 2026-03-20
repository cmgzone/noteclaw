import pool from './database.js';

/**
 * Initialize all feature tables for the application
 */
export async function initializeFeatureTables() {
    const client = await pool.connect();
    try {
        console.log('🔧 Initializing feature tables...');

        // Ebook tables
        await client.query(`
            CREATE TABLE IF NOT EXISTS ebook_projects (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                topic TEXT,
                target_audience TEXT,
                branding JSONB,
                selected_model TEXT,
                status TEXT DEFAULT 'draft',
                cover_image TEXT,
                is_public BOOLEAN DEFAULT false,
                view_count INTEGER DEFAULT 0,
                share_count INTEGER DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS ebook_chapters (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                project_id UUID NOT NULL REFERENCES ebook_projects(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                content TEXT,
                chapter_order INTEGER NOT NULL,
                images JSONB DEFAULT '[]'::jsonb,
                status TEXT DEFAULT 'draft',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            ALTER TABLE ebook_chapters
            ADD COLUMN IF NOT EXISTS images JSONB DEFAULT '[]'::jsonb;

            UPDATE ebook_chapters
            SET images = '[]'::jsonb
            WHERE images IS NULL;
        `);

        // Research tables
        await client.query(`
            CREATE TABLE IF NOT EXISTS research_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                query TEXT NOT NULL,
                report TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS research_sources (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                session_id UUID NOT NULL REFERENCES research_sessions(id) ON DELETE CASCADE,
                title TEXT,
                url TEXT,
                content TEXT,
                snippet TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Tutor sessions
        await client.query(`
            CREATE TABLE IF NOT EXISTS tutor_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
                topic TEXT NOT NULL,
                style TEXT DEFAULT 'socratic',
                difficulty TEXT DEFAULT 'adaptive',
                exchanges JSONB DEFAULT '[]',
                summary TEXT,
                total_score INTEGER DEFAULT 0,
                exchange_count INTEGER DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Language learning sessions
        await client.query(`
            CREATE TABLE IF NOT EXISTS language_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                target_language TEXT NOT NULL,
                native_language TEXT DEFAULT 'English',
                proficiency TEXT DEFAULT 'beginner',
                topic TEXT,
                messages JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Stories
        await client.query(`
            CREATE TABLE IF NOT EXISTS stories (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                summary TEXT,
                cover_image TEXT,
                genre TEXT,
                tone TEXT,
                is_fiction BOOLEAN DEFAULT false,
                sources JSONB DEFAULT '[]',
                chapters JSONB DEFAULT '[]',
                characters JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Meal planner
        await client.query(`
            CREATE TABLE IF NOT EXISTS meal_plans (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                week_start DATE NOT NULL,
                days JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id, week_start)
            );

            CREATE TABLE IF NOT EXISTS saved_meals (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                name TEXT NOT NULL,
                description TEXT,
                meal_type TEXT,
                calories INTEGER,
                protein DECIMAL,
                carbs DECIMAL,
                fat DECIMAL,
                fiber DECIMAL,
                ingredients JSONB DEFAULT '[]',
                instructions TEXT,
                prep_time INTEGER,
                image_url TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Audio overviews
        await client.query(`
            CREATE TABLE IF NOT EXISTS audio_overviews (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                audio_path TEXT,
                duration_seconds INTEGER,
                voice_provider TEXT,
                voice_id TEXT,
                format TEXT DEFAULT 'podcast',
                segments JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Sharing
        await client.query(`
            CREATE TABLE IF NOT EXISTS notebook_shares (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                notebook_id UUID NOT NULL REFERENCES notebooks(id) ON DELETE CASCADE,
                share_token TEXT UNIQUE NOT NULL,
                access_level TEXT DEFAULT 'read',
                expires_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Admin tables
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
                order_index INTEGER NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS app_settings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                key TEXT UNIQUE NOT NULL,
                content TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        console.log('✅ Feature tables initialized');
    } catch (error) {
        console.error('❌ Feature tables initialization error:', error);
        throw error;
    } finally {
        client.release();
    }
}

/**
 * Seed default data
 */
export async function seedDefaultData() {
    const client = await pool.connect();
    try {
        console.log('🌱 Seeding default data...');

        // Check if plans exist
        const plansResult = await client.query('SELECT COUNT(*) FROM subscription_plans');
        if (parseInt(plansResult.rows[0].count) === 0) {
            await client.query(`
                INSERT INTO subscription_plans (
                  name, credits_per_month, price, is_free_plan, features,
                  notes_limit, mcp_sources_limit, mcp_tokens_limit, mcp_api_calls_per_day
                ) VALUES
                ('Free', 50, 0, true, '["Local API keys supported", "100 notes", "MCP: 10 sources, 3 tokens, 100 calls/day"]', 100, 10, 3, 100),
                ('Pro', 1000, 9.99, false, '["More notes", "MCP: 200 sources, 10 tokens, 2000 calls/day"]', 1000, 200, 10, 2000),
                ('Ultra', 5000, 29.99, false, '["Highest limits", "MCP: 1000 sources, 25 tokens, 10000 calls/day"]', 10000, 1000, 25, 10000)
            `);
            console.log('✅ Default subscription plans created');
        }

        // Check if credit packages exist
        const packagesResult = await client.query('SELECT COUNT(*) FROM credit_packages');
        if (parseInt(packagesResult.rows[0].count) === 0) {
            await client.query(`
                INSERT INTO credit_packages (name, credits, price) VALUES
                ('Starter Pack', 100, 1.99),
                ('Value Pack', 500, 7.99),
                ('Pro Pack', 2000, 24.99),
                ('Ultimate Pack', 10000, 99.99)
            `);
            console.log('✅ Default credit packages created');
        }

        console.log('✅ Default data seeded');
    } catch (error) {
        console.error('❌ Seeding error:', error);
    } finally {
        client.release();
    }
}

// Initialize feature tables
initializeFeatureTables()
    .then(() => seedDefaultData())
    .catch(console.error);
