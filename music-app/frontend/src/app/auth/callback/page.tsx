"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { LoaderCircle, TriangleAlert } from "lucide-react";
import { supabase } from "@/lib/supabase";

export default function AuthCallbackPage() {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const finish = async () => {
      const params = new URLSearchParams(window.location.search);
      const callbackError = params.get("error_description") || params.get("error");
      if (callbackError) {
        if (active) setError(callbackError);
        return;
      }

      const code = params.get("code");
      if (code) {
        const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code);
        if (exchangeError) {
          if (active) setError(exchangeError.message);
          return;
        }
      }

      const { data, error: sessionError } = await supabase.auth.getSession();
      if (!active) return;
      if (sessionError) {
        setError(sessionError.message);
        return;
      }
      if (data.session) router.replace("/");
    };

    void finish();
    const { data } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active && session) router.replace("/");
    });
    const timeout = window.setTimeout(() => {
      if (active) setError("Sign-in callback timed out. Please return to InnerWave and try again.");
    }, 15000);

    return () => {
      active = false;
      window.clearTimeout(timeout);
      data.subscription.unsubscribe();
    };
  }, [router]);

  return (
    <main className="auth-shell">
      <section className="auth-card auth-confirmation">
        {error ? <TriangleAlert size={48} /> : <LoaderCircle className="spin" size={48} />}
        <h1>{error ? "Could not finish sign in" : "Finishing sign in…"}</h1>
        <p>{error || "InnerWave is securely restoring your session."}</p>
        {error && <button className="auth-primary" onClick={() => router.replace("/")}>Back to sign in</button>}
      </section>
    </main>
  );
}
