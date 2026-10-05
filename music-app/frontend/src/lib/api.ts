import type { Feed, MediaItem } from "./types";

export const API_URL = process.env.NEXT_PUBLIC_API_URL || "/backend";

async function getJson<T>(path: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch(`${API_URL}${path}`, { signal, cache: "no-store" });
  if (!response.ok) {
    const payload = await response.json().catch(() => null);
    throw new Error(payload?.detail || `Request failed (${response.status})`);
  }
  return response.json() as Promise<T>;
}

export const musicApi = {
  home: (signal?: AbortSignal) => getJson<Feed>("/api/home", signal),
  search: (query: string, signal?: AbortSignal) =>
    getJson<Feed>(`/api/search?q=${encodeURIComponent(query)}`, signal),
  browse: (id: string, params?: string | null, signal?: AbortSignal) =>
    getJson<Feed>(
      `/api/browse?id=${encodeURIComponent(id)}${params ? `&params=${encodeURIComponent(params)}` : ""}`,
      signal,
    ),
  next: (item: MediaItem, continuation?: string | null) => {
    const query = new URLSearchParams({
      videoId: item.videoId || "",
      title: item.title,
      artist: item.artists.join(", ") || item.subtitle.split(" · ")[0] || "",
    });
    if (continuation) query.set("continuation", continuation);
    if (item.playlistId) query.set("playlistId", item.playlistId);
    if (item.watchParams) query.set("params", item.watchParams);
    if (item.index != null) query.set("index", String(item.index));
    return getJson<{ items: MediaItem[]; continuation?: string | null }>(`/api/next?${query}`);
  },
  lyrics: (item: MediaItem, duration?: number, signal?: AbortSignal) => {
    const artist = item.artists.join(", ") || item.subtitle.split(" · ")[0] || "";
    const query = new URLSearchParams({ videoId: item.videoId || "", title: item.title, artist });
    if (duration && Number.isFinite(duration)) query.set("duration", String(duration));
    return getJson<{ lyrics: string; source?: string | null; lines: { time: number; text: string }[]; synced: boolean; syncSource?: string | null }>(`/api/lyrics?${query}`, signal);
  },
  related: (item: MediaItem, signal?: AbortSignal) => {
    const artist = item.artists.join(", ") || item.subtitle.split(" · ")[0] || "";
    const query = new URLSearchParams({ videoId: item.videoId || "", title: item.title, artist });
    return getJson<Feed>(`/api/related?${query}`, signal);
  },
  moreHome: (page: number, continuation?: string | null, seed?: string) =>
    getJson<Feed>(
      `/api/home/more?page=${page}${continuation ? `&continuation=${encodeURIComponent(continuation)}` : ""}${seed ? `&seed=${encodeURIComponent(seed)}` : ""}`,
    ),
  recommendations: (artists: string[]) =>
    getJson<Feed>(`/api/recommendations?artists=${encodeURIComponent(artists.join(","))}`),
};
