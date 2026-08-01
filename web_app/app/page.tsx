"use client";

import { useEffect, useRef, useState } from "react";
import Image from "next/image";
import Link from "next/link";
import { motion, AnimatePresence } from "framer-motion";
import {
  ArrowRight,
  BookOpen,
  Radio,
  Database,
  BadgeCheck,
  MessageSquare,
  Bot,
  KeyRound,
  BookMarked,
  Boxes,
  Copy,
  Check,
  Terminal,
  ShieldCheck,
  Plus,
} from "lucide-react";
import {
  siClaude,
  siGooglegemini,
  siGithubcopilot,
  siCursor,
  siWindsurf,
  siHermes,
} from "simple-icons";

const OPENAI_D =
  "M22.2819 9.8211a5.9847 5.9847 0 0 0-.5157-4.9108 6.0462 6.0462 0 0 0-6.5098-2.9A6.0651 6.0651 0 0 0 4.9807 4.1818a5.9847 5.9847 0 0 0-3.9977 2.9 6.0462 6.0462 0 0 0 .7427 7.0966 5.98 5.98 0 0 0 .511 4.9107 6.051 6.051 0 0 0 6.5146 2.9001A5.9847 5.9847 0 0 0 13.2599 24a6.0557 6.0557 0 0 0 5.7718-4.2058 5.9894 5.9894 0 0 0 3.9977-2.9001 6.0557 6.0557 0 0 0-.7475-7.0729zm-9.022 12.6081a4.4755 4.4755 0 0 1-2.8764-1.0408l.1419-.0804 4.7783-2.7582a.7948.7948 0 0 0 .3927-.6813v-6.7369l2.02 1.1686a.071.071 0 0 1 .038.052v5.5826a4.504 4.504 0 0 1-4.4945 4.4944zm-9.6607-4.1254a4.4708 4.4708 0 0 1-.5346-3.0137l.142.0852 4.783 2.7582a.7712.7712 0 0 0 .7806 0l5.8428-3.3685v2.3324a.0804.0804 0 0 1-.0332.0615L9.74 19.9502a4.4992 4.4992 0 0 1-6.1408-1.6464zM2.3408 7.8956a4.485 4.485 0 0 1 2.3655-1.9728V11.6a.7664.7664 0 0 0 .3879.6765l5.8144 3.3543-2.0201 1.1685a.0757.0757 0 0 1-.071 0l-4.8303-2.7865A4.504 4.504 0 0 1 2.3408 7.872zm16.5963 3.8558L13.1038 8.364 15.1192 7.2a.0757.0757 0 0 1 .071 0l4.8303 2.7913a4.4944 4.4944 0 0 1-.6765 8.1042v-5.6772a.79.79 0 0 0-.407-.667zm2.0107-3.0231l-.142-.0852-4.7735-2.7818a.7759.7759 0 0 0-.7854 0L9.409 9.2297V6.8974a.0662.0662 0 0 1 .0284-.0615l4.8303-2.7866a4.4992 4.4992 0 0 1 6.6802 4.66zM8.3065 12.863l-2.02-1.1638a.0804.0804 0 0 1-.038-.0567V6.0742a4.4992 4.4992 0 0 1 7.3757-3.4537l-.142.0805L8.704 5.459a.7948.7948 0 0 0-.3927.6813zm1.0976-2.3654l2.602-1.4998 2.6069 1.4998v2.9994l-2.5974 1.4997-2.6067-1.4997Z";

const KIRO_D =
  "M5 3h3.4v6.9L14.3 3h4.4l-6.8 7.9L19 21h-4.4l-5.3-6.6V21H5V3z";

const OPENCLAW_D =
  "M3 21l4-16h2.6L5.6 21H3Zm6.5 0l4-16h2.6l-4 16H9.5Zm6.5 0l4-16h2.6l-4 16H16Z";

type Agent = {
  name: string;
  by: string;
  transport: string;
  hue: string;
  d: string;
};

const AGENTS: Agent[] = [
  { name: "Claude Code", by: "Anthropic", transport: "MCP native", hue: "#e08a5b", d: siClaude.path },
  { name: "Codex", by: "OpenAI", transport: "MCP stream", hue: "#3fcf8e", d: OPENAI_D },
  { name: "Gemini CLI", by: "Google", transport: "MCP native", hue: "#7ba8ff", d: siGooglegemini.path },
  { name: "GitHub Copilot", by: "GitHub", transport: "Context memory", hue: "#a78bfa", d: siGithubcopilot.path },
  { name: "Cursor", by: "Anysphere", transport: "Context memory", hue: "#4dd6e8", d: siCursor.path },
  { name: "Windsurf", by: "Cognition", transport: "Gateway ready", hue: "#5fd4c4", d: siWindsurf.path },
  { name: "Hermes", by: "Nous Research", transport: "Live WebSocket", hue: "#f2b544", d: siHermes.path },
  { name: "Kiro", by: "AWS", transport: "Realtime gateway", hue: "#f27e9d", d: KIRO_D },
  { name: "OpenClaw", by: "Autonomous", transport: "Full memory stack", hue: "#5fd4c4", d: OPENCLAW_D },
];

const APP_SCREENS = [
  {
    src: "/screenshots/app-memory.png",
    eyebrow: "01 / MEMORY",
    title: "Memory bank",
    alt: "NoteClaw Android app showing pinned notebooks and shared agent memories",
  },
  {
    src: "/screenshots/app-agents.png",
    eyebrow: "02 / AGENTS",
    title: "Connected agents",
    alt: "NoteClaw Android app showing live MCP agent connections and shared sessions",
  },
  {
    src: "/screenshots/app-chat.png",
    eyebrow: "03 / CHAT",
    title: "Shared memory chat",
    alt: "NoteClaw Android app showing a conversation with a coding agent",
  },
  {
    src: "/screenshots/app-mission-control.png",
    eyebrow: "04 / PLAN",
    title: "Mission control",
    alt: "NoteClaw Android app showing a synchronized project mission-control workspace",
  },
  {
    src: "/screenshots/app-fact-check.png",
    eyebrow: "05 / VERIFY",
    title: "Fact checking",
    alt: "NoteClaw Android app showing the evidence-backed fact verification workspace",
  },
  {
    src: "/screenshots/app-code-review.png",
    eyebrow: "06 / REVIEW",
    title: "Code review",
    alt: "NoteClaw Android app showing the multi-lens code review console",
  },
] as const;

function AgentIcon({ d, className, style }: { d: string; className?: string; style?: React.CSSProperties }) {
  return (
    <svg viewBox="0 0 24 24" className={className} style={style} fill="currentColor" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}

function Reveal({
  children,
  delay = 0,
  className,
}: {
  children: React.ReactNode;
  delay?: number;
  className?: string;
}) {
  return (
    <motion.div
      className={className}
      initial={{ opacity: 0, y: 26 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-70px" }}
      transition={{ duration: 0.65, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  );
}

export default function LandingPage() {
  return (
    <main className="site-shell min-h-screen overflow-x-clip bg-ink text-fg">
      <div className="site-grid" aria-hidden="true" />
      <div className="site-noise" aria-hidden="true" />

      <Navbar />

      <div className="relative z-10">
        <Hero />
        <AgentMarquee />
        <ProductShowcase />
        <MemoryBento />
        <SetupTerminal />
        <FinalCta />
        <Footer />
      </div>
    </main>
  );
}

function Navbar() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-line/60 bg-ink/80 backdrop-blur-xl">
      <nav
        className="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
        aria-label="Main navigation"
      >
        <Link href="/" className="flex min-w-0 items-center gap-2.5">
          <Image src="/icon.png" alt="" width={34} height={34} className="rounded-xl" priority />
          <span className="font-display text-[16px] font-semibold tracking-tight">NoteClaw</span>
        </Link>

        <div className="hidden items-center gap-2 rounded-full border border-line/70 bg-panel/60 px-3.5 py-1.5 md:flex">
          <span className="relative flex h-2 w-2">
            <span className="pulse-dot absolute inline-flex h-full w-full rounded-full bg-mint" />
            <span className="relative inline-flex h-2 w-2 rounded-full bg-mint" />
          </span>
          <span className="font-mono text-[11px] text-mut">mcp://notebackend.pikpam.com · live</span>
        </div>

        <div className="flex shrink-0 items-center gap-1 sm:gap-2">
          <Link href="/docs" className="hidden px-3 py-2 text-sm text-mut transition-colors hover:text-fg md:block">
            Docs
          </Link>
          <Link href="/plans" className="hidden px-3 py-2 text-sm text-mut transition-colors hover:text-fg md:block">
            Plans
          </Link>
          <Link href="/login" className="px-3 py-2 text-sm text-mut transition-colors hover:text-fg">
            Sign in
          </Link>
          <Link
            href="/signup"
            className="inline-flex items-center gap-2 rounded-full bg-teal px-4 py-2 text-sm font-semibold text-[#06251f] transition hover:bg-[#8fe6da] sm:px-5"
          >
            <span className="hidden sm:inline">Open memory bank</span>
            <span className="sm:hidden">Get started</span>
            <ArrowRight size={15} aria-hidden="true" />
          </Link>
        </div>
      </nav>
    </header>
  );
}

type FeedKind = "ws" | "memory" | "verify" | "user" | "agent";

type FeedEvent = {
  kind: FeedKind;
  text: string;
  hue: string;
};

const FEED: FeedEvent[] = [
  { kind: "ws", text: "claude-sonnet connected · session a4f2", hue: "#5fd4c4" },
  { kind: "memory", text: 'memory_put → "checkout-refactor" · 3 items', hue: "#7ba8ff" },
  { kind: "verify", text: "code verified · score 94 → Notebook/payments", hue: "#3fcf8e" },
  { kind: "user", text: 'user: "why did the build fail?"', hue: "#f2b544" },
  { kind: "agent", text: "agent replied in 1.2s · pushed via WebSocket", hue: "#e08a5b" },
  { kind: "memory", text: "memory_compact → 42 items → checkpoint #7", hue: "#a78bfa" },
  { kind: "ws", text: "gemini-cli connected · session 9c1d", hue: "#5fd4c4" },
  { kind: "memory", text: 'memory_get → restored "checkout-refactor"', hue: "#7ba8ff" },
];

const FEED_ICONS: Record<FeedKind, React.ComponentType<{ size?: number; className?: string }>> = {
  ws: Radio,
  memory: Database,
  verify: BadgeCheck,
  user: MessageSquare,
  agent: Bot,
};

type FeedItem = FeedEvent & { id: number };

function LiveConsole() {
  const [items, setItems] = useState<FeedItem[]>(() =>
    FEED.slice(0, 4).map((f, i) => ({ ...f, id: i })),
  );
  const counter = useRef(4);

  useEffect(() => {
    const t = setInterval(() => {
      setItems((prev) => {
        const next = FEED[counter.current % FEED.length];
        counter.current += 1;
        return [...prev.slice(-5), { ...next, id: counter.current }];
      });
    }, 2100);
    return () => clearInterval(t);
  }, []);

  return (
    <div className="relative">
      <div
        className="absolute -inset-8 rounded-[40px] bg-teal/10 blur-3xl"
        aria-hidden="true"
      />

      <div className="console-scan relative overflow-hidden rounded-2xl border border-line bg-[#0c1424]/95 shadow-2xl shadow-black/50">
        <div className="flex items-center justify-between border-b border-line/70 px-4 py-3">
          <div className="flex items-center gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#ff5f57]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#febc2e]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#28c840]" />
          </div>
          <span className="font-mono text-[11px] text-dim">noteclaw · session a4f2c9</span>
          <span className="flex items-center gap-1.5 font-mono text-[11px] text-mint">
            <span className="relative flex h-1.5 w-1.5">
              <span className="pulse-dot absolute h-full w-full rounded-full bg-mint" />
              <span className="relative h-1.5 w-1.5 rounded-full bg-mint" />
            </span>
            live
          </span>
        </div>

        <div className="flex items-center gap-3 border-b border-line/70 bg-panel/40 px-4 py-3">
          <span
            className="flex h-9 w-9 items-center justify-center rounded-lg"
            style={{ backgroundColor: "#e08a5b1f", color: "#e08a5b" }}
          >
            <AgentIcon d={siClaude.path} className="h-5 w-5" />
          </span>
          <div className="min-w-0">
            <p className="truncate font-mono text-[12px] font-medium text-fg">claude-sonnet-4</p>
            <p className="font-mono text-[10px] text-dim">connected · websocket · 38ms</p>
          </div>
          <span className="ml-auto rounded-full border border-teal/30 bg-teal/10 px-2 py-0.5 font-mono text-[9px] uppercase tracking-wider text-teal">
            writing
          </span>
        </div>

        <div className="h-[248px] space-y-2 overflow-hidden px-4 py-4">
          <AnimatePresence initial={false}>
            {items.map((item) => {
              const Icon = FEED_ICONS[item.kind];
              return (
                <motion.div
                  key={item.id}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ duration: 0.35, ease: "easeOut" }}
                  className="flex items-start gap-2.5"
                >
                  <span
                    className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded"
                    style={{ backgroundColor: `${item.hue}1a`, color: item.hue }}
                  >
                    <Icon size={12} />
                  </span>
                  <span className="font-mono text-[11px] leading-5 text-mut">{item.text}</span>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>

        <div className="flex items-center gap-2 border-t border-line/70 bg-panel/40 px-4 py-3">
          <span className="font-mono text-[11px] text-dim">agent is writing to memory</span>
          <span className="flex items-center gap-1">
            {[0, 1, 2].map((i) => (
              <span
                key={i}
                className="typing-dot h-1 w-1 rounded-full bg-teal"
                style={{ animationDelay: `${i * 0.18}s` }}
              />
            ))}
          </span>
          <span className="blink ml-auto font-mono text-[11px] text-teal">▍</span>
        </div>
      </div>

      <div className="drift absolute -right-4 -top-5 z-10 hidden items-center gap-2 rounded-xl border border-line bg-panel px-3 py-2 shadow-lg sm:flex">
        <KeyRound size={13} className="text-amber" />
        <span className="font-mono text-[10px] text-mut">nclaw_•••• · revocable</span>
      </div>
      <div className="drift-slow absolute -bottom-5 -left-4 z-10 hidden items-center gap-2 rounded-xl border border-line bg-panel px-3 py-2 shadow-lg sm:flex">
        <BookMarked size={13} className="text-sky" />
        <span className="font-mono text-[10px] text-mut">notebook: payments-api</span>
      </div>
    </div>
  );
}

function Hero() {
  return (
    <section className="relative px-4 pb-24 pt-32 sm:px-6 sm:pt-36 lg:px-8">
      <div className="wash left-[-16rem] top-[-14rem] h-[42rem] w-[42rem] bg-sky/10" aria-hidden="true" />
      <div className="wash right-[-14rem] top-[8rem] h-[38rem] w-[38rem] bg-teal/10" aria-hidden="true" />

      <div className="mx-auto grid max-w-7xl items-center gap-16 lg:grid-cols-[1.05fr_0.95fr]">
        <div>
          <Reveal>
            <div className="inline-flex items-center gap-2.5 rounded-full border border-teal/25 bg-teal/[0.07] px-3.5 py-1.5">
              <span className="relative flex h-1.5 w-1.5">
                <span className="pulse-dot absolute h-full w-full rounded-full bg-teal" />
                <span className="relative h-1.5 w-1.5 rounded-full bg-teal" />
              </span>
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-teal">
                Memory layer for MCP agents
              </span>
            </div>
          </Reveal>

          <Reveal delay={0.08}>
            <h1 className="mt-7 font-display text-[clamp(2.9rem,7.5vw,5.6rem)] font-bold leading-[0.98] tracking-[-0.045em] text-balance">
              Your agents remember.
              <span className="block text-teal">You hold the keys.</span>
            </h1>
          </Reveal>

          <Reveal delay={0.16}>
            <p className="mt-7 max-w-xl text-base leading-7 text-mut sm:text-lg sm:leading-8">
              NoteClaw gives coding agents a private, namespaced memory bank —
              restored every session, shared across agents, and revocable by you.
            </p>
          </Reveal>

          <Reveal delay={0.24}>
            <div className="mt-9 flex flex-col gap-3 sm:flex-row">
              <Link
                href="/signup"
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-teal px-7 py-3 text-sm font-semibold text-[#06251f] transition hover:bg-[#8fe6da] hover:shadow-[0_0_32px_-6px_rgba(95,212,196,0.55)]"
              >
                Open a memory bank
                <ArrowRight size={17} aria-hidden="true" />
              </Link>
              <Link
                href="/docs"
                className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-line bg-panel/60 px-7 py-3 text-sm font-medium text-fg/80 transition hover:border-teal/40 hover:text-fg"
              >
                <BookOpen size={16} aria-hidden="true" />
                Read the MCP docs
              </Link>
            </div>
          </Reveal>

          <Reveal delay={0.32}>
            <div className="mt-11">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-dim">
                Speaks MCP with
              </p>
              <div className="mt-4 flex flex-wrap items-center gap-x-5 gap-y-3">
                {AGENTS.slice(0, 6).map((a) => (
                  <span
                    key={a.name}
                    title={a.name}
                    className="opacity-45 grayscale transition duration-300 hover:opacity-100 hover:grayscale-0"
                    style={{ color: a.hue }}
                  >
                    <AgentIcon d={a.d} className="h-5 w-5" />
                  </span>
                ))}
              </div>
            </div>
          </Reveal>
        </div>

        <Reveal delay={0.2}>
          <LiveConsole />
        </Reveal>
      </div>
    </section>
  );
}

function AgentCard({ agent }: { agent: Agent }) {
  return (
    <div
      className="group flex w-60 shrink-0 items-center gap-3.5 rounded-xl border border-line bg-panel/70 px-4 py-3.5 transition-all duration-300 hover:-translate-y-0.5 hover:border-[color:var(--hue)] hover:shadow-[0_10px_36px_-10px_var(--hue)]"
      style={{ "--hue": agent.hue } as React.CSSProperties}
    >
      <span
        className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg transition-transform duration-300 group-hover:scale-110"
        style={{ backgroundColor: `${agent.hue}1a`, color: agent.hue }}
      >
        <AgentIcon d={agent.d} className="h-5 w-5" />
      </span>
      <div className="min-w-0">
        <p className="truncate text-sm font-semibold text-fg">{agent.name}</p>
        <p className="truncate text-[11px] text-dim">{agent.by}</p>
      </div>
      <span
        className="ml-auto shrink-0 rounded-full px-2 py-0.5 font-mono text-[9px] uppercase tracking-wider"
        style={{ backgroundColor: `${agent.hue}14`, color: agent.hue }}
      >
        {agent.transport}
      </span>
    </div>
  );
}

function YourAgentCard() {
  return (
    <Link
      href="/docs"
      className="group flex w-60 shrink-0 items-center gap-3.5 rounded-xl border border-dashed border-line px-4 py-3.5 transition-all duration-300 hover:-translate-y-0.5 hover:border-teal/50 hover:bg-teal/[0.05]"
    >
      <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg border border-dashed border-line text-dim transition group-hover:border-teal/50 group-hover:text-teal">
        <Plus size={18} />
      </span>
      <div className="min-w-0">
        <p className="text-sm font-semibold text-fg">Your agent</p>
        <p className="text-[11px] text-dim">any MCP client</p>
      </div>
      <ArrowRight
        size={15}
        className="ml-auto shrink-0 text-dim transition group-hover:translate-x-0.5 group-hover:text-teal"
      />
    </Link>
  );
}

function AgentMarquee() {
  const rowOne = [...AGENTS.slice(0, 5), ...AGENTS.slice(0, 5)];
  const rowTwo = [...AGENTS.slice(5), ...AGENTS.slice(5)];

  return (
    <section className="border-y border-line/60 bg-ink-2/60 py-16">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <Reveal className="flex flex-col items-start justify-between gap-4 sm:flex-row sm:items-end">
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-teal">
              Ecosystem
            </p>
            <h2 className="mt-3 font-display text-3xl font-bold tracking-[-0.03em] sm:text-4xl">
              One memory, every agent.
            </h2>
          </div>
          <p className="max-w-sm text-sm leading-6 text-mut">
            Connect over standard MCP and WebSocket transports. Each agent gets
            its own session — and they all read from the same project memory.
          </p>
        </Reveal>
      </div>

      <Reveal delay={0.1}>
        <div className="mt-10 space-y-4">
          <div className="marquee">
            <div className="marquee-track">
              {rowOne.map((a, i) => (
                <AgentCard key={`${a.name}-${i}`} agent={a} />
              ))}
            </div>
          </div>
          <div className="marquee marquee-rev">
            <div className="marquee-track">
              {rowTwo.map((a, i) => (
                <AgentCard key={`${a.name}-${i}`} agent={a} />
              ))}
              <YourAgentCard />
              <YourAgentCard />
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

function ProductShowcase() {
  return (
    <section id="product" className="relative px-4 py-24 sm:px-6 lg:px-8">
      <div className="wash left-[-18rem] top-1/4 h-[34rem] w-[34rem] bg-vio/[0.08]" aria-hidden="true" />
      <div className="wash right-[-16rem] bottom-0 h-[32rem] w-[32rem] bg-teal/[0.08]" aria-hidden="true" />

      <div className="mx-auto max-w-7xl">
        <Reveal className="flex flex-col justify-between gap-6 lg:flex-row lg:items-end">
          <div className="max-w-3xl">
            <div className="inline-flex items-center gap-2 rounded-full border border-mint/25 bg-mint/[0.06] px-3 py-1.5">
              <span className="h-1.5 w-1.5 rounded-full bg-mint" />
              <span className="font-mono text-[10px] uppercase tracking-[0.2em] text-mint">
                Real app · captured on Android
              </span>
            </div>
            <h2 className="mt-5 font-display text-[clamp(2.4rem,5vw,4.5rem)] font-bold leading-[1.03] tracking-[-0.045em] text-balance">
              One command center.
              <span className="block text-sky">Every part of the work.</span>
            </h2>
          </div>
          <p className="max-w-md text-sm leading-7 text-mut sm:text-base">
            Capture durable memory, talk to connected agents, steer projects,
            verify claims, and review code from the same private workspace.
          </p>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="relative mt-12 overflow-hidden rounded-[32px] border border-line/90 bg-[#07101f] shadow-[0_40px_100px_-55px_rgba(95,212,196,0.45)]">
            <Image
              src="/app-showcase-bg.png"
              alt=""
              fill
              sizes="(max-width: 1280px) 100vw, 1280px"
              className="object-cover opacity-80"
            />
            <div
              className="absolute inset-0 bg-[linear-gradient(180deg,rgba(5,10,22,0.12),rgba(5,10,22,0.5))]"
              aria-hidden="true"
            />

            <div className="showcase-scroll relative overflow-x-auto px-5 pb-7 pt-8 sm:px-8 sm:pb-9 sm:pt-10">
              <div className="flex w-max items-start gap-5 pr-5 sm:gap-7 sm:pr-8">
                {APP_SCREENS.map((screen, index) => (
                  <figure
                    key={screen.src}
                    className={`group w-[184px] shrink-0 sm:w-[230px] ${index % 2 ? "pt-10" : ""}`}
                  >
                    <figcaption className="mb-3 px-1">
                      <p className="font-mono text-[9px] tracking-[0.18em] text-teal/80">
                        {screen.eyebrow}
                      </p>
                      <p className="mt-1 text-sm font-semibold text-fg/90">{screen.title}</p>
                    </figcaption>
                    <div className="rounded-[26px] border border-white/15 bg-[#020611] p-1.5 shadow-[0_26px_70px_-28px_rgba(0,0,0,0.95)] transition duration-500 group-hover:-translate-y-1.5 group-hover:border-teal/35 group-hover:shadow-[0_30px_80px_-30px_rgba(95,212,196,0.4)]">
                      <Image
                        src={screen.src}
                        alt={screen.alt}
                        width={720}
                        height={1600}
                        sizes="(max-width: 640px) 184px, 230px"
                        className="h-auto w-full rounded-[20px]"
                      />
                    </div>
                  </figure>
                ))}
              </div>
            </div>

            <div className="relative flex items-center justify-between border-t border-white/[0.07] px-5 py-3 font-mono text-[9px] uppercase tracking-[0.17em] text-dim sm:px-8">
              <span>Swipe or scroll to explore</span>
              <span className="text-mint">6 live workspaces</span>
            </div>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function MemoryTree() {
  const rows = [
    { depth: 0, label: "notebook: payments-api", icon: BookMarked, hue: "#5fd4c4", score: null },
    { depth: 1, label: "topic: checkout-refactor", icon: Boxes, hue: "#7ba8ff", score: null },
    { depth: 2, label: "source: cart.ts", icon: Terminal, hue: "#93a1b8", score: 94 },
    { depth: 2, label: "source: api.ts", icon: Terminal, hue: "#93a1b8", score: 88 },
    { depth: 1, label: "topic: webhooks", icon: Boxes, hue: "#7ba8ff", score: null },
    { depth: 2, label: "source: stripe.ts", icon: Terminal, hue: "#93a1b8", score: 91 },
  ];

  return (
    <div className="mt-6 space-y-1.5 rounded-xl border border-line/70 bg-[#0c1424]/80 p-4">
      {rows.map((r) => {
        const Icon = r.icon;
        return (
          <div
            key={r.label}
            className="group flex items-center gap-2.5 rounded-lg px-2 py-1.5 transition hover:bg-panel/70"
            style={{ paddingLeft: `${r.depth * 20 + 8}px` }}
          >
            {r.depth > 0 && <span className="font-mono text-[11px] text-dim">└─</span>}
            <Icon size={13} style={{ color: r.hue }} />
            <span className="font-mono text-[11.5px] text-mut transition group-hover:text-fg">
              {r.label}
            </span>
            {r.score !== null && (
              <span className="ml-auto flex items-center gap-1 rounded-full bg-mint/10 px-2 py-0.5 font-mono text-[9px] text-mint">
                <BadgeCheck size={10} /> {r.score}
              </span>
            )}
          </div>
        );
      })}
    </div>
  );
}

function MemoryBento() {
  return (
    <section className="px-4 py-24 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-7xl">
        <Reveal className="max-w-2xl">
          <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-teal">
            How it remembers
          </p>
          <h2 className="mt-3 font-display text-3xl font-bold tracking-[-0.03em] text-balance sm:text-5xl">
            A structured home for agent memory.
          </h2>
          <p className="mt-5 text-base leading-7 text-mut">
            Not a black-box vector store. NoteClaw organizes knowledge into
            notebooks, topics, and sources — readable by you, restorable by any agent.
          </p>
        </Reveal>

        <div className="mt-14 grid gap-4 lg:grid-cols-4">
          <Reveal className="lg:col-span-2 lg:row-span-2" delay={0.05}>
            <article className="flex h-full flex-col rounded-2xl border border-line bg-panel/60 p-7 transition hover:border-teal/35">
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-teal/10 text-teal">
                <Database size={19} />
              </div>
              <h3 className="mt-6 font-display text-xl font-semibold">Namespaced memory</h3>
              <p className="mt-3 text-sm leading-6 text-mut">
                Every project lives in its own namespace. Agents read and write
                by topic, so context never bleeds between repos.
              </p>
              <MemoryTree />
            </article>
          </Reveal>

          <Reveal className="lg:col-span-2" delay={0.1}>
            <article className="group flex h-full items-start gap-5 rounded-2xl border border-line bg-panel/60 p-7 transition hover:border-mint/35">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-mint/10 text-mint">
                <BadgeCheck size={19} />
              </div>
              <div className="flex-1">
                <h3 className="font-display text-lg font-semibold">Verified code sources</h3>
                <p className="mt-2 text-sm leading-6 text-mut">
                  Code an agent saves is checked for correctness before it lands
                  in your notebook, with a quality score attached.
                </p>
              </div>
              <div className="hidden shrink-0 flex-col items-center rounded-xl border border-line/70 bg-[#0c1424]/80 px-4 py-3 sm:flex">
                <span className="font-display text-2xl font-bold text-mint">94</span>
                <span className="font-mono text-[9px] uppercase tracking-wider text-dim">score</span>
              </div>
            </article>
          </Reveal>

          <Reveal className="lg:col-span-2" delay={0.15}>
            <article className="flex h-full items-start gap-5 rounded-2xl border border-line bg-panel/60 p-7 transition hover:border-clay/35">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-clay/10 text-clay">
                <MessageSquare size={19} />
              </div>
              <div className="flex-1">
                <h3 className="font-display text-lg font-semibold">Live chat gateway</h3>
                <p className="mt-2 text-sm leading-6 text-mut">
                  Message a connected agent over WebSocket and get its reply
                  streamed straight back into the app.
                </p>
              </div>
              <div className="hidden shrink-0 flex-col gap-1.5 sm:flex">
                <span className="rounded-lg rounded-tr-sm bg-panel-2 px-3 py-1.5 font-mono text-[10px] text-mut">
                  why did it fail?
                </span>
                <span className="flex items-center gap-1.5 rounded-lg rounded-tl-sm bg-clay/15 px-3 py-1.5 font-mono text-[10px] text-clay">
                  <span className="relative flex h-1 w-1">
                    <span className="pulse-dot absolute h-full w-full rounded-full bg-clay" />
                    <span className="relative h-1 w-1 rounded-full bg-clay" />
                  </span>
                  typing…
                </span>
              </div>
            </article>
          </Reveal>

          <Reveal className="lg:col-span-2" delay={0.2}>
            <article className="flex h-full items-start gap-5 rounded-2xl border border-line bg-panel/60 p-7 transition hover:border-amber/35">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-amber/10 text-amber">
                <KeyRound size={19} />
              </div>
              <div className="flex-1">
                <h3 className="font-display text-lg font-semibold">Revocable access</h3>
                <p className="mt-2 text-sm leading-6 text-mut">
                  Each agent connects with its own token. Revoke it and that
                  agent loses the memory instantly.
                </p>
              </div>
              <div className="hidden shrink-0 items-center gap-2 rounded-xl border border-line/70 bg-[#0c1424]/80 px-3 py-2 sm:flex">
                <span className="font-mono text-[10px] text-dim">nclaw_••••</span>
                <span className="flex h-4 w-7 items-center rounded-full bg-mint/25 px-0.5">
                  <span className="ml-auto h-3 w-3 rounded-full bg-mint" />
                </span>
              </div>
            </article>
          </Reveal>

          <Reveal className="lg:col-span-2" delay={0.25}>
            <article className="flex h-full items-start gap-5 rounded-2xl border border-line bg-panel/60 p-7 transition hover:border-vio/35">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-vio/10 text-vio">
                <ShieldCheck size={19} />
              </div>
              <div className="flex-1">
                <h3 className="font-display text-lg font-semibold">Auto-compaction</h3>
                <p className="mt-2 text-sm leading-6 text-mut">
                  Long histories are folded into checkpoints, so restores stay
                  fast and tokens stay cheap.
                </p>
              </div>
              <div className="hidden shrink-0 items-center gap-1.5 rounded-xl border border-line/70 bg-[#0c1424]/80 px-3 py-2 sm:flex">
                <span className="font-mono text-[10px] text-vio">checkpoint #7</span>
                <ArrowRight size={11} className="text-dim" />
                <span className="font-mono text-[10px] text-mut">42 items</span>
              </div>
            </article>
          </Reveal>
        </div>
      </div>
    </section>
  );
}

const CONFIGS = {
  hosted: `{
  "mcpServers": {
    "noteclaw-memory": {
      "url": "https://notebackend.pikpam.com/mcp",
      "headers": {
        "Authorization": "Bearer nclaw_••••••••"
      }
    }
  }
}`,
  stdio: `{
  "mcpServers": {
    "noteclaw-memory": {
      "command": "node",
      "args": ["/path/to/noteclaw-mcp/dist/index.js"],
      "env": {
        "BACKEND_URL": "https://notebackend.pikpam.com",
        "NOTECLAW_API_TOKEN": "nclaw_••••••••"
      }
    }
  }
}`,
} as const;

function SetupTerminal() {
  const [tab, setTab] = useState<"hosted" | "stdio">("hosted");
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(CONFIGS[tab]);
      setCopied(true);
      setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  };

  return (
    <section className="border-y border-line/60 bg-ink-2/60 px-4 py-24 sm:px-6 lg:px-8">
      <div className="mx-auto grid max-w-7xl items-center gap-14 lg:grid-cols-2">
        <Reveal>
          <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-teal">
            Two-minute setup
          </p>
          <h2 className="mt-3 font-display text-3xl font-bold tracking-[-0.03em] text-balance sm:text-4xl">
            Point your agent at one endpoint.
          </h2>
          <p className="mt-5 max-w-lg text-base leading-7 text-mut">
            Modern MCP clients connect directly over Streamable HTTP — no server
            to run. Need stdio? Drop in the lightweight local bridge. Either way,
            the memory stays in your hosted account.
          </p>

          <ul className="mt-8 space-y-3.5">
            {[
              "Generate a personal token in Settings → Agent Connections",
              "Paste the config into your agent's MCP settings",
              "The first connection creates a private agent notebook",
            ].map((step, i) => (
              <li key={step} className="flex items-start gap-3">
                <span className="mt-0.5 flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-teal/30 bg-teal/10 font-mono text-[10px] text-teal">
                  {i + 1}
                </span>
                <span className="text-sm leading-6 text-mut">{step}</span>
              </li>
            ))}
          </ul>
        </Reveal>

        <Reveal delay={0.12}>
          <div className="overflow-hidden rounded-2xl border border-line bg-[#0c1424]/95 shadow-2xl shadow-black/50">
            <div className="flex items-center justify-between border-b border-line/70 px-3 py-2">
              <div className="flex gap-1">
                {(
                  [
                    { key: "hosted", label: "Hosted MCP" },
                    { key: "stdio", label: "Local stdio" },
                  ] as const
                ).map((t) => (
                  <button
                    key={t.key}
                    onClick={() => setTab(t.key)}
                    className={`rounded-lg px-3 py-1.5 font-mono text-[11px] transition ${
                      tab === t.key
                        ? "bg-teal/15 text-teal"
                        : "text-dim hover:text-mut"
                    }`}
                  >
                    {t.label}
                  </button>
                ))}
              </div>
              <button
                onClick={copy}
                className="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 font-mono text-[11px] text-dim transition hover:bg-panel hover:text-fg"
                aria-label="Copy config"
              >
                {copied ? <Check size={13} className="text-mint" /> : <Copy size={13} />}
                {copied ? "copied" : "copy"}
              </button>
            </div>
            <pre className="overflow-x-auto p-5 font-mono text-[12px] leading-6 text-mut">
              <code>{CONFIGS[tab]}</code>
            </pre>
          </div>
        </Reveal>
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="px-4 py-24 sm:px-6 lg:px-8">
      <Reveal>
        <div className="relative mx-auto max-w-7xl overflow-hidden rounded-3xl border border-line bg-panel/60">
          <div className="wash left-[-10rem] top-[-12rem] h-[30rem] w-[30rem] bg-teal/10" aria-hidden="true" />
          <div className="wash bottom-[-12rem] right-[-10rem] h-[30rem] w-[30rem] bg-sky/10" aria-hidden="true" />

          <div className="relative grid items-center gap-12 px-7 py-14 sm:px-12 lg:grid-cols-[1.1fr_0.9fr] lg:py-16">
            <div>
              <h2 className="font-display text-3xl font-bold tracking-[-0.035em] text-balance sm:text-5xl">
                Give every session a place to continue.
              </h2>
              <p className="mt-5 max-w-xl text-base leading-7 text-mut">
                Start free, connect your agent, and keep its project memory
                under your control.
              </p>
              <Link
                href="/signup"
                className="mt-8 inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-teal px-7 py-3 text-sm font-semibold text-[#06251f] transition hover:bg-[#8fe6da] hover:shadow-[0_0_32px_-6px_rgba(95,212,196,0.55)]"
              >
                Open NoteClaw
                <ArrowRight size={17} aria-hidden="true" />
              </Link>
            </div>

            <div className="rounded-2xl border border-line bg-[#0c1424]/90 p-5">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-dim">
                Your endpoint
              </p>
              <div className="mt-3 flex items-center gap-2.5 rounded-xl border border-line/70 bg-panel/70 px-4 py-3">
                <span className="relative flex h-2 w-2">
                  <span className="pulse-dot absolute h-full w-full rounded-full bg-mint" />
                  <span className="relative h-2 w-2 rounded-full bg-mint" />
                </span>
                <span className="truncate font-mono text-[12px] text-fg">
                  notebackend.pikpam.com/mcp
                </span>
              </div>
              <div className="mt-4 flex flex-wrap gap-2">
                {["Streamable HTTP", "WebSocket", "Webhook fallback"].map((t) => (
                  <span
                    key={t}
                    className="rounded-full border border-line/70 bg-panel/60 px-2.5 py-1 font-mono text-[9px] uppercase tracking-wider text-mut"
                  >
                    {t}
                  </span>
                ))}
              </div>
            </div>
          </div>
        </div>
      </Reveal>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-line/60 px-4 py-9 sm:px-6 lg:px-8">
      <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-5 sm:flex-row">
        <div className="flex items-center gap-2.5">
          <Image src="/icon.png" alt="" width={26} height={26} className="rounded-lg" />
          <span className="font-display text-sm font-semibold">NoteClaw</span>
        </div>
        <div className="flex items-center gap-6 text-sm text-mut">
          <Link href="/docs" className="transition-colors hover:text-fg">
            Docs
          </Link>
          <Link href="/plans" className="transition-colors hover:text-fg">
            Plans
          </Link>
          <Link href="/login" className="transition-colors hover:text-fg">
            Sign in
          </Link>
        </div>
        <p className="font-mono text-[11px] text-dim">
          © {new Date().getFullYear()} NoteClaw
        </p>
      </div>
    </footer>
  );
}
