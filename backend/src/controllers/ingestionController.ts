import type { Request, Response } from 'express';
import pool from '../config/database.js';
import axios from 'axios';
import pdf from 'pdf-parse';

interface IngestionRequest {
    sourceId: string;
}

interface PDFPage {
    pageNumber: number;
    text: string;
    lines: number;
}

/**
 * Process a source for RAG ingestion
 * This splits the content into chunks, generates embeddings, and stores them.
 */
export const processSource = async (req: Request, res: Response) => {
    try {
        const { sourceId } = req.body as IngestionRequest;

        if (!sourceId) {
            return res.status(400).json({ success: false, error: 'Source ID is required' });
        }

        // 1. Fetch source content and metadata
        // Try with mime_type first, fallback to without if column doesn't exist
        let sourceResult;
        try {
            sourceResult = await pool.query(
                `SELECT title, content, type, mime_type FROM sources WHERE id = $1`,
                [sourceId]
            );
        } catch (queryError: any) {
            // If mime_type column doesn't exist, fallback to query without it
            if (queryError.code === '42703') { // undefined_column error
                console.warn('mime_type column not found, using fallback query');
                sourceResult = await pool.query(
                    `SELECT title, content, type, NULL as mime_type FROM sources WHERE id = $1`,
                    [sourceId]
                );
            } else {
                throw queryError;
            }
        }

        if (sourceResult.rows.length === 0) {
            return res.status(404).json({ success: false, error: 'Source not found' });
        }

        const source = sourceResult.rows[0];

        // Validate source content
        if (!source.content) {
            console.warn(`Source ${sourceId} has no content`);
            return res.status(400).json({
                success: false,
                error: 'Source content is empty'
            });
        }

        // Log source info for debugging
        console.log(`Processing source ${sourceId}: ${source.title} (type: ${source.type}, mime: ${source.mime_type || 'unknown'})`);

        // 2. Determine processing strategy based on source type
        let chunks: string[];
        try {
            if (isPdfSource(source)) {
                chunks = await processPdfSource(source, sourceId);
            } else {
                chunks = processTextSource(source, sourceId);
            }

            console.log(`Generated ${chunks.length} chunks for source ${sourceId}`);
        } catch (error) {
            console.error(`Error processing source ${sourceId}:`, error);
            return res.status(500).json({
                success: false,
                error: 'Failed to process source content',
                details: error instanceof Error ? error.message : 'Unknown error'
            });
        }

        if (chunks.length === 0) {
            console.warn(`No chunks generated for source ${sourceId}`);
            return res.json({
                success: true,
                chunksProcessed: 0,
                chunksStored: 0,
                message: 'No content to process'
            });
        }

        // 3. Call embedding service to store chunks
        try {
            // Call back into this same server instance. Do NOT rely on process.env.PORT here:
            // the server can auto-increment ports if the requested port is in use.
            const selfPort = req.socket?.localPort;
            const selfBaseUrl = selfPort
                ? `http://127.0.0.1:${selfPort}`
                : `http://localhost:${process.env.PORT || 3000}`;

            const response = await axios.post(
                `${selfBaseUrl}/api/rag/embeddings/store`,
                {
                    chunks: chunks.map(text => ({
                        sourceId,
                        content: text,
                        metadata: { title: source.title, type: source.type }
                    }))
                },
                {
                    headers: {
                        'Authorization': req.headers.authorization,
                        'Content-Type': 'application/json'
                    },
                    timeout: 60000 // 60 second timeout for large PDFs
                }
            );

            console.log(`Successfully stored ${response.data.count || chunks.length} chunks for source ${sourceId}`);

            return res.json({
                success: true,
                chunksProcessed: chunks.length,
                chunksStored: response.data.count || chunks.length
            });

        } catch (embeddingError: any) {
            const status = embeddingError?.response?.status;
            const data = embeddingError?.response?.data;
            console.error(`Error storing embeddings for source ${sourceId}:`, {
                message: embeddingError?.message,
                status,
                data,
            });
            return res.status(500).json({
                success: false,
                error: 'Failed to store embeddings',
                details: data || embeddingError.message
            });
        }

    } catch (error: any) {
        console.error('Ingestion error:', error);
        return res.status(500).json({
            success: false,
            error: error.message || 'Unknown ingestion error'
        });
    }
};

/**
 * Check if source is a PDF
 */
function isPdfSource(source: any): boolean {
    return source.type === 'pdf' ||
        source.mime_type === 'application/pdf' ||
        (typeof source.content === 'string' && source.content.startsWith('JVBERi0x'));
}

/**
 * Process PDF source with page-level handling
 */
async function processPdfSource(source: any, sourceId: string): Promise<string[]> {
    console.log(`Processing PDF source ${sourceId}`);

    let pdfBuffer: Buffer;

    // Handle different content formats
    if (typeof source.content === 'string') {
        // Check if it's base64 encoded
        if (source.content.startsWith('JVBERi0x') || source.content.startsWith('data:application/pdf;base64,')) {
            const base64Data = source.content.replace('data:application/pdf;base64,', '');
            pdfBuffer = Buffer.from(base64Data, 'base64');
        } else {
            // Assume it's already text content (shouldn't happen for real PDFs)
            console.warn(`PDF source ${sourceId} appears to be text content, processing as text`);
            return processTextSource(source, sourceId);
        }
    } else {
        throw new Error('Invalid PDF content format');
    }

    try {
        // Parse PDF with pdf-parse
        const pdfData = await pdf(pdfBuffer, {
            // Limit pages to prevent memory issues
            max: 500,
            version: 'v1.10.100'
        });

        console.log(`PDF ${sourceId}: ${pdfData.numpages} pages, ${pdfData.text.length} chars total`);

        // Process each page separately
        const allChunks: string[] = [];
        const pages = extractPdfPages(pdfData);

        for (const page of pages) {
            const cleanText = normalizeText(page.text);
            if (!cleanText) {
                console.log(`Skipping empty page ${page.pageNumber} in PDF ${sourceId}`);
                continue;
            }

            // Check for oversized pages
            if (cleanText.length > 50000) {
                console.warn(`Page ${page.pageNumber} in PDF ${sourceId} is very large (${cleanText.length} chars), splitting`);
                // Split large pages in half before chunking
                const midPoint = Math.floor(cleanText.length / 2);
                const breakPoint = cleanText.lastIndexOf(' ', midPoint);
                const actualBreak = breakPoint > midPoint - 1000 ? breakPoint : midPoint;

                const part1 = cleanText.substring(0, actualBreak);
                const part2 = cleanText.substring(actualBreak);

                allChunks.push(...bulletproofSplitText(part1, 1000, 200));
                allChunks.push(...bulletproofSplitText(part2, 1000, 200));
            } else {
                // Normal page chunking
                const pageChunks = bulletproofSplitText(cleanText, 1000, 200);
                allChunks.push(...pageChunks);
            }

            // Safety check
            if (allChunks.length > 50000) {
                console.warn(`PDF ${sourceId} generated too many chunks, stopping at 50000`);
                break;
            }
        }

        return allChunks;

    } catch (error) {
        console.error(`Error parsing PDF ${sourceId}:`, error);
        throw new Error(`Failed to parse PDF: ${error instanceof Error ? error.message : 'Unknown error'}`);
    }
}

/**
 * Extract pages from PDF data
 */
function extractPdfPages(pdfData: any): PDFPage[] {
    const pages: PDFPage[] = [];

    // pdf-parse doesn't give us individual pages, so we need to split the text
    // This is a simplified approach - in production you might want to use a more sophisticated PDF library
    const fullText = pdfData.text || '';
    const lines = fullText.split('\n');

    // Simple heuristic: split by form feed characters or large gaps
    let currentPage = 1;
    let currentPageText = '';
    let currentPageLines = 0;

    for (const line of lines) {
        // Check for page break indicators
        if (line.includes('\f') || line.includes('Page ') || currentPageLines > 100) {
            if (currentPageText.trim()) {
                pages.push({
                    pageNumber: currentPage,
                    text: currentPageText.trim(),
                    lines: currentPageLines
                });
                currentPage++;
                currentPageText = '';
                currentPageLines = 0;
            }
        }

        currentPageText += line + '\n';
        currentPageLines++;
    }

    // Add the last page
    if (currentPageText.trim()) {
        pages.push({
            pageNumber: currentPage,
            text: currentPageText.trim(),
            lines: currentPageLines
        });
    }

    // If we only got one "page", split it artificially
    if (pages.length === 1 && pages[0].text.length > 10000) {
        const text = pages[0].text;
        const chunks = Math.ceil(text.length / 5000);
        const newPages: PDFPage[] = [];

        for (let i = 0; i < chunks; i++) {
            const start = i * 5000;
            const end = Math.min(start + 5000, text.length);
            const breakPoint = i === chunks - 1 ? end : text.lastIndexOf(' ', end);
            const actualEnd = breakPoint > start ? breakPoint : end;

            newPages.push({
                pageNumber: i + 1,
                text: text.substring(start, actualEnd),
                lines: text.substring(start, actualEnd).split('\n').length
            });
        }

        return newPages;
    }

    return pages;
}

/**
 * Process regular text source
 */
function processTextSource(source: any, sourceId: string): string[] {
    console.log(`Processing text source ${sourceId}`);

    const cleanText = normalizeText(source.content);
    if (!cleanText) {
        console.warn(`Text source ${sourceId} has no valid content after cleaning`);
        return [];
    }

    return bulletproofSplitText(cleanText, 1000, 200);
}

/**
 * Normalize and clean text input
 */
function normalizeText(text: any): string | null {
    if (!text || typeof text !== 'string') {
        return null;
    }

    // Remove null bytes and other problematic characters
    const cleaned = text
        .replace(/\0/g, '')           // Remove null bytes
        .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '') // Remove control chars except \n, \r, \t
        .replace(/\s+/g, ' ')         // Normalize whitespace
        .trim();

    // Check for minimum content length
    if (cleaned.length < 20) {
        return null;
    }

    // Check for garbage content (too many repeated characters)
    const uniqueChars = new Set(cleaned.toLowerCase()).size;
    if (uniqueChars < 10 && cleaned.length > 100) {
        console.warn('Text appears to be garbage (too few unique characters)');
        return null;
    }

    return cleaned;
}

/**
 * Bulletproof text splitting with all safety measures
 */
function bulletproofSplitText(text: string, chunkSize: number = 1000, overlap: number = 200): string[] {
    if (!text || typeof text !== 'string') {
        return [];
    }

    // Validate parameters
    if (chunkSize <= 0 || overlap < 0 || overlap >= chunkSize) {
        throw new Error(`Invalid chunk parameters: chunkSize=${chunkSize}, overlap=${overlap}`);
    }

    const chunks: string[] = [];
    let start = 0;
    const step = chunkSize - overlap;

    while (start < text.length) {
        const end = Math.min(start + chunkSize, text.length);
        const chunk = text.slice(start, end).trim();

        if (chunk.length > 0) {
            chunks.push(chunk);
        }

        start += step;

        // HARD safety guard
        if (chunks.length > 50000) {
            throw new Error('Too many chunks — aborting ingestion');
        }
    }

    return chunks;
}
