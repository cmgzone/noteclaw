import { useState, useEffect } from 'react';
import api from '../lib/api';
import { Plus, Edit2, Trash2, Bot, Loader2, RefreshCw } from 'lucide-react';

export default function AIModels() {
    const [models, setModels] = useState([]);
    const [loading, setLoading] = useState(true);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [editingModel, setEditingModel] = useState(null);
    const [saving, setSaving] = useState(false);
    const [syncingAlibaba, setSyncingAlibaba] = useState(false);

    const [formData, setFormData] = useState({
        name: '',
        model_id: '',
        provider: 'gemini',
        description: '',
        cost_input: 0,
        cost_output: 0,
        context_window: 0,
        is_active: true,
        is_premium: false
    });

    const providers = ['gemini', 'openrouter', 'openai', 'anthropic', 'alibaba_token_plan'];

    useEffect(() => {
        fetchModels();
    }, []);

    async function fetchModels() {
        try {
            const response = await api.getAIModels();
            setModels(response.models || []);
        } catch (error) {
            console.error('Failed to fetch models:', error);
            alert('Failed to load models');
        } finally {
            setLoading(false);
        }
    }

    function handleOpenModal(model = null) {
        if (model) {
            setEditingModel(model);
            setFormData({
                name: model.name,
                model_id: model.model_id,
                provider: model.provider,
                description: model.description || '',
                cost_input: parseFloat(model.cost_input) || 0,
                cost_output: parseFloat(model.cost_output) || 0,
                context_window: parseInt(model.context_window) || 0,
                is_active: model.is_active,
                is_premium: model.is_premium
            });
        } else {
            setEditingModel(null);
            setFormData({
                name: '',
                model_id: '',
                provider: 'gemini',
                description: '',
                cost_input: 0,
                cost_output: 0,
                context_window: 0,
                is_active: true,
                is_premium: false
            });
        }
        setIsModalOpen(true);
    }

    async function handleSave(e) {
        e.preventDefault();
        setSaving(true);

        try {
            if (editingModel) {
                await api.updateAIModel(editingModel.id, formData);
            } else {
                await api.createAIModel(formData);
            }
            await fetchModels();
            setIsModalOpen(false);
        } catch (error) {
            console.error('Failed to save model:', error);
            alert('Failed to save model: ' + error.message);
        } finally {
            setSaving(false);
        }
    }

    async function handleDelete(id) {
        if (!confirm('Are you sure you want to delete this model?')) return;

        try {
            await api.deleteAIModel(id);
            fetchModels();
        } catch (error) {
            console.error('Failed to delete model:', error);
            alert('Failed to delete model');
        }
    }

    async function handleSetDefault(id) {
        try {
            await api.setDefaultAIModel(id);
            await fetchModels();
            alert('Default model updated successfully');
        } catch (error) {
            console.error('Failed to set default model:', error);
            alert('Failed to set default model: ' + error.message);
        }
    }

    async function handleSyncAlibaba() {
        setSyncingAlibaba(true);
        try {
            const response = await api.syncAlibabaTokenPlanModels();
            await fetchModels();
            alert(`Synchronized ${response.modelCount} Alibaba Token Plan models.`);
        } catch (error) {
            console.error('Failed to sync Alibaba models:', error);
            alert('Failed to sync Alibaba models: ' + error.message);
        } finally {
            setSyncingAlibaba(false);
        }
    }

    if (loading) return (
        <div className="p-8 flex items-center justify-center">
            <Loader2 className="h-8 w-8 animate-spin" />
        </div>
    );

    return (
        <div className="p-8">
            <div className="sm:flex sm:items-center mb-8">
                <div className="sm:flex-auto">
                    <h1 className="text-2xl font-semibold">AI Models</h1>
                    <p className="mt-2 text-sm text-muted-foreground">
                        Manage available AI models for the application.
                    </p>
                </div>
                <div className="mt-4 sm:ml-16 sm:mt-0 sm:flex-none flex gap-2">
                    <button
                        type="button"
                        onClick={handleSyncAlibaba}
                        disabled={syncingAlibaba}
                        className="inline-flex items-center justify-center rounded-md bg-secondary px-3 py-2 text-sm font-semibold shadow-sm hover:bg-secondary/80 disabled:opacity-50"
                    >
                        <RefreshCw className={`mr-2 h-4 w-4 ${syncingAlibaba ? 'animate-spin' : ''}`} />
                        Sync Alibaba
                    </button>
                    <button
                        type="button"
                        onClick={() => handleOpenModal()}
                        className="inline-flex items-center justify-center rounded-md bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground shadow-sm hover:bg-primary/90"
                    >
                        <Plus className="mr-2 h-4 w-4" />
                        Add Model
                    </button>
                </div>
            </div>

            <div className="overflow-hidden shadow ring-1 ring-black ring-opacity-5 rounded-lg">
                <table className="min-w-full divide-y divide-border">
                    <thead className="bg-muted/50">
                        <tr>
                            <th className="py-3.5 pl-4 pr-3 text-left text-sm font-semibold">Name</th>
                            <th className="px-3 py-3.5 text-left text-sm font-semibold">Model ID</th>
                            <th className="px-3 py-3.5 text-left text-sm font-semibold">Provider</th>
                            <th className="px-3 py-3.5 text-left text-sm font-semibold">Context</th>
                            <th className="px-3 py-3.5 text-left text-sm font-semibold">Cost (In/Out)</th>
                            <th className="px-3 py-3.5 text-left text-sm font-semibold">Status</th>
                            <th className="relative py-3.5 pl-3 pr-4">
                                <span className="sr-only">Actions</span>
                            </th>
                        </tr>
                    </thead>
                    <tbody className="divide-y divide-border bg-card">
                        {models.map((model) => (
                            <tr key={model.id}>
                                <td className="whitespace-nowrap py-4 pl-4 pr-3 text-sm font-medium">
                                    <div className="flex items-center">
                                        <Bot className="mr-2 h-5 w-5 text-muted-foreground" />
                                        {model.name}
                                        {model.is_default && (
                                            <span className="ml-2 inline-flex items-center rounded-md bg-blue-50 px-2 py-1 text-xs font-medium text-blue-700 ring-1 ring-inset ring-blue-600/20">
                                                Default
                                            </span>
                                        )}
                                        {model.is_premium && (
                                            <span className="ml-2 inline-flex items-center rounded-md bg-amber-50 px-2 py-1 text-xs font-medium text-amber-700 ring-1 ring-inset ring-amber-600/20">
                                                Premium
                                            </span>
                                        )}
                                    </div>
                                </td>
                                <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground">{model.model_id}</td>
                                <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground capitalize">{model.provider}</td>
                                <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground">
                                    {parseInt(model.context_window || 0).toLocaleString()} tok
                                </td>
                                <td className="whitespace-nowrap px-3 py-4 text-sm text-muted-foreground">
                                    ${parseFloat(model.cost_input || 0).toFixed(4)} / ${parseFloat(model.cost_output || 0).toFixed(4)}
                                </td>
                                <td className="whitespace-nowrap px-3 py-4 text-sm">
                                    {model.is_active ? (
                                        <span className="inline-flex items-center rounded-md bg-green-50 px-2 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20">
                                            Active
                                        </span>
                                    ) : (
                                        <span className="inline-flex items-center rounded-md bg-red-50 px-2 py-1 text-xs font-medium text-red-700 ring-1 ring-inset ring-red-600/20">
                                            Inactive
                                        </span>
                                    )}
                                </td>
                                <td className="relative whitespace-nowrap py-4 pl-3 pr-4 text-right text-sm font-medium">
                                    {!model.is_default && model.is_active && (
                                        <button 
                                            onClick={() => handleSetDefault(model.id)} 
                                            className="text-blue-600 hover:text-blue-800 mr-4"
                                            title="Set as default"
                                        >
                                            Set Default
                                        </button>
                                    )}
                                    <button onClick={() => handleOpenModal(model)} className="text-primary hover:text-primary/80 mr-4">
                                        <Edit2 className="h-4 w-4" />
                                    </button>
                                    <button onClick={() => handleDelete(model.id)} className="text-destructive hover:text-destructive/80">
                                        <Trash2 className="h-4 w-4" />
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>

            {/* Modal */}
            {isModalOpen && (
                <div className="fixed inset-0 z-10 overflow-y-auto">
                    <div className="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
                        <div className="fixed inset-0 bg-black/50 transition-opacity" onClick={() => setIsModalOpen(false)} />
                        <div className="relative transform overflow-hidden rounded-lg bg-card px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6">
                            <h3 className="text-base font-semibold mb-4">
                                {editingModel ? 'Edit AI Model' : 'Add New AI Model'}
                            </h3>

                            <form onSubmit={handleSave} className="space-y-4">
                                <div>
                                    <label className="block text-sm font-medium mb-1">Display Name</label>
                                    <input
                                        type="text"
                                        required
                                        value={formData.name}
                                        onChange={e => setFormData({ ...formData, name: e.target.value })}
                                        className="block w-full rounded-md border border-border p-2"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium mb-1">Model ID (API)</label>
                                    <input
                                        type="text"
                                        required
                                        value={formData.model_id}
                                        onChange={e => setFormData({ ...formData, model_id: e.target.value })}
                                        placeholder="e.g. gemini-2.0-flash"
                                        className="block w-full rounded-md border border-border p-2"
                                    />
                                </div>

                                <div>
                                    <label className="block text-sm font-medium mb-1">Provider</label>
                                    <select
                                        value={formData.provider}
                                        onChange={e => setFormData({ ...formData, provider: e.target.value })}
                                        className="block w-full rounded-md border border-border p-2"
                                    >
                                        {providers.map(p => (
                                            <option key={p} value={p}>{p}</option>
                                        ))}
                                    </select>
                                </div>

                                <div>
                                    <label className="block text-sm font-medium mb-1">Context Window (tokens)</label>
                                    <input
                                        type="number"
                                        value={formData.context_window}
                                        onChange={e => setFormData({ ...formData, context_window: parseInt(e.target.value) || 0 })}
                                        className="block w-full rounded-md border border-border p-2"
                                    />
                                    <div className="flex gap-2 mt-2 flex-wrap">
                                        {[128000, 200000, 1000000, 2000000].map(size => (
                                            <button
                                                key={size}
                                                type="button"
                                                onClick={() => setFormData({ ...formData, context_window: size })}
                                                className="px-2 py-1 text-xs bg-muted hover:bg-muted/80 rounded border"
                                            >
                                                {(size / 1000) + 'K'}
                                            </button>
                                        ))}
                                    </div>
                                </div>

                                <div className="grid grid-cols-2 gap-4">
                                    <div>
                                        <label className="block text-sm font-medium mb-1">Input Cost ($/1k)</label>
                                        <input
                                            type="number"
                                            step="0.000001"
                                            value={formData.cost_input}
                                            onChange={e => setFormData({ ...formData, cost_input: e.target.value })}
                                            className="block w-full rounded-md border border-border p-2"
                                        />
                                    </div>
                                    <div>
                                        <label className="block text-sm font-medium mb-1">Output Cost ($/1k)</label>
                                        <input
                                            type="number"
                                            step="0.000001"
                                            value={formData.cost_output}
                                            onChange={e => setFormData({ ...formData, cost_output: e.target.value })}
                                            className="block w-full rounded-md border border-border p-2"
                                        />
                                    </div>
                                </div>

                                <div className="flex items-center space-x-4 pt-2">
                                    <label className="flex items-center space-x-2">
                                        <input
                                            type="checkbox"
                                            checked={formData.is_premium}
                                            onChange={e => setFormData({ ...formData, is_premium: e.target.checked })}
                                            className="h-4 w-4 rounded border-border"
                                        />
                                        <span className="text-sm">Premium Only</span>
                                    </label>
                                    <label className="flex items-center space-x-2">
                                        <input
                                            type="checkbox"
                                            checked={formData.is_active}
                                            onChange={e => setFormData({ ...formData, is_active: e.target.checked })}
                                            className="h-4 w-4 rounded border-border"
                                        />
                                        <span className="text-sm">Active</span>
                                    </label>
                                </div>

                                <div className="mt-5 sm:mt-6 sm:grid sm:grid-flow-row-dense sm:grid-cols-2 sm:gap-3">
                                    <button
                                        type="submit"
                                        disabled={saving}
                                        className="inline-flex w-full justify-center rounded-md bg-primary px-3 py-2 text-sm font-semibold text-primary-foreground shadow-sm hover:bg-primary/90 sm:col-start-2"
                                    >
                                        {saving ? <Loader2 className="animate-spin h-5 w-5" /> : 'Save'}
                                    </button>
                                    <button
                                        type="button"
                                        onClick={() => setIsModalOpen(false)}
                                        className="mt-3 inline-flex w-full justify-center rounded-md bg-secondary px-3 py-2 text-sm font-semibold shadow-sm hover:bg-secondary/80 sm:col-start-1 sm:mt-0"
                                    >
                                        Cancel
                                    </button>
                                </div>
                            </form>
                        </div>
                    </div>
                </div>
            )}
        </div>
    );
}
