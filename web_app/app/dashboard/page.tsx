"use client";

import {
    Activity,
    ArrowUpRight,
    Bot,
    Clock3,
    Database,
    Layers3,
    Loader2,
    LogOut,
    Radio,
    Settings,
} from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useEffect, useMemo, useState } from "react";

import { useAuth } from "@/lib/auth-context";
import api, { Notebook } from "@/lib/api";
import SubscriptionFeatureGate from "@/components/subscription-feature-gate";

export default function DashboardPage() {
    return (
        <SubscriptionFeatureGate feature="memory_bank">
            <DashboardContent />
        </SubscriptionFeatureGate>
    );
}

function DashboardContent() {
    const { user, isLoading: authLoading, isAuthenticated, logout } = useAuth();
    const router = useRouter();
    const [notebooks, setNotebooks] = useState<Notebook[]>([]);
    const [isLoading, setIsLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        if (!authLoading && !isAuthenticated) {
            router.push("/login");
            return;
        }

        if (!isAuthenticated) {
            return;
        }

        let active = true;
        const loadNotebooks = async () => {
            try {
                const result = await api.getNotebooks();
                if (active) {
                    setNotebooks(result);
                    setError(null);
                }
            } catch (loadError) {
                console.error("Failed to load memory notebooks:", loadError);
                if (active) {
                    setError("Could not load your memory banks.");
                }
            } finally {
                if (active) {
                    setIsLoading(false);
                }
            }
        };

        void loadNotebooks();
        const refreshTimer = window.setInterval(loadNotebooks, 10_000);
        return () => {
            active = false;
            window.clearInterval(refreshTimer);
        };
    }, [authLoading, isAuthenticated, router]);

    const totals = useMemo(() => {
        const sources = notebooks.reduce(
            (count, notebook) => count + (notebook.sourceCount || 0),
            0,
        );
        const liveConnections = notebooks.reduce(
            (count, notebook) =>
                count + (notebook.session?.websocketConnectionCount || 0),
            0,
        );
        return { sources, liveConnections };
    }, [notebooks]);

    const handleLogout = () => {
        logout();
        router.push("/");
    };

    if (authLoading || (!isAuthenticated && !authLoading)) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-[#050607]">
                <Loader2 className="animate-spin text-[#62d3d0]" size={36} />
            </div>
        );
    }

    return (
        <div className="min-h-screen overflow-x-hidden bg-[#050607] text-white">
            <DashboardNav user={user} onLogout={handleLogout} />

            <main className="mx-auto w-full max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
                <header className="mb-10 flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
                    <div className="min-w-0">
                        <div className="mb-3 flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.2em] text-[#62d3d0]">
                            <Activity size={14} />
                            Memory control room
                        </div>
                        <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">
                            Your agent memory banks
                        </h1>
                        <p className="mt-3 max-w-2xl text-sm leading-6 text-neutral-400 sm:text-base">
                            Each notebook is one shared project session. Its sources are
                            durable memory namespaces maintained by your agents.
                        </p>
                    </div>
                    <Link
                        href="/dashboard/mcp"
                        className="inline-flex shrink-0 items-center justify-center gap-2 rounded-full bg-[#62d3d0] px-5 py-3 text-sm font-semibold text-black transition hover:bg-[#91e2df]"
                    >
                        Connect an agent
                        <ArrowUpRight size={16} />
                    </Link>
                </header>

                <section className="mb-10 grid gap-3 sm:grid-cols-3">
                    <MemoryStat
                        icon={<Database size={18} />}
                        label="Project notebooks"
                        value={notebooks.length}
                    />
                    <MemoryStat
                        icon={<Layers3 size={18} />}
                        label="Memory sources"
                        value={totals.sources}
                    />
                    <MemoryStat
                        icon={<Radio size={18} />}
                        label="Agents live now"
                        value={totals.liveConnections}
                        live={totals.liveConnections > 0}
                    />
                </section>

                {error && (
                    <div className="mb-6 rounded-2xl border border-red-400/20 bg-red-400/5 px-4 py-3 text-sm text-red-200">
                        {error}
                    </div>
                )}

                {isLoading ? (
                    <div className="flex items-center justify-center py-24">
                        <Loader2 className="animate-spin text-[#62d3d0]" size={32} />
                    </div>
                ) : notebooks.length === 0 ? (
                    <EmptyMemoryState />
                ) : (
                    <section>
                        <div className="mb-5 flex items-center justify-between">
                            <h2 className="text-sm font-semibold uppercase tracking-[0.16em] text-neutral-500">
                                Shared project memory
                            </h2>
                            <span className="text-xs text-neutral-600">
                                Refreshes automatically
                            </span>
                        </div>
                        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
                            {notebooks.map((notebook) => (
                                <MemoryNotebookCard key={notebook.id} notebook={notebook} />
                            ))}
                        </div>
                    </section>
                )}
            </main>
        </div>
    );
}

function DashboardNav({
    user,
    onLogout,
}: {
    user: { email?: string; displayName?: string } | null;
    onLogout: () => void;
}) {
    return (
        <nav className="border-b border-white/8 bg-[#08090b]/90 backdrop-blur-xl">
            <div className="mx-auto flex h-16 w-full max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
                <Link href="/" className="flex min-w-0 items-center gap-2.5">
                    <Image
                        src="/icon.png"
                        alt="NoteClaw"
                        width={28}
                        height={28}
                        className="rounded-lg"
                    />
                    <span className="truncate font-semibold tracking-tight">NoteClaw</span>
                    <span className="hidden rounded-full border border-[#62d3d0]/20 bg-[#62d3d0]/5 px-2 py-0.5 text-[9px] font-semibold uppercase tracking-[0.18em] text-[#62d3d0] sm:inline">
                        Memory
                    </span>
                </Link>
                <div className="flex items-center gap-3">
                    <span className="hidden max-w-56 truncate text-sm text-neutral-500 md:block">
                        {user?.email}
                    </span>
                    <Link
                        href="/dashboard/settings"
                        aria-label="Account settings"
                        className="inline-flex items-center gap-2 rounded-full border border-white/10 px-3 py-2 text-sm text-neutral-400 transition hover:border-white/20 hover:text-white"
                    >
                        <Settings size={15} />
                        <span className="hidden sm:inline">Settings</span>
                    </Link>
                    <button
                        onClick={onLogout}
                        className="inline-flex items-center gap-2 rounded-full border border-white/10 px-3 py-2 text-sm text-neutral-400 transition hover:border-white/20 hover:text-white"
                    >
                        <LogOut size={15} />
                        <span className="hidden sm:inline">Log out</span>
                    </button>
                </div>
            </div>
        </nav>
    );
}

function MemoryStat({
    icon,
    label,
    value,
    live = false,
}: {
    icon: ReactNode;
    label: string;
    value: number;
    live?: boolean;
}) {
    return (
        <div className="min-w-0 rounded-2xl border border-white/8 bg-[#0a0c0f] p-5">
            <div className="mb-4 flex items-center justify-between text-neutral-500">
                {icon}
                {live && (
                    <span className="flex items-center gap-1.5 text-[10px] font-semibold uppercase tracking-wider text-emerald-400">
                        <span className="h-1.5 w-1.5 rounded-full bg-emerald-400" />
                        Live
                    </span>
                )}
            </div>
            <div className="text-3xl font-semibold">{value}</div>
            <div className="mt-1 text-sm text-neutral-500">{label}</div>
        </div>
    );
}

function MemoryNotebookCard({ notebook }: { notebook: Notebook }) {
    const liveConnections = notebook.session?.websocketConnectionCount || 0;
    return (
        <Link
            href={`/notebook/${notebook.id}`}
            className="group min-w-0 rounded-2xl border border-white/8 bg-[#0a0c0f] p-5 transition hover:border-[#62d3d0]/30 hover:bg-[#0d100f]"
        >
            <div className="mb-7 flex items-start justify-between gap-3">
                <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-[#62d3d0]/15 bg-[#62d3d0]/5 text-[#62d3d0]">
                    <Bot size={21} />
                </div>
                <div
                    className={`flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-[10px] font-semibold uppercase tracking-wider ${
                        liveConnections > 0
                            ? "border-emerald-400/20 bg-emerald-400/5 text-emerald-400"
                            : "border-white/8 text-neutral-600"
                    }`}
                >
                    <span
                        className={`h-1.5 w-1.5 rounded-full ${
                            liveConnections > 0 ? "bg-emerald-400" : "bg-neutral-700"
                        }`}
                    />
                    {liveConnections > 0
                        ? `${liveConnections} live`
                        : "Offline"}
                </div>
            </div>
            <h3 className="truncate text-lg font-semibold transition group-hover:text-[#62d3d0]">
                {notebook.title}
            </h3>
            <p className="mt-2 line-clamp-2 min-h-10 text-sm leading-5 text-neutral-500">
                {notebook.description || "Shared durable agent memory"}
            </p>
            <div className="mt-6 flex min-w-0 items-center justify-between gap-3 border-t border-white/7 pt-4 text-xs text-neutral-500">
                <span className="flex min-w-0 items-center gap-1.5">
                    <Layers3 size={13} />
                    <span className="truncate">
                        {notebook.sourceCount || 0} memory sources
                    </span>
                </span>
                <span className="flex shrink-0 items-center gap-1.5">
                    <Clock3 size={13} />
                    {new Date(notebook.updatedAt).toLocaleDateString()}
                </span>
            </div>
        </Link>
    );
}

function EmptyMemoryState() {
    return (
        <div className="rounded-3xl border border-dashed border-white/12 bg-[#090a0c] px-6 py-20 text-center">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl border border-[#62d3d0]/15 bg-[#62d3d0]/5 text-[#62d3d0]">
                <Database size={25} />
            </div>
            <h2 className="text-xl font-semibold">No project memory yet</h2>
            <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-neutral-500">
                Connect an MCP agent. NoteClaw creates its private notebook on the
                first connection, exposes permitted notebooks as MCP Resources, and
                organizes every namespace as a memory source.
            </p>
            <Link
                href="/dashboard/mcp"
                className="mt-7 inline-flex items-center gap-2 rounded-full bg-[#62d3d0] px-5 py-3 text-sm font-semibold text-black"
            >
                Configure MCP
                <ArrowUpRight size={16} />
            </Link>
        </div>
    );
}
