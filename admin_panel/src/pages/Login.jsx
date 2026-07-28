import { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useNavigate } from 'react-router-dom';
import { Database, Lock, Mail, Loader2, ShieldCheck } from 'lucide-react';

export default function Login() {
    const [email, setEmail] = useState('');
    const [password, setPassword] = useState('');
    const [error, setError] = useState('');
    const [loading, setLoading] = useState(false);
    const { login } = useAuth();
    const navigate = useNavigate();

    const handleSubmit = async (e) => {
        e.preventDefault();
        setError('');
        setLoading(true);
        try {
            await login(email, password);
            navigate('/');
        } catch (err) {
            setError(err.message || 'Failed to login');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="relative flex min-h-screen items-center justify-center overflow-hidden bg-[#07090d] px-4 py-12 text-white sm:px-6 lg:px-8">
            <div className="pointer-events-none absolute inset-0">
                <div className="absolute -left-24 top-10 h-80 w-80 rounded-full bg-[#6b5bd2]/20 blur-[110px]" />
                <div className="absolute -right-20 bottom-0 h-96 w-96 rounded-full bg-[#62d2d0]/15 blur-[120px]" />
                <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.025)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.025)_1px,transparent_1px)] bg-[size:48px_48px]" />
            </div>

            <div className="relative w-full max-w-md rounded-3xl border border-white/10 bg-[#0d1118]/90 p-7 shadow-2xl shadow-black/40 backdrop-blur-xl sm:p-10">
                <div className="text-center">
                    <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-[#62d2d0] to-[#7869dc] shadow-lg shadow-[#62d2d0]/15">
                        <Database className="h-7 w-7 text-[#071015]" />
                    </div>
                    <p className="mt-5 text-xs font-semibold uppercase tracking-[0.24em] text-[#62d2d0]">
                        NoteClaw
                    </p>
                    <h1 className="mt-2 text-center text-3xl font-semibold tracking-tight text-white">
                        Admin control center
                    </h1>
                    <p className="mt-3 text-center text-sm leading-6 text-slate-400">
                        Manage accounts, plans, credits, and MCP agent access.
                    </p>
                    <div className="mt-4 inline-flex items-center gap-2 rounded-full border border-white/10 bg-white/[0.04] px-3 py-1.5 text-xs text-slate-400">
                        <ShieldCheck className="h-3.5 w-3.5 text-[#62d2d0]" />
                        Authorized administrators only
                    </div>
                </div>

                <form className="mt-8 space-y-5" onSubmit={handleSubmit}>
                    <div className="space-y-3">
                        <label className="block text-left text-xs font-medium uppercase tracking-wider text-slate-400" htmlFor="admin-email">
                            Email
                        </label>
                        <div className="relative">
                            <Mail className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-slate-500" />
                            <input
                                id="admin-email"
                                type="email"
                                required
                                autoComplete="email"
                                className="block w-full rounded-xl border border-white/10 bg-white/[0.045] py-3.5 pl-12 pr-4 text-sm text-white outline-none placeholder:text-slate-600 focus:border-[#62d2d0]/70 focus:ring-2 focus:ring-[#62d2d0]/15"
                                placeholder="admin@noteclaw.com"
                                value={email}
                                onChange={(e) => setEmail(e.target.value)}
                            />
                        </div>

                        <label className="block pt-1 text-left text-xs font-medium uppercase tracking-wider text-slate-400" htmlFor="admin-password">
                            Password
                        </label>
                        <div className="relative">
                            <Lock className="absolute left-4 top-1/2 h-5 w-5 -translate-y-1/2 text-slate-500" />
                            <input
                                id="admin-password"
                                type="password"
                                required
                                autoComplete="current-password"
                                className="block w-full rounded-xl border border-white/10 bg-white/[0.045] py-3.5 pl-12 pr-4 text-sm text-white outline-none placeholder:text-slate-600 focus:border-[#62d2d0]/70 focus:ring-2 focus:ring-[#62d2d0]/15"
                                placeholder="Enter your password"
                                value={password}
                                onChange={(e) => setPassword(e.target.value)}
                            />
                        </div>
                    </div>

                    {error && (
                        <div className="rounded-xl border border-red-400/20 bg-red-500/10 p-3.5 text-sm text-red-200">
                            {error}
                        </div>
                    )}

                    <button
                        type="submit"
                        disabled={loading}
                        className="group relative flex w-full items-center justify-center rounded-xl bg-[#62d2d0] px-4 py-3.5 text-sm font-semibold text-[#071015] transition hover:bg-[#79dfdc] focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#62d2d0] disabled:opacity-60"
                    >
                        {loading ? (
                            <>
                                <Loader2 className="mr-2 h-5 w-5 animate-spin" />
                                Signing in
                            </>
                        ) : (
                            'Sign in securely'
                        )}
                    </button>

                    <p className="text-center text-xs text-slate-600">
                        Protected access to NoteClaw production operations.
                    </p>
                </form>
            </div>
        </div>
    );
}
