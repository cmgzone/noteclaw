import Image from "next/image";
import Link from "next/link";
import {
  ArrowRight,
  Archive,
  Bot,
  Braces,
  Check,
  ChevronRight,
  CircleDot,
  Clock3,
  Database,
  Fingerprint,
  KeyRound,
  Layers3,
  LockKeyhole,
  Radio,
  RefreshCw,
  ServerCog,
  ShieldCheck,
  Sparkles,
  Unplug,
  Waypoints,
} from "lucide-react";

const agents = [
  {
    name: "Codex Workspace",
    identifier: "codex-production",
    namespaces: 4,
    status: "Live",
  },
  {
    name: "Claude Research",
    identifier: "claude-research",
    namespaces: 3,
    status: "Idle",
  },
  {
    name: "OpenClaw Ops",
    identifier: "openclaw-ops",
    namespaces: 1,
    status: "Live",
  },
];

const features = [
  {
    icon: Layers3,
    title: "Project notebooks",
    description:
      "Each shared session becomes a notebook, with every durable namespace organized as a readable memory source.",
  },
  {
    icon: Archive,
    title: "Automatic compaction",
    description:
      "Roll older working history into durable checkpoints while the agent keeps its most useful recent context.",
  },
  {
    icon: Radio,
    title: "Live over WebSocket",
    description:
      "See presence instantly and receive memory-ready, memory-changed, and memory-compacted events without polling.",
  },
  {
    icon: ShieldCheck,
    title: "Focused code review",
    description:
      "Let an agent check correctness, security, and maintainability without adding a full development suite.",
  },
  {
    icon: Braces,
    title: "Model-agnostic JSON",
    description:
      "Store structured memory that any compatible third-party agent can read, merge, append, and carry forward.",
  },
  {
    icon: ShieldCheck,
    title: "Private by default",
    description:
      "Every memory session is scoped to its owner, authenticated, and isolated from other agents and accounts.",
  },
];

const steps = [
  {
    number: "01",
    icon: KeyRound,
    title: "Create one access token",
    description:
      "Generate a revocable MCP token in NoteClaw and add it to the agent’s private environment.",
  },
  {
    number: "02",
    icon: ServerCog,
    title: "Connect and discover",
    description:
      "The first connection creates a private agent notebook and exposes it as an MCP Resource. No manual setup is required.",
  },
  {
    number: "03",
    icon: RefreshCw,
    title: "Restore, work, and sync",
    description:
      "Optionally assign a stable project identifier, then read memory, write changes, and listen for live WebSocket events.",
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
        <AgentStrip />
        <Features />
        <HowItWorks />
        <Protocol />
        <Security />
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
            width={34}
            height={34}
            className="rounded-xl"
            priority
          />
          <span className="truncate text-[15px] font-semibold tracking-[-0.02em]">
            NoteClaw
          </span>
          <span className="hidden rounded-full border border-white/10 bg-white/[0.04] px-2 py-0.5 font-mono text-[9px] uppercase tracking-[0.18em] text-white/45 sm:inline">
            Memory
          </span>
        </Link>

        <div className="hidden items-center gap-8 text-sm text-white/55 lg:flex">
          <a href="#product" className="transition-colors hover:text-white">
            Product
          </a>
          <a href="#how-it-works" className="transition-colors hover:text-white">
            How it works
          </a>
          <a href="#protocol" className="transition-colors hover:text-white">
            Protocol
          </a>
          <a href="#security" className="transition-colors hover:text-white">
            Security
          </a>
          <Link href="/plans" className="transition-colors hover:text-white">
            Plans
          </Link>
        </div>

        <div className="flex shrink-0 items-center gap-2">
          <Link
            href="/login"
            className="hidden px-3 py-2 text-sm text-white/60 transition-colors hover:text-white sm:block"
          >
            Sign in
          </Link>
          <Link
            href="/signup"
            className="inline-flex items-center gap-2 rounded-full bg-white px-4 py-2.5 text-sm font-semibold text-[#090a0f] transition hover:bg-[#62d3d0] sm:px-5"
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
    <section className="relative px-4 pb-20 pt-36 sm:px-6 sm:pb-24 sm:pt-40 lg:px-8 lg:pb-32">
      <div className="mx-auto grid max-w-7xl items-center gap-14 lg:grid-cols-[0.88fr_1.12fr] lg:gap-16">
        <div className="min-w-0">
          <div className="inline-flex items-center gap-2 rounded-full border border-[#62d3d0]/25 bg-[#62d3d0]/[0.07] px-3 py-1.5 font-mono text-[10px] uppercase tracking-[0.16em] text-[#a8ebe7]">
            <span className="relative flex h-2 w-2">
              <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#62d3d0] opacity-60" />
              <span className="relative inline-flex h-2 w-2 rounded-full bg-[#62d3d0]" />
            </span>
            MCP-native · WebSocket live
          </div>

          <h1 className="mt-7 max-w-3xl text-[clamp(3rem,8vw,6.4rem)] font-semibold leading-[0.93] tracking-[-0.065em] text-balance">
            Memory that
            <span className="block text-white/38">survives the session.</span>
          </h1>

          <p className="mt-7 max-w-xl text-base leading-7 text-white/55 sm:text-lg sm:leading-8">
            Give Codex, Claude, OpenClaw, and any MCP-compatible agent a
            durable place to restore identity, keep project context, and carry
            knowledge between runs.
          </p>

          <div className="mt-9 flex flex-col gap-3 sm:flex-row">
            <Link
              href="/signup"
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full bg-[#62d3d0] px-6 py-3 text-sm font-semibold text-[#101307] transition hover:bg-[#a8ebe7]"
            >
              Start with MCP
              <ArrowRight size={17} aria-hidden="true" />
            </Link>
            <a
              href="#protocol"
              className="inline-flex min-h-12 items-center justify-center gap-2 rounded-full border border-white/12 bg-white/[0.035] px-6 py-3 text-sm font-medium text-white/78 transition hover:border-white/25 hover:bg-white/[0.07]"
            >
              See the MCP tools
              <ChevronRight size={16} aria-hidden="true" />
            </a>
          </div>

          <div className="mt-9 flex flex-wrap gap-x-5 gap-y-3 text-xs text-white/42">
            {["No model lock-in", "Revocable access", "Structured JSON"].map(
              (item) => (
                <span key={item} className="inline-flex items-center gap-1.5">
                  <Check size={13} className="text-[#62d3d0]" aria-hidden="true" />
                  {item}
                </span>
              ),
            )}
          </div>
        </div>

        <MemoryPreview />
      </div>
    </section>
  );
}

function MemoryPreview() {
  return (
    <div className="relative min-w-0">
      <div className="preview-aura" aria-hidden="true" />
      <div className="relative overflow-hidden rounded-[26px] border border-white/10 bg-[#0c0e14]/95 shadow-2xl shadow-black/50">
        <div className="flex min-w-0 items-center justify-between gap-4 border-b border-white/[0.07] px-4 py-3.5 sm:px-5">
          <div className="flex min-w-0 items-center gap-3">
            <div className="flex gap-1.5" aria-hidden="true">
              <span className="h-2 w-2 rounded-full bg-white/15" />
              <span className="h-2 w-2 rounded-full bg-white/15" />
              <span className="h-2 w-2 rounded-full bg-white/15" />
            </div>
            <span className="truncate font-mono text-[10px] uppercase tracking-[0.16em] text-white/38">
              NoteClaw / memory bank
            </span>
          </div>
          <span className="inline-flex shrink-0 items-center gap-1.5 rounded-full bg-emerald-400/[0.08] px-2.5 py-1 text-[10px] font-medium text-emerald-300">
            <CircleDot size={10} aria-hidden="true" />
            Live
          </span>
        </div>

        <div className="grid grid-cols-3 border-b border-white/[0.07]">
          {[
            ["3", "Agents"],
            ["8", "Namespaces"],
            ["2", "WebSocket live"],
          ].map(([value, label]) => (
            <div
              key={label}
              className="min-w-0 border-r border-white/[0.07] px-3 py-4 last:border-r-0 sm:px-5"
            >
              <div className="text-xl font-semibold tracking-tight sm:text-2xl">
                {value}
              </div>
              <div className="mt-1 truncate text-[9px] uppercase tracking-[0.12em] text-white/32 sm:text-[10px]">
                {label}
              </div>
            </div>
          ))}
        </div>

        <div className="grid min-w-0 xl:grid-cols-[0.78fr_1.22fr]">
          <div className="min-w-0 border-b border-white/[0.07] p-3 sm:p-4 xl:border-b-0 xl:border-r">
            <div className="mb-3 flex items-center justify-between px-1">
              <span className="font-mono text-[9px] uppercase tracking-[0.16em] text-white/30">
                Agent sessions
              </span>
              <Waypoints size={13} className="text-white/25" aria-hidden="true" />
            </div>
            <div className="space-y-2">
              {agents.map((agent, index) => (
                <div
                  key={agent.identifier}
                  className={`min-w-0 rounded-xl border p-3 ${
                    index === 0
                      ? "border-[#62d3d0]/20 bg-[#62d3d0]/[0.045]"
                      : "border-white/[0.06] bg-white/[0.018]"
                  }`}
                >
                  <div className="flex min-w-0 items-start gap-2.5">
                    <div
                      className={`mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-lg ${
                        index === 0
                          ? "bg-[#62d3d0]/10 text-[#62d3d0]"
                          : "bg-white/[0.05] text-white/40"
                      }`}
                    >
                      <Bot size={14} aria-hidden="true" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-xs font-medium text-white/82">
                        {agent.name}
                      </div>
                      <div className="mt-0.5 truncate font-mono text-[9px] text-white/28">
                        {agent.identifier}
                      </div>
                    </div>
                    <span
                      className={`mt-1 h-1.5 w-1.5 shrink-0 rounded-full ${
                        agent.status === "Live"
                          ? "bg-emerald-400"
                          : "bg-white/20"
                      }`}
                      title={agent.status}
                    />
                  </div>
                  <div className="mt-2.5 flex items-center gap-1.5 text-[9px] text-white/28">
                    <Layers3 size={10} aria-hidden="true" />
                    {agent.namespaces} namespaces
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="min-w-0 p-3 sm:p-4">
            <div className="flex min-w-0 items-center justify-between gap-3 rounded-xl border border-white/[0.07] bg-black/20 px-3 py-2.5">
              <div className="flex min-w-0 items-center gap-2">
                <Database
                  size={13}
                  className="shrink-0 text-[#62d3d0]"
                  aria-hidden="true"
                />
                <span className="truncate font-mono text-[10px] text-white/68">
                  project:launch
                </span>
              </div>
              <span className="shrink-0 font-mono text-[9px] text-white/25">
                v12
              </span>
            </div>

            <div className="mt-3 overflow-x-auto rounded-xl border border-white/[0.07] bg-[#08090d] p-3.5 font-mono text-[10px] leading-5 sm:p-4 sm:text-[11px]">
              <pre className="min-w-[330px] text-white/42">
                <code>
                  <span className="text-white/22">{"{"}</span>
                  {"\n  "}
                  <span className="text-sky-300">&quot;goal&quot;</span>
                  <span className="text-white/24">: </span>
                  <span className="text-[#dfff9e]">
                    &quot;Ship the memory API&quot;
                  </span>
                  <span className="text-white/24">,</span>
                  {"\n  "}
                  <span className="text-sky-300">&quot;decisions&quot;</span>
                  <span className="text-white/24">: [</span>
                  {"\n    "}
                  <span className="text-[#dfff9e]">
                    &quot;MCP is the command surface&quot;
                  </span>
                  <span className="text-white/24">,</span>
                  {"\n    "}
                  <span className="text-[#dfff9e]">
                    &quot;WebSocket sends live events&quot;
                  </span>
                  {"\n  "}
                  <span className="text-white/24">],</span>
                  {"\n  "}
                  <span className="text-sky-300">&quot;next&quot;</span>
                  <span className="text-white/24">: </span>
                  <span className="text-[#dfff9e]">
                    &quot;Run integration checks&quot;
                  </span>
                  {"\n"}
                  <span className="text-white/22">{"}"}</span>
                </code>
              </pre>
            </div>

            <div className="mt-3 min-w-0 rounded-xl border border-emerald-400/12 bg-emerald-400/[0.035] p-3">
              <div className="flex min-w-0 items-center gap-2 text-[10px] text-emerald-300/85">
                <Radio size={12} className="shrink-0" aria-hidden="true" />
                <span className="truncate font-mono">
                  wss://api.noteclaw.com/ws/agent
                </span>
              </div>
              <div className="mt-1.5 flex flex-wrap gap-x-3 gap-y-1 text-[9px] text-white/28">
                <span>memory_ready</span>
                <span>memory_changed</span>
                <span>memory_compacted</span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <div className="absolute -bottom-5 left-1/2 hidden -translate-x-1/2 items-center gap-2 whitespace-nowrap rounded-full border border-white/10 bg-[#101217] px-4 py-2 text-[10px] text-white/42 shadow-xl sm:flex">
        <Clock3 size={12} className="text-[#62d3d0]" aria-hidden="true" />
        Context restored in 84 ms
      </div>
    </div>
  );
}

function AgentStrip() {
  return (
    <section className="border-y border-white/[0.06] bg-white/[0.015] px-4 py-8 sm:px-6">
      <div className="mx-auto flex max-w-7xl flex-col items-center gap-6 lg:flex-row lg:justify-between">
        <p className="text-center text-[10px] font-medium uppercase tracking-[0.2em] text-white/25 lg:text-left">
          Built for the agents you already use
        </p>
        <div className="flex flex-wrap items-center justify-center gap-x-8 gap-y-4 font-mono text-xs text-white/38 sm:gap-x-12">
          {["Codex", "Claude", "OpenClaw", "Cursor", "Kiro", "Any MCP client"].map(
            (agent) => (
              <span key={agent} className="whitespace-nowrap">
                {agent}
              </span>
            ),
          )}
        </div>
      </div>
    </section>
  );
}

function Features() {
  return (
    <section id="product" className="scroll-mt-20 px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="mx-auto max-w-7xl">
        <SectionIntro
          eyebrow="The product"
          title="Memory first. Review included."
          description="A deliberately small surface for agents that need durable context, a focused code check, and a live connection."
        />

        <div className="mt-14 grid gap-px overflow-hidden rounded-[26px] border border-white/[0.07] bg-white/[0.07] md:grid-cols-2 lg:grid-cols-3">
          {features.map((feature) => (
            <article
              key={feature.title}
              className="group min-w-0 bg-[#0a0b10] p-6 transition-colors hover:bg-[#0d0f15] sm:p-8"
            >
              <div className="flex h-11 w-11 items-center justify-center rounded-xl border border-white/[0.07] bg-white/[0.035] text-[#62d3d0] transition-transform group-hover:-translate-y-1">
                <feature.icon size={20} aria-hidden="true" />
              </div>
              <h3 className="mt-7 text-lg font-semibold tracking-[-0.02em]">
                {feature.title}
              </h3>
              <p className="mt-3 text-sm leading-6 text-white/42">
                {feature.description}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="scroll-mt-20 border-y border-white/[0.06] bg-white/[0.012] px-4 py-24 sm:px-6 lg:px-8 lg:py-32"
    >
      <div className="mx-auto max-w-7xl">
        <SectionIntro
          eyebrow="Three steps"
          title="Connect once. Remember continuously."
          description="NoteClaw keeps the integration focused: durable memory, live collaboration, code review, and cited research through one MCP connection."
        />

        <div className="mt-14 grid gap-5 lg:grid-cols-3">
          {steps.map((step) => (
            <article
              key={step.number}
              className="relative min-w-0 overflow-hidden rounded-2xl border border-white/[0.07] bg-[#0b0d12] p-6 sm:p-8"
            >
              <span className="absolute right-5 top-4 font-mono text-5xl font-semibold tracking-[-0.08em] text-white/[0.035]">
                {step.number}
              </span>
              <step.icon size={22} className="text-[#62d3d0]" aria-hidden="true" />
              <h3 className="mt-10 text-lg font-semibold">{step.title}</h3>
              <p className="mt-3 text-sm leading-6 text-white/42">
                {step.description}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function Protocol() {
  const tools = [
    "memory_session_open",
    "memory_sessions_list",
    "memory_topics_list",
    "memory_topic_get",
    "memory_get",
    "memory_put",
    "memory_compact",
    "get_websocket_info",
    "review_code",
    "web_search",
    "deep_research_start",
    "deep_research_status",
    "deep_research_result",
    "research_save_to_notebook",
  ];

  return (
    <section
      id="protocol"
      className="scroll-mt-20 px-4 py-24 sm:px-6 lg:px-8 lg:py-32"
    >
      <div className="mx-auto grid max-w-7xl items-center gap-14 lg:grid-cols-2 lg:gap-20">
        <div>
          <SectionIntro
            eyebrow="The protocol"
            title="Twelve tools. One clear contract."
            description="Durable memory stays central, with paid web search, cited deep research, notebook saving, live collaboration, and focused code review."
          />
          <div className="mt-9 flex flex-wrap gap-2">
            {tools.map((tool) => (
              <span
                key={tool}
                className="max-w-full break-all rounded-lg border border-white/[0.07] bg-white/[0.025] px-3 py-2 font-mono text-[10px] text-white/55"
              >
                {tool}
              </span>
            ))}
          </div>
        </div>

        <div className="min-w-0 overflow-hidden rounded-[22px] border border-white/[0.08] bg-[#090a0e]">
          <div className="flex items-center justify-between border-b border-white/[0.07] px-4 py-3">
            <div className="flex items-center gap-2">
              <div className="h-2 w-2 rounded-full bg-[#62d3d0]" />
              <span className="font-mono text-[10px] uppercase tracking-[0.15em] text-white/35">
                mcp configuration
              </span>
            </div>
            <span className="font-mono text-[9px] text-white/20">json</span>
          </div>
          <div className="overflow-x-auto p-4 sm:p-6">
            <pre className="min-w-[520px] font-mono text-[11px] leading-6 text-white/42">
              <code>{`{
  "mcpServers": {
    "noteclaw-memory": {
      "url": "https://notebackend.pikpam.com/mcp",
      "headers": {
        "Authorization": "Bearer nclaw_••••••••"
      }
    }
  }
}`}</code>
            </pre>
          </div>
          <div className="border-t border-white/[0.07] px-4 py-3 font-mono text-[9px] text-white/25 sm:px-6">
            Hosted Streamable HTTP. Local stdio remains available as a fallback.
          </div>
        </div>
      </div>
    </section>
  );
}

function Security() {
  const points = [
    {
      icon: Fingerprint,
      title: "Session ownership",
      description: "Every memory read and write is checked against its owner.",
    },
    {
      icon: LockKeyhole,
      title: "Revocable secrets",
      description: "Disable a token without deleting the memory it created.",
    },
    {
      icon: Unplug,
      title: "Explicit disconnect",
      description: "End live delivery while durable context stays intact.",
    },
  ];

  return (
    <section
      id="security"
      className="scroll-mt-20 border-y border-white/[0.06] bg-[#0a0b0f] px-4 py-24 sm:px-6 lg:px-8 lg:py-32"
    >
      <div className="mx-auto grid max-w-7xl gap-14 lg:grid-cols-[0.72fr_1.28fr] lg:items-start">
        <SectionIntro
          eyebrow="Security"
          title="Your agents do not share a brain."
          description="Memory is isolated by account and session, with authentication applied to both MCP commands and the live socket."
        />

        <div className="grid gap-4 sm:grid-cols-3">
          {points.map((point) => (
            <article
              key={point.title}
              className="min-w-0 rounded-2xl border border-white/[0.07] bg-white/[0.018] p-5"
            >
              <point.icon size={19} className="text-[#62d3d0]" aria-hidden="true" />
              <h3 className="mt-6 text-sm font-semibold">{point.title}</h3>
              <p className="mt-2 text-xs leading-5 text-white/38">
                {point.description}
              </p>
            </article>
          ))}
        </div>
      </div>
    </section>
  );
}

function FinalCta() {
  return (
    <section className="px-4 py-24 sm:px-6 lg:px-8 lg:py-32">
      <div className="cta-panel relative mx-auto max-w-7xl overflow-hidden rounded-[28px] border border-[#62d3d0]/15 px-6 py-16 text-center sm:px-10 sm:py-20">
        <Sparkles
          size={24}
          className="mx-auto text-[#62d3d0]"
          aria-hidden="true"
        />
        <h2 className="mx-auto mt-6 max-w-3xl text-3xl font-semibold tracking-[-0.045em] text-balance sm:text-5xl">
          Let the next session begin where the last one ended.
        </h2>
        <p className="mx-auto mt-5 max-w-xl text-sm leading-6 text-white/48 sm:text-base">
          Open your memory bank, create an MCP token, and connect the agent you
          already use.
        </p>
        <div className="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <Link
            href="/signup"
            className="inline-flex min-h-12 w-full items-center justify-center gap-2 rounded-full bg-[#62d3d0] px-6 py-3 text-sm font-semibold text-[#101307] transition hover:bg-[#a8ebe7] sm:w-auto"
          >
            Create your memory bank
            <ArrowRight size={17} aria-hidden="true" />
          </Link>
          <Link
            href="/login"
            className="inline-flex min-h-12 w-full items-center justify-center rounded-full border border-white/12 px-6 py-3 text-sm font-medium text-white/70 transition hover:border-white/25 hover:text-white sm:w-auto"
          >
            Sign in
          </Link>
        </div>
      </div>
    </section>
  );
}

function SectionIntro({
  eyebrow,
  title,
  description,
}: {
  eyebrow: string;
  title: string;
  description: string;
}) {
  return (
    <div className="max-w-2xl">
      <div className="font-mono text-[10px] uppercase tracking-[0.2em] text-[#62d3d0]/75">
        {eyebrow}
      </div>
      <h2 className="mt-5 text-3xl font-semibold tracking-[-0.045em] text-balance sm:text-5xl">
        {title}
      </h2>
      <p className="mt-5 text-sm leading-6 text-white/45 sm:text-base sm:leading-7">
        {description}
      </p>
    </div>
  );
}

function Footer() {
  return (
    <footer className="border-t border-white/[0.06] px-4 py-8 sm:px-6 lg:px-8">
      <div className="mx-auto flex max-w-7xl flex-col items-center justify-between gap-5 sm:flex-row">
        <div className="flex items-center gap-2.5">
          <Image src="/icon.png" alt="" width={26} height={26} className="rounded-lg" />
          <span className="text-sm font-semibold">NoteClaw Memory</span>
        </div>
        <div className="flex flex-wrap items-center justify-center gap-x-5 gap-y-2 text-xs text-white/35">
          <a href="#product" className="transition-colors hover:text-white">
            Product
          </a>
          <a href="#protocol" className="transition-colors hover:text-white">
            Protocol
          </a>
          <Link href="/login" className="transition-colors hover:text-white">
            Sign in
          </Link>
          <Link href="/plans" className="transition-colors hover:text-white">
            Plans
          </Link>
        </div>
        <p className="text-xs text-white/25">
          © {new Date().getFullYear()} NoteClaw
        </p>
      </div>
    </footer>
  );
}
