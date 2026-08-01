import { useState, useEffect } from 'react';
import api from '../lib/api';
import { Bot, Settings, Users, Activity, Save, Loader2, ToggleLeft, ToggleRight, RefreshCw } from 'lucide-react';

export default function McpSettings() {
    const [settings, setSettings] = useState(null);
    const [stats, setStats] = useState(null);
    const [diagnostics, setDiagnostics] = useState(null);
    const [users, setUsers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState(false);
    const [activeTab, setActiveTab] = useState('settings');

    useEffect(() => {
        fetchData();
    }, []);

    const fetchData = async () => {
        setLoading(true);
        try {
            const [settingsRes, statsRes, usageRes, diagnosticsRes] = await Promise.all([
                api.getMcpSettings(),
                api.getMcpStats(),
                api.getMcpUsage(),
                api.getMcpDiagnostics(),
            ]);
            setSettings(settingsRes.settings);
            setStats(statsRes);
            setUsers(usageRes.users || []);
            setDiagnostics(diagnosticsRes);
        } catch (error) {
            console.error('Failed to fetch MCP data:', error);
            alert('Failed to load MCP settings');
        } finally {
            setLoading(false);
        }
    };

    const handleSave = async () => {
        setSaving(true);
        try {
            await api.updateMcpSettings(settings);
            alert('MCP settings saved successfully!');
            fetchData();
        } catch (error) {
            console.error('Failed to save settings:', error);
            alert('Failed to save settings: ' + error.message);
        } finally {
            setSaving(false);
        }
    };

    const updateSetting = (key, value) => {
        setSettings(prev => ({ ...prev, [key]: value }));
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center h-64">
                <Loader2 className="h-8 w-8 animate-spin" />
            </div>
        );
    }

    return (
        <div className="p-8 space-y-8">
            <div className="mb-8">
                <h1 className="text-3xl font-bold mb-2 flex items-center gap-3">
                    <Bot className="h-8 w-8" />
                    MCP Settings
                </h1>
                <p className="text-muted-foreground">
                    Configure MCP (Model Context Protocol) limits and monitor usage across plans.
                </p>
                <div className="mt-3 rounded-lg border border-primary/20 bg-primary/5 p-3 text-sm text-muted-foreground">
                    Saving these limits updates the matching Free or Premium subscription plans.
                    You can fine-tune an individual plan from Subscription Plans.
                </div>
                <div className="mt-4 rounded-lg border border-amber-500/20 bg-amber-500/10 p-4 text-amber-700">
                    <div className="font-semibold mb-2">Common Errors</div>
                    <ul className="list-disc list-inside space-y-1 text-sm">
                        <li>401: Invalid or expired API key. Generate a new token in Settings -&gt; Agent Connections.</li>
                        <li>403: MCP disabled or insufficient permissions. Check MCP is enabled and your token permissions.</li>
                        <li>429: Daily tool-call limit reached. Review the user or plan quota here and retry after reset.</li>
                        <li>503: Service unavailable. Wait briefly and retry.</li>
                        <li>Network: Verify the hosted URL and NOTECLAW_API_TOKEN in the client configuration.</li>
                    </ul>
                </div>
            </div>

            {/* Tabs */}
            <div className="flex gap-2 border-b border-border pb-4">
                {['settings', 'usage', 'stats', 'diagnostics'].map((tab) => (
                    <button
                        key={tab}
                        onClick={() => setActiveTab(tab)}
                        className={`px-4 py-2 rounded-t-lg text-sm font-medium transition-colors ${
                            activeTab === tab
                                ? 'bg-primary text-primary-foreground'
                                : 'bg-muted hover:bg-muted/80'
                        }`}
                    >
                        {tab.charAt(0).toUpperCase() + tab.slice(1)}
                    </button>
                ))}
            </div>

            {activeTab === 'settings' && (
                <SettingsTab
                    settings={settings}
                    updateSetting={updateSetting}
                    onSave={handleSave}
                    saving={saving}
                />
            )}

            {activeTab === 'usage' && (
                <UsageTab users={users} settings={settings} onRefresh={fetchData} />
            )}

            {activeTab === 'stats' && (
                <StatsTab stats={stats} settings={settings} />
            )}

            {activeTab === 'diagnostics' && (
                <DiagnosticsTab diagnostics={diagnostics} onRefresh={fetchData} />
            )}
        </div>
    );
}

function SettingsTab({ settings, updateSetting, onSave, saving }) {
    if (!settings) return null;

    return (
        <div className="space-y-6">
            {/* Global Toggle */}
            <div className="rounded-lg bg-card border border-border p-6">
                <div className="flex items-center justify-between">
                    <div>
                        <h3 className="text-lg font-semibold">MCP Status</h3>
                        <p className="text-sm text-muted-foreground">
                            Enable or disable MCP functionality globally
                        </p>
                    </div>
                    <button
                        onClick={() => updateSetting('isMcpEnabled', !settings.isMcpEnabled)}
                        className={`flex items-center gap-2 px-4 py-2 rounded-lg font-medium transition-colors ${
                            settings.isMcpEnabled
                                ? 'bg-green-500/20 text-green-600 hover:bg-green-500/30'
                                : 'bg-red-500/20 text-red-600 hover:bg-red-500/30'
                        }`}
                    >
                        {settings.isMcpEnabled ? (
                            <>
                                <ToggleRight className="h-5 w-5" />
                                Enabled
                            </>
                        ) : (
                            <>
                                <ToggleLeft className="h-5 w-5" />
                                Disabled
                            </>
                        )}
                    </button>
                </div>
            </div>

            {/* Plan Limits */}
            <div className="grid gap-6 md:grid-cols-2">
                {/* Free Plan */}
                <div className="rounded-lg bg-card border border-border p-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                        <span className="px-2 py-1 rounded bg-muted text-xs font-medium">FREE</span>
                        Free Plan Limits
                    </h3>
                    <div className="space-y-4">
                        <div>
                            <label className="block text-sm font-medium mb-1">Sources Limit</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.freeSourcesLimit}
                                onChange={(e) => updateSetting('freeSourcesLimit', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Max verified code sources per user</p>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">API Tokens Limit</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.freeTokensLimit}
                                onChange={(e) => updateSetting('freeTokensLimit', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Max active API tokens per user</p>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">API Calls per Day</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.freeApiCallsPerDay}
                                onChange={(e) => updateSetting('freeApiCallsPerDay', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Daily API call limit</p>
                        </div>
                    </div>
                </div>

                {/* Premium Plan */}
                <div className="rounded-lg bg-card border border-purple-500/30 p-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                        <span className="px-2 py-1 rounded bg-purple-500/20 text-purple-400 text-xs font-medium">PREMIUM</span>
                        Premium Plan Limits
                    </h3>
                    <div className="space-y-4">
                        <div>
                            <label className="block text-sm font-medium mb-1">Sources Limit</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.premiumSourcesLimit}
                                onChange={(e) => updateSetting('premiumSourcesLimit', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Max verified code sources per user</p>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">API Tokens Limit</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.premiumTokensLimit}
                                onChange={(e) => updateSetting('premiumTokensLimit', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Max active API tokens per user</p>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">API Calls per Day</label>
                            <input
                                type="number"
                                min="0"
                                value={settings.premiumApiCallsPerDay}
                                onChange={(e) => updateSetting('premiumApiCallsPerDay', parseInt(e.target.value) || 0)}
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <p className="text-xs text-muted-foreground mt-1">Daily API call limit</p>
                        </div>
                    </div>
                </div>
            </div>

            {/* Save Button */}
            <div className="flex justify-end">
                <button
                    onClick={onSave}
                    disabled={saving}
                    className="flex items-center gap-2 px-6 py-3 rounded-lg bg-primary text-primary-foreground font-medium hover:bg-primary/90 disabled:opacity-50"
                >
                    {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
                    Save Settings
                </button>
            </div>
        </div>
    );
}

function UsageTab({ users, settings, onRefresh }) {
    const [editingUser, setEditingUser] = useState(null);
    const [apiCallsOverride, setApiCallsOverride] = useState('');
    const [saving, setSaving] = useState(false);

    const openEditor = (user) => {
        setEditingUser(user);
        const current = user?.limitsOverride?.apiCallsPerDayOverride;
        setApiCallsOverride(current === null || current === undefined ? '' : String(current));
    };

    const closeEditor = () => {
        setEditingUser(null);
        setApiCallsOverride('');
        setSaving(false);
    };

    const saveOverride = async () => {
        if (!editingUser) return;
        const raw = apiCallsOverride.trim();
        const value = raw.length === 0 ? null : parseInt(raw, 10);
        if (value !== null && (!Number.isFinite(value) || value < 0)) {
            alert('API Calls/Day must be a number >= 0, or blank to clear.');
            return;
        }
        setSaving(true);
        try {
            await api.updateMcpUserLimits(editingUser.id, { apiCallsPerDayOverride: value });
            await onRefresh();
            closeEditor();
        } catch (err) {
            console.error(err);
            alert('Failed to update user limits');
            setSaving(false);
        }
    };

    const clearOverride = async () => {
        if (!editingUser) return;
        setSaving(true);
        try {
            await api.updateMcpUserLimits(editingUser.id, { apiCallsPerDayOverride: null });
            await onRefresh();
            closeEditor();
        } catch (err) {
            console.error(err);
            alert('Failed to clear user limit override');
            setSaving(false);
        }
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold flex items-center gap-2">
                    <Users className="h-5 w-5" />
                    User MCP Usage
                </h3>
                <button
                    onClick={onRefresh}
                    className="flex items-center gap-2 px-4 py-2 rounded-lg bg-secondary hover:bg-secondary/80 text-sm"
                >
                    <RefreshCw className="h-4 w-4" />
                    Refresh
                </button>
            </div>

            <div className="rounded-lg bg-card border border-border overflow-hidden">
                <table className="min-w-full">
                    <thead className="bg-muted/50">
                        <tr>
                            <th className="py-3 px-4 text-left text-sm font-semibold">User</th>
                            <th className="py-3 px-4 text-left text-sm font-semibold">Plan</th>
                            <th className="py-3 px-4 text-center text-sm font-semibold">Sources</th>
                            <th className="py-3 px-4 text-center text-sm font-semibold">Tokens</th>
                            <th className="py-3 px-4 text-center text-sm font-semibold">API Calls Today</th>
                            <th className="py-3 px-4 text-center text-sm font-semibold">API Limit</th>
                            <th className="py-3 px-4 text-left text-sm font-semibold">Last Activity</th>
                            <th className="py-3 px-4 text-right text-sm font-semibold">Actions</th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-border">
                        {users.length === 0 ? (
                            <tr>
                                <td colSpan={8} className="py-8 text-center text-muted-foreground">
                                    No MCP usage data yet.
                                </td>
                            </tr>
                        ) : (
                            users.map((user) => (
                                (() => {
                                    const baseLimit = user.isPremium
                                        ? (settings?.premiumApiCallsPerDay ?? null)
                                        : (settings?.freeApiCallsPerDay ?? null);
                                    const override = user?.limitsOverride?.apiCallsPerDayOverride;
                                    const effectiveLimit = user.apiCallsLimit ?? override ?? baseLimit;
                                    const hasOverride = override !== null && override !== undefined;
                                    return (
                                <tr key={user.id} className="hover:bg-muted/30">
                                    <td className="py-3 px-4">
                                        <div className="font-medium">{user.displayName || 'N/A'}</div>
                                        <div className="text-xs text-muted-foreground">{user.email}</div>
                                    </td>
                                    <td className="py-3 px-4">
                                        <span className={`px-2 py-1 rounded text-xs font-medium ${
                                            user.isPremium
                                                ? 'bg-purple-500/20 text-purple-400'
                                                : 'bg-muted text-muted-foreground'
                                        }`}>
                                            {user.planName || 'Free'}
                                        </span>
                                    </td>
                                    <td className="py-3 px-4 text-center font-mono">
                                        {user.sourcesCount} / {user.sourcesLimit ?? 'Managed'}
                                    </td>
                                    <td className="py-3 px-4 text-center font-mono">
                                        {user.activeTokens} / {user.tokensLimit ?? 'Managed'}
                                    </td>
                                    <td className="py-3 px-4 text-center font-mono">{user.apiCallsToday}</td>
                                    <td className="py-3 px-4 text-center font-mono">
                                        <span className={hasOverride ? 'text-amber-500' : ''}>
                                            {effectiveLimit ?? '—'}
                                        </span>
                                    </td>
                                    <td className="py-3 px-4 text-sm text-muted-foreground">
                                        {user.lastApiCallDate
                                            ? new Date(user.lastApiCallDate).toLocaleDateString()
                                            : 'Never'}
                                    </td>
                                    <td className="py-3 px-4 text-right">
                                        <button
                                            onClick={() => openEditor(user)}
                                            className="px-3 py-1.5 rounded-md bg-secondary hover:bg-secondary/80 text-xs"
                                        >
                                            Edit Limit
                                        </button>
                                    </td>
                                </tr>
                                    );
                                })()
                            ))
                        )}
                    </tbody>
                </table>
            </div>

            {editingUser && (
                <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
                    <div className="w-full max-w-lg rounded-lg bg-card border border-border p-6 space-y-4">
                        <div>
                            <div className="text-lg font-semibold">Edit User Tool Call Limit</div>
                            <div className="text-sm text-muted-foreground">
                                {editingUser.email}
                            </div>
                        </div>

                        <div className="space-y-2">
                            <label className="block text-sm font-medium">API Calls per Day (override)</label>
                            <input
                                type="number"
                                min="0"
                                value={apiCallsOverride}
                                onChange={(e) => setApiCallsOverride(e.target.value)}
                                placeholder="Leave blank to use plan default"
                                className="w-full rounded-md border border-border bg-background p-2"
                            />
                            <div className="text-xs text-muted-foreground">
                                Blank = use plan default. This affects tool calling quota.
                            </div>
                        </div>

                        <div className="flex justify-end gap-2 pt-2">
                            <button
                                onClick={closeEditor}
                                disabled={saving}
                                className="px-4 py-2 rounded-md bg-muted hover:bg-muted/80 text-sm disabled:opacity-50"
                            >
                                Cancel
                            </button>
                            <button
                                onClick={clearOverride}
                                disabled={saving}
                                className="px-4 py-2 rounded-md bg-secondary hover:bg-secondary/80 text-sm disabled:opacity-50"
                            >
                                Clear
                            </button>
                            <button
                                onClick={saveOverride}
                                disabled={saving}
                                className="px-4 py-2 rounded-md bg-primary text-primary-foreground hover:bg-primary/90 text-sm disabled:opacity-50 flex items-center gap-2"
                            >
                                {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : null}
                                Save
                            </button>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

function StatsTab({ stats, settings }) {
    if (!stats) return null;

    const statCards = [
        { label: 'Users with MCP Usage', value: stats.stats?.usersWithUsage || 0, color: 'text-blue-400' },
        { label: 'Total Verified Sources', value: stats.stats?.totalVerifiedSources || 0, color: 'text-green-400' },
        { label: 'Active API Tokens', value: stats.stats?.totalActiveTokens || 0, color: 'text-amber-400' },
        { label: 'API Calls Today', value: stats.stats?.totalApiCallsToday || 0, color: 'text-purple-400' },
    ];

    return (
        <div className="space-y-6">
            <h3 className="text-lg font-semibold flex items-center gap-2">
                <Activity className="h-5 w-5" />
                MCP Statistics
            </h3>

            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                {statCards.map((stat) => (
                    <div key={stat.label} className="rounded-lg bg-card border border-border p-6">
                        <div className="text-sm text-muted-foreground mb-2">{stat.label}</div>
                        <div className={`text-3xl font-bold ${stat.color}`}>{stat.value}</div>
                    </div>
                ))}
            </div>

            {/* Current Limits Summary */}
            {settings && (
                <div className="rounded-lg bg-card border border-border p-6">
                    <h4 className="font-semibold mb-4">Current Limits Summary</h4>
                    <div className="grid gap-4 md:grid-cols-2">
                        <div>
                            <h5 className="text-sm font-medium text-muted-foreground mb-2">Free Plan</h5>
                            <ul className="space-y-1 text-sm">
                                <li>Sources: {settings.freeSourcesLimit}</li>
                                <li>Tokens: {settings.freeTokensLimit}</li>
                                <li>API Calls/Day: {settings.freeApiCallsPerDay}</li>
                            </ul>
                        </div>
                        <div>
                            <h5 className="text-sm font-medium text-purple-400 mb-2">Premium Plan</h5>
                            <ul className="space-y-1 text-sm">
                                <li>Sources: {settings.premiumSourcesLimit}</li>
                                <li>Tokens: {settings.premiumTokensLimit}</li>
                                <li>API Calls/Day: {settings.premiumApiCallsPerDay}</li>
                            </ul>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}

function DiagnosticsTab({ diagnostics, onRefresh }) {
    const [checking, setChecking] = useState(false);
    const [checkResult, setCheckResult] = useState(null);
    const summary = diagnostics?.diagnostics?.summary || {};
    const recent = diagnostics?.diagnostics?.recent || [];
    const tools = diagnostics?.diagnostics?.tools || [];
    const server = diagnostics?.server || {};

    const runCheck = async () => {
        setChecking(true);
        try {
            const result = await api.runMcpDiagnosticCheck();
            setCheckResult(result);
            await onRefresh();
        } catch (error) {
            setCheckResult({ status: 'failed', error: error.message });
        } finally {
            setChecking(false);
        }
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between gap-4">
                <div>
                    <h3 className="text-lg font-semibold flex items-center gap-2">
                        <Activity className="h-5 w-5" />
                        MCP Diagnostics
                    </h3>
                    <p className="text-sm text-muted-foreground mt-1">
                        Discovery and tool execution events from hosted and in-app MCP clients.
                    </p>
                </div>
                <button
                    onClick={runCheck}
                    disabled={checking}
                    className="flex items-center gap-2 px-4 py-2 rounded-lg bg-secondary hover:bg-secondary/80 text-sm"
                >
                    <RefreshCw className={`h-4 w-4 ${checking ? 'animate-spin' : ''}`} />
                    {checking ? 'Checking...' : 'Run check'}
                </button>
            </div>

            {checkResult && (
                <div className={`rounded-lg border p-4 text-sm ${
                    checkResult.status === 'ok'
                        ? 'border-green-500/30 bg-green-500/10 text-green-600'
                        : 'border-red-500/30 bg-red-500/10 text-red-600'
                }`}>
                    {checkResult.status === 'ok'
                        ? `Protocol initialized successfully. ${checkResult.check?.toolCount || 0} entitled tools discovered in ${checkResult.check?.durationMs || 0} ms.`
                        : `MCP check failed: ${checkResult.error || 'Incomplete tool metadata'}`}
                </div>
            )}

            <div className="rounded-lg bg-card border border-border p-5">
                <div className="grid gap-3 md:grid-cols-2 text-sm">
                    <div><span className="text-muted-foreground">Status:</span> <span className="text-green-500 font-medium">{diagnostics?.status || 'unknown'}</span></div>
                    <div><span className="text-muted-foreground">Version:</span> {server.version || '-'}</div>
                    <div className="break-all"><span className="text-muted-foreground">Remote endpoint:</span> {server.remoteUrl || '-'}</div>
                    <div><span className="text-muted-foreground">Authentication:</span> {server.authentication || '-'}</div>
                </div>
            </div>

            <div className="grid gap-4 md:grid-cols-4">
                {[
                    ['Events (24h)', summary.total_events || 0],
                    ['Successful', summary.successful_events || 0],
                    ['Failed', summary.failed_events || 0],
                    ['Average latency', `${summary.average_duration_ms || 0} ms`],
                ].map(([label, value]) => (
                    <div key={label} className="rounded-lg bg-card border border-border p-5">
                        <div className="text-xs text-muted-foreground">{label}</div>
                        <div className="text-2xl font-bold mt-2">{value}</div>
                    </div>
                ))}
            </div>

            <div className="grid gap-6 lg:grid-cols-2">
                <div className="rounded-lg bg-card border border-border overflow-hidden">
                    <div className="font-semibold p-4 border-b border-border">Most-used tools</div>
                    <div className="divide-y divide-border">
                        {tools.length === 0 ? (
                            <div className="p-6 text-sm text-muted-foreground">No tool calls recorded yet.</div>
                        ) : tools.map((tool) => (
                            <div key={tool.tool_name} className="p-3 flex items-center justify-between text-sm">
                                <span className="font-mono">{tool.tool_name}</span>
                                <span className="text-muted-foreground">{tool.count} calls | {tool.failures} failed | {tool.average_duration_ms} ms</span>
                            </div>
                        ))}
                    </div>
                </div>

                <div className="rounded-lg bg-card border border-border overflow-hidden">
                    <div className="font-semibold p-4 border-b border-border">Recent events</div>
                    <div className="max-h-96 overflow-auto divide-y divide-border">
                        {recent.length === 0 ? (
                            <div className="p-6 text-sm text-muted-foreground">Connect an agent or use an in-app tool to populate diagnostics.</div>
                        ) : recent.map((event) => (
                            <div key={event.id} className="p-3 text-sm space-y-1">
                                <div className="flex items-center justify-between gap-3">
                                    <span className="font-mono">{event.tool_name || event.method}</span>
                                    <span className={event.success ? 'text-green-500' : 'text-red-500'}>
                                        {event.success ? 'Success' : 'Failed'}
                                    </span>
                                </div>
                                <div className="text-xs text-muted-foreground">
                                    {event.transport} | {event.duration_ms} ms | {new Date(event.created_at).toLocaleString()}
                                </div>
                                {event.error ? <div className="text-xs text-red-500 break-words">{event.error}</div> : null}
                            </div>
                        ))}
                    </div>
                </div>
            </div>
        </div>
    );
}
