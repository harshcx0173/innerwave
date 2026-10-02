"use client";

import { ArrowLeft, CheckCircle2, LogOut, Mail, Save, ShieldCheck, UserRound } from "lucide-react";
import { useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/context/auth-context";

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((part) => part[0]).join("").toUpperCase() || "IW";
}

export function ProfilePage({ onBack }: { onBack: () => void }) {
  const auth = useAuth();
  const [name, setName] = useState(auth.displayName);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const provider = useMemo(() => {
    const value = auth.user?.app_metadata?.provider;
    return typeof value === "string" ? value : "email";
  }, [auth.user?.app_metadata?.provider]);

  useEffect(() => setName(auth.displayName), [auth.displayName]);

  async function save(event: FormEvent) {
    event.preventDefault();
    const nextName = name.trim();
    setMessage(null); setError(null);
    if (nextName.length < 2) { setError("Display name must be at least 2 characters."); return; }
    if (nextName.length > 40) { setError("Display name cannot exceed 40 characters."); return; }
    setBusy(true);
    const result = await auth.updateProfile(nextName);
    setBusy(false);
    if (result.error) setError(result.error);
    else setMessage("Profile updated on all your devices.");
  }

  return (
    <section className="profile-page">
      <button className="profile-back" onClick={onBack}><ArrowLeft size={18} /> Back to music</button>
      <div className="profile-hero">
        <div className="profile-avatar">{initials(auth.displayName)}</div>
        <div><span>YOUR INNERWAVE PROFILE</span><h1>{auth.displayName}</h1><p>Manage the identity shared across your web and mobile apps.</p></div>
      </div>

      <div className="profile-grid">
        <form className="profile-card profile-form" onSubmit={save}>
          <div className="profile-card-title"><UserRound size={20} /><div><h2>Profile details</h2><p>Your display name appears across InnerWave.</p></div></div>
          <label>Display name<input value={name} onChange={(event) => { setName(event.target.value); setMessage(null); setError(null); }} minLength={2} maxLength={40} required /></label>
          <label>Email address<div className="profile-readonly"><Mail size={16} />{auth.user?.email || "No email available"}<CheckCircle2 size={15} /></div></label>
          {error && <div className="auth-error">{error}</div>}
          {message && <div className="profile-success">{message}</div>}
          <button className="profile-save" type="submit" disabled={busy || name.trim() === auth.displayName}><Save size={16} />{busy ? "Saving…" : "Save changes"}</button>
        </form>

        <div className="profile-side">
          <div className="profile-card">
            <div className="profile-card-title"><ShieldCheck size={20} /><div><h2>Account</h2><p>Your sign-in and security information.</p></div></div>
            <dl><div><dt>Sign-in method</dt><dd>{provider === "google" ? "Google" : "Email & password"}</dd></div><div><dt>Email status</dt><dd>{auth.user?.email_confirmed_at ? "Verified" : "Pending verification"}</dd></div></dl>
          </div>
          <div className="profile-card profile-danger">
            <h2>Sign out</h2><p>You can sign back in anytime without losing your account.</p>
            <button onClick={() => void auth.signOut()}><LogOut size={16} /> Sign out of InnerWave</button>
          </div>
        </div>
      </div>
    </section>
  );
}
