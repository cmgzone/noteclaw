"use client";

import {
    ArrowLeft,
    Bot,
    Braces,
    CheckCircle2,
    Clock3,
    Database,
    FileJson2,
    Layers3,
    Loader2,
    Radio,
    RefreshCw,
} from "lucide-react";
import Link from "next/link";
import { useParams, useRouter } from "next/navigation";
import {
    type ReactNode,
    useCallback,
    useEffect,
    useMemo,
    useState,
} from "react";

import { useAuth } from "@/lib/auth-context";
import api, { Notebook, Source } from "@/lib/api";
import SubscriptionFeatureGate from "@/components/subscription-feature-gate";

export default function NotebookDetailPage() {
    return (
        <SubscriptionFeatureGate feature="memory_bank">
            <NotebookDetailContent />
        </SubscriptionFeatureGate>
    );
}

function NotebookDetailContent() {
    const { id } = useParams() as { id: string };
    const router = useRouter();
    const { isAuthenticated, isLoading: authLoading } = useAuth();
    const [notebook, setNotebook] = useState<Notebook | null>(null);
    const [sources, setSources] = useState<Source[]>([]);
    const [selectedSourceId, setSelectedSourceId] = useState<string | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [isRefreshing, setIsRefreshing] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const loadNotebook = useCallback(
        async (background = false) => {
            if (!background) {
                setIsLoading(true);
            } else {
                setIsRefreshing(true);
            }

            try {
                const result = await api.getMemoryNotebook(id);
                setNotebook(result.notebook);
                setSources(result.sources);
                setSelectedSourceId((current) => {
                    if (
                        current &&
                        result.sources.some((source) => source.id === current)
                    ) {
                        return current;
                    }
                    return result.sources[0]?.id || null;
                });
                setError(null);
            } catch (loadError) {
                console.error("Failed to load memory notebook:", loadError);
                setError("This memory notebook could not be loaded.");
            } finally {
                setIsLoading(false);
                setIsRefreshing(false);
            }
        },
        [id],
    );

    useEffect(() => {
        if (!authLoading && !isAuthenticated) {
            router.push("/login");
            return;
        }
        if (!isAuthenticated) {
            return;
        }

        void loadNotebook();
        const refreshTimer = window.setInterval(
            () => void loadNotebook(true),
            7_500,
        );
        return () => window.clearInterval(refreshTimer);
    }, [authLoading, isAuthenticated, loadNotebook, router]);

    const selectedSource = useMemo(
        () => sources.find((source) => source.id === selectedSourceId) || null,
        [selectedSourceId, sources],
    );

    if (authLoading || isLoading) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-[#050607]">
                <Loader2 className="animate-spin text-[#62d3d0]" size={36} />
            </div>
        );
    }

    if (!notebook) {
        return (
            <div className="flex min-h-screen flex-col items-center justify-center bg-[#050607] px-6 text-center text-white">
                <Database className="mb-5 text-neutral-700" size={42} />
                <h1 className="text-2xl font-semibold">Memory notebook not found</h1>
                <p className="mt-2 text-sm text-neutral-500">
                    {error || "This notebook may no longer be available."}
                </p>
                <Link
                    href="/dashboard"
                    className="mt-6 rounded-full bg-[#62d3d0] px-5 py-2.5 text-sm font-semibold text-black"
                >
                    Return to memory banks
                </Link>
            </div>
        );
    }

    const liveConnections = notebook.session?.websocketConnectionCount || 0;

    return (
        <div className="min-h-screen overflow-x-hidden bg-[#050607] text-white lg:flex">
            <aside className="border-b border-white/8 bg-[#08090b] lg:sticky lg:top-0 lg:h-screen lg:w-80 lg:shrink-0 lg:border-b-0 lg:border-r">
                <div className="flex items-center gap-3 border-b border-white/8 px-4 py-4">
                    <Link
                        href="/dashboard"
                        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-white/10 text-neutral-400 transition hover:text-white"
                    >
                        <ArrowLeft size={17} />
                    </Link>
                    <div className="min-w-0 flex-1">
                        <h1 className="truncate text-sm font-semibold">{notebook.title}</h1>
                        <p className="truncate text-xs text-neutral-600">
                            {notebook.session?.agentIdentifier}
                        </p>
                    </div>
                    <div
                        className={`flex shrink-0 items-center gap-1.5 rounded-full border px-2 py-1 text-[9px] font-semibold uppercase tracking-wider ${
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
                        {liveConnections > 0 ? `${liveConnections} live` : "Offline"}
                    </div>
                </div>

                <div className="border-b border-white/8 px-4 py-4">
                    <div className="flex items-center justify-between text-xs">
                        <span className="font-semibold uppercase tracking-[0.16em] text-neutral-500">
                            Memory sources
                        </span>
                        <span className="rounded-full bg-white/5 px-2 py-0.5 text-neutral-500">
                            {sources.length}
                        </span>
                    </div>
                    <p className="mt-2 text-xs leading-5 text-neutral-600">
                        Each source is a durable namespace shared through MCP.
                    </p>
                </div>

                <div className="flex gap-2 overflow-x-auto p-3 lg:block lg:h-[calc(100vh-174px)] lg:space-y-2 lg:overflow-y-auto">
                    {sources.length === 0 ? (
                        <div className="min-w-64 rounded-xl border border-dashed border-white/10 p-5 text-center text-xs leading-5 text-neutral-600 lg:min-w-0">
                            This notebook is ready. Sources appear when an agent writes its
                            first memory namespace.
                        </div>
                    ) : (
                        sources.map((source) => {
                            const selected = source.id === selectedSourceId;
                            return (
                                <button
                                    key={source.id}
                                    onClick={() => setSelectedSourceId(source.id)}
                                    className={`min-w-64 rounded-xl border p-3 text-left transition lg:min-w-0 lg:w-full ${
                                        selected
                                            ? "border-[#62d3d0]/30 bg-[#62d3d0]/5"
                                            : "border-transparent bg-white/[0.02] hover:border-white/10 hover:bg-white/[0.04]"
                                    }`}
                                >
                                    <div className="flex min-w-0 items-start gap-3">
                                        <div
                                            className={`mt-0.5 flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${
                                                selected
                                                    ? "bg-[#62d3d0]/10 text-[#62d3d0]"
                                                    : "bg-white/5 text-neutral-500"
                                            }`}
                                        >
                                            <FileJson2 size={16} />
                                        </div>
                                        <div className="min-w-0 flex-1">
                                            <div className="truncate text-sm font-medium">
                                                {source.title}
                                            </div>
                                            <div className="mt-1 truncate font-mono text-[10px] text-neutral-600">
                                                {source.namespace}
                                            </div>
                                            <div className="mt-2 text-[10px] text-neutral-500">
                                                Version {source.version || 0}
                                            </div>
                                        </div>
                                    </div>
                                </button>
                            );
                        })
                    )}
                </div>
            </aside>

            <main className="min-w-0 flex-1">
                <header className="border-b border-white/8 bg-[#08090b]/80 px-4 py-5 backdrop-blur-xl sm:px-6 lg:px-8">
                    <div className="mx-auto flex w-full max-w-5xl flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
                        <div className="min-w-0">
                            <div className="mb-2 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.18em] text-[#62d3d0]">
                                <Bot size={13} />
                                Shared agent memory
                            </div>
                            <h2 className="truncate text-xl font-semibold sm:text-2xl">
                                {selectedSource?.title || notebook.title}
                            </h2>
                            <p className="mt-1 truncate font-mono text-xs text-neutral-600">
                                {selectedSource?.namespace ||
                                    "Waiting for the first namespace"}
                            </p>
                        </div>
                        <button
                            onClick={() => void loadNotebook(true)}
                            disabled={isRefreshing}
                            className="inline-flex shrink-0 items-center justify-center gap-2 rounded-full border border-white/10 px-4 py-2.5 text-sm text-neutral-400 transition hover:border-white/20 hover:text-white disabled:opacity-50"
                        >
                            <RefreshCw
                                size={15}
                                className={isRefreshing ? "animate-spin" : ""}
                            />
                            Refresh memory
                        </button>
                    </div>
                </header>

                <div className="mx-auto w-full max-w-5xl px-4 py-7 sm:px-6 lg:px-8">
                    {error && (
                        <div className="mb-5 rounded-xl border border-red-400/20 bg-red-400/5 px-4 py-3 text-sm text-red-200">
                            {error}
                        </div>
                    )}

                    {selectedSource ? (
                        <MemorySourceView source={selectedSource} />
                    ) : (
                        <EmptyNotebook notebook={notebook} />
                    )}
                </div>
            </main>
        </div>
    );
}

function MemorySourceView({ source }: { source: Source }) {
    const memory = source.memory || {};
    const fields = Object.entries(memory);
    const stats = source.memoryStats;

    return (
        <div className="min-w-0 space-y-5">
            <section className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
                <SourceStat
                    icon={<Braces size={16} />}
                    label="Populated fields"
                    value={stats?.nonEmptyFieldCount ?? fields.length}
                />
                <SourceStat
                    icon={<Layers3 size={16} />}
                    label="History items"
                    value={stats?.historyLength || 0}
                />
                <SourceStat
                    icon={<CheckCircle2 size={16} />}
                    label="Checkpoints"
                    value={stats?.checkpointCount || 0}
                />
                <SourceStat
                    icon={<Clock3 size={16} />}
                    label="Last updated"
                    value={
                        source.updatedAt
                            ? new Date(source.updatedAt).toLocaleString()
                            : "Unknown"
                    }
                    text
                />
            </section>

            <section className="rounded-2xl border border-white/8 bg-[#090b0d]">
                <div className="flex min-w-0 flex-col gap-2 border-b border-white/8 px-4 py-4 sm:flex-row sm:items-center sm:justify-between sm:px-5">
                    <div className="min-w-0">
                        <h3 className="text-sm font-semibold">Memory contents</h3>
                        <p className="mt-1 truncate text-xs text-neutral-600">
                            {source.summary}
                        </p>
                    </div>
                    <div className="flex shrink-0 items-center gap-2">
                        <span className="rounded-full border border-white/8 px-2.5 py-1 font-mono text-[10px] text-neutral-500">
                            v{source.version || 0}
                        </span>
                        <span className="flex items-center gap-1.5 rounded-full border border-emerald-400/15 bg-emerald-400/5 px-2.5 py-1 text-[10px] text-emerald-400">
                            <Radio size={10} />
                            MCP managed
                        </span>
                    </div>
                </div>

                {fields.length === 0 ? (
                    <div className="px-5 py-16 text-center text-sm text-neutral-600">
                        This namespace exists but contains no memory fields yet.
                    </div>
                ) : (
                    <div className="divide-y divide-white/7">
                        {fields.map(([key, value]) => (
                            <MemoryField key={key} name={key} value={value} />
                        ))}
                    </div>
                )}
            </section>
        </div>
    );
}

function SourceStat({
    icon,
    label,
    value,
    text = false,
}: {
    icon: ReactNode;
    label: string;
    value: number | string;
    text?: boolean;
}) {
    return (
        <div className="min-w-0 rounded-2xl border border-white/8 bg-[#090b0d] p-4">
            <div className="mb-3 text-neutral-600">{icon}</div>
            <div className={`${text ? "truncate text-sm" : "text-2xl"} font-semibold`}>
                {value}
            </div>
            <div className="mt-1 text-xs text-neutral-600">{label}</div>
        </div>
    );
}

function MemoryField({ name, value }: { name: string; value: unknown }) {
    const label = name
        .replace(/([a-z])([A-Z])/g, "$1 $2")
        .replace(/[_-]+/g, " ")
        .replace(/\b\w/g, (character) => character.toUpperCase());

    return (
        <div className="min-w-0 px-4 py-5 sm:px-5">
            <div className="mb-3 flex min-w-0 items-center justify-between gap-3">
                <h4 className="truncate text-xs font-semibold uppercase tracking-[0.14em] text-neutral-500">
                    {label}
                </h4>
                <span className="shrink-0 font-mono text-[9px] text-neutral-700">
                    {getValueType(value)}
                </span>
            </div>
            <MemoryValue value={value} />
        </div>
    );
}

function MemoryValue({ value }: { value: unknown }) {
    if (value == null) {
        return <span className="text-sm italic text-neutral-600">No value</span>;
    }

    if (typeof value === "boolean") {
        return (
            <span
                className={`inline-flex rounded-full px-2.5 py-1 text-xs font-medium ${
                    value
                        ? "bg-emerald-400/10 text-emerald-300"
                        : "bg-white/5 text-neutral-500"
                }`}
            >
                {String(value)}
            </span>
        );
    }

    if (typeof value === "string" || typeof value === "number") {
        return (
            <div className="break-words text-sm leading-6 text-neutral-300">
                {String(value)}
            </div>
        );
    }

    if (Array.isArray(value)) {
        const visibleItems = value.slice(0, 50);
        return (
            <div className="space-y-2">
                {visibleItems.map((item, index) => (
                    <div
                        key={index}
                        className="min-w-0 rounded-xl border border-white/7 bg-black/20 px-3 py-2.5"
                    >
                        <pre className="overflow-x-auto whitespace-pre-wrap break-words font-mono text-xs leading-5 text-neutral-400">
                            {typeof item === "string"
                                ? item
                                : JSON.stringify(item, null, 2)}
                        </pre>
                    </div>
                ))}
                {value.length > visibleItems.length && (
                    <div className="text-xs text-neutral-600">
                        {value.length - visibleItems.length} additional items are hidden.
                    </div>
                )}
            </div>
        );
    }

    return (
        <pre className="max-w-full overflow-x-auto whitespace-pre-wrap break-words rounded-xl border border-white/7 bg-black/25 p-4 font-mono text-xs leading-6 text-neutral-400">
            {JSON.stringify(value, null, 2)}
        </pre>
    );
}

function EmptyNotebook({ notebook }: { notebook: Notebook }) {
    return (
        <div className="rounded-3xl border border-dashed border-white/10 px-6 py-20 text-center">
            <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-[#62d3d0]/5 text-[#62d3d0]">
                <Database size={25} />
            </div>
            <h2 className="text-xl font-semibold">Notebook ready for memory</h2>
            <p className="mx-auto mt-3 max-w-lg text-sm leading-6 text-neutral-500">
                Ask an agent connected to{" "}
                <span className="font-mono text-neutral-400">
                    {notebook.session?.agentIdentifier}
                </span>{" "}
                to call memory_put. Its namespace will appear here as an organized
                source.
            </p>
        </div>
    );
}

function getValueType(value: unknown): string {
    if (Array.isArray(value)) {
        return `${value.length} items`;
    }
    if (value == null) {
        return "null";
    }
    return typeof value;
}
