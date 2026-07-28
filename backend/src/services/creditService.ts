import pool from '../config/database.js';

/**
 * Credit costs for different AI features
 * These should match the client-side CreditCosts class
 */
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
    deepResearch: 5,
    codeReview: 2,

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
    | 'web_search'
    | 'deep_research'
    | 'code_review';

export function getFeatureCreditCost(
    feature: MeteredCreditFeature,
    options: { depth?: string } = {}
): number {
    switch (feature) {
        case 'notebook_chat':
            return CreditCosts.notebookChat;
        case 'web_search':
            return CreditCosts.webSearch;
        case 'deep_research':
            return options.depth === 'deep'
                ? CreditCosts.deepResearch * 2
                : CreditCosts.deepResearch;
        case 'code_review':
            return CreditCosts.codeReview;
        case 'chat_message':
        default:
            return CreditCosts.chatMessage;
    }
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
    if (!Number.isInteger(amount) || amount <= 0) {
        return {
            success: false,
            newBalance: await getCreditBalance(userId),
            error: 'Credit amount must be a positive integer',
        };
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
