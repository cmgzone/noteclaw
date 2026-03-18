"use client";

import React, { useEffect, useState } from "react";
import {
    Key,
    Activity,
    Code,
    Bot,
    Clock,
    Shield,
    Copy,
    Check,
    Trash2,
    Plus,
    RefreshCw,
    LogOut,
    Loader2,
    ArrowLeft,
    Eye,
    EyeOff,
    Gauge,
    AlertTriangle,
    Crown,
    Settings,
    Sparkles,
} from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { useAuth } from "@/lib/auth-context";
import api, { ApiToken, McpStats, McpUsageEntry, VerifiedSource, AgentNotebook, McpQuota, McpUserSettings, AIModelOption } from "@/lib/api";

export default function McpDashboardPage() {
    const { user, isLoading: authLoading, isAuthenticated, logout } = useAuth();
    const router = useRouter();
    const [stats, setStats] = useState<McpStats | null>(null);
    const [quota, setQuota] = useState<McpQuota | null>(null);
    const [tokens, setTokens] = useState<ApiToken[]>([]);
    const [usage, setUsage] = useState<McpUsageEntry[]>([]);
    const [sources, setSources] = useState<VerifiedSource[]>([]);
    const [notebooks, setNotebooks] = useState<AgentNotebook[]>([]);
    const [settings, setSettings] = useState<McpUserSettings | null>(null);
    const [aiModels, setAiModels] = useState<AIModelOption[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [activeTab, setActiveTab] = useState<"overview" | "tokens" | "usage" | "sources" | "settings">("overview");

    useEffect(() => {
        if (!authLoading && !isAuthenticated) {
            router.push("/login");
            return;
        }
        if (isAuthenticated) {
            loadData();
        }
    }, [authLoading, isAuthenticated, router]);

    const loadData = async () => {
        setIsLoading(true);
        try {
            const [statsData, quotaData, tokensData, usageData, sourcesData, notebooksData, settingsData, modelsData] = await Promise.all([
                api.getMcpStats().catch(() => null),
                api.getMcpQuota().catch(() => null),
                api.getApiTokens().catch(() => []),
                api.getMcpUsage(20).catch(() => []),
                api.getVerifiedSources().catch(() => []),
                api.getAgentNotebooks().catch(() => []),
                api.getMcpSettings().catch(() => null),
                api.getAIModels().catch(() => []),
            ]);
            setStats(statsData);
            setQuota(quotaData);
            setTokens(tokensData);
            setUsage(usageData);
            setSources(sourcesData);
            setNotebooks(notebooksData);
            setSettings(settingsData);
            setAiModels(modelsData);
        } catch (error) {
            console.error("Failed to load MCP data:", error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleLogout = () => {
        logout();
        router.push("/");
    };

    if (authLoading || (!isAuthenticated && !authLoading)) {
        return (
            <div className="min-h-screen bg-neutral-950 flex items-center justify-center">
                <Loader2 className="animate-spin text-blue-500" size={40} />
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-neutral-950 text-white">
            <DashboardNav user={user} onLogout={handleLogout} />
            <main className="container mx-auto px-6 py-8">
                <header className="mb-8">
                    <Link href="/dashboard" className="flex items-center gap-2 text-neutral-400 hover:text-white mb-4 text-sm">
                        <ArrowLeft size={16} />
                        Back to Dashboard
                    </Link>
                    <div className="flex items-center justify-between">
                        <div>
                            <h1 className="text-3xl font-bold tracking-tight flex items-center gap-3">
                                <Bot className="text-purple-400" />
                                MCP Usage
                            </h1>
                            <p className="text-neutral-400 mt-1">Manage your API tokens and monitor coding agent activity.</p>
                        </div>
                        <button onClick={loadData} className="flex items-center gap-2 px-4 py-2 rounded-lg bg-white/5 hover:bg-white/10 transition-colors text-sm">
                            <RefreshCw size={16} />
                            Refresh
                        </button>
                    </div>
                    <div className="mt-4 rounded-lg border border-amber-500/20 bg-amber-500/10 p-4 text-amber-200">
                        <div className="font-semibold mb-2">Common Errors</div>
                        <ul className="list-disc list-inside space-y-1 text-sm">
                            <li>401: Invalid or expired API key. Generate a new token in Settings -&gt; Agent Connections.</li>
                            <li>403: MCP disabled or insufficient permissions. Check MCP is enabled and your token permissions.</li>
                            <li>429: Rate limit exceeded. Call get_quota and retry later.</li>
                            <li>503: Service unavailable. Wait briefly and retry.</li>
                            <li>Network: Verify BACKEND_URL and CODING_AGENT_API_KEY in your .env.</li>
                        </ul>
                    </div>
                </header>

                {/* Tabs */}
                <div className="flex gap-2 mb-6 border-b border-white/10 pb-4">
                    {(["overview", "tokens", "usage", "sources", "settings"] as const).map((tab) => (
                        <button
                            key={tab}
                            onClick={() => setActiveTab(tab)}
                            className={`px-4 py-2 rounded-lg text-sm font-medium transition-colors flex items-center gap-2 ${
                                activeTab === tab ? "bg-blue-600 text-white" : "bg-white/5 text-neutral-400 hover:bg-white/10"
                            }`}
                        >
                            {tab === "settings" && <Settings size={14} />}
                            {tab.charAt(0).toUpperCase() + tab.slice(1)}
                        </button>
                    ))}
                </div>

                {isLoading ? (
                    <div className="flex items-center justify-center py-12">
                        <Loader2 className="animate-spin text-blue-500" size={32} />
                    </div>
                ) : (
                    <>
                        {activeTab === "overview" && <OverviewTab stats={stats} quota={quota} tokens={tokens} usage={usage} notebooks={notebooks} />}
                        {activeTab === "tokens" && <TokensTab tokens={tokens} quota={quota} onRefresh={loadData} />}
                        {activeTab === "usage" && <UsageTab usage={usage} quota={quota} />}
                        {activeTab === "sources" && <SourcesTab sources={sources} quota={quota} />}
                        {activeTab === "settings" && <SettingsTab settings={settings} aiModels={aiModels} onRefresh={loadData} />}
                    </>
                )}
            </main>
        </div>
    );
}


function DashboardNav({ user, onLogout }: { user: any; onLogout: () => void }) {
    return (
        <nav className="border-b border-white/5 bg-neutral-900/50 backdrop-blur-xl">
            <div className="container mx-auto flex h-16 items-center justify-between px-6">
                <Link href="/" className="flex items-center gap-2">
                    <Image src="/icon.png" alt="NoteClaw" width={24} height={24} className="rounded-md" />
                    <span className="font-bold tracking-tight">NoteClaw</span>
                </Link>
                <div className="flex items-center gap-4">
                    <span className="text-sm text-neutral-400 hidden md:block">{user?.email}</span>
                    <button onClick={onLogout} className="flex items-center gap-2 text-sm font-medium text-neutral-400 hover:text-white transition-colors">
                        <LogOut size={16} />
                        <span className="hidden md:inline">Log out</span>
                    </button>
                    <div className="h-8 w-8 rounded-full bg-gradient-to-tr from-blue-500 to-purple-500 flex items-center justify-center text-xs font-bold">
                        {user?.displayName?.[0]?.toUpperCase() || user?.email?.[0]?.toUpperCase() || "U"}
                    </div>
                </div>
            </div>
        </nav>
    );
}

function StatCard({ title, value, icon, color }: { title: string; value: string | number; icon: React.ReactNode; color: string }) {
    return (
        <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6 backdrop-blur-sm">
            <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-neutral-400">{title}</h3>
                <div className={color}>{icon}</div>
            </div>
            <div className="text-2xl font-bold">{value}</div>
        </div>
    );
}

function OverviewTab({ stats, quota, tokens, usage, notebooks }: { stats: McpStats | null; quota: McpQuota | null; tokens: ApiToken[]; usage: McpUsageEntry[]; notebooks: AgentNotebook[] }) {
    return (
        <div className="space-y-6">
            {/* MCP Disabled Warning */}
            {quota && !quota.isMcpEnabled && (
                <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 flex items-center gap-3">
                    <AlertTriangle className="text-amber-400" size={24} />
                    <div>
                        <div className="font-semibold text-amber-400">MCP is Currently Disabled</div>
                        <div className="text-sm text-neutral-400">MCP functionality has been disabled by the administrator.</div>
                    </div>
                </div>
            )}

            {/* Quota Card */}
            {quota && (
                <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6 backdrop-blur-sm">
                    <div className="flex items-center justify-between mb-4">
                        <h3 className="text-lg font-semibold flex items-center gap-2">
                            <Gauge size={20} className="text-blue-400" />
                            Your Usage Quota
                        </h3>
                        {quota.isPremium && (
                            <span className="flex items-center gap-1 px-3 py-1 rounded-full bg-purple-500/20 text-purple-400 text-sm">
                                <Crown size={14} />
                                Premium
                            </span>
                        )}
                    </div>
                    <div className="grid gap-4 md:grid-cols-3">
                        <QuotaBar label="Sources" used={quota.sourcesUsed} limit={quota.sourcesLimit} color="green" />
                        <QuotaBar label="API Tokens" used={quota.tokensUsed} limit={quota.tokensLimit} color="amber" />
                        <QuotaBar label="API Calls Today" used={quota.apiCallsUsed} limit={quota.apiCallsLimit} color="blue" />
                    </div>
                    {!quota.isPremium && (
                        <div className="mt-4 pt-4 border-t border-white/5 text-sm text-neutral-400">
                            <Link href="/plans" className="text-blue-400 hover:text-blue-300">
                                Upgrade to Premium
                            </Link>{" "}
                            for higher limits and more features.
                        </div>
                    )}
                </div>
            )}

            {/* Stats Grid */}
            <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
                <StatCard title="Active Tokens" value={stats?.activeTokens || 0} icon={<Key size={20} />} color="text-amber-400" />
                <StatCard title="Total API Calls" value={stats?.totalUsage || 0} icon={<Activity size={20} />} color="text-blue-400" />
                <StatCard title="Verified Sources" value={stats?.verifiedSources || 0} icon={<Code size={20} />} color="text-green-400" />
                <StatCard title="Agent Sessions" value={stats?.agentSessions || 0} icon={<Bot size={20} />} color="text-purple-400" />
            </div>

            {/* Recent Activity */}
            <div className="grid gap-6 md:grid-cols-2">
                <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                        <Clock size={18} className="text-blue-400" />
                        Recent API Usage
                    </h3>
                    {usage.length === 0 ? (
                        <p className="text-neutral-500 text-sm">No recent API activity.</p>
                    ) : (
                        <div className="space-y-3">
                            {usage.slice(0, 5).map((entry) => (
                                <div key={entry.id} className="flex items-center justify-between p-3 rounded-lg bg-white/5">
                                    <div>
                                        <div className="font-mono text-sm text-blue-400">{entry.endpoint}</div>
                                        <div className="text-xs text-neutral-500">{entry.tokenName}</div>
                                    </div>
                                    <span className="text-xs text-neutral-500">{new Date(entry.createdAt).toLocaleString()}</span>
                                </div>
                            ))}
                        </div>
                    )}
                </div>

                <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6">
                    <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                        <Bot size={18} className="text-purple-400" />
                        Connected Agents
                    </h3>
                    {notebooks.length === 0 ? (
                        <p className="text-neutral-500 text-sm">No agents connected yet.</p>
                    ) : (
                        <div className="space-y-3">
                            {notebooks.slice(0, 5).map((nb) => (
                                <div key={nb.id} className="flex items-center justify-between p-3 rounded-lg bg-white/5">
                                    <div>
                                        <div className="font-medium text-sm">{nb.session?.agentName || "Unknown Agent"}</div>
                                        <div className="text-xs text-neutral-500">{nb.title}</div>
                                    </div>
                                    <span className={`text-xs px-2 py-1 rounded-full ${nb.session?.status === "active" ? "bg-green-500/20 text-green-400" : "bg-neutral-500/20 text-neutral-400"}`}>
                                        {nb.session?.status || "unknown"}
                                    </span>
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}

function QuotaBar({ label, used, limit, color }: { label: string; used: number; limit: number; color: string }) {
    const percentage = limit > 0 ? Math.min(100, (used / limit) * 100) : 0;
    const isNearLimit = percentage >= 80;
    const colorClasses = {
        green: { bar: "bg-green-500", text: "text-green-400" },
        amber: { bar: "bg-amber-500", text: "text-amber-400" },
        blue: { bar: "bg-blue-500", text: "text-blue-400" },
    };
    const colors = colorClasses[color as keyof typeof colorClasses] || colorClasses.blue;

    return (
        <div>
            <div className="flex items-center justify-between mb-2">
                <span className="text-sm text-neutral-400">{label}</span>
                <span className={`text-sm font-mono ${isNearLimit ? "text-red-400" : colors.text}`}>
                    {used} / {limit}
                </span>
            </div>
            <div className="h-2 bg-white/10 rounded-full overflow-hidden">
                <div
                    className={`h-full ${isNearLimit ? "bg-red-500" : colors.bar} transition-all duration-300`}
                    style={{ width: `${percentage}%` }}
                />
            </div>
        </div>
    );
}


function TokensTab({ tokens, quota, onRefresh }: { tokens: ApiToken[]; quota: McpQuota | null; onRefresh: () => void }) {
    const [showCreateModal, setShowCreateModal] = useState(false);
    const [newTokenName, setNewTokenName] = useState("");
    const [newToken, setNewToken] = useState<string | null>(null);
    const [isCreating, setIsCreating] = useState(false);
    const [copied, setCopied] = useState(false);

    const canCreateToken = quota ? quota.tokensRemaining > 0 : true;

    const handleCreateToken = async () => {
        if (!newTokenName.trim()) return;
        setIsCreating(true);
        try {
            const result = await api.createApiToken(newTokenName);
            setNewToken(result.token);
            setNewTokenName("");
            onRefresh();
        } catch (error: any) {
            console.error("Failed to create token:", error);
            alert(error.message || "Failed to create token");
        } finally {
            setIsCreating(false);
        }
    };

    const handleRevokeToken = async (tokenId: string) => {
        if (!confirm("Are you sure you want to revoke this token? This action cannot be undone.")) return;
        try {
            await api.revokeApiToken(tokenId);
            onRefresh();
        } catch (error) {
            console.error("Failed to revoke token:", error);
            alert("Failed to revoke token");
        }
    };

    const copyToClipboard = (text: string) => {
        navigator.clipboard.writeText(text);
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <div className="flex items-center gap-4">
                    <h3 className="text-lg font-semibold">API Tokens</h3>
                    {quota && (
                        <span className="text-sm text-neutral-400">
                            {quota.tokensUsed} / {quota.tokensLimit} used
                        </span>
                    )}
                </div>
                <button 
                    onClick={() => setShowCreateModal(true)} 
                    disabled={!canCreateToken}
                    className="flex items-center gap-2 px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 disabled:bg-neutral-700 disabled:cursor-not-allowed transition-colors text-sm font-medium"
                >
                    <Plus size={16} />
                    Create Token
                </button>
            </div>

            {/* Quota Warning */}
            {quota && !canCreateToken && (
                <div className="rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 flex items-center gap-3">
                    <AlertTriangle className="text-amber-400" size={20} />
                    <div className="flex-1">
                        <div className="font-medium text-amber-400">Token Limit Reached</div>
                        <div className="text-sm text-neutral-400">
                            You've reached your limit of {quota.tokensLimit} API tokens.{" "}
                            {!quota.isPremium && (
                                <Link href="/plans" className="text-blue-400 hover:text-blue-300">
                                    Upgrade to Premium
                                </Link>
                            )}
                        </div>
                    </div>
                </div>
            )}

            {/* New Token Display */}
            {newToken && (
                <motion.div initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} className="rounded-xl border border-green-500/30 bg-green-500/10 p-6">
                    <div className="flex items-start gap-3">
                        <Shield className="text-green-400 mt-1" size={20} />
                        <div className="flex-1">
                            <h4 className="font-semibold text-green-400 mb-2">Token Created Successfully!</h4>
                            <p className="text-sm text-neutral-300 mb-4">Copy this token now. You won't be able to see it again.</p>
                            <div className="flex items-center gap-2 p-3 rounded-lg bg-black/30 font-mono text-sm">
                                <code className="flex-1 break-all">{newToken}</code>
                                <button onClick={() => copyToClipboard(newToken)} className="p-2 hover:bg-white/10 rounded transition-colors">
                                    {copied ? <Check size={16} className="text-green-400" /> : <Copy size={16} />}
                                </button>
                            </div>
                            <button onClick={() => setNewToken(null)} className="mt-4 text-sm text-neutral-400 hover:text-white">
                                Dismiss
                            </button>
                        </div>
                    </div>
                </motion.div>
            )}

            {/* Create Token Modal */}
            {showCreateModal && !newToken && (
                <motion.div initial={{ opacity: 0, y: -10 }} animate={{ opacity: 1, y: 0 }} className="rounded-xl border border-white/10 bg-neutral-900 p-6">
                    <h4 className="font-semibold mb-4">Create New API Token</h4>
                    <input
                        type="text"
                        value={newTokenName}
                        onChange={(e) => setNewTokenName(e.target.value)}
                        placeholder="Token name (e.g., Kiro Agent)"
                        className="w-full px-4 py-3 rounded-lg bg-white/5 border border-white/10 focus:border-blue-500 focus:outline-none mb-4"
                    />
                    <div className="flex gap-3">
                        <button onClick={handleCreateToken} disabled={isCreating || !newTokenName.trim()} className="flex items-center gap-2 px-4 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 disabled:opacity-50 transition-colors text-sm font-medium">
                            {isCreating ? <Loader2 size={16} className="animate-spin" /> : <Plus size={16} />}
                            Create
                        </button>
                        <button onClick={() => setShowCreateModal(false)} className="px-4 py-2 rounded-lg bg-white/5 hover:bg-white/10 transition-colors text-sm">
                            Cancel
                        </button>
                    </div>
                </motion.div>
            )}

            {/* Token List */}
            <div className="rounded-xl border border-white/5 bg-neutral-900/50 overflow-hidden">
                {tokens.length === 0 ? (
                    <div className="p-8 text-center text-neutral-500">
                        <Key size={40} className="mx-auto mb-4 opacity-50" />
                        <p>No API tokens yet. Create one to connect coding agents.</p>
                    </div>
                ) : (
                    <table className="w-full">
                        <thead className="bg-white/5">
                            <tr>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Name</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Token</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Last Used</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Status</th>
                                <th className="text-right px-6 py-3 text-sm font-medium text-neutral-400">Actions</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-white/5">
                            {tokens.map((token) => (
                                <tr key={token.id} className="hover:bg-white/5">
                                    <td className="px-6 py-4 font-medium">{token.name}</td>
                                    <td className="px-6 py-4 font-mono text-sm text-neutral-400">
                                        {token.tokenPrefix}...{token.tokenSuffix}
                                    </td>
                                    <td className="px-6 py-4 text-sm text-neutral-400">
                                        {token.lastUsedAt ? new Date(token.lastUsedAt).toLocaleDateString() : "Never"}
                                    </td>
                                    <td className="px-6 py-4">
                                        <span className={`text-xs px-2 py-1 rounded-full ${token.isActive ? "bg-green-500/20 text-green-400" : "bg-red-500/20 text-red-400"}`}>
                                            {token.isActive ? "Active" : "Revoked"}
                                        </span>
                                    </td>
                                    <td className="px-6 py-4 text-right">
                                        {token.isActive && (
                                            <button onClick={() => handleRevokeToken(token.id)} className="p-2 text-red-400 hover:bg-red-500/10 rounded transition-colors">
                                                <Trash2 size={16} />
                                            </button>
                                        )}
                                    </td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>
        </div>
    );
}


function UsageTab({ usage, quota }: { usage: McpUsageEntry[]; quota: McpQuota | null }) {
    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold">API Usage History</h3>
                {quota && (
                    <span className="text-sm text-neutral-400">
                        {quota.apiCallsUsed} / {quota.apiCallsLimit} calls today
                    </span>
                )}
            </div>
            <div className="rounded-xl border border-white/5 bg-neutral-900/50 overflow-hidden">
                {usage.length === 0 ? (
                    <div className="p-8 text-center text-neutral-500">
                        <Activity size={40} className="mx-auto mb-4 opacity-50" />
                        <p>No API usage recorded yet.</p>
                    </div>
                ) : (
                    <table className="w-full">
                        <thead className="bg-white/5">
                            <tr>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Endpoint</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Token</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">IP Address</th>
                                <th className="text-left px-6 py-3 text-sm font-medium text-neutral-400">Time</th>
                            </tr>
                        </thead>
                        <tbody className="divide-y divide-white/5">
                            {usage.map((entry) => (
                                <tr key={entry.id} className="hover:bg-white/5">
                                    <td className="px-6 py-4 font-mono text-sm text-blue-400">{entry.endpoint}</td>
                                    <td className="px-6 py-4">
                                        <div className="text-sm">{entry.tokenName}</div>
                                        <div className="text-xs text-neutral-500 font-mono">{entry.tokenPrefix}...</div>
                                    </td>
                                    <td className="px-6 py-4 text-sm text-neutral-400">{entry.ipAddress || "N/A"}</td>
                                    <td className="px-6 py-4 text-sm text-neutral-400">{new Date(entry.createdAt).toLocaleString()}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>
        </div>
    );
}

function SourcesTab({ sources, quota }: { sources: VerifiedSource[]; quota: McpQuota | null }) {
    const [expandedSource, setExpandedSource] = useState<string | null>(null);

    const getLanguageColor = (lang: string) => {
        const colors: Record<string, string> = {
            javascript: "text-yellow-400",
            typescript: "text-blue-400",
            python: "text-green-400",
            dart: "text-cyan-400",
            json: "text-orange-400",
        };
        return colors[lang.toLowerCase()] || "text-neutral-400";
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold">Verified Code Sources</h3>
                {quota && (
                    <span className="text-sm text-neutral-400">
                        {quota.sourcesUsed} / {quota.sourcesLimit} sources
                    </span>
                )}
            </div>
            {sources.length === 0 ? (
                <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-8 text-center text-neutral-500">
                    <Code size={40} className="mx-auto mb-4 opacity-50" />
                    <p>No verified code sources yet.</p>
                    <p className="text-sm mt-2">Code verified by AI agents will appear here.</p>
                </div>
            ) : (
                <div className="space-y-4">
                    {sources.map((source) => (
                        <div key={source.id} className="rounded-xl border border-white/5 bg-neutral-900/50 overflow-hidden">
                            <div className="p-4 flex items-center justify-between cursor-pointer hover:bg-white/5" onClick={() => setExpandedSource(expandedSource === source.id ? null : source.id)}>
                                <div className="flex items-center gap-3">
                                    <Code size={18} className={getLanguageColor(source.metadata.language)} />
                                    <div>
                                        <div className="font-medium">{source.title}</div>
                                        <div className="text-xs text-neutral-500 flex items-center gap-2">
                                            <span className={getLanguageColor(source.metadata.language)}>{source.metadata.language}</span>
                                            <span>•</span>
                                            <span>{new Date(source.created_at).toLocaleDateString()}</span>
                                            {source.metadata.agentName && (
                                                <>
                                                    <span>•</span>
                                                    <span className="text-purple-400">{source.metadata.agentName}</span>
                                                </>
                                            )}
                                        </div>
                                    </div>
                                </div>
                                <div className="flex items-center gap-2">
                                    {source.metadata.verification?.score && (
                                        <span className={`text-xs px-2 py-1 rounded-full ${source.metadata.verification.score >= 80 ? "bg-green-500/20 text-green-400" : source.metadata.verification.score >= 60 ? "bg-yellow-500/20 text-yellow-400" : "bg-red-500/20 text-red-400"}`}>
                                            Score: {source.metadata.verification.score}
                                        </span>
                                    )}
                                    {expandedSource === source.id ? <EyeOff size={16} /> : <Eye size={16} />}
                                </div>
                            </div>
                            {expandedSource === source.id && (
                                <motion.div initial={{ height: 0 }} animate={{ height: "auto" }} className="border-t border-white/5">
                                    <pre className="p-4 overflow-x-auto text-sm bg-black/30">
                                        <code>{source.content}</code>
                                    </pre>
                                </motion.div>
                            )}
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}


function SettingsTab({ settings, aiModels, onRefresh }: { settings: McpUserSettings | null; aiModels: AIModelOption[]; onRefresh: () => void }) {
    const [isSaving, setIsSaving] = useState(false);
    const [selectedModel, setSelectedModel] = useState<string | null>(settings?.codeAnalysisModelId || null);
    const [analysisEnabled, setAnalysisEnabled] = useState(settings?.codeAnalysisEnabled ?? true);
    const [saveSuccess, setSaveSuccess] = useState(false);

    useEffect(() => {
        if (settings) {
            setSelectedModel(settings.codeAnalysisModelId);
            setAnalysisEnabled(settings.codeAnalysisEnabled);
        }
    }, [settings]);

    const handleSave = async () => {
        setIsSaving(true);
        setSaveSuccess(false);
        try {
            await api.updateMcpSettings({
                codeAnalysisModelId: selectedModel,
                codeAnalysisEnabled: analysisEnabled,
            });
            setSaveSuccess(true);
            onRefresh();
            setTimeout(() => setSaveSuccess(false), 3000);
        } catch (error) {
            console.error("Failed to save settings:", error);
            alert("Failed to save settings");
        } finally {
            setIsSaving(false);
        }
    };

    const getProviderColor = (provider: string) => {
        switch (provider.toLowerCase()) {
            case "gemini":
                return "text-blue-400";
            case "openrouter":
                return "text-purple-400";
            default:
                return "text-neutral-400";
        }
    };

    return (
        <div className="space-y-6">
            <div className="flex items-center justify-between">
                <h3 className="text-lg font-semibold flex items-center gap-2">
                    <Settings size={20} className="text-blue-400" />
                    MCP Settings
                </h3>
            </div>

            <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6 space-y-6">
                {/* Code Analysis Toggle */}
                <div className="flex items-center justify-between">
                    <div>
                        <h4 className="font-medium flex items-center gap-2">
                            <Sparkles size={16} className="text-amber-400" />
                            Automatic Code Analysis
                        </h4>
                        <p className="text-sm text-neutral-400 mt-1">
                            Automatically analyze GitHub files when added as sources
                        </p>
                    </div>
                    <button
                        onClick={() => setAnalysisEnabled(!analysisEnabled)}
                        className={`relative w-12 h-6 rounded-full transition-colors ${
                            analysisEnabled ? "bg-blue-600" : "bg-neutral-700"
                        }`}
                    >
                        <div
                            className={`absolute top-1 w-4 h-4 rounded-full bg-white transition-transform ${
                                analysisEnabled ? "left-7" : "left-1"
                            }`}
                        />
                    </button>
                </div>

                {/* Model Selection */}
                <div className={analysisEnabled ? "" : "opacity-50 pointer-events-none"}>
                    <h4 className="font-medium mb-3">AI Model for Code Analysis</h4>
                    <p className="text-sm text-neutral-400 mb-4">
                        Select which AI model to use for analyzing your code. Models are configured by the administrator.
                    </p>
                    
                    {aiModels.length === 0 ? (
                        <div className="p-4 rounded-lg bg-amber-500/10 border border-amber-500/30 text-amber-400 text-sm">
                            <AlertTriangle size={16} className="inline mr-2" />
                            No AI models available. Contact your administrator to configure AI models.
                        </div>
                    ) : (
                        <div className="space-y-2">
                            {/* Auto option */}
                            <label
                                className={`flex items-center gap-3 p-4 rounded-lg border cursor-pointer transition-colors ${
                                    selectedModel === null
                                        ? "border-blue-500 bg-blue-500/10"
                                        : "border-white/10 bg-white/5 hover:bg-white/10"
                                }`}
                            >
                                <input
                                    type="radio"
                                    name="model"
                                    checked={selectedModel === null}
                                    onChange={() => setSelectedModel(null)}
                                    className="sr-only"
                                />
                                <div className={`w-4 h-4 rounded-full border-2 flex items-center justify-center ${
                                    selectedModel === null ? "border-blue-500" : "border-neutral-500"
                                }`}>
                                    {selectedModel === null && <div className="w-2 h-2 rounded-full bg-blue-500" />}
                                </div>
                                <div className="flex-1">
                                    <div className="font-medium">Auto (Recommended)</div>
                                    <div className="text-sm text-neutral-400">
                                        Automatically select the best available model with fallback support
                                    </div>
                                </div>
                            </label>

                            {/* Model options */}
                            {aiModels.map((model) => (
                                <label
                                    key={model.id}
                                    className={`flex items-center gap-3 p-4 rounded-lg border cursor-pointer transition-colors ${
                                        selectedModel === model.modelId
                                            ? "border-blue-500 bg-blue-500/10"
                                            : "border-white/10 bg-white/5 hover:bg-white/10"
                                    }`}
                                >
                                    <input
                                        type="radio"
                                        name="model"
                                        checked={selectedModel === model.modelId}
                                        onChange={() => setSelectedModel(model.modelId)}
                                        className="sr-only"
                                    />
                                    <div className={`w-4 h-4 rounded-full border-2 flex items-center justify-center ${
                                        selectedModel === model.modelId ? "border-blue-500" : "border-neutral-500"
                                    }`}>
                                        {selectedModel === model.modelId && <div className="w-2 h-2 rounded-full bg-blue-500" />}
                                    </div>
                                    <div className="flex-1">
                                        <div className="font-medium flex items-center gap-2">
                                            {model.name}
                                            <span className={`text-xs px-2 py-0.5 rounded-full bg-white/10 ${getProviderColor(model.provider)}`}>
                                                {model.provider}
                                            </span>
                                            {model.isPremium && (
                                                <span className="text-xs px-2 py-0.5 rounded-full bg-purple-500/20 text-purple-400 flex items-center gap-1">
                                                    <Crown size={10} />
                                                    Premium
                                                </span>
                                            )}
                                        </div>
                                        {model.description && (
                                            <div className="text-sm text-neutral-400 mt-1">{model.description}</div>
                                        )}
                                    </div>
                                </label>
                            ))}
                        </div>
                    )}
                </div>

                {/* Save Button */}
                <div className="flex items-center gap-4 pt-4 border-t border-white/10">
                    <button
                        onClick={handleSave}
                        disabled={isSaving}
                        className="flex items-center gap-2 px-6 py-2 rounded-lg bg-blue-600 hover:bg-blue-700 disabled:opacity-50 transition-colors font-medium"
                    >
                        {isSaving ? (
                            <Loader2 size={16} className="animate-spin" />
                        ) : saveSuccess ? (
                            <Check size={16} />
                        ) : (
                            <Settings size={16} />
                        )}
                        {saveSuccess ? "Saved!" : "Save Settings"}
                    </button>
                    {settings?.updatedAt && (
                        <span className="text-sm text-neutral-500">
                            Last updated: {new Date(settings.updatedAt).toLocaleString()}
                        </span>
                    )}
                </div>
            </div>

            {/* Info Card */}
            <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6">
                <h4 className="font-medium mb-3 flex items-center gap-2">
                    <Sparkles size={16} className="text-purple-400" />
                    About Code Analysis
                </h4>
                <div className="text-sm text-neutral-400 space-y-2">
                    <p>
                        When you add GitHub files as sources via MCP, they are automatically analyzed by AI to provide:
                    </p>
                    <ul className="list-disc list-inside space-y-1 ml-2">
                        <li>Code quality rating (1-10 scale)</li>
                        <li>Architecture and design pattern detection</li>
                        <li>Quality metrics (readability, maintainability, etc.)</li>
                        <li>Strengths and improvement suggestions</li>
                        <li>Security notes and best practices</li>
                    </ul>
                    <p className="mt-3">
                        This analysis improves fact-checking results by giving the AI deep knowledge about your codebase.
                    </p>
                </div>
            </div>
        </div>
    );
}

