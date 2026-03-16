import type { Request, Response } from 'express';
import { GoogleGenerativeAI } from '@google/generative-ai';
import pool from '../config/database.js';

// Initialize Gemini API
const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || '');
const embeddingModel = genAI.getGenerativeModel({ model: 'text-embedding-004' });

interface GenerateEmbeddingRequest {
    text: string;
}

interface SearchRequest {
    query: string;
    notebookId?: string;
    limit?: number;
    threshold?: number;
}

/**
 * Generate embedding for a text string using Gemini
 */
export const generateEmbedding = async (req: Request, res: Response) => {
    try {
        const { text } = req.body as GenerateEmbeddingRequest;

        if (!text) {
            return res.status(400).json({ success: false, error: 'Text is required' });
        }

        const result = await embeddingModel.embedContent(text);
        const embedding = result.embedding.values;

        return res.json({
            success: true,
            embedding
        });

    } catch (error: any) {
        console.error('Embedding generation error:', error);
        return res.status(500).json({ success: false, error: error.message });
    }
};

/**
 * Semantic search using vector embeddings
 */
export const searchEmbeddings = async (req: Request, res: Response) => {
    try {
        const { query, notebookId, limit = 10, threshold = 0.5 } = req.body as SearchRequest;
        const userId = (req as any).user?.userId;

        if (!query) {
            return res.status(400).json({ success: false, error: 'Query is required' });
        }

        // 1. Generate embedding for the query
        const result = await embeddingModel.embedContent(query);
        const queryEmbedding = result.embedding.values;

        // Format embedding for SQL (pgvector format: [1,2,3])
        const embeddingString = `[${queryEmbedding.join(',')}]`;

        // 2. Perform vector similarity search
        // We join with sources and notebooks to enforce permissions
        let sqlQuery = `
      SELECT 
        c.id, c.content, c.metadata, c.source_id,
        s.title as source_title, s.type as source_type,
        1 - (c.embedding <=> $1) as similarity
      FROM chunks c
      JOIN sources s ON c.source_id = s.id
      JOIN notebooks n ON s.notebook_id = n.id
      WHERE n.user_id = $2
    `;

        const params: any[] = [embeddingString, userId];

        if (notebookId) {
            sqlQuery += ` AND n.id = $3`;
            params.push(notebookId);
        }

        sqlQuery += ` AND 1 - (c.embedding <=> $1) > ${threshold}`;
        sqlQuery += ` ORDER BY similarity DESC LIMIT ${limit}`;

        const searchResult = await pool.query(sqlQuery, params);

        return res.json({
            success: true,
            results: searchResult.rows
        });

    } catch (error: any) {
        console.error('Vector search error:', error);
        return res.status(500).json({ success: false, error: error.message });
    }
};

/**
 * Store embeddings for chunks (Internal/Batch usage)
 */
export const storeEmbeddings = async (req: Request, res: Response) => {
    const client = await pool.connect();
    try {
        const { chunks } = req.body; // Expects [{ sourceId, content, metadata }]

        if (!Array.isArray(chunks)) {
            return res.status(400).json({ success: false, error: 'Chunks array required' });
        }

        // Verify vector search schema is present. Without this, inserts will fail and can
        // poison a transaction (Postgres aborts the whole transaction after any statement error).
        const schema = await client.query(
            `
        SELECT
          EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'chunks') AS has_chunks,
          EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'chunks' AND column_name = 'embedding') AS has_embedding_column
      `
        );

        const hasChunks = Boolean(schema.rows?.[0]?.has_chunks);
        const hasEmbeddingColumn = Boolean(schema.rows?.[0]?.has_embedding_column);

        if (!hasChunks || !hasEmbeddingColumn) {
            return res.status(500).json({
                success: false,
                error: 'VECTOR_SEARCH_NOT_INITIALIZED',
                message: 'Vector search schema is missing. Apply backend/migrations/enable_vector_search.sql to create the chunks table and pgvector extension.',
            });
        }

        await client.query('BEGIN');

        const results: string[] = [];
        let failedEmbeddings = 0;
        let failedInserts = 0;

        // Process in batches
        for (const chunk of chunks) {
            const sourceId = chunk?.sourceId;
            const content = typeof chunk?.content === 'string' ? chunk.content : '';
            const metadata = chunk?.metadata && typeof chunk.metadata === 'object' ? chunk.metadata : {};

            if (!sourceId || content.trim() === '') {
                failedEmbeddings += 1;
                continue;
            }

            // Generate embedding
            try {
                const result = await embeddingModel.embedContent(content);
                const embedding = result.embedding.values;

                // Gemini text-embedding-004 is 768 dimensions. Enforce the expected size for vector(768).
                if (!Array.isArray(embedding) || embedding.length !== 768) {
                    console.warn('Unexpected embedding dimension:', embedding?.length);
                    failedEmbeddings += 1;
                    continue;
                }

                const embeddingString = `[${embedding.join(',')}]`;

                // Use a savepoint so a single insert failure doesn't abort the entire transaction.
                await client.query('SAVEPOINT sp_chunk');
                try {
                    const insertResult = await client.query(
                        `INSERT INTO chunks (source_id, content, metadata, embedding)
             VALUES ($1, $2, $3, $4::vector)
             RETURNING id`,
                        [sourceId, content, metadata, embeddingString]
                    );

                    results.push(insertResult.rows[0].id);
                    await client.query('RELEASE SAVEPOINT sp_chunk');
                } catch (insertErr) {
                    failedInserts += 1;
                    console.warn('Failed to insert chunk:', insertErr);
                    await client.query('ROLLBACK TO SAVEPOINT sp_chunk').catch(() => { });
                    await client.query('RELEASE SAVEPOINT sp_chunk').catch(() => { });
                }
            } catch (e) {
                failedEmbeddings += 1;
                console.warn('Failed to embed chunk:', e);
            }
        }

        await client.query('COMMIT');

        return res.json({
            success: true,
            count: results.length,
            failedEmbeddings,
            failedInserts,
            chunkIds: results
        });

    } catch (error: any) {
        await client.query('ROLLBACK').catch(() => { });
        console.error('Store embeddings error:', error);
        return res.status(500).json({ success: false, error: error.message });
    } finally {
        client.release();
    }
};
