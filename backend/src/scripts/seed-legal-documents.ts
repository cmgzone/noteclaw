import pool from '../config/database.js';
import {
    DEFAULT_PRIVACY_POLICY_MARKDOWN,
    DEFAULT_TERMS_OF_SERVICE_MARKDOWN,
} from '../content/legalDocuments.js';
import {
    setPrivacyPolicyContent,
    setTermsOfServiceContent,
} from '../services/appSettingsService.js';

async function run() {
    try {
        await setPrivacyPolicyContent(DEFAULT_PRIVACY_POLICY_MARKDOWN);
        await setTermsOfServiceContent(DEFAULT_TERMS_OF_SERVICE_MARKDOWN);
        console.log('Seeded privacy policy and terms of service content.');
    } finally {
        await pool.end();
    }
}

run().catch((error) => {
    console.error('Failed to seed legal documents:', error);
    process.exitCode = 1;
});
