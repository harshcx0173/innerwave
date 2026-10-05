"use client";

import { useState } from "react";
import { Check, FolderPlus, ListMusic, Plus, X } from "lucide-react";
import { usePlaylist } from "@/context/playlist-context";
import { MediaArt } from "./media-art";

export function AddToPlaylistModal() {
  const {
    playlists,
    activePlaylistModalSong,
    closeAddToPlaylistModal,
    addSongToPlaylist,
    createPlaylist,
  } = usePlaylist();

  const [creating, setCreating] = useState(false);
  const [newTitle, setNewTitle] = useState("");
  const [addedPlaylists, setAddedPlaylists] = useState<Set<string>>(new Set());

  if (!activePlaylistModalSong) return null;

  const handleAdd = async (playlistId: string) => {
    const success = await addSongToPlaylist(playlistId, activePlaylistModalSong);
    if (success) {
      setAddedPlaylists((prev) => new Set(prev).add(playlistId));
    }
  };

  const handleCreateAndAdd = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!newTitle.trim()) return;
    const created = await createPlaylist(newTitle.trim());
    await addSongToPlaylist(created.id, activePlaylistModalSong);
    setAddedPlaylists((prev) => new Set(prev).add(created.id));
    setNewTitle("");
    setCreating(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 backdrop-blur-md p-4">
      <div className="w-full max-w-md rounded-2xl border border-white/10 bg-[#12141A] p-6 shadow-2xl animate-in fade-in zoom-in-95 duration-200">
        <div className="flex items-center justify-between pb-4 border-b border-white/10">
          <div className="flex items-center gap-3">
            <MediaArt item={activePlaylistModalSong} className="size-12 rounded-lg shrink-0" />
            <div className="min-w-0">
              <h2 className="text-base font-semibold text-white truncate">Add to playlist</h2>
              <p className="text-xs text-white/60 truncate">{activePlaylistModalSong.title}</p>
            </div>
          </div>
          <button
            onClick={closeAddToPlaylistModal}
            className="rounded-full p-2 text-white/60 hover:bg-white/10 hover:text-white transition"
            aria-label="Close"
          >
            <X size={18} />
          </button>
        </div>

        <div className="mt-4 max-h-60 overflow-y-auto space-y-2 pr-1 custom-scrollbar">
          {playlists.length === 0 && !creating ? (
            <div className="py-6 text-center text-sm text-white/50">
              No playlists found. Create your first playlist below!
            </div>
          ) : (
            playlists.map((pl) => {
              const isAdded = addedPlaylists.has(pl.id);
              return (
                <button
                  key={pl.id}
                  onClick={() => !isAdded && handleAdd(pl.id)}
                  className={`w-full flex items-center justify-between p-3 rounded-xl border text-left transition ${
                    isAdded
                      ? "border-emerald-500/40 bg-emerald-500/10 text-emerald-400"
                      : "border-white/5 bg-white/5 hover:border-white/20 hover:bg-white/10 text-white"
                  }`}
                >
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="size-9 rounded-lg bg-white/10 flex items-center justify-center shrink-0">
                      <ListMusic size={18} className="text-white/70" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-sm font-medium truncate">{pl.name}</p>
                      <p className="text-xs text-white/50">{pl.songCount} {pl.songCount === 1 ? "track" : "tracks"}</p>
                    </div>
                  </div>
                  {isAdded ? (
                    <span className="flex items-center gap-1 text-xs font-medium text-emerald-400">
                      <Check size={16} /> Added
                    </span>
                  ) : (
                    <Plus size={18} className="text-white/40" />
                  )}
                </button>
              );
            })
          )}
        </div>

        <div className="mt-4 pt-4 border-t border-white/10">
          {creating ? (
            <form onSubmit={handleCreateAndAdd} className="flex gap-2">
              <input
                type="text"
                autoFocus
                placeholder="Playlist name..."
                value={newTitle}
                onChange={(e) => setNewTitle(e.target.value)}
                className="flex-1 rounded-xl bg-white/5 border border-white/15 px-3 py-2 text-sm text-white placeholder-white/40 focus:outline-none focus:border-cyan-400"
              />
              <button
                type="submit"
                disabled={!newTitle.trim()}
                className="rounded-xl bg-cyan-500 px-4 py-2 text-sm font-semibold text-black hover:bg-cyan-400 disabled:opacity-50 transition"
              >
                Create
              </button>
              <button
                type="button"
                onClick={() => setCreating(false)}
                className="rounded-xl bg-white/10 px-3 py-2 text-sm text-white hover:bg-white/15 transition"
              >
                Cancel
              </button>
            </form>
          ) : (
            <button
              onClick={() => setCreating(true)}
              className="w-full flex items-center justify-center gap-2 rounded-xl border border-dashed border-white/20 p-2.5 text-sm font-medium text-white/80 hover:border-white/40 hover:text-white hover:bg-white/5 transition"
            >
              <FolderPlus size={16} />
              New Playlist
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
