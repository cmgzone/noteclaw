import pool from '../config/database.js';
import bcrypt from 'bcryptjs';

// Configuration - Change these values
const ADMIN_EMAIL = 'admin@example.com';
const ADMIN_PASSWORD = 'admin123'; // Change this!
const ADMIN_NAME = 'Admin User';

async function createAdmin() {
    const client = await pool.connect();
    try {
        console.log('🔧 Creating admin user...');

        // Check if user already exists
        const existing = await client.query(
            'SELECT id, role FROM users WHERE email = $1',
            [ADMIN_EMAIL]
        );

        if (existing.rows.length > 0) {
            if (existing.rows[0].role === 'admin') {
                console.log('✅ Admin user already exists!');
                console.log(`   Email: ${ADMIN_EMAIL}`);
                return;
            }
            // Update existing user to admin
            await client.query(
                'UPDATE users SET role = $1 WHERE email = $2',
                ['admin', ADMIN_EMAIL]
            );
            console.log('✅ Existing user promoted to admin!');
            console.log(`   Email: ${ADMIN_EMAIL}`);
            return;
        }

        // Create new admin user
        const salt = await bcrypt.genSalt(10);
        const passwordHash = await bcrypt.hash(ADMIN_PASSWORD, salt);

        await client.query(`
            INSERT INTO users (email, display_name, password_hash, password_salt, role, email_verified)
            VALUES ($1, $2, $3, $4, 'admin', true)
        `, [ADMIN_EMAIL, ADMIN_NAME, passwordHash, salt]);

        console.log('✅ Admin user created successfully!');
        console.log('');
        console.log('   📧 Email:', ADMIN_EMAIL);
        console.log('   🔑 Password:', ADMIN_PASSWORD);
        console.log('');
        console.log('⚠️  Please change the password after first login!');

    } catch (error) {
        console.error('❌ Error creating admin:', error);
        throw error;
    } finally {
        client.release();
        await pool.end();
    }
}

createAdmin().catch(console.error);
