import axios from 'axios';
import pool from '../config/database.js';
import { getAppSettingValue } from './appSettingsService.js';
import { decryptSecretAllowLegacy } from './secretEncryptionService.js';

const RESEND_API_URL = 'https://api.resend.com/emails';
const DEFAULT_FROM_NAME = 'NoteClaw';

const EMAIL_SETTING_KEYS = {
    fromEmail: 'resend_from_email',
    fromName: 'resend_from_name',
    replyToEmail: 'resend_reply_to_email',
    publicAppUrl: 'public_app_url',
} as const;

type ResendConfig = {
    apiKey: string;
    fromEmail: string;
    fromName: string;
    replyToEmail: string | null;
    publicAppUrl: string;
};

type EmailPayload = {
    to: string;
    subject: string;
    html: string;
    text: string;
};

function normalizeOptionalValue(value: string | null | undefined): string | null {
    const trimmed = typeof value === 'string' ? value.trim() : '';
    return trimmed.length > 0 ? trimmed : null;
}

function normalizeRequiredValue(value: string | null | undefined): string {
    return typeof value === 'string' ? value.trim() : '';
}

function escapeHtml(value: string): string {
    return value
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function joinUrl(baseUrl: string, path: string): string {
    const normalizedBase = baseUrl.replace(/\/+$/, '');
    const normalizedPath = path.startsWith('/') ? path : `/${path}`;
    return `${normalizedBase}${normalizedPath}`;
}

async function getStoredResendApiKey(): Promise<string | null> {
    try {
        const result = await pool.query(
            `SELECT encrypted_value
             FROM api_keys
             WHERE service_name = ANY($1::text[])
             ORDER BY CASE
                 WHEN service_name = 'resend' THEN 0
                 WHEN service_name = 'resend_api_key' THEN 1
                 ELSE 2
             END
             LIMIT 1`,
            [['resend', 'resend_api_key']],
        );

        if (result.rows.length === 0) {
            return null;
        }

        return decryptSecretAllowLegacy(result.rows[0].encrypted_value);
    } catch (error) {
        console.error('[Email] Failed to load stored Resend API key:', error);
        return null;
    }
}

async function getResendConfig(): Promise<ResendConfig | null> {
    const [
        storedApiKey,
        storedFromEmail,
        storedFromName,
        storedReplyToEmail,
        storedPublicAppUrl,
    ] = await Promise.all([
        getStoredResendApiKey(),
        getAppSettingValue(EMAIL_SETTING_KEYS.fromEmail),
        getAppSettingValue(EMAIL_SETTING_KEYS.fromName),
        getAppSettingValue(EMAIL_SETTING_KEYS.replyToEmail),
        getAppSettingValue(EMAIL_SETTING_KEYS.publicAppUrl),
    ]);

    const apiKey = normalizeRequiredValue(storedApiKey) || normalizeRequiredValue(process.env.RESEND_API_KEY);
    const fromEmail = normalizeRequiredValue(storedFromEmail) || normalizeRequiredValue(process.env.RESEND_FROM_EMAIL);
    const fromName =
        normalizeRequiredValue(storedFromName) ||
        normalizeRequiredValue(process.env.RESEND_FROM_NAME) ||
        DEFAULT_FROM_NAME;
    const replyToEmail =
        normalizeOptionalValue(storedReplyToEmail) ||
        normalizeOptionalValue(process.env.RESEND_REPLY_TO_EMAIL);
    const publicAppUrl =
        normalizeRequiredValue(storedPublicAppUrl) ||
        normalizeRequiredValue(process.env.WEB_APP_URL);

    if (!apiKey || !fromEmail || !publicAppUrl) {
        return null;
    }

    return {
        apiKey,
        fromEmail,
        fromName,
        replyToEmail,
        publicAppUrl,
    };
}

async function sendViaResend(payload: EmailPayload): Promise<boolean> {
    const config = await getResendConfig();
    if (!config) {
        console.warn('[Email] Resend not configured; skipping email send.');
        return false;
    }

    const from = config.fromName
        ? `${config.fromName} <${config.fromEmail}>`
        : config.fromEmail;

    try {
        await axios.post(
            RESEND_API_URL,
            {
                from,
                to: [payload.to],
                subject: payload.subject,
                html: payload.html,
                text: payload.text,
                ...(config.replyToEmail ? { replyTo: config.replyToEmail } : {}),
            },
            {
                headers: {
                    Authorization: `Bearer ${config.apiKey}`,
                    'Content-Type': 'application/json',
                },
                timeout: 15000,
            },
        );
        return true;
    } catch (error) {
        console.error('[Email] Failed to send via Resend:', error);
        return false;
    }
}

function buildEmailShell({
    preview,
    heading,
    body,
    ctaLabel,
    ctaUrl,
    footnote,
}: {
    preview: string;
    heading: string;
    body: string[];
    ctaLabel: string;
    ctaUrl: string;
    footnote: string;
}): { html: string; text: string } {
    const safeHeading = escapeHtml(heading);
    const safePreview = escapeHtml(preview);
    const safeCtaLabel = escapeHtml(ctaLabel);
    const safeFootnote = escapeHtml(footnote);
    const htmlParagraphs = body
        .map((paragraph) => `<p style="margin:0 0 16px;color:#1f2937;line-height:1.6;">${escapeHtml(paragraph)}</p>`)
        .join('');

    const html = `
<!DOCTYPE html>
<html lang="en">
  <body style="margin:0;background:#f4f7fb;font-family:Arial,sans-serif;padding:24px;">
    <div style="display:none;max-height:0;overflow:hidden;opacity:0;">${safePreview}</div>
    <div style="max-width:620px;margin:0 auto;background:#ffffff;border-radius:20px;padding:32px;border:1px solid #e5e7eb;">
      <p style="margin:0 0 8px;font-size:12px;letter-spacing:0.12em;text-transform:uppercase;color:#2563eb;font-weight:700;">NoteClaw</p>
      <h1 style="margin:0 0 20px;font-size:28px;line-height:1.2;color:#111827;">${safeHeading}</h1>
      ${htmlParagraphs}
      <div style="margin:28px 0;">
        <a href="${ctaUrl}" style="display:inline-block;background:#111827;color:#ffffff;text-decoration:none;padding:14px 20px;border-radius:12px;font-weight:700;">${safeCtaLabel}</a>
      </div>
      <p style="margin:0 0 12px;color:#4b5563;line-height:1.6;">If the button does not work, copy and paste this link into your browser:</p>
      <p style="margin:0 0 20px;word-break:break-all;"><a href="${ctaUrl}" style="color:#2563eb;">${ctaUrl}</a></p>
      <p style="margin:0;font-size:12px;color:#6b7280;line-height:1.6;">${safeFootnote}</p>
    </div>
  </body>
</html>`.trim();

    const text = [
        heading,
        '',
        ...body,
        '',
        `${ctaLabel}: ${ctaUrl}`,
        '',
        footnote,
    ].join('\n');

    return { html, text };
}

export async function sendVerificationEmail(params: {
    to: string;
    displayName?: string | null;
    token: string;
}): Promise<boolean> {
    const config = await getResendConfig();
    if (!config) {
        console.warn('[Email] Verification email skipped because Resend is not configured.');
        return false;
    }

    const verificationUrl = joinUrl(config.publicAppUrl, `/verify-email/${encodeURIComponent(params.token)}`);
    const greetingName = normalizeOptionalValue(params.displayName) || 'there';
    const body = buildEmailShell({
        preview: 'Confirm your NoteClaw email address.',
        heading: 'Verify your email',
        body: [
            `Hi ${greetingName},`,
            'Thanks for creating your NoteClaw account.',
            'Please confirm your email address so you can verify ownership of this inbox.',
        ],
        ctaLabel: 'Verify email',
        ctaUrl: verificationUrl,
        footnote: 'If you did not create a NoteClaw account, you can safely ignore this email.',
    });

    return sendViaResend({
        to: params.to,
        subject: 'Verify your NoteClaw email',
        html: body.html,
        text: body.text,
    });
}

export async function sendPasswordResetEmail(params: {
    to: string;
    displayName?: string | null;
    token: string;
}): Promise<boolean> {
    const config = await getResendConfig();
    if (!config) {
        console.warn('[Email] Password reset email skipped because Resend is not configured.');
        return false;
    }

    const resetUrl = joinUrl(config.publicAppUrl, `/password-reset/${encodeURIComponent(params.token)}`);
    const greetingName = normalizeOptionalValue(params.displayName) || 'there';
    const body = buildEmailShell({
        preview: 'Reset your NoteClaw password.',
        heading: 'Reset your password',
        body: [
            `Hi ${greetingName},`,
            'We received a request to reset your NoteClaw password.',
            'Use the link below to choose a new password. This link will expire in 1 hour.',
        ],
        ctaLabel: 'Reset password',
        ctaUrl: resetUrl,
        footnote: 'If you did not request a password reset, you can ignore this email and your password will stay the same.',
    });

    return sendViaResend({
        to: params.to,
        subject: 'Reset your NoteClaw password',
        html: body.html,
        text: body.text,
    });
}
