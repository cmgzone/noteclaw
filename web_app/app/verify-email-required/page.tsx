"use client";

import { useEffect, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { AlertCircle, CheckCircle2, Loader2, Mail } from "lucide-react";
import api from "@/lib/api";

export default function VerifyEmailRequiredPage() {
    const [email, setEmail] = useState("");
    const [initiallySent, setInitiallySent] = useState(false);
    const [isSending, setIsSending] = useState(false);
    const [message, setMessage] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);

    useEffect(() => {
        const params = new URLSearchParams(window.location.search);
        setEmail(params.get("email") || "");
        setInitiallySent(params.get("sent") === "true");
    }, []);

    const resend = async () => {
        if (!email) return;
        setIsSending(true);
        setError(null);
        setMessage(null);
        try {
            const response = await api.resendVerification(email);
            setMessage(response.message || "A new verification email has been sent.");
        } catch (err: any) {
            setError(err.message || "The verification email could not be sent.");
        } finally {
            setIsSending(false);
        }
    };

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-950 px-4">
            <div className="w-full max-w-md space-y-6 rounded-2xl border border-white/5 bg-neutral-900/60 p-8 text-center shadow-2xl backdrop-blur-xl">
                <Link href="/" className="inline-block">
                    <Image src="/icon.png" alt="NoteClaw" width={52} height={52} className="mx-auto rounded-xl" />
                </Link>
                <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full bg-[#62d3d0]/10 text-[#62d3d0]">
                    <Mail size={28} />
                </div>
                <div>
                    <h1 className="text-3xl font-bold text-white">Verify your email</h1>
                    <p className="mt-3 text-sm leading-6 text-neutral-400">
                        {initiallySent ? "We sent a verification link to" : "Use the button below to send a verification link to"}
                        {email && <span className="block font-medium text-neutral-200">{email}</span>}
                    </p>
                </div>

                {message && (
                    <div className="flex items-start gap-2 rounded-lg border border-green-500/20 bg-green-500/10 p-3 text-left text-sm text-green-400">
                        <CheckCircle2 size={18} className="mt-0.5 shrink-0" />
                        {message}
                    </div>
                )}
                {error && (
                    <div className="flex items-start gap-2 rounded-lg border border-red-500/20 bg-red-500/10 p-3 text-left text-sm text-red-400">
                        <AlertCircle size={18} className="mt-0.5 shrink-0" />
                        {error}
                    </div>
                )}

                <button
                    type="button"
                    onClick={resend}
                    disabled={!email || isSending}
                    className="flex w-full items-center justify-center rounded-lg bg-[#62d3d0] px-4 py-2.5 font-semibold text-neutral-950 transition hover:bg-[#a8ebe7] disabled:cursor-not-allowed disabled:opacity-50"
                >
                    {isSending ? <Loader2 className="animate-spin" size={20} /> : "Resend verification email"}
                </button>
                <p className="text-sm text-neutral-400">
                    Already verified? <Link href="/login" className="font-medium text-[#62d3d0] hover:text-[#a8ebe7]">Sign in</Link>
                </p>
            </div>
        </div>
    );
}
