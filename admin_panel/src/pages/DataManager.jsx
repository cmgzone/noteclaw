import { useEffect, useState } from 'react';
import api from '../lib/api';
import {
    BookOpen,
    ListTodo,
    Loader2,
    RefreshCw,
    Search,
    Trash2,
} from 'lucide-react';

function formatBulkDeleteMessage(entityLabel, result) {
    const summary = result?.summary || {};
    const deletedCount = summary.deleted || 0;
    const skippedCount = summary.skipped || 0;
    const failedCount = summary.failed || 0;
    const details = [...(result?.skipped || []), ...(result?.failed || [])]
        .slice(0, 3)
        .map((item) => `${item.id}: ${item.error}`);

    const lines = [`Deleted ${deletedCount} ${entityLabel}.`];
    if (skippedCount > 0) {
        lines.push(`Skipped ${skippedCount}.`);
    }
    if (failedCount > 0) {
        lines.push(`Failed ${failedCount}.`);
    }
    if (details.length > 0) {
        lines.push('', 'Details:', ...details);
    }

    return lines.join('\n');
}

export default function DataManager() {
    const [searchTerm, setSearchTerm] = useState('');
    const [notebooks, setNotebooks] = useState([]);
    const [plans, setPlans] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState('');
    const [selectedNotebookIds, setSelectedNotebookIds] = useState([]);
    const [selectedPlanIds, setSelectedPlanIds] = useState([]);
    const [bulkDeletingNotebooks, setBulkDeletingNotebooks] = useState(false);
    const [bulkDeletingPlans, setBulkDeletingPlans] = useState(false);

    useEffect(() => {
        const timeoutId = setTimeout(() => {
            loadData(searchTerm);
        }, 250);

        return () => clearTimeout(timeoutId);
    }, [searchTerm]);

    const loadData = async (search = '') => {
        try {
            setLoading(true);
            setError('');
            const [notebooksResponse, plansResponse] = await Promise.all([
                api.getAdminNotebooks(100, 0, search),
                api.getAdminPlans(100, 0, search),
            ]);

            const nextNotebooks = notebooksResponse.notebooks || [];
            const nextPlans = plansResponse.plans || [];
            const nextNotebookIds = new Set(nextNotebooks.map((notebook) => notebook.id));
            const nextPlanIds = new Set(nextPlans.map((plan) => plan.id));

            setNotebooks(nextNotebooks);
            setPlans(nextPlans);
            setSelectedNotebookIds((current) => current.filter((id) => nextNotebookIds.has(id)));
            setSelectedPlanIds((current) => current.filter((id) => nextPlanIds.has(id)));
        } catch (err) {
            setError(err.message || 'Failed to load content');
        } finally {
            setLoading(false);
        }
    };

    const deleteNotebook = async (notebook) => {
        const confirmed = confirm(
            `Delete notebook "${notebook.title}" owned by ${notebook.user_email}?\n\nThis also removes its sources and related notebook data.`,
        );
        if (!confirmed) return;

        try {
            await api.deleteAdminNotebook(notebook.id);
            await loadData(searchTerm);
        } catch (err) {
            alert('Failed to delete notebook: ' + err.message);
        }
    };

    const deletePlan = async (plan) => {
        const confirmed = confirm(
            `Delete plan "${plan.title}" owned by ${plan.user_email}?\n\nThis also removes its tasks and related planning records.`,
        );
        if (!confirmed) return;

        try {
            await api.deleteAdminPlan(plan.id);
            await loadData(searchTerm);
        } catch (err) {
            alert('Failed to delete plan: ' + err.message);
        }
    };

    const allNotebooksSelected = notebooks.length > 0
        && notebooks.every((notebook) => selectedNotebookIds.includes(notebook.id));

    const allPlansSelected = plans.length > 0
        && plans.every((plan) => selectedPlanIds.includes(plan.id));

    const toggleNotebookSelection = (notebookId) => {
        setSelectedNotebookIds((current) => (
            current.includes(notebookId)
                ? current.filter((id) => id !== notebookId)
                : [...current, notebookId]
        ));
    };

    const togglePlanSelection = (planId) => {
        setSelectedPlanIds((current) => (
            current.includes(planId)
                ? current.filter((id) => id !== planId)
                : [...current, planId]
        ));
    };

    const toggleAllNotebooks = () => {
        if (allNotebooksSelected) {
            setSelectedNotebookIds([]);
            return;
        }
        setSelectedNotebookIds(notebooks.map((notebook) => notebook.id));
    };

    const toggleAllPlans = () => {
        if (allPlansSelected) {
            setSelectedPlanIds([]);
            return;
        }
        setSelectedPlanIds(plans.map((plan) => plan.id));
    };

    const bulkDeleteNotebooks = async () => {
        if (selectedNotebookIds.length === 0) {
            return;
        }

        const confirmed = confirm(
            `Delete ${selectedNotebookIds.length} selected notebooks?\n\nThis also removes notebook sources and notebook-scoped data.`,
        );
        if (!confirmed) return;

        try {
            setBulkDeletingNotebooks(true);
            const result = await api.bulkDeleteAdminNotebooks(selectedNotebookIds);
            setSelectedNotebookIds([]);
            await loadData(searchTerm);
            alert(formatBulkDeleteMessage('notebooks', result));
        } catch (err) {
            alert('Failed to bulk delete notebooks: ' + err.message);
        } finally {
            setBulkDeletingNotebooks(false);
        }
    };

    const bulkDeletePlans = async () => {
        if (selectedPlanIds.length === 0) {
            return;
        }

        const confirmed = confirm(
            `Delete ${selectedPlanIds.length} selected plans?\n\nThis also removes plan tasks and related planning records.`,
        );
        if (!confirmed) return;

        try {
            setBulkDeletingPlans(true);
            const result = await api.bulkDeleteAdminPlans(selectedPlanIds);
            setSelectedPlanIds([]);
            await loadData(searchTerm);
            alert(formatBulkDeleteMessage('plans', result));
        } catch (err) {
            alert('Failed to bulk delete plans: ' + err.message);
        } finally {
            setBulkDeletingPlans(false);
        }
    };

    return (
        <div className="p-8 space-y-8">
            <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
                <div>
                    <h1 className="text-3xl font-bold mb-2">Content & Data</h1>
                    <p className="text-muted-foreground">
                        Delete user notebooks and planning data from one place.
                    </p>
                </div>
                <button
                    onClick={() => loadData(searchTerm)}
                    className="inline-flex items-center justify-center rounded-md bg-secondary px-4 py-2 text-sm font-medium hover:bg-secondary/80"
                >
                    <RefreshCw className="mr-2 h-4 w-4" />
                    Refresh
                </button>
            </div>

            <div className="relative">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <input
                    type="text"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    placeholder="Search by title, description, or owner email"
                    className="w-full rounded-lg border border-border bg-background py-2 pl-10 pr-4"
                />
            </div>

            {loading ? (
                <div className="flex items-center justify-center h-64">
                    <Loader2 className="h-10 w-10 animate-spin text-primary" />
                </div>
            ) : error ? (
                <div className="rounded-lg border border-destructive bg-destructive/10 p-4 text-destructive">
                    {error}
                </div>
            ) : (
                <>
                    <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
                        <div className="rounded-lg border border-border bg-card p-5">
                            <div className="flex items-center gap-3">
                                <BookOpen className="h-8 w-8 text-primary" />
                                <div>
                                    <div className="text-sm text-muted-foreground">Loaded Notebooks</div>
                                    <div className="text-2xl font-bold">{notebooks.length}</div>
                                </div>
                            </div>
                        </div>
                        <div className="rounded-lg border border-border bg-card p-5">
                            <div className="flex items-center gap-3">
                                <ListTodo className="h-8 w-8 text-primary" />
                                <div>
                                    <div className="text-sm text-muted-foreground">Loaded Plans</div>
                                    <div className="text-2xl font-bold">{plans.length}</div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <section className="rounded-lg border border-border bg-card overflow-hidden">
                        <div className="flex flex-col gap-4 border-b border-border px-6 py-4 md:flex-row md:items-center md:justify-between">
                            <div>
                                <h2 className="text-xl font-semibold">Notebooks</h2>
                                <p className="text-sm text-muted-foreground">
                                    Delete notebooks and their notebook-scoped data.
                                </p>
                            </div>
                            <div className="flex items-center gap-3">
                                <div className="text-sm text-muted-foreground">
                                    {selectedNotebookIds.length} selected
                                </div>
                                <button
                                    onClick={bulkDeleteNotebooks}
                                    disabled={selectedNotebookIds.length === 0 || bulkDeletingNotebooks}
                                    className="inline-flex items-center gap-2 rounded-md bg-destructive px-4 py-2 text-sm font-medium text-destructive-foreground hover:bg-destructive/90 disabled:cursor-not-allowed disabled:opacity-60"
                                >
                                    {bulkDeletingNotebooks ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
                                    Delete Selected
                                </button>
                            </div>
                        </div>
                        <table className="w-full">
                            <thead className="bg-muted/50">
                                <tr>
                                    <th className="p-4 text-left font-semibold w-12">
                                        <input
                                            type="checkbox"
                                            checked={allNotebooksSelected}
                                            onChange={toggleAllNotebooks}
                                            aria-label="Select all notebooks"
                                            className="h-4 w-4 rounded border-border"
                                        />
                                    </th>
                                    <th className="p-4 text-left font-semibold">Notebook</th>
                                    <th className="p-4 text-left font-semibold">Owner</th>
                                    <th className="p-4 text-left font-semibold">Sources</th>
                                    <th className="p-4 text-left font-semibold">Updated</th>
                                    <th className="p-4 text-left font-semibold">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {notebooks.map((notebook) => {
                                    const isSelected = selectedNotebookIds.includes(notebook.id);

                                    return (
                                        <tr
                                            key={notebook.id}
                                            className={`border-t border-border transition-colors ${isSelected ? 'bg-destructive/5' : ''}`}
                                        >
                                            <td className="p-4">
                                                <input
                                                    type="checkbox"
                                                    checked={isSelected}
                                                    onChange={() => toggleNotebookSelection(notebook.id)}
                                                    aria-label={`Select notebook ${notebook.title}`}
                                                    className="h-4 w-4 rounded border-border"
                                                />
                                            </td>
                                            <td className="p-4">
                                                <div className="font-medium">{notebook.title}</div>
                                                <div className="text-sm text-muted-foreground">
                                                    {notebook.category || 'General'}
                                                    {notebook.description ? ` - ${notebook.description}` : ''}
                                                </div>
                                            </td>
                                            <td className="p-4 text-sm text-muted-foreground">
                                                <div>{notebook.user_display_name || 'Unknown user'}</div>
                                                <div>{notebook.user_email}</div>
                                            </td>
                                            <td className="p-4 text-sm">{notebook.source_count || 0}</td>
                                            <td className="p-4 text-sm text-muted-foreground">
                                                {new Date(notebook.updated_at).toLocaleString()}
                                            </td>
                                            <td className="p-4">
                                                <button
                                                    onClick={() => deleteNotebook(notebook)}
                                                    className="inline-flex items-center gap-1 rounded-md bg-destructive px-3 py-2 text-sm text-destructive-foreground hover:bg-destructive/90"
                                                >
                                                    <Trash2 className="h-3.5 w-3.5" />
                                                    Delete
                                                </button>
                                            </td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                        {notebooks.length === 0 && (
                            <div className="px-6 py-10 text-center text-muted-foreground">
                                No notebooks found for the current search.
                            </div>
                        )}
                    </section>

                    <section className="rounded-lg border border-border bg-card overflow-hidden">
                        <div className="flex flex-col gap-4 border-b border-border px-6 py-4 md:flex-row md:items-center md:justify-between">
                            <div>
                                <h2 className="text-xl font-semibold">Plans</h2>
                                <p className="text-sm text-muted-foreground">
                                    Delete user-created planning plans and their tasks.
                                </p>
                            </div>
                            <div className="flex items-center gap-3">
                                <div className="text-sm text-muted-foreground">
                                    {selectedPlanIds.length} selected
                                </div>
                                <button
                                    onClick={bulkDeletePlans}
                                    disabled={selectedPlanIds.length === 0 || bulkDeletingPlans}
                                    className="inline-flex items-center gap-2 rounded-md bg-destructive px-4 py-2 text-sm font-medium text-destructive-foreground hover:bg-destructive/90 disabled:cursor-not-allowed disabled:opacity-60"
                                >
                                    {bulkDeletingPlans ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
                                    Delete Selected
                                </button>
                            </div>
                        </div>
                        <table className="w-full">
                            <thead className="bg-muted/50">
                                <tr>
                                    <th className="p-4 text-left font-semibold w-12">
                                        <input
                                            type="checkbox"
                                            checked={allPlansSelected}
                                            onChange={toggleAllPlans}
                                            aria-label="Select all plans"
                                            className="h-4 w-4 rounded border-border"
                                        />
                                    </th>
                                    <th className="p-4 text-left font-semibold">Plan</th>
                                    <th className="p-4 text-left font-semibold">Owner</th>
                                    <th className="p-4 text-left font-semibold">Status</th>
                                    <th className="p-4 text-left font-semibold">Tasks</th>
                                    <th className="p-4 text-left font-semibold">Updated</th>
                                    <th className="p-4 text-left font-semibold">Actions</th>
                                </tr>
                            </thead>
                            <tbody>
                                {plans.map((plan) => {
                                    const isSelected = selectedPlanIds.includes(plan.id);

                                    return (
                                        <tr
                                            key={plan.id}
                                            className={`border-t border-border transition-colors ${isSelected ? 'bg-destructive/5' : ''}`}
                                        >
                                            <td className="p-4">
                                                <input
                                                    type="checkbox"
                                                    checked={isSelected}
                                                    onChange={() => togglePlanSelection(plan.id)}
                                                    aria-label={`Select plan ${plan.title}`}
                                                    className="h-4 w-4 rounded border-border"
                                                />
                                            </td>
                                            <td className="p-4">
                                                <div className="font-medium">{plan.title}</div>
                                                <div className="text-sm text-muted-foreground">
                                                    {plan.description || 'No description'}
                                                </div>
                                            </td>
                                            <td className="p-4 text-sm text-muted-foreground">
                                                <div>{plan.user_display_name || 'Unknown user'}</div>
                                                <div>{plan.user_email}</div>
                                            </td>
                                            <td className="p-4 text-sm">
                                                <span className="rounded-full bg-secondary px-3 py-1 text-xs font-medium capitalize">
                                                    {plan.status}
                                                </span>
                                            </td>
                                            <td className="p-4 text-sm">{plan.task_count || 0}</td>
                                            <td className="p-4 text-sm text-muted-foreground">
                                                {new Date(plan.updated_at).toLocaleString()}
                                            </td>
                                            <td className="p-4">
                                                <button
                                                    onClick={() => deletePlan(plan)}
                                                    className="inline-flex items-center gap-1 rounded-md bg-destructive px-3 py-2 text-sm text-destructive-foreground hover:bg-destructive/90"
                                                >
                                                    <Trash2 className="h-3.5 w-3.5" />
                                                    Delete
                                                </button>
                                            </td>
                                        </tr>
                                    );
                                })}
                            </tbody>
                        </table>
                        {plans.length === 0 && (
                            <div className="px-6 py-10 text-center text-muted-foreground">
                                No plans found for the current search.
                            </div>
                        )}
                    </section>
                </>
            )}
        </div>
    );
}
