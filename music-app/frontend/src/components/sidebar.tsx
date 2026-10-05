"use client";

import { useState } from "react";
import { Compass, Disc3, Headphones, Heart, Home, Library, ListMusic, Plus, Radio, Search } from "lucide-react";
import { usePlaylist, type UserPlaylist } from "@/context/playlist-context";

type View = "home" | "explore" | "library" | "profile";

export function Sidebar({
  active,
  onNavigate,
  onSelectPlaylist,
}: {
  active: View;
  onNavigate: (view: "home" | "explore" | "library") => void;
  onSelectPlaylist?: (playlist: UserPlaylist) => void;
}) {
  const { playlists, createPlaylist } = usePlaylist();
  const [isCreating, setIsCreating] = useState(false);
  const [newTitle, setNewTitle] = useState("");

  const links = [
    { id: "home" as const, label: "Home", icon: Home },
    { id: "explore" as const, label: "Explore", icon: Compass },
    { id: "library" as const, label: "Your Library", icon: Library },
  ];

  const handleCreateSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim()) return;
    const created = await createPlaylist(newTitle.trim());
    setNewTitle("");
    setIsCreating(false);
    onSelectPlaylist?.(created);
  };

  return (
    <aside className="sidebar">
      <div className="brand">
        <span><Disc3 size={20} fill="currentColor" /></span>
        <b>InnerTube Music</b>
      </div>
      <nav>
        {links.map(({ id, label, icon: Icon }) => (
          <button key={id} className={active === id ? "active" : ""} onClick={() => onNavigate(id)}>
            <Icon size={18} />{label}
          </button>
        ))}
      </nav>
      <div className="sidebar-label">COLLECTION</div>
      <nav className="secondary-nav">
        <button onClick={() => onNavigate("library")}><Heart size={17} />Liked songs</button>
        <button onClick={() => onNavigate("explore")}><Radio size={17} />Your mixes</button>
        <button onClick={() => onNavigate("library")}><Headphones size={17} />Recently played</button>
      </nav>

      <div className="sidebar-label flex items-center justify-between pr-2">
        <span>PLAYLISTS</span>
        <button
          onClick={() => setIsCreating(true)}
          className="text-white/60 hover:text-white transition"
          title="Create playlist"
        >
          <Plus size={16} />
        </button>
      </div>

      {isCreating ? (
        <form onSubmit={handleCreateSubmit} className="px-2 py-1">
          <input
            type="text"
            autoFocus
            placeholder="Playlist name..."
            value={newTitle}
            onChange={(e) => setNewTitle(e.target.value)}
            onBlur={() => !newTitle.trim() && setIsCreating(false)}
            className="w-full text-xs px-2.5 py-1.5 rounded-lg bg-white/10 text-white border border-white/20 focus:outline-none focus:border-cyan-400"
          />
        </form>
      ) : (
        <button className="new-playlist" onClick={() => setIsCreating(true)}>
          <Plus size={17} />New playlist
        </button>
      )}

      {playlists.length > 0 && (
        <nav className="secondary-nav max-h-44 overflow-y-auto custom-scrollbar">
          {playlists.map((pl) => (
            <button
              key={pl.id}
              onClick={() => onSelectPlaylist?.(pl)}
              className="truncate flex items-center justify-between"
              title={pl.name}
            >
              <span className="flex items-center gap-2 truncate">
                <ListMusic size={15} className="shrink-0 text-cyan-400/80" />
                <span className="truncate">{pl.name}</span>
              </span>
              <span className="text-[10px] text-white/40 shrink-0">{pl.songCount}</span>
            </button>
          ))}
        </nav>
      )}

      <div className="sidebar-card">
        <Search size={20} />
        <strong>Find your next repeat</strong>
        <p>Search YouTube Music&apos;s catalog from one calm place.</p>
      </div>
    </aside>
  );
}
