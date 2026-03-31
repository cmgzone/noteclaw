import { BrowserRouter, Routes, Route, Navigate, Outlet } from 'react-router-dom';
import { AuthProvider, useAuth } from './contexts/AuthContext';
import Layout from './components/Layout';
import Login from './pages/Login';
import Dashboard from './pages/Dashboard';
import Settings from './pages/Settings';
import OnboardingManager from './pages/OnboardingManager';
import PrivacyPolicyEditor from './pages/PrivacyPolicyEditor';
import UserManagement from './pages/UserManagement';
import SubscriptionPlans from './pages/SubscriptionPlans';
import PaymentTransactions from './pages/PaymentTransactions';
import CreditPackages from './pages/CreditPackages';
import AIModels from './pages/AIModels';
import StorageManager from './pages/StorageManager';
import McpSettings from './pages/McpSettings';
import NotificationManager from './pages/NotificationManager';
import DataManager from './pages/DataManager';

function ProtectedRoute() {
  const { user, loading } = useAuth();
  if (loading) return <div className="flex h-screen items-center justify-center">Loading...</div>;
  return user ? <Outlet /> : <Navigate to="/login" />;
}

export default function App() {
  return (
    <Router />
  );
}

function Router() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<Login />} />

          <Route element={<ProtectedRoute />}>
            <Route element={<Layout />}>
              <Route path="/" element={<Dashboard />} />
              <Route path="/users" element={<UserManagement />} />
              <Route path="/content" element={<DataManager />} />
              <Route path="/notifications" element={<NotificationManager />} />
              <Route path="/subscription-plans" element={<SubscriptionPlans />} />
              <Route path="/credit-packages" element={<CreditPackages />} />
              <Route path="/transactions" element={<PaymentTransactions />} />
              <Route path="/settings" element={<Settings />} />
              <Route path="/storage" element={<StorageManager />} />
              <Route path="/onboarding" element={<OnboardingManager />} />
              <Route path="/privacy" element={<PrivacyPolicyEditor />} />
              <Route path="/ai-models" element={<AIModels />} />
              <Route path="/mcp-settings" element={<McpSettings />} />
            </Route>
          </Route>
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}
