"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/context/auth-context";
import type { MediaItem } from "@/lib/types";

export type UserPlaylist = {
  id: string;
  name: string;
  description?: string;
  coverUrl?: string;
  songCount: number;
  createdAt: string;
  updatedAt: string;
};

type PlaylistContextValue = {
  playlists: UserPlaylist[];
  loading: boolean;
  createPlaylist: (name: string, description?: string) => Promise<UserPlaylist>;
  deletePlaylist: (playlistId: string) => Promise<void>;
  addSongToPlaylist: (playlistId: string, song: MediaItem) => Promise<boolean>;
  removeSongFromPlaylist: (playlistId: string, songId: string) => Promise<void>;
  getPlaylistSongs: (playlistId: string) => Promise<MediaItem[]>;
  activePlaylistModalSong: MediaItem | null;
  openAddToPlaylistModal: (song: MediaItem) => void;
  closeAddToPlaylistModal: () => void;
  refreshPlaylists: () => Promise<void>;
};

const PlaylistContext = createContext<PlaylistContextValue | null>(null);

export function PlaylistProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const userId = user?.id || "guest";
  const [playlists, setPlaylists] = useState<UserPlaylist[]>([]);
  const [loading, setLoading] = useState(true);
  const [activePlaylistModalSong, setActivePlaylistModalSong] = useState<MediaItem | null>(null);

  const localPlaylistsKey = `innerwave-playlists:${userId}`;
  const localItemsPrefix = `innerwave-playlist-items:`;

  const loadLocalPlaylists = useCallback((): UserPlaylist[] => {
    try {
      const raw = localStorage.getItem(localPlaylistsKey);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }, [localPlaylistsKey]);

  const saveLocalPlaylists = useCallback((items: UserPlaylist[]) => {
    try {
      localStorage.setItem(localPlaylistsKey, JSON.stringify(items));
    } catch {
      // ignore storage quota error
    }
  }, [localPlaylistsKey]);

  const refreshPlaylists = useCallback(async () => {
    setLoading(true);
    try {
      if (user?.id) {
        const { data, error } = await supabase
          .from("user_playlists")
          .select("id, name, description, cover_url, created_at, updated_at, user_playlist_items(count)")
          .eq("user_id", user.id)
          .order("updated_at", { ascending: false });

        if (!error && data) {
          const mapped: UserPlaylist[] = data.map((row: any) => ({
            id: row.id,
            name: row.name,
            description: row.description || "",
            coverUrl: row.cover_url || "",
            songCount: row.user_playlist_items?.[0]?.count ?? 0,
            createdAt: row.created_at,
            updatedAt: row.updated_at,
          }));
          setPlaylists(mapped);
          saveLocalPlaylists(mapped);
          return;
        }
      }
      setPlaylists(loadLocalPlaylists());
    } catch {
      setPlaylists(loadLocalPlaylists());
    } finally {
      setLoading(false);
    }
  }, [user?.id, loadLocalPlaylists, saveLocalPlaylists]);

  useEffect(() => {
    refreshPlaylists();
  }, [refreshPlaylists]);

  const createPlaylist = useCallback(async (name: string, description = ""): Promise<UserPlaylist> => {
    const trimmed = name.trim() || "Untitled Playlist";
    const now = new Date().toISOString();
    const tempId = `local-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`;
    let created: UserPlaylist = {
      id: tempId,
      name: trimmed,
      description,
      coverUrl: "",
      songCount: 0,
      createdAt: now,
      updatedAt: now,
    };

    if (user?.id) {
      try {
        const { data, error } = await supabase
          .from("user_playlists")
          .insert({
            user_id: user.id,
            name: trimmed,
            description,
          })
          .select()
          .single();

        if (!error && data) {
          created = {
            id: data.id,
            name: data.name,
            description: data.description || "",
            coverUrl: data.cover_url || "",
            songCount: 0,
            createdAt: data.created_at,
            updatedAt: data.updated_at,
          };
        }
      } catch {
        // fallback to local
      }
    }

    setPlaylists((prev) => {
      const updated = [created, ...prev.filter((p) => p.id !== created.id)];
      saveLocalPlaylists(updated);
      return updated;
    });

    return created;
  }, [user?.id, saveLocalPlaylists]);

  const deletePlaylist = useCallback(async (playlistId: string) => {
    if (user?.id && !playlistId.startsWith("local-")) {
      try {
        await supabase.from("user_playlists").delete().eq("id", playlistId).eq("user_id", user.id);
      } catch {
        // ignore
      }
    }
    localStorage.removeItem(`${localItemsPrefix}${playlistId}`);
    setPlaylists((prev) => {
      const updated = prev.filter((p) => p.id !== playlistId);
      saveLocalPlaylists(updated);
      return updated;
    });
  }, [user?.id, localItemsPrefix, saveLocalPlaylists]);

  const getPlaylistSongs = useCallback(async (playlistId: string): Promise<MediaItem[]> => {
    if (user?.id && !playlistId.startsWith("local-")) {
      try {
        const { data, error } = await supabase
          .from("user_playlist_items")
          .select("song, position")
          .eq("playlist_id", playlistId)
          .order("position", { ascending: true });

        if (!error && data) {
          const songs = data.map((d: any) => d.song as MediaItem);
          localStorage.setItem(`${localItemsPrefix}${playlistId}`, JSON.stringify(songs));
          return songs;
        }
      } catch {
        // ignore
      }
    }

    try {
      const raw = localStorage.getItem(`${localItemsPrefix}${playlistId}`);
      return raw ? JSON.parse(raw) : [];
    } catch {
      return [];
    }
  }, [user?.id, localItemsPrefix]);

  const addSongToPlaylist = useCallback(async (playlistId: string, song: MediaItem): Promise<boolean> => {
    const existing = await getPlaylistSongs(playlistId);
    if (existing.some((item) => item.id === song.id)) {
      return false; // already added
    }

    const nextSongs = [...existing, song];
    localStorage.setItem(`${localItemsPrefix}${playlistId}`, JSON.stringify(nextSongs));

    if (user?.id && !playlistId.startsWith("local-")) {
      try {
        await supabase.from("user_playlist_items").insert({
          playlist_id: playlistId,
          user_id: user.id,
          song,
          position: nextSongs.length - 1,
        });
        await supabase.from("user_playlists").update({
          updated_at: new Date().toISOString(),
          cover_url: song.thumbnail || null,
        }).eq("id", playlistId);
      } catch {
        // saved locally
      }
    }

    setPlaylists((prev) => {
      const updated = prev.map((p) => (p.id === playlistId ? {
        ...p,
        songCount: nextSongs.length,
        coverUrl: p.coverUrl || song.thumbnail || "",
        updatedAt: new Date().toISOString(),
      } : p));
      saveLocalPlaylists(updated);
      return updated;
    });

    return true;
  }, [getPlaylistSongs, localItemsPrefix, user?.id, saveLocalPlaylists]);

  const removeSongFromPlaylist = useCallback(async (playlistId: string, songId: string) => {
    const existing = await getPlaylistSongs(playlistId);
    const nextSongs = existing.filter((item) => item.id !== songId);
    localStorage.setItem(`${localItemsPrefix}${playlistId}`, JSON.stringify(nextSongs));

    if (user?.id && !playlistId.startsWith("local-")) {
      try {
        await supabase
          .from("user_playlist_items")
          .delete()
          .eq("playlist_id", playlistId)
          .contains("song", { id: songId });
      } catch {
        // local updated
      }
    }

    setPlaylists((prev) => {
      const updated = prev.map((p) => (p.id === playlistId ? {
        ...p,
        songCount: nextSongs.length,
        coverUrl: nextSongs[0]?.thumbnail || "",
        updatedAt: new Date().toISOString(),
      } : p));
      saveLocalPlaylists(updated);
      return updated;
    });
  }, [getPlaylistSongs, localItemsPrefix, user?.id, saveLocalPlaylists]);

  const openAddToPlaylistModal = useCallback((song: MediaItem) => {
    setActivePlaylistModalSong(song);
  }, []);

  const closeAddToPlaylistModal = useCallback(() => {
    setActivePlaylistModalSong(null);
  }, []);

  return (
    <PlaylistContext.Provider
      value={{
        playlists,
        loading,
        createPlaylist,
        deletePlaylist,
        addSongToPlaylist,
        removeSongFromPlaylist,
        getPlaylistSongs,
        activePlaylistModalSong,
        openAddToPlaylistModal,
        closeAddToPlaylistModal,
        refreshPlaylists,
      }}
    >
      {children}
    </PlaylistContext.Provider>
  );
}

export function usePlaylist() {
  const context = useContext(PlaylistContext);
  if (!context) {
    throw new Error("usePlaylist must be used within a PlaylistProvider");
  }
  return context;
}
