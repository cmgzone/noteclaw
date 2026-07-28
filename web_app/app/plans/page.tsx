"use client";

import React, { useEffect, useState } from "react";
import {
    Check,
    Zap,
    Crown,
    Rocket,
    ArrowLeft,
    Loader2
} from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { motion } from "framer-motion";
import { useAuth } from "@/lib/auth-context";
import api, { PlanFeatureAccess, Subscription } from "@/lib/api";

interface Plan {
    id: string;
    name: string;
    description: string;
    credits_per_month: number;
    price: string;
    is_free_plan: boolean;
    feature_access: PlanFeatureAccess;
}

const featureLabels: Array<[keyof PlanFeatureAccess, string]> = [
    ["memory_bank", "Durable agent memory"],
    ["notebook_chat", "Chat with memory notebooks"],
    ["websocket_collaboration", "Shared WebSocket sessions"],
    ["code_review", "Agent code review"],
    ["web_search", "Live web search"],
    ["deep_research", "Deep research reports"],
    ["research_save_to_notebook", "Save research to notebooks"],
];

export default function PlansPage() {
    const { isAuthenticated, isLoading: authLoading } = useAuth();
    const router = useRouter();
    const [plans, setPlans] = useState<Plan[]>([]);
    const [currentSubscription, setCurrentSubscription] = useState<Subscription | null>(null);
    const [isLoading, setIsLoading] = useState(true);
    const [upgrading, setUpgrading] = useState<string | null>(null);

    useEffect(() => {
        if (!authLoading) {
            loadData();
        }
    }, [authLoading, isAuthenticated, router]);

    const loadData = async () => {
        setIsLoading(true);
        try {
            const plansData = await api.getPlans();
            setPlans(plansData);
            if (isAuthenticated) {
                const subData = await api.getSubscription();
                setCurrentSubscription(subData);
            } else {
                setCurrentSubscription(null);
            }
        } catch (error) {
            console.error("Failed to load plans:", error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleUpgrade = async (planId: string, isFree: boolean) => {
        if (!isAuthenticated) {
            router.push(`/signup?plan=${encodeURIComponent(planId)}`);
            return;
        }

        if (isFree) {
            // For downgrading to free, just show a message
            alert("To downgrade to the Free plan, please contact support or wait for your current subscription to expire.");
            return;
        }

        setUpgrading(planId);
        try {
            // Create a Stripe Checkout Session
            const { url } = await api.createCheckoutSession(planId);

            if (url) {
                // Redirect to Stripe Checkout
                window.location.href = url;
            } else {
                throw new Error("No checkout URL returned");
            }
        } catch (error: any) {
            console.error("Upgrade failed:", error);
            alert(error.message || "Failed to start checkout. Please try again.");
        } finally {
            setUpgrading(null);
        }
    };

    const getPlanIcon = (name: string) => {
        switch (name.toLowerCase()) {
            case 'pro': return <Crown className="text-[#a8ebe7]" size={24} />;
            case 'ultra': return <Rocket className="text-[#d5b5ef]" size={24} />;
            default: return <Zap className="text-[#62d3d0]" size={24} />;
        }
    };

    const getPlanColor = (name: string) => {
        switch (name.toLowerCase()) {
            case 'pro': return 'from-[#318f96] to-[#68408d]';
            case 'ultra': return 'from-[#68408d] to-[#3d2556]';
            default: return 'from-[#1d5c63] to-[#412b55]';
        }
    };

    if (authLoading || isLoading) {
        return (
            <div className="min-h-screen bg-neutral-950 flex items-center justify-center">
                <Loader2 className="animate-spin text-[#62d3d0]" size={40} />
            </div>
        );
    }

    return (
        <div className="min-h-screen bg-neutral-950 text-white">
            <nav className="border-b border-white/5 bg-neutral-900/50 backdrop-blur-xl">
                <div className="container mx-auto flex h-16 items-center justify-between px-6">
                    <Link href={isAuthenticated ? "/dashboard" : "/"} className="flex items-center gap-2 text-neutral-400 hover:text-white transition-colors">
                        <ArrowLeft size={20} />
                        <span>{isAuthenticated ? "Back to Dashboard" : "Back to home"}</span>
                    </Link>
                    <Link href="/" className="flex items-center gap-2">
                        <Image src="/icon.png" alt="NoteClaw" width={24} height={24} className="rounded-md" />
                        <span className="font-bold tracking-tight">NoteClaw</span>
                    </Link>
                </div>
            </nav>

            <main className="container mx-auto px-6 py-12">
                <div className="text-center mb-12">
                    <div className="mb-3 text-xs font-semibold uppercase tracking-[0.2em] text-[#62d3d0]">
                        Subscription
                    </div>
                    <h1 className="text-4xl font-bold tracking-tight mb-4">Choose what your agents can do</h1>
                    <p className="text-neutral-400 text-lg max-w-2xl mx-auto">
                        Every plan publishes its exact memory, collaboration, review, and research access.
                    </p>
                </div>

                <div
                    className={
                        plans.length <= 2
                            ? "mx-auto grid max-w-4xl gap-8 md:grid-cols-2"
                            : "mx-auto grid max-w-6xl gap-8 md:grid-cols-3"
                    }
                >
                    {plans.map((plan, i) => {
                        const isCurrentPlan = currentSubscription?.plan_id === plan.id;
                        const isPremium = !plan.is_free_plan;

                        return (
                            <motion.div
                                key={plan.id}
                                initial={{ opacity: 0, y: 20 }}
                                animate={{ opacity: 1, y: 0 }}
                                transition={{ delay: i * 0.1 }}
                                className={`relative rounded-2xl border ${isCurrentPlan
                                    ? 'border-[#62d3d0]/50 ring-2 ring-[#62d3d0]/20'
                                    : 'border-white/5'
                                    } bg-neutral-900/50 p-8 backdrop-blur-sm`}
                            >
                                {isCurrentPlan && (
                                    <div className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-1 bg-[#68408d] text-xs font-bold rounded-full">
                                        Current Plan
                                    </div>
                                )}

                                <div className="flex items-center gap-3 mb-4">
                                    <div className={`p-3 rounded-xl bg-gradient-to-br ${getPlanColor(plan.name)}`}>
                                        {getPlanIcon(plan.name)}
                                    </div>
                                    <div>
                                        <h3 className="text-xl font-bold">{plan.name}</h3>
                                        <p className="text-sm text-neutral-400">{plan.description}</p>
                                    </div>
                                </div>

                                <div className="my-6">
                                    <span className="text-4xl font-bold">${parseFloat(plan.price).toFixed(2)}</span>
                                    <span className="text-neutral-400">/month</span>
                                </div>

                                <ul className="space-y-3 mb-8">
                                    <li className="flex items-center gap-2 text-sm">
                                        <Check size={16} className="text-[#62d3d0]" />
                                        <span>{plan.credits_per_month.toLocaleString()} credits/month</span>
                                    </li>
                                    {featureLabels
                                        .filter(([key]) => plan.feature_access?.[key] === true)
                                        .map(([key, label]) => (
                                            <li key={key} className="flex items-center gap-2 text-sm">
                                                <Check size={16} className="text-[#62d3d0]" />
                                                <span>{label}</span>
                                            </li>
                                        ))}
                                    {featureLabels.every(
                                        ([key]) => plan.feature_access?.[key] !== true,
                                    ) && (
                                        <li className="text-sm text-neutral-500">
                                            Account and subscription management only
                                        </li>
                                    )}
                                </ul>

                                <button
                                    onClick={() => handleUpgrade(plan.id, plan.is_free_plan)}
                                    disabled={isCurrentPlan || upgrading === plan.id}
                                    className={`w-full py-3 rounded-lg font-semibold transition-all ${isCurrentPlan
                                        ? 'bg-neutral-800 text-neutral-500 cursor-not-allowed'
                                        : isPremium
                                            ? 'bg-gradient-to-r from-[#318f96] to-[#68408d] hover:brightness-110 text-white'
                                            : 'bg-white/10 hover:bg-white/20 text-white border border-white/10'
                                        }`}
                                >
                                    {upgrading === plan.id ? (
                                        <Loader2 className="animate-spin mx-auto" size={20} />
                                    ) : isCurrentPlan ? (
                                        'Current Plan'
                                    ) : !isAuthenticated ? (
                                        'Create account'
                                    ) : plan.is_free_plan ? (
                                        'Downgrade'
                                    ) : (
                                        'Upgrade Now'
                                    )}
                                </button>
                            </motion.div>
                        );
                    })}
                </div>

                <section className="mx-auto mt-10 max-w-4xl rounded-2xl border border-white/10 bg-neutral-900/60 p-6">
                    <div className="flex flex-col gap-2 sm:flex-row sm:items-end sm:justify-between">
                        <div>
                            <p className="text-xs font-semibold uppercase tracking-[0.18em] text-[#62d3d0]">
                                Credit usage
                            </p>
                            <h2 className="mt-2 text-xl font-semibold">Pay only for model-powered work</h2>
                        </div>
                        <p className="max-w-md text-sm text-neutral-400">
                            Failed operations are refunded. Memory storage, retrieval, WebSocket collaboration,
                            and saving finished research are free.
                        </p>
                    </div>
                    <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-5">
                        {[
                            ["Notebook chat", "1 credit"],
                            ["Web search", "1 credit"],
                            ["Code review", "2 credits"],
                            ["Deep research", "5 credits"],
                            ["Deep depth", "10 credits"],
                        ].map(([label, cost]) => (
                            <div key={label} className="rounded-xl border border-white/5 bg-black/20 px-4 py-3">
                                <div className="text-sm text-neutral-400">{label}</div>
                                <div className="mt-1 font-semibold text-white">{cost}</div>
                            </div>
                        ))}
                    </div>
                </section>

                <div className="mt-8 text-center text-neutral-500 text-sm">
                    <p>Plan access is controlled centrally by your NoteClaw administrator.</p>
                </div>
            </main>
        </div>
    );
}
