"use client";

/* eslint-disable @next/next/no-img-element */
import { useEffect, useState } from "react";
import { LoaderCircle, Play, Shuffle, UserCheck, X } from "lucide-react";
import { musicApi } from "@/lib/api";
import { usePlayer } from "@/context/player-context";
import type { Feed, MediaItem } from "@/lib/types";
import { MediaArt } from "./media-art";

export function ArtistView() {
  const { selectedArtistForView, closeArtistView, play } = usePlayer();
  const [loading, setLoading] = useState(false);
  const [feed, setFeed] = useState<Feed | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!selectedArtistForView) {
      setFeed(null);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    // Search specifically for artist catalog & top tracks
    musicApi
      .search(`${selectedArtistForView} top tracks songs`)
      .then((res) => {
        if (!cancelled) setFeed(res);
      })
      .catch((err) => {
        if (!cancelled) setError(err instanceof Error ? err.message : "Failed to load artist");
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedArtistForView]);

  if (!selectedArtistForView) return null;

  const allTracks = feed?.shelves.flatMap((s) => s.items).filter((it) => it.videoId) || [];
  const uniqueTracks = allTracks.filter(
    (item, index) => allTracks.findIndex((o) => o.id === item.id) === index
  );
  const leadImage = uniqueTracks[0]?.thumbnail || "";

  const handlePlayAll = (shuffle = false) => {
    if (!uniqueTracks.length) return;
    const ordered = shuffle ? [...uniqueTracks].sort(() => Math.random() - 0.5) : uniqueTracks;
    play(ordered[0], ordered);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 backdrop-blur-md p-4 animate-in fade-in duration-200">
      <div className="relative flex flex-col w-full max-w-2xl max-h-[85vh] rounded-3xl border border-white/10 bg-[#12141A] shadow-2xl overflow-hidden text-white">
        {/* Header with Hero Banner */}
        <div className="relative h-56 shrink-0 w-full overflow-hidden bg-gradient-to-b from-purple-900/60 to-[#12141A]">
          {leadImage && (
            <img
              src={leadImage}
              alt=""
              className="absolute inset-0 w-full h-full object-cover opacity-35 filter blur-sm scale-105"
            />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-[#12141A] via-transparent to-black/40" />

          <button
            onClick={closeArtistView}
            className="absolute top-4 right-4 z-10 rounded-full p-2 bg-black/50 text-white/70 hover:bg-black/80 hover:text-white transition"
          >
            <X size={18} />
          </button>

          <div className="absolute bottom-6 left-6 right-6 flex items-end justify-between gap-4">
            <div className="flex items-center gap-4">
              <div className="size-20 rounded-full overflow-hidden border-2 border-cyan-400/60 shadow-xl shrink-0 bg-white/10">
                {leadImage ? (
                  <img src={leadImage} alt="" className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center font-bold text-xl">
                    {selectedArtistForView.slice(0, 2).toUpperCase()}
                  </div>
                )}
              </div>
              <div className="min-w-0">
                <span className="flex items-center gap-1 text-xs font-semibold text-cyan-400 uppercase tracking-wider">
                  <UserCheck size={14} /> Verified Artist
                </span>
                <h1 className="text-2xl font-bold truncate mt-0.5">{selectedArtistForView}</h1>
                <p className="text-xs text-white/60">
                  {uniqueTracks.length} popular {uniqueTracks.length === 1 ? "track" : "tracks"} ready to play
                </p>
              </div>
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => handlePlayAll(false)}
                disabled={!uniqueTracks.length}
                className="flex items-center gap-1.5 rounded-full bg-cyan-500 px-4 py-2 text-xs font-bold text-black hover:bg-cyan-400 disabled:opacity-40 transition shadow-lg"
              >
                <Play size={14} fill="currentColor" /> Play Radio
              </button>
              <button
                onClick={() => handlePlayAll(true)}
                disabled={!uniqueTracks.length}
                className="flex items-center gap-1.5 rounded-full bg-white/10 px-3 py-2 text-xs font-medium text-white hover:bg-white/20 disabled:opacity-40 transition"
              >
                <Shuffle size={14} /> Shuffle
              </button>
            </div>
          </div>
        </div>

        {/* Content body */}
        <div className="flex-1 overflow-y-auto p-6 space-y-4 custom-scrollbar">
          {loading ? (
            <div className="py-16 flex flex-col items-center justify-center gap-3 text-white/60">
              <LoaderCircle className="animate-spin text-cyan-400" size={32} />
              <p className="text-sm">Loading artist music...</p>
            </div>
          ) : error ? (
            <div className="py-12 text-center text-rose-400 text-sm">{error}</div>
          ) : uniqueTracks.length === 0 ? (
            <div className="py-12 text-center text-white/50 text-sm">
              No top tracks found for this artist.
            </div>
          ) : (
            <div>
              <h3 className="text-sm font-bold uppercase tracking-wider text-white/50 mb-3">
                Top Songs & Popular Tracks
              </h3>
              <div className="divide-y divide-white/5">
                {uniqueTracks.map((track, i) => (
                  <div
                    key={track.id}
                    onClick={() => play(track, uniqueTracks)}
                    className="flex items-center justify-between p-3 rounded-xl hover:bg-white/5 cursor-pointer transition group"
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <span className="w-5 text-center text-xs text-white/40 group-hover:text-cyan-400">
                        {i + 1}
                      </span>
                      <MediaArt item={track} className="size-11 rounded-lg shrink-0" />
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-white group-hover:text-cyan-400 truncate">
                          {track.title}
                        </p>
                        <p className="text-xs text-white/50 truncate">{track.subtitle}</p>
                      </div>
                    </div>
                    <div className="flex items-center gap-3">
                      {track.duration && (
                        <span className="text-xs text-white/40">{track.duration}</span>
                      )}
                      <Play
                        size={15}
                        className="text-white/40 group-hover:text-cyan-400 fill-transparent group-hover:fill-cyan-400 transition"
                      />
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
