import express, { type Request, type Response } from 'express';
import { ACCOUNT_DELETION_MARKDOWN } from '../content/legalDocuments.js';
import {
    getPrivacyPolicyContent,
    getTermsOfServiceContent,
} from '../services/appSettingsService.js';

const router = express.Router();

router.get('/privacy-policy', async (_req: Request, res: Response) => {
    try {
        const content = (await getPrivacyPolicyContent()).trim();

        res.setHeader('Cache-Control', 'no-store');
        res.type('html').send(renderDocumentPage({
            title: 'Privacy Policy',
            eyebrow: 'NoteClaw',
            content,
        }));
    } catch (error) {
        console.error('Render privacy policy page error:', error);
        res.status(500).type('html').send(renderErrorPage(
            'Privacy Policy',
            'We could not load the privacy policy right now. Please try again shortly.'
        ));
    }
});

router.get('/terms-of-service', async (_req: Request, res: Response) => {
    try {
        const content = (await getTermsOfServiceContent()).trim();

        res.setHeader('Cache-Control', 'no-store');
        res.type('html').send(renderDocumentPage({
            title: 'Terms and Conditions',
            eyebrow: 'NoteClaw',
            content,
        }));
    } catch (error) {
        console.error('Render terms of service page error:', error);
        res.status(500).type('html').send(renderErrorPage(
            'Terms and Conditions',
            'We could not load the terms and conditions right now. Please try again shortly.'
        ));
    }
});

router.get(['/delete-account', '/account-deletion'], (_req: Request, res: Response) => {
    res.setHeader('Cache-Control', 'no-store');
    res.type('html').send(renderDocumentPage({
        title: 'Delete Your NoteClaw Account',
        eyebrow: 'NoteClaw',
        content: ACCOUNT_DELETION_MARKDOWN,
    }));
});

function renderDocumentPage({
    title,
    eyebrow,
    content,
}: {
    title: string;
    eyebrow: string;
    content: string;
}) {
    return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)} | NoteClaw</title>
  <meta name="description" content="NoteClaw ${escapeHtml(title)}" />
  <style>
    :root {
      color-scheme: light;
      --bg: #f5f7fb;
      --card: #ffffff;
      --text: #172033;
      --muted: #5f6b85;
      --border: #d9dfeb;
      --accent-a: #5d68e8;
      --accent-b: #d548a5;
      --shadow: 0 24px 80px rgba(32, 46, 90, 0.12);
    }

    * {
      box-sizing: border-box;
    }

    body {
      margin: 0;
      font-family: "Segoe UI", Arial, sans-serif;
      background:
        radial-gradient(circle at top left, rgba(93, 104, 232, 0.10), transparent 28%),
        radial-gradient(circle at top right, rgba(213, 72, 165, 0.12), transparent 26%),
        var(--bg);
      color: var(--text);
    }

    .shell {
      min-height: 100vh;
      padding: 40px 20px;
    }

    .card {
      max-width: 920px;
      margin: 0 auto;
      background: var(--card);
      border: 1px solid var(--border);
      border-radius: 24px;
      overflow: hidden;
      box-shadow: var(--shadow);
    }

    .hero {
      padding: 28px 32px;
      background: linear-gradient(90deg, var(--accent-a), var(--accent-b));
      color: #fff;
    }

    .eyebrow {
      margin: 0 0 10px;
      font-size: 13px;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      opacity: 0.82;
    }

    h1 {
      margin: 0;
      font-size: clamp(30px, 4vw, 42px);
      line-height: 1.1;
    }

    .content {
      padding: 32px;
      line-height: 1.7;
      font-size: 16px;
    }

    .content h2,
    .content h3 {
      margin-top: 28px;
      margin-bottom: 12px;
      line-height: 1.25;
    }

    .content p {
      margin: 0 0 16px;
    }

    .content ul,
    .content ol {
      margin: 0 0 18px 24px;
      padding: 0;
    }

    .content li {
      margin-bottom: 8px;
    }

    .content code {
      font-family: Consolas, "Courier New", monospace;
      background: #f0f3fa;
      border-radius: 6px;
      padding: 2px 6px;
      font-size: 0.95em;
    }

    .footer {
      padding: 0 32px 28px;
      color: var(--muted);
      font-size: 14px;
    }

    a {
      color: inherit;
    }

    @media (max-width: 640px) {
      .hero,
      .content,
      .footer {
        padding-left: 20px;
        padding-right: 20px;
      }

      .shell {
        padding: 16px;
      }
    }
  </style>
</head>
<body>
  <main class="shell">
    <article class="card">
      <header class="hero">
        <p class="eyebrow">${escapeHtml(eyebrow)}</p>
        <h1>${escapeHtml(title)}</h1>
      </header>
      <section class="content">
        ${renderSimpleMarkdown(content)}
      </section>
      <footer class="footer">
        Public legal page for sharing with users and app store reviewers.
      </footer>
    </article>
  </main>
</body>
</html>`;
}

function renderErrorPage(title: string, message: string) {
    return renderDocumentPage({
        title,
        eyebrow: 'NoteClaw',
        content: message,
    });
}

function renderSimpleMarkdown(content: string): string {
    const lines = content.replace(/\r\n/g, '\n').split('\n');
    const parts: string[] = [];
    let inUnorderedList = false;
    let inOrderedList = false;

    const closeLists = () => {
        if (inUnorderedList) {
            parts.push('</ul>');
            inUnorderedList = false;
        }
        if (inOrderedList) {
            parts.push('</ol>');
            inOrderedList = false;
        }
    };

    for (const rawLine of lines) {
        const line = rawLine.trim();

        if (!line) {
            closeLists();
            continue;
        }

        const headingMatch = line.match(/^(#{1,3})\s+(.*)$/);
        if (headingMatch) {
            closeLists();
            const level = Math.min(headingMatch[1].length + 1, 4);
            parts.push(`<h${level}>${renderInlineMarkdown(headingMatch[2])}</h${level}>`);
            continue;
        }

        const unorderedMatch = line.match(/^[-*•]\s+(.*)$/);
        if (unorderedMatch) {
            if (inOrderedList) {
                parts.push('</ol>');
                inOrderedList = false;
            }
            if (!inUnorderedList) {
                parts.push('<ul>');
                inUnorderedList = true;
            }
            parts.push(`<li>${renderInlineMarkdown(unorderedMatch[1])}</li>`);
            continue;
        }

        const orderedMatch = line.match(/^\d+\.\s+(.*)$/);
        if (orderedMatch) {
            if (inUnorderedList) {
                parts.push('</ul>');
                inUnorderedList = false;
            }
            if (!inOrderedList) {
                parts.push('<ol>');
                inOrderedList = true;
            }
            parts.push(`<li>${renderInlineMarkdown(orderedMatch[1])}</li>`);
            continue;
        }

        closeLists();
        parts.push(`<p>${renderInlineMarkdown(line)}</p>`);
    }

    closeLists();
    return parts.join('\n');
}

function renderInlineMarkdown(input: string): string {
    let escaped = escapeHtml(input);
    escaped = escaped.replace(/`([^`]+)`/g, '<code>$1</code>');
    escaped = escaped.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    escaped = escaped.replace(/\*([^*]+)\*/g, '<em>$1</em>');
    return escaped;
}

function escapeHtml(input: string): string {
    return input
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

export default router;
