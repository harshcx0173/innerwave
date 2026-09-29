"use client";

import { Bell, ChevronLeft, ChevronRight, LogOut, MonitorSpeaker, Search, Smartphone, X } from "lucide-react";
import { type FormEvent, useState } from "react";
import { useAuth } from "@/context/auth-context";
import { useConnect } from "@/context/connect-context";

function getInitials(name?: string | null): string {
  if (!name || !name.trim()) return "IW";
  const parts = name.trim().split(/\s+/);
  if (parts.length >= 2) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  return name.trim().slice(0, 2).toUpperCase();
}

type Props = {
  query: string;
  setQuery: (value: string) => void;
  onSearch: (query: string) => void;
  userName?: string | null;
  onOpenProfile?: () => void;
};

export function Topbar({ query, setQuery, onSearch, userName, onOpenProfile }: Props) {
  const [devicesOpen, setDevicesOpen] = useState(false);
  const { signOut } = useAuth();
  const { connected, devices, deviceId, activeDeviceId, activateDevice } = useConnect();
  function submit(event: FormEvent) {
    event.preventDefault();
    if (query.trim()) onSearch(query.trim());
  }

  const initials = getInitials(userName);

  return (
    <header className="topbar">
      <div className="history-buttons"><button aria-label="Back"><ChevronLeft /></button><button aria-label="Forward"><ChevronRight /></button></div>
      <form onSubmit={submit} className="search-box">
        <Search size={18} />
        <input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search songs, artists, albums..." aria-label="Search music" />
        {query && <button type="button" onClick={() => setQuery("")}><X size={16} /></button>}
        <kbd>⌘ K</kbd>
      </form>
      <div className="device-menu-wrap">
        <button className={`round-button ${connected ? "is-connected" : ""}`} aria-label="Connect to a device" title="InnerWave Connect" onClick={() => setDevicesOpen((open) => !open)}><MonitorSpeaker size={18} /></button>
        {devicesOpen && (
          <div className="device-menu">
            <strong>InnerWave Connect</strong>
            <span className="device-menu-note">Choose where music plays. Controls stay synced.</span>
            {devices.map((device) => (
              <button key={device.id} className={device.id === activeDeviceId ? "active" : ""} onClick={() => void activateDevice(device.id)}>
                {device.platform === "Android" || device.platform === "iOS" ? <Smartphone size={17} /> : <MonitorSpeaker size={17} />}
                <span><b>{device.name}</b><small>{device.id === deviceId ? "This device" : "Online"}</small></span>
                {device.id === activeDeviceId && <em>Playing</em>}
              </button>
            ))}
            {!devices.length && <span className="device-menu-note">Connecting…</span>}
            <button className="device-signout" onClick={() => void signOut()}><LogOut size={16} /> Sign out</button>
          </div>
        )}
      </div>
      <button className="round-button" aria-label="Notifications"><Bell size={18} /></button>
      <button
        className="avatar"
        aria-label={`Profile (${userName || "Set Name"})`}
        title={userName ? `Listener: ${userName} (Click to edit)` : "Set your name"}
        onClick={onOpenProfile}
      >
        {initials}
      </button>
    </header>
  );
}
