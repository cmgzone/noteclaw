import pool from '../config/database.js';

async function migrate() {
    const client = await pool.connect();
    try {
        await client.query('BEGIN');

        console.log('--- Migrating Gamification ---');
        await client.query(`
            CREATE TABLE IF NOT EXISTS user_stats (
                user_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                total_xp INTEGER DEFAULT 0,
                level INTEGER DEFAULT 1,
                current_streak INTEGER DEFAULT 0,
                longest_streak INTEGER DEFAULT 0,
                last_active_date DATE,
                quizzes_completed INTEGER DEFAULT 0,
                perfect_quizzes INTEGER DEFAULT 0,
                flashcards_reviewed INTEGER DEFAULT 0,
                notebooks_created INTEGER DEFAULT 0,
                sources_added INTEGER DEFAULT 0,
                tutor_sessions_completed INTEGER DEFAULT 0,
                chat_messages_sent INTEGER DEFAULT 0,
                deep_research_completed INTEGER DEFAULT 0,
                voice_mode_used INTEGER DEFAULT 0,
                mindmaps_created INTEGER DEFAULT 0,
                features_used TEXT[] DEFAULT '{}',
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS achievements (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                achievement_id TEXT NOT NULL,
                current_value INTEGER DEFAULT 0,
                is_unlocked BOOLEAN DEFAULT FALSE,
                unlocked_at TIMESTAMP WITH TIME ZONE,
                UNIQUE(user_id, achievement_id)
            );

            CREATE TABLE IF NOT EXISTS daily_challenges (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                type TEXT NOT NULL,
                title TEXT NOT NULL,
                description TEXT,
                target_value INTEGER NOT NULL,
                current_value INTEGER DEFAULT 0,
                is_completed BOOLEAN DEFAULT FALSE,
                xp_reward INTEGER DEFAULT 0,
                date DATE NOT NULL,
                completed_at TIMESTAMP WITH TIME ZONE,
                UNIQUE(user_id, type, date)
            );
        `);

        console.log('--- Migrating Study Tools ---');
        await client.query(`
            CREATE TABLE IF NOT EXISTS flashcard_decks (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
                source_id TEXT REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS flashcards (
                id TEXT PRIMARY KEY,
                deck_id TEXT REFERENCES flashcard_decks(id) ON DELETE CASCADE,
                question TEXT NOT NULL,
                answer TEXT NOT NULL,
                difficulty INTEGER DEFAULT 1,
                times_reviewed INTEGER DEFAULT 0,
                times_correct INTEGER DEFAULT 0,
                last_reviewed_at TIMESTAMP WITH TIME ZONE,
                next_review_at TIMESTAMP WITH TIME ZONE,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS quizzes (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
                source_id TEXT REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                times_attempted INTEGER DEFAULT 0,
                last_score INTEGER,
                best_score INTEGER,
                last_attempted_at TIMESTAMP WITH TIME ZONE,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS quiz_questions (
                id TEXT PRIMARY KEY,
                quiz_id TEXT REFERENCES quizzes(id) ON DELETE CASCADE,
                question TEXT NOT NULL,
                options JSONB NOT NULL,
                correct_option_index INTEGER NOT NULL,
                explanation TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS mind_maps (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
                source_id TEXT REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                root_node JSONB NOT NULL,
                text_content TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS infographics (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
                source_id TEXT REFERENCES sources(id) ON DELETE SET NULL,
                title TEXT NOT NULL,
                image_url TEXT,
                image_base64 TEXT,
                style TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );
        `);

        console.log('--- Migrating Ebooks & Research ---');
        await client.query(`
            CREATE TABLE IF NOT EXISTS ebook_projects (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
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
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS ebook_chapters (
                id TEXT PRIMARY KEY,
                project_id TEXT REFERENCES ebook_projects(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                content TEXT,
                chapter_order INTEGER NOT NULL,
                images JSONB DEFAULT '[]'::jsonb,
                status TEXT DEFAULT 'pending',
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS research_sessions (
                id TEXT PRIMARY KEY,
                user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
                notebook_id TEXT REFERENCES notebooks(id) ON DELETE CASCADE,
                query TEXT NOT NULL,
                report TEXT,
                status TEXT DEFAULT 'completed',
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );

            CREATE TABLE IF NOT EXISTS research_sources (
                id TEXT PRIMARY KEY,
                session_id TEXT REFERENCES research_sessions(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                url TEXT NOT NULL,
                content TEXT,
                snippet TEXT,
                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
            );
        `);

        await client.query('COMMIT');
        console.log('Migration completed successfully!');
    } catch (e) {
        await client.query('ROLLBACK');
        console.error('Migration failed:', e);
        throw e;
    } finally {
        client.release();
    }
}

migrate().catch(err => {
    console.error(err);
    process.exit(1);
});
