import type { Request, Response } from 'express';
import axios from 'axios';
import * as cheerio from 'cheerio';

interface WebContentExtractRequest {
    url: string;
}

/**
 * Extract content from web URLs
 * Converts HTML to clean text
 */
export const extractWebContent = async (req: Request, res: Response) => {
    try {
        const { url } = req.body as WebContentExtractRequest;

        if (!url) {
            return res.status(400).json({
                success: false,
                error: 'URL is required'
            });
        }

        // Validate URL
        if (!isValidUrl(url)) {
            return res.status(400).json({
                success: false,
                error: 'Invalid URL format'
            });
        }

        // Fetch the web page
        const response = await axios.get(url, {
            timeout: 30000,
            maxContentLength: 10 * 1024 * 1024, // 10MB limit
            headers: {
                'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0; +https://noteclaw.com/bot)',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'en-US,en;q=0.5',
            }
        });

        if (response.status !== 200) {
            return res.status(response.status).json({
                success: false,
                error: `Failed to fetch URL: HTTP ${response.status}`
            });
        }

        // Extract and clean content
        const content = extractTextFromHtml(response.data, url);

        // Get metadata
        const metadata = extractMetadata(response.data, url);

        return res.json({
            success: true,
            content,
            metadata
        });

    } catch (error: any) {
        console.error('Web content extraction error:', error);

        const statusCode = error.response?.status || 500;
        const errorMessage = error.code === 'ENOTFOUND'
            ? 'Website not found. Please check the URL'
            : error.code === 'ETIMEDOUT'
                ? 'Request timed out. The website took too long to respond'
                : error.response?.status === 403
                    ? 'Access denied. The website blocked our request'
                    : error.response?.status === 404
                        ? 'Page not found (404)'
                        : error.message || 'Failed to extract web content';

        return res.status(statusCode).json({
            success: false,
            error: errorMessage
        });
    }
};

/**
 * Validate URL format
 */
function isValidUrl(url: string): boolean {
    try {
        const urlObj = new URL(url);
        return urlObj.protocol === 'http:' || urlObj.protocol === 'https:';
    } catch {
        return false;
    }
}

/**
 * Extract clean text from HTML
 */
function extractTextFromHtml(html: string, url: string): string {
    const $ = cheerio.load(html);

    // Remove unwanted elements
    $('script').remove();
    $('style').remove();
    $('noscript').remove();
    $('iframe').remove();
    $('nav').remove();
    $('footer').remove();
    $('header').remove();
    $('.advertisement').remove();
    $('.ad').remove();
    $('#comments').remove();

    // Try to get main content area
    const mainContent =
        $('article').text() ||
        $('main').text() ||
        $('.content').text() ||
        $('.post-content').text() ||
        $('.article-content').text() ||
        $('body').text();

    // Clean up text
    let text = mainContent
        .replace(/\s+/g, ' ')  // Normalize whitespace
        .replace(/\n{3,}/g, '\n\n')  // Remove excessive newlines
        .trim();

    // Limit content size (25000 characters)
    if (text.length > 25000) {
        text = text.substring(0, 25000) + '\n\n... (content truncated)';
    }

    // Format with title if available
    const title = $('title').text() || $('h1').first().text() || new URL(url).hostname;

    return `# ${title}\n\nSource: ${url}\n\n${text}`;
}

/**
 * Extract metadata from HTML
 */
function extractMetadata(html: string, url: string): any {
    const $ = cheerio.load(html);

    return {
        title:
            $('meta[property="og:title"]').attr('content') ||
            $('meta[name="twitter:title"]').attr('content') ||
            $('title').text() ||
            'Web Page',
        description:
            $('meta[property="og:description"]').attr('content') ||
            $('meta[name="description"]').attr('content') ||
            $('meta[name="twitter:description"]').attr('content') ||
            '',
        image:
            $('meta[property="og:image"]').attr('content') ||
            $('meta[name="twitter:image"]').attr('content') ||
            '',
        author:
            $('meta[name="author"]').attr('content') ||
            $('meta[property="article:author"]').attr('content') ||
            '',
        publishedDate:
            $('meta[property="article:published_time"]').attr('content') ||
            $('meta[name="publish-date"]').attr('content') ||
            '',
        url,
        domain: new URL(url).hostname
    };
}
