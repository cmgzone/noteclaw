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
          One private memory bank for third-party agents to restore project
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
