import { useState, useEffect } from 'react';
import api from '../lib/api';
import {
    Users,
    Shield,
    Settings2,
    Calendar,
    CreditCard,
    Bot,
    DollarSign,
    TrendingUp,
} from 'lucide-react';
import { useAuth } from '../contexts/AuthContext';

function formatCurrency(value) {
    const amount = typeof value === 'number' ? value : Number(value || 0);
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 2,
    }).format(Number.isFinite(amount) ? amount : 0);
}

export default function Dashboard() {
    const { user } = useAuth();
    const [stats, setStats] = useState({
        totalUsers: 0,
        adminUsers: 0,
        activeUsers: 0,
        totalModels: 0,
        totalPlans: 0,
        totalTransactions: 0,
        totalRevenue: 0,
        monthlyRevenue: 0,
        paidTransactions: 0,
        recentUsers: [],
    });
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        loadStats();
    }, []);

    const loadStats = async () => {
        try {
            setLoading(true);
            const response = await api.getDashboardStats();
            if (response.success) {
                setStats(response.stats);
            }
        } catch (error) {
            console.error('Error loading stats:', error);
        } finally {
            setLoading(false);
        }
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
            <div className="mb-8">
                <h1 className="text-3xl font-bold mb-2">Dashboard</h1>
                <p className="text-muted-foreground">Welcome back, {user?.displayName || user?.email}!</p>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6 mb-8">
                <StatCard
                    title="Total Users"
                    value={stats.totalUsers}
                    icon={Users}
                    color="bg-blue-500"
                />
                <StatCard
                    title="Admin Users"
                    value={stats.adminUsers}
                    icon={Shield}
                    color="bg-green-500"
                />
                <StatCard
                    title="AI Models"
                    value={stats.totalModels}
                    icon={Bot}
                    color="bg-violet-500"
                />
                <StatCard
                    title="Transactions"
                    value={stats.totalTransactions}
                    icon={CreditCard}
                    color="bg-orange-500"
                    subtitle={`${stats.paidTransactions} monetized`}
                />
                <StatCard
                    title="Total Earnings"
                    value={formatCurrency(stats.totalRevenue)}
                    icon={DollarSign}
                    color="bg-emerald-500"
                />
                <StatCard
                    title="This Month"
                    value={formatCurrency(stats.monthlyRevenue)}
                    icon={TrendingUp}
                    color="bg-cyan-500"
                />
            </div>

            <div className="mb-8">
                <h2 className="text-xl font-semibold mb-4">Quick Actions</h2>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
                    <QuickActionCard
                        title="Manage Users"
                        description="View and manage user accounts"
                        icon={Users}
                        href="/users"
                    />
                    <QuickActionCard
                        title="AI Models"
                        description="Configure AI models"
                        icon={Bot}
                        href="/ai-models"
                    />
                    <QuickActionCard
                        title="Settings"
                        description="Configure app settings and API keys"
                        icon={Settings2}
                        href="/settings"
                    />
                    <QuickActionCard
                        title="Subscriptions"
                        description="Manage subscription plans"
                        icon={CreditCard}
                        href="/subscription-plans"
                    />
                </div>
            </div>

            <div className="bg-card border border-border rounded-lg p-6">
                <h2 className="text-xl font-semibold mb-4">Recent User Registrations</h2>
                <div className="space-y-3">
                    {!stats.recentUsers || stats.recentUsers.length === 0 ? (
                        <p className="text-muted-foreground text-sm">No recent users</p>
                    ) : (
                        stats.recentUsers.map((recentUser, index) => (
                            <div key={index} className="flex items-center justify-between py-2 border-b border-border last:border-0">
                                <div className="flex items-center gap-3">
                                    <Calendar className="h-4 w-4 text-muted-foreground" />
                                    <div>
                                        <p className="text-sm font-medium">{recentUser.email}</p>
                                        <p className="text-xs text-muted-foreground">
                                            {new Date(recentUser.created_at).toLocaleDateString()} - {recentUser.role === 'admin' ? 'Admin' : 'User'}
                                        </p>
                                    </div>
                                </div>
                                <span className={`px-2 py-1 rounded-full text-xs ${recentUser.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-700'}`}>
                                    {recentUser.is_active ? 'Active' : 'Inactive'}
                                </span>
                            </div>
                        ))
                    )}
                </div>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-6 mt-8">
                <div className="bg-card border border-border rounded-lg p-6">
                    <h3 className="font-semibold mb-3">System Configuration</h3>
                    <div className="space-y-2 text-sm">
                        <div className="flex justify-between">
                            <span className="text-muted-foreground">Subscription Plans:</span>
                            <span className="font-medium">{stats.totalPlans} plans</span>
                        </div>
                        <div className="flex justify-between">
                            <span className="text-muted-foreground">AI Models:</span>
                            <span className="font-medium">{stats.totalModels} models</span>
                        </div>
                        <div className="flex justify-between">
                            <span className="text-muted-foreground">Paid Transactions:</span>
                            <span className="font-medium">{stats.paidTransactions}</span>
                        </div>
                        <div className="flex justify-between">
                            <span className="text-muted-foreground">Backend:</span>
                            <span className="font-medium text-green-600">Connected</span>
                        </div>
                    </div>
                </div>

                <div className="bg-gradient-to-br from-primary/10 to-primary/5 border border-primary/20 rounded-lg p-6">
                    <h3 className="font-semibold mb-3">Admin Tips</h3>
                    <ul className="space-y-2 text-sm text-muted-foreground">
                        <li>- Use the User Management page to promote users to admin</li>
                        <li>- Keep your API keys secure in the Settings page</li>
                        <li>- Monitor earnings and purchases in Transactions</li>
                        <li>- Review monthly revenue trends from this dashboard</li>
                    </ul>
                </div>
            </div>
        </div>
    );
}

function StatCard({ title, value, icon: Icon, color, subtitle }) {
    return (
        <div className="bg-card border border-border rounded-lg p-6">
            <div className="flex items-center justify-between mb-4">
                <div className={`${color} p-3 rounded-lg`}>
                    <Icon className="h-6 w-6 text-white" />
                </div>
            </div>
            <div>
                <p className="text-sm text-muted-foreground mb-1">{title}</p>
                <p className="text-3xl font-bold">{value}</p>
                {subtitle ? (
                    <p className="mt-2 text-xs text-muted-foreground">{subtitle}</p>
                ) : null}
            </div>
        </div>
    );
}

function QuickActionCard({ title, description, icon: Icon, href }) {
    return (
        <a
            href={href}
            className="bg-card border border-border rounded-lg p-4 hover:border-primary transition-all hover:shadow-md group"
        >
            <div className="flex items-start gap-3">
                <div className="p-2 bg-primary/10 rounded-lg group-hover:bg-primary group-hover:text-white transition-all">
                    <Icon className="h-5 w-5 text-primary group-hover:text-white" />
                </div>
                <div>
                    <h3 className="font-semibold mb-1">{title}</h3>
                    <p className="text-sm text-muted-foreground">{description}</p>
                </div>
            </div>
        </a>
    );
}
