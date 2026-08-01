"use client";

import React, { createContext, useContext, useState, useEffect, ReactNode } from "react";
import api, { SignupResponse, User } from "./api";

interface AuthContextType {
    user: User | null;
    isLoading: boolean;
    isAuthenticated: boolean;
    login: (email: string, password: string, rememberMe?: boolean) => Promise<void>;
    signup: (email: string, password: string, displayName?: string) => Promise<SignupResponse>;
    logout: () => void;
    refreshUser: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
    const [user, setUser] = useState<User | null>(null);
    const [isLoading, setIsLoading] = useState(true);

    useEffect(() => {
        // Check for existing token on mount
        const token = api.getToken();
        if (token) {
            api.getCurrentUser()
                .then(setUser)
                .catch(() => {
                    api.clearTokens();
                })
                .finally(() => setIsLoading(false));
        } else {
            setIsLoading(false);
        }
    }, []);

    const login = async (email: string, password: string, rememberMe = false) => {
        const { user } = await api.login(email, password, rememberMe);
        setUser(user);
    };

    const signup = async (email: string, password: string, displayName?: string) => {
        const response = await api.signup(email, password, displayName);
        if (!response.requiresEmailVerification && response.accessToken) {
            setUser(response.user);
        }
        return response;
    };

    const logout = () => {
        api.logout();
        setUser(null);
    };

    const refreshUser = async () => {
        const user = await api.getCurrentUser();
        setUser(user);
    };

    return (
        <AuthContext.Provider
            value={{
                user,
                isLoading,
                isAuthenticated: !!user,
                login,
                signup,
                logout,
                refreshUser,
            }}
        >
            {children}
        </AuthContext.Provider>
    );
}

export function useAuth() {
    const context = useContext(AuthContext);
    if (context === undefined) {
        throw new Error("useAuth must be used within an AuthProvider");
    }
    return context;
}
