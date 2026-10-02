"use client";

import { ArrowLeft, Disc3, KeyRound, LoaderCircle, MailCheck } from "lucide-react";
import { useState, type FormEvent } from "react";
import { useAuth } from "@/context/auth-context";

type AuthMode = "signin" | "signup" | "forgot" | "recovery";

export function AuthScreen({ initialMode = "signin" }: { initialMode?: AuthMode }) {
  const auth = useAuth();
  const [mode, setMode] = useState<AuthMode>(initialMode);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [verificationSent, setVerificationSent] = useState(false);
  const [resetSent, setResetSent] = useState(false);
  const [confirmPassword, setConfirmPassword] = useState("");

  async function submit(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null);
    const result = mode === "signup" ? await auth.signUp(name, email.trim(), password) : await auth.signIn(email.trim(), password);
    setBusy(false); setError(result.error); setVerificationSent(Boolean(result.needsEmailVerification));
  }
  async function requestReset(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null);
    const result = await auth.sendPasswordReset(email.trim());
    setBusy(false); setError(result.error); setResetSent(!result.error);
  }
  async function savePassword(event: FormEvent) {
    event.preventDefault(); setError(null);
    if (password.length < 8) { setError("Password must be at least 8 characters."); return; }
    if (password !== confirmPassword) { setError("Passwords do not match."); return; }
    setBusy(true);
    const result = await auth.updatePassword(password);
    setBusy(false); setError(result.error);
  }
  async function google() {
    setBusy(true); setError(null);
    const result = await auth.signInWithGoogle();
    if (result.error) { setError(result.error); setBusy(false); }
  }
  async function resend() {
    setBusy(true); setError(null);
    const result = await auth.resendVerification(email);
    setBusy(false); setError(result.error);
  }

  if (verificationSent) return (
    <main className="auth-shell"><section className="auth-card auth-confirmation">
      <MailCheck size={42} /><h1>Verify your email</h1><p>We sent a confirmation link to <strong>{email}</strong>. Verify it, then come back and sign in.</p>
      {error && <div className="auth-error">{error}</div>}
      <button className="auth-primary" onClick={resend} disabled={busy}>{busy ? <LoaderCircle className="spin" size={18} /> : "Resend verification email"}</button>
      <button className="auth-switch" onClick={() => { setVerificationSent(false); setMode("signin"); setError(null); }}>Back to sign in</button>
    </section></main>
  );

  if (mode === "forgot") return (
    <main className="auth-shell"><section className="auth-card auth-confirmation">
      {resetSent ? <MailCheck size={42} /> : <KeyRound size={42} />}
      <h1>{resetSent ? "Check your email" : "Reset your password"}</h1>
      <p>{resetSent ? <>We sent a secure password reset link to <strong>{email}</strong>.</> : "Enter your account email and we’ll send you a secure reset link."}</p>
      {!resetSent && <form onSubmit={requestReset} className="auth-wide-form">
        <label>Email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="email" autoFocus /></label>
        {error && <div className="auth-error">{error}</div>}
        <button className="auth-primary" type="submit" disabled={busy}>{busy ? <LoaderCircle className="spin" size={18} /> : "Send reset link"}</button>
      </form>}
      {resetSent && error && <div className="auth-error">{error}</div>}
      <button className="auth-switch auth-back" onClick={() => { setMode("signin"); setResetSent(false); setError(null); }}><ArrowLeft size={14} /> Back to sign in</button>
    </section></main>
  );

  if (mode === "recovery") return (
    <main className="auth-shell"><section className="auth-card auth-confirmation">
      <KeyRound size={42} /><h1>Create a new password</h1><p>Choose a strong password for your InnerWave account.</p>
      <form onSubmit={savePassword} className="auth-wide-form">
        <label>New password<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required minLength={8} autoComplete="new-password" autoFocus /></label>
        <label>Confirm password<input type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} required minLength={8} autoComplete="new-password" /></label>
        {error && <div className="auth-error">{error}</div>}
        <button className="auth-primary" type="submit" disabled={busy}>{busy ? <LoaderCircle className="spin" size={18} /> : "Update password"}</button>
      </form>
      <button className="auth-switch" onClick={auth.finishPasswordRecovery}>Cancel</button>
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
      {mode === "signin" && <button className="auth-forgot" type="button" onClick={() => { setMode("forgot"); setError(null); }}>Forgot password?</button>}
      {error && <div className="auth-error">{error}</div>}
      <button className="auth-primary" type="submit" disabled={busy || (mode === "signup" && name.trim().length < 2)}>{busy ? <LoaderCircle className="spin" size={18} /> : mode === "signin" ? "Sign in" : "Sign up"}</button>
    </form>
    <button className="auth-switch" onClick={() => { setMode((value) => value === "signin" ? "signup" : "signin"); setError(null); }}>{mode === "signin" ? "New to InnerWave? Create account" : "Already have an account? Sign in"}</button>
  </section></main>;
}
