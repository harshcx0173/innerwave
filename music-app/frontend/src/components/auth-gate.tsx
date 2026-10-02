"use client";

import type { ReactNode } from "react";
import { LoaderCircle } from "lucide-react";
import { useAuth } from "@/context/auth-context";
import { AuthScreen } from "./auth-screen";

export function AuthGate({ children }: { children: ReactNode }) {
  const { loading, passwordRecovery, user } = useAuth();
  if (loading) return <main className="auth-shell"><LoaderCircle className="spin" size={30} /></main>;
  if (passwordRecovery) return <AuthScreen initialMode="recovery" />;
  if (!user) return <AuthScreen />;
  return children;
}
