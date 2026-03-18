import axios from 'axios';
import { v4 as uuidv4 } from 'uuid';
import pool from '../config/database.js';
import { generateWithGemini, generateWithOpenRouter, type ChatMessage } from './aiService.js';

const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));

// Research depth configuration
export type ResearchDepth = 'quick' | 'standard' | 'deep';
export type ResearchTemplate = 'general' | 'academic' | 'productComparison' | 'marketAnalysis' | 'howToGuide' | 'prosAndCons';

export interface ResearchConfig {
    depth: ResearchDepth;
    template: ResearchTemplate;
    notebookId?: string;
    useNotebookContext?: boolean;
    useContextEngineering?: boolean;
    provider?: 'gemini' | 'openrouter';
    model?: string;
}

export interface ResearchSource {
    title: string;
    url: string;
    content: string;
    snippet?: string;
    credibility: string;
    credibilityScore: number;
}

export interface ResearchProgress {
    status: string;
    progress: number;
    sources?: ResearchSource[];
    images?: string[];
    videos?: string[];
    result?: string;
    isComplete: boolean;
}

// Domain credibility mappings
const ACADEMIC_DOMAINS = ['.edu', '.ac.uk', '.ac.', 'scholar.google', 'researchgate', 'academia.edu', 'arxiv.org', 'pubmed', 'jstor'];
const GOVERNMENT_DOMAINS = ['.gov', '.gov.uk', '.gov.au', '.mil'];
const NEWS_DOMAINS = ['reuters.com', 'apnews.com', 'bbc.com', 'nytimes.com', 'wsj.com', 'theguardian.com', 'washingtonpost.com', 'bloomberg.com', 'forbes.com', 'techcrunch.com', 'wired.com'];
const PROFESSIONAL_DOMAINS = ['microsoft.com', 'google.com', 'aws.amazon.com', 'developer.', 'docs.', 'stackoverflow.com', 'github.com', 'medium.com'];

function getSourceCredibility(url: string): { credibility: string; score: number } {
    const lowerUrl = url.toLowerCase();

    for (const domain of ACADEMIC_DOMAINS) {
        if (lowerUrl.includes(domain)) return { credibility: 'academic', score: 95 };
    }
    for (const domain of GOVERNMENT_DOMAINS) {
        if (lowerUrl.includes(domain)) return { credibility: 'government', score: 90 };
    }
    for (const domain of NEWS_DOMAINS) {
        if (lowerUrl.includes(domain)) return { credibility: 'news', score: 80 };
    }
    for (const domain of PROFESSIONAL_DOMAINS) {
        if (lowerUrl.includes(domain)) return { credibility: 'professional', score: 75 };
    }
    if (lowerUrl.includes('blog') || lowerUrl.includes('wordpress') || lowerUrl.includes('blogspot')) {
        return { credibility: 'blog', score: 50 };
    }
    return { credibility: 'unknown', score: 60 };
}

function getDepthConfig(depth: ResearchDepth) {
    switch (depth) {
        case 'quick': return { maxSources: 3, subQueryCount: 3, sourcesPerQuery: 2 };
        case 'standard': return { maxSources: 7, subQueryCount: 5, sourcesPerQuery: 3 };
        case 'deep': return { maxSources: 15, subQueryCount: 8, sourcesPerQuery: 5 };
    }
}

function getTemplatePrompt(template: ResearchTemplate): string {
    switch (template) {
        case 'academic':
            return `Structure as academic paper: Abstract, Introduction, Literature Review, Methodology, Findings, Discussion, Conclusion, References (APA format).`;
        case 'productComparison':
            return `Structure as comparison: Executive Summary, Products Overview, Feature Comparison Table, Pricing, Pros/Cons, Recommendations.`;
        case 'marketAnalysis':
            return `Structure as market analysis: Executive Summary, Market Overview, Key Players, Trends, Challenges, Competitive Landscape, Future Outlook.`;
        case 'howToGuide':
            return `Structure as how-to guide: Overview, Prerequisites, Step-by-Step Instructions, Tips, Common Mistakes, Troubleshooting.`;
        case 'prosAndCons':
            return `Structure as balanced analysis: Overview, Advantages (with evidence), Disadvantages (with evidence), Who Should Consider, Alternatives, Final Assessment.`;
        default:
            return `Structure: Executive Summary, Introduction, Main Analysis, Key Findings, Practical Applications, Conclusion, Sources.`;
    }
}

// Serper API for web search
export async function searchWeb(query: string, num: number = 5): Promise<any[]> {
    const apiKey = process.env.SERPER_API_KEY;
    if (!apiKey) {
        console.warn('[Research] SERPER_API_KEY not configured; returning empty search results');
        return [];
    }

    let retries = 3;
    let delay = 2000;

    while (retries > 0) {
        try {
            const response = await axios.post(
                'https://google.serper.dev/search',
                { q: query, num },
                {
                    headers: { 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
                    timeout: 15000 // 15 second timeout
                }
            );
            return response.data.organic || [];
        } catch (error: any) {
            if (error.response?.status === 429) {
                console.warn(`[Research] Serper rate limit hit (429). Retrying in ${delay}ms...`);
                await sleep(delay);
                delay *= 2;
                retries--;
                continue;
            }
            console.error('Serper search error:', error.message);
            return [];
        }
    }
    console.error('[Research] Serper search failed after retries due to rate limiting.');
    return [];
}

export async function searchImages(query: string, num: number = 5): Promise<string[]> {
    const apiKey = process.env.SERPER_API_KEY;
    if (!apiKey) return [];

    let retries = 3;
    let delay = 2000;

    while (retries > 0) {
        try {
            const response = await axios.post(
                'https://google.serper.dev/images',
                { q: query, num },
                {
                    headers: { 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
                    timeout: 15000 // 15 second timeout
                }
            );
            return (response.data.images || []).map((img: any) => img.imageUrl).filter(Boolean);
        } catch (error: any) {
            if (error.response?.status === 429) {
                console.warn(`[Research] Serper Images rate limit hit (429). Retrying in ${delay}ms...`);
                await sleep(delay);
                delay *= 2;
                retries--;
                continue;
            }
            return [];
        }
    }
    return [];
}

export async function searchVideos(query: string, num: number = 3): Promise<string[]> {
    const apiKey = process.env.SERPER_API_KEY;
    if (!apiKey) return [];

    let retries = 3;
    let delay = 2000;

    while (retries > 0) {
        try {
            const response = await axios.post(
                'https://google.serper.dev/videos',
                { q: query, num },
                {
                    headers: { 'X-API-KEY': apiKey, 'Content-Type': 'application/json' },
                    timeout: 15000 // 15 second timeout
                }
            );
            return (response.data.videos || []).map((v: any) => v.link).filter(Boolean);
        } catch (error: any) {
            if (error.response?.status === 429) {
                console.warn(`[Research] Serper Videos rate limit hit (429). Retrying in ${delay}ms...`);
                await sleep(delay);
                delay *= 2;
                retries--;
                continue;
            }
            return [];
        }
    }
    return [];
}

export async function fetchPageContent(url: string): Promise<string> {
    try {
        const response = await axios.get(url, {
            timeout: 10000,
            maxContentLength: 100000, // Limit to 100KB
            headers: { 'User-Agent': 'Mozilla/5.0 (compatible; ResearchBot/1.0)' }
        });

        // Basic HTML to text extraction with strict limits
        let text = response.data;
        if (typeof text === 'string') {
            text = text
                .replace(/<script[^>]*>[\s\S]*?<\/script>/gi, '')
                .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
                .replace(/<[^>]+>/g, ' ')
                .replace(/\s+/g, ' ')
                .trim()
                .substring(0, 3000); // Reduced from 5000 to 3000
        }
        return text || '';
    } catch (error) {
        return '';
    }
}

async function generateSubQueries(
    query: string,
    template: ResearchTemplate,
    count: number,
    notebookContext?: string,
    provider?: 'gemini' | 'openrouter',
    model?: string
): Promise<string[]> {
    const notebookContextPrompt = notebookContext && notebookContext.trim().length > 0
        ? `Use this notebook context to make the queries more aligned with the user's notes:\n${notebookContext}\n`
        : '';

    const messages: ChatMessage[] = [{
        role: 'user',
        content: `Generate ${count} specific search queries to research: "${query}"
Template focus: ${template}
${notebookContextPrompt}
Return only queries, one per line, no bullets or numbers.`
    }];

    try {
        if (provider === 'openrouter') {
            const response = model
                ? await generateWithOpenRouter(messages, model)
                : await generateWithOpenRouter(messages);
            return response.split('\n').map(l => l.trim()).filter(l => l.length > 0).slice(0, count);
        }
        const response = model
            ? await generateWithGemini(messages, model)
            : await generateWithGemini(messages);
        return response.split('\n').map(l => l.trim()).filter(l => l.length > 0).slice(0, count);
    } catch (error: any) {
        try {
            const response = model
                ? await generateWithOpenRouter(messages, model)
                : await generateWithOpenRouter(messages);
            return response.split('\n').map(l => l.trim()).filter(l => l.length > 0).slice(0, count);
        } catch (_) {
            return [query, `${query} explained`, `${query} examples`, `${query} benefits`, `${query} challenges`].slice(0, count);
        }
    }
}

async function synthesizeReport(
    query: string,
    sources: ResearchSource[],
    images: string[],
    videos: string[],
    template: ResearchTemplate,
    notebookContext?: string,
    provider?: 'gemini' | 'openrouter',
    model?: string
): Promise<string> {
    if (sources.length === 0) {
        return `No sources were retrieved for "${query}".\n\n` +
            `If you expected results, verify that web search is configured (SERPER_API_KEY) and try again.`;
    }
    // Limit sources and content to prevent memory issues
    const limitedSources = sources.slice(0, 8).map((s, i) => ({
        ...s,
        content: s.content.substring(0, 1500) // Limit each source to 1.5KB
    }));

    const sourcesText = limitedSources.map((s, i) =>
        `Source ${i + 1} [${s.credibility.toUpperCase()} ${s.credibilityScore}%]: ${s.title}\nURL: ${s.url}\nContent: ${s.content}`
    ).join('\n\n---\n\n');

    const templatePrompt = getTemplatePrompt(template);
    const notebookContextPrompt = notebookContext && notebookContext.trim().length > 0
        ? `USER NOTEBOOK CONTEXT (highest priority when relevant):\n${notebookContext}`
        : 'No notebook context provided.';

    const messages: ChatMessage[] = [{
        role: 'user',
        content: `Create a comprehensive research report on: "${query}"

${templatePrompt}

Use markdown formatting. Cite sources with [Title](URL). Prioritize high-credibility sources.
When notebook context exists, align recommendations with user notes and explicitly mention agreements/conflicts between notes and web findings.

SOURCES:
${sourcesText}

${notebookContextPrompt}

IMAGES (embed relevant ones): ${images.slice(0, 4).join(', ')}
VIDEOS (reference relevant ones): ${videos.slice(0, 2).join(', ')}

Write the complete report:`
    }];

    try {
        if (provider === 'openrouter') {
            console.log('[Research] Attempting to generate report with OpenRouter...');
            const result = model
                ? await generateWithOpenRouter(messages, model)
                : await generateWithOpenRouter(messages);
            console.log('[Research] Report generated successfully with OpenRouter');
            return result;
        }

        console.log('[Research] Attempting to generate report with Gemini...');
        const result = model
            ? await generateWithGemini(messages, model)
            : await generateWithGemini(messages);
        console.log('[Research] Report generated successfully with Gemini');
        return result;
    } catch (primaryError: any) {
        console.error('[Research] Primary provider failed:', primaryError.message);
        try {
            if (provider === 'openrouter') {
                console.log('[Research] Falling back to Gemini...');
                const result = model
                    ? await generateWithGemini(messages, model)
                    : await generateWithGemini(messages);
                console.log('[Research] Report generated successfully with Gemini');
                return result;
            }

            console.log('[Research] Falling back to OpenRouter...');
            const result = model
                ? await generateWithOpenRouter(messages, model)
                : await generateWithOpenRouter(messages);
            console.log('[Research] Report generated successfully with OpenRouter');
            return result;
        } catch (secondaryError: any) {
            console.error('[Research] Secondary provider also failed:', secondaryError.message);
            return `# Research Report: ${query}

## Summary
Research completed with ${sources.length} sources found. However, AI synthesis is temporarily unavailable.

## Sources Found

${limitedSources.map((s, i) => `${i + 1}. [${s.title}](${s.url}) - ${s.credibility} (${s.credibilityScore}% credibility)`).join('\n')}

## Note
Please try again later or contact support if this issue persists.`;
        }
    }
}

async function getNotebookContext(
    userId: string,
    notebookId: string,
    query: string
): Promise<string> {
    const searchTerm = `%${query}%`;
    let contextRows = await pool.query(
        `SELECT s.title, s.type, substring(s.content from 1 for 1200) AS content
         FROM sources s
         JOIN notebooks n ON n.id = s.notebook_id
         WHERE n.id = $1 AND n.user_id = $2
           AND (s.title ILIKE $3 OR s.content ILIKE $3)
         ORDER BY s.updated_at DESC
         LIMIT 6`,
        [notebookId, userId, searchTerm]
    );

    if (contextRows.rows.length === 0) {
        contextRows = await pool.query(
            `SELECT s.title, s.type, substring(s.content from 1 for 1200) AS content
             FROM sources s
             JOIN notebooks n ON n.id = s.notebook_id
             WHERE n.id = $1 AND n.user_id = $2
             ORDER BY s.updated_at DESC
             LIMIT 4`,
            [notebookId, userId]
        );
    }

    const chunks = contextRows.rows
        .map((row: any, index: number) => {
            const title = row.title || `Note ${index + 1}`;
            const type = row.type || 'note';
            const content = (row.content || '').toString().trim();
            if (!content) return '';
            return `[${type}] ${title}\n${content}`;
        })
        .filter((chunk: string) => chunk.length > 0);

    return chunks.join('\n\n---\n\n');
}

// Main research function
export async function performCloudResearch(
    userId: string,
    query: string,
    config: ResearchConfig,
    onProgress?: (progress: ResearchProgress) => void
): Promise<{ sessionId: string; report: string; sources: ResearchSource[] }> {
    if (typeof query !== 'string' || query.trim().length === 0) {
        throw new Error('Query is required');
    }
    const normalizedQuery = query.trim();
    const sessionId = uuidv4();
    const depthConfig = getDepthConfig(config.depth);
    const sources: ResearchSource[] = [];
    const allImages: string[] = [];
    const allVideos: string[] = [];
    let notebookContext = '';

    try {
        // Update progress
        onProgress?.({ status: `[${config.depth.toUpperCase()}] Starting research...`, progress: 0.1, isComplete: false });

        // Generate sub-queries
        if (config.useNotebookContext && config.notebookId) {
            onProgress?.({ status: 'Loading notebook context...', progress: 0.12, isComplete: false });
            notebookContext = await getNotebookContext(userId, config.notebookId, normalizedQuery);
        }
        onProgress?.({ status: 'Generating research angles...', progress: 0.15, isComplete: false });
        const subQueries = await generateSubQueries(
            normalizedQuery,
            config.template,
            depthConfig.subQueryCount,
            notebookContext,
            config.provider,
            config.model
        );

        // Initial media search
        const [images, videos] = await Promise.all([
            searchImages(normalizedQuery),
            searchVideos(normalizedQuery)
        ]);
        allImages.push(...images);
        allVideos.push(...videos);

        // Search and collect sources
        let completed = 0;
        for (const subQuery of subQueries) {
            if (sources.length >= depthConfig.maxSources) break;

            const progress = 0.2 + (0.5 * (completed / subQueries.length));
            onProgress?.({
                status: `Searching: "${subQuery}"...`,
                progress,
                sources: [...sources],
                images: [...allImages],
                videos: [...allVideos],
                isComplete: false
            });

            // Search web
            const results = await searchWeb(subQuery, depthConfig.sourcesPerQuery);

            // Search media for sub-query
            const [subImages, subVideos] = await Promise.all([
                searchImages(subQuery, 3),
                searchVideos(subQuery, 2)
            ]);
            allImages.push(...subImages);
            allVideos.push(...subVideos);

            // Process results
            for (const result of results) {
                if (sources.length >= depthConfig.maxSources) break;
                if (sources.some(s => s.url === result.link)) continue;

                const content = await fetchPageContent(result.link);
                const { credibility, score } = getSourceCredibility(result.link);

                sources.push({
                    title: result.title || 'Untitled',
                    url: result.link,
                    content: content || result.snippet || '',
                    snippet: result.snippet,
                    credibility,
                    credibilityScore: score
                });
            }

            completed++;
        }

        // Multi-hop for deep research
        if (config.depth === 'deep' && sources.length < depthConfig.maxSources) {
            onProgress?.({ status: 'Multi-hop: Exploring deeper...', progress: 0.65, sources, isComplete: false });

            // Generate follow-up queries based on initial findings
            const followUpMessages: ChatMessage[] = [{
                role: 'user',
                content: `Based on initial research on "${normalizedQuery}", generate 3 follow-up search queries to explore deeper. Sources found: ${sources.slice(0, 5).map(s => s.title).join(', ')}. Return only queries, one per line.`
            }];

            try {
                const followUpResponse = await generateWithGemini(followUpMessages);
                const followUpQueries = followUpResponse.split('\n').filter(q => q.trim()).slice(0, 3);

                for (const fq of followUpQueries) {
                    if (sources.length >= depthConfig.maxSources) break;
                    const results = await searchWeb(fq, 3);
                    for (const result of results) {
                        if (sources.length >= depthConfig.maxSources) break;
                        if (sources.some(s => s.url === result.link)) continue;

                        const { credibility, score } = getSourceCredibility(result.link);
                        sources.push({
                            title: result.title,
                            url: result.link,
                            content: result.snippet || '',
                            snippet: result.snippet,
                            credibility,
                            credibilityScore: score
                        });
                    }
                }
            } catch (e) {
                console.error('Multi-hop error:', e);
            }
        }

        // Sort by credibility
        sources.sort((a, b) => b.credibilityScore - a.credibilityScore);

        // Deduplicate media
        const uniqueImages = [...new Set(allImages)];
        const uniqueVideos = [...new Set(allVideos)];

        // Synthesize report
        onProgress?.({ status: 'Synthesizing report...', progress: 0.8, sources, images: uniqueImages, videos: uniqueVideos, isComplete: false });

        const report = await synthesizeReport(
            normalizedQuery,
            sources,
            uniqueImages,
            uniqueVideos,
            config.template,
            notebookContext,
            config.provider,
            config.model
        );

        // Save to database
        await pool.query('BEGIN');

        await pool.query(
            `INSERT INTO research_sessions (id, user_id, notebook_id, query, report, depth, template, status)
             VALUES ($1, $2, $3, $4, $5, $6, $7, 'completed')`,
            [sessionId, userId, config.notebookId || null, normalizedQuery, report, config.depth, config.template]
        );

        for (const source of sources) {
            await pool.query(
                `INSERT INTO research_sources (id, session_id, title, url, content, snippet, credibility, credibility_score)
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
                [uuidv4(), sessionId, source.title, source.url, source.content, source.snippet, source.credibility, source.credibilityScore]
            );
        }

        await pool.query('COMMIT');

        onProgress?.({ status: 'Research complete!', progress: 1.0, result: report, sources, images: uniqueImages, videos: uniqueVideos, isComplete: true });

        return { sessionId, report, sources };
    } catch (error: any) {
        await pool.query('ROLLBACK').catch(() => { });
        console.error('Cloud research error:', error);
        throw error;
    }
}

// Start background research job
export async function startBackgroundResearch(
    userId: string,
    query: string,
    config: ResearchConfig
): Promise<string> {
    const jobId = uuidv4();

    // Create job record
    await pool.query(
        `INSERT INTO research_jobs (id, user_id, query, config, status, created_at)
         VALUES ($1, $2, $3, $4, 'pending', NOW())`,
        [jobId, userId, query, JSON.stringify(config)]
    );

    // Start research in background (non-blocking)
    setImmediate(async () => {
        try {
            await pool.query(`UPDATE research_jobs SET status = 'running' WHERE id = $1`, [jobId]);

            const result = await performCloudResearch(userId, query, config, async (progress) => {
                await pool.query(
                    `UPDATE research_jobs SET progress = $1, status_message = $2 WHERE id = $3`,
                    [progress.progress, progress.status, jobId]
                );
            });

            await pool.query(
                `UPDATE research_jobs SET status = 'completed', session_id = $1, completed_at = NOW() WHERE id = $2`,
                [result.sessionId, jobId]
            );
        } catch (error: any) {
            await pool.query(
                `UPDATE research_jobs SET status = 'failed', error = $1 WHERE id = $2`,
                [error.message, jobId]
            );
        }
    });

    return jobId;
}

// Get job status
export async function getResearchJobStatus(jobId: string, userId: string) {
    const result = await pool.query(
        `SELECT * FROM research_jobs WHERE id = $1 AND user_id = $2`,
        [jobId, userId]
    );
    return result.rows[0] || null;
}
