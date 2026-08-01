"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { AlertCircle, CheckCircle2, Loader2 } from "lucide-react";
import { useParams } from "next/navigation";
import api from "@/lib/api";

export default function VerifyEmailPage() {
    const params = useParams<{ token: string }>();
    const token = typeof params.token === "string" ? params.token : "";
    const started = useRef(false);
    const [state, setState] = useState<"loading" | "success" | "error">("loading");
    const [message, setMessage] = useState("Verifying your email address...");

    useEffect(() => {
        if (!token || started.current) return;
        started.current = true;
        api.verifyEmail(token)
            .then((response) => {
                setState("success");
                setMessage(response.message || "Your email has been verified.");
            })
            .catch((error: Error) => {
                setState("error");
                setMessage(error.message || "This verification link is invalid or expired.");
            });
    }, [token]);

    return (
        <div className="min-h-screen flex items-center justify-center bg-neutral-950 px-4">
            <div className="w-full max-w-md space-y-6 rounded-2xl border border-white/5 bg-neutral-900/60 p-8 text-center shadow-2xl backdrop-blur-xl">
                <Link href="/"><Image src="/icon.png" alt="NoteClaw" width={52} height={52} className="mx-auto rounded-xl" /></Link>
                <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-white/5">
                    {state === "loading" && <Loader2 className="animate-spin text-[#62d3d0]" size={32} />}
                    {state === "success" && <CheckCircle2 className="text-green-400" size={36} />}
                    {state === "error" && <AlertCircle className="text-red-400" size={36} />}
                </div>
                <div>
                    <h1 className="text-3xl font-bold text-white">
                        {state === "loading" ? "Verifying email" : state === "success" ? "Email verified" : "Verification failed"}
                    </h1>
                    <p className="mt-3 text-sm leading-6 text-neutral-400">{message}</p>
                </div>
                {state !== "loading" && (
                    <Link href="/login" className="block w-full rounded-lg bg-[#62d3d0] px-4 py-2.5 font-semibold text-neutral-950 transition hover:bg-[#a8ebe7]">
                        Continue to sign in
                    </Link>
                )}
            </div>
        </div>
    );
}
