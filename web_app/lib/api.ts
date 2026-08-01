// API URL configuration
// Uses environment variable or defaults
const PRODUCTION_API_URL = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api';

const getApiBase = () => {
    // Check for environment variable first
    if (process.env.NEXT_PUBLIC_API_URL) {
        return process.env.NEXT_PUBLIC_API_URL;
    }

    // In browser, check if we're on localhost for development
    if (typeof window !== 'undefined') {
        const hostname = window.location.hostname;
        console.log('[API] Hostname:', hostname);
        if (hostname === 'localhost' || hostname === '127.0.0.1') {
            console.log('[API] Using local backend');
            // Local development - try local backend first
            return 'http://localhost:3001/api';
        }
    }
    console.log('[API] Using production backend:', PRODUCTION_API_URL);
    // Default to production backend
    return PRODUCTION_API_URL;
};

const API_BASE = getApiBase();

export interface User {
    id: string;
    email: string;
    displayName: string;
    emailVerified: boolean;
    twoFactorEnabled: boolean;
    avatarUrl: string | null;
    role: string;
    createdAt?: string;
}

export interface Subscription {
    id: string;
    user_id: string;
    plan_id: string;
    plan_name: string;
    credits_per_month: number;
    plan_price: string;
    is_free_plan: boolean;
    current_credits: number;
    credits_consumed_this_month: number;
    last_renewal_date: string;
    next_renewal_date: string;
    status: string;
    feature_access: PlanFeatureAccess;
}

export interface SignupResponse {
    success?: boolean;
    accessToken?: string;
    refreshToken?: string;
    user: User;
    requiresEmailVerification?: boolean;
    verificationEmailSent?: boolean;
    message?: string;
}

export interface PlanFeatureAccess {
    memory_bank: boolean;
    notebook_chat: boolean;
    websocket_collaboration: boolean;
    code_review: boolean;
    web_search: boolean;
    deep_research: boolean;
    research_save_to_notebook: boolean;
}

export interface CreditTransaction {
    id: string;
    user_id: string;
    amount: number;
    transaction_type: string;
    description: string;
    balance_after: number;
    created_at: string;
}

// Research Interfaces
export interface ResearchConfig {
    depth: 'quick' | 'standard' | 'deep';
    template: 'general' | 'academic' | 'productComparison' | 'marketAnalysis' | 'howToGuide' | 'prosAndCons';
    notebookId?: string;
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

export interface ApiToken {
    id: string;
    name: string;
    tokenPrefix: string;
    tokenSuffix: string;
    expiresAt: string | null;
    lastUsedAt: string | null;
    createdAt: string;
    revokedAt: string | null;
    isActive: boolean;
    metadata?: Record<string, unknown>;
}

export interface TopicAccessAgent {
    id: string;
    agentName: string;
    mcpClientName?: string | null;
    agentIdentifier: string;
    status: string;
    defaultNotebookId: string | null;
}

export interface MemoryTopic {
    id: string;
    title: string;
    description: string | null;
    isAgentNotebook: boolean;
    sourceCount: number;
    ownerAgentSessionId: string | null;
}

export interface TopicAccessGrant {
    agentSessionId: string;
    notebookId: string;
    canRead: boolean;
}

export interface TopicAccessMatrix {
    agents: TopicAccessAgent[];
    topics: MemoryTopic[];
    grants: TopicAccessGrant[];
}

export interface TokenUsageLog {
    id: string;
    endpoint: string;
    ipAddress: string | null;
    userAgent: string | null;
    createdAt: string;
}

export interface McpStats {
    totalTokens: number;
    activeTokens: number;
    totalUsage: number;
    recentUsage: number;
    verifiedSources: number;
    agentSessions: number;
}

export interface McpUsageEntry {
    id: string;
    endpoint: string;
    ipAddress: string | null;
    userAgent: string | null;
    createdAt: string;
    tokenName: string;
    tokenPrefix: string;
}

export interface VerifiedSource {
    id: string;
    notebook_id: string;
    title: string;
    content: string;
    type: string;
    metadata: {
        language: string;
        verification: any;
        isVerified: boolean;
        verifiedAt: string;
        agentName?: string;
    };
    created_at: string;
}

export interface AgentNotebook {
    id: string;
    title: string;
    description: string;
    isAgentNotebook: boolean;
    agentSessionId: string | null;
    createdAt: string;
    session?: {
        id: string;
        agentName: string;
        mcpClientName?: string | null;
        agentIdentifier: string;
        status: string;
        lastActivity: string;
        websocketConnected?: boolean;
        websocketConnectionCount?: number;
        connectedClients?: string[];
    };
}

export interface McpQuota {
    sourcesLimit: number;
    sourcesUsed: number;
    sourcesRemaining: number;
    tokensLimit: number;
    tokensUsed: number;
    tokensRemaining: number;
    apiCallsLimit: number;
    apiCallsUsed: number;
    apiCallsRemaining: number;
    isPremium: boolean;
    isMcpEnabled: boolean;
}

export interface McpUserSettings {
    codeAnalysisModelId: string | null;
    codeAnalysisEnabled: boolean;
    updatedAt: string;
}

export interface AIModelOption {
    id: string;
    name: string;
    modelId: string;
    provider: string;
    description: string;
    isPremium: boolean;
}

export interface Notebook {
    id: string;
    userId: string;
    title: string;
    description: string | null;
    coverImage: string | null;
    category: string | null;
    createdAt: string;
    updatedAt: string;
    sourceCount?: number;
    isShared?: boolean;
    isAgentNotebook?: boolean;
    session?: {
        id: string;
        agentName: string;
        mcpClientName?: string | null;
        agentIdentifier: string;
        status: string;
        lastActivity?: string;
        websocketConnected: boolean;
        websocketConnectionCount: number;
        connectedClients?: string[];
    };
}

export interface Source {
    id: string;
    notebookId: string;
    type: 'pdf' | 'url' | 'youtube' | 'text' | 'image' | 'memory';
    title: string;
    content?: string;
    url?: string;
    imageUrl?: string;
    createdAt: string;
    credibility?: string;
    credibilityScore?: number;
    updatedAt?: string;
    namespace?: string;
    version?: number;
    summary?: string;
    memory?: Record<string, unknown>;
    memoryStats?: {
        fieldCount: number;
        nonEmptyFieldCount: number;
        historyLength: number;
        checkpointCount: number;
        longTermStatus: string;
    };
    isMemorySource?: boolean;
    readOnly?: boolean;
}

class ApiService {
    private token: string | null = null;
    private refreshToken: string | null = null;
    private isRefreshing = false;

    constructor() {
        if (typeof window !== 'undefined') {
            this.token = localStorage.getItem('auth_token');
            this.refreshToken = localStorage.getItem('refresh_token');
        }
    }

    setTokens(accessToken: string, refreshToken: string) {
        this.token = accessToken;
        this.refreshToken = refreshToken;
        if (typeof window !== 'undefined') {
            localStorage.setItem('auth_token', accessToken);
            localStorage.setItem('refresh_token', refreshToken);
        }
    }

    clearTokens() {
        this.token = null;
        this.refreshToken = null;
        if (typeof window !== 'undefined') {
            localStorage.removeItem('auth_token');
            localStorage.removeItem('refresh_token');
        }
    }

    getToken(): string | null {
        return this.token;
    }

    private async fetch<T>(endpoint: string, options: RequestInit = {}): Promise<T> {
        const url = `${API_BASE}${endpoint}`;
        const headers: HeadersInit = {
            'Content-Type': 'application/json',
            ...(this.token && { 'Authorization': `Bearer ${this.token}` }),
            ...options.headers,
        };

        const response = await fetch(url, {
            ...options,
            headers,
        });

        if (response.status === 401 && this.refreshToken && !this.isRefreshing && !endpoint.includes('/auth/login') && !endpoint.includes('/auth/refresh')) {
            console.log('[API] Access token expired, attempting refresh...');
            const refreshed = await this.refreshTokens();
            if (refreshed) {
                // Retry the original request with the new token
                const retryHeaders: HeadersInit = {
                    'Content-Type': 'application/json',
                    'Authorization': `Bearer ${this.token}`,
                    ...options.headers,
                };
                const retryResponse = await fetch(url, {
                    ...options,
                    headers: retryHeaders,
                });
                if (retryResponse.ok) {
                    return retryResponse.json();
                }
            }
        }

        if (!response.ok) {
            const error = await response.json().catch(() => ({ error: 'Request failed' }));
            const requestError = new Error(error.error || 'Request failed') as Error & {
                code?: string;
                email?: string;
                emailSent?: boolean;
            };
            requestError.code = error.code;
            requestError.email = error.email;
            requestError.emailSent = error.emailSent === true;
            throw requestError;
        }

        return response.json();
    }

    async refreshTokens(): Promise<boolean> {
        if (!this.refreshToken) return false;
        this.isRefreshing = true;

        try {
            const response = await fetch(`${API_BASE}/auth/refresh`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refreshToken: this.refreshToken }),
            });

            if (response.ok) {
                const data = await response.json();
                if (data.accessToken) {
                    this.token = data.accessToken;
                    if (typeof window !== 'undefined') {
                        localStorage.setItem('auth_token', data.accessToken);
                    }
                    console.log('[API] Token refreshed successfully');
                    return true;
                }
            } else {
                console.warn('[API] Token refresh failed, logging out');
                this.logout();
            }
        } catch (e) {
            console.error('[API] Error refreshing token:', e);
        } finally {
            this.isRefreshing = false;
        }
        return false;
    }

    // Auth
    async login(email: string, password: string, rememberMe = false): Promise<{ accessToken: string; refreshToken: string; user: User }> {
        const data = await this.fetch<{ accessToken: string; refreshToken: string; user: User }>('/auth/login', {
            method: 'POST',
            body: JSON.stringify({ email, password, rememberMe }),
        });
        this.setTokens(data.accessToken, data.refreshToken);
        return data;
    }

    async signup(email: string, password: string, displayName?: string): Promise<SignupResponse> {
        const data = await this.fetch<SignupResponse>('/auth/signup', {
            method: 'POST',
            body: JSON.stringify({ email, password, displayName }),
        });
        if (data.accessToken && data.refreshToken) {
            this.setTokens(data.accessToken, data.refreshToken);
        }
        return data;
    }

    async getCurrentUser(): Promise<User> {
        const data = await this.fetch<{ user: User }>('/auth/me');
        return data.user;
    }

    async deleteAccount(password: string): Promise<{ success: boolean; message: string }> {
        return this.fetch('/auth/delete-account', {
            method: 'POST',
            body: JSON.stringify({ password }),
        });
    }

    logout() {
        this.clearTokens();
    }

    async forgotPassword(email: string): Promise<{ success: boolean; message?: string }> {
        return this.fetch('/auth/forgot-password', {
            method: 'POST',
            body: JSON.stringify({ email }),
        });
    }

    async resetPassword(token: string, newPassword: string): Promise<{ success: boolean; message?: string }> {
        return this.fetch('/auth/reset-password', {
            method: 'POST',
            body: JSON.stringify({ token, newPassword }),
        });
    }

    async resendVerification(email: string): Promise<{ success: boolean; emailSent?: boolean; message?: string }> {
        return this.fetch('/auth/resend-verification', {
            method: 'POST',
            body: JSON.stringify({ email }),
        });
    }

    async verifyEmail(token: string): Promise<{ success: boolean; message?: string }> {
        return this.fetch('/auth/verify-email', {
            method: 'POST',
            body: JSON.stringify({ token }),
        });
    }

    // Notebooks
    async getNotebooks(): Promise<Notebook[]> {
        try {
            const data = await this.fetch<{ notebooks: Notebook[] }>('/coding-agent/memory/notebooks');
            if (data && Array.isArray(data.notebooks)) {
                return data.notebooks;
            }
        } catch (e) {
            console.warn('[API] Memory notebooks fetch failed, falling back to standard notebooks:', e);
        }

        try {
            const fallbackData = await this.fetch<{ notebooks: Notebook[] }>('/notebooks');
            return fallbackData.notebooks || [];
        } catch (fallbackError) {
            console.error('[API] Standard notebooks fetch failed:', fallbackError);
            return [];
        }
    }

    async getNotebook(id: string): Promise<Notebook> {
        const data = await this.fetch<{ notebook: Notebook }>(`/coding-agent/memory/notebooks/${id}`);
        return data.notebook;
    }

    async getMemoryNotebook(id: string): Promise<{ notebook: Notebook; sources: Source[] }> {
        return this.fetch<{ notebook: Notebook; sources: Source[] }>(
            `/coding-agent/memory/notebooks/${id}`,
        );
    }

    async createNotebook(data: { title: string; description?: string; coverImage?: string; category?: string }): Promise<Notebook> {
        const response = await this.fetch<{ notebook: Notebook }>('/notebooks', {
            method: 'POST',
            body: JSON.stringify(data),
        });
        return response.notebook;
    }

    async updateNotebook(id: string, data: { title?: string; description?: string; coverImage?: string; category?: string }): Promise<Notebook> {
        const response = await this.fetch<{ notebook: Notebook }>(`/notebooks/${id}`, {
            method: 'PUT',
            body: JSON.stringify(data),
        });
        return response.notebook;
    }

    async deleteNotebook(id: string): Promise<void> {
        await this.fetch(`/notebooks/${id}`, {
            method: 'DELETE',
        });
    }

    // Sources
    async getSources(notebookId: string): Promise<Source[]> {
        const data = await this.fetch<{ sources: Source[] }>(
            `/coding-agent/memory/notebooks/${notebookId}`,
        );
        return data.sources || [];
    }

    async createSource(data: { notebookId: string; type: string; title: string; content?: string; url?: string; imageUrl?: string }): Promise<Source> {
        const response = await this.fetch<{ source: Source }>('/sources', {
            method: 'POST',
            body: JSON.stringify(data),
        });
        return response.source;
    }

    async deleteSource(id: string): Promise<void> {
        await this.fetch(`/sources/${id}`, {
            method: 'DELETE',
        });
    }



    // AI Chat
    async chatWithAI(messages: { role: string; content: string }[], provider = 'gemini', model?: string): Promise<string> {
        const response = await this.fetch<{ response: string }>('/ai/chat', {
            method: 'POST',
            body: JSON.stringify({
                messages,
                provider,
                model
            }),
        });
        return response.response;
    }

    // Helper for streaming chat
    async chatWithAIStream(
        messages: { role: string; content: string }[],
        onChunk: (chunk: string) => void,
        provider = 'gemini',
        model?: string
    ): Promise<void> {
        if (!this.token) throw new Error("Not authenticated");

        const response = await fetch(`${API_BASE}/ai/chat/stream`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.token}`,
            },
            body: JSON.stringify({
                messages,
                provider,
                model
            }),
        });

        if (!response.body) throw new Error("ReadableStream not supported");

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const chunk = decoder.decode(value, { stream: true });
            buffer += chunk;

            const lines = buffer.split('\n\n');
            buffer = lines.pop() || ""; // Keep incomplete line in buffer

            for (const line of lines) {
                const trimmedLine = line.trim();
                if (trimmedLine.startsWith('data: ')) {
                    const dataStr = trimmedLine.substring(6);
                    if (dataStr === '[DONE]') continue;

                    try {
                        const data = JSON.parse(dataStr);
                        if (data.text) {
                            onChunk(data.text);
                        } else if (data.error) {
                            console.error('SSE Error:', data.error);
                            // Optionally handle error UI here
                        }
                    } catch (e) {
                        console.error('Error parsing SSE chat data:', e);
                    }
                }
            }
        }
    }

    // Research
    async performResearchStream(
        query: string,
        config: ResearchConfig,
        onProgress: (progress: ResearchProgress) => void
    ): Promise<void> {
        if (!this.token) throw new Error("Not authenticated");

        const response = await fetch(`${API_BASE}/research/stream`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Authorization': `Bearer ${this.token}`,
            },
            body: JSON.stringify({ query, ...config }),
        });

        if (!response.body) throw new Error("ReadableStream not supported");

        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = "";

        while (true) {
            const { done, value } = await reader.read();
            if (done) break;

            const chunk = decoder.decode(value, { stream: true });
            buffer += chunk;

            const lines = buffer.split('\n\n');
            buffer = lines.pop() || ""; // Keep incomplete line in buffer

            for (const line of lines) {
                if (line.startsWith('data: ')) {
                    const jsonStr = line.substring(6);
                    try {
                        const data = JSON.parse(jsonStr);
                        onProgress(data);
                    } catch (e) {
                        console.error('Error parsing SSE data:', e);
                    }
                }
            }
        }
    }

    // Subscriptions
    async getSubscription(): Promise<Subscription> {
        const data = await this.fetch<{ subscription: Subscription }>('/subscriptions/me');
        return data.subscription;
    }

    async getCredits(): Promise<{ credits: number; consumed: number }> {
        return this.fetch('/subscriptions/credits');
    }

    async getTransactions(limit = 50): Promise<CreditTransaction[]> {
        const data = await this.fetch<{ transactions: CreditTransaction[] }>(`/subscriptions/transactions?limit=${limit}`);
        return data.transactions;
    }

    async getPlans(): Promise<any[]> {
        const data = await this.fetch<{ plans: any[] }>('/subscriptions/plans');
        return data.plans;
    }

    // Payment
    async getPaymentConfig(): Promise<any> {
        const data = await this.fetch<{ config: any }>('/subscriptions/payment-config');
        return data.config;
    }

    async createCheckoutSession(planId: string): Promise<{ sessionId: string; url: string }> {
        return this.fetch('/subscriptions/create-checkout-session', {
            method: 'POST',
            body: JSON.stringify({ planId }),
        });
    }

    async upgradePlan(planId: string, transactionId: string): Promise<{ success: boolean; newBalance: number }> {
        return this.fetch('/subscriptions/upgrade', {
            method: 'POST',
            body: JSON.stringify({ planId, transactionId }),
        });
    }

    // Analytics (if available)
    async getUsageAnalytics(): Promise<any> {
        try {
            return await this.fetch('/analytics/usage');
        } catch {
            return null;
        }
    }

    // MCP / API Tokens
    async getApiTokens(): Promise<ApiToken[]> {
        const data = await this.fetch<{ tokens: ApiToken[]; count: number; maxTokens: number }>('/auth/tokens');
        return data.tokens;
    }

    async createApiToken(name: string, expiresAt?: string): Promise<{ token: string; tokenRecord: ApiToken }> {
        return this.fetch('/auth/tokens', {
            method: 'POST',
            body: JSON.stringify({ name, expiresAt }),
        });
    }

    async revokeApiToken(tokenId: string): Promise<{ success: boolean }> {
        return this.fetch(`/auth/tokens/${tokenId}`, {
            method: 'DELETE',
        });
    }

    async getTokenUsage(tokenId: string, limit = 100): Promise<TokenUsageLog[]> {
        const data = await this.fetch<{ logs: TokenUsageLog[] }>(`/auth/tokens/${tokenId}/usage?limit=${limit}`);
        return data.logs;
    }

    async getMcpStats(): Promise<McpStats> {
        const data = await this.fetch<{ stats: McpStats }>('/auth/mcp/stats');
        return data.stats;
    }

    async getMcpUsage(limit = 50): Promise<McpUsageEntry[]> {
        const data = await this.fetch<{ usage: McpUsageEntry[] }>(`/auth/mcp/usage?limit=${limit}`);
        return data.usage;
    }

    async getVerifiedSources(notebookId?: string, language?: string): Promise<VerifiedSource[]> {
        let url = '/coding-agent/sources';
        const params = new URLSearchParams();
        if (notebookId) params.append('notebookId', notebookId);
        if (language) params.append('language', language);
        if (params.toString()) url += `?${params.toString()}`;

        const data = await this.fetch<{ sources: VerifiedSource[] }>(url);
        return data.sources;
    }

    async getAgentNotebooks(): Promise<AgentNotebook[]> {
        try {
            const data = await this.fetch<{ notebooks: AgentNotebook[] }>('/coding-agent/notebooks');
            if (data && Array.isArray(data.notebooks) && data.notebooks.length > 0) {
                return data.notebooks;
            }
        } catch (e) {
            console.warn('[API] Agent notebooks fetch failed, falling back to memory notebooks:', e);
        }

        try {
            const data = await this.fetch<{ notebooks: AgentNotebook[] }>('/coding-agent/memory/notebooks');
            return (data.notebooks || []).filter((nb: any) => nb.isAgentNotebook || nb.session);
        } catch (e) {
            console.error('[API] Fallback agent notebooks fetch failed:', e);
            return [];
        }
    }

    async getAgentTopicAccess(): Promise<TopicAccessMatrix> {
        const data = await this.fetch<{ success: boolean } & TopicAccessMatrix>(
            '/coding-agent/memory/topic-access',
        );
        return {
            agents: data.agents,
            topics: data.topics,
            grants: data.grants,
        };
    }

    async updateAgentTopicAccess(
        agentSessionId: string,
        notebookIds: string[],
    ): Promise<void> {
        await this.fetch(
            `/coding-agent/memory/sessions/${encodeURIComponent(agentSessionId)}/topics`,
            {
                method: 'PUT',
                body: JSON.stringify({ notebookIds }),
            },
        );
    }

    async getMcpQuota(): Promise<McpQuota> {
        const data = await this.fetch<{ quota: McpQuota }>('/coding-agent/quota');
        return data.quota;
    }

    // MCP User Settings
    async getMcpSettings(): Promise<McpUserSettings> {
        const data = await this.fetch<{ settings: McpUserSettings }>('/coding-agent/settings');
        return data.settings;
    }

    async updateMcpSettings(settings: { codeAnalysisModelId?: string | null; codeAnalysisEnabled?: boolean }): Promise<McpUserSettings> {
        const data = await this.fetch<{ settings: McpUserSettings }>('/coding-agent/settings', {
            method: 'PUT',
            body: JSON.stringify(settings),
        });
        return data.settings;
    }

    async getAIModels(): Promise<AIModelOption[]> {
        const data = await this.fetch<{ models: AIModelOption[] }>('/coding-agent/models');
        return data.models;
    }

}

export const api = new ApiService();
export default api;
