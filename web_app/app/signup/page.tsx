"use client";

import React, { useState } from "react";
import { Loader2, ArrowRight, AlertCircle } from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { useAuth } from "@/lib/auth-context";

export default function SignupPage() {
    const [displayName, setDisplayName] = useState("");
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [isLoading, setIsLoading] = useState(false);
    const [error, setError] = useState<string | null>(null);
    const router = useRouter();
    const { signup } = useAuth();

    const handleSignup = async (e: React.FormEvent) => {
        e.preventDefault();
        setError(null);

        if (password !== confirmPassword) {
            setError("Passwords do not match.");
            return;
        }

        setIsLoading(true);
        try {
            await signup(email, password, displayName || undefined);
            const selectedPlan =
                typeof window !== "undefined"
                    ? new URLSearchParams(window.location.search).get("plan")
                    : null;
            router.push(
                selectedPlan
                    ? `/plans?selected=${encodeURIComponent(selectedPlan)}`
                    : "/dashboard",
            );
        } catch (err: any) {
            setError(err.message || "Signup failed. Please try again.");
        } finally {
            setIsLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-950 px-4">
            <div className="w-full max-w-md space-y-8 rounded-2xl border border-white/5 bg-neutral-900/50 p-8 backdrop-blur-xl shadow-2xl">
                <div className="text-center">
                    <Link href="/" className="inline-block transition-transform hover:scale-105">
                        <Image src="/icon.png" alt="NoteClaw" width={48} height={48} className="mx-auto rounded-xl drop-shadow-md" />
                    </Link>
                    <h2 className="mt-6 text-3xl font-bold tracking-tight text-white">
                        Create your account
                    </h2>
                    <p className="mt-2 text-sm text-neutral-400">
                        Sign up to manage your subscription and access your notebooks
                    </p>
                </div>

                {error && (
                    <div className="flex items-center gap-2 rounded-lg bg-red-500/10 border border-red-500/20 p-3 text-red-400 text-sm">
                        <AlertCircle size={18} />
                        {error}
                    </div>
                )}

                <form className="mt-8 space-y-6" onSubmit={handleSignup}>
                    <div className="space-y-4">
                        <div>
                            <label htmlFor="displayName" className="block text-sm font-medium text-neutral-200">
                                Display name
                            </label>
                            <input
                                id="displayName"
                                name="displayName"
                                type="text"
                                value={displayName}
                                onChange={(e) => setDisplayName(e.target.value)}
                                className="mt-1 block w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white placeholder-neutral-500 focus:border-[#62d3d0] focus:ring-1 focus:ring-[#62d3d0] focus:outline-none transition-all"
                                placeholder="Your name"
                            />
                        </div>
                        <div>
                            <label htmlFor="email" className="block text-sm font-medium text-neutral-200">
                                Email address
                            </label>
                            <input
                                id="email"
                                name="email"
                                type="email"
                                autoComplete="email"
                                required
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                                className="mt-1 block w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white placeholder-neutral-500 focus:border-[#62d3d0] focus:ring-1 focus:ring-[#62d3d0] focus:outline-none transition-all"
                                placeholder="you@example.com"
                            />
                        </div>
                        <div>
                            <label htmlFor="password" className="block text-sm font-medium text-neutral-200">
                                Password
                            </label>
                            <input
                                id="password"
                                name="password"
                                type="password"
                                autoComplete="new-password"
                                required
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                                className="mt-1 block w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white placeholder-neutral-500 focus:border-[#62d3d0] focus:ring-1 focus:ring-[#62d3d0] focus:outline-none transition-all"
                                placeholder="••••••••"
                            />
                        </div>
                        <div>
                            <label htmlFor="confirmPassword" className="block text-sm font-medium text-neutral-200">
                                Confirm password
                            </label>
                            <input
                                id="confirmPassword"
                                name="confirmPassword"
                                type="password"
                                autoComplete="new-password"
                                required
                                value={confirmPassword}
                                onChange={(e) => setConfirmPassword(e.target.value)}
                                className="mt-1 block w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white placeholder-neutral-500 focus:border-[#62d3d0] focus:ring-1 focus:ring-[#62d3d0] focus:outline-none transition-all"
                                placeholder="••••••••"
                            />
                        </div>
                    </div>

                    <button
                        type="submit"
                        disabled={isLoading}
                        className="group relative flex w-full justify-center rounded-lg bg-gradient-to-r from-[#318f96] to-[#68408d] px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 focus:outline-none focus:ring-2 focus:ring-[#62d3d0] focus:ring-offset-2 focus:ring-offset-neutral-900 disabled:opacity-50 disabled:cursor-not-allowed transition-all"
                    >
                        {isLoading ? (
                            <Loader2 className="animate-spin" size={20} />
                        ) : (
                            <span className="flex items-center gap-2">
                                Create account
                                <ArrowRight size={16} className="group-hover:translate-x-1 transition-transform" />
                            </span>
                        )}
                    </button>

                    <p className="text-center text-sm text-neutral-400">
                        Already have an account?{" "}
                        <Link href="/login" className="text-[#62d3d0] hover:text-[#a8ebe7] font-medium">
                            Sign in
                        </Link>
                    </p>
                </form>
            </div>
        </div>
    );
}
