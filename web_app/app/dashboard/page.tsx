"use client";

import React, { useEffect, useState } from "react";
import {
    CreditCard,
    Zap,
    Clock,
    Database,
    LogOut,
    Loader2,
    ArrowUpRight,
    Bot,
} from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { useAuth } from "@/lib/auth-context";
import api, { Subscription, CreditTransaction, Notebook } from "@/lib/api";

export default function DashboardPage() {
    const { user, isLoading: authLoading, isAuthenticated, logout } = useAuth();
    const router = useRouter();
    const [subscription, setSubscription] = useState<Subscription | null>(null);
    const [transactions, setTransactions] = useState<CreditTransaction[]>([]);
    const [notebooks, setNotebooks] = useState<Notebook[]>([]);
    const [isLoading, setIsLoading] = useState(true);

    useEffect(() => {
        if (!authLoading && !isAuthenticated) {
            router.push("/login");
            return;
        }

        if (isAuthenticated) {
            loadData();
        }
    }, [authLoading, isAuthenticated, router]);

    const loadData = async () => {
        setIsLoading(true);
        try {
            const [sub, txs, nbs] = await Promise.all([
                api.getSubscription(),
                api.getTransactions(10),
                api.getNotebooks(),
            ]);
            setSubscription(sub);
            setTransactions(txs);
            setNotebooks(nbs);
        } catch (error) {
            console.error("Failed to load dashboard data:", error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleLogout = () => {
        logout();
        router.push("/");
    };



    if (authLoading || (!isAuthenticated && !authLoading)) {
        return (
            <div className="min-h-screen bg-neutral-950 flex items-center justify-center">
                <Loader2 className="animate-spin text-blue-500" size={40} />
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-neutral-950 text-white">
            <DashboardNav user={user} onLogout={handleLogout} />

            <main className="container mx-auto px-6 py-8">
                <header className="mb-8 flex justify-between items-center">
                    <div>
                        <h1 className="text-3xl font-bold tracking-tight">Overview</h1>
                        <p className="text-neutral-400">Welcome back, {user?.displayName || user?.email?.split("@")[0]}.</p>
                    </div>

                </header>

                {isLoading ? (
                    <div className="flex items-center justify-center py-12">
                        <Loader2 className="animate-spin text-blue-500" size={32} />
                    </div>
                ) : (
                    <>
                        {/* Notebooks Section */}
                        <section className="mb-12">
                            <h2 className="text-xl font-semibold mb-6 flex items-center gap-2">
                                <Database size={20} className="text-blue-400" />
                                Your Notebooks
                            </h2>
                            {notebooks.length === 0 ? (
                                <div className="rounded-xl border border-white/5 bg-neutral-900/30 p-12 text-center">
                                    <div className="mx-auto w-12 h-12 rounded-full bg-neutral-800 flex items-center justify-center mb-4 text-neutral-500">
                                        <Database size={24} />
                                    </div>
                                    <h3 className="text-lg font-medium text-white mb-2">No notebooks yet</h3>
                                    <p className="text-neutral-400 mb-6">Create your first notebook in the mobile app to start organizing your ideas.</p>
                                </div>
                            ) : (
                                <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
                                    {notebooks.map((notebook) => (
                                        <Link key={notebook.id} href={`/notebook/${notebook.id}`}>
                                            <motion.div
                                                whileHover={{ scale: 1.02 }}
                                                className="group relative overflow-hidden rounded-xl border border-white/5 bg-neutral-900/50 p-6 hover:bg-neutral-900/80 transition-all cursor-pointer h-full"
                                            >
                                                <div className="flex justify-between items-start mb-4">
                                                    <div className="p-3 rounded-lg bg-blue-500/10 text-blue-400 group-hover:bg-blue-500/20 transition-colors">
                                                        <Database size={24} />
                                                    </div>
                                                    {notebook.category && (
                                                        <span className="text-xs font-mono bg-white/5 px-2 py-1 rounded text-neutral-400 border border-white/5">
                                                            {notebook.category}
                                                        </span>
                                                    )}
                                                </div>
                                                <h3 className="text-lg font-semibold mb-2 group-hover:text-blue-400 transition-colors">
                                                    {notebook.title}
                                                </h3>
                                                <p className="text-sm text-neutral-400 line-clamp-2 mb-4">
                                                    {notebook.description || "No description"}
                                                </p>
                                                <div className="flex items-center gap-4 text-xs text-neutral-500 mt-auto pt-4 border-t border-white/5">
                                                    <div className="flex items-center gap-1">
                                                        <Clock size={12} />
                                                        {new Date(notebook.updatedAt).toLocaleDateString()}
                                                    </div>
                                                    <div className="flex items-center gap-1">
                                                        <Database size={12} />
                                                        {notebook.sourceCount || 0} sources
                                                    </div>
                                                </div>
                                            </motion.div>
                                        </Link>
                                    ))}
                                </div>
                            )}
                        </section>

                        <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-4 mb-8">
                            <StatCard
                                title="Credits Remaining"
                                value={subscription?.current_credits?.toString() || "0"}
                                label={`/ ${subscription?.credits_per_month || 0} monthly`}
                                icon={<Zap className="text-amber-400" size={20} />}
                            />
                            <StatCard
                                title="Credits Used"
                                value={subscription?.credits_consumed_this_month?.toString() || "0"}
                                label="This billing cycle"
                                icon={<Clock className="text-blue-400" size={20} />}
                            />
                            <StatCard
                                title="Total Transactions"
                                value={transactions.length.toString()}
                                label="Recent activities"
                                icon={<Database className="text-purple-400" size={20} />}
                            />
                            <StatCard
                                title="Current Plan"
                                value={subscription?.plan_name || "Free"}
                                label={subscription?.next_renewal_date ? `Renews ${new Date(subscription.next_renewal_date).toLocaleDateString()}` : ""}
                                icon={<CreditCard className="text-green-400" size={20} />}
                            />
                        </div>

                        <div className="grid gap-6 md:grid-cols-3">
                            <div className="md:col-span-2 space-y-6">
                                <UsageChart subscription={subscription} />
                                <RecentActivity transactions={transactions} />
                            </div>
                            <div className="space-y-6">
                                <SubscriptionCard subscription={subscription} />
                                <McpCard />
                            </div>
                        </div>
                    </>
                )}
            </main>
        </div>
    );
}

function DashboardNav({ user, onLogout }: { user: any; onLogout: () => void }) {
    return (
        <nav className="border-b border-white/5 bg-neutral-900/50 backdrop-blur-xl">
            <div className="container mx-auto flex h-16 items-center justify-between px-6">
                <Link href="/" className="flex items-center gap-2">
                    <Image src="/icon.png" alt="NoteClaw" width={24} height={24} className="rounded-md" />
                    <span className="font-bold tracking-tight">NoteClaw</span>
                </Link>
                <div className="flex items-center gap-4">
                    <span className="text-sm text-neutral-400 hidden md:block">{user?.email}</span>
                    <button
                        onClick={onLogout}
                        className="flex items-center gap-2 text-sm font-medium text-neutral-400 hover:text-white transition-colors"
                    >
                        <LogOut size={16} />
                        <span className="hidden md:inline">Log out</span>
                    </button>
                    <div className="h-8 w-8 rounded-full bg-gradient-to-tr from-blue-500 to-purple-500 flex items-center justify-center text-xs font-bold">
                        {user?.displayName?.[0]?.toUpperCase() || user?.email?.[0]?.toUpperCase() || "U"}
                    </div>
                </div>
            </div>
        </nav>
    );
}

function StatCard({ title, value, label, icon }: { title: string, value: string, label: string, icon: React.ReactNode }) {
    return (
        <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6 backdrop-blur-sm hover:bg-neutral-900/80 transition-colors">
            <div className="flex items-center justify-between mb-4">
                <h3 className="text-sm font-medium text-neutral-400">{title}</h3>
                {icon}
            </div>
            <div className="text-2xl font-bold">{value}</div>
            <p className="text-xs text-neutral-500 mt-1">{label}</p>
        </div>
    );
}

function UsageChart({ subscription }: { subscription: Subscription | null }) {
    const used = subscription?.credits_consumed_this_month || 0;
    const total = subscription?.credits_per_month || 1;
    const percentage = Math.min((used / total) * 100, 100);

    return (
        <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6">
            <h3 className="text-lg font-semibold mb-6">Credit Usage</h3>
            <div className="space-y-4">
                <div className="flex justify-between text-sm">
                    <span className="text-neutral-400">Used this month</span>
                    <span className="font-mono">{used} / {total}</span>
                </div>
                <div className="h-3 w-full rounded-full bg-neutral-800 overflow-hidden">
                    <motion.div
                        initial={{ width: 0 }}
                        animate={{ width: `${percentage}%` }}
                        transition={{ duration: 1, ease: "easeOut" }}
                        className={`h-full rounded-full ${percentage > 80 ? 'bg-red-500' : percentage > 50 ? 'bg-amber-500' : 'bg-blue-500'}`}
                    />
                </div>
                <p className="text-xs text-neutral-500">
                    {percentage < 50
                        ? "You're using credits efficiently!"
                        : percentage < 80
                            ? "Over halfway through your monthly credits."
                            : "Consider upgrading your plan for more credits."}
                </p>
            </div>
        </div>
    );
}

function RecentActivity({ transactions }: { transactions: CreditTransaction[] }) {
    return (
        <div className="rounded-xl border border-white/5 bg-neutral-900/50 p-6">
            <h3 className="text-lg font-semibold mb-4">Recent Activity</h3>
            {transactions.length === 0 ? (
                <p className="text-neutral-500 text-sm">No recent activity.</p>
            ) : (
                <div className="space-y-4">
                    {transactions.slice(0, 5).map((tx) => (
                        <div key={tx.id} className="flex items-center justify-between p-3 rounded-lg bg-white/5">
                            <div>
                                <div className="font-medium text-sm">{tx.description || tx.transaction_type}</div>
                                <div className="text-xs text-neutral-500">
                                    {new Date(tx.created_at).toLocaleDateString()} at {new Date(tx.created_at).toLocaleTimeString()}
                                </div>
                            </div>
                            <span className={`text-xs font-mono ${tx.amount < 0 ? 'text-red-400' : 'text-green-400'}`}>
                                {tx.amount > 0 ? '+' : ''}{tx.amount} credits
                            </span>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}

function SubscriptionCard({ subscription }: { subscription: Subscription | null }) {
    const planName = subscription?.plan_name || "Free";
    const isFree = subscription?.is_free_plan ?? true;

    return (
        <div className="rounded-xl border border-white/5 bg-gradient-to-br from-blue-900/20 to-purple-900/20 p-6 relative overflow-hidden">
            <div className="relative z-10">
                <div className="flex items-center justify-between mb-2">
                    <h3 className="text-lg font-semibold">{planName} Plan</h3>
                    {!isFree && (
                        <span className="px-2 py-1 text-xs font-bold bg-blue-500/20 text-blue-400 rounded-full">
                            Active
                        </span>
                    )}
                </div>
                <p className="text-sm text-neutral-400 mb-6">
                    {isFree
                        ? "Upgrade to unlock more credits and premium features."
                        : "You have access to all premium features."}
                </p>

                <div className="space-y-3 mb-6">
                    <div className="flex items-center gap-2 text-sm text-neutral-300">
                        <Zap size={16} className="text-blue-400" />
                        <span>{subscription?.credits_per_month || 50} monthly credits</span>
                    </div>
                    <div className="flex items-center gap-2 text-sm text-neutral-300">
                        <Bot size={16} className="text-purple-400" />
                        <span>{isFree ? "Limited Deep Research" : "Unlimited Deep Research"}</span>
                    </div>
                </div>

                <Link
                    href="/plans"
                    className="w-full flex items-center justify-center gap-2 rounded-lg bg-white/10 py-2 text-sm font-medium hover:bg-white/20 transition-colors border border-white/10"
                >
                    {isFree ? "Upgrade Plan" : "Manage Subscription"}
                    <ArrowUpRight size={14} />
                </Link>
            </div>
        </div>
    );
}

function McpCard() {
    return (
        <div className="rounded-xl border border-white/5 bg-gradient-to-br from-purple-900/20 to-pink-900/20 p-6 relative overflow-hidden">
            <div className="relative z-10">
                <div className="flex items-center justify-between mb-2">
                    <h3 className="text-lg font-semibold">MCP Integration</h3>
                    <Bot size={20} className="text-purple-400" />
                </div>
                <p className="text-sm text-neutral-400 mb-6">
                    Connect AI coding agents to verify and save code directly to your notebooks.
                </p>

                <div className="space-y-3 mb-6">
                    <div className="flex items-center gap-2 text-sm text-neutral-300">
                        <Zap size={16} className="text-amber-400" />
                        <span>API token management</span>
                    </div>
                    <div className="flex items-center gap-2 text-sm text-neutral-300">
                        <Database size={16} className="text-green-400" />
                        <span>Code verification & storage</span>
                    </div>
                </div>

                <Link
                    href="/dashboard/mcp"
                    className="w-full flex items-center justify-center gap-2 rounded-lg bg-purple-600/20 py-2 text-sm font-medium hover:bg-purple-600/30 transition-colors border border-purple-500/20"
                >
                    View MCP Dashboard
                    <ArrowUpRight size={14} />
                </Link>
            </div>
        </div>
    );
}
