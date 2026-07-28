"use client";

import {
    AlertTriangle,
    ArrowLeft,
    Loader2,
    Settings,
    ShieldCheck,
    Trash2,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";

import { useAuth } from "@/lib/auth-context";
import api from "@/lib/api";

export default function AccountSettingsPage() {
    const { user, isLoading, isAuthenticated, logout } = useAuth();
    const router = useRouter();
    const [password, setPassword] = useState("");
    const [confirmation, setConfirmation] = useState("");
    const [isDeleting, setIsDeleting] = useState(false);
    const [error, setError] = useState("");

    useEffect(() => {
        if (!isLoading && !isAuthenticated) router.replace("/login");
    }, [isAuthenticated, isLoading, router]);

    const deleteAccount = async () => {
        if (!password || confirmation !== "DELETE") return;
        setIsDeleting(true);
        setError("");
        try {
            await api.deleteAccount(password);
            logout();
            router.replace("/");
        } catch (deleteError) {
            setError(
                deleteError instanceof Error
                    ? deleteError.message
                    : "Could not delete the account.",
            );
        } finally {
            setIsDeleting(false);
        }
    };

    if (isLoading || !isAuthenticated) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-[#050607]">
                <Loader2 className="animate-spin text-[#62d3d0]" size={34} />
            </div>
        );
    }

    return (
        <main className="min-h-screen bg-[#050607] px-4 py-10 text-white sm:px-6">
            <div className="mx-auto w-full max-w-3xl">
                <Link
                    href="/dashboard"
                    className="mb-8 inline-flex items-center gap-2 text-sm text-neutral-500 transition hover:text-white"
                >
                    <ArrowLeft size={16} />
                    Back to dashboard
                </Link>

                <div className="mb-8 flex items-start gap-4">
                    <div className="rounded-2xl border border-[#62d3d0]/20 bg-[#62d3d0]/10 p-3 text-[#62d3d0]">
                        <Settings size={24} />
                    </div>
                    <div>
                        <h1 className="text-3xl font-semibold tracking-tight">Account settings</h1>
                        <p className="mt-2 text-sm text-neutral-500">{user?.email}</p>
                    </div>
                </div>

                <section className="mb-6 rounded-2xl border border-white/10 bg-[#0a0c0f] p-6">
                    <div className="flex items-start gap-3">
                        <ShieldCheck className="mt-0.5 text-[#62d3d0]" size={20} />
                        <div>
                            <h2 className="font-semibold">Your data boundaries</h2>
                            <p className="mt-2 text-sm leading-6 text-neutral-400">
                                Agent access is controlled per notebook topic. Changing
                                an agent&apos;s allowed topics does not delete the notebook,
                                its sources, or its memories.
                            </p>
                            <Link
                                href="/dashboard/mcp"
                                className="mt-4 inline-flex text-sm font-semibold text-[#62d3d0] hover:text-[#91e2df]"
                            >
                                Manage agent topic access
                            </Link>
                        </div>
                    </div>
                </section>

                <section className="rounded-2xl border border-red-400/20 bg-red-400/[0.04] p-6">
                    <div className="flex items-start gap-3">
                        <AlertTriangle className="mt-0.5 shrink-0 text-red-300" size={20} />
                        <div className="min-w-0 flex-1">
                            <h2 className="font-semibold text-red-100">Delete account</h2>
                            <p className="mt-2 text-sm leading-6 text-neutral-400">
                                This permanently deletes your account, API tokens,
                                agent sessions, topic notebooks, memories, and sources.
                                This action cannot be undone.
                            </p>

                            <div className="mt-5 grid gap-4">
                                <label className="grid gap-2 text-sm">
                                    <span className="text-neutral-300">Current password</span>
                                    <input
                                        type="password"
                                        value={password}
                                        onChange={(event) => setPassword(event.target.value)}
                                        autoComplete="current-password"
                                        className="min-w-0 rounded-xl border border-white/10 bg-black/30 px-4 py-3 outline-none transition focus:border-red-300/50"
                                    />
                                </label>
                                <label className="grid gap-2 text-sm">
                                    <span className="text-neutral-300">
                                        Type <strong>DELETE</strong> to confirm
                                    </span>
                                    <input
                                        value={confirmation}
                                        onChange={(event) => setConfirmation(event.target.value)}
                                        className="min-w-0 rounded-xl border border-white/10 bg-black/30 px-4 py-3 outline-none transition focus:border-red-300/50"
                                    />
                                </label>
                            </div>

                            {error && (
                                <div className="mt-4 rounded-xl border border-red-400/20 bg-red-400/10 px-4 py-3 text-sm text-red-200">
                                    {error}
                                </div>
                            )}

                            <button
                                onClick={deleteAccount}
                                disabled={
                                    isDeleting ||
                                    !password ||
                                    confirmation !== "DELETE"
                                }
                                className="mt-5 inline-flex items-center gap-2 rounded-full bg-red-500 px-5 py-2.5 text-sm font-semibold text-white transition hover:bg-red-400 disabled:cursor-not-allowed disabled:opacity-40"
                            >
                                {isDeleting ? (
                                    <Loader2 className="animate-spin" size={16} />
                                ) : (
                                    <Trash2 size={16} />
                                )}
                                Delete my account
                            </button>
                        </div>
                    </div>
                </section>
            </div>
        </main>
    );
}
