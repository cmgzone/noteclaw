import { useEffect, useState } from 'react';
import { Coins, Loader2, Save } from 'lucide-react';
import api from '../lib/api';

export default function FeatureCosts() {
    const [features, setFeatures] = useState([]);
    const [loading, setLoading] = useState(true);
    const [saving, setSaving] = useState('');

    async function load() {
        try {
            const response = await api.getFeatureCreditCosts();
            setFeatures(response.features || []);
        } catch (error) {
            alert(`Failed to load feature costs: ${error.message}`);
        } finally {
            setLoading(false);
        }
    }

    useEffect(() => { load(); }, []);

    async function save(feature) {
        setSaving(feature.key);
        try {
            await api.updateFeatureCreditCost(feature.key, Number(feature.creditCost));
            await load();
        } catch (error) {
            alert(`Failed to save cost: ${error.message}`);
        } finally {
            setSaving('');
        }
    }

    if (loading) return <div className="flex h-64 items-center justify-center"><Loader2 className="h-7 w-7 animate-spin" /></div>;

    return (
        <div className="space-y-6">
            <div>
                <h1 className="flex items-center gap-2 text-2xl font-bold"><Coins className="h-6 w-6" /> Feature Credit Costs</h1>
                <p className="mt-1 text-sm text-muted-foreground">These backend tariffs apply to Flutter, web, and MCP clients. Failed provider operations are refunded.</p>
            </div>
            <div className="overflow-hidden rounded-lg border border-border bg-card">
                <table className="min-w-full divide-y divide-border">
                    <thead className="bg-muted/50"><tr>
                        <th className="px-4 py-3 text-left text-sm font-semibold">Feature</th>
                        <th className="px-4 py-3 text-left text-sm font-semibold">Description</th>
                        <th className="px-4 py-3 text-left text-sm font-semibold">Default</th>
                        <th className="px-4 py-3 text-left text-sm font-semibold">Current cost</th>
                        <th className="px-4 py-3" />
                    </tr></thead>
                    <tbody className="divide-y divide-border">
                        {features.map((feature, index) => (
                            <tr key={feature.key}>
                                <td className="px-4 py-3"><p className="font-medium">{feature.label}</p><code className="text-xs text-muted-foreground">{feature.key}</code></td>
                                <td className="px-4 py-3 text-sm text-muted-foreground">{feature.description}</td>
                                <td className="px-4 py-3 text-sm">{feature.defaultCost}</td>
                                <td className="px-4 py-3">
                                    <input
                                        aria-label={`${feature.label} credit cost`}
                                        type="number"
                                        min="0"
                                        max="100000"
                                        step="1"
                                        value={feature.creditCost}
                                        onChange={(event) => setFeatures((current) => current.map((item, itemIndex) => itemIndex === index ? { ...item, creditCost: event.target.value } : item))}
                                        className="w-28 rounded-md border border-border bg-background px-3 py-2"
                                    />
                                </td>
                                <td className="px-4 py-3 text-right">
                                    <button onClick={() => save(feature)} disabled={saving === feature.key} className="inline-flex items-center rounded-md bg-primary px-3 py-2 text-sm text-primary-foreground disabled:opacity-50">
                                        {saving === feature.key ? <Loader2 className="mr-2 h-4 w-4 animate-spin" /> : <Save className="mr-2 h-4 w-4" />} Save
                                    </button>
                                </td>
                            </tr>
                        ))}
                    </tbody>
                </table>
            </div>
        </div>
    );
}
