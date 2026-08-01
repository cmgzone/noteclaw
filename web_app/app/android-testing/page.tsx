"use client";

import { useState } from "react";
import Image from "next/image";
import Link from "next/link";
import {
  AlertCircle,
  ArrowLeft,
  CheckCircle2,
  ExternalLink,
  Loader2,
  Mail,
  ShieldCheck,
  Smartphone,
} from "lucide-react";
import { api, type PlayTestingJoinResponse } from "@/lib/api";

export default function AndroidTestingPage() {
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [website, setWebsite] = useState("");
  const [consent, setConsent] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<PlayTestingJoinResponse | null>(null);

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setError(null);
    setLoading(true);

    try {
      const response = await api.joinPlayTesting({
        email,
        displayName: displayName || undefined,
        consent,
        website,
      });
      setResult(response);
    } catch (submitError) {
      setError(
        submitError instanceof Error
          ? submitError.message
          : "We could not save your tester request. Please try again.",
      );
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="min-h-screen bg-[#050914] px-4 py-10 text-white sm:px-6">
      <div className="mx-auto max-w-5xl">
        <div className="mb-8 flex items-center justify-between gap-4">
          <Link href="/" className="flex items-center gap-3 text-sm text-slate-300 transition hover:text-white">
            <ArrowLeft className="h-4 w-4" />
            Back to NoteClaw
          </Link>
          <div className="flex items-center gap-2">
            <Image src="/icon.png" alt="NoteClaw" width={34} height={34} className="rounded-lg" />
            <span className="font-semibold">NoteClaw</span>
          </div>
        </div>

        <div className="grid overflow-hidden rounded-[2rem] border border-cyan-300/15 bg-slate-950/80 shadow-2xl shadow-cyan-950/30 lg:grid-cols-[1.05fr_0.95fr]">
          <section className="relative overflow-hidden border-b border-white/10 p-8 sm:p-12 lg:border-b-0 lg:border-r">
            <div className="absolute -left-24 -top-24 h-64 w-64 rounded-full bg-cyan-400/10 blur-3xl" />
            <div className="relative">
              <div className="mb-7 inline-flex items-center gap-2 rounded-full border border-emerald-300/20 bg-emerald-300/10 px-3 py-1.5 text-xs font-semibold uppercase tracking-[0.18em] text-emerald-300">
                <Smartphone className="h-4 w-4" />
                Android closed test
              </div>
              <h1 className="max-w-xl text-4xl font-bold tracking-tight sm:text-5xl">
                Test NoteClaw before the public release.
              </h1>
              <p className="mt-5 max-w-xl text-base leading-7 text-slate-300">
                Join with the Google Account you use on your Android phone. We will email your official Google Play testing link immediately.
              </p>

              <div className="mt-10 space-y-5">
                {[
                  [Mail, "Receive the private Play testing invite by email"],
                  [ShieldCheck, "Install and update securely through Google Play"],
                  [CheckCircle2, "Share private feedback before the public launch"],
                ].map(([Icon, label]) => (
                  <div key={label as string} className="flex items-center gap-3 text-sm text-slate-200">
                    <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-cyan-300/10 text-cyan-300">
                      <Icon className="h-5 w-5" />
                    </span>
                    <span>{label as string}</span>
                  </div>
                ))}
              </div>

              <p className="mt-10 text-xs leading-5 text-slate-500">
                Google Play requires a Gmail or Google Workspace account. Closed-test access is controlled by the tester list in Play Console.
              </p>
            </div>
          </section>

          <section className="p-8 sm:p-12">
            {result ? (
              <div className="flex h-full flex-col justify-center">
                <span className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-emerald-400/10 text-emerald-300">
                  <CheckCircle2 className="h-8 w-8" />
                </span>
                <h2 className="text-3xl font-bold">You&apos;re on the tester list.</h2>
                <p className="mt-3 leading-7 text-slate-300">
                  {result.emailSent
                    ? `We sent the Google Play invite to ${email}. Check your inbox and spam folder.`
                    : "Your request was saved, but email delivery is delayed. You can still open the Play invite below."}
                </p>
                {result.groupUrl && (
                  <a
                    href={result.groupUrl}
                    target="_blank"
                    rel="noreferrer"
                    className="mt-7 inline-flex items-center justify-center gap-2 rounded-xl border border-cyan-300/30 px-5 py-3 font-semibold text-cyan-200 transition hover:bg-cyan-300/10"
                  >
                    Join tester group first
                    <ExternalLink className="h-4 w-4" />
                  </a>
                )}
                <a
                  href={result.optInUrl}
                  target="_blank"
                  rel="noreferrer"
                  className="mt-3 inline-flex items-center justify-center gap-2 rounded-xl bg-cyan-300 px-5 py-3 font-bold text-slate-950 transition hover:bg-cyan-200"
                >
                  Open Google Play invite
                  <ExternalLink className="h-4 w-4" />
                </a>
                <button
                  type="button"
                  onClick={() => {
                    setResult(null);
                    setEmail("");
                    setDisplayName("");
                    setConsent(false);
                  }}
                  className="mt-5 text-sm text-slate-400 transition hover:text-white"
                >
                  Add another tester
                </button>
              </div>
            ) : (
              <>
                <h2 className="text-2xl font-bold">Join the testing group</h2>
                <p className="mt-2 text-sm leading-6 text-slate-400">
                  Enter the Google Account that should receive Play Store access.
                </p>

                {error && (
                  <div className="mt-6 flex gap-3 rounded-xl border border-red-400/20 bg-red-400/10 p-4 text-sm text-red-200">
                    <AlertCircle className="mt-0.5 h-5 w-5 shrink-0" />
                    <span>{error}</span>
                  </div>
                )}

                <form onSubmit={handleSubmit} className="mt-7 space-y-5">
                  <div>
                    <label htmlFor="tester-name" className="text-sm font-medium text-slate-200">
                      Name <span className="text-slate-500">(optional)</span>
                    </label>
                    <input
                      id="tester-name"
                      value={displayName}
                      onChange={(event) => setDisplayName(event.target.value)}
                      maxLength={80}
                      autoComplete="name"
                      placeholder="Your name"
                      className="mt-2 w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 outline-none transition placeholder:text-slate-600 focus:border-cyan-300/60 focus:ring-2 focus:ring-cyan-300/10"
                    />
                  </div>
                  <div>
                    <label htmlFor="tester-email" className="text-sm font-medium text-slate-200">
                      Google Account email
                    </label>
                    <input
                      id="tester-email"
                      type="email"
                      value={email}
                      onChange={(event) => setEmail(event.target.value)}
                      required
                      autoComplete="email"
                      placeholder="you@gmail.com"
                      className="mt-2 w-full rounded-xl border border-white/10 bg-white/5 px-4 py-3 outline-none transition placeholder:text-slate-600 focus:border-cyan-300/60 focus:ring-2 focus:ring-cyan-300/10"
                    />
                  </div>
                  <div className="hidden" aria-hidden="true">
                    <label htmlFor="tester-website">Website</label>
                    <input
                      id="tester-website"
                      tabIndex={-1}
                      autoComplete="off"
                      value={website}
                      onChange={(event) => setWebsite(event.target.value)}
                    />
                  </div>
                  <label className="flex cursor-pointer items-start gap-3 rounded-xl border border-white/10 bg-white/[0.03] p-4 text-sm leading-6 text-slate-300">
                    <input
                      type="checkbox"
                      checked={consent}
                      onChange={(event) => setConsent(event.target.checked)}
                      required
                      className="mt-1 h-4 w-4 accent-cyan-300"
                    />
                    <span>I agree to receive the NoteClaw testing invite and essential testing updates by email.</span>
                  </label>
                  <button
                    type="submit"
                    disabled={loading}
                    className="flex w-full items-center justify-center gap-2 rounded-xl bg-cyan-300 px-5 py-3.5 font-bold text-slate-950 transition hover:bg-cyan-200 disabled:cursor-not-allowed disabled:opacity-60"
                  >
                    {loading ? <Loader2 className="h-5 w-5 animate-spin" /> : <Mail className="h-5 w-5" />}
                    {loading ? "Joining…" : "Join and email my Play link"}
                  </button>
                </form>
              </>
            )}
          </section>
        </div>
      </div>
    </main>
  );
}
