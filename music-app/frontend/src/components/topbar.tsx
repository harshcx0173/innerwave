"use client";

import { Bell, ChevronLeft, ChevronRight, Search, X } from "lucide-react";
import { type FormEvent } from "react";

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
