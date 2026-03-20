// API Service for Admin Panel
// Uses the backend API instead of direct database access

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3001/api';

class ApiService {
    constructor() {
        this.token = localStorage.getItem('admin_token');
        this.refreshToken = localStorage.getItem('admin_refresh_token');
        this.isRefreshing = false;
    }

    setTokens(accessToken, refreshToken) {
        this.token = accessToken;
        this.refreshToken = refreshToken;
        if (accessToken) {
            localStorage.setItem('admin_token', accessToken);
        } else {
            localStorage.removeItem('admin_token');
        }
        if (refreshToken) {
            localStorage.setItem('admin_refresh_token', refreshToken);
        } else {
            localStorage.removeItem('admin_refresh_token');
        }
    }

    getToken() {
        return this.token || localStorage.getItem('admin_token');
    }

    clearTokens() {
        this.token = null;
        this.refreshToken = null;
        localStorage.removeItem('admin_token');
        localStorage.removeItem('admin_refresh_token');
    }

    async request(endpoint, options = {}) {
        const url = `${API_BASE_URL}${endpoint}`;
        const headers = {
            'Content-Type': 'application/json',
            ...options.headers,
        };

        const token = this.getToken();
        if (token) {
            headers['Authorization'] = `Bearer ${token}`;
        }

        try {
            const response = await fetch(url, {
                ...options,
                headers,
            });

            // Handle 401 Unauthorized - attempt token refresh
            if (response.status === 401 && this.refreshToken && !this.isRefreshing && !endpoint.includes('/auth/login') && !endpoint.includes('/auth/refresh')) {
                console.log('[API] Access token expired, attempting refresh...');
                const refreshed = await this.refreshTokens();
                if (refreshed) {
                    // Retry original request
                    const retryHeaders = {
                        ...headers,
                        'Authorization': `Bearer ${this.token}`
                    };
                    const retryResponse = await fetch(url, {
                        ...options,
                        headers: retryHeaders
                    });
                    if (retryResponse.ok) return await retryResponse.json();
                }
            }

            const data = await response.json();

            if (!response.ok) {
                if (response.status === 401) {
                    this.clearTokens();
                    window.location.href = '/login';
                }
                throw new Error(data.error || `Request failed: ${response.status}`);
            }

            return data;
        } catch (error) {
            console.error(`API Error [${endpoint}]:`, error);
            throw error;
        }
    }

    async refreshTokens() {
        if (!this.refreshToken) return false;
        this.isRefreshing = true;

        try {
            const response = await fetch(`${API_BASE_URL}/auth/refresh`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ refreshToken: this.refreshToken }),
            });

            if (response.ok) {
                const data = await response.json();
                if (data.accessToken) {
                    this.token = data.accessToken;
                    localStorage.setItem('admin_token', this.token);
                    console.log('[API] Token refreshed successfully');
                    return true;
                }
            } else {
                console.warn('[API] Token refresh failed, logging out');
                this.clearTokens();
                window.location.href = '/login';
            }
        } catch (e) {
            console.error('[API] Error refreshing token:', e);
        } finally {
            this.isRefreshing = false;
        }
        return false;
    }

    // GET request
    async get(endpoint) {
        return this.request(endpoint, { method: 'GET' });
    }

    // POST request
    async post(endpoint, body) {
        return this.request(endpoint, {
            method: 'POST',
            body: JSON.stringify(body),
        });
    }

    // PUT request
    async put(endpoint, body) {
        return this.request(endpoint, {
            method: 'PUT',
            body: JSON.stringify(body),
        });
    }

    // DELETE request
    async delete(endpoint) {
        return this.request(endpoint, { method: 'DELETE' });
    }

    // ============ AUTH ============
    async login(email, password) {
        const data = await this.post('/auth/login', { email, password });
        if (data.accessToken && data.refreshToken) {
            this.setTokens(data.accessToken, data.refreshToken);
        } else if (data.token) {
            // Fallback
            this.setTokens(data.token, data.refreshToken || '');
        }
        return data;
    }

    async getCurrentUser() {
        return this.get('/auth/me');
    }

    // ============ ADMIN - USERS ============
    async getUsers() {
        return this.get('/admin/users');
    }

    async updateUserRole(userId, role) {
        return this.put(`/admin/users/${userId}/role`, { role });
    }

    async updateUserStatus(userId, isActive) {
        return this.put(`/admin/users/${userId}/status`, { isActive });
    }

    // ============ ADMIN - AI MODELS ============
    async getAIModels() {
        return this.get('/admin/models');
    }

    async createAIModel(model) {
        return this.post('/admin/models', model);
    }

    async updateAIModel(id, model) {
        return this.put(`/admin/models/${id}`, model);
    }

    async deleteAIModel(id) {
        return this.delete(`/admin/models/${id}`);
    }

    async setDefaultAIModel(id) {
        return this.put(`/admin/models/${id}/set-default`, {});
    }

    async getDefaultAIModel() {
        return this.get('/admin/models/default');
    }

    // ============ ADMIN - API KEYS ============
    async getApiKeys() {
        return this.get('/admin/api-keys');
    }

    async setApiKey(service, apiKey, description) {
        return this.post('/admin/api-keys', { service, apiKey, description });
    }

    async deleteApiKey(service) {
        return this.delete(`/admin/api-keys/${service}`);
    }

    // ============ ADMIN - SUBSCRIPTION PLANS ============
    async getPlans() {
        return this.get('/admin/plans');
    }

    async updatePlan(id, updates) {
        return this.put(`/admin/plans/${id}`, updates);
    }

    async createPlan(plan) {
        return this.post('/admin/plans', plan);
    }

    async deletePlan(id) {
        return this.delete(`/admin/plans/${id}`);
    }

    // ============ ADMIN - CREDIT PACKAGES ============
    async getCreditPackages() {
        return this.get('/admin/packages');
    }

    async createCreditPackage(pkg) {
        return this.post('/admin/packages', pkg);
    }

    async updateCreditPackage(id, pkg) {
        return this.put(`/admin/packages/${id}`, pkg);
    }

    async deleteCreditPackage(id) {
        return this.delete(`/admin/packages/${id}`);
    }

    // ============ ADMIN - TRANSACTIONS ============
    async getTransactions(limit = 100) {
        return this.get(`/admin/transactions?limit=${limit}`);
    }

    // ============ ADMIN - SETTINGS ============
    async getSettings() {
        return this.get('/admin/settings');
    }

    async updateSetting(key, value) {
        return this.put('/admin/settings', { key, value });
    }

    // ============ ADMIN - ONBOARDING ============
    async getOnboardingScreens() {
        return this.get('/admin/onboarding');
    }

    async updateOnboardingScreens(screens) {
        return this.put('/admin/onboarding', { screens });
    }

    // ============ ADMIN - PRIVACY POLICY ============
    async getPrivacyPolicy() {
        return this.get('/admin/privacy-policy');
    }

    async updatePrivacyPolicy(content) {
        return this.put('/admin/privacy-policy', { content });
    }

    // ============ ADMIN - STATS ============
    async getDashboardStats() {
        return this.get('/admin/stats');
    }

    // ============ ADMIN - STORAGE / CDN ============
    async getStorageStats() {
        return this.get('/admin/storage-stats');
    }

    // ============ ADMIN - MCP SETTINGS ============
    async getMcpSettings() {
        return this.get('/admin/mcp-settings');
    }

    async updateMcpSettings(settings) {
        return this.put('/admin/mcp-settings', settings);
    }

    async getMcpUsage(limit = 50) {
        return this.get(`/admin/mcp-usage?limit=${limit}`);
    }

    async getMcpStats() {
        return this.get('/admin/mcp-stats');
    }

    async getMcpUserLimits(userId) {
        return this.get(`/admin/mcp-user-limits/${userId}`);
    }

    async updateMcpUserLimits(userId, overrides) {
        return this.put(`/admin/mcp-user-limits/${userId}`, overrides);
    }

    async clearMcpUserLimits(userId) {
        return this.delete(`/admin/mcp-user-limits/${userId}`);
    }

    // ============ ADMIN - NOTIFICATIONS ============
    async sendBroadcastNotification(notification) {
        return this.post('/admin/notifications/broadcast', notification);
    }

    async sendNotificationToUsers(notification) {
        return this.post('/admin/notifications/send', notification);
    }

    async getNotificationStats() {
        return this.get('/admin/notifications/stats');
    }
}

export const api = new ApiService();
export default api;
