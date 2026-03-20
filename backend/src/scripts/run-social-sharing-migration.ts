import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import pool from '../config/database.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function runMigration() {
  console.log('Running social sharing migration...');

  try {
    const migrationPath = join(
      __dirname,
      '../../migrations/add_social_sharing.sql'
    );
    const ebookMigrationPath = join(
      __dirname,
      '../../migrations/add_ebook_social_sharing.sql'
    );
    const sql = readFileSync(migrationPath, 'utf-8');
    const ebookSql = readFileSync(ebookMigrationPath, 'utf-8');

    await pool.query(sql);
    await pool.query(ebookSql);

    console.log('✅ Social sharing migration completed successfully!');
    console.log('Added:');
    console.log('  - is_public, is_locked, view_count, share_count to notebooks');
    console.log('  - is_public, view_count, share_count to plans');
    console.log('  - is_public, view_count, share_count to ebook_projects');
    console.log('  - shared_content table');
    console.log('  - content_views table');
    console.log('  - content_likes table');
    console.log('  - content_saves table');
    console.log('  - increment_view_count function with ebook support');
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

runMigration();
