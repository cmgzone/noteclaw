import { readFileSync } from 'fs';
import { join, dirname } from 'path';
import { fileURLToPath } from 'url';
import pool from '../config/database.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function runMigration() {
  console.log('Running ebook social sharing migration...');

  try {
    const migrationPath = join(
      __dirname,
      '../../migrations/add_ebook_social_sharing.sql'
    );
    const sql = readFileSync(migrationPath, 'utf-8');

    await pool.query(sql);

    console.log('✅ Ebook social sharing migration completed successfully!');
    console.log('Added:');
    console.log('  - is_public, view_count, share_count to ebook_projects');
    console.log('  - public ebook index');
    console.log('  - ebook support in increment_view_count');
  } catch (error) {
    console.error('Migration failed:', error);
    process.exit(1);
  } finally {
    await pool.end();
  }
}

runMigration();
