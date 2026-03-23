import { useState, useEffect } from 'react';
import api from '../lib/api';
import { Plus, Edit2, Trash2, Check, X, Loader2, DollarSign, Calendar } from 'lucide-react';

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
        google_play_product_id: ''
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
            google_play_product_id: plan.google_play_product_id || ''
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
            google_play_product_id: ''
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
                            Manage subscription tiers, pricing, and Google Play product mappings
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
                                                : formData.google_play_product_id
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
                            {plan.description && (
                                <p className="text-sm text-muted-foreground">{plan.description}</p>
                            )}
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
