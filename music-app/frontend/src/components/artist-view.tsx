"use client";

/* eslint-disable @next/next/no-img-element */
import { useCallback, useEffect, useMemo, useState } from "react";
import {
  ArrowLeft,
  Check,
  Disc3,
  Heart,
  LoaderCircle,
  Play,
  Plus,
  Radio,
  Search,
  Share2,
  Shuffle,
  Sparkles,
  UserCheck,
} from "lucide-react";
import { musicApi } from "@/lib/api";
import { usePlayer } from "@/context/player-context";
import { usePlaylist } from "@/context/playlist-context";
import type { MediaItem, Shelf as ShelfType } from "@/lib/types";
import { MediaArt } from "./media-art";

type Props = {
  artistName: string;
  onBack: () => void;
};

export function ArtistPage({ artistName, onBack }: Props) {
  const { play, openShareModal } = usePlayer();
  const { openAddToPlaylistModal } = usePlaylist();

  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [tracks, setTracks] = useState<MediaItem[]>([]);
  const [albums, setAlbums] = useState<MediaItem[]>([]);
  const [continuation, setContinuation] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<"songs" | "albums">("songs");
  const [songFilter, setSongFilter] = useState("");

  const fetchArtistCatalog = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // Parallel searches for top songs, full tracks, and albums
      const [songsFeed, tracksFeed, albumsFeed] = await Promise.allSettled([
        musicApi.search(`${artistName} songs`),
        musicApi.search(`${artistName} all tracks`),
        musicApi.search(`${artistName} albums`),
      ]);

      const gatheredTracks: MediaItem[] = [];
      const gatheredAlbums: MediaItem[] = [];
      let nextContinuation: string | null = null;

      if (songsFeed.status === "fulfilled") {
        const items = songsFeed.value.shelves.flatMap((s) => s.items);
        gatheredTracks.push(...items.filter((it) => it.videoId));
        if (songsFeed.value.continuation) {
          nextContinuation = songsFeed.value.continuation;
        }
      }

      if (tracksFeed.status === "fulfilled") {
        const items = tracksFeed.value.shelves.flatMap((s) => s.items);
        gatheredTracks.push(...items.filter((it) => it.videoId));
        if (!nextContinuation && tracksFeed.value.continuation) {
          nextContinuation = tracksFeed.value.continuation;
        }
      }

      if (albumsFeed.status === "fulfilled") {
        const items = albumsFeed.value.shelves.flatMap((s) => s.items);
        gatheredAlbums.push(...items.filter((it) => it.type === "album" || !it.videoId));
      }

      // Deduplicate songs by videoId or id
      const uniqueTracks = gatheredTracks.filter(
        (item, index) =>
          gatheredTracks.findIndex((o) => (o.videoId || o.id) === (item.videoId || item.id)) === index
      );

      // Deduplicate albums
      const uniqueAlbums = gatheredAlbums.filter(
        (item, index) => gatheredAlbums.findIndex((o) => o.id === item.id) === index
      );

      setTracks(uniqueTracks);
      setAlbums(uniqueAlbums);
      setContinuation(nextContinuation);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to load artist catalog.");
    } finally {
      setLoading(false);
    }
  }, [artistName]);

  useEffect(() => {
    fetchArtistCatalog();
  }, [fetchArtistCatalog]);

  const loadMoreTracks = async () => {
    if (!continuation || loadingMore) return;
    setLoadingMore(true);
    try {
      const res = await musicApi.search(`${artistName} songs`, continuation);
      const moreTracks = res.shelves.flatMap((s) => s.items).filter((it) => it.videoId);
      setTracks((prev) => {
        const combined = [...prev, ...moreTracks];
        return combined.filter(
          (item, index) =>
            combined.findIndex((o) => (o.videoId || o.id) === (item.videoId || item.id)) === index
        );
      });
      setContinuation(res.continuation || null);
    } catch {
      setContinuation(null);
    } finally {
      setLoadingMore(false);
    }
  };

  const filteredTracks = useMemo(() => {
    if (!songFilter.trim()) return tracks;
    const query = songFilter.trim().toLowerCase();
    return tracks.filter(
      (t) =>
        t.title.toLowerCase().includes(query) ||
        t.subtitle.toLowerCase().includes(query) ||
        t.artists.some((a) => a.toLowerCase().includes(query))
    );
  }, [songFilter, tracks]);

  const leadImage = tracks[0]?.thumbnail || albums[0]?.thumbnail || "";

  const handlePlayAll = (shuffle = false) => {
    if (!tracks.length) return;
    const ordered = shuffle ? [...tracks].sort(() => Math.random() - 0.5) : tracks;
    play(ordered[0], ordered);
  };

  return (
    <div className="artist-page w-full pb-32 animate-in fade-in duration-300">
      {/* Top Back Navigation */}
      <div className="flex items-center justify-between mb-4">
        <button
          onClick={onBack}
          className="flex items-center gap-2 rounded-xl bg-white/5 border border-white/10 px-4 py-2 text-sm font-medium text-white/80 hover:bg-white/10 hover:text-white transition"
        >
          <ArrowLeft size={16} />
          Back to music
        </button>

        <span className="text-xs font-semibold uppercase tracking-wider text-cyan-400 flex items-center gap-1.5">
          <Sparkles size={14} /> Artist Discography
        </span>
      </div>

      {/* Hero Header Banner */}
      <section className="relative overflow-hidden rounded-3xl border border-white/10 bg-gradient-to-b from-[#2A1B40] via-[#161822] to-[#0D0F14] p-8 shadow-2xl">
        {leadImage && (
          <img
            src={leadImage}
            alt=""
            className="absolute inset-0 h-full w-full object-cover opacity-25 filter blur-xl scale-110"
            referrerPolicy="no-referrer"
          />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-[#0D0F14] via-[#0D0F14]/70 to-transparent" />

        <div className="relative z-10 flex flex-col md:flex-row items-start md:items-end gap-6 pt-12 pb-2">
          {/* Avatar */}
          <div className="relative size-32 md:size-44 shrink-0 overflow-hidden rounded-full border-4 border-white/15 shadow-2xl bg-white/10">
            {leadImage ? (
              <img
                src={leadImage}
                alt={artistName}
                className="h-full w-full object-cover"
                referrerPolicy="no-referrer"
              />
            ) : (
              <div className="flex h-full w-full items-center justify-center text-3xl font-black text-white/70">
                {artistName.slice(0, 2).toUpperCase()}
              </div>
            )}
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 text-xs font-bold uppercase tracking-widest text-cyan-400 mb-2">
              <UserCheck size={16} /> Verified Artist
            </div>
            <h1 className="text-3xl md:text-5xl lg:text-6xl font-black tracking-tight text-white truncate">
              {artistName}
            </h1>
            <p className="mt-2 text-sm text-white/60">
              {tracks.length} songs cataloged • {albums.length} albums & singles available
            </p>
          </div>
        </div>
      </section>

      {/* Action Bar */}
      <div className="flex flex-wrap items-center justify-between gap-4 my-6 px-1">
        <div className="flex items-center gap-3">
          <button
            onClick={() => handlePlayAll(false)}
            disabled={!tracks.length}
            className="flex items-center gap-2 rounded-full bg-cyan-500 px-7 py-3 text-sm font-bold text-black shadow-lg shadow-cyan-500/30 hover:bg-cyan-400 hover:scale-105 active:scale-95 disabled:opacity-40 transition"
          >
            <Play fill="currentColor" size={18} />
            Play All
          </button>

          <button
            onClick={() => handlePlayAll(true)}
            disabled={!tracks.length}
            className="flex items-center gap-2 rounded-full bg-white/10 border border-white/15 px-5 py-3 text-sm font-semibold text-white hover:bg-white/20 active:scale-95 disabled:opacity-40 transition"
          >
            <Shuffle size={16} />
            Shuffle
          </button>

          {tracks[0] && (
            <button
              onClick={() => openShareModal(tracks[0])}
              className="flex items-center gap-2 rounded-full bg-white/5 border border-white/10 px-4 py-3 text-sm font-medium text-white/80 hover:bg-white/10 hover:text-white transition"
              title="Share Artist Poster"
            >
              <Share2 size={16} />
              Share
            </button>
          )}
        </div>

        {/* Tab switcher */}
        <div className="flex items-center gap-1 rounded-2xl bg-white/5 border border-white/10 p-1">
          <button
            onClick={() => setActiveTab("songs")}
            className={`rounded-xl px-4 py-1.5 text-xs font-bold transition ${
              activeTab === "songs" ? "bg-cyan-500 text-black shadow" : "text-white/70 hover:text-white"
            }`}
          >
            All Songs ({tracks.length})
          </button>
          {albums.length > 0 && (
            <button
              onClick={() => setActiveTab("albums")}
              className={`rounded-xl px-4 py-1.5 text-xs font-bold transition ${
                activeTab === "albums" ? "bg-cyan-500 text-black shadow" : "text-white/70 hover:text-white"
              }`}
            >
              Albums & EPs ({albums.length})
            </button>
          )}
        </div>
      </div>

      {/* Loading & Error States */}
      {loading ? (
        <div className="py-24 flex flex-col items-center justify-center gap-3 text-white/60">
          <LoaderCircle className="animate-spin text-cyan-400" size={36} />
          <p className="text-sm font-medium">Gathering complete discography for {artistName}…</p>
        </div>
      ) : error ? (
        <div className="py-16 text-center text-rose-400 text-sm">
          {error}
          <button
            onClick={fetchArtistCatalog}
            className="block mx-auto mt-3 rounded-xl bg-white/10 px-4 py-1.5 text-xs text-white"
          >
            Try Again
          </button>
        </div>
      ) : activeTab === "albums" ? (
        /* Albums View */
        <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-4 mt-6">
          {albums.map((album) => (
            <div
              key={album.id}
              className="group flex flex-col rounded-2xl bg-white/5 border border-white/5 p-3 hover:border-white/20 hover:bg-white/10 transition"
            >
              <MediaArt item={album} className="aspect-square w-full rounded-xl mb-3" />
              <strong className="text-sm font-semibold text-white truncate group-hover:text-cyan-400">
                {album.title}
              </strong>
              <small className="text-xs text-white/50 truncate mt-0.5">{album.subtitle || "Album"}</small>
            </div>
          ))}
        </div>
      ) : (
        /* All Songs View */
        <div>
          {/* Quick Filter Input */}
          <div className="relative mb-4">
            <Search size={16} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-white/40" />
            <input
              type="text"
              placeholder={`Filter ${tracks.length} songs by ${artistName}…`}
              value={songFilter}
              onChange={(e) => setSongFilter(e.target.value)}
              className="w-full rounded-xl bg-white/5 border border-white/10 pl-10 pr-4 py-2.5 text-sm text-white placeholder-white/40 focus:outline-none focus:border-cyan-400"
            />
            {songFilter && (
              <button
                onClick={() => setSongFilter("")}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-xs text-white/50 hover:text-white"
              >
                Clear
              </button>
            )}
          </div>

          {filteredTracks.length === 0 ? (
            <div className="py-16 text-center text-white/50 text-sm">
              No tracks matching &ldquo;{songFilter}&rdquo;
            </div>
          ) : (
            <div className="rounded-2xl border border-white/10 bg-white/[0.02] overflow-hidden divide-y divide-white/5">
              {filteredTracks.map((track, i) => (
                <div
                  key={`${track.id}-${i}`}
                  onClick={() => play(track, filteredTracks)}
                  className="group flex items-center justify-between p-3.5 hover:bg-white/5 cursor-pointer transition"
                >
                  <div className="flex items-center gap-3.5 min-w-0 flex-1">
                    <span className="w-6 text-center text-xs font-semibold text-white/40 group-hover:text-cyan-400 shrink-0">
                      {i + 1}
                    </span>
                    <MediaArt item={track} className="size-12 rounded-lg shrink-0" />
                    <div className="min-w-0">
                      <p className="text-sm font-semibold text-white group-hover:text-cyan-400 truncate">
                        {track.title}
                      </p>
                      <p className="text-xs text-white/50 truncate mt-0.5">
                        {track.subtitle || artistName}
                      </p>
                    </div>
                  </div>

                  {/* Actions & Duration */}
                  <div className="flex items-center gap-2 shrink-0 ml-3">
                    {track.duration && (
                      <span className="text-xs text-white/40 font-mono hidden sm:inline mr-2">
                        {track.duration}
                      </span>
                    )}

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        openAddToPlaylistModal(track);
                      }}
                      className="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 opacity-0 group-hover:opacity-100 transition"
                      title="Add to playlist"
                    >
                      <Plus size={16} />
                    </button>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        openShareModal(track);
                      }}
                      className="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 opacity-0 group-hover:opacity-100 transition"
                      title="Share track card"
                    >
                      <Share2 size={16} />
                    </button>

                    <button className="p-1.5 rounded-full text-white/50 group-hover:text-cyan-400 group-hover:scale-110 transition">
                      <Play size={16} fill="currentColor" />
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Load More Button */}
          {continuation && !songFilter && (
            <div className="text-center mt-6">
              <button
                onClick={loadMoreTracks}
                disabled={loadingMore}
                className="inline-flex items-center gap-2 rounded-2xl bg-white/10 border border-white/15 px-6 py-2.5 text-xs font-semibold text-white hover:bg-white/20 disabled:opacity-50 transition"
              >
                {loadingMore ? (
                  <>
                    <LoaderCircle size={14} className="animate-spin text-cyan-400" />
                    Loading more songs…
                  </>
                ) : (
                  "Load More Songs from Artist"
                )}
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
