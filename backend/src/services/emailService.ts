import axios from 'axios';
import nodemailer from 'nodemailer';
import pool from '../config/database.js';
import { getAppSettingValue } from './appSettingsService.js';
import { decryptSecretAllowLegacy } from './secretEncryptionService.js';

const RESEND_API_URL = 'https://api.resend.com/emails';
const DEFAULT_FROM_NAME = 'NoteClaw';
const DEFAULT_SMTP_PORT = 587;

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

type SmtpConfig = {
    host: string;
    port: number;
    secure: boolean;
    requireTls: boolean;
    rejectUnauthorized: boolean;
    tlsServername: string | null;
    username: string;
    password: string;
    fromEmail: string;
    fromName: string;
    replyToEmail: string | null;
};

export type EmailDeliveryStatus = {
    provider: 'smtp' | 'resend' | 'none';
    smtpConfigured: boolean;
    resendConfigured: boolean;
    publicAppUrlConfigured: boolean;
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

function parseBoolean(value: string | null | undefined, fallback: boolean): boolean {
    const normalized = normalizeRequiredValue(value).toLowerCase();
    if (!normalized) return fallback;
    if (['true', '1', 'yes', 'on'].includes(normalized)) return true;
    if (['false', '0', 'no', 'off'].includes(normalized)) return false;
    return fallback;
}

function parseSmtpPort(value: string | null | undefined): number {
    const parsed = Number.parseInt(normalizeRequiredValue(value), 10);
    if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
        return DEFAULT_SMTP_PORT;
    }
    return parsed;
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

async function getPublicAppUrl(): Promise<string> {
    const storedPublicAppUrl = await getAppSettingValue(EMAIL_SETTING_KEYS.publicAppUrl);
    return (
        normalizeRequiredValue(storedPublicAppUrl) ||
        normalizeRequiredValue(process.env.PUBLIC_APP_URL) ||
        normalizeRequiredValue(process.env.WEB_APP_URL)
    );
}

async function getSmtpConfig(): Promise<SmtpConfig | null> {
    const [storedFromEmail, storedFromName, storedReplyToEmail] = await Promise.all([
        getAppSettingValue(EMAIL_SETTING_KEYS.fromEmail),
        getAppSettingValue(EMAIL_SETTING_KEYS.fromName),
        getAppSettingValue(EMAIL_SETTING_KEYS.replyToEmail),
    ]);

    const host = normalizeRequiredValue(process.env.SMTP_HOST);
    const port = parseSmtpPort(process.env.SMTP_PORT);
    const username =
        normalizeRequiredValue(process.env.SMTP_USERNAME) ||
        normalizeRequiredValue(process.env.SMTP_USER);
    const password = normalizeRequiredValue(process.env.SMTP_PASSWORD);
    const fromEmail =
        normalizeRequiredValue(process.env.SMTP_FROM_EMAIL) ||
        normalizeRequiredValue(storedFromEmail) ||
        username;
    const fromName =
        normalizeRequiredValue(process.env.SMTP_FROM_NAME) ||
        normalizeRequiredValue(storedFromName) ||
        DEFAULT_FROM_NAME;
    const replyToEmail =
        normalizeOptionalValue(process.env.SMTP_REPLY_TO_EMAIL) ||
        normalizeOptionalValue(storedReplyToEmail);

    if (!host || !username || !password || !fromEmail) {
        return null;
    }

    return {
        host,
        port,
        secure: parseBoolean(process.env.SMTP_SECURE, port === 465),
        requireTls: parseBoolean(process.env.SMTP_REQUIRE_TLS, port !== 465),
        rejectUnauthorized: parseBoolean(
            process.env.SMTP_TLS_REJECT_UNAUTHORIZED,
            true,
        ),
        tlsServername: normalizeOptionalValue(process.env.SMTP_TLS_SERVERNAME),
        username,
        password,
        fromEmail,
        fromName,
        replyToEmail,
    };
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

async function sendViaResend(
    payload: EmailPayload,
    config: ResendConfig,
): Promise<boolean> {
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

async function sendViaSmtp(
    payload: EmailPayload,
    config: SmtpConfig,
): Promise<boolean> {
    const transporter = nodemailer.createTransport({
        host: config.host,
        port: config.port,
        secure: config.secure,
        requireTLS: config.requireTls,
        auth: {
            user: config.username,
            pass: config.password,
        },
        tls: {
            rejectUnauthorized: config.rejectUnauthorized,
            ...(config.tlsServername ? { servername: config.tlsServername } : {}),
        },
        connectionTimeout: 15000,
        greetingTimeout: 10000,
        socketTimeout: 20000,
    });

    const from = config.fromName
        ? `${config.fromName} <${config.fromEmail}>`
        : config.fromEmail;

    try {
        await transporter.sendMail({
            from,
            to: payload.to,
            subject: payload.subject,
            html: payload.html,
            text: payload.text,
            ...(config.replyToEmail ? { replyTo: config.replyToEmail } : {}),
        });
        return true;
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`[Email] Failed to send via SMTP: ${message}`);
        return false;
    } finally {
        transporter.close();
    }
}

async function sendWithConfiguredProvider(payload: EmailPayload): Promise<boolean> {
    const smtpConfig = await getSmtpConfig();
    if (smtpConfig) {
        const smtpSent = await sendViaSmtp(payload, smtpConfig);
        if (smtpSent) {
            return true;
        }
        console.warn('[Email] SMTP delivery failed; checking Resend fallback.');
    }

    const resendConfig = await getResendConfig();
    if (resendConfig) {
        return sendViaResend(payload, resendConfig);
    }

    console.warn('[Email] No configured email provider; skipping email send.');
    return false;
}

export async function getEmailDeliveryStatus(): Promise<EmailDeliveryStatus> {
    const [smtpConfig, resendConfig, publicAppUrl] = await Promise.all([
        getSmtpConfig(),
        getResendConfig(),
        getPublicAppUrl(),
    ]);

    return {
        provider: smtpConfig ? 'smtp' : resendConfig ? 'resend' : 'none',
        smtpConfigured: smtpConfig !== null,
        resendConfigured: resendConfig !== null,
        publicAppUrlConfigured: publicAppUrl.length > 0,
    };
}

function buildEmailShell({
    preview,
    heading,
    body,
    ctaLabel,
    ctaUrl,
    secondaryCtaLabel,
    secondaryCtaUrl,
    footnote,
}: {
    preview: string;
    heading: string;
    body: string[];
    ctaLabel?: string;
    ctaUrl?: string;
    secondaryCtaLabel?: string;
    secondaryCtaUrl?: string;
    footnote: string;
}): { html: string; text: string } {
    const safeHeading = escapeHtml(heading);
    const safePreview = escapeHtml(preview);
    const safeCtaLabel = ctaLabel ? escapeHtml(ctaLabel) : '';
    const safeCtaUrl = ctaUrl ? escapeHtml(ctaUrl) : '';
    const safeSecondaryCtaLabel = secondaryCtaLabel ? escapeHtml(secondaryCtaLabel) : '';
    const safeSecondaryCtaUrl = secondaryCtaUrl ? escapeHtml(secondaryCtaUrl) : '';
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
      ${safeCtaUrl
            ? `<div style="margin:28px 0;">
                <a href="${safeCtaUrl}" style="display:inline-block;background:#111827;color:#ffffff;text-decoration:none;padding:14px 20px;border-radius:12px;font-weight:700;">${safeCtaLabel}</a>
                ${safeSecondaryCtaUrl && safeSecondaryCtaLabel
                    ? `<a href="${safeSecondaryCtaUrl}" style="display:inline-block;margin-left:8px;background:#e5e7eb;color:#111827;text-decoration:none;padding:14px 20px;border-radius:12px;font-weight:700;">${safeSecondaryCtaLabel}</a>`
                    : ''}
              </div>
              <p style="margin:0 0 12px;color:#4b5563;line-height:1.6;">If the button does not work, copy and paste this link into your browser:</p>
              <p style="margin:0 0 20px;word-break:break-all;"><a href="${safeCtaUrl}" style="color:#2563eb;">${safeCtaUrl}</a></p>`
            : ''}
      <p style="margin:0;font-size:12px;color:#6b7280;line-height:1.6;">${safeFootnote}</p>
    </div>
  </body>
</html>`.trim();

    const text = [
        heading,
        '',
        ...body,
        ...(ctaLabel && ctaUrl
            ? ['', `${ctaLabel}: ${ctaUrl}`]
            : []),
        ...(ctaLabel && ctaUrl && secondaryCtaLabel && secondaryCtaUrl
            ? [`${secondaryCtaLabel}: ${secondaryCtaUrl}`]
            : []),
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
    const publicAppUrl = await getPublicAppUrl();
    if (!publicAppUrl) {
        console.warn('[Email] Verification email skipped because the public app URL is not configured.');
        return false;
    }

    const verificationUrl = joinUrl(publicAppUrl, `/verify-email/${encodeURIComponent(params.token)}`);
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

    return sendWithConfiguredProvider({
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
    const publicAppUrl = await getPublicAppUrl();
    if (!publicAppUrl) {
        console.warn('[Email] Password reset email skipped because the public app URL is not configured.');
        return false;
    }

    const resetUrl = joinUrl(publicAppUrl, `/password-reset/${encodeURIComponent(params.token)}`);
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

    return sendWithConfiguredProvider({
        to: params.to,
        subject: 'Reset your NoteClaw password',
        html: body.html,
        text: body.text,
    });
}

export async function sendPlayTestingInviteEmail(params: {
    to: string;
    displayName?: string | null;
    optInUrl: string;
    groupUrl?: string | null;
    feedbackEmail?: string | null;
}): Promise<boolean> {
    const greetingName = normalizeOptionalValue(params.displayName) || 'there';
    const groupInstruction = params.groupUrl
        ? 'Because this is a closed test, join the tester group using the second button before opening the Google Play invite.'
        : 'Use the same Google Account that you entered on the NoteClaw website when Google Play asks you to opt in.';
    const feedbackInstruction = params.feedbackEmail
        ? `Send testing feedback to ${params.feedbackEmail}.`
        : 'You can send feedback through the private feedback option on Google Play.';
    const body = buildEmailShell({
        preview: 'Your NoteClaw Android testing invite is ready.',
        heading: 'Join the NoteClaw Android test',
        body: [
            `Hi ${greetingName},`,
            'Thanks for joining the NoteClaw Android testing program.',
            groupInstruction,
            'Open the Google Play invite, choose Become a tester, then use the download link shown by Google Play.',
            feedbackInstruction,
        ],
        ctaLabel: 'Open Google Play invite',
        ctaUrl: params.optInUrl,
        secondaryCtaLabel: params.groupUrl ? 'Join tester group first' : undefined,
        secondaryCtaUrl: params.groupUrl || undefined,
        footnote: 'Google Play requires a Gmail or Google Workspace account. For closed-test production eligibility, remain opted in continuously for at least 14 days.',
    });

    return sendWithConfiguredProvider({
        to: params.to,
        subject: 'Your NoteClaw Android testing invite',
        html: body.html,
        text: body.text,
    });
}

export async function sendAdminDirectEmail(params: {
    to: string;
    displayName?: string | null;
    subject: string;
    message: string;
}): Promise<boolean> {
    const paragraphs = params.message
        .split(/\r?\n+/)
        .map((paragraph) => paragraph.trim())
        .filter(Boolean);
    const body = buildEmailShell({
        preview: params.subject,
        heading: params.subject,
        body: paragraphs.length > 0 ? paragraphs : [' '],
        footnote: 'You are receiving this email because you have an account with NoteClaw.',
    });

    return sendWithConfiguredProvider({
        to: params.to,
        subject: params.subject,
        html: body.html,
        text: body.text,
    });
}
