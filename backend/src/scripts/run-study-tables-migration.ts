import pool from '../config/database.js';

async function runStudyTablesMigration() {
  console.log('🚀 Running study tools tables migration...\n');

  try {
    // Create flashcard_decks table
    console.log('Creating flashcard_decks table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS flashcard_decks (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
        source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ flashcard_decks table created');

    // Create flashcards table
    console.log('Creating flashcards table...');
    await pool.query(`
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
      )
    `);
    console.log('✅ flashcards table created');

    // Create quizzes table
    console.log('Creating quizzes table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS quizzes (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
        source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        times_attempted INTEGER DEFAULT 0,
        last_score INTEGER,
        best_score INTEGER,
        last_attempted_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ quizzes table created');

    // Create quiz_questions table
    console.log('Creating quiz_questions table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS quiz_questions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        quiz_id UUID NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
        question TEXT NOT NULL,
        options JSONB NOT NULL DEFAULT '[]',
        correct_option_index INTEGER NOT NULL,
        explanation TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ quiz_questions table created');

    // Create mind_maps table
    console.log('Creating mind_maps table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS mind_maps (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
        source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        root_node JSONB NOT NULL DEFAULT '{}',
        text_content TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW(),
        updated_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ mind_maps table created');

    // Create infographics table
    console.log('Creating infographics table...');
    await pool.query(`
      CREATE TABLE IF NOT EXISTS infographics (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        notebook_id UUID REFERENCES notebooks(id) ON DELETE SET NULL,
        source_id UUID REFERENCES sources(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        image_url TEXT,
        image_base64 TEXT,
        style TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ infographics table created');

    // Create indexes
    console.log('\nCreating indexes...');
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_flashcard_decks_user_id ON flashcard_decks(user_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_flashcard_decks_notebook_id ON flashcard_decks(notebook_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_flashcards_deck_id ON flashcards(deck_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_quizzes_user_id ON quizzes(user_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_quizzes_notebook_id ON quizzes(notebook_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_quiz_questions_quiz_id ON quiz_questions(quiz_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_mind_maps_user_id ON mind_maps(user_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_mind_maps_notebook_id ON mind_maps(notebook_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_infographics_user_id ON infographics(user_id)`);
    console.log('✅ All indexes created');

    console.log('\n✅ Study tools migration completed successfully!');
    
    // Verify tables exist
    const result = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_schema = 'public' 
      AND table_name IN ('flashcard_decks', 'flashcards', 'quizzes', 'quiz_questions', 'mind_maps', 'infographics')
      ORDER BY table_name
    `);
    
    console.log('\n📋 Verified tables:');
    result.rows.forEach(row => console.log(`   - ${row.table_name}`));

  } catch (error) {
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    await pool.end();
  }
}

runStudyTablesMigration();
