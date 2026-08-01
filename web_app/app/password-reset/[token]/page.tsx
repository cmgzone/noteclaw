"use client";

import { FormEvent, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { AlertCircle, CheckCircle2, Loader2 } from "lucide-react";
import { useParams } from "next/navigation";
import api from "@/lib/api";

export default function PasswordResetPage() {
    const params = useParams<{ token: string }>();
    const token = typeof params.token === "string" ? params.token : "";
    const [password, setPassword] = useState("");
    const [confirmation, setConfirmation] = useState("");
    const [loading, setLoading] = useState(false);
    const [success, setSuccess] = useState(false);
    const [error, setError] = useState<string | null>(null);

    const submit = async (event: FormEvent) => {
        event.preventDefault();
        setError(null);
        if (password.length < 8) {
            setError("Password must be at least 8 characters.");
            return;
        }
        if (password !== confirmation) {
            setError("Passwords do not match.");
            return;
        }
        setLoading(true);
        try {
            await api.resetPassword(token, password);
            setSuccess(true);
        } catch (err: any) {
            setError(err.message || "This reset link is invalid or expired.");
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-950 px-4">
            <div className="w-full max-w-md space-y-6 rounded-2xl border border-white/5 bg-neutral-900/60 p-8 shadow-2xl backdrop-blur-xl">
                <div className="text-center">
                    <Link href="/"><Image src="/icon.png" alt="NoteClaw" width={52} height={52} className="mx-auto rounded-xl" /></Link>
                    <h1 className="mt-5 text-3xl font-bold text-white">Choose a new password</h1>
                    <p className="mt-2 text-sm text-neutral-400">Use at least eight characters.</p>
                </div>

                {success ? (
                    <div className="space-y-5 text-center">
                        <CheckCircle2 className="mx-auto text-green-400" size={40} />
                        <p className="text-sm text-neutral-300">Your password has been updated successfully.</p>
                        <Link href="/login" className="block rounded-lg bg-[#62d3d0] px-4 py-2.5 font-semibold text-neutral-950 hover:bg-[#a8ebe7]">Sign in</Link>
                    </div>
                ) : (
                    <form onSubmit={submit} className="space-y-4">
                        {error && (
                            <div className="flex items-start gap-2 rounded-lg border border-red-500/20 bg-red-500/10 p-3 text-sm text-red-400">
                                <AlertCircle size={18} className="mt-0.5 shrink-0" />{error}
                            </div>
                        )}
                        <div>
                            <label htmlFor="password" className="block text-sm font-medium text-neutral-200">New password</label>
                            <input id="password" type="password" autoComplete="new-password" required value={password} onChange={(event) => setPassword(event.target.value)} className="mt-1 w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white outline-none focus:border-[#62d3d0]" />
                        </div>
                        <div>
                            <label htmlFor="confirmation" className="block text-sm font-medium text-neutral-200">Confirm password</label>
                            <input id="confirmation" type="password" autoComplete="new-password" required value={confirmation} onChange={(event) => setConfirmation(event.target.value)} className="mt-1 w-full rounded-lg border border-white/10 bg-neutral-800/50 px-3 py-2 text-white outline-none focus:border-[#62d3d0]" />
                        </div>
                        <button type="submit" disabled={loading || !token} className="flex w-full items-center justify-center rounded-lg bg-[#62d3d0] px-4 py-2.5 font-semibold text-neutral-950 hover:bg-[#a8ebe7] disabled:opacity-50">
                            {loading ? <Loader2 className="animate-spin" size={20} /> : "Update password"}
                        </button>
                    </form>
                )}
            </div>
        </div>
    );
}
