import pool from '../config/database.js';
import { activityFeedService } from '../services/activityFeedService.js';

async function seed() {
  console.log('Seeding test activities for all users...\n');
  
  // Get all users (excluding test users)
  const users = await pool.query(`
    SELECT id, display_name FROM users 
    WHERE display_name NOT LIKE 'Test User%'
    ORDER BY display_name
  `);
  
  for (const user of users.rows) {
    try {
      // Create a welcome activity for each user
      await activityFeedService.createActivity({
        userId: user.id,
        activityType: 'notebook_created',
        title: `Welcome to NoteClaw! 🎉`,
        description: 'Started using the app',
        isPublic: true,
        metadata: { welcome: true }
      });
      console.log(`✅ Created activity for ${user.display_name}`);
    } catch (e: any) {
      console.log(`❌ Failed for ${user.display_name}: ${e.message}`);
    }
  }
  
  // Count total activities
  const count = await pool.query('SELECT COUNT(*) FROM activities');
  console.log(`\nTotal activities in database: ${count.rows[0].count}`);
  
  await pool.end();
}

seed();
