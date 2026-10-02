"use client";

import { Activity, ExternalLink, Headphones, LoaderCircle, LogOut, MapPin, RefreshCw, ShieldCheck, Users } from "lucide-react";
import { useCallback, useEffect, useMemo, useState, type FormEvent } from "react";
import { useAuth } from "@/context/auth-context";
import { API_URL } from "@/lib/api";

const ADMIN_EMAIL = process.env.NEXT_PUBLIC_ADMIN_EMAIL || "harsh.b.mevada@gmail.com";
type AdminUser = { id: string; display_name?: string; email?: string; platform?: string; active?: boolean; is_listening?: boolean; current_track?: { title?: string; artists?: string[] }; location_source?: "gps" | "ip" | "unavailable"; latitude?: number; longitude?: number; accuracy_meters?: number; ip_address?: string; location_permission?: string; last_seen?: string; created_at?: string };
type Overview = { totalUsers: number; activeUsers: number; activeListeners: number; users: AdminUser[]; generatedAt: string };

function relativeTime(value?: string) {
  if (!value) return "Never seen";
  const seconds = Math.max(0, Math.round((Date.now() - new Date(value).getTime()) / 1000));
  if (seconds < 60) return `${seconds}s ago`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h ago`;
  return `${Math.floor(seconds / 86400)}d ago`;
}

export function AdminDashboard() {
  const auth = useAuth();
  const [email, setEmail] = useState(ADMIN_EMAIL);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [overview, setOverview] = useState<Overview | null>(null);
  const isAdmin = auth.user?.email?.toLowerCase() === ADMIN_EMAIL.toLowerCase();
  const load = useCallback(async () => {
    if (!auth.session || !isAdmin) return;
    const response = await fetch(`${API_URL}/api/admin/overview`, { headers: { Authorization: `Bearer ${auth.session.access_token}` }, cache: "no-store" });
    const payload = await response.json().catch(() => null);
    if (!response.ok) throw new Error(payload?.detail || `Admin request failed (${response.status})`);
    setOverview(payload as Overview);
  }, [auth.session, isAdmin]);

  useEffect(() => {
    if (!isAdmin) return;
    const initial = window.setTimeout(() => void load().catch((reason) => setError(reason instanceof Error ? reason.message : "Could not load admin analytics")), 0);
    const timer = window.setInterval(() => void load().catch(() => undefined), 15000);
    return () => { window.clearTimeout(initial); window.clearInterval(timer); };
  }, [isAdmin, load]);

  async function login(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError(null);
    const result = await auth.signIn(email.trim(), password);
    setBusy(false); setError(result.error); setPassword("");
  }

  const users = useMemo(() => overview?.users || [], [overview]);
  if (auth.loading) return <main className="admin-login"><LoaderCircle className="spin" /></main>;
  if (!auth.user) return <main className="admin-login"><form className="admin-login-card" onSubmit={login}>
    <div className="admin-mark"><ShieldCheck /></div><span>INNERWAVE CONTROL</span><h1>Music Admin</h1><p>Restricted analytics for listeners, playback activity and permission-aware location.</p>
    <label>Admin email<input type="email" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="username" /></label>
    <label>Password<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" /></label>
    {error && <div className="auth-error">{error}</div>}
    <button type="submit" disabled={busy}>{busy ? <LoaderCircle className="spin" size={17} /> : "Open admin panel"}</button>
  </form></main>;
  if (!isAdmin) return <main className="admin-login"><section className="admin-login-card admin-denied"><ShieldCheck /><h1>Access denied</h1><p>This InnerWave account is not an authorized administrator.</p><button onClick={() => void auth.signOut()}><LogOut size={17} /> Sign out</button></section></main>;

  return <main className="admin-shell">
    <header className="admin-header"><div><span>INNERWAVE CONTROL</span><h1>Listener overview</h1><p>Live activity refreshes every 15 seconds.</p></div><div><button onClick={() => void load()}><RefreshCw size={16} /> Refresh</button><button onClick={() => void auth.signOut()}><LogOut size={16} /> Sign out</button></div></header>
    {error && <div className="auth-error admin-error">{error}</div>}
    <section className="admin-stats">
      <article><Users /><div><strong>{overview?.totalUsers ?? "—"}</strong><span>Total users</span></div></article>
      <article><Activity /><div><strong>{overview?.activeUsers ?? "—"}</strong><span>Active now</span></div></article>
      <article><Headphones /><div><strong>{overview?.activeListeners ?? "—"}</strong><span>Active listeners</span></div></article>
      <article><MapPin /><div><strong>{users.filter((user) => user.location_source !== "unavailable").length}</strong><span>Locations available</span></div></article>
    </section>
    <section className="admin-table-card"><div className="admin-table-title"><div><h2>Users</h2><p>GPS is preferred; IP appears only when precise location is unavailable.</p></div><span>{overview ? `Updated ${relativeTime(overview.generatedAt)}` : "Loading…"}</span></div>
      <div className="admin-table-wrap"><table><thead><tr><th>Listener</th><th>Status</th><th>Now playing</th><th>Platform</th><th>Location</th><th>Last active</th></tr></thead><tbody>
        {users.map((user) => <tr key={user.id}><td><strong>{user.display_name || "InnerWave Listener"}</strong><small>{user.email || user.id}</small></td><td><span className={`admin-status ${user.is_listening ? "listening" : user.active ? "online" : "offline"}`}>{user.is_listening ? "Listening" : user.active ? "Online" : "Offline"}</span></td><td><strong>{user.current_track?.title || "—"}</strong><small>{user.current_track?.artists?.join(", ") || ""}</small></td><td>{user.platform || "—"}</td><td>{user.location_source === "gps" ? <a href={`https://www.google.com/maps?q=${user.latitude},${user.longitude}`} target="_blank" rel="noreferrer"><MapPin size={14} /> GPS · ±{Math.round(user.accuracy_meters || 0)}m <ExternalLink size={12} /></a> : user.location_source === "ip" ? <><strong>IP fallback</strong><small>{user.ip_address}</small></> : <small>{user.location_permission === "denied" ? "Permission denied" : "Unavailable"}</small>}</td><td>{relativeTime(user.last_seen)}</td></tr>)}
        {!users.length && <tr><td colSpan={6} className="admin-empty">No listener data yet.</td></tr>}
      </tbody></table></div>
    </section>
  </main>;
}
