"use client";

import { BadgePlus, BarChart3, ChevronLeft, ChevronRight, MoreHorizontal, Podcast, Smile } from "lucide-react";
import type { MediaItem, Shelf } from "@/lib/types";
import { MediaArt } from "./media-art";

type Props = {
  shelves: Shelf[];
  moods: string[];
  onSelect: (item: MediaItem, context: MediaItem[], shelf: Shelf) => void;
  onPlayAll: (item: MediaItem) => void;
  onBrowse: (kind: "releases" | "charts" | "moods" | "podcasts") => void;
  onMood: (mood: string) => void;
};

const categoryCards = [
  { id: "releases" as const, label: "New releases", icon: BadgePlus },
  { id: "charts" as const, label: "Charts", icon: BarChart3 },
  { id: "moods" as const, label: "Moods & genres", icon: Smile },
  { id: "podcasts" as const, label: "Podcasts", icon: Podcast },
];

function SectionHeader({ title, onMore }: { title: string; onMore: () => void }) {
  return (
    <header className="explore-section-heading">
      <h2>{title}</h2>
      <div>
        <button onClick={onMore}>More</button>
        <span><ChevronLeft /><ChevronRight /></span>
      </div>
    </header>
  );
}

function ReleaseShelf({ shelf, onSelect, onPlayAll, onMore }: {
  shelf: Shelf;
  onSelect: Props["onSelect"];
  onPlayAll: Props["onPlayAll"];
  onMore: () => void;
}) {
  return (
    <section className="explore-section">
      <SectionHeader title={shelf.title} onMore={onMore} />
      <div className="explore-release-grid">
        {shelf.items.map((item) => (
          <article key={item.id}>
            <button className="explore-card" onClick={() => onSelect(item, shelf.items, shelf)}>
              <MediaArt item={item} className="explore-square-art rounded-sm!" />
              <strong>{item.title}</strong>
              <small>{item.subtitle || item.type}</small>
            </button>
            {!item.videoId && ["album", "playlist"].includes(item.type) && (
              <button className="explore-card-menu" onClick={() => onPlayAll(item)} aria-label={`Play all ${item.title}`}>
                <MoreHorizontal />
              </button>
            )}
          </article>
        ))}
      </div>
    </section>
  );
}

function ChartShelf({ shelf, onSelect, onMore }: {
  shelf: Shelf;
  onSelect: Props["onSelect"];
  onMore: () => void;
}) {
  return (
    <section className="explore-section">
      <SectionHeader title={shelf.title} onMore={onMore} />
      <div className="explore-chart-grid">
        {shelf.items.map((item, index) => (
          <button key={item.id} className="explore-chart-row" onClick={() => onSelect(item, shelf.items, shelf)}>
            <MediaArt item={item} className="explore-chart-art rounded-sm!" />
            <b>{index + 1}</b>
            <span><strong>{item.title}</strong><small>{item.subtitle}</small></span>
          </button>
        ))}
      </div>
    </section>
  );
}

function VideoShelf({ shelf, onSelect, onMore }: {
  shelf: Shelf;
  onSelect: Props["onSelect"];
  onMore: () => void;
}) {
  return (
    <section className="explore-section">
      <SectionHeader title={shelf.title} onMore={onMore} />
      <div className="explore-video-grid">
        {shelf.items.map((item) => (
          <button key={item.id} className="explore-card" onClick={() => onSelect(item, shelf.items, shelf)}>
            <MediaArt item={item} className="explore-video-art rounded-sm!" />
            <strong>{item.title}</strong>
            <small>{item.subtitle}</small>
          </button>
        ))}
      </div>
    </section>
  );
}

export function ExplorePage({ shelves, moods, onSelect, onPlayAll, onBrowse, onMood }: Props) {
  const releases = shelves.find((shelf) => shelf.id === "explore-releases");
  const trending = shelves.find((shelf) => shelf.id === "explore-trending");
  const videos = shelves.find((shelf) => shelf.id === "explore-videos");

  return (
    <div className="explore-page">
      <nav className="explore-categories" aria-label="Explore categories">
        {categoryCards.map(({ id, label, icon: Icon }) => (
          <button key={id} onClick={() => onBrowse(id)}><Icon /><span>{label}</span></button>
        ))}
      </nav>

      {releases && <ReleaseShelf shelf={releases} onSelect={onSelect} onPlayAll={onPlayAll} onMore={() => onBrowse("releases")} />}

      {!!moods.length && (
        <section className="explore-section">
          <SectionHeader title="Moods & genres" onMore={() => onBrowse("moods")} />
          <div className="explore-moods">
            {moods.map((mood) => <button key={mood} onClick={() => onMood(mood)}>{mood}</button>)}
          </div>
        </section>
      )}

      {trending && <ChartShelf shelf={trending} onSelect={onSelect} onMore={() => onBrowse("charts")} />}
      {videos && <VideoShelf shelf={videos} onSelect={onSelect} onMore={() => onBrowse("releases")} />}
    </div>
  );
}
