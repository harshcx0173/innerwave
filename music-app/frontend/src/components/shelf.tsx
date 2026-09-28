"use client";

import { ChevronRight, MoreHorizontal, Play } from "lucide-react";
import type { MediaItem, Shelf as ShelfType } from "@/lib/types";
import { MediaArt } from "./media-art";

type Props = {
  shelf: ShelfType;
  onSelect: (item: MediaItem, context: MediaItem[], shelf: ShelfType) => void;
  onPlayAll: (item: MediaItem) => void;
};

export function Shelf({ shelf, onSelect, onPlayAll }: Props) {
  if (shelf.layout === "list") {
    return (
      <section className="shelf-section">
        <header className="shelf-heading"><div><p className="eyebrow">DISCOVER</p><h2>{shelf.title}</h2></div></header>
        <div className="result-list">
          {shelf.items.map((item, index) => (
            <button key={`${item.id}-${index}`} className="result-row" onClick={() => onSelect(item, shelf.items, shelf)}>
              <span className="row-number">{String(index + 1).padStart(2, "0")}</span>
              <MediaArt item={item} className="size-12 shrink-0 rounded-lg!" />
              <span className="item-copy"><strong>{item.title}</strong><small>{item.subtitle || item.type}</small></span>
              {item.duration && <span className="row-duration">{item.duration}</span>}
              {item.videoId ? <Play size={16} /> : <ChevronRight size={17} />}
              <MoreHorizontal size={17} className="muted-icon" />
            </button>
          ))}
        </div>
      </section>
    );
  }

  if (shelf.layout === "songs") {
    return (
      <section className="shelf-section">
        <header className="shelf-heading"><div><p className="eyebrow">FOR THE MOMENT</p><h2>{shelf.title}</h2></div></header>
        <div className="song-grid">
          {shelf.items.map((item) => (
            <button key={item.id} className="song-tile" onClick={() => onSelect(item, shelf.items, shelf)}>
              <MediaArt item={item} className="size-14 shrink-0 rounded-xl!" />
              <span className="item-copy"><strong>{item.title}</strong><small>{item.subtitle}</small></span>
              <Play size={16} className="muted-icon" />
            </button>
          ))}
        </div>
      </section>
    );
  }

  return (
    <section className="shelf-section">
      <header className="shelf-heading"><div><p className="eyebrow">CURATED FOR YOU</p><h2>{shelf.title}</h2></div><span className="view-all">View all <ChevronRight size={15} /></span></header>
      <div className="media-carousel">
        {shelf.items.map((item) => (
          <div key={item.id} className="media-card-wrap">
            <button className="media-card" onClick={() => onSelect(item, shelf.items, shelf)}>
              <MediaArt item={item} className="aspect-square w-full" />
              <strong>{item.title}</strong>
              <small>{item.subtitle || item.type}</small>
            </button>
            {!item.videoId && ["album", "playlist"].includes(item.type) && <button className="card-play-all" onClick={() => onPlayAll(item)} aria-label={`Play all ${item.title}`}><Play fill="currentColor" /></button>}
          </div>
        ))}
      </div>
    </section>
  );
}
