"use client";

import type { Session, User } from "@supabase/supabase-js";
import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import { supabase } from "@/lib/supabase";
import { validateEmailNotDisposable } from "@/lib/disposable-email";

type AuthResult = { error: string | null; needsEmailVerification?: boolean };
type AuthContextValue = {
  session: Session | null;
  user: User | null;
  loading: boolean;
  displayName: string;
  signIn: (email: string, password: string) => Promise<AuthResult>;
  signUp: (name: string, email: string, password: string) => Promise<AuthResult>;
  resendVerification: (email: string) => Promise<AuthResult>;
  sendPasswordReset: (email: string) => Promise<AuthResult>;
  updatePassword: (password: string) => Promise<AuthResult>;
  updateProfile: (name: string) => Promise<AuthResult>;
  signInWithGoogle: () => Promise<AuthResult>;
  signOut: () => Promise<void>;
  passwordRecovery: boolean;
  finishPasswordRecovery: () => void;
};

const AuthContext = createContext<AuthContextValue | null>(null);

function authCallbackUrl() {
  return new URL("/auth/callback", window.location.origin).toString();
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [passwordRecovery, setPasswordRecovery] = useState(false);

  useEffect(() => {
    let mounted = true;
    supabase.auth.getSession().then(({ data }) => {
      if (mounted) { setSession(data.session); setLoading(false); }
    });
    const { data } = supabase.auth.onAuthStateChange((event, nextSession) => {
      setSession(nextSession);
      if (event === "PASSWORD_RECOVERY") setPasswordRecovery(true);
      if (event === "SIGNED_OUT") setPasswordRecovery(false);
      setLoading(false);
    });
    return () => { mounted = false; data.subscription.unsubscribe(); };
  }, []);

  const signIn = useCallback(async (email: string, password: string): Promise<AuthResult> => {
    const validation = await validateEmailNotDisposable(email);
    if (!validation.valid) {
      return { error: validation.error || "Disposable or temporary email addresses are not allowed." };
    }
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    return { error: error?.message ?? null };
  }, []);
  const signUp = useCallback(async (name: string, email: string, password: string): Promise<AuthResult> => {
    const validation = await validateEmailNotDisposable(email);
    if (!validation.valid) {
      return { error: validation.error || "Disposable or temporary email addresses are not allowed." };
    }
    const { data, error } = await supabase.auth.signUp({
      email: email.trim(),
      password,
      options: { emailRedirectTo: authCallbackUrl(), data: { display_name: name.trim() } },
    });
    return { error: error?.message ?? null, needsEmailVerification: !error && !data.session };
  }, []);
  const signInWithGoogle = useCallback(async (): Promise<AuthResult> => {
    const { error } = await supabase.auth.signInWithOAuth({ provider: "google", options: { redirectTo: authCallbackUrl() } });
    return { error: error?.message ?? null };
  }, []);
  const resendVerification = useCallback(async (email: string): Promise<AuthResult> => {
    const validation = await validateEmailNotDisposable(email);
    if (!validation.valid) {
      return { error: validation.error || "Disposable or temporary email addresses are not allowed." };
    }
    const { error } = await supabase.auth.resend({
      type: "signup",
      email: email.trim(),
      options: { emailRedirectTo: authCallbackUrl() },
    });
    return { error: error?.message ?? null };
  }, []);
  const sendPasswordReset = useCallback(async (email: string): Promise<AuthResult> => {
    const validation = await validateEmailNotDisposable(email);
    if (!validation.valid) {
      return { error: validation.error || "Disposable or temporary email addresses are not allowed." };
    }
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: authCallbackUrl(),
    });
    return { error: error?.message ?? null };
  }, []);
  const updatePassword = useCallback(async (password: string): Promise<AuthResult> => {
    const { error } = await supabase.auth.updateUser({ password });
    if (!error) setPasswordRecovery(false);
    return { error: error?.message ?? null };
  }, []);
  const updateProfile = useCallback(async (name: string): Promise<AuthResult> => {
    const { error } = await supabase.auth.updateUser({ data: { display_name: name.trim() } });
    return { error: error?.message ?? null };
  }, []);
  const finishPasswordRecovery = useCallback(() => setPasswordRecovery(false), []);
  const signOut = useCallback(async () => { await supabase.auth.signOut(); }, []);

  const user = session?.user ?? null;
  const displayName = String(user?.user_metadata?.display_name || user?.user_metadata?.full_name || user?.user_metadata?.name || user?.email?.split("@")[0] || "InnerWave Listener");
  const value = useMemo<AuthContextValue>(() => ({ session, user, loading, displayName, signIn, signUp, resendVerification, sendPasswordReset, updatePassword, updateProfile, signInWithGoogle, signOut, passwordRecovery, finishPasswordRecovery }), [displayName, finishPasswordRecovery, loading, passwordRecovery, resendVerification, sendPasswordReset, session, signIn, signInWithGoogle, signOut, signUp, updatePassword, updateProfile, user]);
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) throw new Error("useAuth must be used inside AuthProvider");
  return context;
}
