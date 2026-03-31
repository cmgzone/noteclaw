import { createContext, useContext, useState, useEffect } from 'react';
import api from '../lib/api';

const AuthContext = createContext(null);

export function AuthProvider({ children }) {
    const [user, setUser] = useState(null);
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        checkAuth();
    }, []);

    const checkAuth = async () => {
        const token = api.getToken();
        if (!token) {
            setLoading(false);
            return;
        }

        try {
            const response = await api.getCurrentUser();
            if (response.success && response.user) {
                // Verify user is admin
                if (response.user.role !== 'admin') {
                    throw new Error('Not an admin user');
                }
                setUser(response.user);
            } else {
                api.clearTokens();
            }
        } catch (error) {
            console.error('Auth check failed:', error);
            api.clearTokens();
        } finally {
            setLoading(false);
        }
    };

    const login = async (email, password) => {
        try {
            const response = await api.login(email, password);
            
            if (response.success && response.user) {
                // Verify user is admin
                if (response.user.role !== 'admin') {
                    api.clearTokens();
                    throw new Error('Access denied. Admin privileges required.');
                }
                
                setUser(response.user);
                return response.user;
            } else {
                throw new Error(response.error || 'Login failed');
            }
        } catch (error) {
            console.error('Login error:', error);
            throw error;
        }
    };

    const logout = () => {
        api.clearTokens();
        setUser(null);
    };

    return (
        <AuthContext.Provider value={{ user, login, logout, loading }}>
            {children}
        </AuthContext.Provider>
    );
}

export const useAuth = () => useContext(AuthContext);
