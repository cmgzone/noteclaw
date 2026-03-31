import { useEffect, useMemo, useState } from 'react';
import api from '../lib/api';
import { Users, Shield, Ban, Check, Search, Loader2, Trash2 } from 'lucide-react';

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

export default function UserManagement() {
    const [users, setUsers] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [searchTerm, setSearchTerm] = useState('');
    const [selectedUserIds, setSelectedUserIds] = useState([]);
    const [bulkDeleting, setBulkDeleting] = useState(false);

    useEffect(() => {
        loadUsers();
    }, []);

    const loadUsers = async () => {
        try {
            setLoading(true);
            setError(null);
            const response = await api.getUsers();
            const nextUsers = response.users || [];
            const nextIds = new Set(nextUsers.map((user) => user.id));
            setUsers(nextUsers);
            setSelectedUserIds((current) => current.filter((id) => nextIds.has(id)));
        } catch (err) {
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    const toggleUserRole = async (userId, currentRole) => {
        try {
            const newRole = currentRole === 'admin' ? 'user' : 'admin';
            await api.updateUserRole(userId, newRole);
            await loadUsers();
        } catch (err) {
            alert('Failed to update role: ' + err.message);
        }
    };

    const toggleUserStatus = async (userId, currentStatus) => {
        try {
            await api.updateUserStatus(userId, !currentStatus);
            await loadUsers();
        } catch (err) {
            alert('Failed to update status: ' + err.message);
        }
    };

    const deleteUser = async (user) => {
        const confirmed = confirm(
            `Delete ${user.email} and all associated data?\n\nThis removes notebooks, plans, sources, subscriptions, tokens, and related records.`,
        );
        if (!confirmed) return;

        try {
            await api.deleteUser(user.id);
            await loadUsers();
            alert('User deleted successfully.');
        } catch (err) {
            alert('Failed to delete user: ' + err.message);
        }
    };

    const filteredUsers = useMemo(() => (
        users.filter((user) =>
            user.email?.toLowerCase().includes(searchTerm.toLowerCase()) ||
            user.display_name?.toLowerCase().includes(searchTerm.toLowerCase()),
        )
    ), [searchTerm, users]);

    const allFilteredSelected = filteredUsers.length > 0
        && filteredUsers.every((user) => selectedUserIds.includes(user.id));

    const toggleUserSelection = (userId) => {
        setSelectedUserIds((current) => (
            current.includes(userId)
                ? current.filter((id) => id !== userId)
                : [...current, userId]
        ));
    };

    const toggleAllFilteredUsers = () => {
        if (allFilteredSelected) {
            const filteredIds = new Set(filteredUsers.map((user) => user.id));
            setSelectedUserIds((current) => current.filter((id) => !filteredIds.has(id)));
            return;
        }

        setSelectedUserIds((current) => {
            const next = new Set(current);
            filteredUsers.forEach((user) => next.add(user.id));
            return Array.from(next);
        });
    };

    const bulkDeleteUsers = async () => {
        if (selectedUserIds.length === 0) {
            return;
        }

        const confirmed = confirm(
            `Delete ${selectedUserIds.length} selected users and all of their associated data?\n\nAccounts that cannot be removed, such as your current admin account or the last remaining admin, will be skipped.`,
        );
        if (!confirmed) return;

        try {
            setBulkDeleting(true);
            const result = await api.bulkDeleteUsers(selectedUserIds);
            setSelectedUserIds([]);
            await loadUsers();
            alert(formatBulkDeleteMessage('users', result));
        } catch (err) {
            alert('Failed to bulk delete users: ' + err.message);
        } finally {
            setBulkDeleting(false);
        }
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center h-64">
                <Loader2 className="h-12 w-12 animate-spin text-primary" />
            </div>
        );
    }

    if (error) {
        return (
            <div className="p-8">
                <div className="bg-destructive/10 border border-destructive rounded-lg p-4">
                    <p className="text-destructive">Error: {error}</p>
                </div>
            </div>
        );
    }

    return (
        <div className="p-8">
            <div className="mb-8">
                <h1 className="text-3xl font-bold mb-2">User Management</h1>
                <p className="text-muted-foreground">Manage user accounts and permissions</p>
            </div>

            <div className="mb-6 flex flex-col gap-3 lg:flex-row lg:items-center lg:justify-between">
                <div className="relative flex-1">
                    <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-5 w-5 text-muted-foreground" />
                    <input
                        type="text"
                        placeholder="Search users..."
                        value={searchTerm}
                        onChange={(e) => setSearchTerm(e.target.value)}
                        className="w-full pl-10 pr-4 py-2 border border-border rounded-lg bg-background"
                    />
                </div>
                <div className="flex items-center gap-3">
                    <div className="text-sm text-muted-foreground">
                        {selectedUserIds.length} selected
                    </div>
                    <button
                        onClick={bulkDeleteUsers}
                        disabled={selectedUserIds.length === 0 || bulkDeleting}
                        className="inline-flex items-center gap-2 rounded-md bg-destructive px-4 py-2 text-sm font-medium text-destructive-foreground hover:bg-destructive/90 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                        {bulkDeleting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Trash2 className="h-4 w-4" />}
                        Delete Selected
                    </button>
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
                <div className="bg-card border border-border rounded-lg p-4">
                    <div className="flex items-center gap-3">
                        <Users className="h-8 w-8 text-primary" />
                        <div>
                            <p className="text-sm text-muted-foreground">Total Users</p>
                            <p className="text-2xl font-bold">{users.length}</p>
                        </div>
                    </div>
                </div>
                <div className="bg-card border border-border rounded-lg p-4">
                    <div className="flex items-center gap-3">
                        <Shield className="h-8 w-8 text-green-600" />
                        <div>
                            <p className="text-sm text-muted-foreground">Admins</p>
                            <p className="text-2xl font-bold">{users.filter((user) => user.role === 'admin').length}</p>
                        </div>
                    </div>
                </div>
                <div className="bg-card border border-border rounded-lg p-4">
                    <div className="flex items-center gap-3">
                        <Check className="h-8 w-8 text-blue-600" />
                        <div>
                            <p className="text-sm text-muted-foreground">Active</p>
                            <p className="text-2xl font-bold">{users.filter((user) => user.is_active).length}</p>
                        </div>
                    </div>
                </div>
            </div>

            <div className="bg-card border border-border rounded-lg overflow-hidden">
                <table className="w-full">
                    <thead className="bg-muted/50">
                        <tr>
                            <th className="p-4 text-left font-semibold w-12">
                                <input
                                    type="checkbox"
                                    checked={allFilteredSelected}
                                    onChange={toggleAllFilteredUsers}
                                    aria-label="Select all filtered users"
                                    className="h-4 w-4 rounded border-border"
                                />
                            </th>
                            <th className="text-left p-4 font-semibold">User</th>
                            <th className="text-left p-4 font-semibold">Email</th>
                            <th className="text-left p-4 font-semibold">Role</th>
                            <th className="text-left p-4 font-semibold">Status</th>
                            <th className="text-left p-4 font-semibold">Data</th>
                            <th className="text-left p-4 font-semibold">Created</th>
                            <th className="text-left p-4 font-semibold">Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {filteredUsers.map((user) => {
                            const isSelected = selectedUserIds.includes(user.id);

                            return (
                                <tr
                                    key={user.id}
                                    className={`border-t border-border transition-colors ${isSelected ? 'bg-destructive/5' : 'hover:bg-muted/30'}`}
                                >
                                    <td className="p-4">
                                        <input
                                            type="checkbox"
                                            checked={isSelected}
                                            onChange={() => toggleUserSelection(user.id)}
                                            aria-label={`Select ${user.email}`}
                                            className="h-4 w-4 rounded border-border"
                                        />
                                    </td>
                                    <td className="p-4">
                                        <div className="flex items-center gap-3">
                                            <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
                                                <span className="text-primary font-semibold">
                                                    {(user.display_name || user.email).charAt(0).toUpperCase()}
                                                </span>
                                            </div>
                                            <span className="font-medium">{user.display_name || 'Unknown'}</span>
                                        </div>
                                    </td>
                                    <td className="p-4 text-muted-foreground">{user.email}</td>
                                    <td className="p-4">
                                        <button
                                            onClick={() => toggleUserRole(user.id, user.role)}
                                            className={`px-3 py-1 rounded-full text-xs font-medium ${user.role === 'admin'
                                                ? 'bg-green-100 text-green-700 hover:bg-green-200'
                                                : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                                                }`}
                                        >
                                            {user.role === 'admin' ? (
                                                <span className="flex items-center gap-1">
                                                    <Shield className="h-3 w-3" />
                                                    Admin
                                                </span>
                                            ) : (
                                                'User'
                                            )}
                                        </button>
                                    </td>
                                    <td className="p-4">
                                        <button
                                            onClick={() => toggleUserStatus(user.id, user.is_active)}
                                            className={`px-3 py-1 rounded-full text-xs font-medium ${user.is_active
                                                ? 'bg-blue-100 text-blue-700 hover:bg-blue-200'
                                                : 'bg-red-100 text-red-700 hover:bg-red-200'
                                                }`}
                                        >
                                            {user.is_active ? (
                                                <span className="flex items-center gap-1">
                                                    <Check className="h-3 w-3" />
                                                    Active
                                                </span>
                                            ) : (
                                                <span className="flex items-center gap-1">
                                                    <Ban className="h-3 w-3" />
                                                    Inactive
                                                </span>
                                            )}
                                        </button>
                                    </td>
                                    <td className="p-4 text-sm text-muted-foreground">
                                        <div>{user.notebook_count || 0} notebooks</div>
                                        <div>{user.plan_count || 0} plans</div>
                                    </td>
                                    <td className="p-4 text-muted-foreground text-sm">
                                        {new Date(user.created_at).toLocaleDateString()}
                                    </td>
                                    <td className="p-4">
                                        <div className="flex gap-2">
                                            <button
                                                onClick={() => toggleUserRole(user.id, user.role)}
                                                className="text-sm text-primary hover:underline"
                                            >
                                                {user.role === 'admin' ? 'Demote' : 'Promote'}
                                            </button>
                                            <button
                                                onClick={() => deleteUser(user)}
                                                className="inline-flex items-center gap-1 text-sm text-red-600 hover:underline"
                                            >
                                                <Trash2 className="h-3.5 w-3.5" />
                                                Delete
                                            </button>
                                        </div>
                                    </td>
                                </tr>
                            );
                        })}
                    </tbody>
                </table>
            </div>

            {filteredUsers.length === 0 && (
                <div className="text-center py-12 text-muted-foreground">
                    No users found matching "{searchTerm}"
                </div>
            )}
        </div>
    );
}
