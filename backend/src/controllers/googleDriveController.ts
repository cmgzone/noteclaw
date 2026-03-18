import type { Request, Response } from 'express';
import axios from 'axios';

interface GoogleDriveExportRequest {
    url: string;
    fileId?: string;
}

/**
 * Extract content from Google Drive files
 * Supports: Google Docs, Sheets, Slides, and direct files
 */
export const extractGoogleDriveContent = async (req: Request, res: Response) => {
    try {
        const { url, fileId } = req.body as GoogleDriveExportRequest;

        if (!url && !fileId) {
            return res.status(400).json({
                success: false,
                error: 'URL or fileId is required'
            });
        }

        // Extract file ID from URL if not provided
        const extractedFileId = fileId || extractFileIdFromUrl(url);

        if (!extractedFileId) {
            return res.status(400).json({
                success: false,
                error: 'Invalid Google Drive URL'
            });
        }

        // Detect file type
        const fileType = detectFileType(url);

        let content: string;
        let metadata: any = {
            fileId: extractedFileId,
            fileType,
            sourceUrl: url
        };

        try {
            switch (fileType) {
                case 'document':
                    content = await exportGoogleDoc(extractedFileId);
                    metadata.format = 'Google Docs';
                    break;

                case 'spreadsheet':
                    content = await exportGoogleSheet(extractedFileId);
                    metadata.format = 'Google Sheets';
                    break;

                case 'presentation':
                    content = await exportGoogleSlides(extractedFileId);
                    metadata.format = 'Google Slides';
                    break;

                default:
                    // Try to download as plain text or PDF
                    content = await downloadFile(extractedFileId);
                    metadata.format = 'File';
            }

            return res.json({
                success: true,
                content,
                metadata
            });

        } catch (exportError: any) {
            // If export fails, provide helpful error message
            const errorMessage = exportError.response?.status === 403
                ? 'File is not publicly accessible. Please make sure the file sharing settings are set to "Anyone with the link can view"'
                : exportError.response?.status === 404
                    ? 'File not found. Please check the URL'
                    : `Export failed: ${exportError.message}`;

            return res.status(exportError.response?.status || 500).json({
                success: false,
                error: errorMessage,
                fileId: extractedFileId,
                fileType,
                instructions: [
                    'Make sure the Google Drive file is publicly shared',
                    'File sharing must be set to "Anyone with the link can view"',
                    'For Google Docs/Sheets/Slides, export permissions must be enabled'
                ]
            });
        }

    } catch (error: any) {
        console.error('Google Drive extraction error:', error);
        return res.status(500).json({
            success: false,
            error: error.message || 'Failed to extract Google Drive content'
        });
    }
};

/**
 * Extract file ID from various Google Drive URL formats
 */
function extractFileIdFromUrl(url: string): string | null {
    const patterns = [
        /drive\.google\.com\/file\/d\/([a-zA-Z0-9_-]+)/,
        /drive\.google\.com\/open\?id=([a-zA-Z0-9_-]+)/,
        /docs\.google\.com\/document\/d\/([a-zA-Z0-9_-]+)/,
        /docs\.google\.com\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/,
        /docs\.google\.com\/presentation\/d\/([a-zA-Z0-9_-]+)/,
    ];

    for (const pattern of patterns) {
        const match = url.match(pattern);
        if (match) {
            return match[1];
        }
    }

    return null;
}

/**
 * Detect Google Drive file type from URL
 */
function detectFileType(url: string): string {
    if (url.includes('docs.google.com/document')) return 'document';
    if (url.includes('docs.google.com/spreadsheets')) return 'spreadsheet';
    if (url.includes('docs.google.com/presentation')) return 'presentation';
    return 'file';
}

/**
 * Export Google Doc as plain text
 */
async function exportGoogleDoc(fileId: string): Promise<string> {
    const exportUrl = `https://docs.google.com/document/d/${fileId}/export?format=txt`;

    const response = await axios.get(exportUrl, {
        timeout: 30000,
        headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0)'
        }
    });

    if (response.status !== 200) {
        throw new Error(`Failed to export Google Doc: HTTP ${response.status}`);
    }

    return response.data;
}

/**
 * Export Google Sheet as CSV
 */
async function exportGoogleSheet(fileId: string): Promise<string> {
    const exportUrl = `https://docs.google.com/spreadsheets/d/${fileId}/export?format=csv`;

    const response = await axios.get(exportUrl, {
        timeout: 30000,
        headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0)'
        }
    });

    if (response.status !== 200) {
        throw new Error(`Failed to export Google Sheet: HTTP ${response.status}`);
    }

    // Clean up CSV data
    const csvData = response.data;
    const lines = csvData.split('\n');

    // Limit to 500 rows to avoid huge payloads
    const limitedLines = lines.slice(0, 500);
    let content = limitedLines.join('\n');

    if (lines.length > 500) {
        content += `\n\n... (${lines.length - 500} more rows truncated)`;
    }

    return content;
}

/**
 * Export Google Slides as plain text
 */
export async function exportGoogleSlides(fileId: string): Promise<string> {
    // Slides can be exported as plain text (limited)
    const exportUrl = `https://docs.google.com/presentation/d/${fileId}/export?format=txt`;

    try {
        const response = await axios.get(exportUrl, {
            timeout: 30000,
            headers: {
                'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0)'
            }
        });

        if (response.status === 200 && response.data) {
            return response.data;
        }
    } catch (error) {
        // Text export might not be available, try PDF and extract (future enhancement)
        console.warn('Slides text export failed, returning placeholder');
    }

    // Fallback message
    return `Google Slides Presentation
File ID: ${fileId}

Note: Full text extraction from Google Slides is limited. 
The presentation was added but detailed content extraction requires additional processing.
You can still reference this presentation in your AI conversations by describing it.`;
}

/**
 * Download generic file content
 */
async function downloadFile(fileId: string): Promise<string> {
    // For generic files, try to download directly
    const downloadUrl = `https://drive.google.com/uc?export=download&id=${fileId}`;

    const response = await axios.get(downloadUrl, {
        timeout: 30000,
        maxContentLength: 10 * 1024 * 1024, // 10MB limit
        headers: {
            'User-Agent': 'Mozilla/5.0 (compatible; NoteClaw/1.0)'
        }
    });

    if (response.status !== 200) {
        throw new Error(`Failed to download file: HTTP ${response.status}`);
    }

    // If it's text content, return it
    if (typeof response.data === 'string') {
        return response.data;
    }

    // For binary files, return metadata
    return `Google Drive File
File ID: ${fileId}

Note: Binary files require additional processing for content extraction.
The file has been added and can be referenced in your AI conversations.`;
}
