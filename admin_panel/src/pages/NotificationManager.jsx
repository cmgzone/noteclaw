import { useState, useEffect } from 'react';
import api from '../lib/api';
import { Bell, Send, Users, MessageSquare, AlertCircle, CheckCircle, TrendingUp } from 'lucide-react';

const createDefaultNotification = () => ({
    title: '',
    body: '',
    type: 'system',
    actionUrl: '',
    showPopup: true,
    actionLabel: ''
});

export default function NotificationManager() {
    const [stats, setStats] = useState({
        total_notifications: 0,
        unread_notifications: 0,
        system_notifications: 0,
        notifications_24h: 0,
        notifications_7d: 0,
        typeBreakdown: []
    });
    const [users, setUsers] = useState([]);
    const [selectedUsers, setSelectedUsers] = useState([]);
    const [notification, setNotification] = useState(createDefaultNotification);
    const [loading, setLoading] = useState(true);
    const [sending, setSending] = useState(false);
    const [message, setMessage] = useState({ type: '', text: '' });

    useEffect(() => {
        loadData();
    }, []);

    const loadData = async () => {
        try {
            setLoading(true);
            const [statsResponse, usersResponse] = await Promise.all([
                api.getNotificationStats(),
                api.getUsers()
            ]);

            if (statsResponse.success) {
                setStats(statsResponse.stats);
            }
            if (usersResponse.users) {
                setUsers(usersResponse.users);
            }
        } catch (error) {
            console.error('Error loading data:', error);
            setMessage({ type: 'error', text: 'Failed to load data' });
        } finally {
            setLoading(false);
        }
    };

    const handleSendBroadcast = async () => {
        if (!notification.title.trim()) {
            setMessage({ type: 'error', text: 'Title is required' });
            return;
        }

        const payload = {
            title: notification.title.trim(),
            body: notification.body.trim() || undefined,
            type: 'system',
            actionUrl: notification.actionUrl.trim() || undefined,
            showPopup: notification.showPopup,
            actionLabel: notification.actionLabel.trim() || undefined
        };

        try {
            setSending(true);
            const response = await api.sendBroadcastNotification(payload);

            if (response.success) {
                setMessage({ 
                    type: 'success', 
                    text: `Notification sent to ${response.stats.successCount} users` 
                });
                setNotification(createDefaultNotification());
                loadData(); // Refresh stats
            }
        } catch (error) {
            console.error('Error sending broadcast:', error);
            setMessage({ type: 'error', text: 'Failed to send notification' });
        } finally {
            setSending(false);
        }
    };

    const handleSendToSelected = async () => {
        if (!notification.title.trim()) {
            setMessage({ type: 'error', text: 'Title is required' });
            return;
        }
        if (selectedUsers.length === 0) {
            setMessage({ type: 'error', text: 'Please select at least one user' });
            return;
        }

        const payload = {
            userIds: selectedUsers,
            title: notification.title.trim(),
            body: notification.body.trim() || undefined,
            type: 'system',
            actionUrl: notification.actionUrl.trim() || undefined,
            showPopup: notification.showPopup,
            actionLabel: notification.actionLabel.trim() || undefined
        };

        try {
            setSending(true);
            const response = await api.sendNotificationToUsers(payload);

            if (response.success) {
                setMessage({ 
                    type: 'success', 
                    text: `Notification sent to ${response.stats.successCount} users` 
                });
                setNotification(createDefaultNotification());
                setSelectedUsers([]);
                loadData(); // Refresh stats
            }
        } catch (error) {
            console.error('Error sending to selected users:', error);
            setMessage({ type: 'error', text: 'Failed to send notification' });
        } finally {
            setSending(false);
        }
    };

    const toggleUserSelection = (userId) => {
        setSelectedUsers(prev => 
            prev.includes(userId) 
                ? prev.filter(id => id !== userId)
                : [...prev, userId]
        );
    };

    const selectAllUsers = () => {
        setSelectedUsers(users.map(u => u.id));
    };

    const clearSelection = () => {
        setSelectedUsers([]);
    };

    if (loading) {
        return (
            <div className="flex items-center justify-center h-64">
                <div className="animate-spin rounded-full h-12 w-12 border-b-2 border-primary"></div>
            </div>
        );
    }

    return (
        <div className="p-8">
            {/* Header */}
            <div className="mb-8">
                <h1 className="text-3xl font-bold mb-2">Notification Manager</h1>
                <p className="text-muted-foreground">Send notifications to users and view statistics</p>
            </div>

            {/* Message */}
            {message.text && (
                <div className={`mb-6 p-4 rounded-lg border ${
                    message.type === 'success' 
                        ? 'bg-green-50 border-green-200 text-green-800' 
                        : 'bg-red-50 border-red-200 text-red-800'
                }`}>
                    <div className="flex items-center gap-2">
                        {message.type === 'success' ? (
                            <CheckCircle className="h-5 w-5" />
                        ) : (
                            <AlertCircle className="h-5 w-5" />
                        )}
                        {message.text}
                    </div>
                </div>
            )}

            {/* Stats Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-6 mb-8">
                <StatCard
                    title="Total Notifications"
                    value={stats.total_notifications}
                    icon={Bell}
                    color="bg-blue-500"
                />
                <StatCard
                    title="Unread"
                    value={stats.unread_notifications}
                    icon={MessageSquare}
                    color="bg-orange-500"
                />
                <StatCard
                    title="System Notifications"
                    value={stats.system_notifications}
                    icon={AlertCircle}
                    color="bg-purple-500"
                />
                <StatCard
                    title="Last 24h"
                    value={stats.notifications_24h}
                    icon={TrendingUp}
                    color="bg-green-500"
                />
                <StatCard
                    title="Last 7 days"
                    value={stats.notifications_7d}
                    icon={TrendingUp}
                    color="bg-indigo-500"
                />
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
                {/* Send Notification Form */}
                <div className="bg-card border border-border rounded-lg p-6">
                    <h2 className="text-xl font-semibold mb-4 flex items-center gap-2">
                        <Send className="h-5 w-5" />
                        Send Notification
                    </h2>

                    <div className="space-y-4">
                        <div>
                            <label className="block text-sm font-medium mb-2">Title *</label>
                            <input
                                type="text"
                                value={notification.title}
                                onChange={(e) => setNotification(prev => ({ ...prev, title: e.target.value }))}
                                className="w-full px-3 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
                                placeholder="Notification title"
                                maxLength={100}
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-2">Message</label>
                            <textarea
                                value={notification.body}
                                onChange={(e) => setNotification(prev => ({ ...prev, body: e.target.value }))}
                                className="w-full px-3 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
                                placeholder="Notification message (optional)"
                                rows={3}
                                maxLength={500}
                            />
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-2">Type</label>
                            <select
                                value={notification.type}
                                onChange={(e) => setNotification(prev => ({ ...prev, type: e.target.value }))}
                                className="w-full px-3 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
                            >
                                <option value="system">System</option>
                            </select>
                            <p className="mt-2 text-xs text-muted-foreground">
                                Admin in-app notifications currently use the supported <strong>system</strong> type.
                            </p>
                        </div>

                        <div>
                            <label className="block text-sm font-medium mb-2">Action URL (optional)</label>
                            <input
                                type="url"
                                value={notification.actionUrl}
                                onChange={(e) => setNotification(prev => ({ ...prev, actionUrl: e.target.value }))}
                                className="w-full px-3 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary"
                                placeholder="https://example.com/action"
                            />
                        </div>

                        <div className="rounded-lg border border-border p-4 bg-muted/30">
                            <label className="flex items-start gap-3 cursor-pointer">
                                <input
                                    type="checkbox"
                                    checked={notification.showPopup}
                                    onChange={(e) => setNotification(prev => ({ ...prev, showPopup: e.target.checked }))}
                                    className="mt-1 rounded"
                                />
                                <div>
                                    <div className="text-sm font-medium">Show popup in app</div>
                                    <p className="mt-1 text-xs text-muted-foreground">
                                        Displays an in-app dialog in Flutter when the app is open and the next notification poll runs. This is not a device push notification.
                                    </p>
                                </div>
                            </label>

                            {notification.showPopup && (
                                <div className="mt-4">
                                    <label className="block text-sm font-medium mb-2">Popup action label (optional)</label>
                                    <input
                                        type="text"
                                        value={notification.actionLabel}
                                        onChange={(e) => setNotification(prev => ({ ...prev, actionLabel: e.target.value }))}
                                        className="w-full px-3 py-2 border border-border rounded-lg focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-50"
                                        placeholder="Open"
                                        maxLength={40}
                                    />
                                    <p className="mt-2 text-xs text-muted-foreground">
                                        Used for the popup button when an action URL is provided.
                                    </p>
                                </div>
                            )}
                        </div>

                        <div className="flex gap-3">
                            <button
                                onClick={handleSendBroadcast}
                                disabled={sending || !notification.title.trim()}
                                className="flex-1 bg-primary text-primary-foreground px-4 py-2 rounded-lg hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                            >
                                {sending ? (
                                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white"></div>
                                ) : (
                                    <Send className="h-4 w-4" />
                                )}
                                Send to All Users
                            </button>
                            <button
                                onClick={handleSendToSelected}
                                disabled={sending || !notification.title.trim() || selectedUsers.length === 0}
                                className="flex-1 bg-secondary text-secondary-foreground px-4 py-2 rounded-lg hover:bg-secondary/90 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
                            >
                                {sending ? (
                                    <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-current"></div>
                                ) : (
                                    <Users className="h-4 w-4" />
                                )}
                                Send to Selected ({selectedUsers.length})
                            </button>
                        </div>
                    </div>
                </div>

                {/* User Selection */}
                <div className="bg-card border border-border rounded-lg p-6">
                    <div className="flex items-center justify-between mb-4">
                        <h2 className="text-xl font-semibold flex items-center gap-2">
                            <Users className="h-5 w-5" />
                            Select Users ({users.length})
                        </h2>
                        <div className="flex gap-2">
                            <button
                                onClick={selectAllUsers}
                                className="px-3 py-1 text-sm bg-primary text-primary-foreground rounded hover:bg-primary/90"
                            >
                                Select All
                            </button>
                            <button
                                onClick={clearSelection}
                                className="px-3 py-1 text-sm bg-secondary text-secondary-foreground rounded hover:bg-secondary/90"
                            >
                                Clear
                            </button>
                        </div>
                    </div>

                    <div className="max-h-96 overflow-y-auto space-y-2">
                        {users.map(user => (
                            <div
                                key={user.id}
                                className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer transition-colors ${
                                    selectedUsers.includes(user.id)
                                        ? 'bg-primary/10 border-primary'
                                        : 'bg-background border-border hover:bg-muted'
                                }`}
                                onClick={() => toggleUserSelection(user.id)}
                            >
                                <input
                                    type="checkbox"
                                    checked={selectedUsers.includes(user.id)}
                                    onChange={() => toggleUserSelection(user.id)}
                                    className="rounded"
                                />
                                <div className="flex-1">
                                    <div className="font-medium">{user.display_name || user.email}</div>
                                    <div className="text-sm text-muted-foreground">{user.email}</div>
                                </div>
                                <div className="text-xs text-muted-foreground">
                                    {user.role === 'admin' && (
                                        <span className="bg-red-100 text-red-800 px-2 py-1 rounded">Admin</span>
                                    )}
                                </div>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* Type Breakdown */}
            {stats.typeBreakdown && stats.typeBreakdown.length > 0 && (
                <div className="mt-8 bg-card border border-border rounded-lg p-6">
                    <h2 className="text-xl font-semibold mb-4">Notification Types</h2>
                    <div className="space-y-2">
                        {stats.typeBreakdown.map(item => (
                            <div key={item.type} className="flex justify-between items-center">
                                <span className="capitalize">{item.type}</span>
                                <span className="font-medium">{item.count}</span>
                            </div>
                        ))}
                    </div>
                </div>
            )}
        </div>
    );
}

function StatCard({ title, value, icon: Icon, color }) {
    return (
        <div className="bg-card border border-border rounded-lg p-6">
            <div className="flex items-center justify-between">
                <div>
                    <p className="text-sm font-medium text-muted-foreground">{title}</p>
                    <p className="text-2xl font-bold">{value.toLocaleString()}</p>
                </div>
                <div className={`p-3 rounded-full ${color}`}>
                    <Icon className="h-6 w-6 text-white" />
                </div>
            </div>
        </div>
    );
}
