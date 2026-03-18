"use client";

import React, { useState, useEffect, useRef } from "react";
import { motion, useAnimation, useMotionValue, useSpring, useTransform } from "framer-motion";
import {
  Search,
  Globe,
  Sparkles,
  ArrowRight,
  Zap,
  ShieldCheck,
  BookOpen,
  Check,
  Crown,
  Rocket,
  Loader2,
  Mic,
  Headphones,
  Book,
  GraduationCap,
  Youtube,
  Plug
} from "lucide-react";
import Image from "next/image";
import api from "@/lib/api";
import Link from "next/link";


// --- HOOKS ---
function useMousePosition() {
  const mouseX = useMotionValue(0);
  const mouseY = useMotionValue(0);

  useEffect(() => {
    const handleMouseMove = (e: MouseEvent) => {
      mouseX.set(e.clientX);
      mouseY.set(e.clientY);
      document.documentElement.style.setProperty("--mouse-x", `${e.clientX}px`);
      document.documentElement.style.setProperty("--mouse-y", `${e.clientY}px`);
    };
    window.addEventListener("mousemove", handleMouseMove);
    return () => window.removeEventListener("mousemove", handleMouseMove);
  }, [mouseX, mouseY]);

  return { mouseX, mouseY };
}

// --- COMPONENTS ---
function Magnetic({ children }: { children: React.ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const springX = useSpring(x, { stiffness: 150, damping: 15 });
  const springY = useSpring(y, { stiffness: 150, damping: 15 });

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!ref.current) return;
    const { clientX, clientY } = e;
    const { left, top, width, height } = ref.current.getBoundingClientRect();
    const centerX = left + width / 2;
    const centerY = top + height / 2;
    x.set((clientX - centerX) * 0.35);
    y.set((clientY - centerY) * 0.35);
  };

  const handleMouseLeave = () => {
    x.set(0);
    y.set(0);
  };

  return (
    <motion.div
      ref={ref}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
      style={{ x: springX, y: springY }}
    >
      {children}
    </motion.div>
  );
}

function NodeNetwork() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const { mouseX, mouseY } = useMousePosition();

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    let particles: { x: number; y: number; vx: number; vy: number; size: number }[] = [];
    const particleCount = 40;

    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };

    const createParticles = () => {
      particles = [];
      for (let i = 0; i < particleCount; i++) {
        particles.push({
          x: Math.random() * canvas.width,
          y: Math.random() * canvas.height,
          vx: (Math.random() - 0.5) * 0.5,
          vy: (Math.random() - 0.5) * 0.5,
          size: Math.random() * 2,
        });
      }
    };

    const animate = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      ctx.strokeStyle = "rgba(59, 130, 246, 0.15)";
      ctx.lineWidth = 0.5;

      const mX = mouseX.get();
      const mY = mouseY.get();

      particles.forEach((p, i) => {
        p.x += p.vx;
        p.y += p.vy;

        if (p.x < 0 || p.x > canvas.width) p.vx *= -1;
        if (p.y < 0 || p.y > canvas.height) p.vy *= -1;

        // Draw particle
        ctx.fillStyle = "rgba(255, 255, 255, 0.2)";
        ctx.beginPath();
        ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
        ctx.fill();

        // Connect to mouse
        const dx = mX - p.x;
        const dy = mY - p.y;
        const dist = Math.sqrt(dx * dx + dy * dy);

        if (dist < 200) {
          ctx.beginPath();
          ctx.moveTo(p.x, p.y);
          ctx.lineTo(mX, mY);
          ctx.stroke();
        }

        // Connect to other particles
        for (let j = i + 1; j < particles.length; j++) {
          const p2 = particles[j];
          const dx2 = p.x - p2.x;
          const dy2 = p.y - p2.y;
          const dist2 = Math.sqrt(dx2 * dx2 + dy2 * dy2);

          if (dist2 < 150) {
            ctx.beginPath();
            ctx.moveTo(p.x, p.y);
            ctx.lineTo(p2.x, p2.y);
            ctx.stroke();
          }
        }
      });
      requestAnimationFrame(animate);
    };

    window.addEventListener("resize", resize);
    resize();
    createParticles();
    animate();

    return () => window.removeEventListener("resize", resize);
  }, [mouseX, mouseY]);

  return <canvas ref={canvasRef} className="fixed inset-0 z-0 pointer-events-none opacity-50" />;
}

function NebulaField() {
  return (
    <>
      <div className="nebula w-[800px] h-[800px] -top-96 -left-96 bg-blue-600/10" />
      <div className="nebula w-[600px] h-[600px] top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-purple-600/5 animation-delay-2000" />
      <div className="nebula w-[700px] h-[700px] -bottom-96 -right-96 bg-blue-400/5 animation-delay-4000" />
    </>
  );
}

export default function LandingPage() {
  useMousePosition();

  return (
    <div className="relative min-h-screen bg-neutral-950 text-white selection:bg-blue-500/30 overflow-hidden">
      <div className="grain-overlay" />
      <div className="mouse-spotlight" />
      <StarField />
      <NebulaField />
      <NodeNetwork />
      <Navbar />
      <div className="relative z-10">
        <HeroSection />
        <LiveFeedTicker />
        <FeaturesSection />
        <PricingSection />
        <Footer />
      </div>

    </div>
  );
}

function LiveFeedTicker() {
  const [logs, setLogs] = useState<string[]>([]);
  const logEntries = [
    "FETCH: IEEE Xplore - Neural Networks Architecture",
    "SCRAPE: Wikipedia.org/wiki/Artificial_Intelligence",
    "ANALYZE: Global Market Trends 2025",
    "CROSS-REF: Source A & Source B",
    "GENERATE: Executive Summary",
    "VALIDATE: Accuracy 98.4%",
    "INGEST: Local Research Documents",
    "QUERY: Advanced Vector Database"
  ];

  useEffect(() => {
    const interval = setInterval(() => {
      setLogs((prev) => [logEntries[Math.floor(Math.random() * logEntries.length)], ...prev].slice(0, 3));
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="container mx-auto px-6 py-12 pointer-events-none">
      <div className="flex flex-col items-center gap-2 opacity-30 lowercase font-mono text-[10px] tracking-widest uppercase">
        {logs.map((log, i) => (
          <motion.div
            key={i}
            initial={{ opacity: 0, x: -10 }}
            animate={{ opacity: 1 - i * 0.3, x: 0 }}
            className="flex items-center gap-2"
          >
            <span className="h-1 w-1 bg-blue-500 rounded-full" />
            {log}
          </motion.div>
        ))}
      </div>
    </div>
  );
}



function StarField() {
  return (
    <div className="starfield-container opacity-40">
      <div className="stars-layer stars-1" />
      <div className="stars-layer stars-2" />
      <div className="stars-layer stars-3 twinkle" />
    </div>
  );
}


function Navbar() {
  return (
    <nav className="fixed top-0 left-0 right-0 z-50 border-b border-white/5 bg-neutral-950/20 backdrop-blur-2xl">
      <div className="container mx-auto flex h-20 items-center justify-between px-6">
        <div className="flex items-center gap-2 group cursor-pointer">
          <Image src="/icon.png" alt="NoteClaw" width={32} height={32} className="rounded-lg group-hover:scale-110 transition-all duration-500" />
          <span className="text-xl font-bold tracking-tighter text-white">NoteClaw</span>
        </div>
        <div className="hidden items-center gap-10 text-xs font-semibold uppercase tracking-widest text-neutral-400 md:flex">
          <a href="#" className="hover:text-blue-400 transition-colors">Features</a>
          <a href="#" className="hover:text-blue-400 transition-colors">Technology</a>
          <a href="#pricing" className="hover:text-blue-400 transition-colors">Pricing</a>
          <Link href="/docs" className="hover:text-blue-400 transition-colors">Docs</Link>
        </div>
        <div className="flex items-center gap-6">
          <a href="/login" className="text-sm font-semibold text-neutral-400 hover:text-white transition-colors">
            Log In
          </a>
          <Magnetic>
            <button className="rounded-full bg-white px-6 py-2.5 text-sm font-bold text-neutral-950 hover:bg-blue-400 hover:text-white transition-all">
              Join Waitlist
            </button>
          </Magnetic>
        </div>
      </div>
    </nav>
  );
}


function HeroSection() {
  return (
    <section className="relative flex min-h-screen flex-col items-center justify-center overflow-hidden px-6 pt-20">
      {/* Background Gradients */}
      <div className="absolute top-1/4 -left-1/4 h-[500px] w-[500px] rounded-full bg-blue-600/20 blur-[120px]" />
      <div className="absolute bottom-1/4 -right-1/4 h-[500px] w-[500px] rounded-full bg-purple-600/10 blur-[120px]" />

      <div className="container relative mx-auto grid lg:grid-cols-2 gap-12 items-center">
        <div className="text-center lg:text-left">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.6 }}
          >
            <div className="inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-3 py-1 text-xs font-medium backdrop-blur-md">
              <span className="flex h-2 w-2 rounded-full bg-green-500 animate-pulse" />
              New: Deep Research v2.0
            </div>
            <h1 className="mt-6 text-5xl font-bold tracking-tight sm:text-7xl bg-gradient-to-b from-white to-white/60 bg-clip-text text-transparent">
              Research at the <br /> speed of thought.
            </h1>
            <p className="mt-6 text-lg text-neutral-400 max-w-2xl mx-auto lg:mx-0">
              Transform how you gather information. Our autonomous AI agent dives deep into the web, analyzing thousands of sources to generate comprehensive reports in minutes.
            </p>
            <div className="mt-8 flex flex-col sm:flex-row items-center gap-4 justify-center lg:justify-start">
              <Magnetic>
                <button className="group flex items-center gap-2 rounded-full bg-blue-600 px-8 py-4 font-semibold text-white hover:bg-blue-500 hover:shadow-lg hover:shadow-blue-500/20 transition-all">
                  Download for iOS
                  <ArrowRight size={18} className="transition-transform group-hover:translate-x-1" />
                </button>
              </Magnetic>
              <Magnetic>
                <button className="flex items-center gap-2 rounded-full border border-white/10 bg-white/5 px-8 py-4 font-semibold text-white hover:bg-white/10 transition-colors backdrop-blur-md">
                  <Search size={18} />
                  View Demo
                </button>
              </Magnetic>
            </div>

          </motion.div>
        </div>

        {/* 3D Core Demo */}
        <div className="relative flex items-center justify-center">
          <Magnetic>
            <DeepResearchVisualizer />
          </Magnetic>
        </div>

      </div>
    </section>
  );
}

function DeepResearchVisualizer() {
  const [status, setStatus] = useState("Initializing...");
  const [source, setSource] = useState<string | null>(null);

  useEffect(() => {
    const states = [
      { text: "Scanning academic sources...", domain: null },
      { text: "Found data on wikipedia.org", domain: "wikipedia.org" },
      { text: "Analyzing trends...", domain: null },
      { text: "Cross-referencing nature.com", domain: "nature.com" },
      { text: "Synthesizing report...", domain: null },
      { text: "Deep Research Active", domain: null },
    ];
    let i = 0;
    const interval = setInterval(() => {
      setStatus(states[i].text);
      setSource(states[i].domain);
      i = (i + 1) % states.length;
    }, 2500);
    return () => clearInterval(interval);
  }, []);

  return (
    <div className="relative h-[400px] w-[400px] flex items-center justify-center">
      {/* Rings */}
      <motion.div
        animate={{ rotateX: 360, rotateY: 180 }}
        transition={{ duration: 20, repeat: Infinity, ease: "linear" }}
        className="absolute h-64 w-64 rounded-full border border-blue-500/30 border-t-blue-400"
        style={{ transformStyle: "preserve-3d" }}
      />
      <motion.div
        animate={{ rotateX: -360, rotateY: -90 }}
        transition={{ duration: 15, repeat: Infinity, ease: "linear" }}
        className="absolute h-48 w-48 rounded-full border border-purple-500/30 border-b-purple-400"
        style={{ transformStyle: "preserve-3d" }}
      />

      {/* Core */}
      <div className="relative h-24 w-24 rounded-full bg-neutral-900 border border-white/10 shadow-[0_0_50px_-12px_rgba(59,130,246,0.5)] flex items-center justify-center z-10 backdrop-blur-xl">
        {source ? (
          <Image
            src={`https://www.google.com/s2/favicons?domain=${source}&sz=64`}
            width={40}
            height={40}
            alt="Source"
            className="opacity-90 grayscale hover:grayscale-0 transition-all"
          />
        ) : (
          <Globe className="text-blue-400 animate-pulse" size={40} />
        )}
      </div>

      {/* Floating Status Card */}
      <motion.div
        key={status}
        initial={{ opacity: 0, y: 10 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0 }}
        className="absolute bottom-0 w-64 rounded-xl border border-white/10 bg-neutral-900/80 p-4 backdrop-blur-md shadow-xl"
      >
        <div className="flex items-center gap-3">
          <div className="flex h-2 w-2 relative">
            <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-blue-400 opacity-75"></span>
            <span className="relative inline-flex rounded-full h-2 w-2 bg-blue-500"></span>
          </div>
          <span className="text-sm font-medium text-neutral-200">{status}</span>
        </div>
        <div className="mt-3 h-1 w-full rounded-full bg-neutral-800 overflow-hidden">
          <motion.div
            className="h-full bg-blue-500"
            initial={{ width: "0%" }}
            animate={{ width: "100%" }}
            transition={{ duration: 2.5, ease: "linear", repeat: Infinity }}
          />
        </div>
      </motion.div>
    </div>
  );
}

function FeaturesSection() {
  const features = [
    {
      icon: <Globe className="text-blue-400" />,
      title: "Deep Research Agent",
      desc: "Our autonomous browser agent dives deep into the web, analyzing thousands of sources to generate comprehensive, cited reports in minutes."
    },
    {
      icon: <Plug className="text-cyan-400" />,
      title: "MCP Server Integration",
      desc: "Connect your favorite AI coding agents like Kiro, Claude, or Cursor directly to your notebooks via Model Context Protocol for seamless knowledge access."
    },
    {
      icon: <Mic className="text-purple-400" />,
      title: "Voice-First Research",
      desc: "Interact with your data using our advanced Narrator mode. Get instant voice feedback and control your research entirely through speech."
    },
    {
      icon: <Headphones className="text-green-400" />,
      title: "AI Podcast Studio",
      desc: "Transform your notebooks into high-quality audio discussions. Generate podcast-style overviews with life-like AI hosts in seconds."
    },
    {
      icon: <Book className="text-amber-400" />,
      title: "Ebook Generator",
      desc: "Instantly turn research threads and notebook collections into beautifully structured PDF ebooks ready for sharing or publication."
    },
    {
      icon: <GraduationCap className="text-red-400" />,
      title: "Smart AI Tutor",
      desc: "Master any subject with gamified learning. Generate quizzes, track your XP streaks, and get personalized teaching from your data."
    },
    {
      icon: <Youtube className="text-rose-500" />,
      title: "Multimedia Analysis",
      desc: "Analyze more than just text. Ingest YouTube videos, academic PDFs, and live web pages for a truly 360-degree understanding."
    },
    {
      icon: <Sparkles className="text-orange-400" />,
      title: "Custom Agent Skills",
      desc: "Teach your AI Agent specialized capabilities. Define custom prompts, workflows, and rules that persist across sessions."
    }
  ];

  return (
    <section className="py-24 relative overflow-hidden">
      <div className="container mx-auto px-6">
        <div className="grid md:grid-cols-3 gap-8">
          {features.map((feature, i) => (
            <motion.div
              key={i}
              initial={{ opacity: 0, y: 30 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.5, delay: i * 0.1 }}
              className="group glass-card p-8 rounded-3xl"
            >
              <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-blue-600/10 group-hover:bg-blue-600/20 transition-colors">
                {feature.icon}
              </div>
              <h3 className="text-2xl font-bold text-white">{feature.title}</h3>
              <p className="mt-4 text-neutral-400 leading-relaxed text-lg">{feature.desc}</p>
            </motion.div>
          ))}
        </div>
      </div>
    </section>
  );
}

function PricingSection() {
  const [plans, setPlans] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.getPlans().then(data => {
      setPlans(data);
      setLoading(false);
    }).catch(err => {
      console.error("Failed to load plans:", err);
      setLoading(false);
    });
  }, []);

  const getPlanIcon = (name: string) => {
    switch (name.toLowerCase()) {
      case 'pro': return <Crown className="text-blue-400" size={24} />;
      case 'ultra': return <Rocket className="text-purple-400" size={24} />;
      default: return <Zap className="text-amber-400" size={24} />;
    }
  };

  return (
    <section className="py-24 relative overflow-hidden" id="pricing">
      <div className="container mx-auto px-6">
        <div className="text-center mb-16">
          <h2 className="text-4xl font-bold tracking-tight mb-4">Simple, Transparent Pricing</h2>
          <p className="text-neutral-400 text-lg">Choose the plan that fits your research needs.</p>
        </div>

        {loading ? (
          <div className="flex justify-center py-20">
            <Loader2 className="animate-spin text-blue-500" size={40} />
          </div>
        ) : (
          <div className="grid md:grid-cols-3 gap-8 max-w-6xl mx-auto">
            {plans.map((plan, i) => (
              <motion.div
                key={plan.id}
                initial={{ opacity: 0, scale: 0.95 }}
                whileInView={{ opacity: 1, scale: 1 }}
                viewport={{ once: true }}
                transition={{ duration: 0.5, delay: i * 0.1 }}
                className={`group glass-card p-10 rounded-3xl relative flex flex-col ${plan.name.toLowerCase() === 'pro' ? 'border-blue-500/30 ring-1 ring-blue-500/20' : ''}`}
              >
                {plan.name.toLowerCase() === 'pro' && (
                  <div className="absolute -top-4 left-10 px-4 py-1 bg-blue-600 text-xs font-bold rounded-full uppercase tracking-tighter">
                    Most Popular
                  </div>
                )}
                <div className="mb-8 flex items-center gap-4">
                  <div className="h-12 w-12 rounded-2xl bg-white/5 flex items-center justify-center shrink-0">
                    {getPlanIcon(plan.name)}
                  </div>
                  <div>
                    <h3 className="text-2xl font-bold">{plan.name}</h3>
                    <p className="text-sm text-neutral-400 line-clamp-1">{plan.description}</p>
                  </div>
                </div>

                <div className="mb-8">
                  <span className="text-5xl font-bold">${parseFloat(plan.price).toFixed(0)}</span>
                  <span className="text-neutral-500 text-lg">/month</span>
                </div>

                <ul className="space-y-4 mb-10 flex-grow">
                  <li className="flex items-center gap-3 text-neutral-200">
                    <Check size={20} className="text-blue-400" />
                    <span className="text-sm font-medium">{plan.credits_per_month.toLocaleString()} Credits / mo</span>
                  </li>
                  <li className="flex items-center gap-3 text-neutral-200">
                    <Check size={20} className="text-blue-400" />
                    <span className="text-sm">{plan.is_free_plan ? 'Up to 5 Notebooks' : 'Unlimited Notebooks'}</span>
                  </li>
                  {plan.name.toLowerCase() === 'free' && (
                    <li className="flex items-center gap-3 text-neutral-200">
                      <Check size={20} className="text-blue-400" />
                      <span className="text-sm">Standard AI Search</span>
                    </li>
                  )}
                  {plan.name.toLowerCase() === 'pro' && (
                    <>
                      <li className="flex items-center gap-3 text-neutral-200">
                        <Check size={20} className="text-blue-400" />
                        <span className="text-sm">Autonomous Deep Research</span>
                      </li>
                      <li className="flex items-center gap-3 text-neutral-200">
                        <Check size={20} className="text-blue-400" />
                        <span className="text-sm">AI Podcast Studio</span>
                      </li>
                    </>
                  )}
                  {plan.name.toLowerCase() === 'ultra' && (
                    <>
                      <li className="flex items-center gap-3 text-neutral-200">
                        <Check size={20} className="text-blue-400" />
                        <span className="text-sm">Unlimited Ebook Creator</span>
                      </li>
                      <li className="flex items-center gap-3 text-neutral-200">
                        <Check size={20} className="text-blue-400" />
                        <span className="text-sm">Priority Voice Narrator</span>
                      </li>
                    </>
                  )}
                  <li className="flex items-center gap-3 text-neutral-200">
                    <Check size={20} className="text-blue-400" />
                    <span className="text-sm">Gamified Learning & Quizzes</span>
                  </li>
                </ul>

                <Link href="/login" className="block w-full text-center py-4 rounded-2xl font-bold bg-white text-neutral-950 hover:bg-blue-400 hover:text-white transition-all duration-300">
                  {plan.is_free_plan ? 'Start for Free' : 'Get Started'}
                </Link>
              </motion.div>
            ))}
          </div>
        )}
      </div>
    </section>
  );
}


function Footer() {
  return (
    <footer className="border-t border-white/5 bg-neutral-950 py-12">
      <div className="container mx-auto px-6 text-center text-neutral-500 text-sm">
        <p>© 2025 NoteClaw. Built for the future of research.</p>
      </div>
    </footer>
  );
}
