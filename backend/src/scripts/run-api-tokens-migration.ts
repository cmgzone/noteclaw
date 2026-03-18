/**
 * Run personal API tokens migration
 * Adds support for user-generated API tokens for authenticating third-party coding agents
 * Requirements: 1.1, 1.3, 3.1, 4.1, 4.5
 */

import pool from '../config/database.js';

async function runMigration() {
  const client = await pool.connect();
  
  try {
    console.log('🔧 Running personal API tokens migration...');
    
    await client.query('BEGIN');
    
    // Create api_tokens table
    await client.query(`
      CREATE TABLE IF NOT EXISTS api_tokens (
        id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
        user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        token_hash TEXT NOT NULL UNIQUE,
        token_prefix TEXT NOT NULL,
        token_suffix TEXT NOT NULL,
        expires_at TIMESTAMPTZ,
        last_used_at TIMESTAMPTZ,
        revoked_at TIMESTAMPTZ,
        metadata JSONB DEFAULT '{}',
        created_at TIMESTAMPTZ DEFAULT NOW(),
        CONSTRAINT valid_token_prefix CHECK (token_prefix LIKE 'nclaw_%')
      )
    `);
    console.log('✅ Created api_tokens table');
    
    // Create token_usage_logs table for security auditing
    await client.query(`
      CREATE TABLE IF NOT EXISTS token_usage_logs (
        id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::TEXT,
        token_id TEXT NOT NULL REFERENCES api_tokens(id) ON DELETE CASCADE,
        endpoint TEXT NOT NULL,
        ip_address TEXT,
        user_agent TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      )
    `);
    console.log('✅ Created token_usage_logs table');
    
    // Create indexes for performance
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_api_tokens_user ON api_tokens(user_id);
      CREATE INDEX IF NOT EXISTS idx_api_tokens_hash ON api_tokens(token_hash);
      CREATE INDEX IF NOT EXISTS idx_api_tokens_active ON api_tokens(user_id) WHERE revoked_at IS NULL;
      CREATE INDEX IF NOT EXISTS idx_token_usage_token ON token_usage_logs(token_id);
      CREATE INDEX IF NOT EXISTS idx_token_usage_time ON token_usage_logs(created_at);
    `);
    console.log('✅ Created indexes for performance');
    
    await client.query('COMMIT');
    console.log('✅ Personal API tokens migration completed successfully!');
    
  } catch (error) {
    await client.query('ROLLBACK');
    console.error('❌ Migration failed:', error);
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

runMigration().catch(console.error);
