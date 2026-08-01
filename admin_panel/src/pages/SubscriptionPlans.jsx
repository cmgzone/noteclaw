import { useState, useEffect } from 'react';
import api from '../lib/api';
import { Plus, Edit2, Trash2, Check, X, Loader2, DollarSign, Calendar } from 'lucide-react';

const PLAN_FEATURES = [
    { key: 'memory_bank', label: 'Durable memory bank', description: 'Agent memory sessions and namespaces' },
    { key: 'notebook_chat', label: 'Notebook chat', description: 'Chat with stored agent memories' },
    { key: 'websocket_collaboration', label: 'WebSocket collaboration', description: 'Live shared sessions for multiple agents' },
    { key: 'code_review', label: 'Code review', description: 'MCP code-quality and security review' },
    { key: 'web_search', label: 'Web search', description: 'Current web results with citations' },
    { key: 'deep_research', label: 'Deep research', description: 'Background multi-step research reports' },
    { key: 'research_save_to_notebook', label: 'Save research', description: 'Store research reports in notebooks' },
    { key: 'image_generation', label: 'Image generation', description: 'Create and download AI-generated images' },
    { key: 'video_generation', label: 'Video generation', description: 'Create and download AI-generated videos' },
];

const defaultFeatureAccess = (isFreePlan = false) =>
    Object.fromEntries(PLAN_FEATURES.map(({ key }) => [key, !isFreePlan]));

const defaultQuotaLimits = (isFreePlan = false) => isFreePlan
    ? {
        notes_limit: 100,
        mcp_sources_limit: 10,
        mcp_tokens_limit: 3,
        mcp_api_calls_per_day: 100,
    }
    : {
        notes_limit: 1000,
        mcp_sources_limit: 200,
        mcp_tokens_limit: 10,
        mcp_api_calls_per_day: 2000,
    };

const normalizeFeatureAccess = (value, isFreePlan = false) => {
    const defaults = defaultFeatureAccess(isFreePlan);
    if (!value || typeof value !== 'object' || Array.isArray(value)) return defaults;
    return Object.fromEntries(
        PLAN_FEATURES.map(({ key }) => [
            key,
            typeof value[key] === 'boolean' ? value[key] : defaults[key],
        ]),
    );
};

export default function SubscriptionPlans() {
    const [plans, setPlans] = useState([]);
    const [loading, setLoading] = useState(true);
    const [editingPlan, setEditingPlan] = useState(null);
    const [showForm, setShowForm] = useState(false);

    const [formData, setFormData] = useState({
        name: '',
        description: '',
        credits_per_month: 30,
        price: 0,
        is_active: true,
        is_free_plan: false,
        google_play_product_id: '',
        feature_access: defaultFeatureAccess(false),
        ...defaultQuotaLimits(false),
    });

    useEffect(() => {
        fetchPlans();
    }, []);

    const fetchPlans = async () => {
        setLoading(true);
        try {
            const data = await api.getPlans();
            setPlans(data.plans || []);
        } catch (error) {
            console.error('Error fetching plans:', error);
            alert('Failed to fetch subscription plans');
        } finally {
            setLoading(false);
        }
    };

    const handleSubmit = async (e) => {
        e.preventDefault();
        try {
            if (editingPlan) {
                await api.updatePlan(editingPlan.id, {
                    name: formData.name,
                    description: formData.description,
                    creditsPerMonth: formData.credits_per_month,
                    price: formData.price,
                    isActive: formData.is_active,
                    isFreePlan: formData.is_free_plan,
                    featureAccess: formData.feature_access,
                    notesLimit: formData.notes_limit,
                    mcpSourcesLimit: formData.mcp_sources_limit,
                    mcpTokensLimit: formData.mcp_tokens_limit,
                    mcpApiCallsPerDay: formData.mcp_api_calls_per_day,
                    googlePlayProductId: formData.is_free_plan
                        ? null
                        : (formData.google_play_product_id?.trim() || null)
                });
            } else {
                await api.createPlan({
                    name: formData.name,
                    description: formData.description,
                    creditsPerMonth: formData.credits_per_month,
                    price: formData.price,
                    isActive: formData.is_active,
                    isFreePlan: formData.is_free_plan,
                    featureAccess: formData.feature_access,
                    notesLimit: formData.notes_limit,
                    mcpSourcesLimit: formData.mcp_sources_limit,
                    mcpTokensLimit: formData.mcp_tokens_limit,
                    mcpApiCallsPerDay: formData.mcp_api_calls_per_day,
                    googlePlayProductId: formData.is_free_plan
                        ? null
                        : (formData.google_play_product_id?.trim() || null)
                });
            }

            resetForm();
            fetchPlans();
            alert(editingPlan ? 'Plan updated successfully!' : 'Plan created successfully!');
        } catch (error) {
            console.error('Error saving plan:', error);
            alert('Failed to save plan');
        }
    };

    const handleDelete = async (id) => {
        if (!confirm('Are you sure you want to delete this plan?')) return;

        try {
            await api.deletePlan(id);
            fetchPlans();
            alert('Plan deleted successfully!');
        } catch (error) {
            console.error('Error deleting plan:', error);
            alert('Failed to delete plan. Make sure no users are subscribed to this plan.');
        }
    };

    const handleEdit = (plan) => {
        setEditingPlan(plan);
        setFormData({
            name: plan.name,
            description: plan.description || '',
            credits_per_month: plan.credits_per_month,
            price: plan.price,
            is_active: plan.is_active,
            is_free_plan: plan.is_free_plan,
            google_play_product_id: plan.google_play_product_id || '',
            feature_access: normalizeFeatureAccess(
                plan.feature_access,
                plan.is_free_plan,
            ),
            notes_limit: plan.notes_limit ?? defaultQuotaLimits(plan.is_free_plan).notes_limit,
            mcp_sources_limit: plan.mcp_sources_limit ?? defaultQuotaLimits(plan.is_free_plan).mcp_sources_limit,
            mcp_tokens_limit: plan.mcp_tokens_limit ?? defaultQuotaLimits(plan.is_free_plan).mcp_tokens_limit,
            mcp_api_calls_per_day: plan.mcp_api_calls_per_day ?? defaultQuotaLimits(plan.is_free_plan).mcp_api_calls_per_day,
        });
        setShowForm(true);
    };

    const resetForm = () => {
        setFormData({
            name: '',
            description: '',
            credits_per_month: 30,
            price: 0,
            is_active: true,
            is_free_plan: false,
            google_play_product_id: '',
            feature_access: defaultFeatureAccess(false),
            ...defaultQuotaLimits(false),
        });
        setEditingPlan(null);
        setShowForm(false);
    };

    const toggleActive = async (plan) => {
        try {
            await api.updatePlan(plan.id, { isActive: !plan.is_active });
            fetchPlans();
        } catch (error) {
            console.error('Error toggling active status:', error);
            alert('Failed to update plan status');
        }
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center h-64">
                <Loader2 className="h-8 w-8 animate-spin" />
            </div>
        );
    }

    return (
        <div className="p-8">
            <div className="mb-8">
                <div className="flex items-center justify-between">
                    <div>
                        <h1 className="text-3xl font-bold mb-2">Subscription Plans</h1>
                        <p className="text-muted-foreground">
                            Manage pricing, billing mappings, and the exact features each plan can access
                        </p>
                    </div>
                    <button
                        onClick={() => setShowForm(!showForm)}
                        className="flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
                    >
                        <Plus className="mr-2 h-4 w-4" />
                        New Plan
                    </button>
                </div>
            </div>

            {/* Form */}
            {showForm && (
                <div className="bg-card border border-border rounded-lg p-6 mb-6">
                    <h2 className="text-xl font-semibold mb-4">{editingPlan ? 'Edit Plan' : 'Create New Plan'}</h2>
                    <form onSubmit={handleSubmit} className="space-y-4">
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                            <div>
                                <label className="block text-sm font-medium mb-1">Plan Name</label>
                                <input
                                    type="text"
                                    value={formData.name}
                                    onChange={(e) => setFormData({ ...formData, name: e.target.value })}
                                    className="w-full rounded-md border border-border bg-background p-2"
                                    required
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium mb-1">Price (USD)</label>
                                <input
                                    type="number"
                                    step="0.01"
                                    value={formData.price}
                                    onChange={(e) => setFormData({ ...formData, price: parseFloat(e.target.value) })}
                                    className="w-full rounded-md border border-border bg-background p-2"
                                    required
                                />
                            </div>
                            <div>
                                <label className="block text-sm font-medium mb-1">Credits per Month</label>
                                <input
                                    type="number"
                                    value={formData.credits_per_month}
                                    onChange={(e) => setFormData({ ...formData, credits_per_month: parseInt(e.target.value) })}
                                    className="w-full rounded-md border border-border bg-background p-2"
                                    required
                                />
                            </div>
                            <div className="flex items-center gap-4 pt-6">
                                <label className="flex items-center gap-2">
                                    <input
                                        type="checkbox"
                                        checked={formData.is_active}
                                        onChange={(e) => setFormData({ ...formData, is_active: e.target.checked })}
                                        className="rounded"
                                    />
                                    <span className="text-sm">Active</span>
                                </label>
                                <label className="flex items-center gap-2">
                                    <input
                                        type="checkbox"
                                        checked={formData.is_free_plan}
                                        onChange={(e) => setFormData({
                                            ...formData,
                                            is_free_plan: e.target.checked,
                                            google_play_product_id: e.target.checked
                                                ? ''
                                                : formData.google_play_product_id,
                                            feature_access: defaultFeatureAccess(e.target.checked),
                                            ...defaultQuotaLimits(e.target.checked),
                                        })}
                                        className="rounded"
                                    />
                                    <span className="text-sm">Free Plan</span>
                                </label>
                            </div>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">Description</label>
                            <textarea
                                value={formData.description}
                                onChange={(e) => setFormData({ ...formData, description: e.target.value })}
                                className="w-full rounded-md border border-border bg-background p-2"
                                rows={3}
                            />
                        </div>
                        <div>
                            <div className="mb-3">
                                <h3 className="text-sm font-semibold">Plan quotas</h3>
                                <p className="text-xs text-muted-foreground">
                                    These limits are enforced by the backend and shown to users in the Flutter subscription screen.
                                </p>
                            </div>
                            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
                                {[
                                    ['notes_limit', 'Memory notes', 'Maximum notes stored'],
                                    ['mcp_sources_limit', 'MCP sources', 'Maximum connected sources'],
                                    ['mcp_tokens_limit', 'Agent tokens', 'Maximum active MCP tokens'],
                                    ['mcp_api_calls_per_day', 'Tool calls / day', 'Daily MCP request limit'],
                                ].map(([key, label, help]) => (
                                    <div key={key}>
                                        <label className="block text-sm font-medium mb-1">{label}</label>
                                        <input
                                            type="number"
                                            min="0"
                                            step="1"
                                            value={formData[key]}
                                            onChange={(event) => setFormData({
                                                ...formData,
                                                [key]: Math.max(0, parseInt(event.target.value, 10) || 0),
                                            })}
                                            className="w-full rounded-md border border-border bg-background p-2"
                                            required
                                        />
                                        <p className="mt-1 text-xs text-muted-foreground">{help}</p>
                                    </div>
                                ))}
                            </div>
                        </div>
                        <div>
                            <div className="mb-3">
                                <h3 className="text-sm font-semibold">Feature access</h3>
                                <p className="text-xs text-muted-foreground">
                                    These switches are enforced by the web app, Flutter app, MCP routes, and WebSocket connection.
                                </p>
                            </div>
                            <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
                                {PLAN_FEATURES.map((feature) => {
                                    const enabled = formData.feature_access?.[feature.key] === true;
                                    return (
                                        <label
                                            key={feature.key}
                                            className={`flex cursor-pointer items-start gap-3 rounded-lg border p-3 transition ${
                                                enabled
                                                    ? 'border-primary/50 bg-primary/5'
                                                    : 'border-border bg-background'
                                            }`}
                                        >
                                            <input
                                                type="checkbox"
                                                checked={enabled}
                                                onChange={(event) => setFormData({
                                                    ...formData,
                                                    feature_access: {
                                                        ...formData.feature_access,
                                                        [feature.key]: event.target.checked,
                                                    },
                                                })}
                                                className="mt-1 rounded"
                                            />
                                            <span>
                                                <span className="block text-sm font-medium">{feature.label}</span>
                                                <span className="block text-xs text-muted-foreground">
                                                    {feature.description}
                                                </span>
                                            </span>
                                        </label>
                                    );
                                })}
                            </div>
                        </div>
                        <div>
                            <label className="block text-sm font-medium mb-1">Google Play Product ID</label>
                            <input
                                type="text"
                                value={formData.google_play_product_id}
                                onChange={(e) => setFormData({ ...formData, google_play_product_id: e.target.value })}
                                className="w-full rounded-md border border-border bg-background p-2 font-mono text-sm"
                                placeholder={formData.is_free_plan ? 'Leave blank for free plan' : 'noteclaw_pro_monthly'}
                                disabled={formData.is_free_plan}
                            />
                            <p className="mt-1 text-xs text-muted-foreground">
                                {formData.is_free_plan
                                    ? 'Free plans do not need a Google Play product.'
                                    : 'Must match the subscription product ID created in Google Play Console.'}
                            </p>
                        </div>
                        <div className="flex gap-2">
                            <button
                                type="submit"
                                className="flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground hover:bg-primary/90"
                            >
                                {editingPlan ? 'Update Plan' : 'Create Plan'}
                            </button>
                            <button
                                type="button"
                                onClick={resetForm}
                                className="rounded-md bg-secondary px-4 py-2 text-sm font-medium hover:bg-secondary/80"
                            >
                                Cancel
                            </button>
                        </div>
                    </form>
                </div>
            )}

            {/* Plans Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {plans.map((plan) => (
                    <div
                        key={plan.id}
                        className={`bg-card border-2 rounded-lg p-6 relative ${plan.is_free_plan ? 'border-green-500' : 'border-border'
                            } ${!plan.is_active ? 'opacity-60' : ''}`}
                    >
                        {plan.is_free_plan && (
                            <div className="absolute -top-3 left-4 bg-green-500 text-white px-3 py-1 rounded-full text-xs font-semibold">
                                FREE PLAN
                            </div>
                        )}
                        {!plan.is_active && (
                            <div className="absolute -top-3 right-4 bg-red-500 text-white px-3 py-1 rounded-full text-xs font-semibold">
                                INACTIVE
                            </div>
                        )}

                        <div className="mb-4">
                            <h3 className="text-xl font-bold mb-2">{plan.name}</h3>
                            <div className="flex items-baseline gap-1 mb-3">
                                <span className="text-3xl font-bold">${plan.price}</span>
                                <span className="text-muted-foreground">/month</span>
                            </div>
                            <div className="flex items-center gap-2 text-sm text-muted-foreground mb-2">
                                <Calendar className="h-4 w-4" />
                                <span>{plan.credits_per_month} credits/month</span>
                            </div>
                            <div className="grid grid-cols-2 gap-2 text-xs text-muted-foreground">
                                <span>{plan.notes_limit ?? 'Unlimited'} notes</span>
                                <span>{plan.mcp_sources_limit ?? 'Unlimited'} sources</span>
                                <span>{plan.mcp_tokens_limit ?? 'Unlimited'} tokens</span>
                                <span>{plan.mcp_api_calls_per_day ?? 'Unlimited'} calls/day</span>
                            </div>
                            {plan.description && (
                                <p className="text-sm text-muted-foreground">{plan.description}</p>
                            )}
                            <div className="mt-4">
                                <div className="mb-2 text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                                    Enabled features
                                </div>
                                <div className="flex flex-wrap gap-1.5">
                                    {PLAN_FEATURES.filter(
                                        ({ key }) => normalizeFeatureAccess(
                                            plan.feature_access,
                                            plan.is_free_plan,
                                        )[key],
                                    ).map((feature) => (
                                        <span
                                            key={feature.key}
                                            className="rounded-full border border-primary/20 bg-primary/5 px-2 py-1 text-[11px] text-primary"
                                        >
                                            {feature.label}
                                        </span>
                                    ))}
                                    {PLAN_FEATURES.every(
                                        ({ key }) => !normalizeFeatureAccess(
                                            plan.feature_access,
                                            plan.is_free_plan,
                                        )[key],
                                    ) && (
                                        <span className="text-xs text-muted-foreground">
                                            Subscription management only
                                        </span>
                                    )}
                                </div>
                            </div>
                            <div className="mt-3 space-y-1">
                                {plan.google_play_product_id ? (
                                    <div className="rounded-md bg-secondary/60 px-3 py-2">
                                        <div className="text-[11px] uppercase tracking-wide text-muted-foreground">
                                            Google Play Product
                                        </div>
                                        <div className="font-mono text-sm">{plan.google_play_product_id}</div>
                                    </div>
                                ) : !plan.is_free_plan ? (
                                    <div className="rounded-md border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-700 dark:text-amber-300">
                                        No Google Play product ID mapped yet. Android billing will not match this paid plan until you add one.
                                    </div>
                                ) : null}
                            </div>
                        </div>

                        <div className="flex gap-2 pt-4 border-t border-border">
                            <button
                                onClick={() => handleEdit(plan)}
                                className="flex-1 flex items-center justify-center gap-1 rounded-md bg-secondary px-3 py-2 text-sm hover:bg-secondary/80"
                            >
                                <Edit2 className="h-3 w-3" />
                                Edit
                            </button>
                            <button
                                onClick={() => toggleActive(plan)}
                                className="flex-1 flex items-center justify-center gap-1 rounded-md bg-secondary px-3 py-2 text-sm hover:bg-secondary/80"
                            >
                                {plan.is_active ? <X className="h-3 w-3" /> : <Check className="h-3 w-3" />}
                                {plan.is_active ? 'Deactivate' : 'Activate'}
                            </button>
                            <button
                                onClick={() => handleDelete(plan.id)}
                                className="rounded-md bg-destructive px-3 py-2 text-sm text-destructive-foreground hover:bg-destructive/90"
                            >
                                <Trash2 className="h-3 w-3" />
                            </button>
                        </div>
                    </div>
                ))}
            </div>

            {plans.length === 0 && (
                <div className="text-center py-12 text-muted-foreground">
                    No subscription plans found. Create your first plan!
                </div>
            )}
        </div>
    );
}
