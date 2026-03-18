// Encrypt OpenRouter API key for Neon database
const crypto = require('crypto');

// Your OpenRouter API key
const OPENROUTER_KEY = "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";

// Same secret as in the app
const SECRET = "noteclaw_global_secret_key_2024";

// Generate encryption key from secret (same as app)
const keyBytes = crypto.createHash('sha256').update(SECRET).digest();

// Generate random IV
const iv = crypto.randomBytes(16);

// Create cipher
const cipher = crypto.createCipheriv('aes-256-cbc', keyBytes, iv);

// Encrypt
let encrypted = cipher.update(OPENROUTER_KEY, 'utf8');
encrypted = Buffer.concat([encrypted, cipher.final()]);

// Combine IV + encrypted data
const combined = Buffer.concat([iv, encrypted]);

// Base64 encode
const encryptedBase64 = combined.toString('base64');

console.log("=".repeat(60));
console.log("ENCRYPTED OPENROUTER API KEY");
console.log("=".repeat(60));
console.log();
console.log("Run this SQL in Neon Console:");
console.log();
console.log(`INSERT INTO api_keys (service_name, encrypted_value, description, updated_at)`);
console.log(`VALUES ('openrouter', '${encryptedBase64}', 'OpenRouter API Key', CURRENT_TIMESTAMP)`);
console.log(`ON CONFLICT (service_name)`);
console.log(`DO UPDATE SET encrypted_value = EXCLUDED.encrypted_value, updated_at = CURRENT_TIMESTAMP;`);
console.log();
console.log("=".repeat(60));
console.log("Verify with:");
console.log("SELECT service_name, description, updated_at FROM api_keys;");
console.log("=".repeat(60));
