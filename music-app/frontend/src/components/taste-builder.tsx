"use client";

import type { MediaItem } from "@/lib/types";
import { MediaArt } from "./media-art";

export function TasteBuilder({ items, onExplore }: { items: MediaItem[]; onExplore: () => void }) {
  const artwork = items.filter((item) => item.thumbnail).slice(0, 5);
  if (artwork.length < 3) return null;
  return (
    <section className="taste-builder">
      <div className="taste-faces">{artwork.map((item) => <MediaArt key={item.id} item={{ ...item, type: "artist" }} className="taste-face" />)}</div>
      <div><h3>Tell us which artists you like</h3><p>We&apos;ll create an experience just for you.</p><button onClick={onExplore}>Let&apos;s go</button></div>
    </section>
  );
}
