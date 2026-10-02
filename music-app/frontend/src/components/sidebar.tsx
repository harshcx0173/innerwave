"use client";

import { Compass, Disc3, Headphones, Heart, Home, Library, Plus, Radio, Search } from "lucide-react";

type View = "home" | "explore" | "library" | "profile";

export function Sidebar({ active, onNavigate }: { active: View; onNavigate: (view: "home" | "explore" | "library") => void }) {
  const links = [
    { id: "home" as const, label: "Home", icon: Home },
    { id: "explore" as const, label: "Explore", icon: Compass },
    { id: "library" as const, label: "Your Library", icon: Library },
  ];
  return (
    <aside className="sidebar">
      <div className="brand"><span><Disc3 size={20} fill="currentColor" /></span><b>InnerTube Music</b></div>
      <nav>
        {links.map(({ id, label, icon: Icon }) => (
          <button key={id} className={active === id ? "active" : ""} onClick={() => onNavigate(id)}><Icon size={18} />{label}</button>
        ))}
      </nav>
      <div className="sidebar-label">COLLECTION</div>
      <nav className="secondary-nav">
        <button><Heart size={17} />Liked songs</button>
        <button><Radio size={17} />Your mixes</button>
        <button><Headphones size={17} />Recently played</button>
      </nav>
      <button className="new-playlist"><Plus size={17} />New playlist</button>
      <div className="sidebar-card"><Search size={20} /><strong>Find your next repeat</strong><p>Search YouTube Music&apos;s catalog from one calm place.</p></div>
    </aside>
  );
}
