import jwt from 'jsonwebtoken';

const GOOGLE_PLAY_SCOPE = 'https://www.googleapis.com/auth/androidpublisher';
const GOOGLE_PLAY_TOKEN_URL = 'https://oauth2.googleapis.com/token';

const defaultPlanProductIds: Record<string, string> = {
    pro: 'noteclaw_pro_monthly',
    ultra: 'noteclaw_ultra_monthly',
};

const defaultPackageProductIds: Record<string, string> = {
    'starter pack': 'noteclaw_credits_starter',
    'value pack': 'noteclaw_credits_value',
    'pro pack': 'noteclaw_credits_pro',
    'ultimate pack': 'noteclaw_credits_ultimate',
};

let ensureTablesPromise: Promise<void> | null = null;
let ensureCatalogColumnsPromise: Promise<void> | null = null;

type GooglePlayConfig = {
    configured: boolean;
    packageName: string;
    serviceAccountEmail: string | null;
    privateKey: string | null;
};

type GooglePlayProductType = 'subscription' | 'credit_package';

export function getGooglePlayBillingConfig(): GooglePlayConfig {
    const serviceAccountEmail =
        process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL?.trim() || null;
    const privateKey = normalizePrivateKey(
        process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY || null,
    );
    const packageName =
        process.env.GOOGLE_PLAY_PACKAGE_NAME?.trim() || 'com.note.claw';

    return {
        configured: Boolean(serviceAccountEmail && privateKey),
        packageName,
        serviceAccountEmail,
        privateKey,
    };
}

export function resolveGooglePlayProductIdForPlan(
    planName: string | null | undefined,
): string | null {
    const normalized = normalizeName(planName);
    if (!normalized) return null;

    const explicitEnv = process.env[`GOOGLE_PLAY_PLAN_${envKey(normalized)}_PRODUCT_ID`];
    return explicitEnv?.trim() || defaultPlanProductIds[normalized] || null;
}

export function resolveGooglePlayProductIdForPackage(
    packageName: string | null | undefined,
): string | null {
    const normalized = normalizeName(packageName);
    if (!normalized) return null;

    const explicitEnv =
        process.env[`GOOGLE_PLAY_PACKAGE_${envKey(normalized)}_PRODUCT_ID`];
    return explicitEnv?.trim() || defaultPackageProductIds[normalized] || null;
}

export function attachGooglePlayProductMetadata<T extends Record<string, any>>(
    item: T,
    type: GooglePlayProductType,
): T & { google_play_product_id: string | null } {
    const existingProductId =
        typeof item.google_play_product_id === 'string' &&
        item.google_play_product_id.trim().length > 0
            ? item.google_play_product_id.trim()
            : null;
    const fallbackProductId =
        type === 'subscription'
            ? resolveGooglePlayProductIdForPlan(item.name)
            : resolveGooglePlayProductIdForPackage(item.name);

    return {
        ...item,
        google_play_product_id: existingProductId ?? fallbackProductId,
    };
}

export async function ensureGooglePlayTables(
    query: (sql: string, params?: any[]) => Promise<any>,
): Promise<void> {
    if (!ensureTablesPromise) {
        ensureTablesPromise = (async () => {
            await query(`
                CREATE TABLE IF NOT EXISTS google_play_purchases (
                    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                    purchase_token TEXT NOT NULL UNIQUE,
                    product_id TEXT NOT NULL,
                    product_type TEXT NOT NULL,
                    package_name TEXT NOT NULL,
                    internal_plan_id UUID REFERENCES subscription_plans(id),
                    internal_package_id UUID REFERENCES credit_packages(id),
                    order_id TEXT,
                    latest_expiry_time TIMESTAMPTZ,
                    last_granted_order_id TEXT,
                    status TEXT,
                    metadata JSONB DEFAULT '{}'::jsonb,
                    created_at TIMESTAMPTZ DEFAULT NOW(),
                    updated_at TIMESTAMPTZ DEFAULT NOW()
                )
            `);
        })();
    }

    await ensureTablesPromise;
}

export async function ensureGooglePlayCatalogColumns(
    query: (sql: string, params?: any[]) => Promise<any>,
): Promise<void> {
    if (!ensureCatalogColumnsPromise) {
        ensureCatalogColumnsPromise = (async () => {
            await query(`
                ALTER TABLE subscription_plans
                ADD COLUMN IF NOT EXISTS google_play_product_id TEXT
            `);
            await query(`
                ALTER TABLE credit_packages
                ADD COLUMN IF NOT EXISTS google_play_product_id TEXT
            `);

            for (const [normalizedName, productId] of Object.entries(defaultPlanProductIds)) {
                await query(
                    `
                    UPDATE subscription_plans
                    SET google_play_product_id = $1
                    WHERE LOWER(name) = $2
                      AND (google_play_product_id IS NULL OR google_play_product_id = '')
                    `,
                    [productId, normalizedName],
                );
            }

            for (const [normalizedName, productId] of Object.entries(defaultPackageProductIds)) {
                await query(
                    `
                    UPDATE credit_packages
                    SET google_play_product_id = $1
                    WHERE LOWER(name) = $2
                      AND (google_play_product_id IS NULL OR google_play_product_id = '')
                    `,
                    [productId, normalizedName],
                );
            }
        })();
    }

    await ensureCatalogColumnsPromise;
}

export async function verifyGooglePlayProductPurchase(params: {
    productId: string;
    purchaseToken: string;
}): Promise<any> {
    const accessToken = await getGooglePlayAccessToken();
    const { packageName } = getGooglePlayBillingConfig();
    const url =
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
        `${encodeURIComponent(packageName)}/purchases/products/` +
        `${encodeURIComponent(params.productId)}/tokens/${encodeURIComponent(params.purchaseToken)}`;

    const response = await fetch(url, {
        headers: {
            Authorization: `Bearer ${accessToken}`,
        },
    });

    if (!response.ok) {
        const body = await response.text();
        throw new Error(
            `Google Play product verification failed (${response.status}): ${body}`,
        );
    }

    return response.json();
}

export async function verifyGooglePlaySubscriptionPurchase(
    purchaseToken: string,
): Promise<any> {
    const accessToken = await getGooglePlayAccessToken();
    const { packageName } = getGooglePlayBillingConfig();
    const url =
        `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/` +
        `${encodeURIComponent(packageName)}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`;

    const response = await fetch(url, {
        headers: {
            Authorization: `Bearer ${accessToken}`,
        },
    });

    if (!response.ok) {
        const body = await response.text();
        throw new Error(
            `Google Play subscription verification failed (${response.status}): ${body}`,
        );
    }

    return response.json();
}

function normalizePrivateKey(privateKey: string | null): string | null {
    if (!privateKey) return null;
    return privateKey.replace(/\\n/g, '\n').trim();
}

function normalizeName(value: string | null | undefined): string | null {
    const normalized = value?.trim().toLowerCase() || '';
    return normalized.length > 0 ? normalized : null;
}

function envKey(value: string): string {
    return value.replace(/[^a-z0-9]+/gi, '_').toUpperCase();
}

async function getGooglePlayAccessToken(): Promise<string> {
    const config = getGooglePlayBillingConfig();
    if (!config.configured || !config.serviceAccountEmail || !config.privateKey) {
        throw new Error(
            'Google Play Billing is not configured. Set GOOGLE_PLAY_SERVICE_ACCOUNT_EMAIL and GOOGLE_PLAY_SERVICE_ACCOUNT_PRIVATE_KEY.',
        );
    }

    const issuedAt = Math.floor(Date.now() / 1000);
    const assertion = jwt.sign(
        {
            iss: config.serviceAccountEmail,
            scope: GOOGLE_PLAY_SCOPE,
            aud: GOOGLE_PLAY_TOKEN_URL,
            exp: issuedAt + 3600,
            iat: issuedAt,
        },
        config.privateKey,
        {
            algorithm: 'RS256',
        },
    );

    const response = await fetch(GOOGLE_PLAY_TOKEN_URL, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams({
            grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            assertion,
        }),
    });

    if (!response.ok) {
        const body = await response.text();
        throw new Error(
            `Failed to fetch Google Play access token (${response.status}): ${body}`,
        );
    }

    const data = (await response.json()) as { access_token?: string };
    if (!data.access_token) {
        throw new Error('Google Play access token response was missing access_token');
    }

    return data.access_token;
}
