"use client";

import { ArrowRight, Loader2, RefreshCw, ShieldCheck } from "lucide-react";
import Image from "next/image";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { type ReactNode, useCallback, useEffect, useState } from "react";

import { useAuth } from "@/lib/auth-context";
import api, { type PlanFeatureAccess, type Subscription } from "@/lib/api";

const labels: Record<keyof PlanFeatureAccess, string> = {
    memory_bank: "Durable memory bank",
    notebook_chat: "Memory notebook chat",
    websocket_collaboration: "Shared WebSocket sessions",
    code_review: "Agent code review",
    web_search: "Live web search",
    deep_research: "Deep research",
    research_save_to_notebook: "Research notebook saving",
};

export default function SubscriptionFeatureGate({
    feature,
    children,
}: {
    feature: keyof PlanFeatureAccess;
    children: ReactNode;
}) {
    const router = useRouter();
    const { isAuthenticated, isLoading: authLoading } = useAuth();
    const [subscription, setSubscription] = useState<Subscription | null>(null);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);

    const loadSubscription = useCallback(async () => {
        if (!isAuthenticated) return;
        setLoading(true);
        try {
            setSubscription(await api.getSubscription());
            setError(null);
        } catch (loadError) {
            console.error("Failed to load subscription access:", loadError);
            setError("Subscription access could not be verified.");
        } finally {
            setLoading(false);
        }
    }, [isAuthenticated]);

    useEffect(() => {
        if (!authLoading && !isAuthenticated) {
            router.push("/login");
            return;
        }
        if (isAuthenticated) void loadSubscription();
    }, [authLoading, isAuthenticated, loadSubscription, router]);

    if (authLoading || loading) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-[#050607]">
                <Loader2 className="animate-spin text-[#62d3d0]" size={34} />
            </div>
        );
    }

    const allowed =
        subscription?.status?.toLowerCase() === "active"
        && subscription.feature_access?.[feature] === true;
    if (allowed) return children;

    return (
        <div className="min-h-screen bg-[#050607] px-5 py-10 text-white">
            <div className="mx-auto flex max-w-4xl flex-col items-center text-center">
                <Link href="/" className="mb-16 flex items-center gap-3">
                    <Image
                        src="/icon.png"
                        alt="NoteClaw"
                        width={40}
                        height={40}
                        className="rounded-xl"
                    />
                    <div className="text-left">
                        <div className="font-semibold">NoteClaw</div>
                        <div className="text-[9px] font-semibold uppercase tracking-[0.18em] text-[#62d3d0]">
                            Agent memory
                        </div>
                    </div>
                </Link>

                <div className="flex h-16 w-16 items-center justify-center rounded-2xl bg-[#68408d]/20 text-[#c9a9ea]">
                    <ShieldCheck size={30} />
                </div>
                <h1 className="mt-6 text-3xl font-semibold tracking-tight sm:text-5xl">
                    Choose a plan with {labels[feature]}
                </h1>
                <p className="mt-5 max-w-2xl text-sm leading-7 text-neutral-400 sm:text-base">
                    Your administrator controls which features are included in every
                    free and paid plan. Select a plan that includes this capability,
                    then return here.
                </p>
                {subscription && (
                    <div className="mt-5 rounded-full border border-white/10 bg-white/[0.04] px-4 py-2 text-xs text-neutral-300">
                        Current plan: {subscription.plan_name}
                    </div>
                )}
                {error && (
                    <div className="mt-5 rounded-xl border border-red-400/20 bg-red-400/5 px-4 py-3 text-sm text-red-200">
                        {error}
                    </div>
                )}
                <div className="mt-9 flex w-full max-w-sm flex-col gap-3 sm:flex-row">
                    <Link
                        href="/plans"
                        className="inline-flex flex-1 items-center justify-center gap-2 rounded-full bg-gradient-to-r from-[#318f96] to-[#68408d] px-5 py-3 text-sm font-semibold"
                    >
                        View plans
                        <ArrowRight size={16} />
                    </Link>
                    <button
                        type="button"
                        onClick={() => void loadSubscription()}
                        className="inline-flex flex-1 items-center justify-center gap-2 rounded-full border border-white/12 px-5 py-3 text-sm text-neutral-300 transition hover:border-white/25 hover:text-white"
                    >
                        <RefreshCw size={15} />
                        Check again
                    </button>
                </div>
                <Link
                    href="/dashboard/settings"
                    className="mt-5 text-sm text-neutral-500 transition hover:text-white"
                >
                    Account settings
                </Link>
            </div>
        </div>
    );
}
