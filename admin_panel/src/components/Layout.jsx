import { Link, useLocation } from 'react-router-dom';
import { useAuth } from '../contexts/AuthContext';
import { Outlet } from 'react-router-dom';
import {
    LayoutDashboard,
    Users,
    Settings as SettingsIcon,
    LogOut,
    Smartphone,
    Shield,
    CreditCard,
    Package,
    Receipt,
    Bot,
    Cloud,
    Cpu,
    Bell,
    Database,
    Coins
} from 'lucide-react';
import clsx from 'clsx';

export default function Layout() {
    const { logout, user } = useAuth();
    const location = useLocation();

    const navigation = [
        { name: 'Dashboard', href: '/', icon: LayoutDashboard },
        { name: 'Users', href: '/users', icon: Users },
        { name: 'Play Testers', href: '/play-testers', icon: Smartphone },
        { name: 'Content & Data', href: '/content', icon: Database },
        { name: 'Notifications', href: '/notifications', icon: Bell },
        { name: 'Subscription Plans', href: '/subscription-plans', icon: CreditCard },
        { name: 'Credit Packages', href: '/credit-packages', icon: Package },
        { name: 'Feature Costs', href: '/feature-costs', icon: Coins },
        { name: 'Transactions', href: '/transactions', icon: Receipt },
        { name: 'Storage & CDN', href: '/storage', icon: Cloud },
        { name: 'MCP Settings', href: '/mcp-settings', icon: Cpu },
        { name: 'Onboarding', href: '/onboarding', icon: Smartphone },
        { name: 'Privacy Policy', href: '/privacy', icon: Shield },
        { name: 'AI Models', href: '/ai-models', icon: Bot },
        { name: 'Settings', href: '/settings', icon: SettingsIcon },
    ];

    return (
        <div className="flex h-screen bg-gray-100">
            {/* Sidebar */}
            <div className="hidden w-64 flex-col bg-white border-r border-gray-200 md:flex">
                <div className="flex h-16 items-center justify-center border-b border-gray-200 px-4">
                    <h1 className="text-xl font-bold text-gray-900">NoteClaw Admin</h1>
                </div>
                <div className="flex flex-1 flex-col overflow-y-auto pt-5 pb-4">
                    <nav className="mt-5 flex-1 space-y-1 px-2">
                        {navigation.map((item) => {
                            const isActive = location.pathname === item.href;
                            return (
                                <Link
                                    key={item.name}
                                    to={item.href}
                                    className={clsx(
                                        isActive
                                            ? 'bg-gray-100 text-gray-900'
                                            : 'text-gray-600 hover:bg-gray-50 hover:text-gray-900',
                                        'group flex items-center rounded-md px-2 py-2 text-sm font-medium'
                                    )}
                                >
                                    <item.icon
                                        className={clsx(
                                            isActive ? 'text-gray-500' : 'text-gray-400 group-hover:text-gray-500',
                                            'mr-3 h-5 w-5 flex-shrink-0'
                                        )}
                                        aria-hidden="true"
                                    />
                                    {item.name}
                                </Link>
                            );
                        })}
                    </nav>
                </div>
                <div className="border-t border-gray-200 p-4">
                    <div className="flex items-center">
                        <div className="flex-1 min-w-0">
                            <p className="truncate text-sm font-medium text-gray-900">{user?.name || 'Admin'}</p>
                            <p className="truncate text-xs text-gray-500">{user?.email}</p>
                        </div>
                        <button
                            onClick={logout}
                            className="ml-auto flex-shrink-0 rounded-full bg-white p-1 text-gray-400 hover:text-gray-500"
                        >
                            <LogOut className="h-5 w-5" />
                        </button>
                    </div>
                </div>
            </div>

            {/* Main content */}
            <div className="flex flex-1 flex-col overflow-hidden">
                <main className="flex-1 overflow-y-auto p-8">
                    <Outlet />
                </main>
            </div>
        </div>
    );
}
