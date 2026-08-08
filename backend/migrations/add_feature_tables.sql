-- Migration: Add feature tables for tutor, language learning, stories, meals, and audio
-- Run this in Neon PostgreSQL console

-- Tutor Sessions Table
CREATE TABLE IF NOT EXISTS tutor_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
    source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
    topic TEXT NOT NULL,
    style TEXT DEFAULT 'socratic',
    difficulty TEXT DEFAULT 'adaptive',
    total_score DECIMAL DEFAULT 0,
    exchange_count INTEGER DEFAULT 0,
    exchanges JSONB DEFAULT '[]',
    summary TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Language Learning Sessions Table
CREATE TABLE IF NOT EXISTS language_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_language TEXT NOT NULL,
    native_language TEXT DEFAULT 'English',
    proficiency TEXT DEFAULT 'beginner',
    topic TEXT,
    messages JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Stories Table
CREATE TABLE IF NOT EXISTS stories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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

-- Weekly Meal Plans Table
CREATE TABLE IF NOT EXISTS meal_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    week_start DATE NOT NULL,
    days JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, week_start)
);

-- Saved Meals Table
CREATE TABLE IF NOT EXISTS saved_meals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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

-- Audio Overviews Table
CREATE TABLE IF NOT EXISTS audio_overviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
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

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tutor_sessions_user ON tutor_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_tutor_sessions_notebook ON tutor_sessions(notebook_id);
CREATE INDEX IF NOT EXISTS idx_language_sessions_user ON language_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_stories_user ON stories(user_id);
CREATE INDEX IF NOT EXISTS idx_meal_plans_user ON meal_plans(user_id);
CREATE INDEX IF NOT EXISTS idx_meal_plans_week ON meal_plans(user_id, week_start);
CREATE INDEX IF NOT EXISTS idx_saved_meals_user ON saved_meals(user_id);
CREATE INDEX IF NOT EXISTS idx_audio_overviews_user ON audio_overviews(user_id);
CREATE INDEX IF NOT EXISTS idx_audio_overviews_notebook ON audio_overviews(notebook_id);
