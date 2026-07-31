import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  BookOpen,
  Check,
  KeyRound,
  Layers3,
  Radio,
} from "lucide-react";

const essentials = [
  {
    icon: Layers3,
    title: "Organized memory",
    description:
      "Project knowledge stays readable in notebooks, topics, and sources.",
  },
  {
    icon: Radio,
    title: "Shared agent context",
    description:
      "Agents working on the same project can restore and update one memory.",
  },
  {
    icon: KeyRound,
    title: "Access you control",
    description:
      "Choose which notebooks an agent can use and revoke its token anytime.",
  },
];

export default function LandingPage() {
  return (
    <main className="site-shell min-h-screen overflow-x-clip bg-[#07080c] text-white">
      <div className="site-grid" aria-hidden="true" />
      <div className="site-glow site-glow-one" aria-hidden="true" />
      <div className="site-glow site-glow-two" aria-hidden="true" />

      <Navbar />

      <div className="relative z-10">
        <Hero />
        <AgentEcosystem />
        <Essentials />
        <FinalCta />
        <Footer />
      </div>
    </main>
  );
}

function Navbar() {
  return (
    <header className="fixed inset-x-0 top-0 z-50 border-b border-white/[0.07] bg-[#07080c]/82 backdrop-blur-xl">
      <nav
        className="mx-auto flex h-18 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
        aria-label="Main navigation"
      >
        <Link href="/" className="flex min-w-0 items-center gap-2.5">
          <Image
            src="/icon.png"
            alt=""
            width={36}
            height={36}
            className="rounded-xl"
            priority
          />
          <span className="truncate text-[15px] font-semibold tracking-[-0.02em]">
            NoteClaw
          </span>
        </Link>

        <div className="flex shrink-0 items-center gap-1 sm:gap-2">
          <Link
            href="/docs"
            className="hidden px-3 py-2 text-sm text-white/55 transition-colors hover:text-white md:block"
          >
            Docs
          </Link>
          <Link
            href="/plans"
            className="hidden px-3 py-2 text-sm text-white/55 transition-colors hover:text-white md:block"
          >
            Plans
          </Link>
          <Link
            href="/login"
            className="px-3 py-2 text-sm text-white/65 transition-colors hover:text-white"
          >
            Sign in
          </Link>
          <Link
            href="/signup"
            className="inline-flex items-center gap-2 rounded-full bg-white px-4 py-2.5 text-sm font-semibold text-[#090a0f] transition hover:bg-[#8ce4df] sm:px-5"
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

function Hero() {
  return (
    <section className="relative flex min-h-[76vh] items-center px-4 pb-20 pt-32 sm:px-6 sm:pb-24 sm:pt-36 lg:px-8">
      <div className="mx-auto w-full max-w-5xl text-center">
        <div className="inline-flex items-center gap-2 rounded-full border border-[#62d3d0]/25 bg-[#62d3d0]/[0.07] px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.16em] text-[#a8ebe7]">
          <span className="h-1.5 w-1.5 rounded-full bg-[#62d3d0]" />
          Memory for MCP agents
        </div>

        <h1 className="mx-auto mt-8 max-w-4xl text-[clamp(3.2rem,9vw,7rem)] font-semibold leading-[0.9] tracking-[-0.07em] text-balance">
          Your agents remember
          <span className="block bg-gradient-to-r from-[#8ce4df] via-[#68b7ee] to-[#9b78ef] bg-clip-text text-transparent">
            what matters.
          </span>
        </h1>

        <p className="mx-auto mt-8 max-w-2xl text-base leading-7 text-white/52 sm:text-lg sm:leading-8">
          One private memory bank for AI agents to restore project
          context, share knowledge, and continue after updates.
        </p>

        <div className="mt-10 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Link
            href="/signup"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-[#62d3d0] px-7 py-3 text-sm font-semibold text-[#07100f] transition hover:bg-[#a8ebe7] sm:w-auto"
          >
            Create a memory bank
            <ArrowRight size={17} aria-hidden="true" />
          </Link>
          <Link
            href="/docs"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full border border-white/12 bg-white/[0.035] px-7 py-3 text-sm font-medium text-white/76 transition hover:border-white/25 hover:bg-white/[0.07] sm:w-auto"
          >
            <BookOpen size={16} aria-hidden="true" />
            Read the MCP guide
          </Link>
        </div>

        <div className="mx-auto mt-10 flex max-w-2xl flex-wrap items-center justify-center gap-x-6 gap-y-3 text-xs text-white/38">
          {["MCP compatible", "WebSocket sync", "Revocable tokens"].map(
            (item) => (
              <span key={item} className="inline-flex items-center gap-1.5">
                <Check size={13} className="text-[#62d3d0]" aria-hidden="true" />
                {item}
              </span>
            ),
          )}
        </div>

        <div
          className="mx-auto mt-16 max-w-4xl rounded-[30px] border border-white/[0.08] bg-white/[0.025] p-3 shadow-2xl shadow-black/35 sm:p-4"
          aria-label="NoteClaw memory organization"
        >
          <div className="grid overflow-hidden rounded-[22px] border border-white/[0.07] bg-[#0a0c11]/92 sm:grid-cols-3">
            {[
              ["01", "Connect", "Add one secure MCP token"],
              ["02", "Remember", "Save project context by topic"],
              ["03", "Continue", "Restore it in the next session"],
            ].map(([number, title, description]) => (
              <div
                key={number}
                className="border-b border-white/[0.07] p-6 text-left last:border-b-0 sm:border-b-0 sm:border-r sm:last:border-r-0 sm:p-7"
              >
                <span className="font-mono text-[10px] tracking-[0.16em] text-[#62d3d0]/70">
                  {number}
                </span>
                <h2 className="mt-5 text-base font-semibold">{title}</h2>
                <p className="mt-2 text-xs leading-5 text-white/38">
                  {description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}

function AgentEcosystem() {
  const agents = [
    {
      name: "Claude Code",
      developer: "Anthropic",
      badge: "MCP Native",
      iconColor: "#f59e0b",
      borderColor: "rgba(245, 158, 11, 0.25)",
      bgColor: "rgba(245, 158, 11, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#f59e0b]" viewBox="0 0 24 24" fill="currentColor">
          <path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2Z" />
        </svg>
      ),
    },
    {
      name: "OpenClaw",
      developer: "Autonomous Agent",
      badge: "Gateway Ready",
      iconColor: "#62d3d0",
      borderColor: "rgba(98, 211, 208, 0.25)",
      bgColor: "rgba(98, 211, 208, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#62d3d0]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M12 2v20M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6" />
        </svg>
      ),
    },
    {
      name: "Hermes Agent",
      developer: "Nous Research",
      badge: "Live WebSocket",
      iconColor: "#c084fc",
      borderColor: "rgba(192, 132, 252, 0.25)",
      bgColor: "rgba(192, 132, 252, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#c084fc]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2" />
        </svg>
      ),
    },
    {
      name: "Codex",
      developer: "OpenAI Engine",
      badge: "MCP Stream",
      iconColor: "#34d399",
      borderColor: "rgba(52, 211, 153, 0.25)",
      bgColor: "rgba(52, 211, 153, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#34d399]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M16 18l6-6-6-6M8 6l-6 6 6 6" />
        </svg>
      ),
    },
    {
      name: "Kiro",
      developer: "Coding Agent",
      badge: "Realtime Gateway",
      iconColor: "#60a5fa",
      borderColor: "rgba(96, 165, 250, 0.25)",
      bgColor: "rgba(96, 165, 250, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#60a5fa]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M13 2L3 14h9l-1 8 10-12h-9l1-8z" />
        </svg>
      ),
    },
    {
      name: "Cursor & Windsurf",
      developer: "IDE AI Agents",
      badge: "Context Memory",
      iconColor: "#f472b6",
      borderColor: "rgba(244, 114, 182, 0.25)",
      bgColor: "rgba(244, 114, 182, 0.06)",
      icon: (
        <svg className="h-6 w-6 text-[#f472b6]" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
          <path d="M18 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3zM6 3a3 3 0 0 0-3 3v12a3 3 0 0 0 3 3 3 3 0 0 0 3-3V6a3 3 0 0 0-3-3z" />
        </svg>
      ),
    },
  ];

  return (
    <section className="border-t border-white/[0.06] bg-[#07080c] px-4 py-16 sm:px-6 lg:px-8">
      <div className="mx-auto max-w-6xl text-center">
        <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-[#62d3d0]/75">
          Ecosystem compatibility
        </p>
        <h2 className="mt-3 text-2xl font-semibold tracking-[-0.04em] text-white sm:text-4xl">
          Built for your favorite AI agents.
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-xs leading-6 text-white/45 sm:text-sm">
          Connect your agents over standard MCP and WebSocket transports to grant them persistent memory and real-time chat gateway access.
        </p>

        <div className="mt-10 grid grid-cols-2 gap-3.5 sm:grid-cols-3 lg:grid-cols-6">
          {agents.map((agent) => (
            <div
              key={agent.name}
              className="flex flex-col items-center justify-between rounded-2xl border p-4 text-center transition hover:scale-[1.02] hover:border-white/20"
              style={{
                borderColor: agent.borderColor,
                backgroundColor: agent.bgColor,
              }}
            >
              <div className="mb-3 flex h-12 w-12 items-center justify-center rounded-xl bg-white/[0.05]">
                {agent.icon}
              </div>
              <h3 className="text-sm font-semibold text-white">{agent.name}</h3>
              <span className="mt-1 text-[11px] text-white/45">{agent.developer}</span>
              <span className="mt-3 inline-flex items-center rounded-full bg-white/[0.08] px-2.5 py-0.5 font-mono text-[9px] uppercase tracking-wider text-white/70">
                {agent.badge}
              </span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

function Essentials() {
  return (
    <section className="border-y border-white/[0.06] bg-white/[0.012] px-4 py-20 sm:px-6 lg:px-8 lg:py-24">
      <div className="mx-auto max-w-6xl">
        <div className="mx-auto max-w-2xl text-center">
          <p className="font-mono text-[10px] uppercase tracking-[0.2em] text-[#62d3d0]/75">
            The essentials
          </p>
          <h2 className="mt-5 text-3xl font-semibold tracking-[-0.045em] text-balance sm:text-5xl">
            A clear home for agent memory.
          </h2>
        </div>

        <div className="mt-12 grid gap-4 md:grid-cols-3">
          {essentials.map((item) => (
            <article
              key={item.title}
              className="rounded-2xl border border-white/[0.07] bg-[#0a0c11]/75 p-6 sm:p-7"
            >
              <div className="flex h-10 w-10 items-center justify-center rounded-xl bg-[#62d3d0]/10 text-[#8ce4df]">
                <item.icon size={19} aria-hidden="true" />
              </div>
              <h3 className="mt-6 text-base font-semibold">{item.title}</h3>
              <p className="mt-3 text-sm leading-6 text-white/42">
                {item.description}
              </p>
            </article>
          ))}
        </div>

        <div className="mt-8 text-center">
          <Link
            href="/docs"
            className="inline-flex items-center gap-2 text-sm font-medium text-[#8ce4df] transition hover:text-white"
          >
            View setup, tools, and technical details
            <ArrowRight size={15} aria-hidden="true" />
          </Link>
        </div>
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="px-4 py-20 sm:px-6 lg:px-8 lg:py-24">
      <div className="cta-panel relative mx-auto max-w-6xl overflow-hidden rounded-[28px] border border-[#62d3d0]/15 px-6 py-14 text-center sm:px-10 sm:py-16">
        <h2 className="mx-auto max-w-3xl text-3xl font-semibold tracking-[-0.045em] text-balance sm:text-5xl">
          Give every session a place to continue.
        </h2>
        <p className="mx-auto mt-4 max-w-xl text-sm leading-6 text-white/46 sm:text-base">
          Start free, connect your agent, and keep its project memory under
          your control.
        </p>
        <Link
          href="/signup"
          className="mt-8 inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#62d3d0] px-7 py-3 text-sm font-semibold text-[#07100f] transition hover:bg-[#a8ebe7]"
        >
          Open NoteClaw
          <ArrowRight size={17} aria-hidden="true" />
        </Link>
      </div>
    </section>
  );
}

function Footer() {
  return (
    <footer className="border-t border-white/[0.06] px-4 py-8 sm:px-6 lg:px-8">
      <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-5 sm:flex-row">
        <div className="flex items-center gap-2.5">
          <Image
            src="/icon.png"
            alt=""
            width={28}
            height={28}
            className="rounded-lg"
          />
          <span className="text-sm font-semibold">NoteClaw</span>
        </div>
        <div className="flex items-center gap-5 text-xs text-white/38">
          <Link href="/docs" className="transition-colors hover:text-white">
            Docs
          </Link>
          <Link href="/plans" className="transition-colors hover:text-white">
            Plans
          </Link>
          <Link href="/login" className="transition-colors hover:text-white">
            Sign in
          </Link>
        </div>
        <p className="text-xs text-white/25">
          © {new Date().getFullYear()} NoteClaw
        </p>
      </div>
    </footer>
  );
}
