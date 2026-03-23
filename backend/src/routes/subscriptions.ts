import express, { type Request, type Response, type Router } from 'express';
import pool from '../config/database.js';
import { authenticateToken, type AuthRequest } from '../middleware/auth.js';
import { consumeCredits as consumeCreditsAtomic } from '../services/creditService.js';
import {
    attachGooglePlayProductMetadata,
    ensureGooglePlayCatalogColumns,
    ensureGooglePlayTables,
    getGooglePlayBillingConfig,
    resolveGooglePlayProductIdForPackage,
    resolveGooglePlayProductIdForPlan,
    verifyGooglePlayProductPurchase,
    verifyGooglePlaySubscriptionPurchase,
} from '../services/googlePlayBillingService.js';

const router: Router = express.Router();

class PaymentVerificationError extends Error {
    readonly statusCode: number;

    constructor(message: string, statusCode = 400) {
        super(message);
        this.name = 'PaymentVerificationError';
        this.statusCode = statusCode;
    }
}

async function ensureGooglePlayCatalogReady(): Promise<void> {
    await ensureGooglePlayCatalogColumns((sql, params) => pool.query(sql, params));
}

function parseTimestamp(value: string | null | undefined): Date | null {
    if (!value) return null;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function extractSubscriptionProductId(subscription: any): string | null {
    const lineItems = Array.isArray(subscription?.lineItems)
        ? subscription.lineItems
        : [];
    for (const lineItem of lineItems) {
        if (typeof lineItem?.productId === 'string' && lineItem.productId.trim()) {
            return lineItem.productId.trim();
        }
    }
    return null;
}

function extractSubscriptionExpiry(subscription: any): Date | null {
    const lineItems = Array.isArray(subscription?.lineItems)
        ? subscription.lineItems
        : [];
    for (const lineItem of lineItems) {
        const expiry = parseTimestamp(lineItem?.expiryTime);
        if (expiry) return expiry;
    }
    return null;
}

function isEntitledSubscriptionState(state: string | null | undefined): boolean {
    return state === 'SUBSCRIPTION_STATE_ACTIVE' || state === 'SUBSCRIPTION_STATE_IN_GRACE_PERIOD';
}

async function getCurrentBalance(userId: string): Promise<number> {
    const result = await pool.query(
        'SELECT current_credits FROM user_subscriptions WHERE user_id = $1',
        [userId],
    );
    if (result.rows.length === 0) {
        throw new Error('No subscription found');
    }
    return Number(result.rows[0].current_credits || 0);
}

function parsePriceToCents(value: unknown): number {
    const parsed =
        typeof value === 'number'
            ? value
            : typeof value === 'string'
                ? parseFloat(value)
                : Number.NaN;

    if (!Number.isFinite(parsed) || parsed <= 0) {
        throw new PaymentVerificationError('Invalid price configuration', 500);
    }

    return Math.round(parsed * 100);
}

async function verifyStripePaymentIntent(params: {
    paymentIntentId: string;
    userId: string;
    expectedAmountCents: number;
    expectedPackageId?: string;
    expectedPlanId?: string;
    expectedCurrency?: string;
}) {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    if (!stripeSecretKey) {
        throw new PaymentVerificationError('Stripe is not configured', 500);
    }

    const Stripe = (await import('stripe')).default;
    const stripe = new Stripe(stripeSecretKey);
    const paymentIntent = await stripe.paymentIntents.retrieve(params.paymentIntentId);

    if (!paymentIntent || paymentIntent.object !== 'payment_intent') {
        throw new PaymentVerificationError('Stripe payment intent was not found', 404);
    }

    if (paymentIntent.status !== 'succeeded') {
        throw new PaymentVerificationError(
            `Stripe payment is not completed (${paymentIntent.status})`,
            409,
        );
    }

    const metadata = paymentIntent.metadata ?? {};
    if ((metadata.userId || '').trim() !== params.userId) {
        throw new PaymentVerificationError('Stripe payment belongs to a different account', 403);
    }

    if (
        params.expectedPackageId &&
        (metadata.packageId || '').trim() !== params.expectedPackageId
    ) {
        throw new PaymentVerificationError(
            'Stripe payment does not match this credit package',
        );
    }

    if (
        params.expectedPlanId &&
        (metadata.planId || '').trim() !== params.expectedPlanId
    ) {
        throw new PaymentVerificationError(
            'Stripe payment does not match this subscription plan',
        );
    }

    const normalizedCurrency = (params.expectedCurrency ?? 'usd').toLowerCase();
    if ((paymentIntent.currency || '').toLowerCase() !== normalizedCurrency) {
        throw new PaymentVerificationError('Stripe payment currency did not match');
    }

    const amountPaid = Number(paymentIntent.amount_received || paymentIntent.amount || 0);
    if (amountPaid !== params.expectedAmountCents) {
        throw new PaymentVerificationError('Stripe payment amount did not match');
    }

    return paymentIntent;
}

async function upsertGooglePlayPurchase(params: {
    userId: string;
    purchaseToken: string;
    productId: string;
    productType: 'subscription' | 'credit_package';
    packageName: string;
    orderId: string | null;
    internalPlanId?: string | null;
    internalPackageId?: string | null;
    lastGrantedOrderId?: string | null;
    latestExpiryTime?: Date | null;
    status?: string | null;
    metadata?: Record<string, unknown>;
}) {
    await ensureGooglePlayTables((sql, queryParams) => pool.query(sql, queryParams));

    await pool.query(
        `
        INSERT INTO google_play_purchases (
            user_id,
            purchase_token,
            product_id,
            product_type,
            package_name,
            internal_plan_id,
            internal_package_id,
            order_id,
            latest_expiry_time,
            last_granted_order_id,
            status,
            metadata,
            updated_at
        )
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, CURRENT_TIMESTAMP)
        ON CONFLICT (purchase_token)
        DO UPDATE SET
            user_id = EXCLUDED.user_id,
            product_id = EXCLUDED.product_id,
            product_type = EXCLUDED.product_type,
            package_name = EXCLUDED.package_name,
            internal_plan_id = EXCLUDED.internal_plan_id,
            internal_package_id = EXCLUDED.internal_package_id,
            order_id = EXCLUDED.order_id,
            latest_expiry_time = EXCLUDED.latest_expiry_time,
            last_granted_order_id = EXCLUDED.last_granted_order_id,
            status = EXCLUDED.status,
            metadata = EXCLUDED.metadata,
            updated_at = CURRENT_TIMESTAMP
        `,
        [
            params.userId,
            params.purchaseToken,
            params.productId,
            params.productType,
            params.packageName,
            params.internalPlanId ?? null,
            params.internalPackageId ?? null,
            params.orderId,
            params.latestExpiryTime ?? null,
            params.lastGrantedOrderId ?? null,
            params.status ?? null,
            JSON.stringify(params.metadata ?? {}),
        ],
    );
}

// Get payment configuration - PUBLIC endpoint for Flutter app
// Returns PayPal/Stripe config from environment variables
router.get('/payment-config', async (_req: Request, res: Response) => {
    try {
        await ensureGooglePlayCatalogReady();
        const googlePlayConfig = getGooglePlayBillingConfig();
        const config: any = {
            paypal: {
                configured: !!(process.env.PAYPAL_CLIENT_ID && process.env.PAYPAL_SECRET),
                clientId: process.env.PAYPAL_CLIENT_ID || null,
                sandboxMode: process.env.PAYPAL_SANDBOX_MODE !== 'false',
            },
            stripe: {
                configured: !!(process.env.STRIPE_PUBLISHABLE_KEY && process.env.STRIPE_SECRET_KEY),
                publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || null,
                testMode: process.env.STRIPE_TEST_MODE !== 'false',
            },
            googlePlay: {
                configured: googlePlayConfig.configured,
                packageName: googlePlayConfig.packageName,
            }
        };

        console.log('[PAYMENT] Config request - PayPal configured:', config.paypal.configured, ', Stripe configured:', config.stripe.configured);

        res.json({ success: true, config });
    } catch (error) {
        console.error('Error fetching payment config:', error);
        res.status(500).json({ error: 'Failed to fetch payment config' });
    }
});

// Create Stripe PaymentIntent (requires auth)
router.post('/create-payment-intent', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        const { amount, currency, packageId, planId, description } = req.body || {};

        const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
        if (!stripeSecretKey) {
            return res.status(500).json({ error: 'Stripe is not configured' });
        }

        let amountCents: number | null = null;
        const normalizedCurrency = typeof currency === 'string' && currency.trim().length > 0
            ? currency.trim().toLowerCase()
            : 'usd';
        const metadata: Record<string, string> = { userId };

        if (packageId && planId) {
            return res.status(400).json({ error: 'packageId and planId cannot be used together' });
        }

        if (packageId) {
            const pkgResult = await pool.query(
                'SELECT id, price FROM credit_packages WHERE id = $1 AND is_active = true',
                [packageId]
            );
            if (pkgResult.rows.length === 0) {
                return res.status(404).json({ error: 'Credit package not found' });
            }

            amountCents = parsePriceToCents(pkgResult.rows[0].price);
            metadata.packageId = String(packageId);
        } else if (planId) {
            const planResult = await pool.query(
                'SELECT id, price FROM subscription_plans WHERE id = $1 AND is_active = true',
                [planId]
            );
            if (planResult.rows.length === 0) {
                return res.status(404).json({ error: 'Subscription plan not found' });
            }

            amountCents = parsePriceToCents(planResult.rows[0].price);
            metadata.planId = String(planId);
        } else if (amount !== undefined && amount !== null) {
            const parsedAmount = typeof amount === 'string' ? parseFloat(amount) : Number(amount);
            if (!Number.isFinite(parsedAmount) || parsedAmount <= 0) {
                return res.status(400).json({ error: 'Invalid amount' });
            }
            if (parsedAmount > 1000) {
                return res.status(400).json({ error: 'Amount too large' });
            }
            amountCents = Math.round(parsedAmount * 100);
        } else {
            return res.status(400).json({ error: 'packageId or amount is required' });
        }

        const Stripe = (await import('stripe')).default;
        const stripe = new Stripe(stripeSecretKey);

        const paymentIntent = await stripe.paymentIntents.create({
            amount: amountCents,
            currency: normalizedCurrency,
            automatic_payment_methods: { enabled: true },
            description: typeof description === 'string' ? description : undefined,
            metadata,
        });

        if (!paymentIntent.client_secret) {
            return res.status(500).json({ error: 'Failed to create payment intent' });
        }

        res.json({
            success: true,
            paymentIntentId: paymentIntent.id,
            clientSecret: paymentIntent.client_secret,
        });
    } catch (error: any) {
        console.error('Stripe payment intent error:', error);
        res.status(500).json({ error: 'Failed to create payment intent: ' + (error?.message || String(error)) });
    }
});

// Seed default plans - PUBLIC endpoint for initial setup
router.get('/seed-defaults', async (req: Request, res: Response) => {
    try {
        console.log('[SEED] Starting seed process...');

        // Create tables if not exist
        await pool.query(`
            CREATE TABLE IF NOT EXISTS subscription_plans (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                description TEXT,
                credits_per_month INTEGER NOT NULL,
                price DECIMAL NOT NULL,
                google_play_product_id TEXT,
                notes_limit INTEGER,
                mcp_sources_limit INTEGER,
                mcp_tokens_limit INTEGER,
                mcp_api_calls_per_day INTEGER,
                is_free_plan BOOLEAN DEFAULT false,
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS user_subscriptions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                plan_id UUID REFERENCES subscription_plans(id),
                current_credits INTEGER DEFAULT 0,
                credits_consumed_this_month INTEGER DEFAULT 0,
                last_renewal_date TIMESTAMPTZ,
                next_renewal_date TIMESTAMPTZ,
                created_at TIMESTAMPTZ DEFAULT NOW(),
                updated_at TIMESTAMPTZ DEFAULT NOW(),
                UNIQUE(user_id)
            );

            CREATE TABLE IF NOT EXISTS credit_transactions (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                amount INTEGER NOT NULL,
                transaction_type TEXT NOT NULL,
                description TEXT,
                balance_after INTEGER,
                metadata JSONB,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );

            CREATE TABLE IF NOT EXISTS credit_packages (
                id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
                name TEXT NOT NULL,
                credits INTEGER NOT NULL,
                price DECIMAL NOT NULL,
                google_play_product_id TEXT,
                is_active BOOLEAN DEFAULT true,
                created_at TIMESTAMPTZ DEFAULT NOW()
            );
        `);

        // Seed plans
        const plans = await pool.query('SELECT COUNT(*) FROM subscription_plans');
        if (parseInt(plans.rows[0].count) === 0) {
            await pool.query(`
                INSERT INTO subscription_plans (
                  name, credits_per_month, price, is_free_plan, description, google_play_product_id,
                  notes_limit, mcp_sources_limit, mcp_tokens_limit, mcp_api_calls_per_day
                ) VALUES
                ('Free', 50, 0, true, 'Basic features, local API keys supported, limited notes + MCP quota', NULL, 100, 10, 3, 100),
                ('Pro', 1000, 9.99, false, 'More notes + MCP quota', 'noteclaw_pro_monthly', 1000, 200, 10, 2000),
                ('Ultra', 5000, 29.99, false, 'Highest notes + MCP quota', 'noteclaw_ultra_monthly', 10000, 1000, 25, 10000)
            `);
        }

        // Seed packages
        const packages = await pool.query('SELECT COUNT(*) FROM credit_packages');
        if (parseInt(packages.rows[0].count) === 0) {
            await pool.query(`
                INSERT INTO credit_packages (name, credits, price, google_play_product_id) VALUES
                ('Starter Pack', 100, 1.99, 'noteclaw_credits_starter'),
                ('Value Pack', 500, 7.99, 'noteclaw_credits_value'),
                ('Pro Pack', 2000, 24.99, 'noteclaw_credits_pro'),
                ('Ultimate Pack', 10000, 99.99, 'noteclaw_credits_ultimate')
            `);
        }

        await ensureGooglePlayCatalogReady();

        res.json({ success: true, message: 'Database seeded successfully' });
    } catch (error) {
        console.error('Seed error:', error);
        res.status(500).json({ error: 'Seeding failed: ' + error });
    }
});

// Get all active subscription plans - PUBLIC
router.get('/plans', async (req: Request, res: Response) => {
    try {
        await ensureGooglePlayCatalogReady();
        const result = await pool.query(`
            SELECT * FROM subscription_plans 
            WHERE is_active = true 
            ORDER BY price ASC
        `);
        res.json({
            plans: result.rows.map((plan) =>
                attachGooglePlayProductMetadata(plan, 'subscription'),
            ),
        });
    } catch (error) {
        console.error('Error fetching plans:', error);
        res.status(500).json({ error: 'Failed to fetch plans' });
    }
});

// Get credit packages - PUBLIC
router.get('/packages', async (req: Request, res: Response) => {
    try {
        await ensureGooglePlayCatalogReady();
        const result = await pool.query(`
            SELECT * FROM credit_packages
            WHERE is_active = true
            ORDER BY price ASC
        `);
        res.json({
            packages: result.rows.map((pkg) =>
                attachGooglePlayProductMetadata(pkg, 'credit_package'),
            ),
        });
    } catch (error) {
        console.error('Error fetching packages:', error);
        res.status(500).json({ error: 'Failed to fetch packages' });
    }
});

// Create Stripe Checkout Session (requires auth)
router.post('/create-checkout-session', authenticateToken, async (req: AuthRequest, res: Response) => {
    try {
        const { planId } = req.body;
        const userId = req.userId!;

        if (!planId) {
            return res.status(400).json({ error: 'Plan ID is required' });
        }

        // Get the plan details
        const planResult = await pool.query(
            'SELECT * FROM subscription_plans WHERE id = $1 AND is_active = true',
            [planId]
        );

        if (planResult.rows.length === 0) {
            return res.status(404).json({ error: 'Plan not found' });
        }

        const plan = planResult.rows[0];

        // Check if Stripe is configured
        const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
        if (!stripeSecretKey) {
            return res.status(500).json({ error: 'Stripe is not configured' });
        }

        // Dynamic import of Stripe
        const Stripe = (await import('stripe')).default;
        const stripe = new Stripe(stripeSecretKey);

        // Determine the success and cancel URLs
        const baseUrl = process.env.WEB_APP_URL || 'http://localhost:3001';

        // Create a Stripe Checkout Session
        const session = await stripe.checkout.sessions.create({
            payment_method_types: ['card'],
            mode: 'subscription',
            line_items: [
                {
                    price_data: {
                        currency: 'usd',
                        product_data: {
                            name: `${plan.name} Plan`,
                            description: plan.description || `${plan.credits_per_month} credits per month`,
                        },
                        unit_amount: Math.round(parseFloat(plan.price) * 100), // Convert to cents
                        recurring: {
                            interval: 'month',
                        },
                    },
                    quantity: 1,
                },
            ],
            success_url: `${baseUrl}/plans/success?session_id={CHECKOUT_SESSION_ID}&plan_id=${planId}`,
            cancel_url: `${baseUrl}/plans?cancelled=true`,
            metadata: {
                userId: userId,
                planId: planId,
            },
            client_reference_id: userId,
        });

        console.log(`[STRIPE] Created checkout session ${session.id} for user ${userId}, plan ${plan.name}`);

        res.json({
            sessionId: session.id,
            url: session.url
        });
    } catch (error: any) {
        console.error('Stripe checkout error:', error);
        res.status(500).json({ error: 'Failed to create checkout session: ' + error.message });
    }
});

// Stripe Webhook for payment confirmation
router.post('/webhook/stripe', express.raw({ type: 'application/json' }), async (req: Request, res: Response) => {
    const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET;

    if (!stripeSecretKey) {
        return res.status(500).json({ error: 'Stripe not configured' });
    }

    try {
        const Stripe = (await import('stripe')).default;
        const stripe = new Stripe(stripeSecretKey);

        let event;

        if (webhookSecret) {
            const sig = req.headers['stripe-signature'] as string;
            event = stripe.webhooks.constructEvent(req.body, sig, webhookSecret);
        } else {
            // For testing without webhook secret
            event = req.body;
        }

        if (event.type === 'checkout.session.completed') {
            const session = event.data.object;
            const userId = session.metadata?.userId || session.client_reference_id;
            const planId = session.metadata?.planId;

            if (userId && planId) {
                // Get the plan
                const planResult = await pool.query(
                    'SELECT * FROM subscription_plans WHERE id = $1',
                    [planId]
                );

                if (planResult.rows.length > 0) {
                    const plan = planResult.rows[0];

                    // Update user subscription
                    const subResult = await pool.query(
                        'SELECT * FROM user_subscriptions WHERE user_id = $1',
                        [userId]
                    );

                    const currentCredits = subResult.rows[0]?.current_credits || 0;
                    const newBalance = currentCredits + plan.credits_per_month;

                    await pool.query(`
                        UPDATE user_subscriptions
                        SET plan_id = $1,
                            current_credits = $2,
                            credits_consumed_this_month = 0,
                            last_renewal_date = CURRENT_TIMESTAMP,
                            next_renewal_date = CURRENT_TIMESTAMP + INTERVAL '1 month',
                            updated_at = CURRENT_TIMESTAMP
                        WHERE user_id = $3
                    `, [planId, newBalance, userId]);

                    // Record transaction
                    await pool.query(`
                        INSERT INTO credit_transactions 
                        (user_id, amount, transaction_type, description, balance_after, metadata)
                        VALUES ($1, $2, 'plan_upgrade', $3, $4, $5)
                    `, [
                        userId,
                        plan.credits_per_month,
                        `Upgraded to ${plan.name} via Stripe`,
                        newBalance,
                        JSON.stringify({
                            stripe_session_id: session.id,
                            plan_id: planId
                        })
                    ]);

                    console.log(`[STRIPE WEBHOOK] Successfully upgraded user ${userId} to ${plan.name}`);
                }
            }
        }

        res.json({ received: true });
    } catch (error: any) {
        console.error('Stripe webhook error:', error);
        res.status(400).json({ error: 'Webhook error: ' + error.message });
    }
});

// Protected routes
router.use(authenticateToken);

// Get current user's subscription
router.get('/me', async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        console.log(`[SUB] Fetching subscription for user: ${userId}`);

        const result = await pool.query(`
            SELECT 
                us.*,
                sp.name as plan_name,
                sp.credits_per_month,
                sp.price as plan_price,
                sp.is_free_plan
            FROM user_subscriptions us
            JOIN subscription_plans sp ON us.plan_id = sp.id
            WHERE us.user_id = $1
        `, [userId]);

        if (result.rows.length === 0) {
            // Auto-provision free subscription
            console.log(`[SUB] No subscription found, auto-provisioning for user ${userId}`);

            // First check all available plans
            const allPlans = await pool.query(`SELECT id, name, is_free_plan, credits_per_month FROM subscription_plans`);
            console.log(`[SUB] Available plans:`, allPlans.rows);

            let freePlanResult = await pool.query(
                `SELECT id, credits_per_month FROM subscription_plans WHERE is_free_plan = TRUE LIMIT 1`
            );

            if (freePlanResult.rows.length === 0) {
                console.log(`[SUB] No free plan found, creating one...`);
                // Create free plan if it doesn't exist
                freePlanResult = await pool.query(`
                    INSERT INTO subscription_plans (name, credits_per_month, price, is_free_plan, is_active) 
                    VALUES ('Free', 50, 0, true, true)
                    RETURNING id, credits_per_month
                `);
                console.log(`[SUB] Created free plan:`, freePlanResult.rows[0]);
            }

            console.log(`[SUB] Using free plan: ${freePlanResult.rows[0].id} with ${freePlanResult.rows[0].credits_per_month} credits`);

            try {
                await pool.query(`
                    INSERT INTO user_subscriptions (
                        user_id, plan_id, current_credits, 
                        last_renewal_date, next_renewal_date
                    )
                    VALUES (
                        $1, $2, $3,
                        CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 month'
                    )
                `, [userId, freePlanResult.rows[0].id, freePlanResult.rows[0].credits_per_month]);
                console.log(`[SUB] Successfully created subscription for user ${userId}`);
            } catch (insertError: any) {
                console.error(`[SUB] Error inserting subscription:`, insertError.message);
                // Check if it's a duplicate key error (subscription already exists)
                if (insertError.code === '23505') {
                    console.log(`[SUB] Subscription already exists, fetching it...`);
                } else {
                    throw insertError;
                }
            }

            // Fetch the newly created subscription
            const newResult = await pool.query(`
                SELECT 
                    us.*,
                    sp.name as plan_name,
                    sp.credits_per_month,
                    sp.price as plan_price,
                    sp.is_free_plan
                FROM user_subscriptions us
                JOIN subscription_plans sp ON us.plan_id = sp.id
                WHERE us.user_id = $1
            `, [userId]);

            console.log(`[SUB] Returning subscription:`, newResult.rows[0]);
            return res.json({ subscription: newResult.rows[0] });
        }

        console.log(`[SUB] Found existing subscription for user ${userId}:`, result.rows[0]);
        res.json({ subscription: result.rows[0] });
    } catch (error: any) {
        console.error('Error fetching subscription:', error.message, error.stack);
        res.status(500).json({ error: 'Failed to fetch subscription: ' + error.message });
    }
});


// Get credit balance
router.get('/credits', async (req: AuthRequest, res: Response) => {
    try {
        const result = await pool.query(`
            SELECT current_credits, credits_consumed_this_month 
            FROM user_subscriptions 
            WHERE user_id = $1
        `, [req.userId]);

        if (result.rows.length === 0) {
            return res.json({ credits: 0, consumed: 0 });
        }

        res.json({
            credits: result.rows[0].current_credits,
            consumed: result.rows[0].credits_consumed_this_month
        });
    } catch (error) {
        console.error('Error fetching credits:', error);
        res.status(500).json({ error: 'Failed to fetch credits' });
    }
});

// Get credit transaction history
router.get('/transactions', async (req: AuthRequest, res: Response) => {
    try {
        const limit = parseInt(req.query.limit as string) || 50;

        const result = await pool.query(`
            SELECT * FROM credit_transactions
            WHERE user_id = $1
            ORDER BY created_at DESC
            LIMIT $2
        `, [req.userId, limit]);

        res.json({ transactions: result.rows });
    } catch (error) {
        console.error('Error fetching transactions:', error);
        res.status(500).json({ error: 'Failed to fetch transactions' });
    }
});


// Consume credits
router.post('/consume', async (req: AuthRequest, res: Response) => {
    try {
        const { amount, feature, metadata } = req.body;

        if (!amount || amount <= 0) {
            return res.status(400).json({ error: 'Invalid amount' });
        }
        const consumeResult = await consumeCreditsAtomic(
            req.userId!,
            Number(amount),
            typeof feature === 'string' && feature.trim().length > 0
                ? feature.trim()
                : 'unknown_feature',
            metadata && typeof metadata === 'object' ? metadata : undefined,
        );

        if (!consumeResult.success) {
            if (consumeResult.error === 'No subscription found') {
                return res
                    .status(404)
                    .json({ success: false, error: consumeResult.error });
            }

            if (consumeResult.error === 'Insufficient credits') {
                return res.status(402).json({
                    success: false,
                    error: consumeResult.error,
                    newBalance: consumeResult.newBalance,
                    payment_required: true,
                });
            }

            return res.status(400).json({
                success: false,
                error: consumeResult.error || 'Failed to consume credits',
            });
        }

        res.json({ success: true, newBalance: consumeResult.newBalance });
    } catch (error) {
        console.error('Error consuming credits:', error);
        res.status(500).json({ error: 'Failed to consume credits' });
    }
});

// Create subscription for user
router.post('/create', async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        console.log(`[SUB] Creating subscription for user: ${userId}`);

        const existing = await pool.query(
            'SELECT id FROM user_subscriptions WHERE user_id = $1',
            [userId]
        );

        if (existing.rows.length > 0) {
            console.log(`[SUB] Subscription already exists for user ${userId}`);
            return res.json({ message: 'Subscription already exists' });
        }

        const planResult = await pool.query(`
            SELECT id, credits_per_month FROM subscription_plans 
            WHERE is_free_plan = TRUE 
            LIMIT 1
        `);

        console.log(`[SUB] Free plan query result:`, planResult.rows);

        if (planResult.rows.length === 0) {
            console.log(`[SUB] No free plan found!`);
            return res.status(404).json({ error: 'No free plan available' });
        }

        const freePlan = planResult.rows[0];
        console.log(`[SUB] Using free plan: ${freePlan.id} with ${freePlan.credits_per_month} credits`);

        await pool.query(`
            INSERT INTO user_subscriptions (
                user_id, plan_id, current_credits, 
                last_renewal_date, next_renewal_date
            )
            VALUES (
                $1, $2, $3,
                CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '1 month'
            )
        `, [userId, freePlan.id, freePlan.credits_per_month]);

        console.log(`[SUB] Successfully created subscription for user ${userId}`);
        res.json({ message: 'Subscription created', planId: freePlan.id });
    } catch (error) {
        console.error('Error creating subscription:', error);
        res.status(500).json({ error: 'Failed to create subscription' });
    }
});

// Verify and grant Google Play purchases
router.post('/google-play/verify', async (req: AuthRequest, res: Response) => {
    try {
        await ensureGooglePlayCatalogReady();
        const userId = req.userId!;
        const { purchaseType, internalId, productId, purchaseToken, purchaseId } = req.body || {};
        const googlePlayConfig = getGooglePlayBillingConfig();

        if (!googlePlayConfig.configured) {
            return res.status(500).json({ error: 'Google Play Billing is not configured' });
        }

        if (
            purchaseType !== 'subscription' &&
            purchaseType !== 'credit_package'
        ) {
            return res.status(400).json({ error: 'Invalid purchaseType' });
        }

        if (!internalId || !productId || !purchaseToken) {
            return res.status(400).json({
                error: 'internalId, productId, and purchaseToken are required',
            });
        }

        await ensureGooglePlayTables((sql, queryParams) => pool.query(sql, queryParams));

        const existingPurchase = await pool.query(
            `SELECT * FROM google_play_purchases WHERE purchase_token = $1 LIMIT 1`,
            [purchaseToken],
        );

        if (
            existingPurchase.rows.length > 0 &&
            existingPurchase.rows[0].user_id !== userId
        ) {
            return res.status(403).json({
                error: 'This Google Play purchase token is already linked to another account',
            });
        }

        if (purchaseType === 'credit_package') {
            const packageResult = await pool.query(
                'SELECT * FROM credit_packages WHERE id = $1 AND is_active = true',
                [internalId],
            );

            if (packageResult.rows.length === 0) {
                return res.status(404).json({ error: 'Credit package not found' });
            }

            const pkg = packageResult.rows[0];
            const expectedProductId =
                (typeof pkg.google_play_product_id === 'string' &&
                    pkg.google_play_product_id.trim().length > 0
                    ? pkg.google_play_product_id.trim()
                    : null) ?? resolveGooglePlayProductIdForPackage(pkg.name);
            if (!expectedProductId || expectedProductId !== productId) {
                return res.status(400).json({ error: 'Product ID does not match this credit package' });
            }

            const verifiedPurchase = await verifyGooglePlayProductPurchase({
                productId,
                purchaseToken,
            });

            if (verifiedPurchase.purchaseState !== 0) {
                return res.status(409).json({ error: 'Google Play purchase is not completed' });
            }

            const accountId = verifiedPurchase.obfuscatedExternalAccountId;
            if (accountId && accountId !== userId) {
                return res.status(403).json({ error: 'Purchase is linked to a different account' });
            }

            const orderId =
                verifiedPurchase.orderId ||
                purchaseId ||
                purchaseToken;

            if (
                existingPurchase.rows.length > 0 &&
                existingPurchase.rows[0].last_granted_order_id === orderId
            ) {
                const balance = await getCurrentBalance(userId);
                return res.json({
                    success: true,
                    alreadyProcessed: true,
                    newBalance: balance,
                    transactionId: orderId,
                });
            }

            const subResult = await pool.query(
                'SELECT current_credits FROM user_subscriptions WHERE user_id = $1',
                [userId],
            );

            if (subResult.rows.length === 0) {
                return res.status(404).json({ error: 'No subscription found. Please create one first.' });
            }

            const currentCredits = Number(subResult.rows[0].current_credits || 0);
            const newBalance = currentCredits + Number(pkg.credits || 0);

            await pool.query(
                `
                UPDATE user_subscriptions
                SET current_credits = $1, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $2
                `,
                [newBalance, userId],
            );

            await pool.query(
                `
                INSERT INTO credit_transactions
                (user_id, amount, transaction_type, description, balance_after, metadata)
                VALUES ($1, $2, 'purchase', $3, $4, $5)
                `,
                [
                    userId,
                    Number(pkg.credits || 0),
                    `Purchased ${pkg.credits} credits via Google Play`,
                    newBalance,
                    JSON.stringify({
                        package_id: pkg.id,
                        transaction_id: orderId,
                        payment_method: 'google_play',
                        google_play_product_id: productId,
                        google_play_purchase_token: purchaseToken,
                    }),
                ],
            );

            await upsertGooglePlayPurchase({
                userId,
                purchaseToken,
                productId,
                productType: 'credit_package',
                packageName: googlePlayConfig.packageName,
                internalPackageId: pkg.id,
                orderId,
                lastGrantedOrderId: orderId,
                status: String(verifiedPurchase.purchaseState),
                metadata: {
                    acknowledgementState: verifiedPurchase.acknowledgementState,
                    consumptionState: verifiedPurchase.consumptionState,
                    purchaseTimeMillis: verifiedPurchase.purchaseTimeMillis,
                    purchaseType: verifiedPurchase.purchaseType,
                },
            });

            return res.json({
                success: true,
                newBalance,
                transactionId: orderId,
            });
        }

        const planResult = await pool.query(
            'SELECT * FROM subscription_plans WHERE id = $1 AND is_active = true',
            [internalId],
        );

        if (planResult.rows.length === 0) {
            return res.status(404).json({ error: 'Plan not found or inactive' });
        }

        const plan = planResult.rows[0];
        const expectedProductId =
            (typeof plan.google_play_product_id === 'string' &&
                plan.google_play_product_id.trim().length > 0
                ? plan.google_play_product_id.trim()
                : null) ?? resolveGooglePlayProductIdForPlan(plan.name);
        if (!expectedProductId || expectedProductId !== productId) {
            return res.status(400).json({ error: 'Product ID does not match this subscription plan' });
        }

        const verifiedSubscription = await verifyGooglePlaySubscriptionPurchase(
            purchaseToken,
        );

        const verifiedProductId = extractSubscriptionProductId(verifiedSubscription);
        if (!verifiedProductId || verifiedProductId !== productId) {
            return res.status(409).json({ error: 'Verified subscription did not match the requested product' });
        }

        if (!isEntitledSubscriptionState(verifiedSubscription.subscriptionState)) {
            return res.status(409).json({
                error: `Subscription is not currently active (${verifiedSubscription.subscriptionState || 'unknown'})`,
            });
        }

        const accountId =
            verifiedSubscription.externalAccountIdentifiers?.obfuscatedExternalAccountId;
        if (accountId && accountId !== userId) {
            return res.status(403).json({ error: 'Subscription is linked to a different account' });
        }

        const orderId =
            verifiedSubscription.latestOrderId ||
            purchaseId ||
            purchaseToken;

        if (
            existingPurchase.rows.length > 0 &&
            existingPurchase.rows[0].last_granted_order_id === orderId
        ) {
            const balance = await getCurrentBalance(userId);
            return res.json({
                success: true,
                alreadyProcessed: true,
                newBalance: balance,
                transactionId: orderId,
            });
        }

        const subResult = await pool.query(
            'SELECT * FROM user_subscriptions WHERE user_id = $1',
            [userId],
        );

        if (subResult.rows.length === 0) {
            return res.status(404).json({ error: 'No subscription found' });
        }

        const currentSub = subResult.rows[0];
        const currentCredits = Number(currentSub.current_credits || 0);
        const newBalance = currentCredits + Number(plan.credits_per_month || 0);
        const nextRenewalDate =
            extractSubscriptionExpiry(verifiedSubscription) ||
            new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

        await pool.query(
            `
            UPDATE user_subscriptions
            SET plan_id = $1,
                current_credits = $2,
                credits_consumed_this_month = 0,
                last_renewal_date = CURRENT_TIMESTAMP,
                next_renewal_date = $3,
                updated_at = CURRENT_TIMESTAMP
            WHERE user_id = $4
            `,
            [plan.id, newBalance, nextRenewalDate.toISOString(), userId],
        );

        await pool.query(
            `
            INSERT INTO credit_transactions
            (user_id, amount, transaction_type, description, balance_after, metadata)
            VALUES ($1, $2, 'plan_upgrade', $3, $4, $5)
            `,
            [
                userId,
                Number(plan.credits_per_month || 0),
                `Upgraded to ${plan.name} via Google Play`,
                newBalance,
                JSON.stringify({
                    old_plan_id: currentSub.plan_id,
                    new_plan_id: plan.id,
                    transaction_id: orderId,
                    payment_method: 'google_play',
                    google_play_product_id: productId,
                    google_play_purchase_token: purchaseToken,
                }),
            ],
        );

        await upsertGooglePlayPurchase({
            userId,
            purchaseToken,
            productId,
            productType: 'subscription',
            packageName: googlePlayConfig.packageName,
            internalPlanId: plan.id,
            orderId,
            lastGrantedOrderId: orderId,
            latestExpiryTime: nextRenewalDate,
            status: verifiedSubscription.subscriptionState,
            metadata: {
                acknowledgementState: verifiedSubscription.acknowledgementState,
                lineItems: verifiedSubscription.lineItems,
                externalAccountIdentifiers:
                    verifiedSubscription.externalAccountIdentifiers,
            },
        });

        return res.json({
            success: true,
            newBalance,
            transactionId: orderId,
        });
    } catch (error: any) {
        console.error('Google Play verification error:', error);
        res.status(500).json({
            error:
                'Failed to verify Google Play purchase: ' +
                (error?.message || String(error)),
        });
    }
});

// Add credits after purchase (PayPal/Stripe)
router.post('/add-credits', async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        const { packageId, transactionId, paymentMethod } = req.body;

        if (!transactionId) {
            return res.status(400).json({ error: 'Transaction ID is required' });
        }

        if (!packageId || typeof packageId !== 'string') {
            return res.status(400).json({ error: 'Credit package is required' });
        }

        const normalizedPaymentMethod =
            typeof paymentMethod === 'string' ? paymentMethod.trim().toLowerCase() : 'stripe';
        if (normalizedPaymentMethod !== 'stripe') {
            return res.status(400).json({
                error: 'Unsupported payment method. Credit packs must be verified with Stripe or Google Play.',
            });
        }

        const packageResult = await pool.query(
            'SELECT id, name, credits, price FROM credit_packages WHERE id = $1 AND is_active = true',
            [packageId],
        );

        if (packageResult.rows.length === 0) {
            return res.status(404).json({ error: 'Credit package not found' });
        }

        const pkg = packageResult.rows[0];
        const expectedCredits = Number(pkg.credits || 0);
        const expectedAmountCents = parsePriceToCents(pkg.price);
        const normalizedTransactionId = String(transactionId).trim();

        await verifyStripePaymentIntent({
            paymentIntentId: normalizedTransactionId,
            userId,
            expectedPackageId: String(pkg.id),
            expectedAmountCents,
        });

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const existingTx = await client.query(
                `SELECT id FROM credit_transactions WHERE metadata->>'transaction_id' = $1 LIMIT 1`,
                [normalizedTransactionId],
            );

            if (existingTx.rows.length > 0) {
                await client.query('ROLLBACK');
                return res.status(409).json({ error: 'Transaction already processed' });
            }

            const subResult = await client.query(
                `SELECT current_credits FROM user_subscriptions WHERE user_id = $1 FOR UPDATE`,
                [userId],
            );

            if (subResult.rows.length === 0) {
                await client.query('ROLLBACK');
                return res
                    .status(404)
                    .json({ error: 'No subscription found. Please create one first.' });
            }

            const currentCredits = Number(subResult.rows[0].current_credits || 0);
            const newBalance = currentCredits + expectedCredits;

            await client.query(
                `
                UPDATE user_subscriptions
                SET current_credits = $1, updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $2
                `,
                [newBalance, userId],
            );

            await client.query(
                `
                INSERT INTO credit_transactions
                (user_id, amount, transaction_type, description, balance_after, metadata)
                VALUES ($1, $2, 'purchase', $3, $4, $5)
                `,
                [
                    userId,
                    expectedCredits,
                    `Purchased ${pkg.name} via Stripe`,
                    newBalance,
                    JSON.stringify({
                        package_id: pkg.id,
                        transaction_id: normalizedTransactionId,
                        payment_method: 'stripe',
                        stripe_payment_intent_id: normalizedTransactionId,
                    }),
                ],
            );

            await client.query('COMMIT');

            console.log(
                `[CREDITS] Added ${expectedCredits} credits for user ${userId}. New balance: ${newBalance}`,
            );

            return res.json({
                success: true,
                newBalance,
                message: `Successfully added ${expectedCredits} credits`,
            });
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    } catch (error) {
        if (error instanceof PaymentVerificationError) {
            return res.status(error.statusCode).json({ error: error.message });
        }
        console.error('Error adding credits:', error);
        res.status(500).json({ error: 'Failed to add credits' });
    }
});

// Upgrade plan
router.post('/upgrade', async (req: AuthRequest, res: Response) => {
    try {
        const userId = req.userId!;
        const { planId, transactionId } = req.body;

        if (!planId || typeof planId !== 'string') {
            return res.status(400).json({ error: 'Plan ID is required' });
        }

        if (!transactionId || typeof transactionId !== 'string') {
            return res.status(400).json({ error: 'Transaction ID is required' });
        }

        const planResult = await pool.query(
            'SELECT * FROM subscription_plans WHERE id = $1 AND is_active = true',
            [planId]
        );

        if (planResult.rows.length === 0) {
            return res.status(404).json({ error: 'Plan not found or inactive' });
        }

        const newPlan = planResult.rows[0];
        const normalizedTransactionId = transactionId.trim();
        await verifyStripePaymentIntent({
            paymentIntentId: normalizedTransactionId,
            userId,
            expectedPlanId: String(newPlan.id),
            expectedAmountCents: parsePriceToCents(newPlan.price),
        });

        const client = await pool.connect();
        try {
            await client.query('BEGIN');

            const existingTx = await client.query(
                `SELECT id FROM credit_transactions WHERE metadata->>'transaction_id' = $1 LIMIT 1`,
                [normalizedTransactionId],
            );

            if (existingTx.rows.length > 0) {
                await client.query('ROLLBACK');
                return res.status(409).json({ error: 'Transaction already processed' });
            }

            const subResult = await client.query(
                `SELECT * FROM user_subscriptions WHERE user_id = $1 FOR UPDATE`,
                [userId]
            );

            if (subResult.rows.length === 0) {
                await client.query('ROLLBACK');
                return res.status(404).json({ error: 'No subscription found' });
            }

            const currentSub = subResult.rows[0];
            const newBalance =
                Number(currentSub.current_credits || 0) +
                Number(newPlan.credits_per_month || 0);

            await client.query(
                `
                UPDATE user_subscriptions
                SET plan_id = $1,
                    current_credits = $2,
                    credits_consumed_this_month = 0,
                    last_renewal_date = CURRENT_TIMESTAMP,
                    next_renewal_date = CURRENT_TIMESTAMP + INTERVAL '1 month',
                    updated_at = CURRENT_TIMESTAMP
                WHERE user_id = $3
                `,
                [planId, newBalance, userId]
            );

            await client.query(
                `
                INSERT INTO credit_transactions
                (user_id, amount, transaction_type, description, balance_after, metadata)
                VALUES ($1, $2, 'plan_upgrade', $3, $4, $5)
                `,
                [
                    userId,
                    Number(newPlan.credits_per_month || 0),
                    `Upgraded to ${newPlan.name} via Stripe`,
                    newBalance,
                    JSON.stringify({
                        old_plan_id: currentSub.plan_id,
                        new_plan_id: planId,
                        transaction_id: normalizedTransactionId,
                        payment_method: 'stripe',
                        stripe_payment_intent_id: normalizedTransactionId,
                    })
                ]
            );

            await client.query('COMMIT');

            return res.json({ success: true, newBalance });
        } catch (error) {
            await client.query('ROLLBACK');
            throw error;
        } finally {
            client.release();
        }
    } catch (error) {
        if (error instanceof PaymentVerificationError) {
            return res.status(error.statusCode).json({ error: error.message });
        }
        console.error('Error upgrading plan:', error);
        res.status(500).json({ error: 'Failed to upgrade plan' });
    }
});

export default router;
