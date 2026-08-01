import { useState, useEffect } from 'react';
import api from '../lib/api';
import { CreditCard, Shield, Save, Plus, Trash2, Key, Loader2, Upload, FileText, Zap, Mail } from 'lucide-react';

export default function Settings() {
    const [apiKeys, setApiKeys] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [envContent, setEnvContent] = useState('');
    const [showEnvImport, setShowEnvImport] = useState(false);
    // New API Key Form
    const [newKeyService, setNewKeyService] = useState('');
    const [newKeyValue, setNewKeyValue] = useState('');

    // Payment Configuration
    const [paypalClientId, setPaypalClientId] = useState('');
    const [paypalSecret, setPaypalSecret] = useState('');
    const [stripePublishableKey, setStripePublishableKey] = useState('');
    const [stripeSecretKey, setStripeSecretKey] = useState('');

    // Resend Configuration
    const [resendApiKey, setResendApiKey] = useState('');
    const [resendFromEmail, setResendFromEmail] = useState('');
    const [resendFromName, setResendFromName] = useState('');
    const [resendReplyToEmail, setResendReplyToEmail] = useState('');
    const [publicAppUrl, setPublicAppUrl] = useState('');
    const [requireEmailVerification, setRequireEmailVerification] = useState(false);
    const [emailStatus, setEmailStatus] = useState({
        provider: 'none',
        smtpConfigured: false,
        resendConfigured: false,
        publicAppUrlConfigured: false,
    });

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        setLoading(true);
        try {
            const [keysResponse, settingsResponse, emailStatusResponse] = await Promise.all([
                api.getApiKeys(),
                api.getSettings([
                    'resend_from_email',
                    'resend_from_name',
                    'resend_reply_to_email',
                    'public_app_url',
                    'require_email_verification',
                ]),
                api.getEmailStatus(),
            ]);
            const nextSettings = settingsResponse.settings || {};
            setApiKeys(keysResponse.apiKeys || []);
            setResendFromEmail(nextSettings.resend_from_email || '');
            setResendFromName(nextSettings.resend_from_name || '');
            setResendReplyToEmail(nextSettings.resend_reply_to_email || '');
            setPublicAppUrl(nextSettings.public_app_url || '');
            setRequireEmailVerification(
                String(nextSettings.require_email_verification || '').toLowerCase() === 'true',
            );
            setEmailStatus(emailStatusResponse.status || {
                provider: 'none',
                smtpConfigured: false,
                resendConfigured: false,
                publicAppUrlConfigured: false,
            });
        } catch (error) {
            console.error(error);
            alert('Failed to fetch settings');
        } finally {
            setLoading(false);
        }
    };

    const saveApiKey = async (service, value) => {
        if (!service || !value) return;

        setSaving(true);
        try {
            await api.setApiKey(service.toLowerCase().trim(), value.trim(), `${service} API Key`);
            fetchData();
            alert('API Key saved!');
            return true;
        } catch (error) {
            console.error(error);
            alert('Failed to save API Key: ' + error.message);
            return false;
        } finally {
            setSaving(false);
        }
    };

    const handleAddKey = async (e) => {
        e.preventDefault();
        const success = await saveApiKey(newKeyService, newKeyValue);
        if (success) {
            setNewKeyService('');
            setNewKeyValue('');
        }
    };

    const deleteApiKey = async (service) => {
        if (!confirm(`Delete key for ${service}?`)) return;
        try {
            await api.deleteApiKey(service);
            fetchData();
        } catch (error) {
            console.error(error);
            alert('Failed to delete key');
        }
    };

    const deployFromEnv = async () => {
        if (!envContent.trim()) {
            alert('Please paste your .env content');
            return;
        }

        setSaving(true);
        try {
            const lines = envContent.split('\n');
            let imported = 0;

            const serviceMap = {
                'GEMINI_API_KEY': 'gemini',
                'ELEVENLABS_API_KEY': 'elevenlabs',
                'ELEVENLABS_AGENT_ID': 'elevenlabs_agent_id',
                'MURF_API_KEY': 'murf',
                'GOOGLE_CLOUD_TTS_API_KEY': 'google_cloud_tts',
                'OPENROUTER_API_KEY': 'openrouter',
                'RESEND_API_KEY': 'resend',
                'SERPER_API_KEY': 'serper',
                'DEEPGRAM_API_KEY': 'deepgram',
                'PAYPAL_CLIENT_ID': 'paypal_client_id',
                'PAYPAL_SECRET': 'paypal_secret',
                'STRIPE_PUBLISHABLE_KEY': 'stripe_publishable_key',
                'STRIPE_SECRET_KEY': 'stripe_secret_key',
            };

            const settingMap = {
                'RESEND_FROM_EMAIL': 'resend_from_email',
                'RESEND_FROM_NAME': 'resend_from_name',
                'RESEND_REPLY_TO_EMAIL': 'resend_reply_to_email',
                'PUBLIC_APP_URL': 'public_app_url',
                'WEB_APP_URL': 'public_app_url',
                'REQUIRE_EMAIL_VERIFICATION': 'require_email_verification',
            };

            for (const line of lines) {
                const trimmed = line.trim();
                if (!trimmed || trimmed.startsWith('#')) continue;

                const match = trimmed.match(/^([A-Z_]+)=(.+)$/);
                if (match) {
                    const [, envKey, value] = match;
                    const cleanedValue = value.replace(/^["']|["']$/g, '');
                    const serviceName = serviceMap[envKey];
                    const settingKey = settingMap[envKey];
                    if (serviceName && cleanedValue) {
                        await api.setApiKey(serviceName, cleanedValue, `${serviceName} API Key`);
                        imported++;
                    } else if (settingKey) {
                        await api.updateSetting(settingKey, cleanedValue);
                        imported++;
                    }
                }
            }

            alert(`Successfully imported ${imported} API keys!`);
            setEnvContent('');
            setShowEnvImport(false);
            fetchData();
        } catch (error) {
            console.error(error);
            alert('Failed to import keys: ' + error.message);
        } finally {
            setSaving(false);
        }
    };

    const saveEmailConfiguration = async (e) => {
        e.preventDefault();

        if (!resendFromEmail.trim()) {
            alert('Sender email is required');
            return;
        }

        if (!publicAppUrl.trim()) {
            alert('Public app URL is required');
            return;
        }

        setSaving(true);
        try {
            const updates = [
                api.updateSetting('resend_from_email', resendFromEmail.trim()),
                api.updateSetting('resend_from_name', resendFromName.trim()),
                api.updateSetting('resend_reply_to_email', resendReplyToEmail.trim()),
                api.updateSetting('public_app_url', publicAppUrl.trim()),
                api.updateSetting(
                    'require_email_verification',
                    requireEmailVerification ? 'true' : 'false',
                ),
            ];

            if (resendApiKey.trim()) {
                updates.push(
                    api.setApiKey('resend', resendApiKey.trim(), 'Resend API Key'),
                );
            }

            await Promise.all(updates);
            setResendApiKey('');
            await fetchData();
            alert('Email configuration saved!');
        } catch (error) {
            console.error(error);
            alert('Failed to save email configuration: ' + error.message);
        } finally {
            setSaving(false);
        }
    };

    const resendApiKeyConfigured = emailStatus.resendConfigured || apiKeys.some((key) => key.service_name === 'resend');
    const resendSenderConfigured = resendFromEmail.trim().length > 0;
    const resendLinkingConfigured = emailStatus.publicAppUrlConfigured || publicAppUrl.trim().length > 0;
    const activeEmailProvider = emailStatus.provider === 'smtp'
        ? 'SMTP'
        : emailStatus.provider === 'resend'
            ? 'Resend'
            : 'Not configured';

    if (loading) return (
        <div className="flex items-center justify-center h-64">
            <Loader2 className="h-8 w-8 animate-spin" />
        </div>
    );

    return (
        <div className="p-8 space-y-8">
            <div className="mb-8">
                <h1 className="text-3xl font-bold mb-2">Settings & Configuration</h1>
                <p className="text-muted-foreground">Manage API keys and payment configuration</p>
            </div>

            {/* API Keys Section */}
            <section className="rounded-lg bg-card border border-border p-6">
                <div className="flex items-center justify-between mb-6">
                    <h2 className="text-xl font-bold flex items-center">
                        <Key className="mr-2 h-5 w-5" />
                        API Keys Management
                    </h2>
                    <button
                        onClick={() => setShowEnvImport(!showEnvImport)}
                        className="flex items-center rounded-md bg-secondary px-4 py-2 text-sm font-medium hover:bg-secondary/80"
                    >
                        <Upload className="mr-2 h-4 w-4" />
                        Deploy from .env
                    </button>
                </div>

                {/* Deploy from .env Section */}
                {showEnvImport && (
                    <div className="bg-muted p-4 rounded-md mb-6 border border-border">
                        <h3 className="text-sm font-medium mb-4 flex items-center">
                            <FileText className="mr-2 h-4 w-4" />
                            Paste your .env file content
                        </h3>
                        <textarea
                            placeholder="GEMINI_API_KEY=your_key_here&#10;PAYPAL_CLIENT_ID=your_id&#10;PAYPAL_SECRET=your_secret"
                            className="w-full h-32 rounded-md border border-border bg-background p-2 font-mono text-sm"
                            value={envContent}
                            onChange={(e) => setEnvContent(e.target.value)}
                        />
                        <div className="flex gap-2 mt-4">
                            <button
                                onClick={deployFromEnv}
                                disabled={saving}
                                className="flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
                            >
                                {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Upload className="mr-2 h-4 w-4" />}
                                Import Keys
                            </button>
                            <button
                                onClick={() => setShowEnvImport(false)}
                                className="rounded-md bg-secondary px-4 py-2 text-sm font-medium hover:bg-secondary/80"
                            >
                                Cancel
                            </button>
                        </div>
                        <p className="mt-2 text-xs text-muted-foreground">
                            Supported: GEMINI_API_KEY, RESEND_API_KEY, RESEND_FROM_*, WEB_APP_URL, PAYPAL_CLIENT_ID, PAYPAL_SECRET, STRIPE_*, ELEVENLABS_*, OPENROUTER_*, SERPER_*, DEEPGRAM_*
                        </p>
                    </div>
                )}

                {/* Email Delivery Configuration */}
                <form onSubmit={saveEmailConfiguration} className="bg-muted/50 p-4 rounded-md border border-border mb-6">
                    <div className="flex items-start justify-between gap-4 mb-4">
                        <div>
                            <h3 className="text-lg font-semibold flex items-center">
                                <Mail className="mr-2 h-5 w-5" />
                                Email Delivery Configuration
                            </h3>
                            <p className="text-sm text-muted-foreground mt-1">
                                SMTP is used for verification emails and password reset links, with Resend available as an optional fallback.
                            </p>
                        </div>
                        <div className="text-right text-xs space-y-1">
                            <p className={emailStatus.provider !== 'none' ? 'text-green-600' : 'text-amber-600'}>
                                Active provider: {activeEmailProvider}
                            </p>
                            <p className={emailStatus.smtpConfigured ? 'text-green-600' : 'text-muted-foreground'}>
                                {emailStatus.smtpConfigured ? 'SMTP configured in hosting' : 'SMTP not configured'}
                            </p>
                            <p className={resendSenderConfigured ? 'text-green-600' : 'text-amber-600'}>
                                {resendSenderConfigured ? 'Sender email configured' : 'Sender email missing'}
                            </p>
                            <p className={resendLinkingConfigured ? 'text-green-600' : 'text-amber-600'}>
                                {resendLinkingConfigured ? 'Public app URL configured' : 'Public app URL missing'}
                            </p>
                        </div>
                    </div>

                    <div className="grid gap-4 md:grid-cols-2">
                        <div className="md:col-span-2">
                            <label className="block text-sm font-medium mb-1">Resend API Key (optional fallback)</label>
                            <input
                                type="password"
                                className="w-full rounded-md border border-border bg-background p-2 font-mono text-sm"
                                placeholder={resendApiKeyConfigured ? 'Configured. Paste a new key to replace it.' : 're_...'}
                                value={resendApiKey}
                                onChange={(e) => setResendApiKey(e.target.value)}
                            />
                            <p className="mt-1 text-xs text-muted-foreground">
                                SMTP credentials are managed as protected hosting variables. A Resend fallback key entered here is stored encrypted in the backend.
                            </p>
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-1">From Email</label>
                            <input
                                type="email"
                                className="w-full rounded-md border border-border bg-background p-2"
                                placeholder="hello@yourdomain.com"
                                value={resendFromEmail}
                                onChange={(e) => setResendFromEmail(e.target.value)}
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-1">From Name</label>
                            <input
                                type="text"
                                className="w-full rounded-md border border-border bg-background p-2"
                                placeholder="NoteClaw"
                                value={resendFromName}
                                onChange={(e) => setResendFromName(e.target.value)}
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-1">Reply-To Email</label>
                            <input
                                type="email"
                                className="w-full rounded-md border border-border bg-background p-2"
                                placeholder="support@yourdomain.com"
                                value={resendReplyToEmail}
                                onChange={(e) => setResendReplyToEmail(e.target.value)}
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-1">Public App URL</label>
                            <input
                                type="url"
                                className="w-full rounded-md border border-border bg-background p-2"
                                placeholder="https://app.noteclaw.com"
                                value={publicAppUrl}
                                onChange={(e) => setPublicAppUrl(e.target.value)}
                            />
                        </div>
                    </div>

                    <div className="mt-4 flex items-center justify-between gap-4 flex-wrap">
                        <label className="flex items-center gap-3 text-sm font-medium text-foreground">
                            <input
                                type="checkbox"
                                className="h-4 w-4 rounded border-border"
                                checked={requireEmailVerification}
                                onChange={(e) => setRequireEmailVerification(e.target.checked)}
                            />
                            Require verified email before sign-in
                        </label>
                    </div>

                    <div className="mt-4 flex items-center justify-between gap-4 flex-wrap">
                        <p className="text-xs text-muted-foreground">
                            Verification links will use <span className="font-mono">/verify-email/:token</span> and password resets will use <span className="font-mono">/password-reset/:token</span> on your public app URL.
                        </p>
                        <button
                            type="submit"
                            disabled={saving}
                            className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
                        >
                            {saving ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />}
                            Save Email Settings
                        </button>
                    </div>
                </form>

                {/* PayPal Configuration */}
                <div className="bg-muted/50 p-4 rounded-md border border-border mb-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center">
                        <CreditCard className="mr-2 h-5 w-5" />
                        PayPal Configuration
                    </h3>
                    <div className="space-y-4">
                        <div>
                            <label className="block text-sm font-medium mb-1">Client ID</label>
                            <div className="flex gap-2">
                                <input
                                    type="password"
                                    className="flex-1 rounded-md border border-border bg-background p-2"
                                    placeholder="PayPal Client ID"
                                    value={paypalClientId}
                                    onChange={(e) => setPaypalClientId(e.target.value)}
                                />
                                <button
                                    onClick={() => saveApiKey('paypal_client_id', paypalClientId).then(s => s && setPaypalClientId(''))}
                                    disabled={!paypalClientId || saving}
                                    className="px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
                                >
                                    Save
                                </button>
                            </div>
                            {apiKeys.find(k => k.service_name === 'paypal_client_id') && (
                                <p className="text-xs text-green-600 mt-1 flex items-center">
                                    <Shield className="h-3 w-3 mr-1" /> Configured
                                </p>
                            )}
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">Secret Key</label>
                            <div className="flex gap-2">
                                <input
                                    type="password"
                                    className="flex-1 rounded-md border border-border bg-background p-2"
                                    placeholder="PayPal Secret"
                                    value={paypalSecret}
                                    onChange={(e) => setPaypalSecret(e.target.value)}
                                />
                                <button
                                    onClick={() => saveApiKey('paypal_secret', paypalSecret).then(s => s && setPaypalSecret(''))}
                                    disabled={!paypalSecret || saving}
                                    className="px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
                                >
                                    Save
                                </button>
                            </div>
                            {apiKeys.find(k => k.service_name === 'paypal_secret') && (
                                <p className="text-xs text-green-600 mt-1 flex items-center">
                                    <Shield className="h-3 w-3 mr-1" /> Configured
                                </p>
                            )}
                        </div>
                    </div>
                </div>

                {/* Stripe Configuration */}
                <div className="bg-muted/50 p-4 rounded-md border border-border mb-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center">
                        <Zap className="mr-2 h-5 w-5" />
                        Stripe Configuration
                    </h3>
                    <div className="space-y-4">
                        <div>
                            <label className="block text-sm font-medium mb-1">Publishable Key</label>
                            <div className="flex gap-2">
                                <input
                                    type="text"
                                    className="flex-1 rounded-md border border-border bg-background p-2 font-mono text-sm"
                                    placeholder="pk_test_... or pk_live_..."
                                    value={stripePublishableKey}
                                    onChange={(e) => setStripePublishableKey(e.target.value)}
                                />
                                <button
                                    onClick={() => saveApiKey('stripe_publishable_key', stripePublishableKey).then(s => s && setStripePublishableKey(''))}
                                    disabled={!stripePublishableKey || saving}
                                    className="px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
                                >
                                    Save
                                </button>
                            </div>
                            {apiKeys.find(k => k.service_name === 'stripe_publishable_key') && (
                                <p className="text-xs text-green-600 mt-1 flex items-center">
                                    <Shield className="h-3 w-3 mr-1" /> Configured
                                </p>
                            )}
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">Secret Key</label>
                            <div className="flex gap-2">
                                <input
                                    type="password"
                                    className="flex-1 rounded-md border border-border bg-background p-2 font-mono text-sm"
                                    placeholder="sk_test_... or sk_live_..."
                                    value={stripeSecretKey}
                                    onChange={(e) => setStripeSecretKey(e.target.value)}
                                />
                                <button
                                    onClick={() => saveApiKey('stripe_secret_key', stripeSecretKey).then(s => s && setStripeSecretKey(''))}
                                    disabled={!stripeSecretKey || saving}
                                    className="px-4 py-2 bg-primary text-primary-foreground rounded-md text-sm font-medium hover:bg-primary/90 disabled:opacity-50"
                                >
                                    Save
                                </button>
                            </div>
                            {apiKeys.find(k => k.service_name === 'stripe_secret_key') && (
                                <p className="text-xs text-green-600 mt-1 flex items-center">
                                    <Shield className="h-3 w-3 mr-1" /> Configured
                                </p>
                            )}
                        </div>
                    </div>
                </div>

                {/* Add Key Form */}
                <form onSubmit={handleAddKey} className="bg-muted p-4 rounded-md mb-6 border border-border">
                    <h3 className="text-sm font-medium mb-4">Add / Update Individual Key</h3>
                    <div className="flex gap-4 flex-col sm:flex-row">
                        <input
                            type="text"
                            placeholder="Service Name (e.g. gemini, elevenlabs)"
                            className="flex-1 rounded-md border border-border bg-background p-2"
                            value={newKeyService}
                            onChange={(e) => setNewKeyService(e.target.value)}
                            required
                        />
                        <input
                            type="password"
                            placeholder="API Key Value"
                            className="flex-1 rounded-md border border-border bg-background p-2"
                            value={newKeyValue}
                            onChange={(e) => setNewKeyValue(e.target.value)}
                            required
                        />
                        <button
                            type="submit"
                            disabled={saving}
                            className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90 disabled:opacity-50"
                        >
                            <Plus className="mr-2 h-4 w-4" />
                            Add/Update
                        </button>
                    </div>
                </form>

                {/* Keys List */}
                <div className="overflow-hidden bg-card border border-border rounded-lg">
                    <table className="min-w-full">
                        <thead className="bg-muted/50">
                            <tr>
                                <th className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold">Service</th>
                                <th className="px-3 py-3.5 text-left text-sm font-semibold">Description</th>
                                <th className="px-3 py-3.5 text-left text-sm font-semibold">Updated</th>
                                <th className="relative py-3.5 pl-3 pr-4">
                                    <span className="sr-only">Actions</span>
                                </th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-border">
                            {apiKeys.map((key) => (
                                <tr key={key.service_name} className="hover:bg-muted/30">
                                    <td className="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium">
                                        {key.service_name}
                                    </td>
                                    <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground">
                                        {key.description}
                                    </td>
                                    <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground">
                                        {key.updated_at ? new Date(key.updated_at).toLocaleDateString() : '-'}
                                    </td>
                                    <td className="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium">
                                        <button
                                            onClick={() => deleteApiKey(key.service_name)}
                                            className="text-destructive hover:text-destructive/80"
                                        >
                                            <Trash2 className="h-4 w-4" />
                                        </button>
                                    </td>
                                </tr>
                            ))}
                            {apiKeys.length === 0 && (
                                <tr>
                                    <td colSpan={4} className="py-4 text-center text-sm text-muted-foreground">No keys found.</td>
                                </tr>
                            )}
                        </tbody>
                    </table>
                </div>
            </section>
        </div>
    );
}
