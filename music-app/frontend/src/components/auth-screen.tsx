"use client";

import { Disc3, LoaderCircle, MailCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { useAuth } from "@/context/auth-context";

export function AuthScreen() {
  const auth = useAuth();
  const [mode, setMode] = useState<"signin" | "signup">("signin");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [verificationSent, setVerificationSent] = useState(false);

  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null);
    const result = mode === "signup" ? await auth.signUp(name, email.trim(), password) : await auth.signIn(email.trim(), password);
    setBusy(false); setError(result.error); setVerificationSent(Boolean(result.needsEmailVerification));
  }
  async function google() {
    setBusy(true); setError(null);
    const result = await auth.signInWithGoogle();
    if (result.error) { setError(result.error); setBusy(false); }
  }

  if (verificationSent) return (
    <main className="auth-shell"><section className="auth-card auth-confirmation">
      <MailCheck size={42} /><h1>Verify your email</h1><p>We sent a confirmation link to <strong>{email}</strong>. Verify it, then come back and sign in.</p>
      <button className="auth-primary" onClick={() => { setVerificationSent(false); setMode("signin"); }}>Back to sign in</button>
    </section></main>
  );

  return <main className="auth-shell"><section className="auth-card">
    <div className="auth-brand"><span><Disc3 size={24} /></span><b>InnerWave</b></div>
    <h1>{mode === "signin" ? "Welcome back" : "Create your account"}</h1>
    <p className="auth-subtitle">Your music and active playback device stay in sync everywhere.</p>
    <button className="google-button" onClick={google} disabled={busy}><span className="google-mark">G</span> Continue with Google</button>
    <div className="auth-divider"><span>or</span></div>
    <form onSubmit={submit}>
      {mode === "signup" && <label>Display name<input value={name} onChange={(event) => setName(event.target.value)} required minLength={2} maxLength={40} autoComplete="name" /></label>}
      <label>Email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="email" /></label>
      <label>Password<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required minLength={8} autoComplete={mode === "signup" ? "new-password" : "current-password"} /></label>
      {error && <div className="auth-error">{error}</div>}
      <button className="auth-primary" type="submit" disabled={busy || (mode === "signup" && name.trim().length < 2)}>{busy ? <LoaderCircle className="spin" size={18} /> : mode === "signin" ? "Sign in" : "Sign up"}</button>
    </form>
    <button className="auth-switch" onClick={() => { setMode((value) => value === "signin" ? "signup" : "signin"); setError(null); }}>{mode === "signin" ? "New to InnerWave? Create account" : "Already have an account? Sign in"}</button>
  </section></main>;
}
