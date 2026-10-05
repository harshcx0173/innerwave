"use client";

import { ChevronRight, Play, Plus, Share2 } from "lucide-react";
import type { MediaItem, Shelf as ShelfType } from "@/lib/types";
import { MediaArt } from "./media-art";
import { usePlaylist } from "@/context/playlist-context";
import { usePlayer } from "@/context/player-context";

type Props = {
  shelf: ShelfType;
  onSelect: (item: MediaItem, context: MediaItem[], shelf: ShelfType) => void;
  onPlayAll: (item: MediaItem) => void;
};

export function Shelf({ shelf, onSelect, onPlayAll }: Props) {
  const { openAddToPlaylistModal } = usePlaylist();
  const player = usePlayer();

  if (shelf.layout === "list") {
    return (
      <section className="shelf-section">
        <header className="shelf-heading">
          <div>
            <p className="eyebrow">DISCOVER</p>
            <h2>{shelf.title}</h2>
          </div>
        </header>
        <div className="result-list">
          {shelf.items.map((item, index) => {
            const artist = item.artists[0] || item.subtitle.split(" · ")[0];
            return (
              <div
                key={`${item.id}-${index}`}
                className="result-row group relative flex items-center justify-between"
              >
                <div
                  className="flex items-center gap-3 flex-1 min-w-0 cursor-pointer"
                  onClick={() => onSelect(item, shelf.items, shelf)}
                >
                  <span className="row-number">{String(index + 1).padStart(2, "0")}</span>
                  <MediaArt item={item} className="size-12 shrink-0 rounded-lg!" />
                  <span className="item-copy min-w-0">
                    <strong className="truncate group-hover:text-cyan-400 transition">
                      {item.title}
                    </strong>
                    {artist && item.videoId ? (
                      <small
                        onClick={(e) => {
                          e.stopPropagation();
                          player.openArtistView(artist);
                        }}
                        className="truncate hover:underline hover:text-cyan-400 transition"
                      >
                        {item.subtitle || artist}
                      </small>
                    ) : (
                      <small className="truncate">{item.subtitle || item.type}</small>
                    )}
                  </span>
                </div>

                <div className="flex items-center gap-2 shrink-0 ml-2">
                  {item.duration && <span className="row-duration">{item.duration}</span>}
                  {item.videoId && (
                    <>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          openAddToPlaylistModal(item);
                        }}
                        className="p-1.5 rounded-lg opacity-0 group-hover:opacity-100 hover:bg-white/10 text-white/60 hover:text-white transition"
                        title="Add to playlist"
                        aria-label="Add to playlist"
                      >
                        <Plus size={16} />
                      </button>
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          player.openShareModal(item);
                        }}
                        className="p-1.5 rounded-lg opacity-0 group-hover:opacity-100 hover:bg-white/10 text-white/60 hover:text-white transition"
                        title="Share song card"
                        aria-label="Share song card"
                      >
                        <Share2 size={16} />
                      </button>
                    </>
                  )}
                  <button
                    onClick={() => onSelect(item, shelf.items, shelf)}
                    className="p-1 text-white/70 hover:text-cyan-400 transition"
                  >
                    {item.videoId ? <Play size={16} fill="currentColor" /> : <ChevronRight size={17} />}
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      </section>
    );
  }

  if (shelf.layout === "songs") {
    return (
      <section className="shelf-section">
        <header className="shelf-heading">
          <div>
            <p className="eyebrow">FOR THE MOMENT</p>
            <h2>{shelf.title}</h2>
          </div>
        </header>
        <div className="song-grid">
          {shelf.items.map((item) => (
            <div
              key={item.id}
              className="song-tile group relative flex items-center justify-between cursor-pointer"
              onClick={() => onSelect(item, shelf.items, shelf)}
            >
              <div className="flex items-center gap-3 min-w-0 flex-1">
                <MediaArt item={item} className="size-14 shrink-0 rounded-xl!" />
                <span className="item-copy min-w-0">
                  <strong className="truncate group-hover:text-cyan-400 transition">
                    {item.title}
                  </strong>
                  <small className="truncate">{item.subtitle}</small>
                </span>
              </div>
              <div className="flex items-center gap-1 shrink-0">
                {item.videoId && (
                  <button
                    onClick={(e) => {
                      e.stopPropagation();
                      openAddToPlaylistModal(item);
                    }}
                    className="p-1 rounded opacity-0 group-hover:opacity-100 hover:text-white text-white/50 transition"
                    title="Add to playlist"
                  >
                    <Plus size={15} />
                  </button>
                )}
                <Play size={16} className="muted-icon group-hover:text-cyan-400" />
              </div>
            </div>
          ))}
        </div>
      </section>
    );
  }

  return (
    <section className="shelf-section">
      <header className="shelf-heading">
        <div>
          <p className="eyebrow">CURATED FOR YOU</p>
          <h2>{shelf.title}</h2>
        </div>
        <span className="view-all">
          View all <ChevronRight size={15} />
        </span>
      </header>
      <div className="media-carousel">
        {shelf.items.map((item) => (
          <div key={item.id} className="media-card-wrap">
            <button className="media-card" onClick={() => onSelect(item, shelf.items, shelf)}>
              <MediaArt item={item} className="aspect-square w-full" />
              <strong>{item.title}</strong>
              <small>{item.subtitle || item.type}</small>
            </button>
            {!item.videoId && ["album", "playlist"].includes(item.type) && (
              <button
                className="card-play-all"
                onClick={() => onPlayAll(item)}
                aria-label={`Play all ${item.title}`}
              >
                <Play fill="currentColor" />
              </button>
            )}
          </div>
        ))}
      </div>
    </section>
  );
}
