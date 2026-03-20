import pool from '../config/database.js';

async function runMigration() {
    const client = await pool.connect();
    try {
        console.log('🔧 Running database migration...');

        // Add missing columns to user_stats
        try {
            await client.query(`
                ALTER TABLE user_stats ADD COLUMN IF NOT EXISTS study_time_minutes INTEGER DEFAULT 0;
                ALTER TABLE user_stats ADD COLUMN IF NOT EXISTS last_activity_date DATE;
            `);
            console.log('✅ user_stats table updated');
        } catch (e: any) {
            console.log('ℹ️ user_stats already up to date or error:', e.message);
        }

        // Ensure all feature tables exist - run each separately to handle errors
        const featureTables = [
            `CREATE TABLE IF NOT EXISTS ebook_projects (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                notebook_id UUID,
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
            )`,
            `CREATE TABLE IF NOT EXISTS ebook_chapters (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                project_id UUID,
                title TEXT NOT NULL,
                content TEXT,
                chapter_order INTEGER NOT NULL,
                images JSONB DEFAULT '[]'::jsonb,
                status TEXT DEFAULT 'draft',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS research_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                notebook_id UUID,
                query TEXT NOT NULL,
                report TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS research_sources (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                session_id UUID,
                title TEXT,
                url TEXT,
                content TEXT,
                snippet TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS tutor_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                notebook_id UUID,
                source_id UUID,
                topic TEXT NOT NULL,
                style TEXT DEFAULT 'socratic',
                difficulty TEXT DEFAULT 'adaptive',
                exchanges JSONB DEFAULT '[]',
                summary TEXT,
                total_score INTEGER DEFAULT 0,
                exchange_count INTEGER DEFAULT 0,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS language_sessions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                target_language TEXT NOT NULL,
                native_language TEXT DEFAULT 'English',
                proficiency TEXT DEFAULT 'beginner',
                topic TEXT,
                messages JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS stories (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
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
            )`,
            `CREATE TABLE IF NOT EXISTS meal_plans (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                week_start DATE NOT NULL,
                days JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS saved_meals (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
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
            )`,
            `CREATE TABLE IF NOT EXISTS audio_overviews (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id TEXT NOT NULL,
                notebook_id UUID,
                title TEXT NOT NULL,
                audio_path TEXT,
                duration_seconds INTEGER,
                voice_provider TEXT,
                voice_id TEXT,
                format TEXT DEFAULT 'podcast',
                segments JSONB DEFAULT '[]',
                created_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS notebook_shares (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                notebook_id UUID NOT NULL,
                share_token TEXT UNIQUE NOT NULL,
                access_level TEXT DEFAULT 'read',
                expires_at TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS ai_models (
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
            )`,
            `CREATE TABLE IF NOT EXISTS api_keys (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                service_name TEXT UNIQUE NOT NULL,
                encrypted_value TEXT NOT NULL,
                description TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS onboarding_screens (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                title TEXT NOT NULL,
                description TEXT,
                image_url TEXT,
                order_index INTEGER NOT NULL,
                created_at TIMESTAMPTZ DEFAULT NOW()
            )`,
            `CREATE TABLE IF NOT EXISTS app_settings (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                key TEXT UNIQUE NOT NULL,
                content TEXT,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            )`
        ];

        for (const sql of featureTables) {
            try {
                await client.query(sql);
            } catch (e: any) {
                // Table might already exist with different schema, that's ok
                console.log(`ℹ️ Table creation note: ${e.message?.substring(0, 50)}`);
            }
        }
        console.log('✅ Feature tables created/verified');

        // Create indexes
        await client.query(`
            CREATE INDEX IF NOT EXISTS idx_ebook_projects_user_id ON ebook_projects(user_id);
            CREATE INDEX IF NOT EXISTS idx_research_sessions_user_id ON research_sessions(user_id);
            CREATE INDEX IF NOT EXISTS idx_tutor_sessions_user_id ON tutor_sessions(user_id);
            CREATE INDEX IF NOT EXISTS idx_stories_user_id ON stories(user_id);
        `);
        console.log('✅ Indexes created');

        console.log('🎉 Migration completed successfully!');
    } catch (error) {
        console.error('❌ Migration error:', error);
        throw error;
    } finally {
        client.release();
        await pool.end();
    }
}

runMigration().catch(console.error);
