import pool from '../config/database.js';

/** Default tariffs used until an administrator overrides them in PostgreSQL. */
export const CreditCosts = {
    // Chat & Conversation
    chatMessage: 1,
    notebookChat: 1,
    voiceMode: 2,
    meetingMode: 3,

    // Content Generation
    generateFlashcards: 2,
    generateQuiz: 2,
    generateMindMap: 3,
    generateStudyGuide: 3,
    generateInfographic: 5,

    // Research & Search
    webSearch: 1,
    webSearchChat: 3,
    deepResearch: 5,
    codeReview: 2,
    imageGeneration: 5,
    videoGeneration: 20,

    // Audio & Media
    podcastGeneration: 10,
    audioOverview: 5,
    textToSpeech: 2,
    transcription: 3,

    // Ebook
    ebookGeneration: 15,
    ebookChapter: 5,

    // Story & Creative
    storyGeneration: 5,
    mealPlan: 2,

    // Tutor
    tutorSession: 3,

    // Source Processing
    sourceIngestion: 1,
    youtubeTranscript: 2,
};

export type MeteredCreditFeature =
    | 'chat_message'
    | 'notebook_chat'
    | 'image_chat'
    | 'web_search'
    | 'web_search_chat'
    | 'deep_research'
    | 'deep_research_deep'
    | 'code_review'
    | 'image_generation'
    | 'video_generation';

export interface FeatureCreditDefinition {
    key: MeteredCreditFeature;
    label: string;
    description: string;
    defaultCost: number;
}

export const FeatureCreditDefinitions: FeatureCreditDefinition[] = [
    { key: 'chat_message', label: 'Chat message', description: 'Standard AI chat response', defaultCost: CreditCosts.chatMessage },
    { key: 'notebook_chat', label: 'Notebook chat', description: 'Chat grounded in notebook sources', defaultCost: CreditCosts.notebookChat },
    { key: 'image_chat', label: 'Image chat', description: 'Chat request that analyzes an image', defaultCost: 2 },
    { key: 'web_search', label: 'Web search', description: 'Search the live web', defaultCost: CreditCosts.webSearch },
    { key: 'web_search_chat', label: 'Web-search chat', description: 'Search and synthesize results in chat', defaultCost: CreditCosts.webSearchChat },
    { key: 'deep_research', label: 'Deep research', description: 'Standard multi-source research report', defaultCost: CreditCosts.deepResearch },
    { key: 'deep_research_deep', label: 'Extended deep research', description: 'Extended multi-query research report', defaultCost: CreditCosts.deepResearch * 2 },
    { key: 'code_review', label: 'Code review', description: 'AI-assisted code review', defaultCost: CreditCosts.codeReview },
    { key: 'image_generation', label: 'Image generation', description: 'Generate and store one image', defaultCost: CreditCosts.imageGeneration },
    { key: 'video_generation', label: 'Video generation', description: 'Generate and store one video', defaultCost: CreditCosts.videoGeneration },
];

const featureDefinitions = new Map(
    FeatureCreditDefinitions.map((definition) => [definition.key, definition]),
);

export function getDefaultFeatureCreditCost(
    feature: MeteredCreditFeature,
    options: { depth?: string } = {}
): number {
    const resolvedFeature = feature === 'deep_research' && options.depth === 'deep'
        ? 'deep_research_deep'
        : feature;
    return featureDefinitions.get(resolvedFeature)?.defaultCost ?? CreditCosts.chatMessage;
}

export async function ensureFeatureCreditCostsTable(): Promise<void> {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS feature_credit_costs (
            feature_key TEXT PRIMARY KEY,
            credit_cost INTEGER NOT NULL CHECK (credit_cost >= 0),
            updated_by TEXT REFERENCES users(id) ON DELETE SET NULL,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    `);
}

export async function getFeatureCreditCost(
    feature: MeteredCreditFeature,
    options: { depth?: string } = {},
): Promise<number> {
    const resolvedFeature = feature === 'deep_research' && options.depth === 'deep'
        ? 'deep_research_deep'
        : feature;
    const fallback = getDefaultFeatureCreditCost(resolvedFeature);

    try {
        await ensureFeatureCreditCostsTable();
        const result = await pool.query(
            'SELECT credit_cost FROM feature_credit_costs WHERE feature_key = $1',
            [resolvedFeature],
        );
        return result.rows.length > 0
            ? Math.max(0, Number(result.rows[0].credit_cost))
            : fallback;
    } catch (error) {
        console.warn('[CreditService] Falling back to the default tariff:', error);
        return fallback;
    }
}

export async function listFeatureCreditCosts(): Promise<Array<FeatureCreditDefinition & { creditCost: number }>> {
    await ensureFeatureCreditCostsTable();
    const result = await pool.query('SELECT feature_key, credit_cost FROM feature_credit_costs');
    const overrides = new Map<string, number>(
        result.rows.map((row) => [String(row.feature_key), Number(row.credit_cost)]),
    );
    return FeatureCreditDefinitions.map((definition) => ({
        ...definition,
        creditCost: overrides.get(definition.key) ?? definition.defaultCost,
    }));
}

export async function setFeatureCreditCost(
    feature: MeteredCreditFeature,
    creditCost: number,
    updatedBy?: string,
): Promise<number> {
    if (!featureDefinitions.has(feature)) {
        throw new Error(`Unknown metered feature: ${feature}`);
    }
    if (!Number.isInteger(creditCost) || creditCost < 0 || creditCost > 100000) {
        throw new Error('Credit cost must be a whole number between 0 and 100000');
    }

    await ensureFeatureCreditCostsTable();
    await pool.query(
        `INSERT INTO feature_credit_costs (feature_key, credit_cost, updated_by)
         VALUES ($1, $2, $3)
         ON CONFLICT (feature_key) DO UPDATE SET
            credit_cost = EXCLUDED.credit_cost,
            updated_by = EXCLUDED.updated_by,
            updated_at = NOW()`,
        [feature, creditCost, updatedBy || null],
    );
    return creditCost;
}

export interface CreditCheckResult {
    hasEnough: boolean;
    currentBalance: number;
    required: number;
}

export interface CreditConsumeResult {
    success: boolean;
    newBalance: number;
    error?: string;
}

/**
 * Check if user has enough credits
 */
export async function checkCredits(
    userId: string,
    amount: number
): Promise<CreditCheckResult> {
    try {
        const result = await pool.query(
            'SELECT current_credits FROM user_subscriptions WHERE user_id = $1',
            [userId]
        );

        if (result.rows.length === 0) {
            return {
                hasEnough: false,
                currentBalance: 0,
                required: amount,
            };
        }

        const currentBalance = result.rows[0].current_credits;

        return {
            hasEnough: currentBalance >= amount,
            currentBalance,
            required: amount,
        };
    } catch (error) {
        console.error('[CreditService] Error checking credits:', error);
        throw error;
    }
}

/**
 * Consume credits atomically with transaction safety
 * Returns the new balance or throws an error
 */
export async function consumeCredits(
    userId: string,
    amount: number,
    feature: string,
    metadata?: Record<string, any>
): Promise<CreditConsumeResult> {
    if (!Number.isInteger(amount) || amount < 0) {
        return {
            success: false,
            newBalance: await getCreditBalance(userId),
            error: 'Credit amount must be a non-negative integer',
        };
    }

    if (amount === 0) {
        return { success: true, newBalance: await getCreditBalance(userId) };
    }

    const client = await pool.connect();

    try {
        // Start transaction
        await client.query('BEGIN');

        // Lock the row and get current balance
        const subResult = await client.query(
            `SELECT current_credits FROM user_subscriptions 
             WHERE user_id = $1 
             FOR UPDATE`,
            [userId]
        );

        if (subResult.rows.length === 0) {
            await client.query('ROLLBACK');
            return {
                success: false,
                newBalance: 0,
                error: 'No subscription found',
            };
        }

        const currentBalance = subResult.rows[0].current_credits;

        // Check if enough credits
        if (currentBalance < amount) {
            await client.query('ROLLBACK');
            return {
                success: false,
                newBalance: currentBalance,
                error: 'Insufficient credits',
            };
        }

        const newBalance = currentBalance - amount;

        // Update balance
        await client.query(
            `UPDATE user_subscriptions
             SET current_credits = $1,
                 credits_consumed_this_month = credits_consumed_this_month + $2,
                 updated_at = CURRENT_TIMESTAMP
             WHERE user_id = $3`,
            [newBalance, amount, userId]
        );

        // Record transaction
        await client.query(
            `INSERT INTO credit_transactions 
             (user_id, amount, transaction_type, description, balance_after, metadata)
             VALUES ($1, $2, 'consumption', $3, $4, $5)`,
            [
                userId,
                -amount,
                `Used ${amount} credits for ${feature}`,
                newBalance,
                metadata ? JSON.stringify(metadata) : null,
            ]
        );

        // Commit transaction
        await client.query('COMMIT');

        console.log(
            `[CreditService] Consumed ${amount} credits for user ${userId}. New balance: ${newBalance}`
        );

        return {
            success: true,
            newBalance,
        };
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('[CreditService] Error consuming credits:', error);
        throw error;
    } finally {
        client.release();
    }
}

/**
 * Refund a previously charged feature operation.
 * Refunds are recorded as positive ledger entries and never let the monthly
 * consumed counter fall below zero.
 */
export async function refundCredits(
    userId: string,
    amount: number,
    feature: string,
    metadata?: Record<string, any>
): Promise<CreditConsumeResult> {
    if (!Number.isInteger(amount) || amount <= 0) {
        return {
            success: false,
            newBalance: await getCreditBalance(userId),
            error: 'Refund amount must be a positive integer',
        };
    }

    const client = await pool.connect();

    try {
        await client.query('BEGIN');

        const subResult = await client.query(
            `SELECT current_credits FROM user_subscriptions
             WHERE user_id = $1
             FOR UPDATE`,
            [userId]
        );

        if (subResult.rows.length === 0) {
            await client.query('ROLLBACK');
            return {
                success: false,
                newBalance: 0,
                error: 'No subscription found',
            };
        }

        const currentBalance = Number(subResult.rows[0].current_credits || 0);
        const newBalance = currentBalance + amount;

        await client.query(
            `UPDATE user_subscriptions
             SET current_credits = $1,
                 credits_consumed_this_month =
                     GREATEST(0, credits_consumed_this_month - $2),
                 updated_at = CURRENT_TIMESTAMP
             WHERE user_id = $3`,
            [newBalance, amount, userId]
        );

        await client.query(
            `INSERT INTO credit_transactions
             (user_id, amount, transaction_type, description, balance_after, metadata)
             VALUES ($1, $2, 'refund', $3, $4, $5)`,
            [
                userId,
                amount,
                `Refunded ${amount} credits for ${feature}`,
                newBalance,
                metadata ? JSON.stringify(metadata) : null,
            ]
        );

        await client.query('COMMIT');
        return { success: true, newBalance };
    } catch (error) {
        await client.query('ROLLBACK');
        console.error('[CreditService] Error refunding credits:', error);
        throw error;
    } finally {
        client.release();
    }
}

/**
 * Calculate credit cost for AI chat based on features used
 */
export function calculateChatCreditCost(options: {
    useDeepSearch?: boolean;
    hasImage?: boolean;
}): number {
    let cost = CreditCosts.chatMessage; // Base cost

    if (options.useDeepSearch) {
        cost += CreditCosts.deepResearch;
    }

    if (options.hasImage) {
        cost += 1; // Extra credit for image processing
    }

    return cost;
}

/**
 * Get user's current credit balance
 */
export async function getCreditBalance(userId: string): Promise<number> {
    try {
        const result = await pool.query(
            'SELECT current_credits FROM user_subscriptions WHERE user_id = $1',
            [userId]
        );

        if (result.rows.length === 0) {
            return 0;
        }

        return result.rows[0].current_credits;
    } catch (error) {
        console.error('[CreditService] Error getting balance:', error);
        throw error;
    }
}
